// Copyright © Aptos Foundation
// SPDX-License-Identifier: Apache-2.0



use std::ops::Deref;
use std::sync::Arc;

use arc_swap::ArcSwapOption;
use futures_channel::mpsc::UnboundedSender;

use aptos_bitvec::BitVec;
use aptos_consensus_types::block::Block;
use aptos_consensus_types::common::{Payload};
use aptos_consensus_types::pipelined_block::PipelinedBlock;
// use aptos_consensus_types::executed_block::ExecutedBlock;
use aptos_crypto::HashValue;
use aptos_executor_types::StateComputeResult;
use aptos_infallible::RwLock;
use aptos_logger::{error};
use aptos_types::aggregate_signature::AggregateSignature;
use aptos_types::block_info::{BlockInfo};
use aptos_types::epoch_state::EpochState;
use aptos_types::ledger_info::{LedgerInfo, LedgerInfoWithSignatures};

use crate::counters::update_counters_for_committed_blocks;
use crate::dag::adapter::{ShoalppOrderBlocksInfo, LedgerInfoProvider};
use crate::dag::dag_store::{DagStore};
use crate::pipeline::buffer_manager::OrderedBlocks;



pub struct ShoalppOrderNotifier {
    dag_store_vec: Vec<Arc<ArcSwapOption<DagStore>>>,
    ordered_nodes_tx: UnboundedSender<OrderedBlocks>,
    receivers: Vec<tokio::sync::mpsc::UnboundedReceiver<ShoalppOrderBlocksInfo>>,
    ledger_info_provider: Arc<RwLock<LedgerInfoProvider>>,
    epoch_state: Arc<EpochState>,
    parent_block_info: BlockInfo,
    sent_to_commit_anchor_rounds: Vec<u64>,
}

impl ShoalppOrderNotifier {
    pub fn new(dag_store_vec: Vec<Arc<ArcSwapOption<DagStore>>>,
               ordered_nodes_tx: UnboundedSender<OrderedBlocks>,
               receivers: Vec<tokio::sync::mpsc::UnboundedReceiver<ShoalppOrderBlocksInfo>>,
               ledger_info_provider: Arc<RwLock<LedgerInfoProvider>>,
               epoch_state: Arc<EpochState>,
               parent_block_info: BlockInfo,
    ) -> Self {
        Self {
            dag_store_vec,
            ordered_nodes_tx,
            receivers,
            ledger_info_provider,
            epoch_state,
            parent_block_info,
            sent_to_commit_anchor_rounds: vec![0, 0, 0, 0],
        }
    }

    fn committed_anchors_to_hashvalue(&self) -> HashValue {
        let mut bytes: Vec<u8> = Vec::with_capacity(self.sent_to_commit_anchor_rounds.len() * 8);
        for &value in self.sent_to_commit_anchor_rounds.iter() {
            bytes.extend_from_slice(&value.to_le_bytes());
        }
        // TODO: verify that from_slice cannot fail in this case.
        HashValue::from_slice(&bytes).expect("Failed to create HashValue from committed rounds")
    }

    fn create_block(
        &mut self,
        block_info: ShoalppOrderBlocksInfo,
    ) -> OrderedBlocks {
        let ShoalppOrderBlocksInfo {
            dag_id, ordered_nodes, failed_author
        } = block_info;


        let anchor = ordered_nodes.last().unwrap();
        assert!(anchor.round() > self.sent_to_commit_anchor_rounds[dag_id as usize]);
        self.sent_to_commit_anchor_rounds[dag_id as usize] = anchor.round();
        let block_round = self.sent_to_commit_anchor_rounds
            .iter()
            .sum();
        let epoch = anchor.epoch();
        let timestamp = anchor.metadata().timestamp();
        let parent_timestamp = self.parent_block_info.timestamp_usecs();
        let block_timestamp = timestamp.max(parent_timestamp.checked_add(1).expect("must add"));
        let author = *anchor.author();
        let mut payload = Payload::empty(!anchor.payload().is_direct());
        let mut node_digests = vec![];
        for node in &ordered_nodes {
            payload.extend(node.payload().clone());
            node_digests.push(node.digest());
        }
        let parent_block_id = self.parent_block_info.id();
        // construct the bitvec that indicates which nodes present in the previous round in CommitEvent
        let mut parents_bitvec = BitVec::with_num_bits(self.epoch_state.verifier.len() as u16);
        for parent in anchor.parents().iter() {
            if let Some(idx) = self
                .epoch_state
                .verifier
                .address_to_validator_index()
                .get(parent.metadata().author())
            {
                parents_bitvec.set(*idx as u16);
            }
        }

        let block = PipelinedBlock::new(
            Block::new_for_dag(
                epoch,
                block_round,
                block_timestamp,
                vec![],
                payload,
                author,
                failed_author,
                parent_block_id,
                parents_bitvec,
                node_digests,
            ),
            vec![],
            StateComputeResult::new_dummy(),
        );
        let block_info = block.block_info();
        self.parent_block_info = block_info.clone();

        let ledger_info_provider = self.ledger_info_provider.clone();
        let dag_vec: Vec<Arc<DagStore>> = self.dag_store_vec
            .iter()
            .filter_map(|aso_dag| {
                aso_dag.load().deref().clone()
            })
            .collect();

        let consensus_data_hash = self.committed_anchors_to_hashvalue();
        OrderedBlocks {
            ordered_blocks: vec![block],
            ordered_proof: LedgerInfoWithSignatures::new(
                LedgerInfo::new(block_info, consensus_data_hash),
                AggregateSignature::empty(),
            ),
            callback: Box::new(
                move |committed_blocks: &[Arc<PipelinedBlock>],
                      commit_decision: LedgerInfoWithSignatures| {
                    let committed_rounds = commit_decision.get_highest_committed_rounds_for_shoalpp();
                    dag_vec
                        .iter()
                        .enumerate()
                        .for_each(|(dag_id, dag)| {
                            let round = committed_rounds[dag_id];
                            dag.write()
                                .commit_callback(round);
                        });
                    ledger_info_provider
                        .write()
                        .notify_commit_proof(commit_decision);
                    update_counters_for_committed_blocks(committed_blocks);
                },
            ),
        }
    }

    pub async fn run(mut self) {
        // TODO: shutdown logic

        let num_dags = self.receivers.len();

        loop {
            for dag_id in 0..=(num_dags - 1) {
                if let Some(bolt_block_info) = self.receivers[dag_id].recv().await {
                    let block = self.create_block(bolt_block_info);
                    if let Err(e) = self.ordered_nodes_tx.unbounded_send(block) {
                        error!("Failed to send ordered nodes {:?}", e);
                    }
                } else {
                    // shutdown in progress, but notifier should be killed before DAG
                    error!("Failed to receive message");
                    // Panic for debugging
                    panic!();
                }
            }
        }
    }
}