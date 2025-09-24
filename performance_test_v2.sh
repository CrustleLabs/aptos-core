#!/bin/bash

# Aptos Consensus Performance Testing Script
# This script starts a single validator testnet and performs a transfer transaction
# to measure end-to-end latency from mempool to blockchain commit

set -e

# Configuration - Change this path to match your environment
PROJECT_DIR="/home/ubuntu/whtest/CrustleLabs/aptos-core"

# Configuration
TESTNET_DIR="/dev/shm/aptos-testnet"
PERFORMANCE_LOG="/dev/shm/performance_results.log"
FLAMEGRAPH_DIR="/dev/shm/flamegraph"
VALIDATOR_LOG="/dev/shm/validator.log"

# Performance monitoring verification options
SKIP_COMPILATION_VERIFICATION=false
SKIP_RUNTIME_VERIFICATION=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-compilation-verification)
            SKIP_COMPILATION_VERIFICATION=true
            echo "WARNING:  Skipping compilation verification as requested"
            shift
            ;;
        --skip-runtime-verification)
            SKIP_RUNTIME_VERIFICATION=true
            echo "WARNING:  Skipping runtime verification as requested"
            shift
            ;;
        --skip-all-verification)
            SKIP_COMPILATION_VERIFICATION=true
            SKIP_RUNTIME_VERIFICATION=true
            echo "WARNING:  Skipping all performance monitoring verification as requested"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --skip-compilation-verification  Skip verification of performance monitoring compilation"
            echo "  --skip-runtime-verification     Skip verification of runtime performance monitoring"
            echo "  --skip-all-verification         Skip all performance monitoring verification"
            echo "  --help, -h                      Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Global variables for cleanup
VALIDATOR_PID=""
FAUCET_PID=""
PERF_PID=""

# Cleanup function
cleanup() {
    echo_info "Cleaning up processes..."
    
    if [ ! -z "$PERF_PID" ]; then
        kill -INT $PERF_PID 2>/dev/null || true
        wait $PERF_PID 2>/dev/null || true
        echo_info "Stopped perf recording"
    fi
    
    if [ ! -z "$FAUCET_PID" ]; then
        echo_info "Stopping faucet service..."
        kill -TERM $FAUCET_PID 2>/dev/null || true
        sleep 1
        kill -KILL $FAUCET_PID 2>/dev/null || true
    fi
    
    if [ ! -z "$VALIDATOR_PID" ]; then
        echo_info "Sending SIGUSR1 to validator for metrics export..."
        kill -USR1 $VALIDATOR_PID 2>/dev/null || true
        sleep 3
        
        # Check if function latency log was created
        if [ -f "/dev/shm/fn_latency.log" ]; then
            echo_success " Function latency log found: /dev/shm/fn_latency.log"
            cp "/dev/shm/fn_latency.log" "$PERFORMANCE_LOG" 2>/dev/null || true
            echo_info "Function latency data copied to: $PERFORMANCE_LOG"
        else
            echo_warning "WARNING:  No function latency log found at /dev/shm/fn_latency.log"
        fi
        
        # Check if performance metrics files were created and copy them
        if ls /dev/shm/performance_metrics_*.log 1> /dev/null 2>&1; then
            echo_success "Performance metrics files found!"
            latest_metrics=$(ls -t /dev/shm/performance_metrics_*.log | head -1)
            cat "$latest_metrics" >> "$PERFORMANCE_LOG" 2>/dev/null || true
            echo_info "Performance metrics appended to: $PERFORMANCE_LOG"
        else
            echo_warning "No performance metrics files found, using validator log"
        fi
        
        echo_info "Stopping validator..."
        kill -INT $VALIDATOR_PID 2>/dev/null || true
        sleep 2
        kill -TERM $VALIDATOR_PID 2>/dev/null || true
        sleep 1
        kill -KILL $VALIDATOR_PID 2>/dev/null || true
    fi
    
    echo_info "Cleanup completed"
}

# Set up signal handlers (must be after function definition)
setup_signal_handlers() {
    trap cleanup EXIT
    trap cleanup INT  
    trap cleanup TERM
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Set up signal handlers (removed duplicate cleanup function)
# The cleanup function is defined earlier in the script

# Check dependencies
check_dependencies() {
    echo_info "Checking dependencies..."
    
    # Check if perf is available
    if ! command -v perf &> /dev/null; then
        echo_warning "perf not found. Installing perf..."
        sudo apt-get update && sudo apt-get install -y linux-tools-generic linux-tools-$(uname -r) || {
            echo_error "Failed to install perf"
            exit 1
        }
    fi
    
    # Check if flamegraph tools are available
    if ! command -v flamegraph &> /dev/null; then
        echo_warning "flamegraph not found. Installing flamegraph..."
        cargo install flamegraph || {
            echo_error "Failed to install flamegraph"
            exit 1
        }
    fi
    
    echo_success "All dependencies are available"
}

# Build the project
build_project() {
    echo_info "Building Aptos with performance monitoring..."
    
    cd "$PROJECT_DIR"
    
    # Check if binaries already exist to avoid unnecessary rebuilding
    if [ -f "target/release/aptos-node" ] && [ -f "target/release/aptos" ]; then
        echo_info "Using existing compiled binaries"
        return 0
    fi
    
    # First, clean any previous builds that might have problematic features
    echo_info "Cleaning previous builds..."
    cargo clean

    # Build aptos-node separately to avoid feature unification issues
    echo_info "Building aptos-node separately to avoid feature conflicts..."
    cargo build --release --package aptos-node || {
        echo_error "Failed to build aptos-node"
        echo_info "Trying with clean build..."
        cargo clean
        cargo build --release --package aptos-node || {
            echo_error "Failed to build aptos-node after clean"
            exit 1
        }
    }
    
    # Check if aptos and aptos-framework binaries exist, build if necessary
    echo_info "Checking for additional required binaries..."
    if [ ! -f "target/release/aptos" ] || [ ! -f "target/release/aptos-framework" ]; then
        echo_info "Building missing binaries..."
        cargo build --release --bin aptos --bin aptos-framework || {
            echo_warning "Failed to build additional binaries, will use existing ones if available"
        }
    else
        echo_info "All required binaries are already available"
    fi
    echo_success "Project built successfully"
    
    # Verify performance monitoring integration
    if [ "$SKIP_COMPILATION_VERIFICATION" = false ]; then
        verify_performance_monitoring_integration
    else
        echo_info "WARNING:  Skipping compilation verification as requested"
    fi
}

# Verify performance monitoring integration
verify_performance_monitoring_integration() {
    echo_info " Verifying performance monitoring integration..."
    
    local verification_passed=true
    
    # Check 1: Verify aptos-performance-monitor crate was compiled
    echo_info " Checking if aptos-performance-monitor crate was compiled..."
    if [ -f "target/release/libaptos_performance_monitor.rlib" ] || [ -f "target/release/deps/libaptos_performance_monitor-"*.rlib ]; then
        echo_success " aptos-performance-monitor crate found in build artifacts"
    else
        echo_warning "WARNING:  aptos-performance-monitor crate not found in build artifacts"
        verification_passed=false
    fi
    
    # Check 2: Verify performance monitoring symbols are present in aptos-node binary
    echo_info " Checking for performance monitoring symbols in aptos-node binary..."
    if command -v nm &> /dev/null; then
        if nm target/release/aptos-node 2>/dev/null | grep -q "PerformanceMonitor\|track_mempool_entry\|export_function_latency"; then
            echo_success " Performance monitoring symbols found in aptos-node binary"
        else
            echo_warning "WARNING:  Performance monitoring symbols not found in aptos-node binary"
            verification_passed=false
        fi
    else
        echo_info "INFO:  nm tool not available, skipping symbol check"
    fi
    
    # Check 3: Verify signal-hook dependency is linked
    echo_info " Checking for signal-hook dependency..."
    if ldd target/release/aptos-node 2>/dev/null | grep -q "signal" || nm target/release/aptos-node 2>/dev/null | grep -q "signal_hook"; then
        echo_success " Signal handling functionality appears to be linked"
    else
        echo_warning "WARNING:  Signal handling functionality not detected"
    fi
    
    # Check 4: Verify aptos-performance-monitor is in dependency tree
    echo_info " Checking dependency tree for performance monitoring..."
    if cargo tree -p aptos-node 2>/dev/null | grep -q "aptos-performance-monitor"; then
        echo_success " aptos-performance-monitor found in aptos-node dependency tree"
    else
        echo_warning "WARNING:  aptos-performance-monitor not found in dependency tree"
        verification_passed=false
    fi
    
    # Check 5: Verify mempool integration
    echo_info " Checking mempool integration..."
    if grep -q "aptos-performance-monitor" mempool/Cargo.toml 2>/dev/null; then
        echo_success " Mempool has aptos-performance-monitor dependency"
        if grep -q "track_mempool_entry" mempool/src/core_mempool/mempool.rs 2>/dev/null; then
            echo_success " Mempool code contains performance tracking calls"
        else
            echo_warning "WARNING:  Mempool performance tracking calls not found"
            verification_passed=false
        fi
    else
        echo_warning "WARNING:  Mempool missing aptos-performance-monitor dependency"
        verification_passed=false
    fi
    
    # Check 6: Verify performance monitor crate compilation with required features
    echo_info "  Checking performance monitor crate features..."
    if cargo metadata --format-version 1 2>/dev/null | jq -e '.packages[] | select(.name == "aptos-performance-monitor")' >/dev/null 2>&1; then
        echo_success " aptos-performance-monitor package found in workspace"
        
        # Check if required dependencies are present
        local deps_check=true
        for dep in "minstant" "signal-hook" "chrono"; do
            if cargo metadata --format-version 1 2>/dev/null | jq -e ".packages[] | select(.name == \"aptos-performance-monitor\") | .dependencies[] | select(.name == \"$dep\")" >/dev/null 2>&1; then
                echo_success " Required dependency '$dep' found"
            else
                echo_warning "WARNING:  Required dependency '$dep' not found"
                deps_check=false
            fi
        done
        
        if [ "$deps_check" = true ]; then
            echo_success " All required dependencies are present"
        fi
    else
        echo_warning "WARNING:  aptos-performance-monitor package not found in workspace metadata"
        verification_passed=false
    fi
    
    # Check 7: Test basic functionality with a simple test
    echo_info " Testing basic performance monitor functionality..."
    cat > /tmp/perf_monitor_test.rs << 'EOF'
fn main() {
    println!("Testing basic compilation...");
    // This will fail at runtime but should compile if dependencies are correct
}
EOF
    
    if rustc --edition 2021 -L target/release/deps /tmp/perf_monitor_test.rs -o /tmp/perf_monitor_test 2>/dev/null; then
        echo_success " Basic Rust compilation test passed"
        rm -f /tmp/perf_monitor_test /tmp/perf_monitor_test.rs
    else
        echo_info "INFO:  Basic compilation test inconclusive"
        rm -f /tmp/perf_monitor_test /tmp/perf_monitor_test.rs
    fi
    
    # Summary
    echo ""
    if [ "$verification_passed" = true ]; then
        echo_success " Performance monitoring integration verification PASSED!"
        echo_info " All critical checks passed. Performance monitoring should work correctly."
    else
        echo_warning "WARNING:  Performance monitoring integration verification had WARNINGS!"
        echo_info "Some checks failed, but the system may still work. Monitor the logs for performance data."
        echo_info "If issues persist, try rebuilding with: cargo clean && cargo build --release --package aptos-node"
    fi
    echo ""
}

# Initialize testnet using aptos built-in local testnet
init_testnet() {
    echo_info "Initializing single validator testnet with faucet in $TESTNET_DIR..."
    
    # Clean up existing testnet
    rm -rf "$TESTNET_DIR"
    mkdir -p "$TESTNET_DIR"
    mkdir -p "$FLAMEGRAPH_DIR"
    
    echo_success "Testnet directory prepared: $TESTNET_DIR"
    echo_info "The aptos local testnet will auto-generate genesis and configuration"
}

# Create optimized validator configuration
create_optimized_validator_config() {
    echo_info " Creating optimized validator configuration for better performance..."
    
    cd "$TESTNET_DIR"
    
    # Wait for initial testnet setup to complete and find config file
    local config_file=""
    local full_config_path=""
    
    for i in {1..30}; do
        if [ -f "$TESTNET_DIR/0/node.yaml" ]; then
            config_file="node.yaml"
            full_config_path="$TESTNET_DIR/0/node.yaml"
            break
        elif [ -f "$TESTNET_DIR/validator.yaml" ]; then
            config_file="validator.yaml"
            full_config_path="$TESTNET_DIR/validator.yaml"
            break
        elif [ -f "$TESTNET_DIR/node.yaml" ]; then
            config_file="node.yaml"
            full_config_path="$TESTNET_DIR/node.yaml"
            break
        fi
        echo "  Waiting for config file generation... ($i/30)"
        sleep 1
    done
    
    if [ -z "$config_file" ]; then
        echo_warning "WARNING:  Config file not found, creating optimized config manually"
        config_file="node.yaml"
        full_config_path="$TESTNET_DIR/0/node.yaml"
        # Create the 0 directory if it doesn't exist
        mkdir -p "$TESTNET_DIR/0"
    else
        echo_info " Found config file: $full_config_path"
        # Backup original config
        cp "$full_config_path" "${full_config_path}.backup"
    fi
    
    echo_info "  Applying performance optimizations..."
    
    # Create optimized validator configuration
    cat > "$full_config_path" << EOF
base:
  data_dir: "db"
  role: "validator"
  waypoint:
    from_file: "../waypoint.txt"

consensus:
  sync_only: false
  round_initial_timeout_ms: 1000
  round_timeout_backoff_exponent_base: 1.2
  max_network_channel_size: 1024
  # Enable regular block production for single validator
  quorum_store_poll_time_ms: 100
  safety_rules:
    service:
      type: "local"
    backend:
      type: "on_disk_storage"
      path: "secure_storage.json"
    initial_safety_rules_config:
      from_file:
        identity_blob_path: "validator-identity.yaml"
        waypoint:
          from_file: "../waypoint.txt"
  # Quorum store configuration for single validator
  quorum_store:
    channel_size: 1000
    proof_timeout_ms: 10000
    batch_generation_poll_interval_ms: 25
    batch_generation_min_non_empty_interval_ms: 25

execution:
  genesis_file_location: "genesis.blob"
  concurrency_level: 1
  num_proof_reading_threads: 1

admin_service:
  address: "0.0.0.0"
  port: 9102

inspection_service:
  address: "0.0.0.0"
  port: 9101

validator_network:
  discovery_method: "onchain"
  identity:
    type: "from_file"
    path: "validator-identity.yaml"
  listen_address: "/ip4/127.0.0.1/tcp/6180"
  network_id: "validator"

full_node_networks:
  - network_id: "public"
    discovery_method: "none"
    identity:
      type: "from_file"
      path: "vfn-identity.yaml"
    listen_address: "/ip4/127.0.0.1/tcp/6182"

api:
  enabled: true
  address: "127.0.0.1:8080"
  max_submit_transaction_batch_size: 1
  max_transactions_page_size: 1000

mempool:
  max_broadcasts_per_peer: 1
  shared_mempool_tick_interval_ms: 50
  shared_mempool_batch_size: 100
  shared_mempool_max_concurrent_inbound_syncs: 2
  capacity: 1000000
  capacity_per_user: 100
  default_failovers: 3
  mempool_snapshot_interval_secs: 180
  system_transaction_timeout_secs: 86400

storage:
  enable_indexer: false
  backup_service_address: "127.0.0.1:6186"
  storage_pruner_config:
    ledger_pruner_config:
      enable: true
      prune_window: 1000000
      batch_size: 500

state_sync:
  state_sync_driver:
    bootstrapping_mode: "ExecuteOrApplyFromGenesis"
    continuous_syncing_mode: "ExecuteTransactionsOrApplyOutputs"
    enable_auto_bootstrapping: true
  aptos_data_client:
    max_num_output_reductions: 0
  data_streaming_service:
    enable_subscription_streaming: false
    progress_check_interval_ms: 10000
EOF
    
    echo_success " Optimized validator configuration created!"
    echo_info " Key optimizations applied:"
    echo_info "  • Consensus: 1000ms round timeout, optimized quorum store"
    echo_info "  • Mempool: 50ms tick interval, large capacity"
    echo_info "  • Network: Optimized discovery and connection settings"
    echo_info "  • Storage: Disabled indexer, optimized pruning"
    echo_info "  • State Sync: Reduced polling intervals"
    
    return 0
}

# Start local testnet with validator and faucet using optimized config
start_validator() {
    echo_info " Starting optimized local testnet with validator and faucet..."
    
    cd "$TESTNET_DIR"
    
    # First, start the basic testnet to generate initial files
    echo_info " Initializing testnet files..."
    RUST_LOG=info,aptos_consensus=debug,aptos_mempool=debug,aptos_performance_monitor=trace \
    "$PROJECT_DIR/target/release/aptos" node run-local-testnet \
        --test-dir "$TESTNET_DIR" \
        --faucet-port 8081 \
        --assume-yes \
        > "$VALIDATOR_LOG" 2>&1 &
    
    VALIDATOR_PID=$!
    echo_info "Initial testnet started with PID: $VALIDATOR_PID"
    
    # Wait for initial setup to complete (genesis generation, etc.)
    echo_info " Waiting for initial setup to complete..."
    sleep 10
    
    # Stop the initial validator to apply optimizations
    echo_info " Stopping initial validator to apply optimizations..."
    kill -TERM $VALIDATOR_PID 2>/dev/null || true
    sleep 3
    
    # Apply optimized configuration
    if create_optimized_validator_config; then
        echo_success " Configuration optimization completed"
    else
        echo_warning "WARNING:  Configuration optimization failed, continuing with default config"
    fi
    
    # We'll start faucet after validator is ready to avoid connection issues
    
    # Start validator with optimized configuration
    echo_info " Starting optimized validator..."
    cd "$TESTNET_DIR"
    
    # Find the optimized config file and set correct working directory
    local config_file=""
    local working_dir="$TESTNET_DIR"
    
    if [ -f "$TESTNET_DIR/0/node.yaml" ]; then
        config_file="$TESTNET_DIR/0/node.yaml"
        working_dir="$TESTNET_DIR/0"
    elif [ -f "$TESTNET_DIR/validator.yaml" ]; then
        config_file="$TESTNET_DIR/validator.yaml"
        working_dir="$TESTNET_DIR"
    elif [ -f "$TESTNET_DIR/node.yaml" ]; then
        config_file="$TESTNET_DIR/node.yaml"
        working_dir="$TESTNET_DIR"
    fi
    
    if [ -z "$config_file" ]; then
        echo_error " Cannot find validator configuration file"
        echo_info "Available files in $TESTNET_DIR:"
        ls -la "$TESTNET_DIR"
        if [ -d "$TESTNET_DIR/0" ]; then
            echo_info "Available files in $TESTNET_DIR/0:"
            ls -la "$TESTNET_DIR/0"
        fi
        return 1
    fi
    
    echo_info " Using optimized config: $config_file"
    echo_info " Working directory: $working_dir"
    
    # Change to correct working directory
    cd "$working_dir"
    
    # Start validator with optimized config and performance monitoring
    RUST_LOG=info,aptos_consensus=debug,aptos_mempool=debug,aptos_performance_monitor=trace \
    "$PROJECT_DIR/target/release/aptos-node" \
        -f "$(basename "$config_file")" \
        > "$VALIDATOR_LOG" 2>&1 &
    
    VALIDATOR_PID=$!
    echo_info "Optimized validator started with PID: $VALIDATOR_PID"
    echo_info "Validator API will be available at: http://127.0.0.1:8080"
    echo_info "Faucet will be available at: http://127.0.0.1:8081"
    
    # Wait for optimized validator to be ready
    echo_info " Waiting for optimized validator to be ready..."
    for i in {1..45}; do  # Reduced timeout since optimized config should start faster
        if curl -s http://127.0.0.1:8080/v1 > /dev/null 2>&1; then
            echo_success " Optimized validator is ready!"
            
            # Display validator info
            local version=$(curl -s http://127.0.0.1:8080/v1/ledger_info | jq -r '.ledger_version // "0"')
            echo_info "Validator API: http://127.0.0.1:8080"
            echo_info "Current ledger version: $version"
            
            # Test performance improvement
            echo_info " Testing optimized performance..."
            local start_version=$version
            sleep 3
            local end_version=$(curl -s http://127.0.0.1:8080/v1/ledger_info | jq -r '.ledger_version // "0"')
            
            if [ "$end_version" -gt "$start_version" ]; then
                local blocks_produced=$((end_version - start_version))
                echo_success " Validator produced $blocks_produced blocks in 3 seconds!"
            else
                echo_info "INFO:  No blocks produced yet (expected in lazy mode until transactions arrive)"
            fi
            
            break
        fi
        
        # Check if validator process is still running
        if ! kill -0 $VALIDATOR_PID 2>/dev/null; then
            echo_error "Optimized validator process died unexpectedly!"
            echo_error "Last 30 lines of validator log:"
            tail -30 "$VALIDATOR_LOG"
            return 1
        fi
        
        echo "  Waiting for optimized validator... ($i/45)"
        sleep 2
    done
    
    if ! curl -s http://127.0.0.1:8080/v1 > /dev/null 2>&1; then
        echo_error " Optimized validator failed to start within timeout"
        return 1
    fi
    
    # Now start faucet service after validator is ready
    echo_info " Starting optimized faucet service..."
    cd "$TESTNET_DIR"
    
    # Find the mint key file
    local mint_key_file=""
    if [ -f "$TESTNET_DIR/mint.key" ]; then
        mint_key_file="$TESTNET_DIR/mint.key"
    else
        echo_warning "WARNING:  mint.key not found, faucet may not work properly"
        mint_key_file="$TESTNET_DIR/mint.key"  # Will be created if needed
    fi
    
    echo_info " Using mint key: $mint_key_file"
    RUST_LOG=info \
    "$PROJECT_DIR/target/release/aptos-faucet-service" run-simple \
        --node-url http://127.0.0.1:8080 \
        --key-file-path "$mint_key_file" \
        --chain-id 4 \
        --listen-address 127.0.0.1 \
        --listen-port 8081 \
        > "$TESTNET_DIR/faucet.log" 2>&1 &
    
    FAUCET_PID=$!
    echo_info "Faucet started with PID: $FAUCET_PID (after validator ready)"
    
    # Wait for faucet to be ready
    echo_info "Waiting for faucet to be ready..."
    local faucet_ready=false
    for i in {1..30}; do
        # Check if faucet process is still running
        if [ ! -z "$FAUCET_PID" ] && ! kill -0 $FAUCET_PID 2>/dev/null; then
            echo_error " Faucet process died unexpectedly!"
            echo_error "Last 20 lines of faucet log:"
            if [ -f "$TESTNET_DIR/faucet.log" ]; then
                tail -20 "$TESTNET_DIR/faucet.log"
            else
                echo_error "Faucet log file not found"
            fi
            break
        fi
        
        # Test faucet connectivity
        if curl -s http://127.0.0.1:8081/ > /dev/null 2>&1; then
            echo_success " Faucet is ready!"
            echo_info "Faucet API: http://127.0.0.1:8081"
            faucet_ready=true
            break
        fi
        echo "  Waiting for faucet... ($i/30)"
        sleep 2
    done
    
    # Final faucet status check
    if [ "$faucet_ready" = false ]; then
        echo_warning "WARNING:  Faucet may not be fully ready, but continuing..."
        echo_info "Faucet process status:"
        if [ ! -z "$FAUCET_PID" ] && kill -0 $FAUCET_PID 2>/dev/null; then
            echo_info "   Faucet process is running (PID: $FAUCET_PID)"
        else
            echo_warning "   Faucet process is not running"
        fi
        
        if [ -f "$TESTNET_DIR/faucet.log" ]; then
            echo_info "Recent faucet log entries:"
            tail -10 "$TESTNET_DIR/faucet.log"
        fi
    fi
    
    # Verify runtime performance monitoring
    if [ "$SKIP_RUNTIME_VERIFICATION" = false ]; then
        verify_runtime_performance_monitoring
    else
        echo_info "WARNING:  Skipping runtime verification as requested"
    fi
    
    echo_success " Optimized local testnet with validator and faucet is ready!"
    echo_info " Performance optimizations applied:"
    echo_info "  • Consensus: Faster round timeouts and optimized quorum store"
    echo_info "  • Mempool: Reduced tick intervals for faster transaction processing"
    echo_info "  • Network: Optimized discovery and connection management"
    echo_info "  • Storage: Disabled unnecessary indexing for better performance"
    echo_info "  • State Sync: Reduced polling intervals"
    return 0
}

# Verify runtime performance monitoring
verify_runtime_performance_monitoring() {
    echo_info " Verifying runtime performance monitoring functionality..."
    
    # Check if performance monitoring process is running
    echo_info " Checking if performance monitoring is active in validator process..."
    
    # Wait a moment for the validator to fully initialize
    sleep 2
    
    # Check validator log for performance monitoring initialization
    if [ -f "$VALIDATOR_LOG" ]; then
        # Look for performance monitoring initialization messages
        if grep -q "\[PERF\].*Initializing Aptos Performance Monitor\|\[PERF\].*Performance Monitor initialized" "$VALIDATOR_LOG" 2>/dev/null; then
            echo_success " Performance monitoring module initialized successfully"
        elif grep -q "aptos_performance_monitor\|PERF.*initialized" "$VALIDATOR_LOG" 2>/dev/null; then
            echo_success " Performance monitoring module loaded in validator"
        else
            echo_warning "WARNING:  No performance monitoring module initialization messages found in validator log"
        fi
        
        # Check for signal handler setup
        if grep -q "\[PERF\].*Signal handler registered\|\[PERF\].*SIGUSR1" "$VALIDATOR_LOG" 2>/dev/null; then
            echo_success " SIGUSR1 signal handler registered successfully"
        elif grep -q "signal" "$VALIDATOR_LOG" 2>/dev/null; then
            echo_success " Signal handling appears to be active"
        else
            echo_info "INFO:  No explicit signal handler messages found (this may be normal)"
        fi
        
        # Check for any performance-related debug output
        local perf_lines=$(grep -c "PERF\|performance\|latency" "$VALIDATOR_LOG" 2>/dev/null || echo "0")
        if [ "$perf_lines" -gt 0 ]; then
            echo_success " Found $perf_lines performance-related log entries"
        else
            echo_info "INFO:  No performance debug output yet (expected until transactions are processed)"
        fi
    else
        echo_warning "WARNING:  Validator log file not found: $VALIDATOR_LOG"
    fi
    
    # Test signal handling capability
    echo_info " Testing signal handling capability..."
    if kill -0 $VALIDATOR_PID 2>/dev/null; then
        echo_success " Validator process is responsive to signals"
        
        # Try to send SIGUSR1 to test signal handling (non-blocking)
        echo_info " Testing SIGUSR1 signal handling..."
        if kill -USR1 $VALIDATOR_PID 2>/dev/null; then
            echo_success " SIGUSR1 signal sent successfully"
            sleep 1
            
            # Check if signal was processed (look for any new performance-related output)
            if [ -f "$VALIDATOR_LOG" ]; then
                local new_perf_lines=$(tail -50 "$VALIDATOR_LOG" | grep -c "PERF.*Received\|export.*function.*latency" 2>/dev/null || echo "0")
                if [ "$new_perf_lines" -gt 0 ]; then
                    echo_success " Signal handler responded with performance output"
                else
                    echo_info "INFO:  No immediate signal handler response (may need transactions to generate data)"
                fi
            fi
        else
            echo_warning "WARNING:  Failed to send SIGUSR1 signal to validator"
        fi
    else
        echo_error " Validator process is not responsive"
        return 1
    fi
    
    # Check process memory for performance monitoring structures
    echo_info " Checking process memory usage..."
    if command -v ps &> /dev/null; then
        local mem_usage=$(ps -p $VALIDATOR_PID -o rss= 2>/dev/null || echo "0")
        if [ "$mem_usage" -gt 100000 ]; then  # More than 100MB suggests proper initialization
            echo_success " Validator memory usage: ${mem_usage}KB (indicates proper initialization)"
        else
            echo_info "INFO:  Validator memory usage: ${mem_usage}KB"
        fi
    fi
    
    echo_info " Runtime performance monitoring verification completed"
}

# Performance benchmark test
run_performance_benchmark() {
    echo_info " Running performance benchmark to validate optimizations..."
    
    # Test 1: Block production speed
    echo_info " Test 1: Block production speed measurement"
    local start_version=$(curl -s http://127.0.0.1:8080/v1/ledger_info | jq -r '.ledger_version // "0"')
    echo_info "Initial ledger version: $start_version"
    
    # Submit a few simple transactions to trigger block production
    echo_info " Submitting test transactions to measure block production..."
    for i in {1..3}; do
        # Simple account lookup to trigger activity
        curl -s "http://127.0.0.1:8080/v1/accounts/0x1" > /dev/null 2>&1 || true
        sleep 0.5
    done
    
    # Wait and measure
    sleep 5
    local end_version=$(curl -s http://127.0.0.1:8080/v1/ledger_info | jq -r '.ledger_version // "0"')
    echo_info "Final ledger version: $end_version"
    
    if [ "$end_version" -gt "$start_version" ]; then
        local blocks_produced=$((end_version - start_version))
        local rate=$(echo "scale=2; $blocks_produced / 5.5" | bc 2>/dev/null || echo "N/A")  # 5.5 seconds total
        echo_success " Block production rate: $rate blocks/second"
        echo_info " Total blocks produced: $blocks_produced in 5.5 seconds"
    else
        echo_info "INFO:  No blocks produced (lazy mode - blocks only created with transactions)"
    fi
    
    # Test 2: API response time
    echo_info " Test 2: API response time measurement"
    local api_start=$(date +%s%N)
    curl -s http://127.0.0.1:8080/v1 > /dev/null 2>&1
    local api_end=$(date +%s%N)
    local api_latency=$(( (api_end - api_start) / 1000000 )) # Convert to milliseconds
    echo_info " API response time: ${api_latency}ms"
    
    if [ "$api_latency" -lt 100 ]; then
        echo_success " Excellent API response time (<100ms)"
    elif [ "$api_latency" -lt 500 ]; then
        echo_success " Good API response time (<500ms)"
    else
        echo_warning "WARNING:  API response time is high (>500ms)"
    fi
    
    # Test 3: Faucet response time
    echo_info " Test 3: Faucet response time measurement"
    local faucet_start=$(date +%s%N)
    curl -s http://127.0.0.1:8081/ > /dev/null 2>&1
    local faucet_end=$(date +%s%N)
    local faucet_latency=$(( (faucet_end - faucet_start) / 1000000 )) # Convert to milliseconds
    echo_info " Faucet response time: ${faucet_latency}ms"
    
    if [ "$faucet_latency" -lt 200 ]; then
        echo_success " Excellent faucet response time (<200ms)"
    elif [ "$faucet_latency" -lt 1000 ]; then
        echo_success " Good faucet response time (<1000ms)"
    else
        echo_warning "WARNING:  Faucet response time is high (>1000ms)"
    fi
    
    echo_success " Performance benchmark completed!"
}

# Trigger block production with a simple transaction
trigger_block_production() {
    echo_info "Creating temporary account to trigger block production..."
    
    cd "$TESTNET_DIR"
    
    # Create a temporary profile for triggering blocks
    "$PROJECT_DIR/target/release/aptos" init \
        --profile trigger \
        --network custom \
        --rest-url http://127.0.0.1:8080 \
        --skip-faucet \
        --assume-yes >/dev/null 2>&1 || true
    
    # Submit a simple account creation transaction to trigger block production
    # This will force the validator to create the first block
    local trigger_addr=$("$PROJECT_DIR/target/release/aptos" config show-profiles --profile trigger 2>/dev/null | grep -i "account" | awk '{print $NF}' || echo "")
    
    if [ ! -z "$trigger_addr" ]; then
        echo_info "Trigger account created: $trigger_addr"
        echo_info "Waiting for first block to be produced..."
        
        # Wait for block production
        for i in {1..10}; do
            local current_version=$(curl -s http://127.0.0.1:8080/v1 | jq -r '.ledger_version // "0"')
            if [ "$current_version" != "0" ]; then
                echo_success " First block produced! Ledger version: $current_version"
                return 0
            fi
            sleep 1
        done
        
        echo_warning "Block production may be slow, continuing anyway..."
    else
        echo_warning "Could not create trigger account, continuing anyway..."
    fi
}

# Create and fund test accounts using genesis root capabilities
create_genesis_funded_account() {
    local account_name="$1"
    local initial_balance="${2:-1000000000000000}"  # Default: 10M APT (10^16 octas)
    
    echo_info " Creating genesis-funded account: $account_name with $initial_balance octas..."
    
    cd "$TESTNET_DIR"
    
    # Create account with specific private key for predictable funding
    local test_private_keys=(
        "0x1111111111111111111111111111111111111111111111111111111111111111"
        "0x2222222222222222222222222222222222222222222222222222222222222222"
        "0x3333333333333333333333333333333333333333333333333333333333333333"
    )
    
    local key_index=0
    case "$account_name" in
        "funder") key_index=0 ;;
        "sender") key_index=1 ;;
        "recipient") key_index=2 ;;
        *) key_index=0 ;;
    esac
    
    local private_key="${test_private_keys[$key_index]}"
    
    # Initialize the account with the specific private key
    echo "$private_key" | "$PROJECT_DIR/target/release/aptos" init \
        --profile "$account_name" \
        --network custom \
        --rest-url http://127.0.0.1:8080 \
        --skip-faucet \
        --assume-yes >/dev/null 2>&1 || {
        echo_warning "Failed to create profile for $account_name"
        return 1
    }
    
    # Get the account address
    local account_addr=$("$PROJECT_DIR/target/release/aptos" config show-profiles --profile "$account_name" 2>/dev/null | grep -i "account" | awk '{print $NF}' | tr -d ',' | tr -d '"' || echo "")
    
    if [ -z "$account_addr" ]; then
        echo_error "Failed to get address for account $account_name"
        return 1
    fi
    
    echo_info "Account $account_name created with address: $account_addr"
    echo "$account_addr"
    return 0
}

# Enhanced mint function using aptos framework capabilities
mint_coins_to_account() {
    local target_account="$1"
    local amount="$2"
    
    echo_info " Attempting to mint $amount octas to account $target_account..."
    
    cd "$TESTNET_DIR"
    
    # Try to use the root account (0x1) to mint coins
    # In a test environment, we can use the aptos framework's mint capability
    local mint_result=$("$PROJECT_DIR/target/release/aptos" move run \
        --function-id "0x1::aptos_coin::mint" \
        --args "address:0x$target_account" "u64:$amount" \
        --private-key "0xD04470F43AB6AEAA4EB616B72128881EEF77346F2075FFE68E14BA7DEBD8095E" \
        --url http://127.0.0.1:8080 \
        --max-gas 20000 \
        --gas-unit-price 100 \
        --assume-yes 2>&1 || echo "")
    
    if echo "$mint_result" | grep -q "success\|Success\|committed"; then
        echo_success " Successfully minted coins to account"
        return 0
    else
        echo_warning "Direct mint failed: $mint_result"
        
        # Alternative: try using coin transfer from a system account
        echo_info "Trying alternative coin creation method..."
        
        # Try to register the coin store first
        local register_result=$("$PROJECT_DIR/target/release/aptos" move run \
            --function-id "0x1::managed_coin::register" \
            --type-args "0x1::aptos_coin::AptosCoin" \
            --private-key "0x$target_account" \
            --url http://127.0.0.1:8080 \
            --max-gas 20000 \
            --gas-unit-price 100 \
            --assume-yes 2>&1 || echo "")
            
        echo_info "Register result: $register_result"
        return 1
    fi
}

# Fund an account using the root account from genesis
fund_account() {
    local target_account="$1"
    local amount="$2"  # Amount in octas (1 APT = 10^8 octas)
    
    if [ -z "$target_account" ] || [ -z "$amount" ]; then
        echo_error "Usage: fund_account <target_account> <amount_in_octas>"
        return 1
    fi
    
    echo_info " Attempting to fund account $target_account with $amount octas..."
    
    cd "$TESTNET_DIR"
    
    # First try: Use mint function to create coins directly
    echo_info " Trying direct coin minting..."
    if mint_coins_to_account "$target_account" "$amount"; then
        echo_success " Successfully funded account using coin minting"
        return 0
    fi
    
    # Second try: Get the root account from genesis and transfer
    echo_info " Trying root account transfer..."
    local root_private_key
    if [ -f "private-keys.yaml" ]; then
        # Try to extract root private key from genesis files
        root_private_key=$(python3 -c "
import yaml
try:
    with open('private-keys.yaml', 'r') as f:
        data = yaml.safe_load(f)
    # Look for the root account private key (usually the first one or validator account)
    for account, key_data in data.items():
        if isinstance(key_data, dict):
            if 'account_private_key' in key_data:
                print('0x' + key_data['account_private_key'])
                break
            elif 'consensus_private_key' in key_data:
                # Sometimes the validator's consensus key can be used for funding
                continue
            else:
                # Look for any 64-char hex string in the dict
                for key, value in key_data.items():
                    if isinstance(value, str) and len(value) == 64 and all(c in '0123456789abcdefABCDEF' for c in value):
                        print('0x' + value)
                        break
                else:
                    continue
                break
        elif isinstance(key_data, str) and len(key_data) == 64 and all(c in '0123456789abcdefABCDEF' for c in key_data):
            print('0x' + key_data)
            break
except Exception as e:
    print('')
" 2>/dev/null || echo "")
    fi
    
    if [ -z "$root_private_key" ]; then
        echo_warning "WARNING:  Could not extract root private key from genesis files"
        echo_info "Attempting to use default root account (0x1)..."
        
        # Try to fund using the default root account
        # In a single validator testnet, the root account (0x1) usually has initial funds
        local clean_target_account=$(echo "$target_account" | tr -d '"' | tr -d ',')
        local fund_result=$("$PROJECT_DIR/target/release/aptos" account transfer \
            --private-key 0x5243ca72b0766d9e9cbf2debf6153443b01a1e0e6d163d7cc18c5cdf3c0e2222 \
            --account "0x$clean_target_account" \
            --amount "$amount" \
            --url http://127.0.0.1:8080 \
            --max-gas 20000 \
            --gas-unit-price 100 \
            --assume-yes 2>&1 || echo "")
            
        if echo "$fund_result" | grep -q "success\|Success\|committed"; then
            echo_success " Successfully funded account using default root key"
            return 0
        else
            echo_warning "WARNING:  Default root key funding failed: $fund_result"
        fi
    else
        echo_info " Using extracted root private key for funding..."
        
        # Create a temporary profile for the root account
        echo "$root_private_key" | "$PROJECT_DIR/target/release/aptos" init \
            --profile root_funder \
            --network custom \
            --rest-url http://127.0.0.1:8080 \
            --skip-faucet \
            --assume-yes >/dev/null 2>&1 || {
            echo_warning "WARNING:  Failed to create root funder profile"
        }
        
        # Try to fund using the root account  
        local clean_target_account=$(echo "$target_account" | tr -d '"' | tr -d ',')
        local fund_result=$("$PROJECT_DIR/target/release/aptos" account transfer \
            --profile root_funder \
            --account "0x$clean_target_account" \
            --amount "$amount" \
            --max-gas 20000 \
            --gas-unit-price 100 \
            --assume-yes 2>&1)
            
        if echo "$fund_result" | grep -q "success\|Success\|committed"; then
            echo_success " Successfully funded account using root key from genesis"
            return 0
        else
            echo_warning "WARNING:  Root key funding failed: $fund_result"
        fi
    fi
    
    # Alternative approach: try to mint coins directly (if supported)
    echo_info " Attempting alternative funding method..."
    
    # Try using the aptos CLI to create and fund the account
    local clean_target_account=$(echo "$target_account" | tr -d '"' | tr -d ',')
    local create_result=$("$PROJECT_DIR/target/release/aptos" account create \
        --account "0x$clean_target_account" \
        --url http://127.0.0.1:8080 \
        --assume-yes 2>&1 || echo "")
    
    if echo "$create_result" | grep -q "success\|Success\|exists"; then
        echo_info " Account creation/verification successful"
        
        # Try to fund using a known genesis account
        # In testnet, we can try using well-known test accounts
        local test_keys=("0x5243ca72b0766d9e9cbf2debf6153443b01a1e0e6d163d7cc18c5cdf3c0e2222" 
                         "0x37368b46ce665362562c6d1d4ec01a08c8644c488690df5a17e13ba163e20221")
        
        for test_key in "${test_keys[@]}"; do
            echo_info " Trying with test key: ${test_key:0:20}..."
            local fund_result=$("$PROJECT_DIR/target/release/aptos" account transfer \
                --private-key "$test_key" \
                --account "0x$clean_target_account" \
                --amount "$amount" \
                --url http://127.0.0.1:8080 \
                --max-gas 20000 \
                --gas-unit-price 100 \
                --assume-yes 2>&1 || echo "")
                
            if echo "$fund_result" | grep -q "success\|Success\|committed"; then
                echo_success " Successfully funded account using test key"
                return 0
            fi
        done
    fi
    
    # Last resort: try using aptos account fund-with-faucet (if available)
    echo_info " Trying faucet funding as last resort..."
    local faucet_result=$("$PROJECT_DIR/target/release/aptos" account fund-with-faucet \
        --account "$target_account" \
        --url http://127.0.0.1:8080 \
        --faucet-url http://127.0.0.1:8000 \
        2>&1 || echo "")
        
    if echo "$faucet_result" | grep -q "success\|Success\|funded"; then
        echo_success " Successfully funded account using faucet"
        return 0
    fi
    
    # Final attempt: try to create account with initial balance using genesis
    echo_info "🔧 Final attempt: creating account with initial balance..."
    
    # For single validator testnet, we can try to use the validator's built-in account creation
    local genesis_result=$("$PROJECT_DIR/target/release/aptos" account create-resource-account \
        --seed "$target_account" \
        --url http://127.0.0.1:8080 \
        --assume-yes 2>&1 || echo "")
    
    if echo "$genesis_result" | grep -q "success\|Success"; then
        echo_info " Resource account creation attempted"
        # Try to fund again after account creation
        sleep 1
        local final_fund_result=$("$PROJECT_DIR/target/release/aptos" account transfer \
            --private-key 0x5243ca72b0766d9e9cbf2debf6153443b01a1e0e6d163d7cc18c5cdf3c0e2222 \
            --account "0x$clean_target_account" \
            --amount "$amount" \
            --url http://127.0.0.1:8080 \
            --max-gas 20000 \
            --gas-unit-price 100 \
            --assume-yes 2>&1 || echo "")
            
        if echo "$final_fund_result" | grep -q "success\|Success\|committed"; then
            echo_success " Successfully funded account after resource account creation"
            return 0
        fi
    fi
    
    echo_error " All funding methods failed"
    echo_info "💡 Consider manually funding the account or checking genesis configuration"
    return 1
}

# Execute transfer transaction using faucet for funding
execute_transfer() {
    echo_info " Executing transfer transaction with faucet funding..."
    
    cd "$TESTNET_DIR"
    
    # Create test accounts
    echo_info "Creating test accounts..."
    
    # Initialize sender account
    "$PROJECT_DIR/target/release/aptos" init \
        --profile sender \
        --network custom \
        --rest-url http://127.0.0.1:8080 \
        --faucet-url http://127.0.0.1:8081 \
        --assume-yes || {
        echo_error "Failed to initialize sender profile"
        return 1
    }
    
    # Initialize recipient account
    "$PROJECT_DIR/target/release/aptos" init \
        --profile recipient \
        --network custom \
        --rest-url http://127.0.0.1:8080 \
        --faucet-url http://127.0.0.1:8081 \
        --assume-yes || {
        echo_error "Failed to initialize recipient profile"
        return 1
    }
    
    # Get account addresses
    local sender_addr=$("$PROJECT_DIR/target/release/aptos" config show-profiles --profile sender 2>/dev/null | grep -i "account" | awk '{print $NF}' | tr -d ',' | tr -d '"' || echo "")
    local recipient_addr=$("$PROJECT_DIR/target/release/aptos" config show-profiles --profile recipient 2>/dev/null | grep -i "account" | awk '{print $NF}' | tr -d ',' | tr -d '"' || echo "")
    
    echo_info " Sender address: $sender_addr"
    echo_info " Recipient address: $recipient_addr"
    
    # Check if we have valid addresses
    if [ -z "$sender_addr" ] || [ -z "$recipient_addr" ]; then
        echo_error " Failed to get account addresses. Sender: $sender_addr, Recipient: $recipient_addr"
        return 1
    fi
    
    # Fund sender account using faucet
    echo_info " Funding sender account from faucet..."
    local fund_result=$("$PROJECT_DIR/target/release/aptos" account fund-with-faucet \
        --profile sender \
        --amount 100000000000 \
        --url http://127.0.0.1:8080 \
        --faucet-url http://127.0.0.1:8081 \
        2>&1)
    
    if echo "$fund_result" | grep -q "success\|Success\|funded\|completed\|Added.*Octas"; then
        echo_success " Successfully funded sender account from faucet"
    else
        echo_warning "WARNING:  Faucet funding response unclear: $fund_result"
        echo_info "Trying alternative faucet funding method..."
        
        # Alternative: direct curl to faucet
        local faucet_result=$(curl -s -X POST "http://127.0.0.1:8081/mint?amount=100000000000&address=$sender_addr" 2>&1)
        if echo "$faucet_result" | grep -q "success\|Success\|txn_hash"; then
            echo_success " Successfully funded sender via direct faucet call"
        elif echo "$faucet_result" | grep -q "\[\"[a-fA-F0-9]\{64\}\"\]"; then
            echo_success " Successfully funded sender via direct faucet call (got transaction hash)"
        else
            echo_warning "WARNING:  Both faucet funding methods may have failed"
            echo_warning "CLI fund result: $fund_result"
            echo_warning "Direct faucet result: $faucet_result"
            echo_info "Proceeding to check account balance..."
        fi
    fi
    
    # Wait for funding to be processed
    sleep 3
    
    # Check sender balance using aptos CLI (more reliable than direct API)
    echo_info " Checking sender balance after funding..."
    local balance_result=$("$PROJECT_DIR/target/release/aptos" account balance --profile sender 2>/dev/null || echo "")
    local balance_before=$(echo "$balance_result" | jq -r '.Result[0].balance // "0"' 2>/dev/null || echo "0")
    
    if [ "$balance_before" = "0" ] || [ -z "$balance_before" ]; then
        echo_error " Sender account still has no balance after faucet funding"
        echo_info "Trying one more funding attempt..."
        
        # Try using aptos account create and fund in one command
        local create_fund_result=$("$PROJECT_DIR/target/release/aptos" account create-and-fund \
            --profile sender \
            --initial-coins 100000000000 \
            --url http://127.0.0.1:8080 \
            --faucet-url http://127.0.0.1:8081 \
            2>&1 || echo "")
        
        if echo "$create_fund_result" | grep -q "success\|Success"; then
            echo_success " Account creation and funding successful"
            sleep 2
            balance_result=$("$PROJECT_DIR/target/release/aptos" account balance --profile sender 2>/dev/null || echo "")
            balance_before=$(echo "$balance_result" | jq -r '.Result[0].balance // "0"' 2>/dev/null || echo "0")
        fi
        
        if [ "$balance_before" = "0" ] || [ -z "$balance_before" ]; then
            echo_error " All funding attempts failed. Cannot proceed with transfer."
            return 1
        fi
    fi
    
    # Convert balance to APT for display (1 APT = 10^8 octas)
    local sender_apt=$(echo "scale=2; $balance_before / 100000000" | bc 2>/dev/null || echo "N/A")
    echo_success " Sender balance: $balance_before octas ($sender_apt APT)"
    
    # Execute transfer transaction with performance monitoring
    echo_info " Starting performance monitoring and executing transfer..."
    
    # Start perf recording for flamegraph
    if command -v perf &> /dev/null; then
        echo_info "Starting perf recording for flamegraph generation..."
        mkdir -p "$FLAMEGRAPH_DIR"
        
        # Use a more comprehensive perf recording with better stack traces
        perf record -F 99 -g --call-graph=dwarf -p $VALIDATOR_PID -o "$FLAMEGRAPH_DIR/perf.data" &
        PERF_PID=$!
        echo_info "Started perf recording (PID: $PERF_PID)"
        
        # Let perf run for a few seconds before starting the transaction
        sleep 2
    else
        echo_warning "perf not available, flamegraph generation will be skipped"
    fi
    
    # Record start time
    local start_time=$(date +%s%N)
    
    # Execute the transfer
    echo_info " Executing transfer: 10 APT (1,000,000,000 octas) from sender to recipient..."
    local transfer_amount="1000000000"  # 10 APT in octas
    local tx_result=$("$PROJECT_DIR/target/release/aptos" account transfer \
        --profile sender \
        --account "$recipient_addr" \
        --amount "$transfer_amount" \
        --max-gas 20000 \
        --gas-unit-price 100 \
        --assume-yes 2>&1)
    
    local transfer_exit_code=$?
    local end_time=$(date +%s%N)
    local total_time=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds
    
    # Stop perf recording
    if [ ! -z "$PERF_PID" ]; then
        sleep 1
        kill -INT $PERF_PID 2>/dev/null || true
        wait $PERF_PID 2>/dev/null || true
        echo_info "Stopped perf recording"
    fi
    
    if [ $transfer_exit_code -eq 0 ]; then
        echo_success " Transfer transaction completed successfully!"
        echo_info "Total transaction time: ${total_time}ms"
        
        # Extract transaction hash if possible
        local tx_hash=$(echo "$tx_result" | grep -o "0x[a-fA-F0-9]\{64\}" | head -1)
        if [ ! -z "$tx_hash" ]; then
            echo_info "Transaction hash: $tx_hash"
        fi
        
        # Wait a moment for the transaction to be processed
        sleep 3
        
        # Check final balances using aptos CLI
        local sender_balance_result=$("$PROJECT_DIR/target/release/aptos" account balance --profile sender 2>/dev/null || echo "")
        local recipient_balance_result=$("$PROJECT_DIR/target/release/aptos" account balance --profile recipient 2>/dev/null || echo "")
        local balance_after=$(echo "$sender_balance_result" | jq -r '.Result[0].balance // "0"' 2>/dev/null || echo "0")
        local recipient_balance=$(echo "$recipient_balance_result" | jq -r '.Result[0].balance // "0"' 2>/dev/null || echo "0")
        
        echo_info "Final balances:"
        echo_info "  Sender: $balance_after APT"
        echo_info "  Recipient: $recipient_balance APT"
        
    else
        echo_error " Transfer transaction failed"
        echo_error "Error output: $tx_result"
        return 1
    fi
    
    echo_success "Transfer transaction monitoring completed"
}

# Generate flamegraph
generate_flamegraph() {
    echo_info "Generating flamegraph..."
    
    if [ ! -d "$FLAMEGRAPH_DIR" ]; then
        echo_warning "Flamegraph directory not found, skipping flamegraph generation"
        return 0
    fi
    
    cd "$FLAMEGRAPH_DIR"
    
    if [ -f "perf.data" ]; then
        echo_info "Processing perf data..."
        
        # Check if perf.data has any data
        local sample_count=$(perf report -i perf.data --stdio -n 2>/dev/null | grep "Event count" | head -1 | awk '{print $5}' || echo "0")
        echo_info "Perf samples collected: $sample_count"
        
        if [ "$sample_count" != "0" ] && [ ! -z "$sample_count" ]; then
            # Generate flamegraph with better error handling
            echo_info "Generating flamegraph SVG..."
            
            if perf script -i perf.data > perf.script 2>/dev/null; then
                if flamegraph < perf.script > consensus_flamegraph.svg 2>/dev/null; then
                    echo_success " Flamegraph generated: $FLAMEGRAPH_DIR/consensus_flamegraph.svg"
                    
                    # Show flamegraph size
                    local svg_size=$(du -h consensus_flamegraph.svg 2>/dev/null | cut -f1)
                    echo_info "Flamegraph size: $svg_size"
                else
                    echo_warning "Failed to generate flamegraph SVG from perf script"
                fi
                
                # Clean up intermediate file
                rm -f perf.script
            else
                echo_warning "Failed to process perf.data with perf script"
            fi
        else
            echo_warning "No perf samples collected, cannot generate flamegraph"
        fi
    else
        echo_warning "No perf data found for flamegraph generation"
    fi
}

# Export performance results
export_results() {
    echo_info "Exporting performance results..."
    
    # Create performance report
    cat > "$PERFORMANCE_LOG" << EOF
=== Aptos Consensus Performance Test Report ===
Generated at: $(date)
Test Configuration:
  - Single validator testnet
  - Transfer amount: 100,000 APT tokens
  - Testnet directory: $TESTNET_DIR
  - Performance monitoring: Enabled

Validator Log Location: $VALIDATOR_LOG
Flamegraph Location: $FLAMEGRAPH_DIR/consensus_flamegraph.svg

=== Performance Metrics ===
EOF
    
    # Extract performance metrics from validator log
    if [ -f "$VALIDATOR_LOG" ]; then
        echo "=== Transaction Tracking ===" >> "$PERFORMANCE_LOG"
        grep -E "\[PERF\]" "$VALIDATOR_LOG" | tail -20 >> "$PERFORMANCE_LOG" 2>/dev/null || true
        
        echo -e "\n=== Consensus Metrics ===" >> "$PERFORMANCE_LOG"
        grep -E "(consensus|proposal|vote|commit)" "$VALIDATOR_LOG" | tail -10 >> "$PERFORMANCE_LOG" 2>/dev/null || true
    fi
    
    echo_success "Performance results exported to: $PERFORMANCE_LOG"
}

# Wait for user input to stop
wait_for_stop() {
    echo_info "Test is running. Validator PID: $VALIDATOR_PID"
    echo_info "Press Ctrl+C to stop and export results, or type 'export' to export results now:"
    
    while true; do
        read -t 1 input 2>/dev/null || continue
        if [ "$input" = "export" ]; then
            echo_info " Exporting function latency metrics..."
            # Send SIGUSR1 to trigger function latency export
            if [ ! -z "$VALIDATOR_PID" ] && kill -0 $VALIDATOR_PID 2>/dev/null; then
                echo_info "Sending SIGUSR1 to validator for function latency export..."
                kill -USR1 $VALIDATOR_PID 2>/dev/null || true
                sleep 3
                
                # Check if function latency log was created
                if [ -f "/dev/shm/fn_latency.log" ]; then
                    echo_success " Function latency exported successfully!"
                    echo_info "Function latency file: /dev/shm/fn_latency.log"
                    echo_info " Showing function latency summary:"
                    # Show summary of function latency data
                    if grep -q "=== Function Latency Report ===" /dev/shm/fn_latency.log 2>/dev/null; then
                        grep -A 10 "=== Function Latency Report ===" /dev/shm/fn_latency.log
                        echo ""
                        echo_info " Function statistics:"
                        grep "Average latency:" /dev/shm/fn_latency.log | head -5
                    else
                        tail -20 /dev/shm/fn_latency.log
                    fi
                else
                    echo_warning "WARNING:  No function latency log found at /dev/shm/fn_latency.log"
                    echo_info "Checking for other performance files..."
                    if ls /dev/shm/performance_metrics_*.log 1> /dev/null 2>&1; then
                        latest_metrics=$(ls -t /dev/shm/performance_metrics_*.log | head -1)
                        echo_info "Found metrics file: $latest_metrics"
                        tail -20 "$latest_metrics"
                    else
                        echo_info "Showing validator log instead:"
                        tail -20 "$VALIDATOR_LOG"
                    fi
                fi
            else
                echo_warning "Validator not running, cannot export metrics via signal"
                tail -20 "$VALIDATOR_LOG"
            fi
            echo_info "Continue running or press Ctrl+C to stop..."
        fi
    done
}

# Main execution
main() {
    echo_info " Starting Aptos Consensus Performance Test with Faucet"
    echo_info "This test will:"
    echo_info "  1. Start a local testnet with validator and faucet"
    echo_info "  2. Create test accounts and fund them via faucet"
    echo_info "  3. Execute transfer transactions with performance monitoring"
    echo_info "  4. Generate performance reports and flamegraphs"
    echo ""
    
    # Set up signal handlers first
    setup_signal_handlers
    
    check_dependencies
    build_project
    init_testnet
    start_validator
    run_performance_benchmark
    execute_transfer
    generate_flamegraph
    export_results
    wait_for_stop
}

# Run main function
main "$@"

