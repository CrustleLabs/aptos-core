// Copyright © Aptos Foundation
// SPDX-License-Identifier: Apache-2.0

//! Network address types stub

use serde::{Deserialize, Serialize};
use std::net::SocketAddr;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct NetworkAddress {
    address: String,
}

impl NetworkAddress {
    pub fn new(address: String) -> Self {
        Self { address }
    }
    
    pub fn as_str(&self) -> &str {
        &self.address
    }
    
    pub fn from_protocols(protocols: Vec<Protocol>) -> Result<Self, String> {
        // Stub implementation
        Ok(Self {
            address: "127.0.0.1:8080".to_string(),
        })
    }
    
    pub fn push(mut self, protocol: Protocol) -> Self {
        // Stub implementation - just return self
        self
    }
    
    pub fn ip(&self) -> std::net::IpAddr {
        // Stub implementation
        std::net::IpAddr::V4(std::net::Ipv4Addr::new(127, 0, 0, 1))
    }
    
    pub fn port(&self) -> u16 {
        8080 // Stub implementation
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum Protocol {
    Tcp(u16),
    Memory(u16),
    Ip4([u8; 4]),
    Ip6([u8; 16]),
    Dns(String),
    Dns4(String),
    Dns6(String),
}

impl From<SocketAddr> for NetworkAddress {
    fn from(addr: SocketAddr) -> Self {
        Self {
            address: addr.to_string(),
        }
    }
}

impl std::fmt::Display for NetworkAddress {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.address)
    }
}
