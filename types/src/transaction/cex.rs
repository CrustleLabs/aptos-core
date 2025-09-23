use serde::{Deserialize, Serialize};

// 常量定义
pub const ASSETS_SIZE: usize = 256;
pub const PERPS_SIZE: usize = 256;
pub const ACCOUNT_ID_LENGTH: usize = 20;
pub const ORDER_ID_LENGTH: usize = 20;

// ClobPair represents the different trading pair types supported
#[derive(Clone, Copy, Debug, Hash, Eq, PartialEq, Serialize, Deserialize)]
#[repr(u32)]
pub enum ClobPair {
    Unspecified = 0,
    BtcUsdcSpot = 1,
    BtcUsdcPerpetual = 2,
    EthUsdcSpot = 3,
    EthUsdcPerpetual = 4,
}

#[repr(align(8))]
#[derive(Clone, Copy, Debug, Hash, Eq, PartialEq, Serialize, Deserialize)]
pub struct AssetPosition {
    pub asset_id: u32,
    pub quantums: u64,
}

#[repr(align(16))]
#[derive(Clone, Copy, Debug, Hash, Eq, PartialEq, Serialize, Deserialize)]
pub struct PerpetualPosition {
    pub perpetual_id: u32,
    // int64精度不够,实际是gcc/clang __int128
    pub short_quantums: i128,
    pub long_quantums: i128,
    pub funding_index: i128,
}

#[repr(align(16))]
#[derive(Clone, Copy, Debug, Hash, Eq, PartialEq, Serialize, Deserialize)]
pub struct SubaccountId {
    pub subaccount_id: [u8; ACCOUNT_ID_LENGTH],
    // Currently limited to 128*1000 subaccounts per owner.
    pub number: u32,
}

// ConditionType defines the trigger conditions for conditional orders
#[derive(Clone, Copy, Debug, Hash, Eq, PartialEq, Serialize, Deserialize)]
#[repr(u32)]
pub enum ConditionType {
    Unspecified = 0,
    StopLoss = 1,
    TakeProfit = 2,
}

#[derive(Clone, Copy, Debug, Hash, Eq, PartialEq, Serialize, Deserialize)]
#[repr(u32)]
pub enum GoodTill {
    Block = 0,
    Gtc = 1,
    Gtd = 2,
}

#[derive(Clone, Copy, Debug, Hash, Eq, PartialEq, Serialize, Deserialize)]
#[repr(u32)]
pub enum TimeInForce {
    Unspecified = 0,
    // Immediate-or-cancel orders
    Ioc = 1,
    // Fill-or-kill orders (不能拆单，不成交订单则取消)
    Fok = 2,
    // All-or-none orders (不能拆单，不成交订单放入订单薄)
    Aon = 3,
    Alo = 4, // post only
}

#[derive(Clone, Copy, Debug, Hash, Eq, PartialEq, Serialize, Deserialize)]
#[repr(u32)]
pub enum OrderState {
    Unspecified = 0,
    Pending = 1,
    Validated = 2,
    Active = 3,
    PartiallyFilled = 4,
    Filled = 5,
    Cancelled = 6,
    Rejected = 7,
}

#[derive(Clone, Copy, Debug, Hash, Eq, PartialEq, Serialize, Deserialize)]
#[repr(u32)]
pub enum Side {
    Unspecified = 0,
    Buy = 1,
    Sell = 2,
}

#[derive(Clone, Copy, Debug, Hash, Eq, PartialEq, Serialize, Deserialize)]
#[repr(u32)]
pub enum Operation {
    Unspecified = 0,
    Place = 1,
    Cancel = 2,
    Replace = 3, // not supported current
}

#[derive(Clone, Copy, Debug, Hash, Eq, PartialEq, Serialize, Deserialize)]
#[repr(u32)]
pub enum OrderCateType {
    Regular = 0,
    Liquidation = 1,
    Adl = 2,
    Funding = 3, // not supported current
}

#[repr(align(64))]
#[derive(Clone, Copy, Debug, Hash, Eq, PartialEq, Serialize, Deserialize)]
pub struct Order {
    pub subaccount_id: SubaccountId,
    pub nonce: u64,
    pub clob_pair: ClobPair,        // symbol, btc_usdc_spot
    pub side: Side,                 // buy/sell
    pub quantums: u64,              // Total quantity in quantums
    pub subticks: u64,              // 最小交易数量，代币精度
    pub order_basic_type: u32,      // market, limit, etc.
    pub good_till: GoodTill,        // GTC, GTD, etc.
    pub time_in_force: TimeInForce, // IOC, FOK, AON, ALO
    pub reduce_only: bool,
    pub condition_type: ConditionType, // normal, stop loss, take profit
    pub trigger_subticks: u64,         // conditional orders trigger subticks
    pub operation: Operation,          // place, cancel, replace
    pub timestamp: u64,                // Order creation timestamp
    pub target_nonce: u64,             // use for cancel or replace operation

    pub order_id: [u8; ORDER_ID_LENGTH], // generated order id
    pub state: OrderState,               // Current state of the order in the system lifecycle
    pub remaining_quantums: u64,         // Remaining quantity to be filled
    pub fill_amount: u64,                // Amount already filled
    pub cate_type: OrderCateType,        // regular, liquidation, ADL, funding type
    pub seq_num: u64,                    // 不同交易对序列不一样
}

#[repr(align(64))]
#[derive(Clone, Copy, Debug, Hash, Eq, PartialEq, Serialize, Deserialize)]
pub struct FillOrder {
    pub fill_id: [u8; ORDER_ID_LENGTH],  // generated fill order id
    pub trade_id: [u8; ORDER_ID_LENGTH], // generated trade order id
    pub maker_order_id: [u8; ORDER_ID_LENGTH],
    pub taker_order_id: [u8; ORDER_ID_LENGTH],
    pub fill_quantums: u64,
    pub timestamp: u64,
}

#[repr(align(8))]
#[derive(Clone, Debug, Hash, Eq, PartialEq, Serialize, Deserialize)]
pub struct Response {
    // TODO
}

#[repr(align(16))]
#[derive(Clone, Debug, Hash, Eq, PartialEq, Serialize, Deserialize)]
pub struct Account {
    pub id: SubaccountId,
    pub assets_size: u32,
    pub perps_size: u32,
    pub assets: Vec<AssetPosition>,    // asset positions
    pub perps: Vec<PerpetualPosition>, // perpetual positions
}

#[repr(align(16))]
#[derive(Clone, Debug, Hash, Eq, PartialEq, Serialize, Deserialize)]
pub struct FundingSamplingEpoch {
    pub timestamp: u64,
    pub block_height: u64,
    pub rate: Vec<u64>,
}

impl FundingSamplingEpoch {
    pub fn new(timestamp: u64, block_height: u64) -> Self {
        Self {
            timestamp,
            block_height,
            rate: vec![0u64; PERPS_SIZE],
        }
    }

    pub fn with_rate(timestamp: u64, block_height: u64, rate: Vec<u64>) -> Result<Self, String> {
        if rate.len() != PERPS_SIZE {
            return Err(format!(
                "Rate vector must have exactly {} elements",
                PERPS_SIZE
            ));
        }
        Ok(Self {
            timestamp,
            block_height,
            rate,
        })
    }
}

#[repr(align(16))]
#[derive(Clone, Debug, Hash, Eq, PartialEq, Serialize, Deserialize)]
pub struct FundingSettlementEpoch {
    pub timestamp: u64,
    pub block_height: u64,
    pub rate: Vec<u64>,
}

impl FundingSettlementEpoch {
    pub fn new(timestamp: u64, block_height: u64) -> Self {
        Self {
            timestamp,
            block_height,
            rate: vec![0u64; PERPS_SIZE],
        }
    }

    pub fn with_rate(timestamp: u64, block_height: u64, rate: Vec<u64>) -> Result<Self, String> {
        if rate.len() != PERPS_SIZE {
            return Err(format!(
                "Rate vector must have exactly {} elements",
                PERPS_SIZE
            ));
        }
        Ok(Self {
            timestamp,
            block_height,
            rate,
        })
    }
}

#[derive(Clone, Debug, Hash, Eq, PartialEq, Serialize, Deserialize)]
pub struct CEXOrder {
    pub order: Order,
}

impl CEXOrder {
    pub fn new(order: Order) -> Self {
        Self { order }
    }
}
