#!/bin/bash

# Aptos Local Testnet Startup Script with Performance Monitoring
# This script starts a local Aptos testnet for performance analysis

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APTOS_CORE_PATH="${APTOS_CORE_PATH:-$(pwd)}"
TESTNET_DIR="$HOME/.aptos/testnet"
VALIDATOR_COUNT=4
PERFORMANCE_LOG_DIR="$HOME/.aptos/performance_logs"
PERF_RECORD_TIME=60  # seconds

echo -e "${BLUE}=== Aptos Local Testnet Performance Testing Setup ===${NC}"
echo -e "${BLUE}Aptos Core Path: $APTOS_CORE_PATH${NC}"
echo -e "${BLUE}Testnet Directory: $TESTNET_DIR${NC}"
echo -e "${BLUE}Performance Logs: $PERFORMANCE_LOG_DIR${NC}"

# Check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    # Check if we're in aptos-core directory
    if [ ! -f "Cargo.toml" ] || [ ! -d "consensus" ] || [ ! -d "mempool" ]; then
        echo -e "${RED}Error: Please run this script from the aptos-core root directory${NC}"
        exit 1
    fi
    
    # Check if Rust is installed
    if ! command -v cargo &> /dev/null; then
        echo -e "${RED}Error: Cargo not found. Please install Rust${NC}"
        exit 1
    fi
    
    # Check if perf is available (Linux only)
    if command -v perf &> /dev/null; then
        echo -e "${GREEN}✓ perf found - flame graph generation will be available${NC}"
        PERF_AVAILABLE=true
    else
        echo -e "${YELLOW}⚠ perf not found - flame graph generation will be skipped${NC}"
        PERF_AVAILABLE=false
    fi
    
    # Check if FlameGraph tools are available
    if [ -d "FlameGraph" ] || command -v flamegraph.pl &> /dev/null; then
        echo -e "${GREEN}✓ FlameGraph tools found${NC}"
        FLAMEGRAPH_AVAILABLE=true
    else
        echo -e "${YELLOW}⚠ FlameGraph tools not found - will clone from GitHub${NC}"
        FLAMEGRAPH_AVAILABLE=false
    fi
    
    echo -e "${GREEN}Prerequisites check completed${NC}"
}

# Setup FlameGraph tools
setup_flamegraph_tools() {
    if [ "$FLAMEGRAPH_AVAILABLE" = false ]; then
        echo -e "${YELLOW}Setting up FlameGraph tools...${NC}"
        if [ ! -d "FlameGraph" ]; then
            git clone https://github.com/brendangregg/FlameGraph.git
        fi
        export PATH="$PWD/FlameGraph:$PATH"
        echo -e "${GREEN}✓ FlameGraph tools setup completed${NC}"
    fi
}

# Apply performance monitoring patches
apply_performance_patches() {
    echo -e "${YELLOW}Applying performance monitoring patches...${NC}"
    
    # Add performance_monitoring.rs to the appropriate location
    if [ -f "performance_monitoring.rs" ]; then
        cp performance_monitoring.rs mempool/src/
        
        # Add to mempool lib.rs
        if ! grep -q "pub mod performance_monitoring" mempool/src/lib.rs; then
            echo "pub mod performance_monitoring;" >> mempool/src/lib.rs
        fi
        
        # Add to consensus lib.rs (if exists)
        if [ -f "consensus/src/lib.rs" ] && ! grep -q "pub mod performance_monitoring" consensus/src/lib.rs; then
            echo "pub mod performance_monitoring;" >> consensus/src/lib.rs
        fi
    fi
    
    echo -e "${GREEN}✓ Performance monitoring setup completed${NC}"
}

# Build Aptos with performance monitoring
build_aptos() {
    echo -e "${YELLOW}Building Aptos with performance monitoring...${NC}"
    
    # Build with debug symbols for better profiling
    export RUSTFLAGS="-g -C force-frame-pointers=yes"
    
    cargo build --release --bin aptos-node
    cargo build --release --bin aptos
    
    echo -e "${GREEN}✓ Aptos build completed${NC}"
}

# Clean up previous testnet
cleanup_testnet() {
    echo -e "${YELLOW}Cleaning up previous testnet...${NC}"
    
    # Stop any running aptos-node processes
    pkill -f aptos-node || true
    sleep 2
    
    # Remove old testnet directory
    if [ -d "$TESTNET_DIR" ]; then
        rm -rf "$TESTNET_DIR"
    fi
    
    mkdir -p "$TESTNET_DIR"
    mkdir -p "$PERFORMANCE_LOG_DIR"
    
    echo -e "${GREEN}✓ Cleanup completed${NC}"
}

# Initialize testnet
init_testnet() {
    echo -e "${YELLOW}Initializing local testnet...${NC}"
    
    cd "$TESTNET_DIR"
    
    # Generate genesis and validator configs
    "$APTOS_CORE_PATH/target/release/aptos" genesis generate-genesis \
        --local-repository-dir . \
        --num-validators $VALIDATOR_COUNT \
        --output-dir .
    
    echo -e "${GREEN}✓ Testnet initialization completed${NC}"
}

# Start validator nodes with performance monitoring
start_validators() {
    echo -e "${YELLOW}Starting validator nodes...${NC}"
    
    cd "$TESTNET_DIR"
    
    for i in $(seq 0 $((VALIDATOR_COUNT - 1))); do
        echo -e "${BLUE}Starting validator $i...${NC}"
        
        # Create log directory for this validator
        mkdir -p "$PERFORMANCE_LOG_DIR/validator_$i"
        
        # Start validator with performance monitoring
        if [ "$PERF_AVAILABLE" = true ]; then
            # Start with perf recording
            perf record -g -o "$PERFORMANCE_LOG_DIR/validator_$i/perf.data" \
                "$APTOS_CORE_PATH/target/release/aptos-node" \
                -f "validator_$i.yaml" \
                > "$PERFORMANCE_LOG_DIR/validator_$i/node.log" 2>&1 &
        else
            # Start without perf
            "$APTOS_CORE_PATH/target/release/aptos-node" \
                -f "validator_$i.yaml" \
                > "$PERFORMANCE_LOG_DIR/validator_$i/node.log" 2>&1 &
        fi
        
        VALIDATOR_PIDS[$i]=$!
        echo -e "${GREEN}✓ Validator $i started (PID: ${VALIDATOR_PIDS[$i]})${NC}"
    done
    
    # Wait for nodes to start
    echo -e "${YELLOW}Waiting for nodes to start and sync...${NC}"
    sleep 10
    
    # Check if nodes are running
    for i in $(seq 0 $((VALIDATOR_COUNT - 1))); do
        if kill -0 ${VALIDATOR_PIDS[$i]} 2>/dev/null; then
            echo -e "${GREEN}✓ Validator $i is running${NC}"
        else
            echo -e "${RED}✗ Validator $i failed to start${NC}"
            cat "$PERFORMANCE_LOG_DIR/validator_$i/node.log"
        fi
    done
}

# Wait for network to be ready
wait_for_network() {
    echo -e "${YELLOW}Waiting for network to be ready...${NC}"
    
    # Try to get the ledger info
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s http://127.0.0.1:8080/v1 > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Network is ready!${NC}"
            return 0
        fi
        
        echo -e "${YELLOW}Attempt $attempt/$max_attempts - waiting for network...${NC}"
        sleep 2
        ((attempt++))
    done
    
    echo -e "${RED}✗ Network failed to become ready${NC}"
    return 1
}

# Create test accounts and fund them
setup_test_accounts() {
    echo -e "${YELLOW}Setting up test accounts...${NC}"
    
    cd "$APTOS_CORE_PATH"
    
    # Create sender account
    echo -e "${BLUE}Creating sender account...${NC}"
    ./target/release/aptos init --profile sender \
        --private-key 0x1111111111111111111111111111111111111111111111111111111111111111 \
        --rest-url http://127.0.0.1:8080 \
        --faucet-url http://127.0.0.1:8081 \
        --skip-faucet
    
    # Create receiver account  
    echo -e "${BLUE}Creating receiver account...${NC}"
    ./target/release/aptos init --profile receiver \
        --private-key 0x2222222222222222222222222222222222222222222222222222222222222222 \
        --rest-url http://127.0.0.1:8080 \
        --faucet-url http://127.0.0.1:8081 \
        --skip-faucet
    
    # Fund sender account
    echo -e "${BLUE}Funding sender account...${NC}"
    ./target/release/aptos account fund-with-faucet --profile sender \
        --rest-url http://127.0.0.1:8080 \
        --faucet-url http://127.0.0.1:8081 \
        --amount 1000000000
    
    # Get account addresses
    SENDER_ADDR=$(./target/release/aptos config show-profiles --profile sender | grep "account" | awk '{print $2}')
    RECEIVER_ADDR=$(./target/release/aptos config show-profiles --profile receiver | grep "account" | awk '{print $2}')
    
    echo -e "${GREEN}✓ Test accounts setup completed${NC}"
    echo -e "${BLUE}Sender address: $SENDER_ADDR${NC}"
    echo -e "${BLUE}Receiver address: $RECEIVER_ADDR${NC}"
}

# Generate performance report
generate_performance_report() {
    echo -e "${YELLOW}Generating performance report...${NC}"
    
    # Create performance analysis script
    cat > "$PERFORMANCE_LOG_DIR/analyze_performance.py" << 'EOF'
#!/usr/bin/env python3
import re
import sys
from datetime import datetime
from collections import defaultdict

def parse_performance_logs(log_file):
    """Parse performance logs and extract timing information"""
    stages = defaultdict(list)
    transactions = {}
    
    with open(log_file, 'r') as f:
        for line in f:
            if 'PERF_TRACK:' in line:
                # Extract timestamp, transaction hash, and stage info
                match = re.search(r'(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z).*PERF_TRACK: ([a-f0-9]+) - (\w+) at ([\d.]+[a-z]+)', line)
                if match:
                    timestamp, tx_hash, stage, duration = match.groups()
                    stages[stage].append(float(duration.replace('ms', '').replace('us', '').replace('s', '')))
                    
                    if tx_hash not in transactions:
                        transactions[tx_hash] = {}
                    transactions[tx_hash][stage] = duration
    
    return stages, transactions

def generate_report(stages, transactions):
    """Generate performance analysis report"""
    print("=== APTOS TRANSACTION PERFORMANCE ANALYSIS ===")
    print(f"Total transactions analyzed: {len(transactions)}")
    print()
    
    print("Stage-by-Stage Performance (all times in ms):")
    print("-" * 60)
    
    for stage, durations in stages.items():
        if durations:
            avg = sum(durations) / len(durations)
            min_dur = min(durations)
            max_dur = max(durations)
            
            print(f"{stage:25} | Count: {len(durations):4} | Avg: {avg:8.3f} | Min: {min_dur:8.3f} | Max: {max_dur:8.3f}")
    
    print()
    print("End-to-End Transaction Analysis:")
    print("-" * 40)
    
    end_to_end_times = []
    for tx_hash, stages_data in transactions.items():
        if 'mempool_received' in stages_data and 'chain_committed' in stages_data:
            # Calculate end-to-end time
            start_time = float(stages_data['mempool_received'].replace('ms', ''))
            end_time = float(stages_data['chain_committed'].replace('ms', ''))
            e2e_time = end_time - start_time
            end_to_end_times.append(e2e_time)
    
    if end_to_end_times:
        avg_e2e = sum(end_to_end_times) / len(end_to_end_times)
        min_e2e = min(end_to_end_times)
        max_e2e = max(end_to_end_times)
        
        print(f"End-to-End Average: {avg_e2e:.3f} ms")
        print(f"End-to-End Min:     {min_e2e:.3f} ms") 
        print(f"End-to-End Max:     {max_e2e:.3f} ms")
        
        # Calculate percentiles
        sorted_times = sorted(end_to_end_times)
        p50 = sorted_times[len(sorted_times) // 2]
        p95 = sorted_times[int(len(sorted_times) * 0.95)]
        p99 = sorted_times[int(len(sorted_times) * 0.99)]
        
        print(f"End-to-End P50:     {p50:.3f} ms")
        print(f"End-to-End P95:     {p95:.3f} ms")
        print(f"End-to-End P99:     {p99:.3f} ms")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 analyze_performance.py <log_file>")
        sys.exit(1)
    
    log_file = sys.argv[1]
    stages, transactions = parse_performance_logs(log_file)
    generate_report(stages, transactions)
EOF
    
    chmod +x "$PERFORMANCE_LOG_DIR/analyze_performance.py"
    
    # Combine all validator logs
    cat "$PERFORMANCE_LOG_DIR"/validator_*/node.log > "$PERFORMANCE_LOG_DIR/combined_logs.txt"
    
    # Run performance analysis
    python3 "$PERFORMANCE_LOG_DIR/analyze_performance.py" "$PERFORMANCE_LOG_DIR/combined_logs.txt" > "$PERFORMANCE_LOG_DIR/performance_report.txt"
    
    echo -e "${GREEN}✓ Performance report generated: $PERFORMANCE_LOG_DIR/performance_report.txt${NC}"
}

# Generate flame graphs
generate_flame_graphs() {
    if [ "$PERF_AVAILABLE" = false ]; then
        echo -e "${YELLOW}Skipping flame graph generation - perf not available${NC}"
        return
    fi
    
    echo -e "${YELLOW}Generating flame graphs...${NC}"
    
    for i in $(seq 0 $((VALIDATOR_COUNT - 1))); do
        local perf_data="$PERFORMANCE_LOG_DIR/validator_$i/perf.data"
        local flamegraph_svg="$PERFORMANCE_LOG_DIR/validator_$i/flamegraph.svg"
        
        if [ -f "$perf_data" ]; then
            echo -e "${BLUE}Generating flame graph for validator $i...${NC}"
            
            # Convert perf data to flame graph
            perf script -i "$perf_data" | FlameGraph/stackcollapse-perf.pl | FlameGraph/flamegraph.pl > "$flamegraph_svg"
            
            echo -e "${GREEN}✓ Flame graph generated: $flamegraph_svg${NC}"
        fi
    done
}

# Stop validators
stop_validators() {
    echo -e "${YELLOW}Stopping validator nodes...${NC}"
    
    for i in $(seq 0 $((VALIDATOR_COUNT - 1))); do
        if [ -n "${VALIDATOR_PIDS[$i]}" ] && kill -0 ${VALIDATOR_PIDS[$i]} 2>/dev/null; then
            kill ${VALIDATOR_PIDS[$i]}
            echo -e "${GREEN}✓ Validator $i stopped${NC}"
        fi
    done
    
    # Wait for processes to terminate
    sleep 2
    
    # Force kill if necessary
    pkill -f aptos-node || true
}

# Main execution
main() {
    declare -a VALIDATOR_PIDS
    
    # Setup signal handlers
    trap 'echo -e "${RED}Interrupted! Stopping validators...${NC}"; stop_validators; exit 1' INT TERM
    
    check_prerequisites
    setup_flamegraph_tools
    apply_performance_patches
    build_aptos
    cleanup_testnet
    init_testnet
    start_validators
    
    if wait_for_network; then
        setup_test_accounts
        
        echo -e "${GREEN}=== Local testnet is ready! ===${NC}"
        echo -e "${BLUE}REST API: http://127.0.0.1:8080${NC}"
        echo -e "${BLUE}Faucet: http://127.0.0.1:8081${NC}"
        echo -e "${BLUE}Sender: $SENDER_ADDR${NC}"
        echo -e "${BLUE}Receiver: $RECEIVER_ADDR${NC}"
        echo
        echo -e "${YELLOW}You can now run transfer transactions using the send_transfer.sh script${NC}"
        echo -e "${YELLOW}Press Ctrl+C to stop the testnet and generate performance reports${NC}"
        
        # Keep running until interrupted
        wait
    else
        echo -e "${RED}Failed to start testnet${NC}"
        stop_validators
        exit 1
    fi
}

# Cleanup function
cleanup() {
    echo -e "${YELLOW}Cleaning up and generating reports...${NC}"
    stop_validators
    generate_performance_report
    generate_flame_graphs
    echo -e "${GREEN}Performance analysis completed!${NC}"
    echo -e "${BLUE}Check results in: $PERFORMANCE_LOG_DIR${NC}"
}

# Set cleanup trap
trap cleanup EXIT

# Run main function
main "$@"
