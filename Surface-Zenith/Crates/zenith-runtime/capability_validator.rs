//! # Capability Validator
//!
//! Validates capability tokens for cross-domain operations within runtimes.

use std::collections::HashMap;
use uuid::Uuid;
use zenith_abi::domain::{Domain, ResourceClass, AccessLevel};
use zenith_abi::capability::CapabilityToken;
use zenith_abi::types::ZIdentityId;
use crate::error::RuntimeError;

/// Validation result
#[derive(Debug, Clone)]
pub struct ValidationResult {
    pub valid:    bool,
    pub reason:   Option<String>,
    pub identity: Option<ZIdentityId>,
}

impl ValidationResult {
    pub fn ok(identity: ZIdentityId) -> Self {
        Self { valid: true, reason: None, identity: Some(identity) }
    }
    pub fn denied(reason: impl Into<String>) -> Self {
        Self { valid: false, reason: Some(reason.into()), identity: None }
    }
}

/// The Capability Validator
#[derive(Debug, Default)]
pub struct CapabilityValidator {
    master_secret:    Vec<u8>,
    total_validated:  u64,
    total_denied:     u64,
    denial_reasons:   HashMap<String, u64>,
}

impl CapabilityValidator {
    pub fn new(master_secret: Vec<u8>) -> Self {
        Self { master_secret, ..Default::default() }
    }

    pub fn default_validator() -> Self {
        Self::new(b"zenith-master-secret-v1".to_vec())
    }

    /// Validate a capability token for a specific operation
    pub fn validate(
        &mut self,
        token: &CapabilityToken,
        resource: &ResourceClass,
        access: &AccessLevel,
        requesting_domain: &Domain,
    ) -> ValidationResult {
        self.total_validated += 1;

        // Check if token is valid (not revoked, not expired)
        if !token.is_valid() {
            let reason = if token.revoked { "token revoked" } else { "token expired" };
            self.record_denial(reason);
            return ValidationResult::denied(reason);
        }

        // Verify signature
        if !token.verify(&self.master_secret) {
            self.record_denial("invalid signature");
            return ValidationResult::denied("invalid signature");
        }

        // Check if requesting domain is in the audience
        if !token.audience.contains(requesting_domain) && !token.audience.is_empty() {
            self.record_denial("domain not in audience");
            return ValidationResult::denied(format!("domain {:?} not in token audience", requesting_domain));
        }

        // Check if token grants the requested permission
        if !token.grants(resource, access) {
            self.record_denial("permission denied");
            return ValidationResult::denied(format!("token does not grant {:?} access to {:?}", access, resource));
        }

        ValidationResult::ok(token.subject)
    }

    fn record_denial(&mut self, reason: &str) {
        self.total_denied += 1;
        *self.denial_reasons.entry(reason.to_string()).or_insert(0) += 1;
    }

    pub fn total_validated(&self) -> u64 { self.total_validated }
    pub fn total_denied(&self) -> u64 { self.total_denied }
    pub fn denial_rate(&self) -> f64 {
        if self.total_validated == 0 { return 0.0; }
        self.total_denied as f64 / self.total_validated as f64
    }
    pub fn top_denial_reason(&self) -> Option<(&str, u64)> {
        self.denial_reasons.iter()
            .max_by_key(|(_, &count)| count)
            .map(|(reason, &count)| (reason.as_str(), count))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use zenith_abi::capability::{Permission, CapabilityToken};

    fn make_token(resource: ResourceClass, access: AccessLevel) -> CapabilityToken {
        let subject  = Uuid::new_v4();
        let session  = Uuid::new_v4();
        let mut token = CapabilityToken::new(
            subject, session,
            Domain::Windows,
            vec![Domain::Android, Domain::AI],
            vec![Permission { resource, access, scope: None }],
            Some(3600),
        );
        token.sign(b"zenith-master-secret-v1");
        token
    }

    #[test]
    fn validator_valid_token() {
        let mut validator = CapabilityValidator::default_validator();
        let token = make_token(ResourceClass::Files, AccessLevel::ReadWrite);
        let result = validator.validate(&token, &ResourceClass::Files, &AccessLevel::Read, &Domain::Android);
        assert!(result.valid);
    }

    #[test]
    fn validator_wrong_domain() {
        let mut validator = CapabilityValidator::default_validator();
        let token = make_token(ResourceClass::Files, AccessLevel::ReadWrite);
        // Quantum domain is not in audience
        let result = validator.validate(&token, &ResourceClass::Files, &AccessLevel::Read, &Domain::Quantum);
        assert!(!result.valid);
    }

    #[test]
    fn validator_wrong_resource() {
        let mut validator = CapabilityValidator::default_validator();
        let token = make_token(ResourceClass::Files, AccessLevel::ReadWrite);
        let result = validator.validate(&token, &ResourceClass::Camera, &AccessLevel::Read, &Domain::Android);
        assert!(!result.valid);
    }

    #[test]
    fn validator_revoked_token() {
        let mut validator = CapabilityValidator::default_validator();
        let mut token = make_token(ResourceClass::Files, AccessLevel::ReadWrite);
        token.revoke();
        let result = validator.validate(&token, &ResourceClass::Files, &AccessLevel::Read, &Domain::Android);
        assert!(!result.valid);
        assert_eq!(validator.total_denied(), 1);
    }

    #[test]
    fn validator_metrics() {
        let mut validator = CapabilityValidator::default_validator();
        let token = make_token(ResourceClass::Files, AccessLevel::ReadWrite);
        validator.validate(&token, &ResourceClass::Files, &AccessLevel::Read, &Domain::Android);
        validator.validate(&token, &ResourceClass::Camera, &AccessLevel::Read, &Domain::Android);
        assert_eq!(validator.total_validated(), 2);
        assert_eq!(validator.total_denied(), 1);
        assert!((validator.denial_rate() - 0.5).abs() < 0.01);
    }
}