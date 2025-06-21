
<a id="0x1_scheduled_txns"></a>

# Module `0x1::scheduled_txns`



-  [Enum `ScheduledFunction`](#0x1_scheduled_txns_ScheduledFunction)
-  [Struct `ScheduledTransaction`](#0x1_scheduled_txns_ScheduledTransaction)
-  [Resource `ScheduledTransactionContainer`](#0x1_scheduled_txns_ScheduledTransactionContainer)
-  [Struct `ScheduledTransactionInfoWithKey`](#0x1_scheduled_txns_ScheduledTransactionInfoWithKey)
-  [Struct `ScheduleMapKey`](#0x1_scheduled_txns_ScheduleMapKey)
-  [Resource `ScheduleQueue`](#0x1_scheduled_txns_ScheduleQueue)
-  [Resource `AuxiliaryData`](#0x1_scheduled_txns_AuxiliaryData)
-  [Resource `ToRemoveTbl`](#0x1_scheduled_txns_ToRemoveTbl)
-  [Enum `CancelledTxnCode`](#0x1_scheduled_txns_CancelledTxnCode)
-  [Struct `TransactionFailedEvent`](#0x1_scheduled_txns_TransactionFailedEvent)
-  [Struct `ShutdownEvent`](#0x1_scheduled_txns_ShutdownEvent)
-  [Struct `KeyAndTxnInfo`](#0x1_scheduled_txns_KeyAndTxnInfo)
-  [Struct `State`](#0x1_scheduled_txns_State)
-  [Constants](#@Constants_0)
-  [Function `initialize`](#0x1_scheduled_txns_initialize)
-  [Function `shutdown`](#0x1_scheduled_txns_shutdown)
-  [Function `set_expiry_delta`](#0x1_scheduled_txns_set_expiry_delta)
-  [Function `new_scheduled_transaction`](#0x1_scheduled_txns_new_scheduled_transaction)
-  [Function `insert`](#0x1_scheduled_txns_insert)
-  [Function `cancel`](#0x1_scheduled_txns_cancel)
-  [Function `u256_to_u64_safe`](#0x1_scheduled_txns_u256_to_u64_safe)
-  [Function `hash_to_u256`](#0x1_scheduled_txns_hash_to_u256)
-  [Function `move_scheduled_transaction_container`](#0x1_scheduled_txns_move_scheduled_transaction_container)
-  [Function `cancel_internal`](#0x1_scheduled_txns_cancel_internal)
-  [Function `get_ready_transactions`](#0x1_scheduled_txns_get_ready_transactions)
-  [Function `finish_execution`](#0x1_scheduled_txns_finish_execution)
-  [Function `remove_txns`](#0x1_scheduled_txns_remove_txns)
-  [Function `execute_user_function_wrapper`](#0x1_scheduled_txns_execute_user_function_wrapper)
-  [Function `emit_transaction_failed_event`](#0x1_scheduled_txns_emit_transaction_failed_event)
-  [Function `step`](#0x1_scheduled_txns_step)


<pre><code><b>use</b> <a href="account.md#0x1_account">0x1::account</a>;
<b>use</b> <a href="aptos_coin.md#0x1_aptos_coin">0x1::aptos_coin</a>;
<b>use</b> <a href="../../aptos-stdlib/../move-stdlib/doc/bcs.md#0x1_bcs">0x1::bcs</a>;
<b>use</b> <a href="big_ordered_map.md#0x1_big_ordered_map">0x1::big_ordered_map</a>;
<b>use</b> <a href="coin.md#0x1_coin">0x1::coin</a>;
<b>use</b> <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error">0x1::error</a>;
<b>use</b> <a href="event.md#0x1_event">0x1::event</a>;
<b>use</b> <a href="../../aptos-stdlib/doc/from_bcs.md#0x1_from_bcs">0x1::from_bcs</a>;
<b>use</b> <a href="fungible_asset.md#0x1_fungible_asset">0x1::fungible_asset</a>;
<b>use</b> <a href="../../aptos-stdlib/../move-stdlib/doc/hash.md#0x1_hash">0x1::hash</a>;
<b>use</b> <a href="object.md#0x1_object">0x1::object</a>;
<b>use</b> <a href="../../aptos-stdlib/../move-stdlib/doc/option.md#0x1_option">0x1::option</a>;
<b>use</b> <a href="primary_fungible_store.md#0x1_primary_fungible_store">0x1::primary_fungible_store</a>;
<b>use</b> <a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">0x1::signer</a>;
<b>use</b> <a href="system_addresses.md#0x1_system_addresses">0x1::system_addresses</a>;
<b>use</b> <a href="../../aptos-stdlib/doc/table.md#0x1_table">0x1::table</a>;
<b>use</b> <a href="timestamp.md#0x1_timestamp">0x1::timestamp</a>;
<b>use</b> <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">0x1::vector</a>;
</code></pre>



<a id="0x1_scheduled_txns_ScheduledFunction"></a>

## Enum `ScheduledFunction`



<pre><code>enum <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledFunction">ScheduledFunction</a> <b>has</b> <b>copy</b>, drop, store
</code></pre>



<details>
<summary>Variants</summary>


<details>
<summary>V1</summary>


<details>
<summary>Fields</summary>


<dl>
<dt>
<code>0: |<a href="../../aptos-stdlib/../move-stdlib/doc/option.md#0x1_option_Option">option::Option</a>&lt;<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>&gt;| <b>has</b> <b>copy</b> + drop + store</code>
</dt>
<dd>

</dd>
</dl>


</details>

</details>

</details>

<a id="0x1_scheduled_txns_ScheduledTransaction"></a>

## Struct `ScheduledTransaction`

ScheduledTransaction with scheduled_time, gas params, and function


<pre><code><b>struct</b> <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransaction">ScheduledTransaction</a> <b>has</b> <b>copy</b>, drop, store
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>sender_addr: <b>address</b></code>
</dt>
<dd>
 32 bytes
</dd>
<dt>
<code>scheduled_time_ms: u64</code>
</dt>
<dd>
 UTC timestamp in milliseconds
</dd>
<dt>
<code>max_gas_amount: u64</code>
</dt>
<dd>
 Maximum gas to spend for this transaction
</dd>
<dt>
<code>max_gas_unit_price: u64</code>
</dt>
<dd>
 Charged @ lesser of {max_gas_unit_price, max_gas_unit_price other than this in the block executed}
</dd>
<dt>
<code>pass_signer: bool</code>
</dt>
<dd>
 Option to pass a signer to the function
</dd>
<dt>
<code>f: <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledFunction">scheduled_txns::ScheduledFunction</a></code>
</dt>
<dd>
 Variables are captured in the closure; optionally a signer is passed; no return
</dd>
</dl>


</details>

<a id="0x1_scheduled_txns_ScheduledTransactionContainer"></a>

## Resource `ScheduledTransactionContainer`



<pre><code><b>struct</b> <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransactionContainer">ScheduledTransactionContainer</a> <b>has</b> key
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>transaction: <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransaction">scheduled_txns::ScheduledTransaction</a></code>
</dt>
<dd>

</dd>
<dt>
<code>delete_ref: <a href="object.md#0x1_object_DeleteRef">object::DeleteRef</a></code>
</dt>
<dd>

</dd>
</dl>


</details>

<a id="0x1_scheduled_txns_ScheduledTransactionInfoWithKey"></a>

## Struct `ScheduledTransactionInfoWithKey`

We pass around only needed info


<pre><code><b>struct</b> <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransactionInfoWithKey">ScheduledTransactionInfoWithKey</a> <b>has</b> drop
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>sender_addr: <b>address</b></code>
</dt>
<dd>

</dd>
<dt>
<code>max_gas_amount: u64</code>
</dt>
<dd>

</dd>
<dt>
<code>max_gas_unit_price: u64</code>
</dt>
<dd>

</dd>
<dt>
<code>gas_unit_price_charged: u64</code>
</dt>
<dd>
 To be determined during execution
</dd>
<dt>
<code>key: <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleMapKey">scheduled_txns::ScheduleMapKey</a></code>
</dt>
<dd>

</dd>
</dl>


</details>

<a id="0x1_scheduled_txns_ScheduleMapKey"></a>

## Struct `ScheduleMapKey`

First sorted in ascending order of time, then on gas priority, and finally on txn_id
gas_priority = U64_MAX - gas_unit_price; we want higher gas_unit_price to come before lower gas_unit_price
The goal is to have fixed (less variable) size 'key', 'val' entries in BigOrderedMap, hence we use txn_id
as a key. That is we have "{time, gas_priority, txn_id} -> ScheduledTxn" instead of
"{time, gas_priority} --> List<(txn_id, ScheduledTxn)>".
Note: ScheduledTxn is still variable size though due to its closure.


<pre><code><b>struct</b> <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleMapKey">ScheduleMapKey</a> <b>has</b> <b>copy</b>, drop, store
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>time: u64</code>
</dt>
<dd>
 UTC timestamp in the granularity of 100ms
</dd>
<dt>
<code>gas_priority: u64</code>
</dt>
<dd>

</dd>
<dt>
<code>txn_id: u256</code>
</dt>
<dd>
 SHA3-256
</dd>
</dl>


</details>

<a id="0x1_scheduled_txns_ScheduleQueue"></a>

## Resource `ScheduleQueue`



<pre><code><b>struct</b> <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleQueue">ScheduleQueue</a> <b>has</b> key
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>schedule_map: <a href="big_ordered_map.md#0x1_big_ordered_map_BigOrderedMap">big_ordered_map::BigOrderedMap</a>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleMapKey">scheduled_txns::ScheduleMapKey</a>, <a href="object.md#0x1_object_Object">object::Object</a>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransactionContainer">scheduled_txns::ScheduledTransactionContainer</a>&gt;&gt;</code>
</dt>
<dd>
 key_size = 48 bytes; value_size = key_size + AVG_SCHED_TXN_SIZE
</dd>
</dl>


</details>

<a id="0x1_scheduled_txns_AuxiliaryData"></a>

## Resource `AuxiliaryData`

Signer for the store for gas fee deposits


<pre><code><b>struct</b> <a href="scheduled_txns.md#0x1_scheduled_txns_AuxiliaryData">AuxiliaryData</a> <b>has</b> key
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>gas_fee_deposit_store_signer_cap: <a href="account.md#0x1_account_SignerCapability">account::SignerCapability</a></code>
</dt>
<dd>

</dd>
<dt>
<code>stop_scheduling: bool</code>
</dt>
<dd>

</dd>
<dt>
<code>expiry_delta: u64</code>
</dt>
<dd>
 If we cannot schedule in expiry_delta * time granularity(100ms), we will abort the txn
</dd>
</dl>


</details>

<a id="0x1_scheduled_txns_ToRemoveTbl"></a>

## Resource `ToRemoveTbl`



<pre><code><b>struct</b> <a href="scheduled_txns.md#0x1_scheduled_txns_ToRemoveTbl">ToRemoveTbl</a> <b>has</b> key
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>remove_tbl: <a href="../../aptos-stdlib/doc/table.md#0x1_table_Table">table::Table</a>&lt;u16, <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleMapKey">scheduled_txns::ScheduleMapKey</a>&gt;&gt;</code>
</dt>
<dd>

</dd>
</dl>


</details>

<a id="0x1_scheduled_txns_CancelledTxnCode"></a>

## Enum `CancelledTxnCode`



<pre><code>enum <a href="scheduled_txns.md#0x1_scheduled_txns_CancelledTxnCode">CancelledTxnCode</a> <b>has</b> drop, store
</code></pre>



<details>
<summary>Variants</summary>


<details>
<summary>Shutdown</summary>


<details>
<summary>Fields</summary>


<dl>
</dl>


</details>

</details>

<details>
<summary>Expired</summary>


<details>
<summary>Fields</summary>


<dl>
</dl>


</details>

</details>

<details>
<summary>Failed</summary>


<details>
<summary>Fields</summary>


<dl>
</dl>


</details>

</details>

</details>

<a id="0x1_scheduled_txns_TransactionFailedEvent"></a>

## Struct `TransactionFailedEvent`



<pre><code>#[<a href="event.md#0x1_event">event</a>]
<b>struct</b> <a href="scheduled_txns.md#0x1_scheduled_txns_TransactionFailedEvent">TransactionFailedEvent</a> <b>has</b> drop, store
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>key: <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleMapKey">scheduled_txns::ScheduleMapKey</a></code>
</dt>
<dd>

</dd>
<dt>
<code>sender_addr: <b>address</b></code>
</dt>
<dd>

</dd>
<dt>
<code>cancelled_txn_code: <a href="scheduled_txns.md#0x1_scheduled_txns_CancelledTxnCode">scheduled_txns::CancelledTxnCode</a></code>
</dt>
<dd>

</dd>
</dl>


</details>

<a id="0x1_scheduled_txns_ShutdownEvent"></a>

## Struct `ShutdownEvent`



<pre><code>#[<a href="event.md#0x1_event">event</a>]
<b>struct</b> <a href="scheduled_txns.md#0x1_scheduled_txns_ShutdownEvent">ShutdownEvent</a> <b>has</b> drop, store
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>complete: bool</code>
</dt>
<dd>

</dd>
</dl>


</details>

<a id="0x1_scheduled_txns_KeyAndTxnInfo"></a>

## Struct `KeyAndTxnInfo`



<pre><code><b>struct</b> <a href="scheduled_txns.md#0x1_scheduled_txns_KeyAndTxnInfo">KeyAndTxnInfo</a> <b>has</b> drop
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>key: <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleMapKey">scheduled_txns::ScheduleMapKey</a></code>
</dt>
<dd>

</dd>
<dt>
<code>account_addr: <b>address</b></code>
</dt>
<dd>

</dd>
<dt>
<code>deposit_amt: u64</code>
</dt>
<dd>

</dd>
<dt>
<code>delete_ref: <a href="object.md#0x1_object_DeleteRef">object::DeleteRef</a></code>
</dt>
<dd>

</dd>
</dl>


</details>

<a id="0x1_scheduled_txns_State"></a>

## Struct `State`



<pre><code><b>struct</b> <a href="scheduled_txns.md#0x1_scheduled_txns_State">State</a> <b>has</b> <b>copy</b>, drop, store
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>count: u64</code>
</dt>
<dd>

</dd>
</dl>


</details>

<a id="@Constants_0"></a>

## Constants


<a id="0x1_scheduled_txns_MICRO_CONVERSION_FACTOR"></a>

Conversion factor between our time granularity (100ms) and microseconds


<pre><code><b>const</b> <a href="scheduled_txns.md#0x1_scheduled_txns_MICRO_CONVERSION_FACTOR">MICRO_CONVERSION_FACTOR</a>: u64 = 100000;
</code></pre>



<a id="0x1_scheduled_txns_AVG_SCHED_TXN_SIZE"></a>

The average size of a scheduled transaction to provide an estimate of leaf nodes of BigOrderedMap


<pre><code><b>const</b> <a href="scheduled_txns.md#0x1_scheduled_txns_AVG_SCHED_TXN_SIZE">AVG_SCHED_TXN_SIZE</a>: u16 = 1024;
</code></pre>



<a id="0x1_scheduled_txns_BIG_ORDRD_MAP_TGT_ND_SZ"></a>

BigOrderedMap has MAX_NODE_BYTES = 409600 (400KB), MAX_DEGREE = 4096, DEFAULT_TARGET_NODE_SIZE = 4096;


<pre><code><b>const</b> <a href="scheduled_txns.md#0x1_scheduled_txns_BIG_ORDRD_MAP_TGT_ND_SZ">BIG_ORDRD_MAP_TGT_ND_SZ</a>: u16 = 4096;
</code></pre>



<a id="0x1_scheduled_txns_EINVALID_HASH_SIZE"></a>

Indicates error in SHA3-256 generation


<pre><code><b>const</b> <a href="scheduled_txns.md#0x1_scheduled_txns_EINVALID_HASH_SIZE">EINVALID_HASH_SIZE</a>: u64 = 6;
</code></pre>



<a id="0x1_scheduled_txns_EINVALID_SIGNER"></a>

Map key already exists


<pre><code><b>const</b> <a href="scheduled_txns.md#0x1_scheduled_txns_EINVALID_SIGNER">EINVALID_SIGNER</a>: u64 = 1;
</code></pre>



<a id="0x1_scheduled_txns_EINVALID_TIME"></a>

Scheduled time is in the past


<pre><code><b>const</b> <a href="scheduled_txns.md#0x1_scheduled_txns_EINVALID_TIME">EINVALID_TIME</a>: u64 = 2;
</code></pre>



<a id="0x1_scheduled_txns_ELOW_GAS_UNIT_PRICE"></a>

Gas unit price is too low


<pre><code><b>const</b> <a href="scheduled_txns.md#0x1_scheduled_txns_ELOW_GAS_UNIT_PRICE">ELOW_GAS_UNIT_PRICE</a>: u64 = 4;
</code></pre>



<a id="0x1_scheduled_txns_ETXN_TOO_LARGE"></a>

Txn size is too large; beyond 10KB


<pre><code><b>const</b> <a href="scheduled_txns.md#0x1_scheduled_txns_ETXN_TOO_LARGE">ETXN_TOO_LARGE</a>: u64 = 5;
</code></pre>



<a id="0x1_scheduled_txns_EUNAVAILABLE"></a>

Scheduling is stopped


<pre><code><b>const</b> <a href="scheduled_txns.md#0x1_scheduled_txns_EUNAVAILABLE">EUNAVAILABLE</a>: u64 = 3;
</code></pre>



<a id="0x1_scheduled_txns_EXPIRY_DELTA_DEFAULT"></a>

If we cannot schedule in 100 * time granularity (10s, i.e 100 blocks), we will abort the txn


<pre><code><b>const</b> <a href="scheduled_txns.md#0x1_scheduled_txns_EXPIRY_DELTA_DEFAULT">EXPIRY_DELTA_DEFAULT</a>: u64 = 100;
</code></pre>



<a id="0x1_scheduled_txns_GET_READY_TRANSACTIONS_LIMIT"></a>

The maximum number of scheduled transactions that can be run in a block


<pre><code><b>const</b> <a href="scheduled_txns.md#0x1_scheduled_txns_GET_READY_TRANSACTIONS_LIMIT">GET_READY_TRANSACTIONS_LIMIT</a>: u64 = 5000;
</code></pre>



<a id="0x1_scheduled_txns_MASK_64"></a>



<pre><code><b>const</b> <a href="scheduled_txns.md#0x1_scheduled_txns_MASK_64">MASK_64</a>: u256 = 18446744073709551615;
</code></pre>



<a id="0x1_scheduled_txns_MAX_SCHED_TXN_SIZE"></a>

Max size of a scheduled transaction; 1MB for now as we are bounded by the slot size


<pre><code><b>const</b> <a href="scheduled_txns.md#0x1_scheduled_txns_MAX_SCHED_TXN_SIZE">MAX_SCHED_TXN_SIZE</a>: u64 = 1048576;
</code></pre>



<a id="0x1_scheduled_txns_MILLI_CONVERSION_FACTOR"></a>

Conversion factor between our time granularity (100ms) and milliseconds


<pre><code><b>const</b> <a href="scheduled_txns.md#0x1_scheduled_txns_MILLI_CONVERSION_FACTOR">MILLI_CONVERSION_FACTOR</a>: u64 = 100;
</code></pre>



<a id="0x1_scheduled_txns_SCHEDULE_MAP_KEY_SIZE"></a>



<pre><code><b>const</b> <a href="scheduled_txns.md#0x1_scheduled_txns_SCHEDULE_MAP_KEY_SIZE">SCHEDULE_MAP_KEY_SIZE</a>: u16 = 48;
</code></pre>



<a id="0x1_scheduled_txns_SHUTDOWN_CANCEL_LIMIT"></a>

The maximum number of transactions that can be cancelled in a block during shutdown


<pre><code><b>const</b> <a href="scheduled_txns.md#0x1_scheduled_txns_SHUTDOWN_CANCEL_LIMIT">SHUTDOWN_CANCEL_LIMIT</a>: u64 = 10000;
</code></pre>



<a id="0x1_scheduled_txns_TO_REMOVE_PARALLELISM"></a>

We want reduce the contention while scheduled txns are being executed


<pre><code><b>const</b> <a href="scheduled_txns.md#0x1_scheduled_txns_TO_REMOVE_PARALLELISM">TO_REMOVE_PARALLELISM</a>: u64 = 1024;
</code></pre>



<a id="0x1_scheduled_txns_TXN_ID_SIZE"></a>

SHA3-256 produces 32 bytes


<pre><code><b>const</b> <a href="scheduled_txns.md#0x1_scheduled_txns_TXN_ID_SIZE">TXN_ID_SIZE</a>: u16 = 32;
</code></pre>



<a id="0x1_scheduled_txns_U64_MAX"></a>



<pre><code><b>const</b> <a href="scheduled_txns.md#0x1_scheduled_txns_U64_MAX">U64_MAX</a>: u64 = 18446744073709551615;
</code></pre>



<a id="0x1_scheduled_txns_initialize"></a>

## Function `initialize`

Can be called only by the framework


<pre><code><b>public</b> <b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_initialize">initialize</a>(framework: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> <b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_initialize">initialize</a>(framework: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>) {
    <a href="system_addresses.md#0x1_system_addresses_assert_aptos_framework">system_addresses::assert_aptos_framework</a>(framework);

    // Create owner <a href="account.md#0x1_account">account</a> for handling deposits
    <b>let</b> owner_addr = @0xb; // Replace <b>with</b> your desired <b>address</b>
    <b>let</b> (owner_signer, owner_cap) =
        <a href="account.md#0x1_account_create_framework_reserved_account">account::create_framework_reserved_account</a>(owner_addr);

    // Initialize fungible store for the owner
    <b>let</b> metadata = ensure_paired_metadata&lt;AptosCoin&gt;();
    <b>let</b> deposit_store =
        <a href="primary_fungible_store.md#0x1_primary_fungible_store_ensure_primary_store_exists">primary_fungible_store::ensure_primary_store_exists</a>(
            <a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer_address_of">signer::address_of</a>(&owner_signer), metadata
        );
    upgrade_store_to_concurrent(&owner_signer, deposit_store);

    // Store the <a href="../../aptos-stdlib/doc/capability.md#0x1_capability">capability</a>
    <b>move_to</b>(
        framework,
        <a href="scheduled_txns.md#0x1_scheduled_txns_AuxiliaryData">AuxiliaryData</a> {
            gas_fee_deposit_store_signer_cap: owner_cap,
            stop_scheduling: <b>false</b>,
            expiry_delta: <a href="scheduled_txns.md#0x1_scheduled_txns_EXPIRY_DELTA_DEFAULT">EXPIRY_DELTA_DEFAULT</a>
        }
    );

    // Initialize queue
    <b>let</b> queue = <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleQueue">ScheduleQueue</a> { schedule_map: <a href="big_ordered_map.md#0x1_big_ordered_map_new_with_reusable">big_ordered_map::new_with_reusable</a>() };
    <b>move_to</b>(framework, queue);

    // Parallelizable data structure used <b>to</b> track executed txn_ids.
    <b>move_to</b>(
        framework,
        <a href="scheduled_txns.md#0x1_scheduled_txns_ToRemoveTbl">ToRemoveTbl</a> {
            remove_tbl: <a href="../../aptos-stdlib/doc/table.md#0x1_table_new">table::new</a>&lt;u16, <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleMapKey">ScheduleMapKey</a>&gt;&gt;()
        }
    );
}
</code></pre>



</details>

<a id="0x1_scheduled_txns_shutdown"></a>

## Function `shutdown`

Stop, remove and refund all scheduled txns; can be called only by the framework


<pre><code><b>public</b> <b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_shutdown">shutdown</a>(framework: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> <b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_shutdown">shutdown</a>(
    framework: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>
) <b>acquires</b> <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleQueue">ScheduleQueue</a>, <a href="scheduled_txns.md#0x1_scheduled_txns_ToRemoveTbl">ToRemoveTbl</a>, <a href="scheduled_txns.md#0x1_scheduled_txns_AuxiliaryData">AuxiliaryData</a>, <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransactionContainer">ScheduledTransactionContainer</a> {
    <a href="system_addresses.md#0x1_system_addresses_assert_aptos_framework">system_addresses::assert_aptos_framework</a>(framework);

    // set stop_scheduling flag
    <b>let</b> aux_data = <b>borrow_global_mut</b>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_AuxiliaryData">AuxiliaryData</a>&gt;(<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer_address_of">signer::address_of</a>(framework));
    aux_data.stop_scheduling = <b>true</b>;

    <b>let</b> txns_to_cancel = <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_empty">vector::empty</a>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_KeyAndTxnInfo">KeyAndTxnInfo</a>&gt;();
    // Make a list of txns <b>to</b> cancel <b>with</b> their keys and signers
    {
        <b>let</b> queue = <b>borrow_global</b>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleQueue">ScheduleQueue</a>&gt;(<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer_address_of">signer::address_of</a>(framework));

        // Iterate through schedule_map <b>to</b> get all transactions
        <b>let</b> iter = queue.schedule_map.new_begin_iter();
        <b>let</b> cancel_count = 0;
        <b>while</b> ((!iter.iter_is_end(&queue.schedule_map))
            && (cancel_count &lt; <a href="scheduled_txns.md#0x1_scheduled_txns_SHUTDOWN_CANCEL_LIMIT">SHUTDOWN_CANCEL_LIMIT</a>)) {
            <b>let</b> key = iter.iter_borrow_key();
            <b>let</b> txn_obj = iter.iter_borrow(&queue.schedule_map);
            <b>let</b> (txn, delete_ref) = <a href="scheduled_txns.md#0x1_scheduled_txns_move_scheduled_transaction_container">move_scheduled_transaction_container</a>(txn_obj);
            <b>let</b> deposit_amt = txn.max_gas_amount * txn.max_gas_unit_price;
            txns_to_cancel.push_back(
                <a href="scheduled_txns.md#0x1_scheduled_txns_KeyAndTxnInfo">KeyAndTxnInfo</a> {
                    key: *key,
                    account_addr: txn.sender_addr,
                    deposit_amt,
                    delete_ref
                }
            );
            cancel_count = cancel_count + 1;
            iter = iter.iter_next(&queue.schedule_map);
        };
    };

    // Cancel transactions
    <b>while</b> (!txns_to_cancel.is_empty()) {
        <b>let</b> <a href="scheduled_txns.md#0x1_scheduled_txns_KeyAndTxnInfo">KeyAndTxnInfo</a> { key, account_addr, deposit_amt, delete_ref } =
            txns_to_cancel.pop_back();
        <a href="scheduled_txns.md#0x1_scheduled_txns_cancel_internal">cancel_internal</a>(account_addr, key, deposit_amt, delete_ref);
        <a href="event.md#0x1_event_emit">event::emit</a>(
            <a href="scheduled_txns.md#0x1_scheduled_txns_TransactionFailedEvent">TransactionFailedEvent</a> {
                key,
                sender_addr: account_addr,
                cancelled_txn_code: CancelledTxnCode::Shutdown
            }
        );
    };

    // Remove and destroy schedule_map <b>if</b> empty
    <b>let</b> queue = <b>borrow_global</b>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleQueue">ScheduleQueue</a>&gt;(<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer_address_of">signer::address_of</a>(framework));
    <b>if</b> (queue.schedule_map.is_empty()) {
        <a href="event.md#0x1_event_emit">event::emit</a>(<a href="scheduled_txns.md#0x1_scheduled_txns_ShutdownEvent">ShutdownEvent</a> { complete: <b>true</b> });
    };

    // Clean up <a href="scheduled_txns.md#0x1_scheduled_txns_ToRemoveTbl">ToRemoveTbl</a>
    <b>let</b> <a href="scheduled_txns.md#0x1_scheduled_txns_ToRemoveTbl">ToRemoveTbl</a> { remove_tbl } =
        <b>borrow_global_mut</b>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ToRemoveTbl">ToRemoveTbl</a>&gt;(<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer_address_of">signer::address_of</a>(framework));
    <b>let</b> i = 0;
    <b>while</b> (i &lt; <a href="scheduled_txns.md#0x1_scheduled_txns_TO_REMOVE_PARALLELISM">TO_REMOVE_PARALLELISM</a>) {
        <b>if</b> (remove_tbl.contains((i <b>as</b> u16))) {
            remove_tbl.remove((i <b>as</b> u16));
        };
        i = i + 1;
    };
}
</code></pre>



</details>

<a id="0x1_scheduled_txns_set_expiry_delta"></a>

## Function `set_expiry_delta`

todo: Do we need a function to pause/unpause without issuing refund of deposit ???
Change the expiry delta for scheduled transactions; can be called only by the framework


<pre><code><b>public</b> <b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_set_expiry_delta">set_expiry_delta</a>(framework: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>, new_expiry_delta: u64)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> <b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_set_expiry_delta">set_expiry_delta</a>(
    framework: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>, new_expiry_delta: u64
) <b>acquires</b> <a href="scheduled_txns.md#0x1_scheduled_txns_AuxiliaryData">AuxiliaryData</a> {
    <a href="system_addresses.md#0x1_system_addresses_assert_aptos_framework">system_addresses::assert_aptos_framework</a>(framework);
    <b>let</b> aux_data = <b>borrow_global_mut</b>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_AuxiliaryData">AuxiliaryData</a>&gt;(<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer_address_of">signer::address_of</a>(framework));
    aux_data.expiry_delta = new_expiry_delta;
}
</code></pre>



</details>

<a id="0x1_scheduled_txns_new_scheduled_transaction"></a>

## Function `new_scheduled_transaction`

Constructor


<pre><code><b>public</b> <b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_new_scheduled_transaction">new_scheduled_transaction</a>(sender_addr: <b>address</b>, scheduled_time_ms: u64, max_gas_amount: u64, max_gas_unit_price: u64, pass_signer: bool, f: |<a href="../../aptos-stdlib/../move-stdlib/doc/option.md#0x1_option_Option">option::Option</a>&lt;<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>&gt;| <b>has</b> <b>copy</b> + drop + store): <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransaction">scheduled_txns::ScheduledTransaction</a>
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> <b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_new_scheduled_transaction">new_scheduled_transaction</a>(
    sender_addr: <b>address</b>,
    scheduled_time_ms: u64,
    max_gas_amount: u64,
    max_gas_unit_price: u64,
    pass_signer: bool,
    f: |Option&lt;<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>&gt;| <b>has</b> <b>copy</b> + store + drop
): <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransaction">ScheduledTransaction</a> {
    <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransaction">ScheduledTransaction</a> {
        sender_addr,
        scheduled_time_ms,
        max_gas_amount,
        max_gas_unit_price,
        pass_signer,
        f: ScheduledFunction::V1(f)
    }
}
</code></pre>



</details>

<a id="0x1_scheduled_txns_insert"></a>

## Function `insert`

Insert a scheduled transaction into the queue. ScheduleMapKey is returned to user, which can be used to cancel the txn.


<pre><code><b>public</b> <b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_insert">insert</a>(sender: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>, txn: <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransaction">scheduled_txns::ScheduledTransaction</a>): <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleMapKey">scheduled_txns::ScheduleMapKey</a>
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> <b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_insert">insert</a>(
    sender: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>, txn: <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransaction">ScheduledTransaction</a>
): <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleMapKey">ScheduleMapKey</a> <b>acquires</b> <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleQueue">ScheduleQueue</a>, <a href="scheduled_txns.md#0x1_scheduled_txns_AuxiliaryData">AuxiliaryData</a> {
    // If scheduling is shutdown, we cannot schedule <a href="../../aptos-stdlib/doc/any.md#0x1_any">any</a> more transactions
    <b>let</b> aux_data = <b>borrow_global</b>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_AuxiliaryData">AuxiliaryData</a>&gt;(@aptos_framework);
    <b>assert</b>!(!aux_data.stop_scheduling, <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_unavailable">error::unavailable</a>(<a href="scheduled_txns.md#0x1_scheduled_txns_EUNAVAILABLE">EUNAVAILABLE</a>));

    // we expect the sender <b>to</b> be a permissioned <a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>
    <b>assert</b>!(
        <a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer_address_of">signer::address_of</a>(sender) == txn.sender_addr,
        <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_permission_denied">error::permission_denied</a>(<a href="scheduled_txns.md#0x1_scheduled_txns_EINVALID_SIGNER">EINVALID_SIGNER</a>)
    );

    // Only schedule txns in the future
    <b>let</b> txn_time = txn.scheduled_time_ms / <a href="scheduled_txns.md#0x1_scheduled_txns_MILLI_CONVERSION_FACTOR">MILLI_CONVERSION_FACTOR</a>; // Round down <b>to</b> the nearest 100ms
    <b>let</b> block_time = <a href="timestamp.md#0x1_timestamp_now_microseconds">timestamp::now_microseconds</a>() / <a href="scheduled_txns.md#0x1_scheduled_txns_MICRO_CONVERSION_FACTOR">MICRO_CONVERSION_FACTOR</a>;
    <b>assert</b>!(txn_time &gt; block_time, <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_invalid_argument">error::invalid_argument</a>(<a href="scheduled_txns.md#0x1_scheduled_txns_EINVALID_TIME">EINVALID_TIME</a>));

    <b>assert</b>!(
        txn.max_gas_unit_price &gt;= 100,
        <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_invalid_argument">error::invalid_argument</a>(<a href="scheduled_txns.md#0x1_scheduled_txns_ELOW_GAS_UNIT_PRICE">ELOW_GAS_UNIT_PRICE</a>)
    );

    <b>assert</b>!(
        <a href="../../aptos-stdlib/../move-stdlib/doc/bcs.md#0x1_bcs_serialized_size">bcs::serialized_size</a>(&txn) &lt; <a href="scheduled_txns.md#0x1_scheduled_txns_MAX_SCHED_TXN_SIZE">MAX_SCHED_TXN_SIZE</a>,
        <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_invalid_argument">error::invalid_argument</a>(<a href="scheduled_txns.md#0x1_scheduled_txns_ETXN_TOO_LARGE">ETXN_TOO_LARGE</a>)
    );

    // Generate unique transaction ID
    <b>let</b> <a href="../../aptos-stdlib/../move-stdlib/doc/hash.md#0x1_hash">hash</a> = sha3_256(<a href="../../aptos-stdlib/../move-stdlib/doc/bcs.md#0x1_bcs_to_bytes">bcs::to_bytes</a>(&txn));
    <b>let</b> txn_id = <a href="scheduled_txns.md#0x1_scheduled_txns_hash_to_u256">hash_to_u256</a>(<a href="../../aptos-stdlib/../move-stdlib/doc/hash.md#0x1_hash">hash</a>);

    // Insert the transaction into the schedule_map
    // Create schedule map key
    <b>let</b> key = <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleMapKey">ScheduleMapKey</a> {
        time: txn_time,
        gas_priority: <a href="scheduled_txns.md#0x1_scheduled_txns_U64_MAX">U64_MAX</a> - txn.max_gas_unit_price,
        txn_id
    };

    // Create the <a href="object.md#0x1_object">object</a> <b>with</b> delete <a href="../../aptos-stdlib/doc/capability.md#0x1_capability">capability</a>
    <b>let</b> constructor_ref = <a href="object.md#0x1_object_create_object_from_account">object::create_object_from_account</a>(sender);
    <b>let</b> object_signer = <a href="object.md#0x1_object_generate_signer">object::generate_signer</a>(&constructor_ref);
    <b>let</b> delete_ref = <a href="object.md#0x1_object_generate_delete_ref">object::generate_delete_ref</a>(&constructor_ref);

    <b>let</b> scheduled_txn_container = <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransactionContainer">ScheduledTransactionContainer</a> {
        transaction: txn,
        delete_ref
    };
    <b>move_to</b>(&object_signer, scheduled_txn_container);
    <b>let</b> scheduled_txn_obj =
        <a href="object.md#0x1_object_object_from_constructor_ref">object::object_from_constructor_ref</a>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransactionContainer">ScheduledTransactionContainer</a>&gt;(
            &constructor_ref
        );

    <b>let</b> queue = <b>borrow_global_mut</b>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleQueue">ScheduleQueue</a>&gt;(@aptos_framework);
    queue.schedule_map.add(key, scheduled_txn_obj);

    // Collect deposit
    // Get owner <a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a> from <a href="../../aptos-stdlib/doc/capability.md#0x1_capability">capability</a>
    <b>let</b> gas_deposit_store_cap = <b>borrow_global</b>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_AuxiliaryData">AuxiliaryData</a>&gt;(@aptos_framework);
    <b>let</b> gas_deposit_store_signer =
        <a href="account.md#0x1_account_create_signer_with_capability">account::create_signer_with_capability</a>(
            &gas_deposit_store_cap.gas_fee_deposit_store_signer_cap
        );
    <b>let</b> gas_deposit_store_addr = <a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer_address_of">signer::address_of</a>(&gas_deposit_store_signer);

    <a href="coin.md#0x1_coin_transfer">coin::transfer</a>&lt;AptosCoin&gt;(
        sender,
        gas_deposit_store_addr,
        txn.max_gas_amount * txn.max_gas_unit_price
    );

    key
}
</code></pre>



</details>

<a id="0x1_scheduled_txns_cancel"></a>

## Function `cancel`

Cancel a scheduled transaction, must be called by the signer who originally scheduled the transaction.


<pre><code><b>public</b> <b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_cancel">cancel</a>(sender: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>, key: <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleMapKey">scheduled_txns::ScheduleMapKey</a>)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> <b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_cancel">cancel</a>(
    sender: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>, key: <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleMapKey">ScheduleMapKey</a>
) <b>acquires</b> <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleQueue">ScheduleQueue</a>, <a href="scheduled_txns.md#0x1_scheduled_txns_AuxiliaryData">AuxiliaryData</a>, <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransactionContainer">ScheduledTransactionContainer</a> {
    // If scheduling is shutdown, we cannot schedule <a href="../../aptos-stdlib/doc/any.md#0x1_any">any</a> more transactions
    <b>let</b> aux_data = <b>borrow_global</b>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_AuxiliaryData">AuxiliaryData</a>&gt;(@aptos_framework);
    <b>assert</b>!(!aux_data.stop_scheduling, <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_unavailable">error::unavailable</a>(<a href="scheduled_txns.md#0x1_scheduled_txns_EUNAVAILABLE">EUNAVAILABLE</a>));

    <b>let</b> queue = <b>borrow_global</b>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleQueue">ScheduleQueue</a>&gt;(@aptos_framework);
    <b>if</b> (!queue.schedule_map.contains(&key)) { <b>return</b> };

    <b>let</b> txn_obj = queue.schedule_map.borrow(&key);
    <b>let</b> (txn, delete_ref) = <a href="scheduled_txns.md#0x1_scheduled_txns_move_scheduled_transaction_container">move_scheduled_transaction_container</a>(txn_obj);
    <b>let</b> deposit_amt = txn.max_gas_amount * txn.max_gas_unit_price;

    // verify sender
    <b>assert</b>!(
        <a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer_address_of">signer::address_of</a>(sender) == txn.sender_addr,
        <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_permission_denied">error::permission_denied</a>(<a href="scheduled_txns.md#0x1_scheduled_txns_EINVALID_SIGNER">EINVALID_SIGNER</a>)
    );
    <a href="scheduled_txns.md#0x1_scheduled_txns_cancel_internal">cancel_internal</a>(<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer_address_of">signer::address_of</a>(sender), key, deposit_amt, delete_ref);
}
</code></pre>



</details>

<a id="0x1_scheduled_txns_u256_to_u64_safe"></a>

## Function `u256_to_u64_safe`



<pre><code><b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_u256_to_u64_safe">u256_to_u64_safe</a>(val: u256): u64
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_u256_to_u64_safe">u256_to_u64_safe</a>(val: u256): u64 {
    <b>let</b> masked = val & <a href="scheduled_txns.md#0x1_scheduled_txns_MASK_64">MASK_64</a>; // Truncate high bits
    (masked <b>as</b> u64) // Now safe: always &lt;= u64::MAX
}
</code></pre>



</details>

<a id="0x1_scheduled_txns_hash_to_u256"></a>

## Function `hash_to_u256`



<pre><code><b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_hash_to_u256">hash_to_u256</a>(<a href="../../aptos-stdlib/../move-stdlib/doc/hash.md#0x1_hash">hash</a>: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;): u256
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_hash_to_u256">hash_to_u256</a>(<a href="../../aptos-stdlib/../move-stdlib/doc/hash.md#0x1_hash">hash</a>: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;): u256 {
    <b>assert</b>!(<a href="../../aptos-stdlib/../move-stdlib/doc/hash.md#0x1_hash">hash</a>.length() == 32, <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_internal">error::internal</a>(<a href="scheduled_txns.md#0x1_scheduled_txns_EINVALID_HASH_SIZE">EINVALID_HASH_SIZE</a>));
    <a href="../../aptos-stdlib/doc/from_bcs.md#0x1_from_bcs_to_u256">from_bcs::to_u256</a>(<a href="../../aptos-stdlib/../move-stdlib/doc/hash.md#0x1_hash">hash</a>)
}
</code></pre>



</details>

<a id="0x1_scheduled_txns_move_scheduled_transaction_container"></a>

## Function `move_scheduled_transaction_container`



<pre><code><b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_move_scheduled_transaction_container">move_scheduled_transaction_container</a>(txn_obj: &<a href="object.md#0x1_object_Object">object::Object</a>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransactionContainer">scheduled_txns::ScheduledTransactionContainer</a>&gt;): (<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransaction">scheduled_txns::ScheduledTransaction</a>, <a href="object.md#0x1_object_DeleteRef">object::DeleteRef</a>)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_move_scheduled_transaction_container">move_scheduled_transaction_container</a>(
    txn_obj: &Object&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransactionContainer">ScheduledTransactionContainer</a>&gt;
): (<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransaction">ScheduledTransaction</a>, DeleteRef) <b>acquires</b> <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransactionContainer">ScheduledTransactionContainer</a> {
    <b>let</b> txn_obj_addr = <a href="object.md#0x1_object_object_address">object::object_address</a>(txn_obj);
    <b>let</b> <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransactionContainer">ScheduledTransactionContainer</a> { transaction: txn, delete_ref } =
        <b>move_from</b>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransactionContainer">ScheduledTransactionContainer</a>&gt;(txn_obj_addr);
    (txn, delete_ref)
}
</code></pre>



</details>

<a id="0x1_scheduled_txns_cancel_internal"></a>

## Function `cancel_internal`

Internal cancel function that takes an address instead of signer. No signer verification, assumes key is present
in the schedule_map.


<pre><code><b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_cancel_internal">cancel_internal</a>(account_addr: <b>address</b>, key: <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleMapKey">scheduled_txns::ScheduleMapKey</a>, deposit_amt: u64, delete_ref: <a href="object.md#0x1_object_DeleteRef">object::DeleteRef</a>)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_cancel_internal">cancel_internal</a>(
    account_addr: <b>address</b>, key: <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleMapKey">ScheduleMapKey</a>, deposit_amt: u64, delete_ref: DeleteRef
) <b>acquires</b> <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleQueue">ScheduleQueue</a>, <a href="scheduled_txns.md#0x1_scheduled_txns_AuxiliaryData">AuxiliaryData</a> {
    <b>let</b> queue = <b>borrow_global_mut</b>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleQueue">ScheduleQueue</a>&gt;(@aptos_framework);

    // Delete the scheduled function <a href="object.md#0x1_object">object</a>
    <a href="object.md#0x1_object_delete">object::delete</a>(delete_ref);

    // Remove the transaction from schedule_map
    queue.schedule_map.remove(&key);

    // Refund the deposit
    // Get owner <a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a> from <a href="../../aptos-stdlib/doc/capability.md#0x1_capability">capability</a>
    <b>let</b> gas_deposit_store_cap = <b>borrow_global</b>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_AuxiliaryData">AuxiliaryData</a>&gt;(@aptos_framework);
    <b>let</b> gas_deposit_store_signer =
        <a href="account.md#0x1_account_create_signer_with_capability">account::create_signer_with_capability</a>(
            &gas_deposit_store_cap.gas_fee_deposit_store_signer_cap
        );

    // Refund deposit from owner's store <b>to</b> sender
    <a href="coin.md#0x1_coin_transfer">coin::transfer</a>&lt;AptosCoin&gt;(
        &gas_deposit_store_signer,
        account_addr,
        deposit_amt
    );
}
</code></pre>



</details>

<a id="0x1_scheduled_txns_get_ready_transactions"></a>

## Function `get_ready_transactions`

Gets txns due to be run; also expire txns that could not be run for a while (mostly due to low gas priority)


<pre><code><b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_get_ready_transactions">get_ready_transactions</a>(timestamp_ms: u64): <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransactionInfoWithKey">scheduled_txns::ScheduledTransactionInfoWithKey</a>&gt;
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_get_ready_transactions">get_ready_transactions</a>(
    timestamp_ms: u64
): <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransactionInfoWithKey">ScheduledTransactionInfoWithKey</a>&gt; <b>acquires</b> <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleQueue">ScheduleQueue</a>, <a href="scheduled_txns.md#0x1_scheduled_txns_AuxiliaryData">AuxiliaryData</a>, <a href="scheduled_txns.md#0x1_scheduled_txns_ToRemoveTbl">ToRemoveTbl</a>, <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransactionContainer">ScheduledTransactionContainer</a> {
    <a href="scheduled_txns.md#0x1_scheduled_txns_remove_txns">remove_txns</a>();
    // If scheduling is shutdown, we cannot schedule <a href="../../aptos-stdlib/doc/any.md#0x1_any">any</a> more transactions
    <b>let</b> aux_data = <b>borrow_global</b>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_AuxiliaryData">AuxiliaryData</a>&gt;(@aptos_framework);
    <b>if</b> (aux_data.stop_scheduling) {
        <b>return</b> <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_empty">vector::empty</a>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransactionInfoWithKey">ScheduledTransactionInfoWithKey</a>&gt;();
    };

    <b>let</b> queue = <b>borrow_global</b>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleQueue">ScheduleQueue</a>&gt;(@aptos_framework);
    <b>let</b> block_time = timestamp_ms / <a href="scheduled_txns.md#0x1_scheduled_txns_MILLI_CONVERSION_FACTOR">MILLI_CONVERSION_FACTOR</a>;
    <b>let</b> <a href="scheduled_txns.md#0x1_scheduled_txns">scheduled_txns</a> = <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_empty">vector::empty</a>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransactionInfoWithKey">ScheduledTransactionInfoWithKey</a>&gt;();
    <b>let</b> count = 0;
    <b>let</b> txns_to_expire = <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_empty">vector::empty</a>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_KeyAndTxnInfo">KeyAndTxnInfo</a>&gt;();

    <b>let</b> iter = queue.schedule_map.new_begin_iter();
    <b>while</b> (!iter.iter_is_end(&queue.schedule_map)
        && count &lt; <a href="scheduled_txns.md#0x1_scheduled_txns_GET_READY_TRANSACTIONS_LIMIT">GET_READY_TRANSACTIONS_LIMIT</a>) {
        <b>let</b> key = iter.iter_borrow_key();
        <b>if</b> (key.time &gt; block_time) {
            <b>break</b>;
        };
        <b>let</b> txn_obj = iter.iter_borrow(&queue.schedule_map);
        <b>let</b> txn_obj_addr = <a href="object.md#0x1_object_object_address">object::object_address</a>(txn_obj);
        <b>let</b> txn =
            <b>borrow_global</b>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransactionContainer">ScheduledTransactionContainer</a>&gt;(txn_obj_addr).transaction;

        <b>let</b> scheduled_txn_info_with_key = <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransactionInfoWithKey">ScheduledTransactionInfoWithKey</a> {
            sender_addr: txn.sender_addr,
            max_gas_amount: txn.max_gas_amount,
            max_gas_unit_price: txn.max_gas_unit_price,
            gas_unit_price_charged: txn.max_gas_unit_price,
            key: *key
        };

        <b>if</b> ((block_time - key.time) &gt; aux_data.expiry_delta) {
            <b>let</b> (_, delete_ref) = <a href="scheduled_txns.md#0x1_scheduled_txns_move_scheduled_transaction_container">move_scheduled_transaction_container</a>(txn_obj);
            <b>let</b> deposit_amt = txn.max_gas_amount * txn.max_gas_unit_price;
            txns_to_expire.push_back(
                <a href="scheduled_txns.md#0x1_scheduled_txns_KeyAndTxnInfo">KeyAndTxnInfo</a> {
                    key: *key,
                    account_addr: txn.sender_addr,
                    deposit_amt,
                    delete_ref
                }
            );
        } <b>else</b> {
            <a href="scheduled_txns.md#0x1_scheduled_txns">scheduled_txns</a>.push_back(scheduled_txn_info_with_key);
        };
        // we do not want an unbounded size of ready or expirable txns; hence we increment either way
        count = count + 1;
        iter = iter.iter_next(&queue.schedule_map);
    };

    // Cancel expired transactions
    <b>while</b> (!txns_to_expire.is_empty()) {
        <b>let</b> <a href="scheduled_txns.md#0x1_scheduled_txns_KeyAndTxnInfo">KeyAndTxnInfo</a> { key, account_addr, deposit_amt, delete_ref } =
            txns_to_expire.pop_back();
        <a href="scheduled_txns.md#0x1_scheduled_txns_cancel_internal">cancel_internal</a>(account_addr, key, deposit_amt, delete_ref);
        <a href="event.md#0x1_event_emit">event::emit</a>(
            <a href="scheduled_txns.md#0x1_scheduled_txns_TransactionFailedEvent">TransactionFailedEvent</a> {
                key,
                sender_addr: account_addr,
                cancelled_txn_code: CancelledTxnCode::Expired
            }
        );
    };
    <a href="scheduled_txns.md#0x1_scheduled_txns">scheduled_txns</a>
}
</code></pre>



</details>

<a id="0x1_scheduled_txns_finish_execution"></a>

## Function `finish_execution`

Increment after every scheduled transaction is run
IMP: Make sure this does not affect parallel execution of txns


<pre><code><b>public</b>(<b>friend</b>) <b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_finish_execution">finish_execution</a>(key: <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleMapKey">scheduled_txns::ScheduleMapKey</a>)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b>(<b>friend</b>) <b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_finish_execution">finish_execution</a>(key: <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleMapKey">ScheduleMapKey</a>) <b>acquires</b> <a href="scheduled_txns.md#0x1_scheduled_txns_ToRemoveTbl">ToRemoveTbl</a> {
    // Calculate <a href="../../aptos-stdlib/doc/table.md#0x1_table">table</a> index using <a href="../../aptos-stdlib/../move-stdlib/doc/hash.md#0x1_hash">hash</a>
    <b>let</b> tbl_idx = ((<a href="scheduled_txns.md#0x1_scheduled_txns_u256_to_u64_safe">u256_to_u64_safe</a>(key.txn_id) % <a href="scheduled_txns.md#0x1_scheduled_txns_TO_REMOVE_PARALLELISM">TO_REMOVE_PARALLELISM</a>) <b>as</b> u16);
    <b>let</b> to_remove = <b>borrow_global_mut</b>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ToRemoveTbl">ToRemoveTbl</a>&gt;(@aptos_framework);

    <b>if</b> (!to_remove.remove_tbl.contains(tbl_idx)) {
        <b>let</b> keys = <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_empty">vector::empty</a>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleMapKey">ScheduleMapKey</a>&gt;();
        keys.push_back(key);
        to_remove.remove_tbl.add(tbl_idx, keys);
    } <b>else</b> {
        <b>let</b> keys = to_remove.remove_tbl.borrow_mut(tbl_idx);
        keys.push_back(key);
    };
}
</code></pre>



</details>

<a id="0x1_scheduled_txns_remove_txns"></a>

## Function `remove_txns`

Remove the txns that are run


<pre><code><b>public</b>(<b>friend</b>) <b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_remove_txns">remove_txns</a>()
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b>(<b>friend</b>) <b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_remove_txns">remove_txns</a>() <b>acquires</b> <a href="scheduled_txns.md#0x1_scheduled_txns_ToRemoveTbl">ToRemoveTbl</a>, <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleQueue">ScheduleQueue</a>, <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransactionContainer">ScheduledTransactionContainer</a> {
    <b>let</b> to_remove = <b>borrow_global_mut</b>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ToRemoveTbl">ToRemoveTbl</a>&gt;(@aptos_framework);
    <b>let</b> queue = <b>borrow_global_mut</b>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleQueue">ScheduleQueue</a>&gt;(@aptos_framework);
    <b>let</b> tbl_idx: u16 = 0;

    <b>let</b> remove_count = 0;
    <b>while</b> ((tbl_idx <b>as</b> u64) &lt; <a href="scheduled_txns.md#0x1_scheduled_txns_TO_REMOVE_PARALLELISM">TO_REMOVE_PARALLELISM</a>) {
        <b>if</b> (to_remove.remove_tbl.contains(tbl_idx)) {
            <b>let</b> keys = to_remove.remove_tbl.borrow_mut(tbl_idx);

            <b>while</b> (!keys.is_empty()) {
                <b>let</b> key = keys.pop_back();
                <b>if</b> (queue.schedule_map.contains(&key)) {
                    // Remove transaction from schedule_map
                    remove_count = remove_count + 1;

                    <b>let</b> txn_obj = queue.schedule_map.borrow(&key);
                    <b>let</b> (_, delete_ref) = <a href="scheduled_txns.md#0x1_scheduled_txns_move_scheduled_transaction_container">move_scheduled_transaction_container</a>(txn_obj);
                    // Delete the scheduled function <a href="object.md#0x1_object">object</a>
                    <a href="object.md#0x1_object_delete">object::delete</a>(delete_ref);
                    queue.schedule_map.remove(&key);
                };
            };
        };
        tbl_idx = tbl_idx + 1;
    };
}
</code></pre>



</details>

<a id="0x1_scheduled_txns_execute_user_function_wrapper"></a>

## Function `execute_user_function_wrapper`

Called by the executor when the scheduled transaction is run


<pre><code><b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_execute_user_function_wrapper">execute_user_function_wrapper</a>(<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>: <a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>, txn_key: <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleMapKey">scheduled_txns::ScheduleMapKey</a>)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_execute_user_function_wrapper">execute_user_function_wrapper</a>(
    <a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>: <a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>, txn_key: <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleMapKey">ScheduleMapKey</a>
) <b>acquires</b> <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleQueue">ScheduleQueue</a>, <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransactionContainer">ScheduledTransactionContainer</a> {
    <b>let</b> queue = <b>borrow_global</b>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleQueue">ScheduleQueue</a>&gt;(@aptos_framework);
    <b>assert</b>!(queue.schedule_map.contains(&txn_key), 0);

    <b>let</b> txn_obj = queue.schedule_map.borrow(&txn_key);
    <b>let</b> txn_obj_addr = <a href="object.md#0x1_object_object_address">object::object_address</a>(txn_obj);
    <b>let</b> txn = <b>borrow_global</b>&lt;<a href="scheduled_txns.md#0x1_scheduled_txns_ScheduledTransactionContainer">ScheduledTransactionContainer</a>&gt;(txn_obj_addr).transaction;
    <b>let</b> pass_signer = txn.pass_signer;

    match(txn.f) {
        ScheduledFunction::V1(f) =&gt; {
            <b>if</b> (pass_signer) {
                f(some(<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>));
            } <b>else</b> {
                f(std::option::none());
            };
        }
    };
}
</code></pre>



</details>

<a id="0x1_scheduled_txns_emit_transaction_failed_event"></a>

## Function `emit_transaction_failed_event`



<pre><code><b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_emit_transaction_failed_event">emit_transaction_failed_event</a>(key: <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleMapKey">scheduled_txns::ScheduleMapKey</a>, sender_addr: <b>address</b>)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_emit_transaction_failed_event">emit_transaction_failed_event</a>(
    key: <a href="scheduled_txns.md#0x1_scheduled_txns_ScheduleMapKey">ScheduleMapKey</a>, sender_addr: <b>address</b>
) {
    <a href="event.md#0x1_event_emit">event::emit</a>(
        <a href="scheduled_txns.md#0x1_scheduled_txns_TransactionFailedEvent">TransactionFailedEvent</a> {
            key,
            sender_addr,
            cancelled_txn_code: CancelledTxnCode::Failed
        }
    );
}
</code></pre>



</details>

<a id="0x1_scheduled_txns_step"></a>

## Function `step`



<pre><code>#[persistent]
<b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_step">step</a>(state: <a href="scheduled_txns.md#0x1_scheduled_txns_State">scheduled_txns::State</a>, _s: <a href="../../aptos-stdlib/../move-stdlib/doc/option.md#0x1_option_Option">option::Option</a>&lt;<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>&gt;)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>fun</b> <a href="scheduled_txns.md#0x1_scheduled_txns_step">step</a>(state: <a href="scheduled_txns.md#0x1_scheduled_txns_State">State</a>, _s: Option&lt;<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>&gt;) {
    <b>if</b> (state.count &lt; 10) {
        state.count = state.count + 1;
    }
}
</code></pre>



</details>


[move-book]: https://aptos.dev/move/book/SUMMARY
