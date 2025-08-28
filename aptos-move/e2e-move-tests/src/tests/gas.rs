// Copyright © Aptos Foundation
// SPDX-License-Identifier: Apache-2.0

use crate::{
    tests::{
        common::test_dir_path,
        token_objects::{
            create_mint_hero_payload, create_set_hero_description_payload,
            publish_object_token_example,
        },
    },
    MoveHarness,
};
use aptos_cached_packages::{aptos_stdlib, aptos_token_sdk_builder};
use aptos_crypto::{bls12381, PrivateKey, Uniform};
use aptos_gas_algebra::GasQuantity;
use aptos_gas_profiling::TransactionGasLog;
use aptos_language_e2e_tests::account::Account;
use aptos_transaction_generator_lib::{
    entry_point_trait::{EntryPointTrait, MultiSigConfig},
    publishing::publish_util::PackageHandler,
};
use aptos_transaction_workloads_lib::{EntryPoints, LoopType};
use aptos_types::{
    account_address::{default_stake_pool_address, AccountAddress},
    account_config::CORE_CODE_ADDRESS,
    chain_id::ChainId,
    fee_statement::FeeStatement,
    transaction::{EntryFunction, TransactionPayload},
};
use move_core_types::{identifier::Identifier, language_storage::ModuleId, value::MoveValue};
use rand::{rngs::StdRng, SeedableRng};
use sha3::{Digest, Sha3_512};
use std::path::Path;

#[test]
fn test_modify_gas_schedule_check_hash() {
    let mut harness = MoveHarness::new();

    let mut gas_schedule = harness.get_gas_schedule();
    let old_hash = Sha3_512::digest(&bcs::to_bytes(&gas_schedule).unwrap()).to_vec();

    const MAGIC: u64 = 42424242;

    let (_, val) = gas_schedule
        .entries
        .iter_mut()
        .find(|(name, _)| name == "instr.nop")
        .unwrap();
    assert_ne!(*val, MAGIC);
    *val = MAGIC;

    harness.executor.exec(
        "gas_schedule",
        "set_for_next_epoch_check_hash",
        vec![],
        vec![
            MoveValue::Signer(CORE_CODE_ADDRESS)
                .simple_serialize()
                .unwrap(),
            bcs::to_bytes(&old_hash).unwrap(),
            bcs::to_bytes(&bcs::to_bytes(&gas_schedule).unwrap()).unwrap(),
        ],
    );

    harness
        .executor
        .exec("reconfiguration_with_dkg", "finish", vec![], vec![
            MoveValue::Signer(CORE_CODE_ADDRESS)
                .simple_serialize()
                .unwrap(),
        ]);

    let (_, gas_params) = harness.get_gas_params();
    assert_eq!(gas_params.vm.instr.nop, MAGIC.into());
}
