//! # Windows Domain Runtime
//!
//! The Windows Runtime adapter bridges the Zenith Hypervisor Layer with
//! Win32, .NET, and Windows subsystems.
//!
//! ## Responsibilities
//!
//! - Managing Win32 process and thread lifecycle
//! - Routing COM/RPC calls → ZIB translation
//! - Managing Windows registry access
//! - Handling .NET CLR integration
//! - Managing Windows file system access
//! - Providing Windows API compatibility layer
//! - Managing Office runtime integration

use std::collections::HashMap;
use uuid::Uuid;
use serde::{Deserialize, Serialize};
use zenith_abi::domain::{Domain, DomainHealth};
use zenith_abi::task::{ZenithTask, TaskState};
use zenith_abi::types::{ZTaskId, ZSessionId};
use zenith_abi::contract::IZDomainRuntime;
use crate::error::RuntimeError;
use crate::metrics::DomainMetrics;
use crate::task_executor::TaskExecutor;

// ---------------------------------------------------------------------------
// Win32 process model
// ---------------------------------------------------------------------------

/// Win32 process record
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Win32Process {
    pub pid:          u32,
    pub name:         String,
    pub executable:   String,
    pub state:        ProcessState,
    pub memory_mb:    u32,
    pub cpu_pct:      f32,
    pub thread_count: u32,
    pub handle_count: u32,
    pub session_id:   u32,
    pub integrity:    IntegrityLevel,
    pub started_at:   std::time::Instant,
}

impl Win32Process {
    pub fn new(pid: u32, name: impl Into<String>, executable: impl Into<String>) -> Self {
        Self {
            pid,
            name:         name.into(),
            executable:   executable.into(),
            state:        ProcessState::Running,
            memory_mb:    64,
            cpu_pct:      0.0,
            thread_count: 4,
            handle_count: 100,
            session_id:   1,
            integrity:    IntegrityLevel::Medium,
            started_at:   std::time::Instant::now(),
        }
    }

    pub fn uptime_s(&self) -> u64 { self.started_at.elapsed().as_secs() }
}

/// Win32 process state
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ProcessState {
    Running,
    Suspended,
    Terminated,
    Crashed { exit_code: u32 },
}

/// Windows integrity level
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum IntegrityLevel {
    Untrusted,
    Low,
    Medium,
    High,
    System,
    Protected,
}

// ---------------------------------------------------------------------------
// .NET CLR integration
// ---------------------------------------------------------------------------

/// .NET runtime version
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DotNetRuntime {
    pub version:      String,
    pub loaded:       bool,
    pub assemblies:   Vec<String>,
    pub gc_heap_mb:   u32,
    pub jit_enabled:  bool,
    pub tier_jit:     bool,
}

impl DotNetRuntime {
    pub fn new(version: impl Into<String>) -> Self {
        Self {
            version:     version.into(),
            loaded:      false,
            assemblies:  Vec::new(),
            gc_heap_mb:  256,
            jit_enabled: true,
            tier_jit:    true,
        }
    }

    pub fn load(&mut self) {
        self.loaded = true;
        self.assemblies.push("mscorlib".into());
        self.assemblies.push("System".into());
        self.assemblies.push("System.Core".into());
        self.assemblies.push("Microsoft.CSharp".into());
    }

    pub fn load_assembly(&mut self, name: impl Into<String>) {
        self.assemblies.push(name.into());
    }
}

// ---------------------------------------------------------------------------
// COM/RPC bridge
// ---------------------------------------------------------------------------

/// COM interface registration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComInterface {
    pub clsid:       String,
    pub iid:         String,
    pub name:        String,
    pub threading:   ComThreadingModel,
    pub registered:  bool,
}

/// COM threading model
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ComThreadingModel {
    Apartment,
    Free,
    Both,
    Neutral,
}

/// COM/RPC call record
#[derive(Debug, Clone)]
pub struct ComCall {
    pub id:        Uuid,
    pub clsid:     String,
    pub method:    String,
    pub args:      Vec<u8>,
    pub result:    Option<Vec<u8>>,
    pub duration_us: u64,
}

// ---------------------------------------------------------------------------
// Windows Registry
// ---------------------------------------------------------------------------

/// Registry hive
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum RegistryHive {
    LocalMachine,
    CurrentUser,
    ClassesRoot,
    Users,
    CurrentConfig,
}

/// Registry value type
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum RegistryValue {
    String(String),
    ExpandString(String),
    Binary(Vec<u8>),
    DWord(u32),
    QWord(u64),
    MultiString(Vec<String>),
}

/// Windows Registry (simplified in-memory implementation)
#[derive(Debug, Default)]
pub struct WindowsRegistry {
    keys: HashMap<String, HashMap<String, RegistryValue>>,
    read_count:  u64,
    write_count: u64,
}

impl WindowsRegistry {
    pub fn new() -> Self { Self::default() }

    pub fn set_value(&mut self, hive: &RegistryHive, key: &str, name: &str, value: RegistryValue) {
        let full_key = format!("{hive:?}\\{key}");
        self.keys.entry(full_key).or_default().insert(name.to_string(), value);
        self.write_count += 1;
    }

    pub fn get_value(&self, hive: &RegistryHive, key: &str, name: &str) -> Option<&RegistryValue> {
        let full_key = format!("{hive:?}\\{key}");
        self.keys.get(&full_key)?.get(name)
    }

    pub fn delete_key(&mut self, hive: &RegistryHive, key: &str) -> bool {
        let full_key = format!("{hive:?}\\{key}");
        self.keys.remove(&full_key).is_some()
    }

    pub fn key_count(&self) -> usize { self.keys.len() }
    pub fn read_count(&self) -> u64 { self.read_count }
    pub fn write_count(&self) -> u64 { self.write_count }
}

// ---------------------------------------------------------------------------
// Office Runtime
// ---------------------------------------------------------------------------

/// Office application type
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum OfficeApp {
    Word,
    Excel,
    PowerPoint,
    Outlook,
    OneNote,
    Teams,
    Visio,
}

impl OfficeApp {
    pub fn process_name(&self) -> &str {
        match self {
            OfficeApp::Word       => "WINWORD.EXE",
            OfficeApp::Excel      => "EXCEL.EXE",
            OfficeApp::PowerPoint => "POWERPNT.EXE",
            OfficeApp::Outlook    => "OUTLOOK.EXE",
            OfficeApp::OneNote    => "ONENOTE.EXE",
            OfficeApp::Teams      => "Teams.exe",
            OfficeApp::Visio      => "VISIO.EXE",
        }
    }
}

/// Office document session
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OfficeSession {
    pub id:       Uuid,
    pub app:      OfficeApp,
    pub document: String,
    pub pid:      u32,
    pub modified: bool,
    pub opened_at: std::time::Instant,
}

impl OfficeSession {
    pub fn new(app: OfficeApp, document: impl Into<String>, pid: u32) -> Self {
        Self {
            id:        Uuid::new_v4(),
            app,
            document:  document.into(),
            pid,
            modified:  false,
            opened_at: std::time::Instant::now(),
        }
    }
}

// ---------------------------------------------------------------------------
// Windows Runtime
// ---------------------------------------------------------------------------

/// The Windows Domain Runtime
#[derive(Debug)]
pub struct WindowsRuntime {
    health:          DomainHealth,
    processes:       HashMap<u32, Win32Process>,
    active_tasks:    HashMap<ZTaskId, ZenithTask>,
    dotnet:          DotNetRuntime,
    registry:        WindowsRegistry,
    com_interfaces:  Vec<ComInterface>,
    com_call_log:    Vec<ComCall>,
    office_sessions: Vec<OfficeSession>,
    metrics:         DomainMetrics,
    executor:        TaskExecutor,
    initialized:     bool,
    next_pid:        u32,
    windows_version: String,
    build_number:    u32,
}

impl WindowsRuntime {
    pub fn new() -> Self {
        Self {
            health:          DomainHealth::Initializing,
            processes:       HashMap::new(),
            active_tasks:    HashMap::new(),
            dotnet:          DotNetRuntime::new("9.0"),
            registry:        WindowsRegistry::new(),
            com_interfaces:  Vec::new(),
            com_call_log:    Vec::new(),
            office_sessions: Vec::new(),
            metrics:         DomainMetrics::new(Domain::Windows),
            executor:        TaskExecutor::new(Domain::Windows),
            initialized:     false,
            next_pid:        1000,
            windows_version: "Windows 11".into(),
            build_number:    26100,
        }
    }

    /// Spawn a Win32 process
    pub fn spawn_process(&mut self, name: impl Into<String>, executable: impl Into<String>) -> u32 {
        let pid = self.next_pid;
        self.next_pid += 1;
        let process = Win32Process::new(pid, name, executable);
        self.processes.insert(pid, process);
        self.metrics.record_event("process_spawned");
        pid
    }

    /// Terminate a process
    pub fn terminate_process(&mut self, pid: u32, exit_code: u32) -> bool {
        if let Some(process) = self.processes.get_mut(&pid) {
            process.state = ProcessState::Terminated;
            self.metrics.record_event("process_terminated");
            true
        } else {
            false
        }
    }

    /// Open an Office document
    pub fn open_office_document(&mut self, app: OfficeApp, document: impl Into<String>) -> Uuid {
        let pid = self.spawn_process(app.process_name(), app.process_name());
        let session = OfficeSession::new(app, document, pid);
        let id = session.id;
        self.office_sessions.push(session);
        self.metrics.record_event("office_document_opened");
        id
    }

    /// Close an Office session
    pub fn close_office_session(&mut self, id: &Uuid) -> bool {
        let before = self.office_sessions.len();
        self.office_sessions.retain(|s| &s.id != id);
        self.office_sessions.len() < before
    }

    /// Handle a COM call
    pub fn handle_com_call(&mut self, clsid: impl Into<String>, method: impl Into<String>, args: Vec<u8>) -> Vec<u8> {
        let call = ComCall {
            id:          Uuid::new_v4(),
            clsid:       clsid.into(),
            method:      method.into(),
            args,
            result:      None,
            duration_us: 100,
        };
        self.com_call_log.push(call);
        self.metrics.record_event("com_call");
        b"S_OK".to_vec()
    }

    /// Set a registry value
    pub fn set_registry(&mut self, hive: RegistryHive, key: &str, name: &str, value: RegistryValue) {
        self.registry.set_value(&hive, key, name, value);
    }

    /// Get a registry value
    pub fn get_registry(&self, hive: &RegistryHive, key: &str, name: &str) -> Option<&RegistryValue> {
        self.registry.get_value(hive, key, name)
    }

    /// Running process count
    pub fn running_process_count(&self) -> usize {
        self.processes.values().filter(|p| p.state == ProcessState::Running).count()
    }

    /// Active Office sessions
    pub fn office_session_count(&self) -> usize { self.office_sessions.len() }

    /// Windows version
    pub fn windows_version(&self) -> &str { &self.windows_version }

    /// Build number
    pub fn build_number(&self) -> u32 { self.build_number }

    /// .NET runtime reference
    pub fn dotnet(&self) -> &DotNetRuntime { &self.dotnet }

    /// Metrics
    pub fn metrics(&self) -> &DomainMetrics { &self.metrics }
}

impl IZDomainRuntime for WindowsRuntime {
    fn start(&mut self) -> zenith_abi::types::ZResult<()> {
        self.initialized = true;
        self.health = DomainHealth::Healthy;

        // Load .NET runtime
        self.dotnet.load();

        // Initialize system registry keys
        self.registry.set_value(
            &RegistryHive::LocalMachine,
            "SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion",
            "ProductName",
            RegistryValue::String("Windows 11".into()),
        );
        self.registry.set_value(
            &RegistryHive::LocalMachine,
            "SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion",
            "CurrentBuild",
            RegistryValue::String(self.build_number.to_string()),
        );

        // Spawn system processes
        self.spawn_process("System", "ntoskrnl.exe");
        self.spawn_process("smss.exe", "smss.exe");
        self.spawn_process("csrss.exe", "csrss.exe");
        self.spawn_process("winlogon.exe", "winlogon.exe");
        self.spawn_process("explorer.exe", "explorer.exe");
        self.spawn_process("svchost.exe", "svchost.exe");

        tracing::info!("Windows Runtime started ({} build {})", self.windows_version, self.build_number);
        Ok(())
    }

    fn stop(&mut self) -> zenith_abi::types::ZResult<()> {
        // Terminate all processes
        let pids: Vec<u32> = self.processes.keys().copied().collect();
        for pid in pids {
            self.terminate_process(pid, 0);
        }
        self.office_sessions.clear();
        self.health = DomainHealth::ShuttingDown;
        self.initialized = false;
        tracing::info!("Windows Runtime stopped");
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

    fn domain(&self) -> Domain { Domain::Windows }
}

impl Default for WindowsRuntime {
    fn default() -> Self { Self::new() }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn windows_runtime_start_stop() {
        let mut rt = WindowsRuntime::new();
        rt.start().unwrap();
        assert_eq!(rt.health(), DomainHealth::Healthy);
        assert!(rt.running_process_count() > 0); // System processes
        rt.stop().unwrap();
    }

    #[test]
    fn windows_spawn_terminate_process() {
        let mut rt = WindowsRuntime::new();
        rt.start().unwrap();
        let pid = rt.spawn_process("notepad.exe", "notepad.exe");
        assert!(rt.processes.contains_key(&pid));
        rt.terminate_process(pid, 0);
        assert_eq!(rt.processes[&pid].state, ProcessState::Terminated);
    }

    #[test]
    fn windows_office_sessions() {
        let mut rt = WindowsRuntime::new();
        rt.start().unwrap();
        let id = rt.open_office_document(OfficeApp::Excel, "Q4_Sales.xlsx");
        assert_eq!(rt.office_session_count(), 1);
        rt.close_office_session(&id);
        assert_eq!(rt.office_session_count(), 0);
    }

    #[test]
    fn windows_registry() {
        let mut rt = WindowsRuntime::new();
        rt.start().unwrap();
        rt.set_registry(
            RegistryHive::CurrentUser,
            "SOFTWARE\\Zenith\\Settings",
            "Theme",
            RegistryValue::String("Dark".into()),
        );
        let val = rt.get_registry(
            &RegistryHive::CurrentUser,
            "SOFTWARE\\Zenith\\Settings",
            "Theme",
        );
        assert!(val.is_some());
        if let Some(RegistryValue::String(s)) = val {
            assert_eq!(s, "Dark");
        }
    }

    #[test]
    fn windows_com_call() {
        let mut rt = WindowsRuntime::new();
        rt.start().unwrap();
        let result = rt.handle_com_call(
            "{00000000-0000-0000-C000-000000000046}",
            "QueryInterface",
            vec![],
        );
        assert_eq!(result, b"S_OK");
    }

    #[test]
    fn windows_dotnet_loaded() {
        let mut rt = WindowsRuntime::new();
        rt.start().unwrap();
        assert!(rt.dotnet().loaded);
        assert!(!rt.dotnet().assemblies.is_empty());
    }

    #[test]
    fn windows_domain_identity() {
        let rt = WindowsRuntime::new();
        assert_eq!(rt.domain(), Domain::Windows);
    }
}