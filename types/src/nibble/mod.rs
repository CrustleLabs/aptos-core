// Copyright © Aptos Foundation
// SPDX-License-Identifier: Apache-2.0

//! Nibble types stub

pub mod nibble_path;

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Nibble(u8);

impl Nibble {
    pub fn new(value: u8) -> Self {
        Self(value & 0xf)
    }
}

