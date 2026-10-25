//! # Fault Handler

use zenith_abi::domain::Domain;
use zenith_abi::types::ZDomainId;

/// Fault type
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FaultType {
    PageFault { va: u64, write: bool },
    GeneralProtectionFault { error_code: u64 },
    DivisionByZero,
    InvalidOpcode,
    StackOverflow,
    DoubleFault,
    MachineCheck,
    MemoryAccessViolation { from: Domain, to: Domain },
    QuotaExceeded { resource: String },
    HypercallError { number: u64, code: i64 },
}

/// A fault event
#[derive(Debug, Clone)]
pub struct FaultEvent {
    pub id:         uuid::Uuid,
    pub container:  ZDomainId,
    pub domain:     Domain,
    pub fault_type: FaultType,
    pub recoverable: bool,
    pub timestamp:  std::time::Instant,
}

/// Fault handler — processes and classifies faults from domain containers
#[derive(Debug, Default)]
pub struct FaultHandler {
    fault_log:       Vec<FaultEvent>,
    total_faults:    u64,
    recovered_faults: u64,
}

impl FaultHandler {
    pub fn new() -> Self { Self::default() }

    /// Handle a fault from a domain container
    pub fn handle(&mut self, container: ZDomainId, domain: Domain, fault: FaultType) -> bool {
        self.total_faults += 1;
        let recoverable = self.is_recoverable(&fault);

        let event = FaultEvent {
            id:         uuid::Uuid::new_v4(),
            container,
            domain,
            fault_type: fault,
            recoverable,
            timestamp:  std::time::Instant::now(),
        };

        tracing::warn!("Fault in container {}: {:?} (recoverable: {})",
            container, event.fault_type, recoverable);

        self.fault_log.push(event);
        if self.fault_log.len() > 10_000 {
            self.fault_log.drain(0..1000);
        }

        if recoverable {
            self.recovered_faults += 1;
        }

        recoverable
    }

    /// Whether a fault type is recoverable
    fn is_recoverable(&self, fault: &FaultType) -> bool {
        matches!(
            fault,
            FaultType::PageFault { .. }
                | FaultType::QuotaExceeded { .. }
                | FaultType::HypercallError { .. }
        )
    }

    /// Total faults handled
    pub fn total_faults(&self) -> u64 { self.total_faults }

    /// Fault recovery rate
    pub fn recovery_rate(&self) -> f64 {
        if self.total_faults == 0 { return 1.0; }
        self.recovered_faults as f64 / self.total_faults as f64
    }

    /// Recent fault events
    pub fn recent(&self, count: usize) -> &[FaultEvent] {
        let len = self.fault_log.len();
        &self.fault_log[len.saturating_sub(count)..]
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    #[test]
    fn fault_handler_page_fault_recoverable() {
        let mut handler = FaultHandler::new();
        let id = Uuid::new_v4();
        let recoverable = handler.handle(id, Domain::Windows,
            FaultType::PageFault { va: 0x1000, write: false });
        assert!(recoverable);
        assert_eq!(handler.total_faults(), 1);
    }

    #[test]
    fn fault_handler_double_fault_not_recoverable() {
        let mut handler = FaultHandler::new();
        let id = Uuid::new_v4();
        let recoverable = handler.handle(id, Domain::Android, FaultType::DoubleFault);
        assert!(!recoverable);
    }

    #[test]
    fn fault_recovery_rate() {
        let mut handler = FaultHandler::new();
        let id = Uuid::new_v4();
        handler.handle(id, Domain::AI, FaultType::PageFault { va: 0, write: false });
        handler.handle(id, Domain::AI, FaultType::DoubleFault);
        assert!((handler.recovery_rate() - 0.5).abs() < 0.01);
    }
}