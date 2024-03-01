// Copyright © Aptos Foundation
// SPDX-License-Identifier: Apache-2.0

use crate::dag::{DAGMessage, DAGRpcResult};
use aptos_reliable_broadcast::ReliableBroadcast;
use async_trait::async_trait;
use futures_channel::oneshot;
use std::sync::Arc;
use tokio::sync::mpsc::Receiver;
use tokio_retry::strategy::ExponentialBackoff;
use crate::dag::shoal_plus_plus::shoalpp_types::{BoltBCParms, BoltBCRet};

#[async_trait]
pub trait BroadcastSync {
    async fn run(self);
}

pub struct BroadcastNoSync {
    reliable_broadcast: Arc<ReliableBroadcast<DAGMessage, ExponentialBackoff, DAGRpcResult>>,
    receivers: Vec<Receiver<(oneshot::Sender<BoltBCRet>, BoltBCParms)>>,
}

impl BroadcastNoSync {
    pub fn new(reliable_broadcast: Arc<ReliableBroadcast<DAGMessage, ExponentialBackoff, DAGRpcResult>>, receivers: Vec<Receiver<(oneshot::Sender<BoltBCRet>, BoltBCParms)>>,) -> Self {
        Self { reliable_broadcast, receivers }
    }
}

#[async_trait]
impl BroadcastSync for BroadcastNoSync {
    async fn run(mut self) {
        assert_eq!(self.receivers.len(), 1);

        // TODO: shutdown mechanism
        loop {
            let (ret_tx1, bolt_bc_parms) = self.receivers[0].recv().await.unwrap();
            if let Err(_e) = ret_tx1.send(bolt_bc_parms.broadcast(self.reliable_broadcast.clone()))
            {
                // TODO: should we panic here?
            }
        }
    }
}

// TODO: handle the Bolt disabled case

pub struct BoltBroadcastSync {
    reliable_broadcast: Arc<ReliableBroadcast<DAGMessage, ExponentialBackoff, DAGRpcResult>>,
    receivers: Vec<Receiver<(oneshot::Sender<BoltBCRet>, BoltBCParms)>>,
}

impl BoltBroadcastSync {
    pub fn new(reliable_broadcast: Arc<ReliableBroadcast<DAGMessage, ExponentialBackoff, DAGRpcResult>>,  receivers: Vec<Receiver<(oneshot::Sender<BoltBCRet>, BoltBCParms)>>,) -> Self {
        Self { reliable_broadcast, receivers, }
    }
}

#[async_trait]
impl BroadcastSync for BoltBroadcastSync {
    async fn run(mut self) {
        assert_eq!(self.receivers.len(), 3);
        // TODO: think about synchronization after state sync.

        for i in 0..=1 {
            // TODO: think about the unwrap()
            let (ret_tx, bolt_bc_parms) = self.receivers[i].recv().await.unwrap();
            if let Err(_e) = ret_tx.send(bolt_bc_parms.broadcast(self.reliable_broadcast.clone())) {
                // TODO: should we panic here?
            }
        }

        // TODO: shutdown mechanism

        let mut inx = 2;
        loop {
            let (ret_tx1, bolt_bc_parms1) = self.receivers[inx].recv().await.unwrap();
            let (ret_tx2, bolt_bc_parms2) = self.receivers[(inx + 1) % 3].recv().await.unwrap();

            let ret1 = bolt_bc_parms1.broadcast(self.reliable_broadcast.clone());
            let ret2 = bolt_bc_parms2.broadcast(self.reliable_broadcast.clone());

            if let Err(_e) = ret_tx1.send(ret1) {
                // TODO: should we panic here?
            }
            if let Err(_e) = ret_tx2.send(ret2) {
                // TODO: should we panic here?
            }

            inx = (inx + 1) % 3;
        }
    }
}