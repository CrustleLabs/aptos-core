// Copyright © Aptos Foundation
// SPDX-License-Identifier: Apache-2.0

//! Transaction types for Aptos without Move VM

use crate::account_address::AccountAddress;
use serde::{Deserialize, Serialize};

pub type Version = u64;

// Transaction payload types with proper enum variants
#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum TransactionPayload {
    EntryFunction(EntryFunction),
    Script(Script),
    Multisig(MultisigTransactionPayload),
    ModuleBundle(Vec<u8>), // Simplified module bundle
    Payload(TransactionPayloadInner),
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum TransactionPayloadInner {
    V1 { 
        executable: TransactionExecutableRef,
        extra_config: TransactionExtraConfig,
    },
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum TransactionExecutableRef {
    EntryFunction(EntryFunction),
    Script(Script),
    Empty,
}

impl TransactionExecutableRef {
    pub fn as_ref(&self) -> &Self {
        self
    }
}

// Main transaction type with necessary methods
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SignedTransaction {
    pub sender: AccountAddress,
    pub payload: TransactionPayload,
    pub authenticator: TransactionAuthenticator,
}

impl SignedTransaction {
    pub fn payload(&self) -> &TransactionPayload {
        &self.payload
    }
    
    pub fn sender(&self) -> AccountAddress {
        self.sender
    }
    
    pub fn authenticator_ref(&self) -> &TransactionAuthenticator {
        &self.authenticator
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct EntryFunction {
    pub module: String,
    pub function: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Script {
    pub code: Vec<u8>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum MultisigTransactionPayload {
    EntryFunction(EntryFunction),
}

impl MultisigTransactionPayload {
    pub fn multisig_address(&self) -> AccountAddress {
        AccountAddress::zero() // Stub implementation
    }
    
    pub fn transaction_payload(&self) -> &TransactionPayload {
        // Stub - return a static reference
        static PAYLOAD: TransactionPayload = TransactionPayload::EntryFunction(EntryFunction { module: String::new(), function: String::new() });
        &PAYLOAD
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum TransactionExtraConfig {
    V1 { gas_unit_price: u64 },
}

// Authenticator module with proper enum variants
pub mod authenticator {
    use crate::account_address::AccountAddress;
    use serde::{Deserialize, Serialize};
    
    #[derive(Clone, Debug, Serialize, Deserialize)]
    pub struct AccountAuthenticator;
    
    #[derive(Clone, Debug, Serialize, Deserialize)]
    pub enum AnyPublicKey {
        Ed25519 { public_key: Vec<u8> },
        Secp256k1 { public_key: Vec<u8> },
        Keyless { public_key: Vec<u8> },
        FederatedKeyless { public_key: Vec<u8> },
    }
    
    impl AnyPublicKey {
        pub fn public_keys(&self) -> Vec<AnyPublicKey> {
            vec![self.clone()]
        }
    }
    
    #[derive(Clone, Debug, Serialize, Deserialize)]
    pub enum TransactionAuthenticator {
        Ed25519 { 
            public_key: AnyPublicKey,
            signature: Vec<u8>,
        },
        MultiEd25519 { 
            public_key: AnyPublicKey,
            signature: Vec<u8>,
        },
        MultiAgent {
            sender: AccountAuthenticator,
            secondary_signers: Vec<AccountAuthenticator>,
            secondary_signer_addresses: Vec<AccountAddress>,
        },
        FeePayer {
            sender: AccountAuthenticator,
            secondary_signers: Vec<AccountAuthenticator>,
            fee_payer_signer: AccountAuthenticator,
            secondary_signer_addresses: Vec<AccountAddress>,
            fee_payer_address: AccountAddress,
        },
        SingleSender { 
            sender: AccountAuthenticator,
        },
        SingleKey { 
            authenticator: AccountAuthenticator,
        },
    }
}

pub use authenticator::TransactionAuthenticator;