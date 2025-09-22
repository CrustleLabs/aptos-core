// Copyright © Aptos Foundation
// SPDX-License-Identifier: Apache-2.0

use minstant::Instant;
use std::collections::HashMap;
use std::fs::File;
use std::io::Write;
use std::sync::{Arc, Mutex};
use aptos_crypto::HashValue;
use aptos_types::transaction::SignedTransaction;
use once_cell::sync::Lazy;
use signal_hook::{consts::SIGUSR1, iterator::Signals};
use std::thread;
use chrono::{DateTime, Utc};

/// Performance monitoring system for tracking transaction latency
/// from mempool to blockchain commitment
#[derive(Debug, Clone)]
pub struct PerformanceMonitor {
    inner: Arc<Mutex<PerformanceMonitorInner>>,
}

#[derive(Debug)]
struct PerformanceMonitorInner {
    /// Transaction tracking data
    transaction_metrics: HashMap<HashValue, TransactionMetrics>,
    /// Function call metrics
    function_metrics: HashMap<String, Vec<FunctionCall>>,
    /// Global start time for relative measurements
    start_time: Instant,
}

#[derive(Debug, Clone)]
struct TransactionMetrics {
    /// Transaction hash
    tx_hash: HashValue,
    /// Sender address
    sender: String,
    /// Transaction type
    tx_type: String,
    /// Timestamps for different phases
    mempool_entry_time: Option<Instant>,
    proposal_generation_time: Option<Instant>,
    block_execution_time: Option<Instant>,
    vote_creation_time: Option<Instant>,
    commit_time: Option<Instant>,
    /// Additional metadata
    block_round: Option<u64>,
    block_id: Option<HashValue>,
}

#[derive(Debug, Clone)]
struct FunctionCall {
    function_name: String,
    start_time: Instant,
    end_time: Option<Instant>,
    duration_micros: Option<u64>,
    tx_hash: Option<HashValue>,
    additional_info: String,
    timestamp: DateTime<Utc>,
    thread_id: String,
}

/// Global performance monitor instance
static GLOBAL_MONITOR: Lazy<PerformanceMonitor> = Lazy::new(|| {
    println!("[PERF] Initializing Aptos Performance Monitor");
    let monitor = PerformanceMonitor::new();
    println!("[PERF] Performance Monitor initialized successfully");
    
    // Start signal handling thread
    monitor.start_signal_handler();
    println!("[PERF] Signal handler registered for SIGUSR1");
    
    monitor
});

impl PerformanceMonitor {
    /// Create a new performance monitor
    pub fn new() -> Self {
        Self {
            inner: Arc::new(Mutex::new(PerformanceMonitorInner {
                transaction_metrics: HashMap::new(),
                function_metrics: HashMap::new(),
                start_time: Instant::now(),
            })),
        }
    }
    
    /// Get global performance monitor instance
    pub fn global() -> &'static PerformanceMonitor {
        &GLOBAL_MONITOR
    }
    
    /// Start signal handler for metrics export
    fn start_signal_handler(&self) {
        let monitor_clone = self.clone();
        thread::spawn(move || {
            let mut signals = Signals::new(&[SIGUSR1]).expect("Failed to register signal handler");
            for sig in signals.forever() {
                match sig {
                    SIGUSR1 => {
                        println!("[PERF] Received SIGUSR1, exporting function latency metrics...");
                        let _ = monitor_clone.export_function_latency_to_file("/dev/shm/fn_latency.log");
                    }
                    _ => {}
                }
            }
        });
    }

    /// Track a transaction entering mempool
    pub fn track_mempool_entry(&self, tx: &SignedTransaction) {
        let mut inner = self.inner.lock().unwrap();
        let tx_hash = tx.committed_hash();
        let sender = tx.sender().to_string();
        let tx_type = match tx.payload() {
            aptos_types::transaction::TransactionPayload::Script(_) => "Script".to_string(),
            aptos_types::transaction::TransactionPayload::EntryFunction(entry_fn) => {
                format!("EntryFunction:{}::{}", entry_fn.module().address(), entry_fn.module().name())
            },
            aptos_types::transaction::TransactionPayload::Multisig(_) => "Multisig".to_string(),
            aptos_types::transaction::TransactionPayload::ModuleBundle(_) => "ModuleBundle".to_string(),
            aptos_types::transaction::TransactionPayload::Payload(_) => "Payload".to_string(),
        };

        let metrics = TransactionMetrics {
            tx_hash,
            sender,
            tx_type,
            mempool_entry_time: Some(Instant::now()),
            proposal_generation_time: None,
            block_execution_time: None,
            vote_creation_time: None,
            commit_time: None,
            block_round: None,
            block_id: None,
        };

        inner.transaction_metrics.insert(tx_hash, metrics);
        // Store function call for mempool entry (no direct printing)
        self.track_function_call_internal(&mut inner, "mempool_entry", Some(tx_hash), "Transaction entered mempool".to_string());
    }
    
    /// Internal method to track function calls
    fn track_function_call_internal(&self, inner: &mut PerformanceMonitorInner, function_name: &str, tx_hash: Option<HashValue>, info: String) {
        let call = FunctionCall {
            function_name: function_name.to_string(),
            start_time: Instant::now(),
            end_time: None,
            duration_micros: None,
            tx_hash,
            additional_info: info,
            timestamp: Utc::now(),
            thread_id: format!("{:?}", std::thread::current().id()),
        };
        
        inner.function_metrics
            .entry(function_name.to_string())
            .or_insert_with(Vec::new)
            .push(call);
    }

    /// Track proposal generation
    pub fn track_proposal_generation(&self, tx_hash: HashValue, block_round: u64) {
        let mut inner = self.inner.lock().unwrap();
        if let Some(metrics) = inner.transaction_metrics.get_mut(&tx_hash) {
            metrics.proposal_generation_time = Some(Instant::now());
            metrics.block_round = Some(block_round);
            // Store function call for proposal generation (no direct printing)
            self.track_function_call_internal(&mut inner, "proposal_generation", Some(tx_hash), format!("Transaction included in proposal for round {}", block_round));
        }
    }

    /// Track block execution
    pub fn track_block_execution(&self, tx_hash: HashValue, block_id: HashValue) {
        let mut inner = self.inner.lock().unwrap();
        if let Some(metrics) = inner.transaction_metrics.get_mut(&tx_hash) {
            metrics.block_execution_time = Some(Instant::now());
            metrics.block_id = Some(block_id);
            // Store function call for block execution (no direct printing)
            self.track_function_call_internal(&mut inner, "block_execution", Some(tx_hash), format!("Transaction executed in block {}", block_id));
        }
    }

    /// Track vote creation
    pub fn track_vote_creation(&self, tx_hash: HashValue) {
        let mut inner = self.inner.lock().unwrap();
        if let Some(metrics) = inner.transaction_metrics.get_mut(&tx_hash) {
            metrics.vote_creation_time = Some(Instant::now());
            // Store function call for vote creation (no direct printing)
            self.track_function_call_internal(&mut inner, "vote_creation", Some(tx_hash), "Vote created for transaction".to_string());
        }
    }

    /// Track block commit
    pub fn track_block_commit(&self, tx_hash: HashValue) {
        let mut inner = self.inner.lock().unwrap();
        if let Some(metrics) = inner.transaction_metrics.get_mut(&tx_hash) {
            metrics.commit_time = Some(Instant::now());
            // Store function call for block commit (no direct printing)
            self.track_function_call_internal(&mut inner, "block_commit", Some(tx_hash), "Transaction committed to blockchain".to_string());
        }
    }

    /// Start tracking a function call
    pub fn start_function(&self, function_name: &str, tx_hash: Option<HashValue>, info: &str) -> FunctionTracker {
        let call = FunctionCall {
            function_name: function_name.to_string(),
            start_time: Instant::now(),
            end_time: None,
            duration_micros: None,
            tx_hash,
            additional_info: info.to_string(),
            timestamp: Utc::now(),
            thread_id: format!("{:?}", std::thread::current().id()),
        };

        FunctionTracker {
            monitor: self.clone(),
            call,
        }
    }

    /// Complete a function call tracking
    fn complete_function(&self, mut call: FunctionCall) {
        call.end_time = Some(Instant::now());
        call.duration_micros = Some(
            call.end_time.unwrap().duration_since(call.start_time).as_micros() as u64
        );

        let mut inner = self.inner.lock().unwrap();
        inner.function_metrics
            .entry(call.function_name.clone())
            .or_insert_with(Vec::new)
            .push(call);
    }

    /// Export all metrics to a log file
    pub fn export_metrics(&self, file_path: &str) -> std::io::Result<()> {
        let inner = self.inner.lock().unwrap();
        let mut file = File::create(file_path)?;

        writeln!(file, "=== Aptos Consensus Performance Report ===")?;
        writeln!(file, "Generated at: {}", chrono::Utc::now().format("%Y-%m-%d %H:%M:%S UTC"))?;
        writeln!(file)?;

        // Export transaction end-to-end metrics
        writeln!(file, "=== Transaction End-to-End Latency ===")?;
        for (tx_hash, metrics) in &inner.transaction_metrics {
            writeln!(file, "Transaction: {}", tx_hash)?;
            writeln!(file, "  Sender: {}", metrics.sender)?;
            writeln!(file, "  Type: {}", metrics.tx_type)?;
            if let Some(round) = metrics.block_round {
                writeln!(file, "  Block Round: {}", round)?;
            }
            if let Some(block_id) = metrics.block_id {
                writeln!(file, "  Block ID: {}", block_id)?;
            }

            // Calculate phase durations
            if let Some(mempool_time) = metrics.mempool_entry_time {
                let base_time = mempool_time;
                writeln!(file, "  Mempool Entry: 0 μs (baseline)")?;

                if let Some(proposal_time) = metrics.proposal_generation_time {
                    let duration = proposal_time.duration_since(base_time).as_micros();
                    writeln!(file, "  Proposal Generation: {} μs", duration)?;
                }

                if let Some(execution_time) = metrics.block_execution_time {
                    let duration = execution_time.duration_since(base_time).as_micros();
                    writeln!(file, "  Block Execution: {} μs", duration)?;
                }

                if let Some(vote_time) = metrics.vote_creation_time {
                    let duration = vote_time.duration_since(base_time).as_micros();
                    writeln!(file, "  Vote Creation: {} μs", duration)?;
                }

                if let Some(commit_time) = metrics.commit_time {
                    let total_duration = commit_time.duration_since(base_time).as_micros();
                    writeln!(file, "  Block Commit: {} μs", total_duration)?;
                    writeln!(file, "  TOTAL LATENCY: {} μs ({} ms)", total_duration, total_duration / 1000)?;
                }
            }
            writeln!(file)?;
        }

        // Export function call metrics
        writeln!(file, "=== Function Call Latency Statistics ===")?;
        for (function_name, calls) in &inner.function_metrics {
            if calls.is_empty() {
                continue;
            }

            let durations: Vec<u64> = calls.iter()
                .filter_map(|c| c.duration_micros)
                .collect();

            if durations.is_empty() {
                continue;
            }

            let total_calls = durations.len();
            let total_time: u64 = durations.iter().sum();
            let avg_time = total_time / total_calls as u64;
            let min_time = *durations.iter().min().unwrap();
            let max_time = *durations.iter().max().unwrap();

            writeln!(file, "Function: {}", function_name)?;
            writeln!(file, "  Total Calls: {}", total_calls)?;
            writeln!(file, "  Average Time: {} μs", avg_time)?;
            writeln!(file, "  Min Time: {} μs", min_time)?;
            writeln!(file, "  Max Time: {} μs", max_time)?;
            writeln!(file, "  Total Time: {} μs", total_time)?;

            // Show individual calls for detailed analysis
            writeln!(file, "  Individual Calls:")?;
            for call in calls {
                if let Some(duration) = call.duration_micros {
                    let tx_info = call.tx_hash
                        .map(|h| format!(" [tx: {}]", h))
                        .unwrap_or_default();
                    writeln!(file, "    {} μs{} - {}", duration, tx_info, call.additional_info)?;
                }
            }
            writeln!(file)?;
        }

        println!("[PERF] Performance metrics exported to: {}", file_path);
        Ok(())
    }

    /// Export function latency data to a specific log file
    pub fn export_function_latency_to_file(&self, file_path: &str) -> std::io::Result<()> {
        let inner = self.inner.lock().unwrap();
        let mut file = File::create(file_path)?;
        
        writeln!(file, "=== Function Latency Report ===")?;
        writeln!(file, "Generated at: {}", Utc::now().format("%Y-%m-%d %H:%M:%S UTC"))?;
        writeln!(file, "Total function types tracked: {}", inner.function_metrics.len())?;
        writeln!(file)?;
        
        // Calculate total function calls
        let total_calls: usize = inner.function_metrics.values().map(|calls| calls.len()).sum();
        writeln!(file, "Total function calls recorded: {}", total_calls)?;
        writeln!(file)?;
        
        // Export detailed function latency data
        for (function_name, calls) in &inner.function_metrics {
            if calls.is_empty() {
                continue;
            }
            
            writeln!(file, "=== {} ===", function_name)?;
            writeln!(file, "Total calls: {}", calls.len())?;
            
            // Calculate statistics for calls with duration
            let durations: Vec<u64> = calls.iter()
                .filter_map(|c| c.duration_micros)
                .collect();
            
            if !durations.is_empty() {
                let total_time: u64 = durations.iter().sum();
                let avg_time = total_time / durations.len() as u64;
                let min_time = *durations.iter().min().unwrap();
                let max_time = *durations.iter().max().unwrap();
                
                writeln!(file, "Completed calls: {}", durations.len())?;
                writeln!(file, "Average latency: {} μs ({:.2} ms)", avg_time, avg_time as f64 / 1000.0)?;
                writeln!(file, "Min latency: {} μs", min_time)?;
                writeln!(file, "Max latency: {} μs", max_time)?;
                writeln!(file, "Total time: {} μs ({:.2} ms)", total_time, total_time as f64 / 1000.0)?;
            }
            
            // List individual function calls with timestamps
            writeln!(file, "Individual calls:")?;
            for (i, call) in calls.iter().enumerate() {
                let duration_str = call.duration_micros
                    .map(|d| format!("{} μs", d))
                    .unwrap_or_else(|| "pending".to_string());
                
                let tx_str = call.tx_hash
                    .map(|h| format!(" [tx:{}]", h.to_string()[..8].to_string()))
                    .unwrap_or_default();
                    
                writeln!(file, "  {}: {} at {} (thread:{}) - {}{}", 
                    i + 1,
                    duration_str,
                    call.timestamp.format("%H:%M:%S%.3f"),
                    call.thread_id,
                    call.additional_info,
                    tx_str
                )?;
            }
            writeln!(file)?;
        }
        
        // Export transaction-to-function mapping
        writeln!(file, "=== Transaction Function Mapping ===")?;
        let mut tx_functions: HashMap<HashValue, Vec<String>> = HashMap::new();
        for (func_name, calls) in &inner.function_metrics {
            for call in calls {
                if let Some(tx_hash) = call.tx_hash {
                    tx_functions.entry(tx_hash)
                        .or_insert_with(Vec::new)
                        .push(func_name.clone());
                }
            }
        }
        
        for (tx_hash, functions) in tx_functions {
            writeln!(file, "Transaction {}: {} functions", tx_hash, functions.len())?;
            for func in functions {
                writeln!(file, "  - {}", func)?;
            }
        }
        
        println!("[PERF] Function latency data exported to: {}", file_path);
        Ok(())
    }
}

/// RAII wrapper for function call tracking
pub struct FunctionTracker {
    monitor: PerformanceMonitor,
    call: FunctionCall,
}

impl Drop for FunctionTracker {
    fn drop(&mut self) {
        self.monitor.complete_function(self.call.clone());
    }
}

/// Macro for easy function tracking
#[macro_export]
macro_rules! track_function {
    ($func_name:expr) => {
        let _tracker = $crate::PerformanceMonitor::global()
            .start_function($func_name, None, "");
    };
    ($func_name:expr, $tx_hash:expr) => {
        let _tracker = $crate::PerformanceMonitor::global()
            .start_function($func_name, Some($tx_hash), "");
    };
    ($func_name:expr, $tx_hash:expr, $info:expr) => {
        let _tracker = $crate::PerformanceMonitor::global()
            .start_function($func_name, Some($tx_hash), $info);
    };
}
