// Copyright © Aptos Foundation
// SPDX-License-Identifier: Apache-2.0

//! Minimal MVHashMap stub - Move VM functionality removed

#![forbid(unsafe_code)]

use std::collections::HashMap;

// Minimal stub implementation
pub struct MVHashMap<K, V> {
    inner: HashMap<K, V>,
}

impl<K, V> MVHashMap<K, V> {
    pub fn new() -> Self {
        Self {
            inner: HashMap::new(),
        }
    }
}

impl<K, V> Default for MVHashMap<K, V> {
    fn default() -> Self {
        Self::new()
    }
}
