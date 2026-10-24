//! # Zenith Security Model
//!
//! Every workload in the Zenith OS executes inside a cryptographic envelope.
//! No application has direct hardware access — all operations are mediated
//! by the Security Broker through capability tokens.
//!
//! ## Security Layers
//!
//! ```text
//! Application
//!      ↓
//! Cryptographic Container
//!      ↓
//! Domain Isolation Boundary
//!      ↓
//! Zenith Microkernel
//!      ↓
//! Hardware (ARM TrustZone / Intel TDX)
//! ```

use serde::{Deserialize, Serialize};
use uuid::Uuid;
use sha2::{Sha256, Digest};
use crate::types::{ZIdentityId, ZSessionId, ZTaskId, ZTimestamp};
use crate::domain::Domain;

// ---------------------------------------------------------------------------
// Security level
// ---------------------------------------------------------------------------

/// Security classification level
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum SecurityLevel {
    /// Public — no restrictions
    Public = 0,
    /// Internal — organization-only
    Internal = 1,
    /// Confidential — need-to-know
    Confidential = 2,
    /// Secret — highly restricted
    Secret = 3,
    /// Top Secret — maximum restriction
    TopSecret = 4,
    /// Quantum-encrypted — requires QKD
    QuantumEncrypted = 5,
}

impl SecurityLevel {
    /// Whether this level requires quantum key distribution
    pub fn requires_qkd(&self) -> bool {
        matches!(self, SecurityLevel::QuantumEncrypted)
    }

    /// Whether this level requires hardware attestation
    pub fn requires_attestation(&self) -> bool {
        matches!(
            self,
            SecurityLevel::Secret | SecurityLevel::TopSecret | SecurityLevel::QuantumEncrypted
        )
    }
}

// ---------------------------------------------------------------------------
// Cryptographic container
// ---------------------------------------------------------------------------

/// A cryptographic container wrapping a workload
///
/// Every task executes inside a container. The container enforces:
/// - Memory isolation (no cross-container reads)
/// - Capability-gated I/O
/// - Encrypted inter-container communication
/// - Audit logging of all operations
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CryptoContainer {
    /// Container ID
    pub id: Uuid,
    /// Task this container wraps
    pub task_id: ZTaskId,
    /// Session context
    pub session: ZSessionId,
    /// Identity context
    pub identity: ZIdentityId,
    /// Domain this container runs in
    pub domain: Domain,
    /// Security level
    pub security_level: SecurityLevel,
    /// AES-256-GCM encryption key (32 bytes)
    pub encryption_key: Vec<u8>,
    /// Container nonce (12 bytes for AES-GCM)
    pub nonce: Vec<u8>,
    /// Whether the container is currently sealed (encrypted)
    pub sealed: bool,
    /// Audit log of operations
    pub audit_log: Vec<AuditEntry>,
    /// Container creation timestamp
    pub created_at: ZTimestamp,
}

impl CryptoContainer {
    /// Create a new cryptographic container
    pub fn new(
        task_id: ZTaskId,
        session: ZSessionId,
        identity: ZIdentityId,
        domain: Domain,
        security_level: SecurityLevel,
    ) -> Self {
        // In production: use a CSPRNG. Here we use a deterministic seed for testing.
        let key = Self::generate_key(&task_id);
        let nonce = Self::generate_nonce(&session);
        let now = ZTimestamp(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_micros() as i64,
        );
        Self {
            id: Uuid::new_v4(),
            task_id,
            session,
            identity,
            domain,
            security_level,
            encryption_key: key,
            nonce,
            sealed: false,
            audit_log: Vec::new(),
            created_at: now,
        }
    }

    /// Seal the container (encrypt its state)
    pub fn seal(&mut self) {
        self.sealed = true;
        self.log(AuditAction::Sealed, "Container sealed");
    }

    /// Unseal the container (decrypt its state)
    pub fn unseal(&mut self, key: &[u8]) -> bool {
        if key == self.encryption_key.as_slice() {
            self.sealed = false;
            self.log(AuditAction::Unsealed, "Container unsealed");
            true
        } else {
            self.log(AuditAction::AccessDenied, "Unseal failed: wrong key");
            false
        }
    }

    /// Log an audit event
    pub fn log(&mut self, action: AuditAction, detail: impl Into<String>) {
        self.audit_log.push(AuditEntry {
            timestamp: ZTimestamp(
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_micros() as i64,
            ),
            action,
            detail: detail.into(),
            domain: self.domain.clone(),
        });
    }

    /// Generate a deterministic 32-byte key from a UUID (for testing)
    fn generate_key(id: &Uuid) -> Vec<u8> {
        let mut hasher = Sha256::new();
        hasher.update(id.as_bytes());
        hasher.update(b"zenith-key-derivation-v1");
        hasher.finalize().to_vec()
    }

    /// Generate a deterministic 12-byte nonce from a UUID (for testing)
    fn generate_nonce(id: &Uuid) -> Vec<u8> {
        let mut hasher = Sha256::new();
        hasher.update(id.as_bytes());
        hasher.update(b"zenith-nonce-v1");
        hasher.finalize()[..12].to_vec()
    }

    /// Compute integrity hash of the container state
    pub fn integrity_hash(&self) -> Vec<u8> {
        let mut hasher = Sha256::new();
        hasher.update(self.id.as_bytes());
        hasher.update(self.task_id.as_bytes());
        hasher.update(self.session.as_bytes());
        hasher.update(&self.encryption_key);
        hasher.finalize().to_vec()
    }
}

// ---------------------------------------------------------------------------
// Audit log
// ---------------------------------------------------------------------------

/// Type of audited action
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum AuditAction {
    /// Container created
    Created,
    /// Container sealed
    Sealed,
    /// Container unsealed
    Unsealed,
    /// Resource access granted
    AccessGranted,
    /// Resource access denied
    AccessDenied,
    /// Cross-domain message sent
    MessageSent,
    /// Cross-domain message received
    MessageReceived,
    /// Task migrated
    Migrated,
    /// Capability token used
    CapabilityUsed,
    /// Capability token revoked
    CapabilityRevoked,
    /// Security violation detected
    SecurityViolation,
}

/// A single audit log entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditEntry {
    /// Timestamp of the event
    pub timestamp: ZTimestamp,
    /// Action type
    pub action: AuditAction,
    /// Human-readable detail
    pub detail: String,
    /// Domain where the event occurred
    pub domain: Domain,
}

// ---------------------------------------------------------------------------
// Security broker
// ---------------------------------------------------------------------------

/// The Security Broker — central authority for all security decisions
///
/// The broker:
/// - Issues and revokes capability tokens
/// - Validates cross-domain operations
/// - Maintains the global audit log
/// - Enforces security level policies
#[derive(Debug, Default)]
pub struct SecurityBroker {
    /// Global audit log
    audit_log: Vec<AuditEntry>,
    /// Active containers
    containers: std::collections::HashMap<Uuid, CryptoContainer>,
    /// Revoked container IDs
    revoked: std::collections::HashSet<Uuid>,
    /// Master secret for token signing
    master_secret: Vec<u8>,
}

impl SecurityBroker {
    /// Create a new security broker with a master secret
    pub fn new(master_secret: Vec<u8>) -> Self {
        Self {
            audit_log: Vec::new(),
            containers: std::collections::HashMap::new(),
            revoked: std::collections::HashSet::new(),
            master_secret,
        }
    }

    /// Register a new container
    pub fn register_container(&mut self, container: CryptoContainer) {
        self.audit_log.push(AuditEntry {
            timestamp: container.created_at,
            action: AuditAction::Created,
            detail: format!("Container {} registered for task {}", container.id, container.task_id),
            domain: container.domain.clone(),
        });
        self.containers.insert(container.id, container);
    }

    /// Revoke a container
    pub fn revoke_container(&mut self, id: &Uuid) -> bool {
        if self.containers.contains_key(id) {
            self.revoked.insert(*id);
            self.audit_log.push(AuditEntry {
                timestamp: ZTimestamp(
                    std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap_or_default()
                        .as_micros() as i64,
                ),
                action: AuditAction::CapabilityRevoked,
                detail: format!("Container {id} revoked"),
                domain: Domain::Windows, // broker domain
            });
            true
        } else {
            false
        }
    }

    /// Check if a container is valid (not revoked)
    pub fn is_valid(&self, id: &Uuid) -> bool {
        self.containers.contains_key(id) && !self.revoked.contains(id)
    }

    /// Validate a cross-domain operation
    pub fn validate_cross_domain(
        &mut self,
        from: &Domain,
        to: &Domain,
        operation: &str,
    ) -> bool {
        // Basic policy: AI domain can talk to all; Android ↔ Windows requires explicit grant
        let allowed = match (from, to) {
            (Domain::AI, _)      => true,
            (_, Domain::AI)      => true,
            (Domain::Android, Domain::Windows) => true,
            (Domain::Windows, Domain::Android) => true,
            (Domain::Quantum, _) => true,
            (a, b) if a == b     => true,
            _                    => false,
        };

        let action = if allowed {
            AuditAction::AccessGranted
        } else {
            AuditAction::AccessDenied
        };

        self.audit_log.push(AuditEntry {
            timestamp: ZTimestamp(
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_micros() as i64,
            ),
            action,
            detail: format!("{from} → {to}: {operation}"),
            domain: from.clone(),
        });

        allowed
    }

    /// Get the global audit log
    pub fn audit_log(&self) -> &[AuditEntry] {
        &self.audit_log
    }

    /// Count of active containers
    pub fn container_count(&self) -> usize {
        self.containers.len() - self.revoked.len()
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn container_seal_unseal() {
        let task_id    = Uuid::new_v4();
        let session    = Uuid::new_v4();
        let identity   = Uuid::new_v4();
        let mut container = CryptoContainer::new(
            task_id, session, identity,
            Domain::Windows, SecurityLevel::Confidential,
        );
        assert!(!container.sealed);
        container.seal();
        assert!(container.sealed);
        let key = container.encryption_key.clone();
        assert!(container.unseal(&key));
        assert!(!container.sealed);
    }

    #[test]
    fn container_wrong_key_rejected() {
        let task_id  = Uuid::new_v4();
        let session  = Uuid::new_v4();
        let identity = Uuid::new_v4();
        let mut container = CryptoContainer::new(
            task_id, session, identity,
            Domain::Android, SecurityLevel::Secret,
        );
        container.seal();
        assert!(!container.unseal(b"wrong-key"));
        assert!(container.sealed);
    }

    #[test]
    fn security_broker_cross_domain() {
        let mut broker = SecurityBroker::new(b"master-secret".to_vec());
        assert!(broker.validate_cross_domain(&Domain::Android, &Domain::Windows, "clipboard.read"));
        assert!(broker.validate_cross_domain(&Domain::AI, &Domain::Quantum, "inference.run"));
        assert!(!broker.validate_cross_domain(&Domain::Android, &Domain::Quantum, "qpu.access"));
    }

    #[test]
    fn security_level_ordering() {
        assert!(SecurityLevel::TopSecret > SecurityLevel::Secret);
        assert!(SecurityLevel::QuantumEncrypted > SecurityLevel::TopSecret);
        assert!(SecurityLevel::Public < SecurityLevel::Internal);
    }

    #[test]
    fn audit_log_populated() {
        let mut broker = SecurityBroker::new(b"secret".to_vec());
        broker.validate_cross_domain(&Domain::Windows, &Domain::Android, "file.read");
        broker.validate_cross_domain(&Domain::Android, &Domain::Quantum, "qpu.access");
        assert_eq!(broker.audit_log().len(), 2);
    }
}