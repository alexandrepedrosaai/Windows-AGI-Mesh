//! # Zenith Version Management

use serde::{Deserialize, Serialize};

/// Semantic version
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct SemVer {
    pub major: u32,
    pub minor: u32,
    pub patch: u32,
    pub pre: Option<String>,
}

impl SemVer {
    pub fn new(major: u32, minor: u32, patch: u32) -> Self {
        Self { major, minor, patch, pre: None }
    }
    pub fn with_pre(mut self, pre: impl Into<String>) -> Self {
        self.pre = Some(pre.into());
        self
    }
    pub fn is_compatible_with(&self, other: &SemVer) -> bool {
        self.major == other.major && self.minor >= other.minor
    }
}

impl std::fmt::Display for SemVer {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}.{}.{}", self.major, self.minor, self.patch)?;
        if let Some(ref pre) = self.pre {
            write!(f, "-{pre}")?;
        }
        Ok(())
    }
}

/// Zenith OS version constants
pub mod versions {
    use super::SemVer;
    pub fn zenith_os()  -> SemVer { SemVer::new(0, 1, 0).with_pre("alpha") }
    pub fn zenith_abi() -> SemVer { SemVer::new(0, 1, 0) }
    pub fn zenith_ipc() -> SemVer { SemVer::new(0, 3, 1) }
    pub fn zenith_kernel() -> SemVer { SemVer::new(0, 1, 0) }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn semver_compatibility() {
        let v010 = SemVer::new(0, 1, 0);
        let v011 = SemVer::new(0, 1, 1);
        let v020 = SemVer::new(0, 2, 0);
        assert!(v011.is_compatible_with(&v010));
        assert!(!v010.is_compatible_with(&v020));
    }
    #[test]
    fn semver_display() {
        let v = SemVer::new(1, 2, 3).with_pre("beta");
        assert_eq!(v.to_string(), "1.2.3-beta");
    }
}