//! # Cloud Domain Runtime
//!
//! The Cloud Runtime manages Azure offload, edge computing, and cloud sync.

use std::collections::HashMap;
use uuid::Uuid;
use serde::{Deserialize, Serialize};
use zenith_abi::domain::{Domain, DomainHealth};
use zenith_abi::task::{ZenithTask, TaskState};
use zenith_abi::types::ZTaskId;
use zenith_abi::contract::IZDomainRuntime;
use crate::error::RuntimeError;
use crate::metrics::DomainMetrics;
use crate::task_executor::TaskExecutor;

/// Cloud service type
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum CloudService {
    AzureOpenAI,
    AzureCognitiveServices,
    AzureStorage,
    AzureCosmosDb,
    AzureServiceBus,
    AzureEventHub,
    OneDrive,
    SharePoint,
    MicrosoftGraph,
    AzureEdge,
    Custom(String),
}

impl CloudService {
    pub fn endpoint(&self) -> &str {
        match self {
            CloudService::AzureOpenAI             => "https://api.openai.azure.com",
            CloudService::AzureCognitiveServices  => "https://cognitiveservices.azure.com",
            CloudService::AzureStorage            => "https://storage.azure.com",
            CloudService::AzureCosmosDb           => "https://cosmos.azure.com",
            CloudService::OneDrive                => "https://graph.microsoft.com/v1.0/me/drive",
            CloudService::SharePoint              => "https://graph.microsoft.com/v1.0/sites",
            CloudService::MicrosoftGraph          => "https://graph.microsoft.com/v1.0",
            CloudService::AzureEdge               => "https://edge.azure.com",
            _                                     => "https://azure.microsoft.com",
        }
    }
}

/// Cloud connection state
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ConnectionState {
    Disconnected,
    Connecting,
    Connected { latency_ms: u32 },
    Degraded  { latency_ms: u32, packet_loss_pct: f32 },
    Failed    { reason: String },
}

impl ConnectionState {
    pub fn is_connected(&self) -> bool {
        matches!(self, ConnectionState::Connected { .. } | ConnectionState::Degraded { .. })
    }
}

/// Cloud sync job
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncJob {
    pub id:           Uuid,
    pub service:      CloudService,
    pub local_path:   String,
    pub remote_path:  String,
    pub direction:    SyncDirection,
    pub state:        SyncState,
    pub bytes_total:  u64,
    pub bytes_synced: u64,
    pub started_at:   std::time::Instant,
}

/// Sync direction
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum SyncDirection {
    Upload,
    Download,
    Bidirectional,
}

/// Sync state
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum SyncState {
    Pending,
    Running,
    Completed,
    Failed { reason: String },
    Paused,
}

impl SyncJob {
    pub fn new(service: CloudService, local: impl Into<String>, remote: impl Into<String>, direction: SyncDirection) -> Self {
        Self {
            id:           Uuid::new_v4(),
            service,
            local_path:   local.into(),
            remote_path:  remote.into(),
            direction,
            state:        SyncState::Pending,
            bytes_total:  0,
            bytes_synced: 0,
            started_at:   std::time::Instant::now(),
        }
    }

    pub fn progress(&self) -> f64 {
        if self.bytes_total == 0 { return 0.0; }
        self.bytes_synced as f64 / self.bytes_total as f64
    }

    pub fn is_complete(&self) -> bool {
        matches!(self.state, SyncState::Completed)
    }
}

/// Cloud offload request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OffloadRequest {
    pub id:          Uuid,
    pub task_type:   String,
    pub payload:     Vec<u8>,
    pub service:     CloudService,
    pub priority:    u8,
    pub timeout_ms:  u32,
    pub submitted_at: std::time::Instant,
}

impl OffloadRequest {
    pub fn new(task_type: impl Into<String>, payload: Vec<u8>, service: CloudService) -> Self {
        Self {
            id:           Uuid::new_v4(),
            task_type:    task_type.into(),
            payload,
            service,
            priority:     128,
            timeout_ms:   30_000,
            submitted_at: std::time::Instant::now(),
        }
    }
}

/// The Cloud Domain Runtime
#[derive(Debug)]
pub struct CloudRuntime {
    health:          DomainHealth,
    active_tasks:    HashMap<ZTaskId, ZenithTask>,
    connections:     HashMap<String, ConnectionState>,
    sync_jobs:       HashMap<Uuid, SyncJob>,
    offload_queue:   std::collections::VecDeque<OffloadRequest>,
    metrics:         DomainMetrics,
    executor:        TaskExecutor,
    initialized:     bool,
    region:          String,
    subscription_id: String,
    total_synced_bytes: u64,
    total_offloads:  u64,
    bandwidth_mbps:  f64,
}

impl CloudRuntime {
    pub fn new() -> Self {
        Self {
            health:             DomainHealth::Initializing,
            active_tasks:       HashMap::new(),
            connections:        HashMap::new(),
            sync_jobs:          HashMap::new(),
            offload_queue:      std::collections::VecDeque::new(),
            metrics:            DomainMetrics::new(Domain::Cloud),
            executor:           TaskExecutor::new(Domain::Cloud),
            initialized:        false,
            region:             "eastus".into(),
            subscription_id:    Uuid::new_v4().to_string(),
            total_synced_bytes: 0,
            total_offloads:     0,
            bandwidth_mbps:     100.0,
        }
    }

    /// Connect to a cloud service
    pub fn connect(&mut self, service: CloudService) -> bool {
        let key = format!("{service:?}");
        self.connections.insert(key, ConnectionState::Connected { latency_ms: 20 });
        self.metrics.record_event("cloud_connected");
        true
    }

    /// Disconnect from a cloud service
    pub fn disconnect(&mut self, service: &CloudService) {
        let key = format!("{service:?}");
        self.connections.insert(key, ConnectionState::Disconnected);
    }

    /// Check if connected to a service
    pub fn is_connected(&self, service: &CloudService) -> bool {
        let key = format!("{service:?}");
        self.connections.get(&key).map(|s| s.is_connected()).unwrap_or(false)
    }

    /// Submit a sync job
    pub fn submit_sync(&mut self, service: CloudService, local: impl Into<String>, remote: impl Into<String>, direction: SyncDirection) -> Uuid {
        let mut job = SyncJob::new(service, local, remote, direction);
        job.state        = SyncState::Running;
        job.bytes_total  = 1024 * 1024; // 1 MB simulated
        job.bytes_synced = 1024 * 1024; // Immediately complete (simulated)
        job.state        = SyncState::Completed;
        let id = job.id;
        self.total_synced_bytes += job.bytes_synced;
        self.sync_jobs.insert(id, job);
        self.metrics.record_event("sync_completed");
        id
    }

    /// Submit a cloud offload request
    pub fn submit_offload(&mut self, request: OffloadRequest) -> Uuid {
        let id = request.id;
        self.offload_queue.push_back(request);
        self.total_offloads += 1;
        self.metrics.record_event("offload_submitted");
        id
    }

    /// Process one offload request
    pub fn process_offload(&mut self) -> Option<Vec<u8>> {
        let request = self.offload_queue.pop_front()?;
        // Simulate cloud processing
        let result = format!("{{\"status\":\"ok\",\"task\":\"{}\",\"region\":\"{}\"}}", 
            request.task_type, self.region).into_bytes();
        self.metrics.record_event("offload_completed");
        Some(result)
    }

    /// Get sync job status
    pub fn get_sync_job(&self, id: &Uuid) -> Option<&SyncJob> {
        self.sync_jobs.get(id)
    }

    /// Connected service count
    pub fn connected_count(&self) -> usize {
        self.connections.values().filter(|s| s.is_connected()).count()
    }

    /// Total synced bytes
    pub fn total_synced_bytes(&self) -> u64 { self.total_synced_bytes }

    /// Total offloads
    pub fn total_offloads(&self) -> u64 { self.total_offloads }

    /// Offload queue depth
    pub fn offload_queue_depth(&self) -> usize { self.offload_queue.len() }

    /// Azure region
    pub fn region(&self) -> &str { &self.region }

    /// Metrics
    pub fn metrics(&self) -> &DomainMetrics { &self.metrics }
}

impl IZDomainRuntime for CloudRuntime {
    fn start(&mut self) -> zenith_abi::types::ZResult<()> {
        self.initialized = true;
        self.health = DomainHealth::Healthy;

        // Connect to default Azure services
        self.connect(CloudService::OneDrive);
        self.connect(CloudService::MicrosoftGraph);
        self.connect(CloudService::AzureStorage);

        tracing::info!("Cloud Runtime started (region: {}, bandwidth: {}Mbps)",
            self.region, self.bandwidth_mbps);
        Ok(())
    }

    fn stop(&mut self) -> zenith_abi::types::ZResult<()> {
        // Disconnect all services
        let keys: Vec<String> = self.connections.keys().cloned().collect();
        for key in keys {
            self.connections.insert(key, ConnectionState::Disconnected);
        }
        self.offload_queue.clear();
        self.health = DomainHealth::ShuttingDown;
        self.initialized = false;
        Ok(())
    }

    fn health(&self) -> DomainHealth { self.health.clone() }

    fn accept_task(&mut self, mut task: ZenithTask, _snapshot: &[u8]) -> zenith_abi::types::ZResult<()> {
        task.resume();
        self.active_tasks.insert(task.id, task);
        self.metrics.record_task_accepted();
        Ok(())
    }

    fn snapshot_all(&mut self) -> zenith_abi::types::ZResult<Vec<(ZTaskId, Vec<u8>)>> {
        Ok(self.active_tasks.iter()
            .map(|(&id, task)| (id, serde_json::to_vec(task).unwrap_or_default()))
            .collect())
    }

    fn domain(&self) -> Domain { Domain::Cloud }
}

impl Default for CloudRuntime {
    fn default() -> Self { Self::new() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cloud_runtime_start() {
        let mut rt = CloudRuntime::new();
        rt.start().unwrap();
        assert_eq!(rt.health(), DomainHealth::Healthy);
        assert!(rt.connected_count() > 0);
    }

    #[test]
    fn cloud_connect_disconnect() {
        let mut rt = CloudRuntime::new();
        rt.start().unwrap();
        rt.connect(CloudService::AzureOpenAI);
        assert!(rt.is_connected(&CloudService::AzureOpenAI));
        rt.disconnect(&CloudService::AzureOpenAI);
        assert!(!rt.is_connected(&CloudService::AzureOpenAI));
    }

    #[test]
    fn cloud_sync_job() {
        let mut rt = CloudRuntime::new();
        rt.start().unwrap();
        let id = rt.submit_sync(
            CloudService::OneDrive,
            "/local/documents",
            "/remote/documents",
            SyncDirection::Upload,
        );
        let job = rt.get_sync_job(&id).unwrap();
        assert!(job.is_complete());
        assert!(rt.total_synced_bytes() > 0);
    }

    #[test]
    fn cloud_offload() {
        let mut rt = CloudRuntime::new();
        rt.start().unwrap();
        let req = OffloadRequest::new("llm-inference", b"prompt data".to_vec(), CloudService::AzureOpenAI);
        rt.submit_offload(req);
        assert_eq!(rt.offload_queue_depth(), 1);
        let result = rt.process_offload().unwrap();
        assert!(!result.is_empty());
        assert_eq!(rt.offload_queue_depth(), 0);
    }

    #[test]
    fn cloud_domain_identity() {
        let rt = CloudRuntime::new();
        assert_eq!(rt.domain(), Domain::Cloud);
    }
}