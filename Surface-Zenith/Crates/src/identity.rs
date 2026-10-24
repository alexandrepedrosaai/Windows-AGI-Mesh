//! # Zenith Identity Model
//!
//! Identity is the fundamental unit of the Zenith OS — not the device.
//! A user's computational context follows their identity across all
//! physical form factors and devices.

use serde::{Deserialize, Serialize};
use uuid::Uuid;
use sha2::{Sha256, Digest};
use crate::types::{ZIdentityId, ZTimestamp};

/// Authentication factor type
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum AuthFactor {
    /// Password hash (SHA-256)
    Password(Vec<u8>),
    /// Biometric token (fingerprint, face)
    Biometric(Vec<u8>),
    /// Hardware security key (FIDO2)
    HardwareKey(Vec<u8>),
    /// Quantum key distribution token
    QuantumKey(Vec<u8>),
    /// PIN code hash
    Pin(Vec<u8>),
}

/// Identity role within the Zenith ecosystem
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum IdentityRole {
    /// Standard user
    User,
    /// System service account
    Service,
    /// Administrator
    Admin,
    /// AI agent acting on behalf of a user
    Agent { principal: ZIdentityId },
    /// Guest (limited capabilities)
    Guest,
}

/// A Zenith identity — the persistent computational self
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZenithIdentity {
    /// Unique identity ID
    pub id: ZIdentityId,
    /// Display name
    pub display_name: String,
    /// Email address (primary identifier)
    pub email: String,
    /// Identity role
    pub role: IdentityRole,
    /// Authentication factors
    pub auth_factors: Vec<AuthFactor>,
    /// Whether this identity is active
    pub active: bool,
    /// Creation timestamp
    pub created_at: ZTimestamp,
    /// Last login timestamp
    pub last_login: Option<ZTimestamp>,
    /// Associated Microsoft account ID (for Windows domain integration)
    pub microsoft_account_id: Option<String>,
    /// Associated Google account ID (for Android domain integration)
    pub google_account_id: Option<String>,
    /// Quantum public key (for QKD sessions)
    pub quantum_public_key: Option<Vec<u8>>,
    /// Metadata
    pub metadata: std::collections::HashMap<String, String>,
}

impl ZenithIdentity {
    /// Create a new user identity
    pub fn new(display_name: impl Into<String>, email: impl Into<String>) -> Self {
        let now = ZTimestamp(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_micros() as i64,
        );
        Self {
            id: Uuid::new_v4(),
            display_name: display_name.into(),
            email: email.into(),
            role: IdentityRole::User,
            auth_factors: Vec::new(),
            active: true,
            created_at: now,
            last_login: None,
            microsoft_account_id: None,
            google_account_id: None,
            quantum_public_key: None,
            metadata: std::collections::HashMap::new(),
        }
    }

    /// Add a password authentication factor
    pub fn set_password(&mut self, password: &str) {
        let mut hasher = Sha256::new();
        hasher.update(password.as_bytes());
        let hash = hasher.finalize().to_vec();
        self.auth_factors.retain(|f| !matches!(f, AuthFactor::Password(_)));
        self.auth_factors.push(AuthFactor::Password(hash));
    }

    /// Verify a password
    pub fn verify_password(&self, password: &str) -> bool {
        let mut hasher = Sha256::new();
        hasher.update(password.as_bytes());
        let hash = hasher.finalize().to_vec();
        self.auth_factors.iter().any(|f| {
            if let AuthFactor::Password(stored) = f {
                stored == &hash
            } else {
                false
            }
        })
    }

    /// Record a login event
    pub fn record_login(&mut self) {
        self.last_login = Some(ZTimestamp(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_micros() as i64,
        ));
    }

    /// Deactivate this identity
    pub fn deactivate(&mut self) {
        self.active = false;
    }

    /// Link a Microsoft account
    pub fn link_microsoft(&mut self, account_id: impl Into<String>) {
        self.microsoft_account_id = Some(account_id.into());
    }

    /// Link a Google account
    pub fn link_google(&mut self, account_id: impl Into<String>) {
        self.google_account_id = Some(account_id.into());
    }

    /// Set quantum public key
    pub fn set_quantum_key(&mut self, key: Vec<u8>) {
        self.quantum_public_key = Some(key);
    }

    /// Whether this identity has quantum authentication capability
    pub fn is_quantum_capable(&self) -> bool {
        self.quantum_public_key.is_some()
    }
}

/// Identity registry
#[derive(Debug, Default)]
pub struct IdentityRegistry {
    identities: std::collections::HashMap<ZIdentityId, ZenithIdentity>,
    email_index: std::collections::HashMap<String, ZIdentityId>,
}

impl IdentityRegistry {
    /// Create a new registry
    pub fn new() -> Self {
        Self::default()
    }

    /// Register a new identity
    pub fn register(&mut self, identity: ZenithIdentity) -> ZIdentityId {
        let id = identity.id;
        self.email_index.insert(identity.email.clone(), id);
        self.identities.insert(id, identity);
        id
    }

    /// Look up by ID
    pub fn get(&self, id: &ZIdentityId) -> Option<&ZenithIdentity> {
        self.identities.get(id)
    }

    /// Look up by email
    pub fn get_by_email(&self, email: &str) -> Option<&ZenithIdentity> {
        self.email_index
            .get(email)
            .and_then(|id| self.identities.get(id))
    }

    /// Authenticate by email + password
    pub fn authenticate(&self, email: &str, password: &str) -> Option<&ZenithIdentity> {
        let identity = self.get_by_email(email)?;
        if identity.active && identity.verify_password(password) {
            Some(identity)
        } else {
            None
        }
    }

    /// Total identity count
    pub fn count(&self) -> usize {
        self.identities.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identity_password_auth() {
        let mut identity = ZenithIdentity::new("Alice", "alice@zenith.os");
        identity.set_password("secure-pass-123");
        assert!(identity.verify_password("secure-pass-123"));
        assert!(!identity.verify_password("wrong-pass"));
    }

    #[test]
    fn identity_registry_lookup() {
        let mut registry = IdentityRegistry::new();
        let mut id = ZenithIdentity::new("Bob", "bob@zenith.os");
        id.set_password("bob-pass");
        registry.register(id);
        let found = registry.authenticate("bob@zenith.os", "bob-pass");
        assert!(found.is_some());
        assert_eq!(found.unwrap().display_name, "Bob");
    }

    #[test]
    fn identity_quantum_capability() {
        let mut identity = ZenithIdentity::new("Quantum User", "q@zenith.os");
        assert!(!identity.is_quantum_capable());
        identity.set_quantum_key(vec![0u8; 32]);
        assert!(identity.is_quantum_capable());
    }
}