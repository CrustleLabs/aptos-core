#!/bin/bash

# Transfer Transaction Sender with Performance Monitoring
# This script sends transfer transactions and monitors their performance

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
REST_URL="http://127.0.0.1:8080"
TRANSFER_AMOUNT=1000000  # 0.01 APT (in octas)

# Default values
TRANSACTION_COUNT=1
INTERVAL=1
PROFILE_SENDER="sender"
PROFILE_RECEIVER="receiver"

# Parse command line arguments
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -c, --count NUM       Number of transactions to send (default: 1)"
    echo "  -i, --interval SEC    Interval between transactions in seconds (default: 1)"
    echo "  -a, --amount OCTAS    Transfer amount in octas (default: 1000000)"
    echo "  -s, --sender PROFILE  Sender profile name (default: sender)"
    echo "  -r, --receiver PROFILE Receiver profile name (default: receiver)"
    echo "  -m, --monitor         Enable detailed monitoring"
    echo "  -h, --help           Show this help"
    echo
    echo "Examples:"
    echo "  $0 -c 10 -i 0.5       # Send 10 transactions with 0.5s interval"
    echo "  $0 -a 5000000 -m      # Send 1 transaction of 0.05 APT with monitoring"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--count)
            TRANSACTION_COUNT="$2"
            shift 2
            ;;
        -i|--interval)
            INTERVAL="$2"
            shift 2
            ;;
        -a|--amount)
            TRANSFER_AMOUNT="$2"
            shift 2
            ;;
        -s|--sender)
            PROFILE_SENDER="$2"
            shift 2
            ;;
        -r|--receiver)
            PROFILE_RECEIVER="$2"
            shift 2
            ;;
        -m|--monitor)
            ENABLE_MONITORING=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# Check if testnet is running
check_testnet() {
    echo -e "${YELLOW}Checking testnet status...${NC}"
    
    if ! curl -s "$REST_URL/v1" > /dev/null; then
        echo -e "${RED}Error: Testnet is not running or not accessible${NC}"
        echo -e "${YELLOW}Please start the testnet first using: ./start_local_testnet.sh${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Testnet is running${NC}"
}

# Get account information
get_account_info() {
    echo -e "${YELLOW}Getting account information...${NC}"
    
    # Get sender address and balance
    SENDER_ADDR=$(cd "$APTOS_CORE_PATH" && ./target/release/aptos config show-profiles --profile "$PROFILE_SENDER" | grep "account" | awk '{print $2}')
    RECEIVER_ADDR=$(cd "$APTOS_CORE_PATH" && ./target/release/aptos config show-profiles --profile "$PROFILE_RECEIVER" | grep "account" | awk '{print $2}')
    
    if [ -z "$SENDER_ADDR" ] || [ -z "$RECEIVER_ADDR" ]; then
        echo -e "${RED}Error: Could not get account addresses${NC}"
        echo -e "${YELLOW}Please ensure accounts are set up properly${NC}"
        exit 1
    fi
    
    # Get sender balance
    SENDER_BALANCE=$(curl -s "$REST_URL/v1/accounts/$SENDER_ADDR/resource/0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>" | jq -r '.data.coin.value // "0"')
    
    echo -e "${GREEN}✓ Account information retrieved${NC}"
    echo -e "${BLUE}Sender: $SENDER_ADDR (Balance: $SENDER_BALANCE octas)${NC}"
    echo -e "${BLUE}Receiver: $RECEIVER_ADDR${NC}"
    echo -e "${BLUE}Transfer Amount: $TRANSFER_AMOUNT octas${NC}"
    
    # Check if sender has enough balance
    if [ "$SENDER_BALANCE" -lt "$((TRANSFER_AMOUNT * TRANSACTION_COUNT + 1000000))" ]; then
        echo -e "${RED}Warning: Sender may not have enough balance for all transactions${NC}"
    fi
}

# Send a single transfer transaction
send_transfer() {
    local tx_num=$1
    local start_time=$(date +%s.%N)
    
    echo -e "${BLUE}Sending transaction $tx_num/$TRANSACTION_COUNT...${NC}"
    
    cd "$APTOS_CORE_PATH"
    
    # Send transfer transaction with detailed output
    local transfer_output
    transfer_output=$(./target/release/aptos account transfer \
        --profile "$PROFILE_SENDER" \
        --account "$RECEIVER_ADDR" \
        --amount "$TRANSFER_AMOUNT" \
        --rest-url "$REST_URL" \
        --max-gas 2000 \
        --gas-unit-price 100 \
        2>&1)
    
    local exit_code=$?
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)
    
    if [ $exit_code -eq 0 ]; then
        # Extract transaction hash from output
        local tx_hash=$(echo "$transfer_output" | grep -oE '"hash":"[^"]*"' | cut -d'"' -f4)
        
        echo -e "${GREEN}✓ Transaction $tx_num sent successfully${NC}"
        echo -e "${BLUE}  Hash: $tx_hash${NC}"
        echo -e "${BLUE}  Duration: ${duration}s${NC}"
        
        # Log transaction details for performance tracking
        if [ "$ENABLE_MONITORING" = true ]; then
            echo "PERF_TRACK: Transaction $tx_num sent - Hash: $tx_hash, CLI_Duration: ${duration}s" >> "$PERFORMANCE_LOG_DIR/transfer_log.txt"
        fi
        
        # Wait for transaction to be committed
        echo -e "${YELLOW}  Waiting for transaction confirmation...${NC}"
        local confirm_start=$(date +%s.%N)
        
        while true; do
            local tx_status=$(curl -s "$REST_URL/v1/transactions/by_hash/$tx_hash" | jq -r '.success // false')
            if [ "$tx_status" = "true" ]; then
                local confirm_end=$(date +%s.%N)
                local confirm_duration=$(echo "$confirm_end - $confirm_start" | bc -l)
                echo -e "${GREEN}  ✓ Transaction confirmed in ${confirm_duration}s${NC}"
                break
            elif [ "$tx_status" = "false" ]; then
                echo -e "${RED}  ✗ Transaction failed${NC}"
                break
            fi
            
            sleep 0.1
        done
        
        return 0
    else
        echo -e "${RED}✗ Transaction $tx_num failed${NC}"
        echo -e "${RED}Error: $transfer_output${NC}"
        return 1
    fi
}

# Monitor system resources during test
monitor_resources() {
    if [ "$ENABLE_MONITORING" != true ]; then
        return
    fi
    
    echo -e "${YELLOW}Starting resource monitoring...${NC}"
    
    # Monitor CPU and memory usage
    {
        echo "timestamp,cpu_percent,memory_mb,disk_io_read,disk_io_write"
        while true; do
            local timestamp=$(date +%s.%N)
            local cpu_percent=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
            local memory_mb=$(free -m | awk 'NR==2{printf "%.1f", $3}')
            local disk_read=$(cat /proc/diskstats | awk '{read += $6} END {print read}')
            local disk_write=$(cat /proc/diskstats | awk '{write += $10} END {print write}')
            
            echo "$timestamp,$cpu_percent,$memory_mb,$disk_read,$disk_write"
            sleep 0.5
        done
    } > "$PERFORMANCE_LOG_DIR/resource_monitor.csv" &
    
    MONITOR_PID=$!
}

# Stop resource monitoring
stop_monitoring() {
    if [ -n "$MONITOR_PID" ] && kill -0 $MONITOR_PID 2>/dev/null; then
        kill $MONITOR_PID
        echo -e "${GREEN}✓ Resource monitoring stopped${NC}"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}=== Aptos Transfer Transaction Performance Test ===${NC}"
    echo -e "${BLUE}Transaction Count: $TRANSACTION_COUNT${NC}"
    echo -e "${BLUE}Interval: ${INTERVAL}s${NC}"
    echo -e "${BLUE}Amount: $TRANSFER_AMOUNT octas${NC}"
    echo -e "${BLUE}Monitoring: ${ENABLE_MONITORING:-false}${NC}"
    echo
    
    check_testnet
    get_account_info
    
    # Create performance log directory
    mkdir -p "$PERFORMANCE_LOG_DIR"
    
    # Start monitoring if enabled
    if [ "$ENABLE_MONITORING" = true ]; then
        monitor_resources
    fi
    
    # Record test start time
    local test_start=$(date +%s.%N)
    local successful_transactions=0
    local failed_transactions=0
    
    # Send transactions
    echo -e "${YELLOW}Starting transaction sending...${NC}"
    
    for i in $(seq 1 $TRANSACTION_COUNT); do
        if send_transfer $i; then
            ((successful_transactions++))
        else
            ((failed_transactions++))
        fi
        
        # Wait interval before next transaction (except for last one)
        if [ $i -lt $TRANSACTION_COUNT ]; then
            sleep "$INTERVAL"
        fi
    done
    
    local test_end=$(date +%s.%N)
    local total_duration=$(echo "$test_end - $test_start" | bc -l)
    
    # Stop monitoring
    stop_monitoring
    
    # Generate summary
    echo
    echo -e "${GREEN}=== Test Summary ===${NC}"
    echo -e "${BLUE}Total Duration: ${total_duration}s${NC}"
    echo -e "${GREEN}Successful Transactions: $successful_transactions${NC}"
    echo -e "${RED}Failed Transactions: $failed_transactions${NC}"
    
    if [ $successful_transactions -gt 0 ]; then
        local avg_tps=$(echo "scale=3; $successful_transactions / $total_duration" | bc -l)
        echo -e "${BLUE}Average TPS: $avg_tps${NC}"
    fi
    
    # Generate performance report if monitoring was enabled
    if [ "$ENABLE_MONITORING" = true ]; then
        echo -e "${YELLOW}Generating performance analysis...${NC}"
        sleep 5  # Wait for logs to be written
        generate_performance_report
    fi
    
    echo -e "${GREEN}Performance test completed!${NC}"
    echo -e "${BLUE}Logs and reports available in: $PERFORMANCE_LOG_DIR${NC}"
}

# Run main function
main "$@"
