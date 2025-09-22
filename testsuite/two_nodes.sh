#!/bin/bash

set -e

BASE_DIR="/dev/shm/two-node-testnet"
echo "=== 修正版：两验证节点 Aptos 测试网络 ==="

# 清理和创建目录
rm -rf "$BASE_DIR"
mkdir -p "$BASE_DIR"/{alice,bob}

# 编译所需工具
echo "编译必要的工具..."
cargo build -p aptos-node
cargo build -p aptos
cargo build -p aptos-framework

cd "$BASE_DIR"

echo "1. 为 Alice 生成密钥..."
/root/Desktop/whwork/CrustleLabs/aptos-core/target/debug/aptos genesis generate-keys --output-dir alice/
echo "2. 为 Bob 生成密钥..."
/root/Desktop/whwork/CrustleLabs/aptos-core/target/debug/aptos genesis generate-keys --output-dir bob/

echo "3. 编译 Move 框架..."
# 生成 framework.mrb 文件（默认生成 head.mrb）
/root/Desktop/whwork/CrustleLabs/aptos-core/target/debug/aptos-framework release --target head
# 重命名为 framework.mrb
mv head.mrb framework.mrb

echo "4. 创建完整的布局文件..."
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

echo "5. 设置 Alice 验证器配置..."
/root/Desktop/whwork/CrustleLabs/aptos-core/target/debug/aptos genesis set-validator-configuration \
    --local-repository-dir . \
    --username alice \
    --owner-public-identity-file alice/public-keys.yaml \
    --validator-host 127.0.0.1:6180 \
    --full-node-host 127.0.0.1:6182 \
    --stake-amount 100000000000000

echo "6. 设置 Bob 验证器配置..."
/root/Desktop/whwork/CrustleLabs/aptos-core/target/debug/aptos genesis set-validator-configuration \
    --local-repository-dir . \
    --username bob \
    --owner-public-identity-file bob/public-keys.yaml \
    --validator-host 127.0.0.1:6181 \
    --full-node-host 127.0.0.1:6183 \
    --stake-amount 100000000000000

echo "7. 生成创世区块..."
/root/Desktop/whwork/CrustleLabs/aptos-core/target/debug/aptos genesis generate-genesis --local-repository-dir . --output-dir .

# 创建节点配置函数
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

echo "8. 创建节点配置文件..."
create_node_config "alice" 6180 6182 8080 9102 9101 6186
create_node_config "bob" 6181 6183 8081 9103 9104 6187

# 创建数据目录
mkdir -p alice/data bob/data

echo "9. 启动 Alice 节点..."
/root/Desktop/whwork/CrustleLabs/aptos-core/target/debug/aptos-node -f alice/node.yaml > alice/node.log 2>&1 &
ALICE_PID=$!

echo "10. 启动 Bob 节点..."
/root/Desktop/whwork/CrustleLabs/aptos-core/target/debug/aptos-node -f bob/node.yaml > bob/node.log 2>&1 &
BOB_PID=$!

echo "Alice 节点 PID: $ALICE_PID"
echo "Bob 节点 PID: $BOB_PID"

# 等待节点启动
echo "11. 等待节点启动和同步..."
for i in {1..60}; do
    if curl -s http://127.0.0.1:8080/v1 > /dev/null 2>&1 && \
       curl -s http://127.0.0.1:8081/v1 > /dev/null 2>&1; then
        echo "✅ 两个节点都已启动成功!"
        echo ""
        echo "🎉 两验证节点测试网络运行中:"
        echo "  Alice 节点 API: http://127.0.0.1:8080"
        echo "  Bob 节点 API:   http://127.0.0.1:8081"
        echo ""
        
        # 显示区块高度
        alice_version=$(curl -s http://127.0.0.1:8080/v1/ledger_info | jq -r '.ledger_version // "0"')
        bob_version=$(curl -s http://127.0.0.1:8081/v1/ledger_info | jq -r '.ledger_version // "0"')
        echo "  Alice 区块高度: $alice_version"
        echo "  Bob 区块高度:   $bob_version"
        echo ""
        break
    fi
    echo "  等待中... ($i/60)"
    sleep 2
done

if [ $i -eq 60 ]; then
    echo "❌ 节点启动超时"
    kill $ALICE_PID $BOB_PID 2>/dev/null
    exit 1
fi

echo "💡 测试命令示例:"
echo "  curl http://127.0.0.1:8080/v1/ledger_info"
echo "  curl http://127.0.0.1:8081/v1/ledger_info"
echo ""
echo "按 Ctrl+C 停止网络"

# 设置信号处理
trap "echo '正在停止节点...'; kill $ALICE_PID $BOB_PID 2>/dev/null; exit 0" INT TERM

# 监控节点状态
while true; do
    sleep 10
    
    # 检查节点是否还在运行
    if ! kill -0 $ALICE_PID 2>/dev/null; then
        echo "⚠️  Alice 节点已停止"
        break
    fi
    if ! kill -0 $BOB_PID 2>/dev/null; then
        echo "⚠️  Bob 节点已停止"
        break
    fi
    
    # 每分钟显示一次状态
    if [ $(($(date +%s) % 60)) -eq 0 ]; then
        alice_version=$(curl -s http://127.0.0.1:8080/v1/ledger_info 2>/dev/null | jq -r '.ledger_version // "N/A"')
        bob_version=$(curl -s http://127.0.0.1:8081/v1/ledger_info 2>/dev/null | jq -r '.ledger_version // "N/A"')
        echo "📊 状态更新 - Alice: $alice_version, Bob: $bob_version"
    fi
done

echo "网络已停止"

