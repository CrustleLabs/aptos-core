// Copyright © Aptos Foundation
// SPDX-License-Identifier: Apache-2.0

//! Proof types stub

use serde::{Deserialize, Serialize};
use aptos_crypto::HashValue;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SparseMerkleInternalNode;

impl SparseMerkleInternalNode {
    pub fn new(_left: HashValue, _right: HashValue) -> Self {
        Self
    }
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
pub struct SparseMerkleLeafNode {
    key: HashValue,
    value_hash: HashValue,
}

impl SparseMerkleLeafNode {
    pub fn key(&self) -> &HashValue {
        &self.key
    }
    
    pub fn value_hash(&self) -> &HashValue {
        &self.value_hash
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SparseMerkleProofExt {
    leaf: Option<SparseMerkleLeafNode>,
    siblings: Vec<HashValue>,
}

impl SparseMerkleProofExt {
    pub fn new(leaf: Option<SparseMerkleLeafNode>, siblings: Vec<HashValue>) -> Self {
        Self { leaf, siblings }
    }
    
    pub fn root_depth(&self) -> usize {
        self.siblings.len()
    }
    
    pub fn bottom_depth(&self) -> usize {
        self.siblings.len()
    }
    
    pub fn leaf(&self) -> Option<&SparseMerkleLeafNode> {
        self.leaf.as_ref()
    }
    
    pub fn sibling_at_depth(&self, depth: usize) -> Option<HashValue> {
        self.siblings.get(depth).copied()
    }
}

pub mod definition {
    use serde::{Deserialize, Serialize};
    use aptos_crypto::HashValue;
    
    #[derive(Clone, Debug, Serialize, Deserialize)]
    pub enum NodeInProof {
        Leaf(super::SparseMerkleLeafNode),
        Other(HashValue),
    }
    
    impl NodeInProof {
        pub fn hash(&self) -> HashValue {
            match self {
                NodeInProof::Leaf(_) => HashValue::zero(),
                NodeInProof::Other(hash) => *hash,
            }
        }
    }
}
