// Copyright (c) The Diem Core Contributors
// Copyright (c) The Move Contributors
// SPDX-License-Identifier: Apache-2.0

use crate::{
    module_traversal::TraversalContext, storage::{
        module_storage::FunctionValueExtensionAdapter,
        ty_layout_converter::{LayoutConverter, StorageLayoutConverter},
    }, ModuleStorage, RuntimeEnvironment
};
use bytes::Bytes;
use move_binary_format::errors::*;
use move_core_types::{
    account_address::AccountAddress, effects::{AccountChanges, ChangeSet, Changes}, gas_algebra::NumBytes, language_storage::{StructTag, TypeTag}, metadata::Metadata, value::MoveTypeLayout, vm_status::StatusCode
};
use move_vm_types::{
    gas::GasMeter, loaded_data::runtime_types::Type, resolver::ResourceResolver, value_serde::{FunctionValueExtension, ValueSerDeContext}, values::{GlobalValue, Value}, views::TypeView
};
use std::collections::btree_map::{BTreeMap, Entry, OccupiedEntry};

struct TypeWithRuntimeEnvironment<'a, 'b> {
    ty: &'a Type,
    runtime_environment: &'b RuntimeEnvironment,
}

impl TypeView for TypeWithRuntimeEnvironment<'_, '_> {
    fn to_type_tag(&self) -> TypeTag {
        self.runtime_environment.ty_to_ty_tag(self.ty).unwrap()
    }
}

pub(crate) enum CachedInformation {
    Value(GlobalValue),
    /// If resource exists then store its size, None otherwise
    SizeOnly(Option<u64>),
}

impl CachedInformation {
    fn value_mut(&mut self) -> PartialVMResult<&mut GlobalValue> {
        match self {
            CachedInformation::Value(v) => Ok(v),
            CachedInformation::SizeOnly(_) => Err(PartialVMError::new_invariant_violation(
                "Data is not cached",
            )),
        }
    }

    pub(crate) fn exists(&self) -> PartialVMResult<bool> {
        match &self {
            CachedInformation::SizeOnly(e) => Ok(e.is_some()),
            CachedInformation::Value(v) => v.exists(),
        }
    }

    pub(crate) fn maybe_value(&self) -> Option<&GlobalValue> {
        match &self {
            CachedInformation::SizeOnly(_) => None,
            CachedInformation::Value(v) => Some(v),
        }
    }
}

/// An entry in the data cache, containing resource's [GlobalValue] as well as additional cached
/// information such as tag, layout, and a flag whether there are any delayed fields inside the
/// resource.
struct DataCacheEntry {
    struct_tag: StructTag,
    layout: MoveTypeLayout,
    contains_delayed_fields: bool,
    value: CachedInformation,
}

/// Transaction data cache. Keep updates within a transaction so they can all be published at
/// once when the transaction succeeds.
///
/// It also provides an implementation for the opcodes that refer to storage and gives the
/// proper guarantees of reference lifetime.
///
/// Dirty objects are serialized and returned in make_write_set.
///
/// It is a responsibility of the client to publish changes once the transaction is executed.
///
/// The Move VM takes a `DataStore` in input and this is the default and correct implementation
/// for a data store related to a transaction. Clients should create an instance of this type
/// and pass it to the Move VM.
pub struct TransactionDataCache {
    account_map: BTreeMap<AccountAddress, BTreeMap<Type, DataCacheEntry>>,
}

impl TransactionDataCache {
    /// Create a `TransactionDataCache` with a `RemoteCache` that provides access to data
    /// not updated in the transaction.
    pub fn empty() -> Self {
        TransactionDataCache {
            account_map: BTreeMap::new(),
        }
    }

    /// Make a write set from the updated (dirty, deleted) global resources along with
    /// published modules.
    ///
    /// Gives all proper guarantees on lifetime of global data as well.
    pub fn into_effects(self, module_storage: &dyn ModuleStorage) -> PartialVMResult<ChangeSet> {
        let resource_converter =
            |value: Value, layout: MoveTypeLayout, _: bool| -> PartialVMResult<Bytes> {
                let function_value_extension = FunctionValueExtensionAdapter { module_storage };
                let max_value_nest_depth = function_value_extension.max_value_nest_depth();
                ValueSerDeContext::new(max_value_nest_depth)
                    .with_func_args_deserialization(&function_value_extension)
                    .serialize(&value, &layout)?
                    .map(Into::into)
                    .ok_or_else(|| {
                        PartialVMError::new(StatusCode::INTERNAL_TYPE_ERROR)
                            .with_message(format!("Error when serializing resource {}.", value))
                    })
            };
        self.into_custom_effects(&resource_converter)
    }

    /// Same like `into_effects`, but also allows clients to select the format of
    /// produced effects for resources.
    pub fn into_custom_effects<Resource>(
        self,
        resource_converter: &dyn Fn(Value, MoveTypeLayout, bool) -> PartialVMResult<Resource>,
    ) -> PartialVMResult<Changes<Resource>> {
        let mut change_set = Changes::<Resource>::new();
        for (addr, account_data_cache) in self.account_map.into_iter() {
            let mut resources = BTreeMap::new();
            for entry in account_data_cache.into_values() {
                let DataCacheEntry {
                    struct_tag,
                    layout,
                    contains_delayed_fields,
                    value: cached_info,
                } = entry;
                if let CachedInformation::Value(value) = cached_info {
                    if let Some(op) = value.into_effect_with_layout(layout) {
                        resources.insert(
                            struct_tag,
                            op.and_then(|(value, layout)| {
                                resource_converter(value, layout, contains_delayed_fields)
                            })?,
                        );
                    }
                }
            }
            if !resources.is_empty() {
                change_set
                    .add_account_changeset(addr, AccountChanges::from_resources(resources))
                    .expect("accounts should be unique");
            }
        }

        Ok(change_set)
    }

    // fn upgrade_cache_entry(
    //     &mut self,
    //     module_storage: &dyn ModuleStorage,
    //     resource_resolver: &dyn ResourceResolver,
    //     maybe_gas_meter: Option<&mut impl GasMeter>,
    //     _traversal_context: &mut TraversalContext,
    //     addr: &AccountAddress,
    //     ty: &Type,
    //     load_data: bool,
    //     cache_entry: &mut OccupiedEntry<'_, Type, DataCacheEntry>
    // ) -> PartialVMResult<()> {
    // }

    fn create_cached_info(
        load_data: bool,
        resource_resolver: &dyn ResourceResolver,
        module_storage: &dyn ModuleStorage,
        struct_tag: &StructTag,
        addr: &AccountAddress,
        layout: &MoveTypeLayout,
        contains_delayed_fields: bool,
    ) -> PartialVMResult<(CachedInformation, usize)> {
        let metadata = module_storage
            .fetch_existing_module_metadata(&struct_tag.address, struct_tag.module.as_ident_str())
            .map_err(|err| err.to_partial())?;

        Ok(if load_data {
            let (data, bytes_loaded) = {
                // If we need to process delayed fields, we pass type layout to remote storage. Remote
                // storage, in turn ensures that all delayed field values are pre-processed.
                resource_resolver.get_resource_bytes_with_metadata_and_layout(
                    addr,
                    &struct_tag,
                    &metadata,
                    if contains_delayed_fields {
                        Some(&layout)
                    } else {
                        None
                    },
                )?
            };
            let function_value_extension = FunctionValueExtensionAdapter { module_storage };
            let value = match data {
                Some(blob) => {
                    let max_value_nest_depth = function_value_extension.max_value_nest_depth();
                    let val = ValueSerDeContext::new(max_value_nest_depth)
                        .with_func_args_deserialization(&function_value_extension)
                        .with_delayed_fields_serde()
                        .deserialize(&blob, &layout)
                        .ok_or_else(|| {
                            let msg = format!(
                                "Failed to deserialize resource {} at {}!",
                                struct_tag.to_canonical_string(),
                                addr
                            );
                            PartialVMError::new(StatusCode::FAILED_TO_DESERIALIZE_RESOURCE)
                                .with_message(msg)
                        })?;
                    GlobalValue::cached(val)?
                },
                None => GlobalValue::none(),
            };
            (CachedInformation::Value(value), bytes_loaded)
        } else {
            let (size, bytes_loaded) = resource_resolver.get_resource_size_with_metadata_and_layout(
                addr,
                &struct_tag,
                &metadata,
                if contains_delayed_fields {
                    Some(&layout)
                } else {
                    None
                },
            )?;
            (CachedInformation::SizeOnly(size), bytes_loaded)
        })
    }

    /// Retrieves data from the remote on-chain storage and converts it into a [DataCacheEntry].
    /// Also returns the size of the loaded resource in bytes. This method does not add the entry
    /// to the cache - it is the caller's responsibility to add it there.
    /// If `load_data` is false, only resource existence information will be retrieved
    ///
    /// Possible cases:
    /// 1. User called exists, nothing is cached - fetch size, charge for size
    /// 2. User called exists, SizeOnly is cached - do nothing, no charge
    /// 3. User called exists, Value is cached - do nothing, no charge
    /// 4. User called borrow, nothing is cached - fetch bytes, charge for size and bytes
    /// 5. User called borrow, SizeOnly is cached - fetch bytes, charge for bytes
    /// 6. User called borrow, Value is cached - do nothing, no charge
    pub(crate) fn create_and_insert_or_upgrade_and_charge_data_cache_entry(
        &mut self,
        module_storage: &dyn ModuleStorage,
        resource_resolver: &dyn ResourceResolver,
        maybe_gas_meter: Option<&mut impl GasMeter>,
        _traversal_context: &mut TraversalContext,
        addr: &AccountAddress,
        ty: &Type,
        load_data: bool,
    ) -> PartialVMResult<(&CachedInformation, NumBytes)> {
        let existing_entry = self.account_map.entry(addr.clone()).or_default().entry(ty.clone());

        let (entry, bytes_loaded) = match existing_entry {
            Entry::Vacant(vacant_entry) => {
                // Nothing is cached: charge for size and potentially bytes
                let struct_tag = match module_storage.runtime_environment().ty_to_ty_tag(ty)? {
                    TypeTag::Struct(struct_tag) => *struct_tag,
                    _ => {
                        // Since every resource is a struct, the tag must be also a struct tag.
                        return Err(PartialVMError::new(StatusCode::INTERNAL_TYPE_ERROR));
                    },
                };

                // TODO(Gas): Shall we charge for this?
                let (layout, contains_delayed_fields) = StorageLayoutConverter::new(module_storage)
                    .type_to_type_layout_with_identifier_mappings(ty)?;

                let (cached_info, bytes_loaded) = TransactionDataCache::create_cached_info(
                    load_data,
                    resource_resolver,
                    module_storage,
                    &struct_tag,
                    addr,
                    &layout,
                    contains_delayed_fields,
                )?;

                let num_bytes_loaded = NumBytes::new(bytes_loaded as u64);
                if let Some(gas_meter) = maybe_gas_meter {
                    gas_meter.charge_load_resource(
                        addr.clone(),
                        TypeWithRuntimeEnvironment {
                            ty,
                            runtime_environment: module_storage.runtime_environment(),
                        },
                        match cached_info.maybe_value() {
                            None => None,
                            Some(v) => v.view(),
                        },
                        num_bytes_loaded,
                    )?;
                }

                let new_entry = DataCacheEntry {
                    struct_tag,
                    layout,
                    contains_delayed_fields,
                    value: cached_info,
                };

                (vacant_entry.insert(new_entry), num_bytes_loaded)
            },
            Entry::Occupied(mut occupied_entry) => {
                // If entry already exists we might only need to upgrade it from SizeOnly to Value and charge for bytes
                let num_bytes_loaded = NumBytes::zero();
                if load_data && !matches!(occupied_entry.get().value, CachedInformation::Value(_)) {
                    let (cached_info, _) = TransactionDataCache::create_cached_info(
                        load_data,
                        resource_resolver,
                        module_storage,
                        &occupied_entry.get().struct_tag,
                        addr,
                        &occupied_entry.get().layout,
                        occupied_entry.get().contains_delayed_fields,
                    )?;

                    if let Some(gas_meter) = maybe_gas_meter {
                        gas_meter.charge_load_resource(
                            addr.clone(),
                            TypeWithRuntimeEnvironment {
                                ty,
                                runtime_environment: module_storage.runtime_environment(),
                            },
                            match cached_info.maybe_value() {
                                None => None,
                                Some(v) => v.view(),
                            },
                            num_bytes_loaded,
                        )?;
                    }

                    occupied_entry.get_mut().value = cached_info;
                }

                (occupied_entry.into_mut(), num_bytes_loaded)
            },
        };

        Ok((&entry.value, bytes_loaded))
    }

    fn find_entry(&self, addr: &AccountAddress, ty: &Type) -> Option<&DataCacheEntry> {
        if let Some(account_cache) = self.account_map.get(addr) {
            account_cache.get(ty)
        } else {
            None
        }
    }

    fn find_entry_mut(&mut self, addr: &AccountAddress, ty: &Type) -> Option<&mut DataCacheEntry> {
        if let Some(account_cache) = self.account_map.get_mut(addr) {
            account_cache.get_mut(ty)
        } else {
            None
        }
    }

    /// Returns true if resource is present in the cache and thus we know if it exists.
    /// The state of the cache does not change when calling this function.
    pub(crate) fn contains_resource_existence(&self, addr: &AccountAddress, ty: &Type) -> bool {
        self.find_entry(addr, ty).is_some()
    }

    /// Returns true if resource is present in the cache and we know its whole value, not just the size.
    pub(crate) fn contains_resource_data(&self, addr: &AccountAddress, ty: &Type) -> bool {
        match self.find_entry(addr, ty) {
            None => false,
            Some(entry) => matches!(entry.value, CachedInformation::Value(_)),
        }
    }

    /// Stores a new entry for loaded resource into the data cache. Returns an error if there is an
    /// entry already for the specified address-type pair.
    fn insert_resource(
        &mut self,
        addr: AccountAddress,
        ty: Type,
        data_cache_entry: DataCacheEntry,
    ) -> PartialVMResult<&mut DataCacheEntry> {
        match self.account_map.entry(addr).or_default().entry(ty.clone()) {
            Entry::Vacant(entry) => {
                let v = entry.insert(data_cache_entry);
                Ok(v)
            },
            Entry::Occupied(mut entry) => {
                if matches!(entry.get().value, CachedInformation::SizeOnly(_))
                    && matches!(data_cache_entry.value, CachedInformation::Value(_))
                {
                    entry.insert(data_cache_entry);
                    let v = entry.into_mut();
                    Ok(v)
                } else {
                    let msg = format!("Entry for {:?} at {} already exists", ty, addr);
                    let err = PartialVMError::new(StatusCode::UNKNOWN_INVARIANT_VIOLATION_ERROR)
                        .with_message(msg);
                    Err(err)
                }
            },
        }
    }

    /// Returns the resource from the data cache. If resource has not been inserted (i.e., it does
    /// not exist in cache), an error is returned.
    pub(crate) fn get_resource_mut(
        &mut self,
        addr: &AccountAddress,
        ty: &Type,
    ) -> PartialVMResult<&mut GlobalValue> {
        if let Some(entry) = self.find_entry_mut(addr, ty) {
            return entry.value.value_mut();
        }

        let msg = format!("Resource for {:?} at {} must exist", ty, addr);
        let err =
            PartialVMError::new(StatusCode::UNKNOWN_INVARIANT_VIOLATION_ERROR).with_message(msg);
        Err(err)
    }

    pub(crate) fn get_resource_existence(
        &mut self,
        addr: &AccountAddress,
        ty: &Type,
    ) -> PartialVMResult<bool> {
        if let Some(entry) = self.find_entry_mut(addr, ty) {
            return entry.value.exists();
        }

        let msg = format!("Resource for {:?} at {} must exist", ty, addr);
        let err = PartialVMError::new_invariant_violation(msg);
        Err(err)
    }
}
