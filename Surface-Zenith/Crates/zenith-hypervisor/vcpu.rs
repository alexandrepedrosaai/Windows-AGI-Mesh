//! # Virtual CPU (vCPU) Model
//!
//! Each domain container has one or more vCPUs that are scheduled
//! by the Zenith Hypervisor Layer onto physical CPU cores.

use serde::{Deserialize, Serialize};
use zenith_abi::domain::Domain;
use crate::error::ZhlError;

/// vCPU state
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum VCpuState {
    /// vCPU is uninitialized
    Uninitialized,
    /// vCPU is running (executing guest code)
    Running,
    /// vCPU is paused (halted by hypervisor)
    Paused,
    /// vCPU is blocked (waiting for I/O or event)
    Blocked,
    /// vCPU is in a hypercall (executing hypervisor code)
    Hypercall,
    /// vCPU has been halted permanently
    Halted,
}

/// Simulated CPU register state (ARM64)
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct RegisterState {
    /// General-purpose registers x0–x30
    pub gpr: [u64; 31],
    /// Stack pointer
    pub sp: u64,
    /// Program counter
    pub pc: u64,
    /// Process state register (PSTATE)
    pub pstate: u64,
    /// Exception Link Register EL1
    pub elr_el1: u64,
    /// Saved Program Status Register EL1
    pub spsr_el1: u64,
    /// Fault Address Register EL1
    pub far_el1: u64,
    /// Exception Syndrome Register EL1
    pub esr_el1: u64,
    /// Translation Table Base Register 0
    pub ttbr0_el1: u64,
    /// Translation Table Base Register 1
    pub ttbr1_el1: u64,
    /// System Control Register EL1
    pub sctlr_el1: u64,
    /// Vector Base Address Register EL1
    pub vbar_el1: u64,
    /// NEON/SIMD registers (32 × 128-bit)
    pub simd: [[u64; 2]; 32],
}

impl RegisterState {
    /// Create a zeroed register state
    pub fn new() -> Self {
        Self::default()
    }

    /// Set the program counter
    pub fn set_pc(&mut self, pc: u64) {
        self.pc = pc;
    }

    /// Set the stack pointer
    pub fn set_sp(&mut self, sp: u64) {
        self.sp = sp;
    }

    /// Set a general-purpose register
    pub fn set_gpr(&mut self, reg: usize, value: u64) {
        if reg < 31 {
            self.gpr[reg] = value;
        }
    }

    /// Get a general-purpose register
    pub fn get_gpr(&self, reg: usize) -> u64 {
        if reg < 31 { self.gpr[reg] } else { 0 }
    }

    /// Serialize to bytes for snapshot
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::with_capacity(std::mem::size_of::<RegisterState>());
        for &r in &self.gpr { bytes.extend_from_slice(&r.to_le_bytes()); }
        bytes.extend_from_slice(&self.sp.to_le_bytes());
        bytes.extend_from_slice(&self.pc.to_le_bytes());
        bytes.extend_from_slice(&self.pstate.to_le_bytes());
        bytes.extend_from_slice(&self.elr_el1.to_le_bytes());
        bytes.extend_from_slice(&self.spsr_el1.to_le_bytes());
        bytes.extend_from_slice(&self.far_el1.to_le_bytes());
        bytes.extend_from_slice(&self.esr_el1.to_le_bytes());
        bytes.extend_from_slice(&self.ttbr0_el1.to_le_bytes());
        bytes.extend_from_slice(&self.ttbr1_el1.to_le_bytes());
        bytes.extend_from_slice(&self.sctlr_el1.to_le_bytes());
        bytes.extend_from_slice(&self.vbar_el1.to_le_bytes());
        for pair in &self.simd {
            bytes.extend_from_slice(&pair[0].to_le_bytes());
            bytes.extend_from_slice(&pair[1].to_le_bytes());
        }
        bytes
    }
}

/// vCPU performance counters
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct VCpuCounters {
    /// Total instructions retired
    pub instructions_retired: u64,
    /// Total cycles elapsed
    pub cycles: u64,
    /// Cache misses (L1)
    pub l1_cache_misses: u64,
    /// Cache misses (L2)
    pub l2_cache_misses: u64,
    /// Branch mispredictions
    pub branch_mispredictions: u64,
    /// TLB misses
    pub tlb_misses: u64,
    /// Number of hypercalls issued
    pub hypercalls: u64,
    /// Number of VM exits
    pub vm_exits: u64,
    /// Time spent in guest mode (nanoseconds)
    pub guest_time_ns: u64,
    /// Time spent in hypervisor mode (nanoseconds)
    pub hypervisor_time_ns: u64,
}

impl VCpuCounters {
    /// Instructions per cycle (IPC)
    pub fn ipc(&self) -> f64 {
        if self.cycles == 0 { return 0.0; }
        self.instructions_retired as f64 / self.cycles as f64
    }

    /// Hypervisor overhead ratio (0.0–1.0)
    pub fn hypervisor_overhead(&self) -> f64 {
        let total = self.guest_time_ns + self.hypervisor_time_ns;
        if total == 0 { return 0.0; }
        self.hypervisor_time_ns as f64 / total as f64
    }
}

/// A virtual CPU managed by the Zenith Hypervisor Layer
#[derive(Debug)]
pub struct VCpu {
    /// vCPU index within the container (0-based)
    pub index: u32,
    /// Domain this vCPU belongs to
    pub domain: Domain,
    /// Current state
    pub state: VCpuState,
    /// Physical CPU core this vCPU is pinned to (None = floating)
    pub pinned_core: Option<u32>,
    /// Current register state
    pub registers: RegisterState,
    /// Performance counters
    pub counters: VCpuCounters,
    /// Current scheduling priority (0–255)
    pub priority: u8,
    /// Whether this vCPU is in a real-time scheduling class
    pub realtime: bool,
    /// Time slice remaining in nanoseconds
    pub time_slice_ns: u64,
}

impl VCpu {
    /// Create a new vCPU
    pub fn new(index: u32, domain: Domain) -> Self {
        let realtime = domain == Domain::RealTime;
        Self {
            index,
            domain,
            state: VCpuState::Uninitialized,
            pinned_core: None,
            registers: RegisterState::new(),
            counters: VCpuCounters::default(),
            priority: 128,
            realtime,
            time_slice_ns: 10_000_000, // 10ms default time slice
        }
    }

    /// Initialize the vCPU (set up initial register state)
    pub fn initialize(&mut self) -> Result<(), ZhlError> {
        if self.state != VCpuState::Uninitialized {
            return Err(ZhlError::VCpuAlreadyInitialized { index: self.index });
        }
        // Set up initial ARM64 state
        self.registers.pc = 0xFFFF_0000_0000_0000; // Kernel entry point
        self.registers.sp = 0xFFFF_0000_0001_0000; // Initial stack
        self.registers.pstate = 0x3C5; // EL1h, DAIF masked
        self.state = VCpuState::Running;
        tracing::debug!("vCPU {} initialized for domain {:?}", self.index, self.domain);
        Ok(())
    }

    /// Pause this vCPU
    pub fn pause(&mut self) -> Result<(), ZhlError> {
        if self.state != VCpuState::Running {
            return Err(ZhlError::VCpuNotRunning { index: self.index });
        }
        self.state = VCpuState::Paused;
        Ok(())
    }

    /// Resume this vCPU
    pub fn resume(&mut self) -> Result<(), ZhlError> {
        if !matches!(self.state, VCpuState::Paused | VCpuState::Blocked) {
            return Err(ZhlError::InvalidVCpuState {
                index: self.index,
                state: format!("{:?}", self.state),
            });
        }
        self.state = VCpuState::Running;
        Ok(())
    }

    /// Halt this vCPU permanently
    pub fn halt(&mut self) {
        self.state = VCpuState::Halted;
    }

    /// Pin this vCPU to a physical core
    pub fn pin_to_core(&mut self, core: u32) {
        self.pinned_core = Some(core);
    }

    /// Unpin this vCPU (allow floating scheduling)
    pub fn unpin(&mut self) {
        self.pinned_core = None;
    }

    /// Record a VM exit event
    pub fn record_vm_exit(&mut self, guest_time_ns: u64, hypervisor_time_ns: u64) {
        self.counters.vm_exits += 1;
        self.counters.guest_time_ns += guest_time_ns;
        self.counters.hypervisor_time_ns += hypervisor_time_ns;
    }

    /// Record a hypercall
    pub fn record_hypercall(&mut self) {
        self.counters.hypercalls += 1;
    }

    /// Snapshot the vCPU state
    pub fn snapshot(&self) -> VCpuSnapshot {
        VCpuSnapshot {
            index:     self.index,
            state:     self.state.clone(),
            registers: self.registers.clone(),
            counters:  self.counters.clone(),
            priority:  self.priority,
        }
    }

    /// Restore from a snapshot
    pub fn restore(&mut self, snapshot: VCpuSnapshot) -> Result<(), ZhlError> {
        if snapshot.index != self.index {
            return Err(ZhlError::SnapshotIndexMismatch {
                expected: self.index,
                got: snapshot.index,
            });
        }
        self.registers = snapshot.registers;
        self.counters  = snapshot.counters;
        self.priority  = snapshot.priority;
        self.state     = VCpuState::Paused; // Start paused after restore
        Ok(())
    }

    /// Whether this vCPU is currently executing
    pub fn is_running(&self) -> bool {
        self.state == VCpuState::Running
    }

    /// CPU usage percentage (simplified)
    pub fn cpu_usage_pct(&self) -> f64 {
        let total = self.counters.guest_time_ns + self.counters.hypervisor_time_ns;
        if total == 0 { return 0.0; }
        (self.counters.guest_time_ns as f64 / total as f64) * 100.0
    }
}

/// Snapshot of a vCPU state for migration/checkpoint
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VCpuSnapshot {
    pub index:     u32,
    pub state:     VCpuState,
    pub registers: RegisterState,
    pub counters:  VCpuCounters,
    pub priority:  u8,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn vcpu_lifecycle() {
        let mut vcpu = VCpu::new(0, Domain::Windows);
        assert_eq!(vcpu.state, VCpuState::Uninitialized);
        vcpu.initialize().unwrap();
        assert_eq!(vcpu.state, VCpuState::Running);
        vcpu.pause().unwrap();
        assert_eq!(vcpu.state, VCpuState::Paused);
        vcpu.resume().unwrap();
        assert_eq!(vcpu.state, VCpuState::Running);
        vcpu.halt();
        assert_eq!(vcpu.state, VCpuState::Halted);
    }

    #[test]
    fn vcpu_double_init_fails() {
        let mut vcpu = VCpu::new(0, Domain::Android);
        vcpu.initialize().unwrap();
        assert!(vcpu.initialize().is_err());
    }

    #[test]
    fn vcpu_snapshot_restore() {
        let mut vcpu = VCpu::new(0, Domain::AI);
        vcpu.initialize().unwrap();
        vcpu.registers.set_gpr(0, 0xDEADBEEF);
        let snap = vcpu.snapshot();
        let mut vcpu2 = VCpu::new(0, Domain::AI);
        vcpu2.initialize().unwrap();
        vcpu2.restore(snap).unwrap();
        assert_eq!(vcpu2.registers.get_gpr(0), 0xDEADBEEF);
        assert_eq!(vcpu2.state, VCpuState::Paused);
    }

    #[test]
    fn register_state_serialization() {
        let mut regs = RegisterState::new();
        regs.set_pc(0x1234_5678);
        regs.set_sp(0xFFFF_0000);
        regs.set_gpr(1, 42);
        let bytes = regs.to_bytes();
        assert!(!bytes.is_empty());
    }

    #[test]
    fn vcpu_counters_ipc() {
        let mut counters = VCpuCounters::default();
        counters.instructions_retired = 1_000_000;
        counters.cycles = 500_000;
        assert!((counters.ipc() - 2.0).abs() < 0.001);
    }

    #[test]
    fn realtime_vcpu_flag() {
        let vcpu = VCpu::new(0, Domain::RealTime);
        assert!(vcpu.realtime);
        let vcpu2 = VCpu::new(0, Domain::Windows);
        assert!(!vcpu2.realtime);
    }
}