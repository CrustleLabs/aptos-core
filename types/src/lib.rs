// Copyright © Aptos Foundation
// SPDX-License-Identifier: Apache-2.0

#![forbid(unsafe_code)]

// Minimal types for CLI compilation without Move VM
pub mod account_address;
pub mod aggregate_signature;
pub mod chain_id;
pub mod mempool_status;
pub mod network_address;
pub mod nibble;
pub mod proof;
pub mod state_store;
pub mod validator_set;
pub mod validator_signer;
pub mod transaction; // Minimal transaction module

// Re-exports
pub use account_address::AccountAddress as PeerId;