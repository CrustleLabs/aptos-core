#!/bin/bash

# Aptos Performance Monitoring Example
# This script demonstrates how to use the performance monitoring system

set -e

echo "=== Aptos Performance Monitoring Example ==="
echo

# Step 1: Build Aptos with performance monitoring
echo "Step 1: Building Aptos with performance monitoring..."
export RUSTFLAGS="-g -C force-frame-pointers=yes"
cargo build --release --bin aptos-node --bin aptos

echo "✓ Build completed"
echo

# Step 2: Start a simple local testnet
echo "Step 2: Starting local testnet..."
# Note: This would require the full testnet setup
echo "  (In a real scenario, you would start the testnet here)"
echo "  Example: ./start_local_testnet.sh"
echo

# Step 3: Monitor performance
echo "Step 3: Performance monitoring is now active"
echo "  The following stages will be tracked for each transaction:"
echo "  - mempool_received: Transaction enters mempool"
echo "  - mempool_validation: VM validates transaction"
echo "  - mempool_added: Transaction added to mempool"
echo "  - payload_pull: Leader pulls transactions"
echo "  - proposal_generation: Block proposal created"
echo "  - block_prepare: Block preparation"
echo "  - transaction_execution: Individual transaction execution"
echo "  - vote_generation: Vote creation"
echo "  - block_commit: Block commitment"
echo "  - chain_committed: Final chain commitment"
echo

# Step 4: Example of how logs would look
echo "Step 4: Example performance logs:"
echo "  PERF_TRACK: Started tracking transaction 0xabc123... from sender 0xdef456..."
echo "  PERF_TRACK: 0xabc123... - mempool_received at 1.234ms (total: 1.234ms)"
echo "  PERF_TRACK: 0xabc123... - mempool_validation at 5.678ms (total: 6.912ms)"
echo "  PERF_TRACK: 0xabc123... - payload_pull at 15.234ms (total: 22.146ms)"
echo "  PERF_TRACK: 0xabc123... - transaction_execution at 18.567ms (total: 40.713ms)"
echo "  PERF_TRACK: 0xabc123... - chain_committed at 85.234ms (total: 125.947ms)"
echo "  PERF_TRACK: Transaction 0xabc123... completed in 125.947ms"
echo

# Step 5: Generate performance report
echo "Step 5: Performance report generation:"
echo "  The system automatically generates reports showing:"
echo "  - End-to-end transaction latency statistics"
echo "  - Per-stage timing breakdown"
echo "  - Percentile analysis (P50, P95, P99)"
echo "  - Performance bottleneck identification"
echo

echo "=== Example Performance Report ==="
cat << 'EOF'
=== APTOS TRANSACTION PERFORMANCE REPORT ===
Total Completed: 100
Total Active: 5

End-to-End Performance:
  Count: 100
  Min: 45.2ms
  Max: 234.7ms
  Avg: 87.3ms
  P50: 82.1ms
  P95: 156.8ms
  P99: 203.4ms

Stage-by-Stage Performance:
  mempool_received (100 samples):
    Min: 0.1ms, Max: 2.3ms, Avg: 0.8ms
    P50: 0.7ms, P95: 1.2ms, P99: 2.1ms
  
  mempool_validation (100 samples):
    Min: 2.1ms, Max: 15.7ms, Avg: 4.2ms
    P50: 3.8ms, P95: 7.8ms, P99: 12.3ms
  
  payload_pull (100 samples):
    Min: 5.2ms, Max: 28.4ms, Avg: 8.7ms
    P50: 7.9ms, P95: 15.2ms, P99: 22.1ms
  
  transaction_execution (100 samples):
    Min: 0.8ms, Max: 8.3ms, Avg: 1.8ms
    P50: 1.5ms, P95: 3.2ms, P99: 5.7ms
  
  vote_generation (100 samples):
    Min: 1.2ms, Max: 9.1ms, Avg: 2.3ms
    P50: 2.0ms, P95: 4.1ms, P99: 7.2ms
  
  block_commit (25 samples):
    Min: 8.7ms, Max: 52.3ms, Avg: 15.7ms
    P50: 13.2ms, P95: 28.3ms, P99: 41.2ms

=== END PERFORMANCE REPORT ===
EOF

echo
echo "=== Integration Instructions ==="
echo "To integrate this performance monitoring into your Aptos setup:"
echo
echo "1. Copy the performance monitoring module:"
echo "   cp performance_monitoring.rs mempool/src/"
echo "   echo 'pub mod performance_monitoring;' >> mempool/src/lib.rs"
echo
echo "2. Apply the code changes shown in the patch files:"
echo "   - mempool_performance_hooks.patch"
echo "   - consensus_performance_hooks.patch"
echo "   - vm_performance_hooks.patch"
echo
echo "3. Build with performance monitoring enabled:"
echo "   export RUSTFLAGS='-g -C force-frame-pointers=yes'"
echo "   cargo build --release"
echo
echo "4. Start your testnet and observe the PERF_TRACK logs"
echo
echo "5. For flame graph generation (Linux only):"
echo "   sudo apt-get install linux-tools-generic"
echo "   sudo sysctl kernel.perf_event_paranoid=1"
echo "   perf record -g -F 99 ./target/release/aptos-node ..."
echo "   perf script | FlameGraph/stackcollapse-perf.pl | FlameGraph/flamegraph.pl > flamegraph.svg"
echo
echo "=== Performance Targets ==="
echo "Recommended performance targets for optimal operation:"
echo "- End-to-end transaction latency: < 100ms"
echo "- Mempool processing: < 10ms"
echo "- Transaction execution: < 5ms"
echo "- Consensus (vote generation): < 10ms"
echo "- Block commitment: < 50ms"
echo
echo "Performance monitoring setup completed!"
echo "Monitor your logs for PERF_TRACK entries to analyze transaction performance."
