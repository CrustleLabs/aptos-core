// Copyright © Aptos Foundation
// SPDX-License-Identifier: Apache-2.0

use aptos_performance_monitor::PerformanceMonitor;
use std::sync::atomic::{AtomicBool, Ordering};
use tokio::signal;

static SHUTDOWN_REQUESTED: AtomicBool = AtomicBool::new(false);

/// Initialize signal handlers for graceful shutdown and performance metrics export
pub fn init_signal_handlers() {
    use std::sync::Once;
    static INIT: Once = Once::new();
    
    INIT.call_once(|| {
        println!("[SIGNAL] Basic signal handlers initialized");
        
        // Set up a thread to handle SIGUSR1 specifically for metrics export
        std::thread::spawn(|| {
            use std::sync::{Arc, atomic::{AtomicBool, Ordering}};
            
            let sigusr1_flag = Arc::new(AtomicBool::new(false));
            let _ = signal_hook::flag::register(signal_hook::consts::SIGUSR1, 
                Arc::clone(&sigusr1_flag));
            
            loop {
                std::thread::sleep(std::time::Duration::from_millis(100));
                if sigusr1_flag.load(Ordering::SeqCst) {
                    println!("[SIGNAL] Received SIGUSR1, exporting performance metrics...");
                    export_performance_metrics();
                    sigusr1_flag.store(false, Ordering::SeqCst);
                }
            }
        });
    });
}

/// Initialize async signal handlers - call this after tokio runtime is started
pub async fn init_async_signal_handlers() {
    tokio::spawn(async {
        let mut sigterm = signal::unix::signal(signal::unix::SignalKind::terminate())
            .expect("Failed to install SIGTERM handler");
        let mut sigint = signal::unix::signal(signal::unix::SignalKind::interrupt())
            .expect("Failed to install SIGINT handler");
        let mut sigusr1 = signal::unix::signal(signal::unix::SignalKind::user_defined1())
            .expect("Failed to install SIGUSR1 handler");

        loop {
            tokio::select! {
                _ = sigterm.recv() => {
                    println!("[SIGNAL] Received SIGTERM, exporting performance metrics...");
                    export_performance_metrics();
                    SHUTDOWN_REQUESTED.store(true, Ordering::SeqCst);
                    std::process::exit(0);
                },
                _ = sigint.recv() => {
                    println!("[SIGNAL] Received SIGINT (Ctrl+C), exporting performance metrics...");
                    export_performance_metrics();
                    SHUTDOWN_REQUESTED.store(true, Ordering::SeqCst);
                    std::process::exit(0);
                },
                _ = sigusr1.recv() => {
                    println!("[SIGNAL] Received SIGUSR1, exporting performance metrics...");
                    export_performance_metrics();
                },
            }
        }
    });
}

/// Export performance metrics to a log file
fn export_performance_metrics() {
    let timestamp = chrono::Utc::now().format("%Y%m%d_%H%M%S");
    let log_path = format!("/dev/shm/performance_metrics_{}.log", timestamp);
    
    match PerformanceMonitor::global().export_metrics(&log_path) {
        Ok(()) => {
            println!("[SIGNAL] Performance metrics exported to: {}", log_path);
        },
        Err(e) => {
            eprintln!("[SIGNAL] Failed to export performance metrics: {}", e);
        }
    }
}

/// Check if shutdown was requested
pub fn is_shutdown_requested() -> bool {
    SHUTDOWN_REQUESTED.load(Ordering::SeqCst)
}
