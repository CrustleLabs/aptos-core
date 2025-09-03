// Copyright © Aptos Foundation
// SPDX-License-Identifier: Apache-2.0

//! Minimal block executor stub - Move VM functionality removed

#![forbid(unsafe_code)]

// Minimal stub implementation
pub struct BlockExecutor;

impl BlockExecutor {
    pub fn new() -> Self {
        Self
    }
}

impl Default for BlockExecutor {
    fn default() -> Self {
        Self::new()
    }
}

// Re-export commonly used types for compatibility
pub use aptos_types::*;
