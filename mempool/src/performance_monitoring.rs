// Copyright © Aptos Foundation
// SPDX-License-Identifier: Apache-2.0

//! Performance monitoring and timing hooks for transaction processing
//! 
//! This module provides comprehensive timing instrumentation for tracking
//! transaction lifecycle from mempool to blockchain commitment.

use std::{
    collections::HashMap,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Mutex,
    },
    time::{Duration, Instant},
};
use aptos_crypto::HashValue;
use aptos_logger::{info, warn};
use aptos_types::account_address::AccountAddress;
use once_cell::sync::Lazy;

/// Global performance tracker instance
pub static PERF_TRACKER: Lazy<Arc<PerformanceTracker>> = Lazy::new(|| {
    Arc::new(PerformanceTracker::new())
});

/// Transaction processing stages
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ProcessingStage {
    // Mempool stages
    MempoolReceived,        // Transaction received by mempool
    MempoolValidation,      // VM validation in mempool
    MempoolAdded,          // Added to mempool storage
    
    // Consensus stages  
    PayloadPull,           // Leader pulls from mempool
    ProposalGeneration,    // Block proposal generation
    ProposalBroadcast,     // Proposal broadcast to validators
    
    // Validator stages
    ProposalReceived,      // Validator receives proposal
    BlockPrepare,          // Block preparation (get transactions)
    TransactionExecution,  // Individual transaction execution
    BlockExecution,        // Complete block execution
    VoteGeneration,        // Vote creation and signing
    VoteBroadcast,         // Vote sent to leader
    
    // Consensus finalization
    VoteAggregation,       // Leader aggregates votes
    QuorumCertCreation,    // QC formation
    BlockCommit,           // Block commitment to storage
    
    // Final stage
    ChainCommitted,        // Transaction committed to blockchain
}

impl ProcessingStage {
    pub fn as_str(&self) -> &'static str {
        match self {
            ProcessingStage::MempoolReceived => "mempool_received",
            ProcessingStage::MempoolValidation => "mempool_validation",
            ProcessingStage::MempoolAdded => "mempool_added",
            ProcessingStage::PayloadPull => "payload_pull",
            ProcessingStage::ProposalGeneration => "proposal_generation",
            ProcessingStage::ProposalBroadcast => "proposal_broadcast",
            ProcessingStage::ProposalReceived => "proposal_received",
            ProcessingStage::BlockPrepare => "block_prepare",
            ProcessingStage::TransactionExecution => "transaction_execution",
            ProcessingStage::BlockExecution => "block_execution",
            ProcessingStage::VoteGeneration => "vote_generation",
            ProcessingStage::VoteBroadcast => "vote_broadcast",
            ProcessingStage::VoteAggregation => "vote_aggregation",
            ProcessingStage::QuorumCertCreation => "quorum_cert_creation",
            ProcessingStage::BlockCommit => "block_commit",
            ProcessingStage::ChainCommitted => "chain_committed",
        }
    }
}

/// Timing record for a specific stage
#[derive(Debug, Clone)]
pub struct TimingRecord {
    pub stage: ProcessingStage,
    pub timestamp: Instant,
    pub duration: Option<Duration>,
    pub metadata: HashMap<String, String>,
}

/// Transaction timing tracker
#[derive(Debug, Clone)]
pub struct TransactionTiming {
    pub tx_hash: HashValue,
    pub sender: AccountAddress,
    pub start_time: Instant,
    pub records: Vec<TimingRecord>,
    pub completed: bool,
}

impl TransactionTiming {
    pub fn new(tx_hash: HashValue, sender: AccountAddress) -> Self {
        Self {
            tx_hash,
            sender,
            start_time: Instant::now(),
            records: Vec::new(),
            completed: false,
        }
    }
    
    pub fn add_stage(&mut self, stage: ProcessingStage, metadata: HashMap<String, String>) {
        let now = Instant::now();
        let duration = self.records.last()
            .map(|last| now.duration_since(last.timestamp));
            
        self.records.push(TimingRecord {
            stage,
            timestamp: now,
            duration,
            metadata,
        });
        
        if stage == ProcessingStage::ChainCommitted {
            self.completed = true;
        }
    }
    
    pub fn total_duration(&self) -> Duration {
        if let Some(last) = self.records.last() {
            last.timestamp.duration_since(self.start_time)
        } else {
            Duration::ZERO
        }
    }
    
    pub fn stage_duration(&self, stage: ProcessingStage) -> Option<Duration> {
        self.records.iter()
            .find(|r| r.stage == stage)
            .and_then(|r| r.duration)
    }
}

/// Main performance tracker
pub struct PerformanceTracker {
    active_transactions: Mutex<HashMap<HashValue, TransactionTiming>>,
    completed_transactions: Mutex<Vec<TransactionTiming>>,
    stage_counters: HashMap<ProcessingStage, AtomicU64>,
    total_processed: AtomicU64,
}

impl PerformanceTracker {
    pub fn new() -> Self {
        let mut stage_counters = HashMap::new();
        for stage in [
            ProcessingStage::MempoolReceived,
            ProcessingStage::MempoolValidation,
            ProcessingStage::MempoolAdded,
            ProcessingStage::PayloadPull,
            ProcessingStage::ProposalGeneration,
            ProcessingStage::ProposalBroadcast,
            ProcessingStage::ProposalReceived,
            ProcessingStage::BlockPrepare,
            ProcessingStage::TransactionExecution,
            ProcessingStage::BlockExecution,
            ProcessingStage::VoteGeneration,
            ProcessingStage::VoteBroadcast,
            ProcessingStage::VoteAggregation,
            ProcessingStage::QuorumCertCreation,
            ProcessingStage::BlockCommit,
            ProcessingStage::ChainCommitted,
        ] {
            stage_counters.insert(stage, AtomicU64::new(0));
        }
        
        Self {
            active_transactions: Mutex::new(HashMap::new()),
            completed_transactions: Mutex::new(Vec::new()),
            stage_counters,
            total_processed: AtomicU64::new(0),
        }
    }
    
    /// Start tracking a new transaction
    pub fn start_transaction(&self, tx_hash: HashValue, sender: AccountAddress) {
        let mut active = self.active_transactions.lock().unwrap();
        let timing = TransactionTiming::new(tx_hash, sender);
        active.insert(tx_hash, timing);
        
        info!(
            "PERF_TRACK: Started tracking transaction {} from sender {}",
            tx_hash, sender
        );
    }
    
    /// Record a processing stage for a transaction
    pub fn record_stage(&self, tx_hash: HashValue, stage: ProcessingStage, metadata: HashMap<String, String>) {
        let mut active = self.active_transactions.lock().unwrap();
        
        if let Some(timing) = active.get_mut(&tx_hash) {
            timing.add_stage(stage, metadata);
            self.stage_counters.get(&stage).unwrap().fetch_add(1, Ordering::Relaxed);
            
            info!(
                "PERF_TRACK: {} - {} at {:?} (total: {:?})",
                tx_hash,
                stage.as_str(),
                timing.records.last().unwrap().timestamp.duration_since(timing.start_time),
                timing.total_duration()
            );
            
            // Move to completed if transaction is done
            if timing.completed {
                let completed_timing = timing.clone();
                let total_duration = timing.total_duration();
                drop(active);
                
                let mut completed = self.completed_transactions.lock().unwrap();
                completed.push(completed_timing);
                self.total_processed.fetch_add(1, Ordering::Relaxed);
                
                // Remove from active
                let mut active = self.active_transactions.lock().unwrap();
                active.remove(&tx_hash);
                
                info!(
                    "PERF_TRACK: Transaction {} completed in {:?}",
                    tx_hash,
                    total_duration
                );
            }
        } else {
            warn!(
                "PERF_TRACK: Attempted to record stage {} for unknown transaction {}",
                stage.as_str(),
                tx_hash
            );
        }
    }
    
    /// Get statistics for completed transactions
    pub fn get_statistics(&self) -> PerformanceStatistics {
        let completed = self.completed_transactions.lock().unwrap();
        let active_count = self.active_transactions.lock().unwrap().len();
        
        let mut stage_stats = HashMap::new();
        let mut total_durations = Vec::new();
        
        for timing in completed.iter() {
            total_durations.push(timing.total_duration());
            
            for record in &timing.records {
                if let Some(duration) = record.duration {
                    stage_stats.entry(record.stage)
                        .or_insert_with(Vec::new)
                        .push(duration);
                }
            }
        }
        
        // Calculate percentiles
        let percentile_calc = |mut durations: Vec<Duration>| -> StageStatistics {
            if durations.is_empty() {
                return StageStatistics::default();
            }
            
            durations.sort();
            let len = durations.len();
            
            StageStatistics {
                count: len,
                min: durations[0],
                max: durations[len - 1],
                p50: durations[len / 2],
                p95: durations[len * 95 / 100],
                p99: durations[len * 99 / 100],
                avg: Duration::from_nanos(
                    durations.iter().map(|d| d.as_nanos()).sum::<u128>() as u64 / len as u64
                ),
            }
        };
        
        let mut stage_statistics = HashMap::new();
        for (stage, durations) in stage_stats {
            stage_statistics.insert(stage, percentile_calc(durations));
        }
        
        PerformanceStatistics {
            total_completed: completed.len(),
            total_active: active_count,
            end_to_end_stats: percentile_calc(total_durations),
            stage_statistics,
        }
    }
    
    /// Print comprehensive performance report
    pub fn print_report(&self) {
        let stats = self.get_statistics();
        
        info!("=== APTOS TRANSACTION PERFORMANCE REPORT ===");
        info!("Total Completed: {}", stats.total_completed);
        info!("Total Active: {}", stats.total_active);
        
        info!("End-to-End Performance:");
        info!("  Count: {}", stats.end_to_end_stats.count);
        info!("  Min: {:?}", stats.end_to_end_stats.min);
        info!("  Max: {:?}", stats.end_to_end_stats.max);
        info!("  Avg: {:?}", stats.end_to_end_stats.avg);
        info!("  P50: {:?}", stats.end_to_end_stats.p50);
        info!("  P95: {:?}", stats.end_to_end_stats.p95);
        info!("  P99: {:?}", stats.end_to_end_stats.p99);
        
        info!("Stage-by-Stage Performance:");
        for (stage, stage_stats) in &stats.stage_statistics {
            info!("  {} ({} samples):", stage.as_str(), stage_stats.count);
            info!("    Min: {:?}, Max: {:?}, Avg: {:?}", 
                  stage_stats.min, stage_stats.max, stage_stats.avg);
            info!("    P50: {:?}, P95: {:?}, P99: {:?}", 
                  stage_stats.p50, stage_stats.p95, stage_stats.p99);
        }
        
        info!("=== END PERFORMANCE REPORT ===");
    }
}

#[derive(Debug, Default)]
pub struct StageStatistics {
    pub count: usize,
    pub min: Duration,
    pub max: Duration,
    pub avg: Duration,
    pub p50: Duration,
    pub p95: Duration,
    pub p99: Duration,
}

#[derive(Debug)]
pub struct PerformanceStatistics {
    pub total_completed: usize,
    pub total_active: usize,
    pub end_to_end_stats: StageStatistics,
    pub stage_statistics: HashMap<ProcessingStage, StageStatistics>,
}

/// Convenience macros for timing
#[macro_export]
macro_rules! perf_start_transaction {
    ($tx_hash:expr, $sender:expr) => {
        $crate::performance_monitoring::PERF_TRACKER.start_transaction($tx_hash, $sender);
    };
}

#[macro_export]
macro_rules! perf_record_stage {
    ($tx_hash:expr, $stage:expr) => {
        $crate::performance_monitoring::PERF_TRACKER.record_stage(
            $tx_hash, 
            $stage, 
            std::collections::HashMap::new()
        );
    };
    ($tx_hash:expr, $stage:expr, $($key:expr => $value:expr),*) => {
        {
            let mut metadata = std::collections::HashMap::new();
            $(
                metadata.insert($key.to_string(), $value.to_string());
            )*
            $crate::performance_monitoring::PERF_TRACKER.record_stage($tx_hash, $stage, metadata);
        }
    };
}

#[macro_export]
macro_rules! perf_function_timer {
    ($tx_hash:expr, $stage:expr, $func:expr) => {
        {
            let start = std::time::Instant::now();
            let result = $func;
            let duration = start.elapsed();
            
            let mut metadata = std::collections::HashMap::new();
            metadata.insert("function_duration".to_string(), format!("{:?}", duration));
            
            $crate::performance_monitoring::PERF_TRACKER.record_stage($tx_hash, $stage, metadata);
            result
        }
    };
}
