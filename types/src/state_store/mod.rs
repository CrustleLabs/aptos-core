// Copyright © Aptos Foundation
// SPDX-License-Identifier: Apache-2.0

//! State store types stub

pub mod state_value {
    use serde::{Deserialize, Serialize};
    
    #[derive(Clone, Debug, Serialize, Deserialize)]
    pub struct StateValue {
        pub bytes: Vec<u8>,
    }
    
    // Simplified without CryptoHash implementation to avoid private method issues
}

pub mod state_key {
    use serde::{Deserialize, Serialize};
    
    #[derive(Clone, Debug, Serialize, Deserialize)]
    pub struct StateKey {
        pub bytes: Vec<u8>,
    }
}
