// Copyright © Aptos Foundation
// SPDX-License-Identifier: Apache-2.0

//! Detailed performance hooks for specific Aptos components
//! This file contains the exact code modifications needed for comprehensive timing

use crate::performance_monitoring::{PERF_TRACKER, ProcessingStage};
use aptos_crypto::HashValue;
use aptos_types::account_address::AccountAddress;
use std::collections::HashMap;

/// Mempool performance hooks
/// File: mempool/src/shared_mempool/tasks.rs
pub mod mempool_hooks {
    use super::*;
    
    /// Hook for when transaction is received by mempool
    /// Insert at line ~200 in process_incoming_transactions()
    pub fn on_transaction_received(tx_hash: HashValue, sender: AccountAddress) {
        PERF_TRACKER.start_transaction(tx_hash, sender);
        PERF_TRACKER.record_stage(tx_hash, ProcessingStage::MempoolReceived, HashMap::new());
    }
    
    /// Hook for when transaction validation completes
    /// Insert after VM validation in process_incoming_transactions()
    pub fn on_transaction_validated(tx_hash: HashValue, validation_result: &str) {
        let mut metadata = HashMap::new();
        metadata.insert("validation_result".to_string(), validation_result.to_string());
        PERF_TRACKER.record_stage(tx_hash, ProcessingStage::MempoolValidation, metadata);
    }
    
    /// Hook for when transaction is added to mempool
    /// Insert after successful addition to CoreMempool
    pub fn on_transaction_added_to_mempool(tx_hash: HashValue) {
        PERF_TRACKER.record_stage(tx_hash, ProcessingStage::MempoolAdded, HashMap::new());
    }
}

/// Consensus performance hooks
/// File: consensus/src/liveness/proposal_generator.rs
pub mod consensus_hooks {
    use super::*;
    
    /// Hook for payload pull from mempool
    /// Insert before payload_client.pull_payload() call at line ~655
    pub fn on_payload_pull_start(block_id: HashValue) {
        // We'll track this at the block level since we don't have individual tx hashes yet
        let mut metadata = HashMap::new();
        metadata.insert("block_id".to_string(), block_id.to_string());
        // Note: Individual transaction tracking will happen when we get the payload
    }
    
    /// Hook for payload pull completion
    /// Insert after payload_client.pull_payload() success
    pub fn on_payload_pull_complete(transactions: &[SignedTransaction], duration: std::time::Duration) {
        for txn in transactions {
            let mut metadata = HashMap::new();
            metadata.insert("payload_pull_duration".to_string(), format!("{:?}", duration));
            PERF_TRACKER.record_stage(txn.hash(), ProcessingStage::PayloadPull, metadata);
        }
    }
    
    /// Hook for proposal generation
    /// Insert in RoundManager::generate_proposal() at line ~637
    pub fn on_proposal_generation_start(block: &Block) {
        if let Some(payload) = block.payload() {
            if let Some(txns) = payload.txns() {
                for txn in txns {
                    PERF_TRACKER.record_stage(txn.hash(), ProcessingStage::ProposalGeneration, HashMap::new());
                }
            }
        }
    }
    
    /// Hook for proposal broadcast
    /// Insert in NetworkSender::broadcast_proposal()
    pub fn on_proposal_broadcast(proposal: &Block) {
        if let Some(payload) = proposal.payload() {
            if let Some(txns) = payload.txns() {
                for txn in txns {
                    PERF_TRACKER.record_stage(txn.hash(), ProcessingStage::ProposalBroadcast, HashMap::new());
                }
            }
        }
    }
    
    /// Hook for proposal received
    /// Insert in RoundManager::process_proposal_msg() at line ~687
    pub fn on_proposal_received(proposal: &Block) {
        if let Some(payload) = proposal.payload() {
            if let Some(txns) = payload.txns() {
                for txn in txns {
                    PERF_TRACKER.record_stage(txn.hash(), ProcessingStage::ProposalReceived, HashMap::new());
                }
            }
        }
    }
}

/// Block execution performance hooks
/// File: consensus/src/block_preparer.rs & consensus/src/pipeline/pipeline_builder.rs
pub mod execution_hooks {
    use super::*;
    
    /// Hook for block preparation start
    /// Insert in BlockPreparer::prepare_block() at line ~42
    pub fn on_block_prepare_start(block: &Block) {
        if let Some(payload) = block.payload() {
            if let Some(txns) = payload.txns() {
                for txn in txns {
                    PERF_TRACKER.record_stage(txn.hash(), ProcessingStage::BlockPrepare, HashMap::new());
                }
            }
        }
    }
    
    /// Hook for transaction execution start
    /// Insert in AptosExecutorTask::execute_transaction() at line ~43
    pub fn on_transaction_execution_start(tx_hash: HashValue, txn_idx: usize) {
        let mut metadata = HashMap::new();
        metadata.insert("txn_index".to_string(), txn_idx.to_string());
        PERF_TRACKER.record_stage(tx_hash, ProcessingStage::TransactionExecution, metadata);
    }
    
    /// Hook for block execution start
    /// Insert in PipelineBuilder::execute() at line ~544
    pub fn on_block_execution_start(transactions: &[SignedTransaction]) {
        for txn in transactions {
            PERF_TRACKER.record_stage(txn.hash(), ProcessingStage::BlockExecution, HashMap::new());
        }
    }
    
    /// Hook for block execution completion
    /// Insert after executor.execute_and_update_state() success
    pub fn on_block_execution_complete(transactions: &[SignedTransaction], execution_time: std::time::Duration) {
        for txn in transactions {
            let mut metadata = HashMap::new();
            metadata.insert("block_execution_time".to_string(), format!("{:?}", execution_time));
            PERF_TRACKER.record_stage(txn.hash(), ProcessingStage::BlockExecution, metadata);
        }
    }
}

/// Voting and consensus finalization hooks
/// File: consensus/src/round_manager.rs & consensus/src/pending_votes.rs
pub mod voting_hooks {
    use super::*;
    
    /// Hook for vote generation
    /// Insert in RoundManager::create_vote() before vote creation
    pub fn on_vote_generation_start(block: &Block) {
        if let Some(payload) = block.payload() {
            if let Some(txns) = payload.txns() {
                for txn in txns {
                    PERF_TRACKER.record_stage(txn.hash(), ProcessingStage::VoteGeneration, HashMap::new());
                }
            }
        }
    }
    
    /// Hook for vote broadcast
    /// Insert in NetworkSender::send_vote() or broadcast_vote()
    pub fn on_vote_broadcast(vote: &Vote) {
        let block_id = vote.vote_data().proposed().id();
        let mut metadata = HashMap::new();
        metadata.insert("block_id".to_string(), block_id.to_string());
        metadata.insert("voter".to_string(), vote.author().to_string());
        // Note: Need to get transactions from block_id to record per-transaction
    }
    
    /// Hook for vote aggregation
    /// Insert in PendingVotes::insert_vote() when processing votes
    pub fn on_vote_aggregation(vote: &Vote, current_voting_power: u128) {
        let mut metadata = HashMap::new();
        metadata.insert("voting_power".to_string(), current_voting_power.to_string());
        metadata.insert("voter".to_string(), vote.author().to_string());
        // Note: Need block context to get transactions
    }
    
    /// Hook for quorum certificate creation
    /// Insert in PendingVotes when QC is formed (line ~362)
    pub fn on_quorum_cert_created(qc: &QuorumCert) {
        let block_id = qc.certified_block().id();
        let mut metadata = HashMap::new();
        metadata.insert("block_id".to_string(), block_id.to_string());
        metadata.insert("certified_round".to_string(), qc.certified_block().round().to_string());
        // Note: Need to get transactions from block to record per-transaction
    }
}

/// Block commitment hooks
/// File: consensus/src/block_storage/block_tree.rs
pub mod commitment_hooks {
    use super::*;
    
    /// Hook for block commitment
    /// Insert in BlockTree::commit_callback() at line ~568
    pub fn on_block_commit_start(block_id: HashValue, block_round: u64) {
        let mut metadata = HashMap::new();
        metadata.insert("block_id".to_string(), block_id.to_string());
        metadata.insert("block_round".to_string(), block_round.to_string());
        // Note: Need to get transactions from block_id
    }
    
    /// Hook for final chain commitment
    /// Insert in process_committed_transactions() in mempool/src/shared_mempool/tasks.rs
    pub fn on_chain_committed(transactions: &[CommittedTransaction]) {
        for transaction in transactions {
            let tx_hash = transaction.hash(); // Assuming this method exists
            PERF_TRACKER.record_stage(tx_hash, ProcessingStage::ChainCommitted, HashMap::new());
        }
    }
}

/// Utility functions for extracting transaction hashes from various contexts
pub mod utils {
    use super::*;
    use aptos_consensus_types::{block::Block, common::Payload};
    use aptos_types::transaction::SignedTransaction;
    
    /// Extract transaction hashes from a block's payload
    pub fn get_transaction_hashes_from_block(block: &Block) -> Vec<HashValue> {
        if let Some(payload) = block.payload() {
            if let Some(txns) = get_transactions_from_payload(payload) {
                return txns.iter().map(|txn| txn.hash()).collect();
            }
        }
        Vec::new()
    }
    
    /// Extract transactions from payload (implementation depends on payload type)
    pub fn get_transactions_from_payload(payload: &Payload) -> Option<Vec<SignedTransaction>> {
        match payload {
            Payload::DirectMempool(txns) => Some(txns.clone()),
            Payload::QuorumStoreInlineHybrid(inline_batches, _proof, _max_txns) => {
                let mut all_txns = Vec::new();
                for (_batch_info, txns) in inline_batches {
                    all_txns.extend(txns.clone());
                }
                Some(all_txns)
            },
            // Add other payload types as needed
            _ => None,
        }
    }
    
    /// Helper macro to record stage for all transactions in a block
    #[macro_export]
    macro_rules! perf_record_block_stage {
        ($block:expr, $stage:expr) => {
            if let Some(tx_hashes) = $crate::detailed_performance_hooks::utils::get_transaction_hashes_from_block($block) {
                for tx_hash in tx_hashes {
                    $crate::performance_monitoring::PERF_TRACKER.record_stage(
                        tx_hash, 
                        $stage, 
                        std::collections::HashMap::new()
                    );
                }
            }
        };
        ($block:expr, $stage:expr, $($key:expr => $value:expr),*) => {
            if let Some(tx_hashes) = $crate::detailed_performance_hooks::utils::get_transaction_hashes_from_block($block) {
                for tx_hash in tx_hashes {
                    let mut metadata = std::collections::HashMap::new();
                    $(
                        metadata.insert($key.to_string(), $value.to_string());
                    )*
                    $crate::performance_monitoring::PERF_TRACKER.record_stage(tx_hash, $stage, metadata);
                }
            }
        };
    }
}

/// Performance monitoring configuration
pub struct PerformanceConfig {
    pub enable_detailed_timing: bool,
    pub enable_resource_monitoring: bool,
    pub log_level: u8,  // 0=none, 1=basic, 2=detailed, 3=verbose
    pub output_format: OutputFormat,
}

pub enum OutputFormat {
    Console,
    Json,
    Csv,
}

impl Default for PerformanceConfig {
    fn default() -> Self {
        Self {
            enable_detailed_timing: true,
            enable_resource_monitoring: false,
            log_level: 2,
            output_format: OutputFormat::Console,
        }
    }
}

/// Initialize performance monitoring system
pub fn initialize_performance_monitoring(config: PerformanceConfig) {
    // Set global configuration
    // This would be called during node startup
    
    std::env::set_var("APTOS_PERF_MONITORING", "enabled");
    std::env::set_var("APTOS_PERF_LOG_LEVEL", config.log_level.to_string());
    
    // Setup signal handlers for graceful shutdown and report generation
    setup_signal_handlers();
}

fn setup_signal_handlers() {
    // Setup SIGINT and SIGTERM handlers to generate final performance report
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Arc;
    
    let running = Arc::new(AtomicBool::new(true));
    let r = running.clone();
    
    ctrlc::set_handler(move || {
        r.store(false, Ordering::SeqCst);
        PERF_TRACKER.print_report();
        std::process::exit(0);
    }).expect("Error setting Ctrl-C handler");
}
