// Copyright © Aptos Foundation
// Parts of the project are originally copyright © Meta Platforms, Inc.
// SPDX-License-Identifier: Apache-2.0

/// This module provides various indexes used by Mempool.
use crate::{
    core_mempool::transaction::{MempoolTransaction, TimelineState},
    counters,
    logging::{LogEntry, LogSchema},
    shared_mempool::types::{MultiBucketTimelineIndexIds, TimelineIndexIdentifier},
};
use aptos_consensus_types::common::TransactionSummary;
use aptos_crypto::HashValue;
use aptos_logger::error;
use aptos_types::{
    account_address::AccountAddress,
    transaction::{
        ReplayProtector, TransactionExecutable, TransactionPayload, TransactionPayloadInner,
    },
};
use rand::seq::SliceRandom;
use std::{
    cmp::Ordering,
    collections::{btree_map::RangeMut, btree_set::Iter, BTreeMap, BTreeSet, HashMap},
    hash::Hash,
    iter::Rev,
    mem,
    ops::{Bound, RangeBounds},
    time::{Duration, Instant, SystemTime},
};

/// Transaction type priority for ordering in mempool
/// Lower numeric values indicate higher priority
#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash, PartialOrd, Ord)]
pub enum TransactionTypePriority {
    CEX = 0,      // 最高优先级：CEX交易
    Platform = 1, // 平台交易
    Contract = 2, // 合约交易
    Script = 3,   // 脚本交易
    Others = 4,   // 其他交易（包括Multisig等）
}

impl TransactionTypePriority {
    fn from_payload(payload: &TransactionPayload) -> Self {
        match payload {
            TransactionPayload::CEX(_) => TransactionTypePriority::CEX,
            TransactionPayload::EntryFunction(entry_func) => {
                // 检查是否为平台交易（地址是特殊地址）
                if entry_func.module().address().is_special() {
                    TransactionTypePriority::Platform
                } else {
                    TransactionTypePriority::Contract
                }
            },
            TransactionPayload::Script(_) => TransactionTypePriority::Script,
            TransactionPayload::Payload(inner) => match &inner {
                TransactionPayloadInner::V1 { executable, .. } => match executable {
                    TransactionExecutable::EntryFunction(entry_func) => {
                        if entry_func.module().address().is_special() {
                            TransactionTypePriority::Platform
                        } else {
                            TransactionTypePriority::Contract
                        }
                    },
                    TransactionExecutable::Script(_) => TransactionTypePriority::Script,
                    _ => TransactionTypePriority::Others,
                },
            },
            _ => TransactionTypePriority::Others,
        }
    }
}

#[derive(Clone, Default)]
pub struct AccountTransactions {
    nonce_transactions: BTreeMap<u64 /* Nonce */, MempoolTransaction>,
    sequence_number_transactions: BTreeMap<u64 /* Sequence number */, MempoolTransaction>,
}

impl AccountTransactions {
    pub(crate) fn get(&self, replay_protector: &ReplayProtector) -> Option<&MempoolTransaction> {
        match replay_protector {
            ReplayProtector::Nonce(nonce) => self.nonce_transactions.get(nonce),
            ReplayProtector::SequenceNumber(sequence_number) => {
                self.sequence_number_transactions.get(sequence_number)
            },
        }
    }

    pub(crate) fn get_mut(
        &mut self,
        replay_protector: &ReplayProtector,
    ) -> Option<&mut MempoolTransaction> {
        match replay_protector {
            ReplayProtector::Nonce(nonce) => self.nonce_transactions.get_mut(nonce),
            ReplayProtector::SequenceNumber(sequence_number) => {
                self.sequence_number_transactions.get_mut(sequence_number)
            },
        }
    }

    pub(crate) fn insert(&mut self, txn: MempoolTransaction) {
        match txn.get_replay_protector() {
            ReplayProtector::Nonce(nonce) => {
                self.nonce_transactions.insert(nonce, txn);
            },
            ReplayProtector::SequenceNumber(sequence_number) => {
                self.sequence_number_transactions
                    .insert(sequence_number, txn);
            },
        }
    }

    pub(crate) fn remove(
        &mut self,
        replay_protector: &ReplayProtector,
    ) -> Option<MempoolTransaction> {
        match replay_protector {
            ReplayProtector::Nonce(nonce) => self.nonce_transactions.remove(nonce),
            ReplayProtector::SequenceNumber(sequence_number) => {
                self.sequence_number_transactions.remove(sequence_number)
            },
        }
    }

    pub(crate) fn append(&mut self, other: &mut Self) {
        self.nonce_transactions
            .append(&mut other.nonce_transactions);
        self.sequence_number_transactions
            .append(&mut other.sequence_number_transactions);
    }

    pub(crate) fn clear(&mut self) {
        self.nonce_transactions.clear();
        self.sequence_number_transactions.clear();
    }

    pub(crate) fn seq_num_split_off(&mut self, sequence_number: u64) -> Self {
        AccountTransactions {
            sequence_number_transactions: self
                .sequence_number_transactions
                .split_off(&sequence_number),
            nonce_transactions: mem::take(&mut self.nonce_transactions),
        }
    }

    pub(crate) fn seq_num_range_mut(
        &mut self,
        range: impl RangeBounds<u64>,
    ) -> RangeMut<'_, u64, MempoolTransaction> {
        self.sequence_number_transactions.range_mut(range)
    }

    pub(crate) fn values(&self) -> impl Iterator<Item = &MempoolTransaction> {
        self.nonce_transactions
            .values()
            .chain(self.sequence_number_transactions.values())
    }

    pub(crate) fn orderless_txns_len(&self) -> usize {
        self.nonce_transactions.len()
    }

    pub(crate) fn seq_num_txns_len(&self) -> usize {
        self.sequence_number_transactions.len()
    }

    pub(crate) fn len(&self) -> usize {
        self.nonce_transactions.len() + self.sequence_number_transactions.len()
    }
}

/// PriorityIndex represents the main Priority Queue in Mempool.
/// It's used to form the transaction block for Consensus.
/// Transactions are ordered by gas price. Second level ordering is done by expiration time.
///
/// We don't store the full content of transactions in the index.
/// Instead we use `OrderedQueueKey` - logical reference to the transaction in the main store.
pub struct PriorityIndex {
    data: BTreeSet<OrderedQueueKey>,
}

pub type PriorityQueueIter<'a> = Rev<Iter<'a, OrderedQueueKey>>;

impl PriorityIndex {
    pub(crate) fn new() -> Self {
        Self {
            data: BTreeSet::new(),
        }
    }

    pub(crate) fn insert(&mut self, txn: &MempoolTransaction) -> bool {
        self.data.insert(self.make_key(txn))
    }

    pub(crate) fn remove(&mut self, txn: &MempoolTransaction) {
        self.data.remove(&self.make_key(txn));
    }

    pub(crate) fn contains(&self, txn: &MempoolTransaction) -> bool {
        self.data.contains(&self.make_key(txn))
    }

    fn make_key(&self, txn: &MempoolTransaction) -> OrderedQueueKey {
        // 提取CEX交易的timestamp用于内部排序
        let cex_timestamp = match txn.txn.payload() {
            TransactionPayload::CEX(cex_order) => Some(cex_order.order.timestamp),
            _ => None,
        };

        OrderedQueueKey {
            transaction_type_priority: TransactionTypePriority::from_payload(txn.txn.payload()),
            cex_timestamp,
            gas_ranking_score: txn.ranking_score,
            expiration_time: txn.expiration_time,
            insertion_time: txn.insertion_info.insertion_time,
            address: txn.get_sender(),
            replay_protector: txn.get_replay_protector(),
            hash: txn.get_committed_hash(),
        }
    }

    pub(crate) fn iter(&self) -> PriorityQueueIter<'_> {
        self.data.iter().rev()
    }

    pub(crate) fn size(&self) -> usize {
        self.data.len()
    }
}

#[derive(Eq, PartialEq, Clone, Debug, Hash)]
pub struct OrderedQueueKey {
    pub transaction_type_priority: TransactionTypePriority,
    pub cex_timestamp: Option<u64>, // CEX交易的timestamp，用于CEX内部排序
    pub gas_ranking_score: u64,
    pub expiration_time: Duration,
    pub insertion_time: SystemTime,
    pub address: AccountAddress,
    pub replay_protector: ReplayProtector,
    pub hash: HashValue,
}

impl PartialOrd for OrderedQueueKey {
    fn partial_cmp(&self, other: &OrderedQueueKey) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for OrderedQueueKey {
    fn cmp(&self, other: &OrderedQueueKey) -> Ordering {
        // Note: BTreeSet + .iter().rev() means higher priority items should be "greater"

        // First priority: Transaction type (CEX transactions have highest priority)
        // CEX (0) should be "greater than" Platform (1), Contract (2), etc.
        match self
            .transaction_type_priority
            .cmp(&other.transaction_type_priority)
            .reverse()
        {
            Ordering::Equal => {},
            ordering => return ordering,
        }

        // Special handling for CEX transactions: sort by timestamp (smaller timestamp first)
        if self.transaction_type_priority == TransactionTypePriority::CEX {
            match (self.cex_timestamp, other.cex_timestamp) {
                (Some(ts1), Some(ts2)) => match ts1.cmp(&ts2) {
                    Ordering::Equal => {},
                    ordering => return ordering.reverse(), // Reverse because we want smaller timestamps to be "greater" in BTreeSet
                },
                (Some(_), None) => return Ordering::Greater, // CEX with timestamp beats CEX without
                (None, Some(_)) => return Ordering::Less, // CEX without timestamp loses to CEX with
                (None, None) => {}, // Both CEX without timestamp, continue to next criteria
            }
        }

        // Second priority: Higher gas preferred
        match self.gas_ranking_score.cmp(&other.gas_ranking_score) {
            Ordering::Equal => {},
            ordering => return ordering,
        }
        // Third priority: Lower insertion time preferred (earlier is better, so reverse)
        match self.insertion_time.cmp(&other.insertion_time).reverse() {
            Ordering::Equal => {},
            ordering => return ordering,
        }
        // Fourth priority: Higher address preferred
        match self.address.cmp(&other.address) {
            Ordering::Equal => {},
            ordering => return ordering,
        }
        match self.replay_protector.cmp(&other.replay_protector).reverse() {
            Ordering::Equal => {},
            ordering => return ordering,
        }
        self.hash.cmp(&other.hash)
    }
}

/// TTLIndex is used to perform garbage collection of old transactions in Mempool.
/// Periodically separate GC-like job queries this index to find out transactions that have to be
/// removed. Index is represented as `BTreeSet<TTLOrderingKey>`, where `TTLOrderingKey`
/// is a logical reference to TxnInfo.
/// Index is ordered by `TTLOrderingKey::expiration_time`.
pub struct TTLIndex {
    data: BTreeSet<TTLOrderingKey>,
    get_expiration_time: Box<dyn Fn(&MempoolTransaction) -> Duration + Send + Sync>,
}

impl TTLIndex {
    pub(crate) fn new<F>(get_expiration_time: Box<F>) -> Self
    where
        F: Fn(&MempoolTransaction) -> Duration + 'static + Send + Sync,
    {
        Self {
            data: BTreeSet::new(),
            get_expiration_time,
        }
    }

    pub(crate) fn insert(&mut self, txn: &MempoolTransaction) {
        self.data.insert(self.make_key(txn));
    }

    pub(crate) fn remove(&mut self, txn: &MempoolTransaction) {
        self.data.remove(&self.make_key(txn));
    }

    /// Garbage collect all old transactions.
    pub(crate) fn gc(&mut self, now: Duration) -> Vec<TTLOrderingKey> {
        // Ideally, we should garbage collect all transactions with expiration time < now.
        let max_expiration_time = now.saturating_sub(Duration::from_micros(1));
        let ttl_key = TTLOrderingKey {
            expiration_time: max_expiration_time,
            address: AccountAddress::ZERO,
            replay_protector: ReplayProtector::Nonce(0),
        };

        let mut active = self.data.split_off(&ttl_key);
        let ttl_transactions = self.data.iter().cloned().collect();
        self.data.clear();
        self.data.append(&mut active);
        ttl_transactions
    }

    fn make_key(&self, txn: &MempoolTransaction) -> TTLOrderingKey {
        TTLOrderingKey {
            expiration_time: (self.get_expiration_time)(txn),
            address: txn.get_sender(),
            replay_protector: txn.get_replay_protector(),
        }
    }

    pub(crate) fn iter(&self) -> Iter<'_, TTLOrderingKey> {
        self.data.iter()
    }

    pub(crate) fn size(&self) -> usize {
        self.data.len()
    }
}

#[allow(clippy::derive_ord_xor_partial_ord)]
#[derive(Eq, PartialEq, PartialOrd, Clone, Debug)]
pub struct TTLOrderingKey {
    pub expiration_time: Duration,
    pub address: AccountAddress,
    pub replay_protector: ReplayProtector,
}

/// Be very careful with this, to not break the partial ordering.
/// See:  https://rust-lang.github.io/rust-clippy/master/index.html#derive_ord_xor_partial_ord
#[allow(clippy::derive_ord_xor_partial_ord)]
impl Ord for TTLOrderingKey {
    fn cmp(&self, other: &TTLOrderingKey) -> Ordering {
        match self.expiration_time.cmp(&other.expiration_time) {
            Ordering::Equal => match self.address.cmp(&other.address) {
                Ordering::Equal => self.replay_protector.cmp(&other.replay_protector),
                ordering => ordering,
            },
            ordering => ordering,
        }
    }
}

/// TimelineId is the unique id of a transaction inserted into a timeline.
/// It's an auto incrementing counter.
pub type TimelineId = u64;

/// TimelineIndex is an ordered log of all transactions that are "ready" for mempool broadcast.
/// We only add a transaction to the index if it has a chance to be included in the next consensus
/// block (which means its status is != NotReady or its sequential to another "ready" transaction).
///
/// It's represented as Map <timeline_id, (Address, Replay Protector)>, where timeline_id is auto
/// increment unique id of "ready" transaction in local Mempool. (Address, Replay Protector) is a
/// logical reference to transaction content in main storage.
pub struct TimelineIndex {
    // Every transaction inserted into the TimelineIndex gets a unique timeline id.
    // This id is an auto incrementing counter.
    next_timeline_id: TimelineId,
    timeline: BTreeMap<TimelineId, (AccountAddress, ReplayProtector, Instant)>,
}

impl TimelineIndex {
    pub(crate) fn new() -> Self {
        Self {
            next_timeline_id: 1,
            timeline: BTreeMap::new(),
        }
    }

    /// Read all transactions from the timeline since <timeline_id>.
    /// At most `count` transactions will be returned.
    /// If `before` is set, only transactions inserted before this time will be returned.
    pub(crate) fn read_timeline(
        &self,
        timeline_id: TimelineId,
        count: usize,
        before: Option<Instant>,
    ) -> Vec<(AccountAddress, ReplayProtector)> {
        let mut batch = vec![];
        for (_id, &(address, replay_protector, insertion_time)) in self
            .timeline
            .range((Bound::Excluded(timeline_id), Bound::Unbounded))
        {
            if let Some(before) = before {
                if insertion_time >= before {
                    break;
                }
            }
            if batch.len() == count {
                break;
            }
            batch.push((address, replay_protector));
        }
        batch
    }

    /// Read transactions from the timeline from `start_timeline_id` (exclusive) to `end_timeline_id` (inclusive).
    pub(crate) fn timeline_range(
        &self,
        start_timeline_id: TimelineId,
        end_timeline_id: TimelineId,
    ) -> Vec<(AccountAddress, ReplayProtector)> {
        self.timeline
            .range((
                Bound::Excluded(start_timeline_id),
                Bound::Included(end_timeline_id),
            ))
            .map(|(_idx, &(address, replay_protector, _))| (address, replay_protector))
            .collect()
    }

    pub(crate) fn insert(&mut self, txn: &mut MempoolTransaction) {
        self.timeline.insert(
            self.next_timeline_id,
            (txn.get_sender(), txn.get_replay_protector(), Instant::now()),
        );
        txn.timeline_state = TimelineState::Ready(self.next_timeline_id);
        self.next_timeline_id += 1;
    }

    pub(crate) fn remove(&mut self, txn: &MempoolTransaction) {
        if let TimelineState::Ready(timeline_id) = txn.timeline_state {
            self.timeline.remove(&timeline_id);
        }
    }

    pub(crate) fn size(&self) -> usize {
        self.timeline.len()
    }
}

/// We use ranking score as a means to prioritize transactions.
/// At the moment, we use gas_unit_price in the transaction as ranking score.
/// Transactions with higher ranking score (gas_unit_price) are given higher priority.
type RankingScore = u64;

/// We divide the transactions into multiple buckets based on the ranking score.
/// Transactions with ranking score between bucket_mins[i] and bucket_mins[i+1] are stored in the ith bucket.
pub struct MultiBucketTimelineIndex {
    timelines: Vec<TimelineIndex>,
    bucket_mins: Vec<RankingScore>,
    bucket_mins_to_string: Vec<String>,
}

impl MultiBucketTimelineIndex {
    pub(crate) fn new(bucket_mins: Vec<RankingScore>) -> anyhow::Result<Self> {
        anyhow::ensure!(!bucket_mins.is_empty(), "Must not be empty");
        anyhow::ensure!(bucket_mins[0] == 0, "First bucket must start at 0");

        let mut prev = None;
        let mut timelines = vec![];
        for entry in bucket_mins.clone() {
            if let Some(prev) = prev {
                anyhow::ensure!(prev < entry, "Values must be sorted and not repeat");
            }
            prev = Some(entry);
            timelines.push(TimelineIndex::new());
        }

        let bucket_mins_to_string: Vec<_> = bucket_mins
            .iter()
            .map(|bucket_min| bucket_min.to_string())
            .collect();

        Ok(Self {
            timelines,
            bucket_mins,
            bucket_mins_to_string,
        })
    }

    /// Read all transactions from the timeline since <timeline_id>.
    /// At most `count` transactions will be returned.
    pub(crate) fn read_timeline(
        &self,
        multibucket_timeline_ids: &MultiBucketTimelineIndexIds,
        count: usize,
        before: Option<Instant>,
    ) -> Vec<Vec<(AccountAddress, ReplayProtector)>> {
        assert!(multibucket_timeline_ids.id_per_bucket.len() == self.bucket_mins.len());

        let mut added = 0;
        let mut returned = vec![];
        for (timeline, &timeline_id) in self
            .timelines
            .iter()
            .zip(multibucket_timeline_ids.id_per_bucket.iter())
            .rev()
        {
            let txns = timeline.read_timeline(timeline_id, count - added, before);
            added += txns.len();
            returned.push(txns);

            if added == count {
                break;
            }
        }
        while returned.len() < self.timelines.len() {
            returned.push(vec![]);
        }
        returned.iter().rev().cloned().collect()
    }

    /// Read transactions from the timeline from `start_timeline_id` (exclusive) to `end_timeline_id` (inclusive).
    pub(crate) fn timeline_range(
        &self,
        start_end_pairs: HashMap<TimelineIndexIdentifier, (TimelineId, TimelineId)>,
    ) -> Vec<(AccountAddress, ReplayProtector)> {
        assert_eq!(start_end_pairs.len(), self.timelines.len());

        let mut all_txns = vec![];
        for (timeline_index_identifier, (start_id, end_id)) in start_end_pairs {
            let mut txns = self
                .timelines
                .get(timeline_index_identifier as usize)
                .map_or_else(Vec::new, |timeline| {
                    timeline.timeline_range(start_id, end_id)
                });
            all_txns.append(&mut txns);
        }
        all_txns
    }

    #[inline]
    fn get_timeline(&mut self, ranking_score: RankingScore) -> &mut TimelineIndex {
        let index = self
            .bucket_mins
            .binary_search(&ranking_score)
            .unwrap_or_else(|i| i - 1);
        self.timelines.get_mut(index).unwrap()
    }

    pub(crate) fn insert(&mut self, txn: &mut MempoolTransaction) {
        self.get_timeline(txn.ranking_score).insert(txn);
    }

    pub(crate) fn remove(&mut self, txn: &MempoolTransaction) {
        self.get_timeline(txn.ranking_score).remove(txn);
    }

    pub(crate) fn size(&self) -> usize {
        let mut size = 0;
        for timeline in &self.timelines {
            size += timeline.size()
        }
        size
    }

    pub(crate) fn get_sizes(&self) -> Vec<(&str, usize)> {
        self.bucket_mins_to_string
            .iter()
            .zip(self.timelines.iter())
            .map(|(bucket_min, timeline)| (bucket_min.as_str(), timeline.size()))
            .collect()
    }

    #[inline]
    pub(crate) fn get_bucket(&self, ranking_score: RankingScore) -> &str {
        let index = self
            .bucket_mins
            .binary_search(&ranking_score)
            .unwrap_or_else(|i| i - 1);
        self.bucket_mins_to_string[index].as_str()
    }
}

/// ParkingLotIndex keeps track of "not_ready" transactions, e.g., transactions that
/// can't be included in the next block because their sequence number is too high.
/// We keep a separate index to be able to efficiently evict them when Mempool is full.
pub struct ParkingLotIndex {
    // DS invariants:
    // 1. for each entry (account, txns) in `data`, `txns` is never empty
    // 2. for all accounts, data.get(account_indices.get(`account`)) == (account, sequence numbers of account's txns)
    data: Vec<(AccountAddress, BTreeSet<(u64, HashValue)>)>,
    account_indices: HashMap<AccountAddress, usize>,
    size: usize,
}

impl ParkingLotIndex {
    pub(crate) fn new() -> Self {
        Self {
            data: vec![],
            account_indices: HashMap::new(),
            size: 0,
        }
    }

    pub(crate) fn insert(&mut self, txn: &mut MempoolTransaction) {
        // Orderless transactions are always in the "ready" state and are not stored in the parking lot.
        match txn.get_replay_protector() {
            ReplayProtector::SequenceNumber(sequence_number) => {
                if txn.insertion_info.park_time.is_none() {
                    txn.insertion_info.park_time = Some(SystemTime::now());
                }
                txn.was_parked = true;

                let sender = &txn.txn.sender();
                let hash = txn.get_committed_hash();
                let is_new_entry = match self.account_indices.get(sender) {
                    Some(index) => {
                        if let Some((_account, seq_nums)) = self.data.get_mut(*index) {
                            seq_nums.insert((sequence_number, hash))
                        } else {
                            counters::CORE_MEMPOOL_INVARIANT_VIOLATION_COUNT.inc();
                            error!(
                                LogSchema::new(LogEntry::InvariantViolated),
                                "Parking lot invariant violated: for account {}, account index exists but missing entry in data",
                                sender
                            );
                            return;
                        }
                    },
                    None => {
                        let entry = [(sequence_number, hash)]
                            .iter()
                            .cloned()
                            .collect::<BTreeSet<_>>();
                        self.data.push((*sender, entry));
                        self.account_indices.insert(*sender, self.data.len() - 1);
                        true
                    },
                };
                if is_new_entry {
                    self.size += 1;
                }
            },
            ReplayProtector::Nonce(_) => {},
        }
    }

    pub(crate) fn remove(&mut self, txn: &MempoolTransaction) {
        // Orderless transactions are always in the "ready" state and are not stored in the parking lot.
        match txn.get_replay_protector() {
            ReplayProtector::SequenceNumber(sequence_number) => {
                let sender = &txn.txn.sender();
                if let Some(index) = self.account_indices.get(sender).cloned() {
                    if let Some((_account, txns)) = self.data.get_mut(index) {
                        if txns.remove(&(sequence_number, txn.get_committed_hash())) {
                            self.size -= 1;
                        }

                        // maintain DS invariant
                        if txns.is_empty() {
                            // remove account with no more txns
                            self.data.swap_remove(index);
                            self.account_indices.remove(sender);

                            // update DS for account that was swapped in `swap_remove`
                            if let Some((swapped_account, _)) = self.data.get(index) {
                                self.account_indices.insert(*swapped_account, index);
                            }
                        }
                    }
                }
            },
            ReplayProtector::Nonce(_) => {},
        }
    }

    pub(crate) fn contains(
        &self,
        account: &AccountAddress,
        replay_protector: ReplayProtector,
        hash: HashValue,
    ) -> bool {
        // Orderless transactions are always in the "ready" state and are not stored in the parking lot.
        match replay_protector {
            ReplayProtector::SequenceNumber(seq_num) => self
                .account_indices
                .get(account)
                .and_then(|idx| self.data.get(*idx))
                .is_some_and(|(_account, txns)| txns.contains(&(seq_num, hash))),
            ReplayProtector::Nonce(_) => false,
        }
    }

    /// Returns a random "non-ready" transaction (with highest sequence number for that account).
    pub(crate) fn get_poppable(&self) -> Option<TxnPointer> {
        let mut rng = rand::thread_rng();
        self.data.choose(&mut rng).and_then(|(sender, txns)| {
            txns.iter().next_back().map(|(seq_num, hash)| TxnPointer {
                sender: *sender,
                replay_protector: ReplayProtector::SequenceNumber(*seq_num),
                hash: *hash,
            })
        })
    }

    pub(crate) fn size(&self) -> usize {
        self.size
    }

    pub(crate) fn get_addresses(&self) -> Vec<(AccountAddress, u64)> {
        self.data
            .iter()
            .map(|(addr, txns)| (*addr, txns.len() as u64))
            .collect::<Vec<(AccountAddress, u64)>>()
    }
}

/// Logical pointer to `MempoolTransaction`.
/// Includes Account's address and transaction sequence number.
pub type TxnPointer = TransactionSummary;

impl From<&MempoolTransaction> for TxnPointer {
    fn from(txn: &MempoolTransaction) -> Self {
        Self {
            sender: txn.get_sender(),
            replay_protector: txn.get_replay_protector(),
            hash: txn.get_committed_hash(),
        }
    }
}

impl From<&OrderedQueueKey> for TxnPointer {
    fn from(key: &OrderedQueueKey) -> Self {
        Self {
            sender: key.address,
            replay_protector: key.replay_protector,
            hash: key.hash,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use aptos_types::{account_address::AccountAddress, transaction::TransactionPayload};
    use std::time::{Duration, UNIX_EPOCH};

    fn create_ordered_queue_key(
        transaction_type_priority: TransactionTypePriority,
        cex_timestamp: Option<u64>,
        gas_ranking_score: u64,
        insertion_time_offset: u64, // seconds from UNIX_EPOCH
        address_suffix: u8,
    ) -> OrderedQueueKey {
        OrderedQueueKey {
            transaction_type_priority,
            cex_timestamp,
            gas_ranking_score,
            expiration_time: Duration::from_secs(3600), // 1 hour
            insertion_time: UNIX_EPOCH + Duration::from_secs(insertion_time_offset),
            address: AccountAddress::from_hex_literal(&format!("0x{:02x}", address_suffix))
                .unwrap(),
            replay_protector: ReplayProtector::SequenceNumber(0),
            hash: aptos_crypto::HashValue::zero(),
        }
    }

    #[test]
    fn test_transaction_type_priority_ordering() {
        // Test different transaction types are ordered correctly
        let cex_key =
            create_ordered_queue_key(TransactionTypePriority::CEX, Some(1000), 100, 1000, 0x01);
        let platform_key = create_ordered_queue_key(
            TransactionTypePriority::Platform,
            None,
            200, // Higher gas
            900, // Earlier insertion
            0x02,
        );
        let contract_key = create_ordered_queue_key(
            TransactionTypePriority::Contract,
            None,
            300, // Highest gas
            800, // Earliest insertion
            0x03,
        );

        // CEX should beat Platform despite lower gas and later insertion
        assert!(cex_key > platform_key);
        // Platform should beat Contract despite lower gas and later insertion
        assert!(platform_key > contract_key);
        // CEX should beat Contract
        assert!(cex_key > contract_key);
    }

    #[test]
    fn test_cex_timestamp_ordering() {
        // Test CEX transactions are ordered by timestamp (smaller first)
        let cex_early = create_ordered_queue_key(
            TransactionTypePriority::CEX,
            Some(500), // Earlier timestamp
            50,        // Lower gas
            2000,      // Later insertion
            0x01,
        );
        let cex_late = create_ordered_queue_key(
            TransactionTypePriority::CEX,
            Some(1500), // Later timestamp
            150,        // Higher gas
            1000,       // Earlier insertion
            0x02,
        );

        // Earlier timestamp should win despite lower gas and later insertion
        assert!(cex_early > cex_late);
    }

    #[test]
    fn test_cex_timestamp_vs_no_timestamp() {
        let cex_with_timestamp = create_ordered_queue_key(
            TransactionTypePriority::CEX,
            Some(1000),
            50,   // Lower gas
            2000, // Later insertion
            0x01,
        );
        let cex_without_timestamp = create_ordered_queue_key(
            TransactionTypePriority::CEX,
            None,
            150,  // Higher gas
            1000, // Earlier insertion
            0x02,
        );

        // CEX with timestamp should beat CEX without timestamp
        assert!(cex_with_timestamp > cex_without_timestamp);
    }

    #[test]
    fn test_same_type_gas_ordering() {
        // Test same type transactions with same timestamp are ordered by gas
        let cex_high_gas = create_ordered_queue_key(
            TransactionTypePriority::CEX,
            Some(1000),
            200,  // Higher gas
            2000, // Later insertion
            0x01,
        );
        let cex_low_gas = create_ordered_queue_key(
            TransactionTypePriority::CEX,
            Some(1000), // Same timestamp
            100,        // Lower gas
            1000,       // Earlier insertion
            0x02,
        );

        // Higher gas should win despite later insertion
        assert!(cex_high_gas > cex_low_gas);
    }

    #[test]
    fn test_priority_index_ordering() {
        let mut priority_index = PriorityIndex::new();

        // Create mock transactions with different priorities
        let keys = vec![
            create_ordered_queue_key(TransactionTypePriority::Contract, None, 300, 1000, 0x01),
            create_ordered_queue_key(TransactionTypePriority::CEX, Some(500), 100, 3000, 0x02),
            create_ordered_queue_key(TransactionTypePriority::Platform, None, 250, 2000, 0x03),
            create_ordered_queue_key(TransactionTypePriority::CEX, Some(300), 50, 4000, 0x04),
            create_ordered_queue_key(TransactionTypePriority::Script, None, 400, 500, 0x05),
        ];

        // Insert in random order
        for key in &keys {
            priority_index.data.insert(key.clone());
        }

        // Collect ordered results
        let ordered: Vec<_> = priority_index.iter().collect();

        // Verify ordering: CEX transactions should come first (ordered by timestamp),
        // then Platform, then Contract, then Script
        assert_eq!(ordered.len(), 5);

        // First should be CEX with timestamp 300
        assert_eq!(
            ordered[0].transaction_type_priority,
            TransactionTypePriority::CEX
        );
        assert_eq!(ordered[0].cex_timestamp, Some(300));

        // Second should be CEX with timestamp 500
        assert_eq!(
            ordered[1].transaction_type_priority,
            TransactionTypePriority::CEX
        );
        assert_eq!(ordered[1].cex_timestamp, Some(500));

        // Third should be Platform
        assert_eq!(
            ordered[2].transaction_type_priority,
            TransactionTypePriority::Platform
        );

        // Fourth should be Contract
        assert_eq!(
            ordered[3].transaction_type_priority,
            TransactionTypePriority::Contract
        );

        // Fifth should be Script
        assert_eq!(
            ordered[4].transaction_type_priority,
            TransactionTypePriority::Script
        );
    }

    #[test]
    fn test_transaction_type_priority_from_payload() {
        use aptos_types::transaction::cex::{
            CEXOrder, ClobPair, ConditionType, GoodTill, Operation, Order, OrderCateType,
            OrderState, Side, SubaccountId, TimeInForce,
        };

        // Test CEX transaction
        let cex_order = CEXOrder::new(Order {
            subaccount_id: SubaccountId {
                subaccount_id: [0u8; 20],
                number: 0,
            },
            nonce: 1,
            clob_pair: ClobPair::BtcUsdcSpot,
            side: Side::Buy,
            quantums: 1000,
            subticks: 100,
            order_basic_type: 0,
            good_till: GoodTill::Gtc,
            time_in_force: TimeInForce::Ioc,
            reduce_only: false,
            condition_type: ConditionType::Unspecified,
            trigger_subticks: 0,
            operation: Operation::Place,
            timestamp: 1000,
            target_nonce: 0,
            order_id: [0u8; 20],
            state: OrderState::Pending,
            remaining_quantums: 1000,
            fill_amount: 0,
            cate_type: OrderCateType::Regular,
            seq_num: 1,
        });

        let cex_payload = TransactionPayload::CEX(cex_order);
        assert_eq!(
            TransactionTypePriority::from_payload(&cex_payload),
            TransactionTypePriority::CEX
        );

        // Test Script transaction
        use aptos_types::transaction::Script;
        let script_payload = TransactionPayload::Script(Script::new(vec![], vec![], vec![]));
        assert_eq!(
            TransactionTypePriority::from_payload(&script_payload),
            TransactionTypePriority::Script
        );
    }

    #[test]
    fn test_multiple_cex_transactions_complex_ordering() {
        // Test a complex scenario with multiple CEX transactions
        let keys = vec![
            // CEX transactions with different timestamps and gas
            create_ordered_queue_key(TransactionTypePriority::CEX, Some(1000), 100, 5000, 0x01),
            create_ordered_queue_key(TransactionTypePriority::CEX, Some(500), 200, 4000, 0x02),
            create_ordered_queue_key(TransactionTypePriority::CEX, Some(1500), 50, 3000, 0x03),
            create_ordered_queue_key(TransactionTypePriority::CEX, None, 300, 2000, 0x04), // No timestamp
            create_ordered_queue_key(TransactionTypePriority::CEX, Some(500), 250, 1000, 0x05), // Same timestamp as #2
        ];

        let mut sorted_keys = keys.clone();
        sorted_keys.sort();
        sorted_keys.reverse(); // Simulate PriorityIndex.iter().rev() behavior

        // Expected order:
        // 1. CEX with timestamp 500 and gas 250 (earlier timestamp, higher gas wins tie)
        // 2. CEX with timestamp 500 and gas 200 (same timestamp, lower gas)
        // 3. CEX with timestamp 1000 (later timestamp)
        // 4. CEX with timestamp 1500 (latest timestamp)
        // 5. CEX without timestamp (should be last among CEX)

        assert_eq!(sorted_keys[0].cex_timestamp, Some(500));
        assert_eq!(sorted_keys[0].gas_ranking_score, 250);

        assert_eq!(sorted_keys[1].cex_timestamp, Some(500));
        assert_eq!(sorted_keys[1].gas_ranking_score, 200);

        assert_eq!(sorted_keys[2].cex_timestamp, Some(1000));

        assert_eq!(sorted_keys[3].cex_timestamp, Some(1500));

        assert_eq!(sorted_keys[4].cex_timestamp, None);
    }
}
