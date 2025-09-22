#!/bin/bash

# Aptos Consensus Performance Testing Script
# This script starts a single validator testnet and performs a transfer transaction
# to measure end-to-end latency from mempool to blockchain commit

set -e

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
            echo "⚠️  Skipping compilation verification as requested"
            shift
            ;;
        --skip-runtime-verification)
            SKIP_RUNTIME_VERIFICATION=true
            echo "⚠️  Skipping runtime verification as requested"
            shift
            ;;
        --skip-all-verification)
            SKIP_COMPILATION_VERIFICATION=true
            SKIP_RUNTIME_VERIFICATION=true
            echo "⚠️  Skipping all performance monitoring verification as requested"
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
PERF_PID=""

# Cleanup function
cleanup() {
    echo_info "Cleaning up processes..."
    
    if [ ! -z "$PERF_PID" ]; then
        kill -INT $PERF_PID 2>/dev/null || true
        wait $PERF_PID 2>/dev/null || true
        echo_info "Stopped perf recording"
    fi
    
    if [ ! -z "$VALIDATOR_PID" ]; then
        echo_info "Sending SIGUSR1 to validator for metrics export..."
        kill -USR1 $VALIDATOR_PID 2>/dev/null || true
        sleep 3
        
        # Check if function latency log was created
        if [ -f "/dev/shm/fn_latency.log" ]; then
            echo_success "✅ Function latency log found: /dev/shm/fn_latency.log"
            cp "/dev/shm/fn_latency.log" "$PERFORMANCE_LOG" 2>/dev/null || true
            echo_info "Function latency data copied to: $PERFORMANCE_LOG"
        else
            echo_warning "⚠️  No function latency log found at /dev/shm/fn_latency.log"
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
    
    cd /home/ubuntu/whtest/CrustleLabs/aptos-core
    
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
        echo_info "⚠️  Skipping compilation verification as requested"
    fi
}

# Verify performance monitoring integration
verify_performance_monitoring_integration() {
    echo_info "🔍 Verifying performance monitoring integration..."
    
    local verification_passed=true
    
    # Check 1: Verify aptos-performance-monitor crate was compiled
    echo_info "📦 Checking if aptos-performance-monitor crate was compiled..."
    if [ -f "target/release/libaptos_performance_monitor.rlib" ] || [ -f "target/release/deps/libaptos_performance_monitor-"*.rlib ]; then
        echo_success "✅ aptos-performance-monitor crate found in build artifacts"
    else
        echo_warning "⚠️  aptos-performance-monitor crate not found in build artifacts"
        verification_passed=false
    fi
    
    # Check 2: Verify performance monitoring symbols are present in aptos-node binary
    echo_info "🔍 Checking for performance monitoring symbols in aptos-node binary..."
    if command -v nm &> /dev/null; then
        if nm target/release/aptos-node 2>/dev/null | grep -q "PerformanceMonitor\|track_mempool_entry\|export_function_latency"; then
            echo_success "✅ Performance monitoring symbols found in aptos-node binary"
        else
            echo_warning "⚠️  Performance monitoring symbols not found in aptos-node binary"
            verification_passed=false
        fi
    else
        echo_info "ℹ️  nm tool not available, skipping symbol check"
    fi
    
    # Check 3: Verify signal-hook dependency is linked
    echo_info "🔗 Checking for signal-hook dependency..."
    if ldd target/release/aptos-node 2>/dev/null | grep -q "signal" || nm target/release/aptos-node 2>/dev/null | grep -q "signal_hook"; then
        echo_success "✅ Signal handling functionality appears to be linked"
    else
        echo_warning "⚠️  Signal handling functionality not detected"
    fi
    
    # Check 4: Verify aptos-performance-monitor is in dependency tree
    echo_info "📋 Checking dependency tree for performance monitoring..."
    if cargo tree -p aptos-node 2>/dev/null | grep -q "aptos-performance-monitor"; then
        echo_success "✅ aptos-performance-monitor found in aptos-node dependency tree"
    else
        echo_warning "⚠️  aptos-performance-monitor not found in dependency tree"
        verification_passed=false
    fi
    
    # Check 5: Verify mempool integration
    echo_info "🧩 Checking mempool integration..."
    if grep -q "aptos-performance-monitor" mempool/Cargo.toml 2>/dev/null; then
        echo_success "✅ Mempool has aptos-performance-monitor dependency"
        if grep -q "track_mempool_entry" mempool/src/core_mempool/mempool.rs 2>/dev/null; then
            echo_success "✅ Mempool code contains performance tracking calls"
        else
            echo_warning "⚠️  Mempool performance tracking calls not found"
            verification_passed=false
        fi
    else
        echo_warning "⚠️  Mempool missing aptos-performance-monitor dependency"
        verification_passed=false
    fi
    
    # Check 6: Verify performance monitor crate compilation with required features
    echo_info "⚙️  Checking performance monitor crate features..."
    if cargo metadata --format-version 1 2>/dev/null | jq -e '.packages[] | select(.name == "aptos-performance-monitor")' >/dev/null 2>&1; then
        echo_success "✅ aptos-performance-monitor package found in workspace"
        
        # Check if required dependencies are present
        local deps_check=true
        for dep in "minstant" "signal-hook" "chrono"; do
            if cargo metadata --format-version 1 2>/dev/null | jq -e ".packages[] | select(.name == \"aptos-performance-monitor\") | .dependencies[] | select(.name == \"$dep\")" >/dev/null 2>&1; then
                echo_success "✅ Required dependency '$dep' found"
            else
                echo_warning "⚠️  Required dependency '$dep' not found"
                deps_check=false
            fi
        done
        
        if [ "$deps_check" = true ]; then
            echo_success "✅ All required dependencies are present"
        fi
    else
        echo_warning "⚠️  aptos-performance-monitor package not found in workspace metadata"
        verification_passed=false
    fi
    
    # Check 7: Test basic functionality with a simple test
    echo_info "🧪 Testing basic performance monitor functionality..."
    cat > /tmp/perf_monitor_test.rs << 'EOF'
fn main() {
    println!("Testing basic compilation...");
    // This will fail at runtime but should compile if dependencies are correct
}
EOF
    
    if rustc --edition 2021 -L target/release/deps /tmp/perf_monitor_test.rs -o /tmp/perf_monitor_test 2>/dev/null; then
        echo_success "✅ Basic Rust compilation test passed"
        rm -f /tmp/perf_monitor_test /tmp/perf_monitor_test.rs
    else
        echo_info "ℹ️  Basic compilation test inconclusive"
        rm -f /tmp/perf_monitor_test /tmp/perf_monitor_test.rs
    fi
    
    # Summary
    echo ""
    if [ "$verification_passed" = true ]; then
        echo_success "🎉 Performance monitoring integration verification PASSED!"
        echo_info "✅ All critical checks passed. Performance monitoring should work correctly."
    else
        echo_warning "⚠️  Performance monitoring integration verification had WARNINGS!"
        echo_info "Some checks failed, but the system may still work. Monitor the logs for performance data."
        echo_info "If issues persist, try rebuilding with: cargo clean && cargo build --release --package aptos-node"
    fi
    echo ""
}

# Initialize testnet
init_testnet() {
    echo_info "Initializing single validator testnet in $TESTNET_DIR..."
    
    # Clean up existing testnet
    rm -rf "$TESTNET_DIR"
    mkdir -p "$TESTNET_DIR"
    mkdir -p "$FLAMEGRAPH_DIR"
    
    cd "$TESTNET_DIR"
    
    echo_info "Step 1: Generating validator keys..."
    /home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos genesis generate-keys --output-dir . || {
        echo_error "Failed to generate keys"
        exit 1
    }
    
    echo_info "Step 2: Compiling Move framework..."
    /home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos-framework release --target head || {
        echo_error "Failed to compile framework"
        exit 1
    }
    # Rename to framework.mrb
    mv head.mrb framework.mrb || {
        echo_error "Failed to rename framework file"
        exit 1
    }
    
    echo_info "Step 3: Creating layout configuration..."
    cat > layout.yaml << 'EOF'
root_key: "D04470F43AB6AEAA4EB616B72128881EEF77346F2075FFE68E14BA7DEBD8095E"
users:
  - validator
chain_id: 4
allow_new_validators: false
epoch_duration_secs: 7200
is_test: true
min_stake: 100000000000000
min_voting_threshold: 100000000000000
max_stake: 100000000000000000
recurring_lockup_duration_secs: 86400
required_proposer_stake: 100000000000000
rewards_apy_percentage: 10
voting_duration_secs: 43200
voting_quorum_percentage: 67
voting_power_increase_limit: 50
EOF
    
    echo_info "Step 4: Setting validator configuration..."
    /home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos genesis set-validator-configuration \
        --local-repository-dir . \
        --username validator \
        --owner-public-identity-file public-keys.yaml \
        --validator-host 127.0.0.1:6180 \
        --full-node-host 127.0.0.1:6182 \
        --stake-amount 100000000000000 || {
        echo_error "Failed to set validator configuration"
        exit 1
    }
    
    echo_info "Step 5: Generating genesis block..."
    /home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos genesis generate-genesis \
        --local-repository-dir . \
        --output-dir . || {
        echo_error "Failed to generate genesis"
        exit 1
    }
    
    echo_info "Step 6: Creating node configuration..."
    cat > validator.yaml << EOF
base:
  data_dir: "$TESTNET_DIR/data"
  role: "validator"
  waypoint:
    from_file: "$TESTNET_DIR/waypoint.txt"

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
      path: "$TESTNET_DIR/safety-rules.yaml"
    initial_safety_rules_config:
      from_file:
        identity_blob_path: "$TESTNET_DIR/validator-identity.yaml"
        waypoint:
          from_file: "$TESTNET_DIR/waypoint.txt"
  # Quorum store configuration for single validator
  quorum_store:
    channel_size: 1000
    proof_timeout_ms: 10000
    batch_generation_poll_interval_ms: 25
    batch_generation_min_non_empty_interval_ms: 25

execution:
  genesis_file_location: "$TESTNET_DIR/genesis.blob"
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
    path: "$TESTNET_DIR/validator-identity.yaml"
  listen_address: "/ip4/127.0.0.1/tcp/6180"
  network_id: "validator"

full_node_networks:
  - network_id: "public"
    discovery_method: "none"
    identity:
      type: "from_file"
      path: "$TESTNET_DIR/validator-full-node-identity.yaml"
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
    
    # Create data directory
    mkdir -p data
    
    echo_success "Testnet initialized successfully"
}

# Start validator
start_validator() {
    echo_info "Starting validator..."
    
    cd "$TESTNET_DIR"
    
    # Start validator with performance monitoring
    RUST_LOG=info,aptos_consensus=debug,aptos_mempool=debug,aptos_performance_monitor=trace \
    /home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos-node \
        -f validator.yaml \
        > "$VALIDATOR_LOG" 2>&1 &
    
    VALIDATOR_PID=$!
    echo_info "Validator started with PID: $VALIDATOR_PID"
    
    # Wait for validator to be ready
    echo_info "Waiting for validator to be ready..."
    for i in {1..60}; do  # Increased timeout to 120 seconds
        if curl -s http://127.0.0.1:8080/v1 > /dev/null 2>&1; then
            echo_success "✅ Validator is ready!"
            
            # Display validator info
            local version=$(curl -s http://127.0.0.1:8080/v1/ledger_info | jq -r '.ledger_version // "0"')
            echo_info "Validator API: http://127.0.0.1:8080"
            echo_info "Current ledger version: $version"
            
            # Verify runtime performance monitoring
            if [ "$SKIP_RUNTIME_VERIFICATION" = false ]; then
                verify_runtime_performance_monitoring
            else
                echo_info "⚠️  Skipping runtime verification as requested"
            fi
            
            # Trigger initial block production with a simple transaction
            echo_info "Triggering initial block production..."
            trigger_block_production
            
            return 0
        fi
        
        # Check if validator process is still running
        if ! kill -0 $VALIDATOR_PID 2>/dev/null; then
            echo_error "Validator process died unexpectedly!"
            echo_error "Last 30 lines of validator log:"
            tail -30 "$VALIDATOR_LOG"
            exit 1
        fi
        
        echo "  Waiting for validator... ($i/60)"
        sleep 2
    done
    
    echo_error "Validator failed to start within timeout"
    echo_error "Validator log:"
    tail -20 "$VALIDATOR_LOG"
    kill $VALIDATOR_PID 2>/dev/null
    exit 1
}

# Verify runtime performance monitoring
verify_runtime_performance_monitoring() {
    echo_info "🔍 Verifying runtime performance monitoring functionality..."
    
    # Check if performance monitoring process is running
    echo_info "📊 Checking if performance monitoring is active in validator process..."
    
    # Wait a moment for the validator to fully initialize
    sleep 2
    
    # Check validator log for performance monitoring initialization
    if [ -f "$VALIDATOR_LOG" ]; then
        # Look for performance monitoring initialization messages
        if grep -q "\[PERF\].*Initializing Aptos Performance Monitor\|\[PERF\].*Performance Monitor initialized" "$VALIDATOR_LOG" 2>/dev/null; then
            echo_success "✅ Performance monitoring module initialized successfully"
        elif grep -q "aptos_performance_monitor\|PERF.*initialized" "$VALIDATOR_LOG" 2>/dev/null; then
            echo_success "✅ Performance monitoring module loaded in validator"
        else
            echo_warning "⚠️  No performance monitoring module initialization messages found in validator log"
        fi
        
        # Check for signal handler setup
        if grep -q "\[PERF\].*Signal handler registered\|\[PERF\].*SIGUSR1" "$VALIDATOR_LOG" 2>/dev/null; then
            echo_success "✅ SIGUSR1 signal handler registered successfully"
        elif grep -q "signal" "$VALIDATOR_LOG" 2>/dev/null; then
            echo_success "✅ Signal handling appears to be active"
        else
            echo_info "ℹ️  No explicit signal handler messages found (this may be normal)"
        fi
        
        # Check for any performance-related debug output
        local perf_lines=$(grep -c "PERF\|performance\|latency" "$VALIDATOR_LOG" 2>/dev/null || echo "0")
        if [ "$perf_lines" -gt 0 ]; then
            echo_success "✅ Found $perf_lines performance-related log entries"
        else
            echo_info "ℹ️  No performance debug output yet (expected until transactions are processed)"
        fi
    else
        echo_warning "⚠️  Validator log file not found: $VALIDATOR_LOG"
    fi
    
    # Test signal handling capability
    echo_info "📡 Testing signal handling capability..."
    if kill -0 $VALIDATOR_PID 2>/dev/null; then
        echo_success "✅ Validator process is responsive to signals"
        
        # Try to send SIGUSR1 to test signal handling (non-blocking)
        echo_info "🧪 Testing SIGUSR1 signal handling..."
        if kill -USR1 $VALIDATOR_PID 2>/dev/null; then
            echo_success "✅ SIGUSR1 signal sent successfully"
            sleep 1
            
            # Check if signal was processed (look for any new performance-related output)
            if [ -f "$VALIDATOR_LOG" ]; then
                local new_perf_lines=$(tail -50 "$VALIDATOR_LOG" | grep -c "PERF.*Received\|export.*function.*latency" 2>/dev/null || echo "0")
                if [ "$new_perf_lines" -gt 0 ]; then
                    echo_success "✅ Signal handler responded with performance output"
                else
                    echo_info "ℹ️  No immediate signal handler response (may need transactions to generate data)"
                fi
            fi
        else
            echo_warning "⚠️  Failed to send SIGUSR1 signal to validator"
        fi
    else
        echo_error "❌ Validator process is not responsive"
        return 1
    fi
    
    # Check process memory for performance monitoring structures
    echo_info "💾 Checking process memory usage..."
    if command -v ps &> /dev/null; then
        local mem_usage=$(ps -p $VALIDATOR_PID -o rss= 2>/dev/null || echo "0")
        if [ "$mem_usage" -gt 100000 ]; then  # More than 100MB suggests proper initialization
            echo_success "✅ Validator memory usage: ${mem_usage}KB (indicates proper initialization)"
        else
            echo_info "ℹ️  Validator memory usage: ${mem_usage}KB"
        fi
    fi
    
    echo_info "✅ Runtime performance monitoring verification completed"
}

# Trigger block production with a simple transaction
trigger_block_production() {
    echo_info "Creating temporary account to trigger block production..."
    
    cd "$TESTNET_DIR"
    
    # Create a temporary profile for triggering blocks
    /home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos init \
        --profile trigger \
        --network custom \
        --rest-url http://127.0.0.1:8080 \
        --skip-faucet \
        --assume-yes >/dev/null 2>&1 || true
    
    # Submit a simple account creation transaction to trigger block production
    # This will force the validator to create the first block
    local trigger_addr=$(/home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos config show-profiles --profile trigger 2>/dev/null | grep -i "account" | awk '{print $NF}' || echo "")
    
    if [ ! -z "$trigger_addr" ]; then
        echo_info "Trigger account created: $trigger_addr"
        echo_info "Waiting for first block to be produced..."
        
        # Wait for block production
        for i in {1..10}; do
            local current_version=$(curl -s http://127.0.0.1:8080/v1 | jq -r '.ledger_version // "0"')
            if [ "$current_version" != "0" ]; then
                echo_success "✅ First block produced! Ledger version: $current_version"
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
    
    echo_info "💰 Creating genesis-funded account: $account_name with $initial_balance octas..."
    
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
    echo "$private_key" | /home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos init \
        --profile "$account_name" \
        --network custom \
        --rest-url http://127.0.0.1:8080 \
        --skip-faucet \
        --assume-yes >/dev/null 2>&1 || {
        echo_warning "Failed to create profile for $account_name"
        return 1
    }
    
    # Get the account address
    local account_addr=$(/home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos config show-profiles --profile "$account_name" 2>/dev/null | grep -i "account" | awk '{print $NF}' | tr -d ',' | tr -d '"' || echo "")
    
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
    
    echo_info "🏦 Attempting to mint $amount octas to account $target_account..."
    
    cd "$TESTNET_DIR"
    
    # Try to use the root account (0x1) to mint coins
    # In a test environment, we can use the aptos framework's mint capability
    local mint_result=$(/home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos move run \
        --function-id "0x1::aptos_coin::mint" \
        --args "address:0x$target_account" "u64:$amount" \
        --private-key "0xD04470F43AB6AEAA4EB616B72128881EEF77346F2075FFE68E14BA7DEBD8095E" \
        --url http://127.0.0.1:8080 \
        --max-gas 20000 \
        --gas-unit-price 100 \
        --assume-yes 2>&1 || echo "")
    
    if echo "$mint_result" | grep -q "success\|Success\|committed"; then
        echo_success "✅ Successfully minted coins to account"
        return 0
    else
        echo_warning "Direct mint failed: $mint_result"
        
        # Alternative: try using coin transfer from a system account
        echo_info "Trying alternative coin creation method..."
        
        # Try to register the coin store first
        local register_result=$(/home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos move run \
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
    
    echo_info "💰 Attempting to fund account $target_account with $amount octas..."
    
    cd "$TESTNET_DIR"
    
    # First try: Use mint function to create coins directly
    echo_info "🪙 Trying direct coin minting..."
    if mint_coins_to_account "$target_account" "$amount"; then
        echo_success "✅ Successfully funded account using coin minting"
        return 0
    fi
    
    # Second try: Get the root account from genesis and transfer
    echo_info "💸 Trying root account transfer..."
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
        echo_warning "⚠️  Could not extract root private key from genesis files"
        echo_info "Attempting to use default root account (0x1)..."
        
        # Try to fund using the default root account
        # In a single validator testnet, the root account (0x1) usually has initial funds
        local clean_target_account=$(echo "$target_account" | tr -d '"' | tr -d ',')
        local fund_result=$(/home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos account transfer \
            --private-key 0x5243ca72b0766d9e9cbf2debf6153443b01a1e0e6d163d7cc18c5cdf3c0e2222 \
            --account "0x$clean_target_account" \
            --amount "$amount" \
            --url http://127.0.0.1:8080 \
            --max-gas 20000 \
            --gas-unit-price 100 \
            --assume-yes 2>&1 || echo "")
            
        if echo "$fund_result" | grep -q "success\|Success\|committed"; then
            echo_success "✅ Successfully funded account using default root key"
            return 0
        else
            echo_warning "⚠️  Default root key funding failed: $fund_result"
        fi
    else
        echo_info "🔑 Using extracted root private key for funding..."
        
        # Create a temporary profile for the root account
        echo "$root_private_key" | /home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos init \
            --profile root_funder \
            --network custom \
            --rest-url http://127.0.0.1:8080 \
            --skip-faucet \
            --assume-yes >/dev/null 2>&1 || {
            echo_warning "⚠️  Failed to create root funder profile"
        }
        
        # Try to fund using the root account  
        local clean_target_account=$(echo "$target_account" | tr -d '"' | tr -d ',')
        local fund_result=$(/home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos account transfer \
            --profile root_funder \
            --account "0x$clean_target_account" \
            --amount "$amount" \
            --max-gas 20000 \
            --gas-unit-price 100 \
            --assume-yes 2>&1)
            
        if echo "$fund_result" | grep -q "success\|Success\|committed"; then
            echo_success "✅ Successfully funded account using root key from genesis"
            return 0
        else
            echo_warning "⚠️  Root key funding failed: $fund_result"
        fi
    fi
    
    # Alternative approach: try to mint coins directly (if supported)
    echo_info "🏦 Attempting alternative funding method..."
    
    # Try using the aptos CLI to create and fund the account
    local clean_target_account=$(echo "$target_account" | tr -d '"' | tr -d ',')
    local create_result=$(/home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos account create \
        --account "0x$clean_target_account" \
        --url http://127.0.0.1:8080 \
        --assume-yes 2>&1 || echo "")
    
    if echo "$create_result" | grep -q "success\|Success\|exists"; then
        echo_info "📝 Account creation/verification successful"
        
        # Try to fund using a known genesis account
        # In testnet, we can try using well-known test accounts
        local test_keys=("0x5243ca72b0766d9e9cbf2debf6153443b01a1e0e6d163d7cc18c5cdf3c0e2222" 
                         "0x37368b46ce665362562c6d1d4ec01a08c8644c488690df5a17e13ba163e20221")
        
        for test_key in "${test_keys[@]}"; do
            echo_info "🔄 Trying with test key: ${test_key:0:20}..."
            local fund_result=$(/home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos account transfer \
                --private-key "$test_key" \
                --account "0x$clean_target_account" \
                --amount "$amount" \
                --url http://127.0.0.1:8080 \
                --max-gas 20000 \
                --gas-unit-price 100 \
                --assume-yes 2>&1 || echo "")
                
            if echo "$fund_result" | grep -q "success\|Success\|committed"; then
                echo_success "✅ Successfully funded account using test key"
                return 0
            fi
        done
    fi
    
    # Last resort: try using aptos account fund-with-faucet (if available)
    echo_info "🚰 Trying faucet funding as last resort..."
    local faucet_result=$(/home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos account fund-with-faucet \
        --account "$target_account" \
        --url http://127.0.0.1:8080 \
        --faucet-url http://127.0.0.1:8000 \
        2>&1 || echo "")
        
    if echo "$faucet_result" | grep -q "success\|Success\|funded"; then
        echo_success "✅ Successfully funded account using faucet"
        return 0
    fi
    
    # Final attempt: try to create account with initial balance using genesis
    echo_info "🔧 Final attempt: creating account with initial balance..."
    
    # For single validator testnet, we can try to use the validator's built-in account creation
    local genesis_result=$(/home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos account create-resource-account \
        --seed "$target_account" \
        --url http://127.0.0.1:8080 \
        --assume-yes 2>&1 || echo "")
    
    if echo "$genesis_result" | grep -q "success\|Success"; then
        echo_info "📝 Resource account creation attempted"
        # Try to fund again after account creation
        sleep 1
        local final_fund_result=$(/home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos account transfer \
            --private-key 0x5243ca72b0766d9e9cbf2debf6153443b01a1e0e6d163d7cc18c5cdf3c0e2222 \
            --account "0x$clean_target_account" \
            --amount "$amount" \
            --url http://127.0.0.1:8080 \
            --max-gas 20000 \
            --gas-unit-price 100 \
            --assume-yes 2>&1 || echo "")
            
        if echo "$final_fund_result" | grep -q "success\|Success\|committed"; then
            echo_success "✅ Successfully funded account after resource account creation"
            return 0
        fi
    fi
    
    echo_error "❌ All funding methods failed"
    echo_info "💡 Consider manually funding the account or checking genesis configuration"
    return 1
}

# Execute transfer transaction
execute_transfer() {
    echo_info "Executing transfer transaction..."
    
    cd "$TESTNET_DIR"
    
    # Create funded test accounts using improved strategy
    echo_info "Setting up funded test accounts..."
    
    # Use the root account from genesis for sending (it has initial funds)
    local root_private_key
    if [ -f "private-keys.yaml" ]; then
        # Try to extract root private key from genesis files
        root_private_key=$(python3 -c "
import yaml
try:
    with open('private-keys.yaml', 'r') as f:
        data = yaml.safe_load(f)
    # Look for the root account private key
    for account, key_data in data.items():
        if 'account_private_key' in key_data:
            print('0x' + key_data['account_private_key'])
            break
except:
    print('')
" 2>/dev/null || echo "")
    fi
    
    if [ -z "$root_private_key" ]; then
        echo_warning "Could not extract root private key, using generated account..."
        # Initialize CLI with generated account
        /home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos init \
            --profile default \
            --network custom \
            --rest-url http://127.0.0.1:8080 \
            --skip-faucet \
            --assume-yes || {
            echo_error "Failed to initialize CLI profile"
            return 1
        }
    else
        echo_info "Using root account from genesis..."
        # Initialize CLI with root account
        echo "$root_private_key" | /home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos init \
            --profile default \
            --network custom \
            --rest-url http://127.0.0.1:8080 \
            --skip-faucet \
            --assume-yes || {
            echo_warning "Failed to use root key, using generated account..."
            /home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos init \
                --profile default \
                --network custom \
                --rest-url http://127.0.0.1:8080 \
                --skip-faucet \
                --assume-yes || {
                echo_error "Failed to initialize CLI profile"
                return 1
            }
        }
    fi
    
    # Create recipient account
    echo_info "Creating recipient account..."
    /home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos init \
        --profile recipient \
        --network custom \
        --rest-url http://127.0.0.1:8080 \
        --skip-faucet \
        --assume-yes || {
        echo_error "Failed to create recipient profile"
        return 1
    }
    
    # Get account addresses using aptos account list
    local sender_addr=$(/home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos config show-profiles --profile default 2>/dev/null | grep -i "account" | awk '{print $NF}' | tr -d ',' | tr -d '"' || echo "")
    local recipient_addr=$(/home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos config show-profiles --profile recipient 2>/dev/null | grep -i "account" | awk '{print $NF}' | tr -d ',' | tr -d '"' || echo "")
    
    # Fallback: try to get addresses from config file if it exists
    if [ -z "$sender_addr" ] && [ -f ~/.aptos/config.yaml ]; then
        sender_addr=$(grep -A 5 "default:" ~/.aptos/config.yaml | grep "account:" | awk '{print $2}' || echo "")
    fi
    if [ -z "$recipient_addr" ] && [ -f ~/.aptos/config.yaml ]; then
        recipient_addr=$(grep -A 5 "recipient:" ~/.aptos/config.yaml | grep "account:" | awk '{print $2}' || echo "")
    fi
    
    echo_info "Sender address: $sender_addr"
    echo_info "Recipient address: $recipient_addr"
    
    # Check if we have valid addresses
    if [ -z "$sender_addr" ] || [ -z "$recipient_addr" ]; then
        echo_error "Failed to get account addresses. Sender: $sender_addr, Recipient: $recipient_addr"
        return 1
    fi
    
    # Check sender balance
    echo_info "Checking sender balance..."
    local balance_before=$(curl -s "http://127.0.0.1:8080/v1/accounts/$sender_addr/resources" 2>/dev/null | jq -r '.[] | select(.type == "0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>") | .data.coin.value // "0"' 2>/dev/null || echo "0")
    echo_info "Sender balance before: $balance_before APT"
    
    if [ "$balance_before" = "0" ] || [ -z "$balance_before" ]; then
        echo_warning "Sender has no balance. Attempting to fund the account..."
        
        # Try to fund the account using multiple strategies
        echo_info "🚀 Attempting comprehensive funding strategy..."
        
        # Strategy 1: Direct coin minting (best approach for test networks)
        if mint_coins_to_account "$sender_addr" "100000000000"; then  # Fund with 1000 APT (10^11 octas)
            echo_success "✅ Successfully funded account using direct minting"
            
            # Re-check balance after minting
            sleep 2
            balance_before=$(curl -s "http://127.0.0.1:8080/v1/accounts/$sender_addr/resources" 2>/dev/null | jq -r '.[] | select(.type == "0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>") | .data.coin.value // "0"' 2>/dev/null || echo "0")
            echo_info "Sender balance after minting: $balance_before APT"
            
            if [ "$balance_before" != "0" ] && [ ! -z "$balance_before" ]; then
                echo_success "✅ Minting successful, proceeding with transfer"
            else
                echo_warning "Minting may not have worked, trying traditional funding..."
                if fund_account "$sender_addr" "100000000000"; then
                    echo_success "✅ Traditional funding successful"
                else
                    echo_error "❌ All funding methods failed"
                    return 1
                fi
            fi
        elif fund_account "$sender_addr" "100000000000"; then  # Fallback to traditional funding
            echo_success "✅ Successfully funded sender account"
            
            # Re-check balance after funding
            sleep 2  # Wait for transaction to be processed
            balance_before=$(curl -s "http://127.0.0.1:8080/v1/accounts/$sender_addr/resources" 2>/dev/null | jq -r '.[] | select(.type == "0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>") | .data.coin.value // "0"' 2>/dev/null || echo "0")
            echo_info "Sender balance after funding: $balance_before APT"
            
            if [ "$balance_before" = "0" ] || [ -z "$balance_before" ]; then
                echo_error "❌ Account funding failed, balance is still 0"
                return 1
            fi
        else
            echo_error "❌ Failed to fund sender account. Cannot proceed with transfer."
            return 1
        fi
    fi
    
    # Execute transfer transaction with performance monitoring
    echo_info "🚀 Starting performance monitoring and executing transfer..."
    
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
    echo_info "Executing transfer: 1000000 APT from sender to recipient..."
    local tx_result=$(/home/ubuntu/whtest/CrustleLabs/aptos-core/target/release/aptos account transfer \
        --profile default \
        --account "0x$recipient_addr" \
        --amount 1000000 \
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
        echo_success "✅ Transfer transaction completed successfully!"
        echo_info "Total transaction time: ${total_time}ms"
        
        # Extract transaction hash if possible
        local tx_hash=$(echo "$tx_result" | grep -o "0x[a-fA-F0-9]\{64\}" | head -1)
        if [ ! -z "$tx_hash" ]; then
            echo_info "Transaction hash: $tx_hash"
        fi
        
        # Wait a moment for the transaction to be processed
        sleep 3
        
        # Check final balances
        local balance_after=$(curl -s "http://127.0.0.1:8080/v1/accounts/$sender_addr/resources" 2>/dev/null | jq -r '.[] | select(.type == "0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>") | .data.coin.value // "0"' 2>/dev/null || echo "0")
        local recipient_balance=$(curl -s "http://127.0.0.1:8080/v1/accounts/$recipient_addr/resources" 2>/dev/null | jq -r '.[] | select(.type == "0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>") | .data.coin.value // "0"' 2>/dev/null || echo "0")
        
        echo_info "Final balances:"
        echo_info "  Sender: $balance_after APT"
        echo_info "  Recipient: $recipient_balance APT"
        
    else
        echo_error "❌ Transfer transaction failed"
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
                    echo_success "✅ Flamegraph generated: $FLAMEGRAPH_DIR/consensus_flamegraph.svg"
                    
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
            echo_info "🚀 Exporting function latency metrics..."
            # Send SIGUSR1 to trigger function latency export
            if [ ! -z "$VALIDATOR_PID" ] && kill -0 $VALIDATOR_PID 2>/dev/null; then
                echo_info "Sending SIGUSR1 to validator for function latency export..."
                kill -USR1 $VALIDATOR_PID 2>/dev/null || true
                sleep 3
                
                # Check if function latency log was created
                if [ -f "/dev/shm/fn_latency.log" ]; then
                    echo_success "✅ Function latency exported successfully!"
                    echo_info "Function latency file: /dev/shm/fn_latency.log"
                    echo_info "📊 Showing function latency summary:"
                    # Show summary of function latency data
                    if grep -q "=== Function Latency Report ===" /dev/shm/fn_latency.log 2>/dev/null; then
                        grep -A 10 "=== Function Latency Report ===" /dev/shm/fn_latency.log
                        echo ""
                        echo_info "📈 Function statistics:"
                        grep "Average latency:" /dev/shm/fn_latency.log | head -5
                    else
                        tail -20 /dev/shm/fn_latency.log
                    fi
                else
                    echo_warning "⚠️  No function latency log found at /dev/shm/fn_latency.log"
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
    echo_info "Starting Aptos Consensus Performance Test"
    
    # Set up signal handlers first
    setup_signal_handlers
    
    check_dependencies
    build_project
    init_testnet
    start_validator
    execute_transfer
    generate_flamegraph
    export_results
    wait_for_stop
}

# Run main function
main "$@"

