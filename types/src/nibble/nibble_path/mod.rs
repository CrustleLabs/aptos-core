// Copyright © Aptos Foundation
// SPDX-License-Identifier: Apache-2.0

//! Nibble path types stub

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct NibblePath {
    bytes: Vec<u8>,
}

impl NibblePath {
    pub fn new_even(bytes: Vec<u8>) -> Self {
        Self { bytes }
    }
    
    pub fn bit(&self, _depth: usize) -> bool {
        false // Stub implementation
    }
}

