// Copyright © Aptos Foundation
// SPDX-License-Identifier: Apache-2.0

use super::{
    dag_store::DagStore, health::HealthBackoff, order_rule::TOrderRule, types::NodeCertificate,
};
use crate::{
    dag::{
        adapter::TLedgerInfoProvider,
        dag_fetcher::TFetchRequester,
        errors::DagDriverError,
        observability::{
            counters::{self, FETCH_ENQUEUE_FAILURES, NODE_PAYLOAD_SIZE, NUM_TXNS_PER_NODE},
            logging::{LogEvent, LogSchema},
            tracing::{observe_node, observe_round, NodeStage, RoundStage},
        },
        order_rule::OrderRule,
        round_state::RoundState,
        storage::DAGStorage,
        types::{
            CertificateAckState, CertifiedAck, CertifiedNode, CertifiedNodeMessage, DAGMessage,
            Extensions, Node, SignatureBuilder,
        },
        DAGRpcResult, RpcHandler,
    },
    payload_client::PayloadClient,
};
use anyhow::{bail, ensure};
use aptos_collections::BoundedVecDeque;
use aptos_config::{
    config::DagPayloadConfig,
    network_id::{NetworkId, PeerNetworkId},
};
use aptos_consensus_types::common::{Author, Payload, PayloadFilter};
use aptos_crypto::hash::CryptoHash;
use aptos_infallible::Mutex;
use aptos_logger::{debug, error};
use aptos_network::application::storage::PeersAndMetadata;
use aptos_reliable_broadcast::{DropGuard, ReliableBroadcast};
use aptos_time_service::{TimeService, TimeServiceTrait};
use aptos_types::{block_info::Round, epoch_state::EpochState};
use aptos_validator_transaction_pool as vtxn_pool;
use async_trait::async_trait;
use futures::{
    executor::block_on,
    future::{join, AbortHandle, Abortable},
};
use futures_channel::oneshot;
use std::{collections::HashSet, sync::Arc, time::Duration};
use tokio_retry::strategy::ExponentialBackoff;

pub(crate) struct DagDriver {
    author: Author,
    epoch_state: Arc<EpochState>,
    dag: Arc<DagStore>,
    payload_client: Arc<dyn PayloadClient>,
    reliable_broadcast: Arc<ReliableBroadcast<DAGMessage, ExponentialBackoff, DAGRpcResult>>,
    time_service: TimeService,
    rb_handles: Mutex<BoundedVecDeque<(DropGuard, u64, Round)>>,
    storage: Arc<dyn DAGStorage>,
    order_rule: Arc<Mutex<OrderRule>>,
    fetch_requester: Arc<dyn TFetchRequester>,
    ledger_info_provider: Arc<dyn TLedgerInfoProvider>,
    round_state: RoundState,
    window_size_config: Round,
    payload_config: DagPayloadConfig,
    health_backoff: HealthBackoff,
    quorum_store_enabled: bool,
    allow_batches_without_pos_in_proposal: bool,
    peers_by_latency: PeersByLatency,
}

impl DagDriver {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        author: Author,
        epoch_state: Arc<EpochState>,
        dag: Arc<DagStore>,
        payload_client: Arc<dyn PayloadClient>,
        reliable_broadcast: Arc<ReliableBroadcast<DAGMessage, ExponentialBackoff, DAGRpcResult>>,
        time_service: TimeService,
        storage: Arc<dyn DAGStorage>,
        order_rule: Arc<Mutex<OrderRule>>,
        fetch_requester: Arc<dyn TFetchRequester>,
        ledger_info_provider: Arc<dyn TLedgerInfoProvider>,
        round_state: RoundState,
        window_size_config: Round,
        payload_config: DagPayloadConfig,
        health_backoff: HealthBackoff,
        quorum_store_enabled: bool,
        allow_batches_without_pos_in_proposal: bool,
        peers_by_latency: PeersByLatency,
    ) -> Self {
        let pending_node = storage
            .get_pending_node()
            .expect("should be able to read dag storage");
        let highest_strong_links_round =
            dag.read().highest_strong_links_round(&epoch_state.verifier);

        let driver = Self {
            author,
            epoch_state,
            dag,
            payload_client,
            reliable_broadcast,
            time_service,
            rb_handles: Mutex::new(BoundedVecDeque::new(window_size_config as usize)),
            storage,
            order_rule,
            fetch_requester,
            ledger_info_provider,
            round_state,
            window_size_config,
            payload_config,
            health_backoff,
            quorum_store_enabled,
            allow_batches_without_pos_in_proposal,
            peers_by_latency,
        };

        // If we were broadcasting the node for the round already, resume it
        if let Some(node) =
            pending_node.filter(|node| node.round() == highest_strong_links_round + 1)
        {
            debug!(
                LogSchema::new(LogEvent::NewRound).round(node.round()),
                "Resume round"
            );
            driver
                .round_state
                .set_current_round(node.round())
                .expect("must succeed");
            driver.broadcast_node(node);
        } else {
            // kick start a new round
            if !driver.dag.read().is_empty() {
                block_on(driver.enter_new_round(highest_strong_links_round + 1));
            }
        }
        driver
    }

    fn add_node(&self, node: CertifiedNode) -> anyhow::Result<()> {
        {
            let dag_reader = self.dag.read();

            // Ensure the window hasn't moved, so we don't request fetch unnecessarily.
            ensure!(node.round() >= dag_reader.lowest_round(), "stale node");

            if !dag_reader.all_exists(node.parents_metadata()) {
                if let Err(err) = self.fetch_requester.request_for_certified_node(node) {
                    FETCH_ENQUEUE_FAILURES
                        .with_label_values(&[&"cert_node"])
                        .inc();
                    error!("request to fetch failed: {}", err);
                }
                bail!(DagDriverError::MissingParents);
            }
        }

        // Note on concurrency: it is possible that a prune operation kicks in here and
        // moves the window forward making the `node` stale, but we guarantee that the
        // order rule only visits `window` length rounds, so having node around should
        // be fine. Any stale node inserted due to this race will be cleaned up with
        // the next prune operation.

        self.dag.add_node(node)?;

        self.check_new_round();
        Ok(())
    }

    fn check_new_round(&self) {
        let (highest_strong_link_round, strong_links) = self.get_highest_strong_links_round();

        debug!(round = highest_strong_link_round, "check new round");

        let minimum_delay = self
            .health_backoff
            .backoff_duration(highest_strong_link_round + 1);
        self.round_state.check_for_new_round(
            highest_strong_link_round,
            strong_links,
            minimum_delay,
        );
    }

    fn get_highest_strong_links_round(&self) -> (Round, Vec<NodeCertificate>) {
        let dag_reader = self.dag.read();
        let highest_strong_links_round =
            dag_reader.highest_strong_links_round(&self.epoch_state.verifier);
        (
            highest_strong_links_round,
            // unwrap is for round 0
            dag_reader
                .get_strong_links_for_round(highest_strong_links_round, &self.epoch_state.verifier)
                .unwrap_or_default(),
        )
    }

    pub async fn enter_new_round(&self, new_round: Round) {
        if let Err(e) = self.round_state.set_current_round(new_round) {
            debug!(error=?e, "cannot enter round");
            return;
        }

        let (strong_links, sys_payload_filter, payload_filter) = {
            let dag_reader = self.dag.read();

            let highest_strong_links_round =
                dag_reader.highest_strong_links_round(&self.epoch_state.verifier);
            if new_round.saturating_sub(highest_strong_links_round) == 0 {
                debug!(
                    new_round = new_round,
                    highest_strong_link_round = highest_strong_links_round,
                    "new round too stale to enter"
                );
                return;
            }

            debug!(LogSchema::new(LogEvent::NewRound).round(new_round));
            counters::CURRENT_ROUND.set(new_round as i64);

            let strong_links = dag_reader
                .get_strong_links_for_round(new_round - 1, &self.epoch_state.verifier)
                .unwrap_or_else(|| {
                    assert_eq!(new_round, 1, "Only expect empty strong links for round 1");
                    vec![]
                });

            if strong_links.is_empty() {
                (
                    strong_links,
                    vtxn_pool::TransactionFilter::PendingTxnHashSet(HashSet::new()),
                    PayloadFilter::Empty,
                )
            } else {
                let highest_commit_round = self
                    .ledger_info_provider
                    .get_highest_committed_anchor_round();

                let nodes = dag_reader
                    .reachable(
                        strong_links.iter().map(|node| node.metadata()),
                        Some(highest_commit_round.saturating_sub(self.window_size_config)),
                        |_| true,
                    )
                    .map(|node_status| node_status.as_node())
                    .collect::<Vec<_>>();

                let payload_filter =
                    PayloadFilter::from(&nodes.iter().map(|node| node.payload()).collect());
                let validator_txn_hashes = nodes
                    .iter()
                    .flat_map(|node| node.validator_txns())
                    .map(|txn| txn.hash());
                let validator_payload_filter = vtxn_pool::TransactionFilter::PendingTxnHashSet(
                    HashSet::from_iter(validator_txn_hashes),
                );

                (strong_links, validator_payload_filter, payload_filter)
            }
        };

        let (max_txns, max_size_bytes) = self
            .health_backoff
            .calculate_payload_limits(new_round, &self.payload_config);

        let (validator_txns, payload) = match self
            .payload_client
            .pull_payload(
                Duration::from_millis(self.payload_config.payload_pull_max_poll_time_ms),
                max_txns,
                max_size_bytes,
                // TODO: Set max_inline_items and max_inline_bytes correctly
                100,
                100 * 1024,
                sys_payload_filter,
                payload_filter,
                Box::pin(async {}),
                false,
                0,
                0.0,
            )
            .await
        {
            Ok(payload) => payload,
            Err(e) => {
                error!("error pulling payload: {}", e);
                (
                    vec![],
                    Payload::empty(
                        self.quorum_store_enabled,
                        self.allow_batches_without_pos_in_proposal,
                    ),
                )
            },
        };

        // TODO: need to wait to pass median of parents timestamp
        let highest_parent_timestamp = strong_links
            .iter()
            .map(|node| node.metadata().timestamp())
            .max()
            .unwrap_or(0);
        let timestamp = std::cmp::max(
            self.time_service.now_unix_time().as_micros() as u64,
            highest_parent_timestamp + 1,
        );
        let new_node = Node::new(
            self.epoch_state.epoch,
            new_round,
            self.author,
            timestamp,
            validator_txns,
            payload,
            strong_links,
            Extensions::empty(),
        );
        self.storage
            .save_pending_node(&new_node)
            .expect("node must be saved");
        self.broadcast_node(new_node);
    }

    fn broadcast_node(&self, node: Node) {
        let rb = self.reliable_broadcast.clone();
        let rb2 = self.reliable_broadcast.clone();
        let (abort_handle, abort_registration) = AbortHandle::new_pair();
        let (tx, rx) = oneshot::channel();
        let signature_builder =
            SignatureBuilder::new(node.metadata().clone(), self.epoch_state.clone(), tx);
        let cert_ack_set = CertificateAckState::new(self.epoch_state.verifier.len());
        let latest_ledger_info = self.ledger_info_provider.clone();

        let round = node.round();
        let node_clone = node.clone();
        let timestamp = node.timestamp();
        let ordered_peers = self.peers_by_latency.get_peers();
        let ordered_peers_clone = ordered_peers.clone();
        let node_broadcast = async move {
            debug!(LogSchema::new(LogEvent::BroadcastNode), id = node.id());

            defer!( observe_round(timestamp, RoundStage::NodeBroadcastedAll); );
            rb.multicast(node, signature_builder, ordered_peers_clone)
                .await
        };
        let certified_broadcast = async move {
            let Ok(certificate) = rx.await else {
                error!("channel closed before receiving ceritifcate");
                return;
            };
            observe_round(timestamp, RoundStage::NodeBroadcastedQuorum);

            debug!(
                LogSchema::new(LogEvent::BroadcastCertifiedNode),
                id = node_clone.id()
            );

            defer!( observe_round(timestamp, RoundStage::CertifiedNodeBroadcasted); );
            let certified_node =
                CertifiedNode::new(node_clone, certificate.signatures().to_owned());
            let certified_node_msg = CertifiedNodeMessage::new(
                certified_node,
                latest_ledger_info.get_latest_ledger_info(),
            );
            rb2.multicast(certified_node_msg, cert_ack_set, ordered_peers)
                .await
        };
        let core_task = join(node_broadcast, certified_broadcast);
        let author = self.author;
        let task = async move {
            debug!("{} Start reliable broadcast for round {}", author, round);
            core_task.await;
            debug!("Finish reliable broadcast for round {}", round);
        };
        tokio::spawn(Abortable::new(task, abort_registration));
        // TODO: a bounded vec queue can hold more than window rounds, but we want to limit
        // by number of rounds.
        let mut rb_handles = self.rb_handles.lock();
        if let Some((_handle, prev_round_timestamp, _)) =
            rb_handles.push_back((DropGuard::new(abort_handle), timestamp, round))
        {
            // TODO: this observation is inaccurate.
            observe_round(prev_round_timestamp, RoundStage::Finished);
        }

        while let Some(front) = rb_handles.front() {
            if round.abs_diff(front.2) > self.window_size_config {
                observe_round(front.1, RoundStage::Finished);
                rb_handles.pop_front();
            } else {
                break;
            }
        }
    }

    pub fn fetch_callback(&self) {
        self.order_rule.process_all();
        self.check_new_round();
    }
}

#[async_trait]
impl RpcHandler for DagDriver {
    type Request = CertifiedNode;
    type Response = CertifiedAck;

    async fn process(&self, certified_node: Self::Request) -> anyhow::Result<Self::Response> {
        let epoch = certified_node.metadata().epoch();
        debug!(LogSchema::new(LogEvent::ReceiveCertifiedNode)
            .remote_peer(*certified_node.author())
            .round(certified_node.round()));
        if self.dag.read().exists(certified_node.metadata()) {
            return Ok(CertifiedAck::new(epoch));
        }

        observe_node(certified_node.timestamp(), NodeStage::CertifiedNodeReceived);
        NUM_TXNS_PER_NODE.observe(certified_node.payload().len() as f64);
        NODE_PAYLOAD_SIZE.observe(certified_node.payload().size() as f64);

        let node_metadata = certified_node.metadata().clone();
        self.add_node(certified_node)
            .map(|_| self.order_rule.process_new_node(&node_metadata))?;

        Ok(CertifiedAck::new(epoch))
    }
}

pub struct PeersByLatency {
    peers: Vec<Author>,
    peers_and_metadata: Arc<PeersAndMetadata>,
}

impl PeersByLatency {
    pub fn new(peers: Vec<Author>, peers_and_metadata: Arc<PeersAndMetadata>) -> Self {
        Self {
            peers,
            peers_and_metadata,
        }
    }

    fn get_peers(&self) -> Vec<Author> {
        let mut peers = self.peers.clone();
        peers.sort_unstable_by(|a, b| {
            let a = Self::get_latency(&self.peers_and_metadata, *a).unwrap_or(0.0);
            let b = Self::get_latency(&self.peers_and_metadata, *b).unwrap_or(0.0);
            b.partial_cmp(&a).unwrap()
        });
        peers
    }

    fn get_latency(peers_and_metadata: &PeersAndMetadata, peer: Author) -> Option<f64> {
        peers_and_metadata
            .get_metadata_for_peer(PeerNetworkId::new(NetworkId::Validator, peer))
            .map(|metadata| {
                metadata
                    .get_peer_monitoring_metadata()
                    .average_ping_latency_secs
            })
            .ok()
            .flatten()
    }
}
