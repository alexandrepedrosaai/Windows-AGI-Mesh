//! # Zenith Capability System
//!
//! Every operation in the Zenith OS is mediated by cryptographically signed
//! capability tokens. No domain, application, or service can access a resource
//! without a valid, unexpired capability token issued by the Security Broker.
//!
//! ## Token Lifecycle
//!
//! ```text
//! Identity → Request → Security Broker → Issue Token → Use → Revoke
//! ```
//!
//! Tokens are:
//! - Scoped to a specific resource and operation
//! - Time-limited (TTL enforced by the kernel)
//! - Cryptographically bound to the requesting identity
//! - Revocable at any time by the Security Broker

use serde::{Deserialize, Serialize};
use uuid::Uuid;
use sha2::{Sha256, Digest};
use crate::types::{ZCapabilityId, ZIdentityId, ZSessionId, ZTimestamp};
use crate::domain::{Domain, ResourceClass, AccessLevel};

// ---------------------------------------------------------------------------
// Permission set
// ---------------------------------------------------------------------------

/// A single permission granted by a capability token
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Permission {
    /// Resource class this permission applies to
    pub resource: ResourceClass,
    /// Level of access granted
    pub access: AccessLevel,
    /// Optional sub-resource path (e.g., "/documents/contracts/")
    pub scope: Option<String>,
}

impl Permission {
    /// Create a simple read permission for a resource
    pub fn read(resource: ResourceClass) -> Self {
        Self { resource, access: AccessLevel::Read, scope: None }
    }

    /// Create a full read/write permission for a resource
    pub fn read_write(resource: ResourceClass) -> Self {
        Self { resource, access: AccessLevel::ReadWrite, scope: None }
    }

    /// Create a scoped permission
    pub fn scoped(resource: ResourceClass, access: AccessLevel, scope: impl Into<String>) -> Self {
        Self { resource, access, scope: Some(scope.into()) }
    }
}

// ---------------------------------------------------------------------------
// Capability token
// ---------------------------------------------------------------------------

/// Cryptographically signed capability token
///
/// Issued by the Zenith Security Broker. Must be presented with every
/// cross-domain or privileged operation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CapabilityToken {
    /// Unique token ID
    pub id: ZCapabilityId,
    /// Identity that owns this token
    pub subject: ZIdentityId,
    /// Session this token is bound to
    pub session: ZSessionId,
    /// Domain that issued this token
    pub issuer: Domain,
    /// Domains that may use this token
    pub audience: Vec<Domain>,
    /// Permissions granted by this token
    pub permissions: Vec<Permission>,
    /// Token issue timestamp
    pub issued_at: ZTimestamp,
    /// Token expiry timestamp (None = no expiry)
    pub expires_at: Option<ZTimestamp>,
    /// Whether this token has been revoked
    pub revoked: bool,
    /// SHA-256 signature of the token payload
    pub signature: Vec<u8>,
}

impl CapabilityToken {
    /// Create a new capability token (unsigned — call `sign()` before use)
    pub fn new(
        subject: ZIdentityId,
        session: ZSessionId,
        issuer: Domain,
        audience: Vec<Domain>,
        permissions: Vec<Permission>,
        ttl_seconds: Option<u64>,
    ) -> Self {
        let issued_at = ZTimestamp(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_micros() as i64,
        );
        let expires_at = ttl_seconds.map(|ttl| {
            ZTimestamp(issued_at.0 + (ttl as i64 * 1_000_000))
        });

        Self {
            id: Uuid::new_v4(),
            subject,
            session,
            issuer,
            audience,
            permissions,
            issued_at,
            expires_at,
            revoked: false,
            signature: Vec::new(),
        }
    }

    /// Sign the token with a secret key (HMAC-SHA256 simulation)
    pub fn sign(&mut self, secret: &[u8]) {
        let payload = self.canonical_payload();
        let mut hasher = Sha256::new();
        hasher.update(secret);
        hasher.update(&payload);
        self.signature = hasher.finalize().to_vec();
    }

    /// Verify the token signature
    pub fn verify(&self, secret: &[u8]) -> bool {
if self.revoked || self.is_expired() {
        let payload = self.canonical_payload();
        let mut hasher = Sha256::new();
        hasher.update(secret);
        hasher.update(&payload);
        let expected = hasher.finalize().to_vec();
        self.signature == expected
    }

    /// Check if the token is expired
    pub fn is_expired(&self) -> bool {
        if let Some(exp) = self.expires_at {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_micros() as i64;
            now > exp.0
        } else {
            false
        }
    }

    /// Check if the token is valid (not revoked, not expired)
    pub fn is_valid(&self) -> bool {
        !self.revoked && !self.is_expired()
    }

    /// Check if this token grants a specific permission
    pub fn grants(&self, resource: &ResourceClass, access: &AccessLevel) -> bool {
        if !self.is_valid() {
            return false;
        }
        self.permissions.iter().any(|p| {
            &p.resource == resource
                && (p.access == AccessLevel::ReadWrite
                    || &p.access == access)
        })
    }

    /// Revoke this token
    pub fn revoke(&mut self) {
        self.revoked = true;
    }

    /// Canonical byte representation for signing
    fn canonical_payload(&self) -> Vec<u8> {
        let s = format!(
            "{}:{}:{}:{}:{}",
            self.id,
            self.subject,
            self.session,
            self.issuer.name(),
            self.issued_at.0,
        );
        s.into_bytes()
    }
}

// ---------------------------------------------------------------------------
// Capability request
// ---------------------------------------------------------------------------

/// Request for a new capability token, submitted to the Security Broker
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CapabilityRequest {
    /// Requesting identity
    pub requester: ZIdentityId,
    /// Session context
    pub session: ZSessionId,
    /// Requesting domain
    pub domain: Domain,
    /// Permissions being requested
    pub permissions: Vec<Permission>,
    /// Requested TTL in seconds (None = indefinite)
    pub ttl_seconds: Option<u64>,
    /// Human-readable justification
    pub justification: String,
}

// ---------------------------------------------------------------------------
// Capability store (in-memory registry)
// ---------------------------------------------------------------------------

/// In-memory registry of active capability tokens
#[derive(Debug, Default)]
pub struct CapabilityStore {
    tokens: std::collections::HashMap<ZCapabilityId, CapabilityToken>,
}

impl CapabilityStore {
    /// Create a new empty store
    pub fn new() -> Self {
        Self::default()
    }

    /// Insert a token into the store
    pub fn insert(&mut self, token: CapabilityToken) {
        self.tokens.insert(token.id, token);
    }

    /// Look up a token by ID
    pub fn get(&self, id: &ZCapabilityId) -> Option<&CapabilityToken> {
        self.tokens.get(id)
    }

    /// Revoke a token by ID
    pub fn revoke(&mut self, id: &ZCapabilityId) -> bool {
        if let Some(token) = self.tokens.get_mut(id) {
            token.revoke();
            true
        } else {
            false
        }
    }

    /// Remove all expired tokens
    pub fn purge_expired(&mut self) {
        self.tokens.retain(|_, t| !t.is_expired());
    }

    /// Count of active (valid) tokens
    pub fn active_count(&self) -> usize {
        self.tokens.values().filter(|t| t.is_valid()).count()
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::ResourceClass;

    fn make_token() -> CapabilityToken {
        let subject  = Uuid::new_v4();
        let session  = Uuid::new_v4();
        let mut token = CapabilityToken::new(
            subject,
            session,
            Domain::Windows,
            vec![Domain::Android, Domain::AI],
            vec![Permission::read_write(ResourceClass::Files)],
            Some(3600),
        );
        token.sign(b"zenith-secret-key");
        token
    }

    #[test]
    fn token_sign_verify() {
        let token = make_token();
        assert!(token.verify(b"zenith-secret-key"));
        assert!(!token.verify(b"wrong-key"));
    }

    #[test]
    fn token_grants_permission() {
        let token = make_token();
        assert!(token.grants(&ResourceClass::Files, &AccessLevel::Read));
        assert!(token.grants(&ResourceClass::Files, &AccessLevel::ReadWrite));
        assert!(!token.grants(&ResourceClass::Camera, &AccessLevel::Read));
    }

    #[test]
    fn token_revocation() {
        let mut token = make_token();
        assert!(token.is_valid());
        token.revoke();
        assert!(!token.is_valid());
        assert!(!token.grants(&ResourceClass::Files, &AccessLevel::Read));
    }

    #[test]
    fn store_insert_and_revoke() {
        let mut store = CapabilityStore::new();
        let token = make_token();
        let id = token.id;
        store.insert(token);
        assert_eq!(store.active_count(), 1);
        store.revoke(&id);
        assert_eq!(store.active_count(), 0);
    }
}