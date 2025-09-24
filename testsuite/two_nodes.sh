#!/bin/bash

set -e

# Configuration - Change this path to match your environment
PROJECT_DIR="/home/ubuntu/whtest/CrustleLabs/aptos-core"

BASE_DIR="/dev/shm/two-node-testnet"
echo "=== Fixed Version: Two Validator Node Aptos Test Network ==="

# Clean up and create directories
rm -rf "$BASE_DIR"
mkdir -p "$BASE_DIR"/{alice,bob}

# Compile required tools
echo "Compiling necessary tools..."
cargo build -p aptos-node
cargo build -p aptos
cargo build -p aptos-framework

cd "$BASE_DIR"

echo "1. Generating keys for Alice..."
"$PROJECT_DIR/target/debug/aptos" genesis generate-keys --output-dir alice/
echo "2. Generating keys for Bob..."
"$PROJECT_DIR/target/debug/aptos" genesis generate-keys --output-dir bob/

echo "3. Compiling Move framework..."
# Generate framework.mrb file (default generates head.mrb)
"$PROJECT_DIR/target/debug/aptos-framework" release --target head
# Rename to framework.mrb
mv head.mrb framework.mrb

echo "4. Creating complete layout file..."
cat > layout.yaml << 'EOF'
root_key: "D04470F43AB6AEAA4EB616B72128881EEF77346F2075FFE68E14BA7DEBD8095E"
users:
  - alice
  - bob
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

echo "5. Setting up Alice validator configuration..."
"$PROJECT_DIR/target/debug/aptos" genesis set-validator-configuration \
    --local-repository-dir . \
    --username alice \
    --owner-public-identity-file alice/public-keys.yaml \
    --validator-host 127.0.0.1:6180 \
    --full-node-host 127.0.0.1:6182 \
    --stake-amount 100000000000000

echo "6. Setting up Bob validator configuration..."
"$PROJECT_DIR/target/debug/aptos" genesis set-validator-configuration \
    --local-repository-dir . \
    --username bob \
    --owner-public-identity-file bob/public-keys.yaml \
    --validator-host 127.0.0.1:6181 \
    --full-node-host 127.0.0.1:6183 \
    --stake-amount 100000000000000

echo "7. Generating genesis block..."
"$PROJECT_DIR/target/debug/aptos" genesis generate-genesis --local-repository-dir . --output-dir .

# Create node configuration function
create_node_config() {
    local user=$1
    local val_port=$2
    local fn_port=$3
    local api_port=$4
    local admin_port=$5
    local inspection_port=$6
    local backup_port=$7
    
    cat > "${user}/node.yaml" << EOF
base:
  data_dir: "$BASE_DIR/${user}/data"
  role: "validator"
  waypoint:
    from_file: "$BASE_DIR/waypoint.txt"

consensus:
  safety_rules:
    service:
      type: "local"
    backend:
      type: "on_disk_storage"
      path: "$BASE_DIR/${user}/safety-rules.yaml"
    initial_safety_rules_config:
      from_file:
        identity_blob_path: "$BASE_DIR/${user}/validator-identity.yaml"
        waypoint:
          from_file: "$BASE_DIR/waypoint.txt"

execution:
  genesis_file_location: "$BASE_DIR/genesis.blob"

admin_service:
  address: "0.0.0.0"
  port: $admin_port

inspection_service:
  address: "0.0.0.0"
  port: $inspection_port

validator_network:
  discovery_method: "onchain"
  identity:
    type: "from_file"
    path: "$BASE_DIR/${user}/validator-identity.yaml"
  listen_address: "/ip4/127.0.0.1/tcp/${val_port}"
  network_id: "validator"

full_node_networks:
  - network_id: "public"
    discovery_method: "none"
    identity:
      type: "from_file"
      path: "$BASE_DIR/${user}/validator-full-node-identity.yaml"
    listen_address: "/ip4/127.0.0.1/tcp/${fn_port}"

api:
  enabled: true
  address: "127.0.0.1:${api_port}"

storage:
  enable_indexer: true
  backup_service_address: "127.0.0.1:$backup_port"
  storage_pruner_config:
    ledger_pruner_config:
      enable: true
      prune_window: 1000000
      batch_size: 500
EOF
}

echo "8. Creating node configuration files..."
create_node_config "alice" 6180 6182 8080 9102 9101 6186
create_node_config "bob" 6181 6183 8081 9103 9104 6187

# Create data directories
mkdir -p alice/data bob/data

echo "9. Starting Alice node..."
"$PROJECT_DIR/target/debug/aptos-node" -f alice/node.yaml > alice/node.log 2>&1 &
ALICE_PID=$!

echo "10. Starting Bob node..."
"$PROJECT_DIR/target/debug/aptos-node" -f bob/node.yaml > bob/node.log 2>&1 &
BOB_PID=$!

echo "Alice node PID: $ALICE_PID"
echo "Bob node PID: $BOB_PID"

# Wait for nodes to start
echo "11. Waiting for nodes to start and synchronize..."
for i in {1..60}; do
    if curl -s http://127.0.0.1:8080/v1 > /dev/null 2>&1 && \
       curl -s http://127.0.0.1:8081/v1 > /dev/null 2>&1; then
        echo "Both nodes have started successfully!"
        echo ""
        echo "Two validator node test network is running:"
        echo "  Alice node API: http://127.0.0.1:8080"
        echo "  Bob node API:   http://127.0.0.1:8081"
        echo ""
        
        # Display block height
        alice_version=$(curl -s http://127.0.0.1:8080/v1/ledger_info | jq -r '.ledger_version // "0"')
        bob_version=$(curl -s http://127.0.0.1:8081/v1/ledger_info | jq -r '.ledger_version // "0"')
        echo "  Alice block height: $alice_version"
        echo "  Bob block height:   $bob_version"
        echo ""
        break
    fi
    echo "  Waiting... ($i/60)"
    sleep 2
done

if [ $i -eq 60 ]; then
    echo "Node startup timeout"
    kill $ALICE_PID $BOB_PID 2>/dev/null
    exit 1
fi

echo "Test command examples:"
echo "  curl http://127.0.0.1:8080/v1/ledger_info"
echo "  curl http://127.0.0.1:8081/v1/ledger_info"
echo ""
echo "Press Ctrl+C to stop network"

# Set up signal handling
trap "echo 'Stopping nodes...'; kill $ALICE_PID $BOB_PID 2>/dev/null; exit 0" INT TERM

# Monitor node status
while true; do
    sleep 10
    
    # Check if nodes are still running
    if ! kill -0 $ALICE_PID 2>/dev/null; then
        echo "Warning: Alice node has stopped"
        break
    fi
    if ! kill -0 $BOB_PID 2>/dev/null; then
        echo "Warning: Bob node has stopped"
        break
    fi
    
    # Display status every minute
    if [ $(($(date +%s) % 60)) -eq 0 ]; then
        alice_version=$(curl -s http://127.0.0.1:8080/v1/ledger_info 2>/dev/null | jq -r '.ledger_version // "N/A"')
        bob_version=$(curl -s http://127.0.0.1:8081/v1/ledger_info 2>/dev/null | jq -r '.ledger_version // "N/A"')
        echo "Status update - Alice: $alice_version, Bob: $bob_version"
    fi
done

echo "Network has stopped"

