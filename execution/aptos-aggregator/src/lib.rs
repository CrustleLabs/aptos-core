// Copyright © Aptos Foundation
// SPDX-License-Identifier: Apache-2.0

//! Minimal aggregator stub - Move VM functionality removed

#![forbid(unsafe_code)]

// Minimal stub implementation
pub struct Aggregator;

impl Aggregator {
    pub fn new() -> Self {
        Self
    }
}

impl Default for Aggregator {
    fn default() -> Self {
        Self::new()
    }
}
