// Copyright © Aptos Foundation
// SPDX-License-Identifier: Apache-2.0

//! Account address implementation

use serde::{Deserialize, Serialize};
use std::fmt;

/// A struct that represents an account address.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd, Serialize, Deserialize)]
pub struct AccountAddress([u8; AccountAddress::LENGTH]);

impl AccountAddress {
    /// The number of bytes in an address.
    pub const LENGTH: usize = 32;

    /// Create a new account address from a byte array.
    pub fn new(address: [u8; Self::LENGTH]) -> Self {
        Self(address)
    }

    /// Create from bytes slice
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, &'static str> {
        if bytes.len() != Self::LENGTH {
            return Err("Invalid length");
        }
        let mut addr = [0u8; Self::LENGTH];
        addr.copy_from_slice(bytes);
        Ok(Self(addr))
    }

    /// Return the byte representation of the account address.
    pub fn as_bytes(&self) -> &[u8; Self::LENGTH] {
        &self.0
    }

    /// Return a zero address.
    pub fn zero() -> Self {
        Self([0u8; Self::LENGTH])
    }

    /// Generate a random address (for testing)
    #[cfg(any(test, feature = "fuzzing"))]
    pub fn random() -> Self {
        use rand::Rng;
        let mut rng = rand::thread_rng();
        let mut bytes = [0u8; Self::LENGTH];
        rng.fill(&mut bytes);
        Self(bytes)
    }
}

#[cfg(any(test, feature = "fuzzing"))]
impl proptest::arbitrary::Arbitrary for AccountAddress {
    type Parameters = ();
    type Strategy = proptest::strategy::BoxedStrategy<Self>;

    fn arbitrary_with(_args: Self::Parameters) -> Self::Strategy {
        use proptest::prelude::*;
        any::<[u8; Self::LENGTH]>()
            .prop_map(|bytes| Self(bytes))
            .boxed()
    }
}

impl fmt::Display for AccountAddress {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "0x{}", hex::encode(self.0))
    }
}

impl From<[u8; AccountAddress::LENGTH]> for AccountAddress {
    fn from(bytes: [u8; AccountAddress::LENGTH]) -> Self {
        Self::new(bytes)
    }
}

impl TryFrom<&[u8]> for AccountAddress {
    type Error = anyhow::Error;

    fn try_from(bytes: &[u8]) -> Result<Self, Self::Error> {
        if bytes.len() != Self::LENGTH {
            return Err(anyhow::anyhow!("Invalid address length: expected {}, got {}", Self::LENGTH, bytes.len()));
        }
        let mut addr = [0u8; Self::LENGTH];
        addr.copy_from_slice(bytes);
        Ok(Self(addr))
    }
}
