// Minimal ValidatorSet stub
use crate::account_address::AccountAddress;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ValidatorSet {
    validators: Vec<AccountAddress>,
}

impl ValidatorSet {
    pub fn empty() -> Self {
        Self { validators: Vec::new() }
    }
    
    pub fn new(validators: Vec<AccountAddress>) -> Self {
        Self { validators }
    }
}
