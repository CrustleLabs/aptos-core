// Copyright © Aptos Foundation
// SPDX-License-Identifier: Apache-2.0

//! Aggregate signature stub

use crate::account_address::AccountAddress;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AggregateSignature {
    validator_to_signature_map: Vec<(AccountAddress, Vec<u8>)>,
}

impl AggregateSignature {
    pub fn new(validator_to_signature_map: Vec<(AccountAddress, Vec<u8>)>) -> Self {
        Self {
            validator_to_signature_map,
        }
    }

    pub fn empty() -> Self {
        Self {
            validator_to_signature_map: Vec::new(),
        }
    }
}
