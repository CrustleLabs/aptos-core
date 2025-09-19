#!/bin/bash

# Aptos Performance Profiling and Flame Graph Generation Script
# This script provides comprehensive performance analysis with flame graphs

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
APTOS_CORE_PATH="${APTOS_CORE_PATH:-$(pwd)}"
PERFORMANCE_LOG_DIR="$HOME/.aptos/performance_logs"
FLAMEGRAPH_DIR="$PERFORMANCE_LOG_DIR/flamegraphs"
PROFILE_DURATION=30  # seconds
SAMPLE_FREQUENCY=99  # Hz

# Profiling configuration
ENABLE_CPU_PROFILING=true
ENABLE_MEMORY_PROFILING=false
ENABLE_IO_PROFILING=false
PROFILE_ALL_VALIDATORS=true

usage() {
    echo "Usage: $0 [OPTIONS] COMMAND"
    echo
    echo "Commands:"
    echo "  setup                 Setup profiling environment"
    echo "  profile               Start profiling session"
    echo "  analyze               Analyze existing perf data"
    echo "  flamegraph            Generate flame graphs from perf data"
    echo "  full-test             Run complete test with profiling"
    echo
    echo "Options:"
    echo "  -d, --duration SEC    Profiling duration in seconds (default: 30)"
    echo "  -f, --frequency HZ    Sampling frequency in Hz (default: 99)"
    echo "  -v, --validator ID    Profile specific validator (default: all)"
    echo "  --cpu                 Enable CPU profiling (default: on)"
    echo "  --memory              Enable memory profiling"
    echo "  --io                  Enable I/O profiling"
    echo "  -h, --help           Show this help"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--duration)
                PROFILE_DURATION="$2"
                shift 2
                ;;
            -f|--frequency)
                SAMPLE_FREQUENCY="$2"
                shift 2
                ;;
            -v|--validator)
                SPECIFIC_VALIDATOR="$2"
                PROFILE_ALL_VALIDATORS=false
                shift 2
                ;;
            --cpu)
                ENABLE_CPU_PROFILING=true
                shift
                ;;
            --memory)
                ENABLE_MEMORY_PROFILING=true
                shift
                ;;
            --io)
                ENABLE_IO_PROFILING=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            setup|profile|analyze|flamegraph|full-test)
                COMMAND="$1"
                shift
                break
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                usage
                exit 1
                ;;
        esac
    done
    
    if [ -z "$COMMAND" ]; then
        echo -e "${RED}Error: No command specified${NC}"
        usage
        exit 1
    fi
}

# Setup profiling environment
setup_profiling() {
    echo -e "${YELLOW}Setting up profiling environment...${NC}"
    
    # Check if perf is available
    if ! command -v perf &> /dev/null; then
        echo -e "${RED}Error: perf not found${NC}"
        echo -e "${YELLOW}On Ubuntu/Debian: sudo apt-get install linux-tools-generic${NC}"
        echo -e "${YELLOW}On CentOS/RHEL: sudo yum install perf${NC}"
        exit 1
    fi
    
    # Check perf permissions
    if [ "$(cat /proc/sys/kernel/perf_event_paranoid)" -gt 1 ]; then
        echo -e "${YELLOW}Warning: perf_event_paranoid is set to restrictive mode${NC}"
        echo -e "${YELLOW}You may need to run: sudo sysctl kernel.perf_event_paranoid=1${NC}"
        echo -e "${YELLOW}Or run with sudo for full profiling capabilities${NC}"
    fi
    
    # Setup FlameGraph tools
    if [ ! -d "FlameGraph" ]; then
        echo -e "${YELLOW}Cloning FlameGraph tools...${NC}"
        git clone https://github.com/brendangregg/FlameGraph.git
    fi
    
    # Create directories
    mkdir -p "$FLAMEGRAPH_DIR"
    mkdir -p "$PERFORMANCE_LOG_DIR/perf_data"
    
    # Install additional tools if needed
    if [ "$ENABLE_MEMORY_PROFILING" = true ]; then
        if ! command -v valgrind &> /dev/null; then
            echo -e "${YELLOW}Installing valgrind for memory profiling...${NC}"
            # Note: User should install valgrind manually
            echo -e "${YELLOW}Please install valgrind: sudo apt-get install valgrind${NC}"
        fi
    fi
    
    echo -e "${GREEN}✓ Profiling environment setup completed${NC}"
}

# Start profiling session
start_profiling() {
    echo -e "${YELLOW}Starting profiling session...${NC}"
    echo -e "${BLUE}Duration: ${PROFILE_DURATION}s${NC}"
    echo -e "${BLUE}Frequency: ${SAMPLE_FREQUENCY}Hz${NC}"
    
    # Find running aptos-node processes
    local pids=($(pgrep -f aptos-node))
    
    if [ ${#pids[@]} -eq 0 ]; then
        echo -e "${RED}Error: No aptos-node processes found${NC}"
        echo -e "${YELLOW}Please start the testnet first using: ./start_local_testnet.sh${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Found ${#pids[@]} aptos-node processes${NC}"
    
    # Start profiling for each process
    local profile_pids=()
    
    for i in "${!pids[@]}"; do
        local pid=${pids[$i]}
        local output_file="$PERFORMANCE_LOG_DIR/perf_data/validator_$i.perf.data"
        
        if [ "$PROFILE_ALL_VALIDATORS" = true ] || [ "$SPECIFIC_VALIDATOR" = "$i" ]; then
            echo -e "${BLUE}Starting profiling for validator $i (PID: $pid)...${NC}"
            
            # Build perf command
            local perf_cmd="perf record"
            
            if [ "$ENABLE_CPU_PROFILING" = true ]; then
                perf_cmd="$perf_cmd -g -F $SAMPLE_FREQUENCY"
            fi
            
            if [ "$ENABLE_MEMORY_PROFILING" = true ]; then
                perf_cmd="$perf_cmd -e cache-misses,cache-references,page-faults"
            fi
            
            if [ "$ENABLE_IO_PROFILING" = true ]; then
                perf_cmd="$perf_cmd -e block:block_rq_issue,block:block_rq_complete"
            fi
            
            perf_cmd="$perf_cmd -o $output_file -p $pid"
            
            # Start profiling in background
            eval "$perf_cmd" &
            profile_pids+=($!)
            
            echo -e "${GREEN}✓ Profiling started for validator $i${NC}"
        fi
    done
    
    echo -e "${YELLOW}Profiling for ${PROFILE_DURATION} seconds...${NC}"
    echo -e "${BLUE}You can now send transactions to capture their performance profile${NC}"
    
    # Wait for profiling duration
    sleep "$PROFILE_DURATION"
    
    # Stop profiling
    echo -e "${YELLOW}Stopping profiling...${NC}"
    for profile_pid in "${profile_pids[@]}"; do
        if kill -0 $profile_pid 2>/dev/null; then
            kill -INT $profile_pid
        fi
    done
    
    # Wait for perf processes to finish
    sleep 2
    
    echo -e "${GREEN}✓ Profiling session completed${NC}"
    echo -e "${BLUE}Perf data saved in: $PERFORMANCE_LOG_DIR/perf_data/${NC}"
}

# Analyze perf data
analyze_perf_data() {
    echo -e "${YELLOW}Analyzing perf data...${NC}"
    
    local perf_files=($(find "$PERFORMANCE_LOG_DIR/perf_data" -name "*.perf.data" 2>/dev/null))
    
    if [ ${#perf_files[@]} -eq 0 ]; then
        echo -e "${RED}Error: No perf data files found${NC}"
        echo -e "${YELLOW}Please run profiling first: $0 profile${NC}"
        exit 1
    fi
    
    for perf_file in "${perf_files[@]}"; do
        local validator_name=$(basename "$perf_file" .perf.data)
        local report_file="$PERFORMANCE_LOG_DIR/${validator_name}_perf_report.txt"
        
        echo -e "${BLUE}Analyzing $validator_name...${NC}"
        
        # Generate perf report
        perf report -i "$perf_file" --stdio > "$report_file"
        
        # Extract top functions
        echo -e "${GREEN}Top CPU consuming functions for $validator_name:${NC}"
        perf report -i "$perf_file" --stdio | head -30 | grep -E "^\s*[0-9]+\.[0-9]+%" | head -10
        
        echo -e "${BLUE}Full report saved: $report_file${NC}"
    done
}

# Generate flame graphs
generate_flamegraphs() {
    echo -e "${YELLOW}Generating flame graphs...${NC}"
    
    local perf_files=($(find "$PERFORMANCE_LOG_DIR/perf_data" -name "*.perf.data" 2>/dev/null))
    
    if [ ${#perf_files[@]} -eq 0 ]; then
        echo -e "${RED}Error: No perf data files found${NC}"
        exit 1
    fi
    
    # Ensure FlameGraph tools are available
    if [ ! -d "FlameGraph" ]; then
        echo -e "${YELLOW}FlameGraph tools not found, setting up...${NC}"
        setup_profiling
    fi
    
    export PATH="$PWD/FlameGraph:$PATH"
    
    for perf_file in "${perf_files[@]}"; do
        local validator_name=$(basename "$perf_file" .perf.data)
        local flamegraph_file="$FLAMEGRAPH_DIR/${validator_name}_flamegraph.svg"
        
        echo -e "${BLUE}Generating flame graph for $validator_name...${NC}"
        
        # Generate flame graph
        perf script -i "$perf_file" | \
            FlameGraph/stackcollapse-perf.pl | \
            FlameGraph/flamegraph.pl \
            --title "Aptos Node Performance - $validator_name" \
            --subtitle "CPU Flame Graph" \
            --width 1600 \
            --height 800 \
            --colors hot > "$flamegraph_file"
        
        echo -e "${GREEN}✓ Flame graph generated: $flamegraph_file${NC}"
        
        # Generate differential flame graph if we have baseline
        local baseline_file="$PERFORMANCE_LOG_DIR/perf_data/baseline_${validator_name}.perf.data"
        if [ -f "$baseline_file" ]; then
            local diff_flamegraph="$FLAMEGRAPH_DIR/${validator_name}_diff_flamegraph.svg"
            echo -e "${BLUE}Generating differential flame graph...${NC}"
            
            # Create differential flame graph
            perf script -i "$baseline_file" | FlameGraph/stackcollapse-perf.pl > /tmp/baseline.folded
            perf script -i "$perf_file" | FlameGraph/stackcollapse-perf.pl > /tmp/current.folded
            
            FlameGraph/difffolded.pl /tmp/baseline.folded /tmp/current.folded | \
                FlameGraph/flamegraph.pl \
                --title "Aptos Node Performance Diff - $validator_name" \
                --subtitle "CPU Differential Flame Graph (red=regression, blue=improvement)" \
                > "$diff_flamegraph"
            
            echo -e "${GREEN}✓ Differential flame graph generated: $diff_flamegraph${NC}"
            
            # Cleanup
            rm -f /tmp/baseline.folded /tmp/current.folded
        fi
    done
    
    echo -e "${GREEN}✓ All flame graphs generated in: $FLAMEGRAPH_DIR${NC}"
}

# Run full performance test
run_full_test() {
    echo -e "${BLUE}=== Running Full Performance Test ===${NC}"
    
    # Setup
    setup_profiling
    
    # Start testnet if not running
    if ! curl -s http://127.0.0.1:8080/v1 > /dev/null 2>&1; then
        echo -e "${YELLOW}Testnet not running, starting...${NC}"
        ./start_local_testnet.sh &
        TESTNET_PID=$!
        
        # Wait for testnet to be ready
        local max_attempts=60
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            if curl -s http://127.0.0.1:8080/v1 > /dev/null 2>&1; then
                echo -e "${GREEN}✓ Testnet is ready!${NC}"
                break
            fi
            echo -e "${YELLOW}Waiting for testnet... ($attempt/$max_attempts)${NC}"
            sleep 2
            ((attempt++))
        done
        
        if [ $attempt -gt $max_attempts ]; then
            echo -e "${RED}Error: Testnet failed to start${NC}"
            exit 1
        fi
    fi
    
    # Start profiling
    echo -e "${YELLOW}Starting profiling session...${NC}"
    start_profiling &
    PROFILING_PID=$!
    
    # Wait a moment for profiling to start
    sleep 2
    
    # Send test transactions
    echo -e "${YELLOW}Sending test transactions...${NC}"
    ./send_transfer.sh -c 10 -i 0.5 -m
    
    # Wait for profiling to complete
    wait $PROFILING_PID
    
    # Analyze results
    echo -e "${YELLOW}Analyzing results...${NC}"
    analyze_perf_data
    generate_flamegraphs
    
    # Generate comprehensive report
    generate_comprehensive_report
    
    echo -e "${GREEN}✓ Full performance test completed${NC}"
}

# Generate comprehensive performance report
generate_comprehensive_report() {
    echo -e "${YELLOW}Generating comprehensive performance report...${NC}"
    
    local report_file="$PERFORMANCE_LOG_DIR/comprehensive_report.html"
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Aptos Transaction Performance Analysis</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f8ff; padding: 20px; border-radius: 5px; }
        .section { margin: 20px 0; }
        .metric { background-color: #f9f9f9; padding: 10px; margin: 5px 0; border-left: 4px solid #007acc; }
        .flamegraph { text-align: center; margin: 20px 0; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .good { color: green; }
        .warning { color: orange; }
        .error { color: red; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Aptos Transaction Performance Analysis</h1>
        <p>Generated on: $(date)</p>
        <p>Test Configuration: ${TRANSACTION_COUNT} transactions, ${PROFILE_DURATION}s profiling</p>
    </div>
    
    <div class="section">
        <h2>Executive Summary</h2>
        <div class="metric">
            <strong>End-to-End Transaction Latency:</strong> 
            <span id="e2e-latency">Calculating...</span>
        </div>
        <div class="metric">
            <strong>Transaction Throughput:</strong> 
            <span id="throughput">Calculating...</span>
        </div>
        <div class="metric">
            <strong>Consensus Efficiency:</strong> 
            <span id="consensus-efficiency">Calculating...</span>
        </div>
    </div>
    
    <div class="section">
        <h2>Stage-by-Stage Performance</h2>
        <table>
            <tr>
                <th>Stage</th>
                <th>Average (ms)</th>
                <th>P95 (ms)</th>
                <th>P99 (ms)</th>
                <th>Count</th>
            </tr>
EOF
    
    # Add stage performance data (would be populated by actual data)
    for stage in "mempool_received" "payload_pull" "proposal_generation" "transaction_execution" "vote_generation" "block_commit"; do
        cat >> "$report_file" << EOF
            <tr>
                <td>$stage</td>
                <td id="${stage}-avg">-</td>
                <td id="${stage}-p95">-</td>
                <td id="${stage}-p99">-</td>
                <td id="${stage}-count">-</td>
            </tr>
EOF
    done
    
    cat >> "$report_file" << EOF
        </table>
    </div>
    
    <div class="section">
        <h2>CPU Flame Graphs</h2>
EOF
    
    # Add flame graph links
    for flamegraph in "$FLAMEGRAPH_DIR"/*.svg; do
        if [ -f "$flamegraph" ]; then
            local graph_name=$(basename "$flamegraph")
            cat >> "$report_file" << EOF
        <div class="flamegraph">
            <h3>$graph_name</h3>
            <a href="flamegraphs/$graph_name" target="_blank">
                <img src="flamegraphs/$graph_name" style="max-width: 100%; height: 300px;">
            </a>
        </div>
EOF
        fi
    done
    
    cat >> "$report_file" << EOF
    </div>
    
    <div class="section">
        <h2>Performance Recommendations</h2>
        <ul>
            <li>Monitor transaction execution time - target &lt; 10ms for simple transfers</li>
            <li>Consensus latency should be &lt; 100ms for fast finality</li>
            <li>Mempool processing should be &lt; 1ms per transaction</li>
            <li>Block execution parallelism efficiency should be &gt; 80%</li>
        </ul>
    </div>
    
    <script>
        // JavaScript to populate dynamic data
        // This would be populated by actual performance data
        document.getElementById('e2e-latency').textContent = 'XX.X ms (target: <100ms)';
        document.getElementById('throughput').textContent = 'XXX TPS (target: >1000 TPS)';
        document.getElementById('consensus-efficiency').textContent = 'XX% (target: >90%)';
    </script>
</body>
</html>
EOF
    
    echo -e "${GREEN}✓ Comprehensive report generated: $report_file${NC}"
    
    # Try to open in browser
    if command -v xdg-open &> /dev/null; then
        xdg-open "$report_file"
    elif command -v open &> /dev/null; then
        open "$report_file"
    else
        echo -e "${BLUE}Open the report in your browser: file://$report_file${NC}"
    fi
}

# Cleanup function
cleanup() {
    echo -e "${YELLOW}Cleaning up...${NC}"
    
    # Stop any running profiling processes
    pkill -f "perf record" || true
    
    # Stop testnet if we started it
    if [ -n "$TESTNET_PID" ]; then
        kill $TESTNET_PID 2>/dev/null || true
    fi
}

# Main execution
main() {
    declare -a VALIDATOR_PIDS
    declare TESTNET_PID
    declare PROFILING_PID
    
    # Setup signal handlers
    trap cleanup EXIT INT TERM
    
    case "$COMMAND" in
        setup)
            setup_profiling
            ;;
        profile)
            start_profiling
            ;;
        analyze)
            analyze_perf_data
            ;;
        flamegraph)
            generate_flamegraphs
            ;;
        full-test)
            run_full_test
            ;;
        *)
            echo -e "${RED}Unknown command: $COMMAND${NC}"
            usage
            exit 1
            ;;
    esac
}

# Parse arguments and run
parse_arguments "$@"
main
