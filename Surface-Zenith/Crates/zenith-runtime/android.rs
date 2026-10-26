//! # Android Domain Runtime
//!
//! The Android Runtime adapter bridges the Zenith Hypervisor Layer with
//! the Android Runtime (ART) and Android framework subsystems.
//!
//! ## Responsibilities
//!
//! - Managing Android app lifecycle (Activity, Service, BroadcastReceiver)
//! - Routing telephony, SMS, and cellular data
//! - Managing camera, microphone, and sensor access
//! - Handling Android-specific IPC (Binder → ZIB translation)
//! - Managing Android permissions → Zenith capability tokens
//! - Providing Android API compatibility layer

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
// Android app component types
// ---------------------------------------------------------------------------

/// Android app component type
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum AndroidComponent {
    Activity { package: String, class: String },
    Service  { package: String, class: String, foreground: bool },
    BroadcastReceiver { package: String, action: String },
    ContentProvider { package: String, authority: String },
}

impl AndroidComponent {
    pub fn package(&self) -> &str {
        match self {
            AndroidComponent::Activity { package, .. }          => package,
            AndroidComponent::Service { package, .. }           => package,
            AndroidComponent::BroadcastReceiver { package, .. } => package,
            AndroidComponent::ContentProvider { package, .. }   => package,
        }
    }
}

/// Android app lifecycle state
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum AppLifecycleState {
    NotInstalled,
    Installed,
    Running,
    Paused,
    Stopped,
    Destroyed,
}

/// Android app record
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AndroidApp {
    pub package:    String,
    pub version:    String,
    pub state:      AppLifecycleState,
    pub pid:        Option<u32>,
    pub uid:        u32,
    pub components: Vec<AndroidComponent>,
    pub permissions: Vec<String>,
    pub memory_mb:  u32,
    pub cpu_pct:    f32,
}

impl AndroidApp {
    pub fn new(package: impl Into<String>, version: impl Into<String>) -> Self {
        Self {
            package:     package.into(),
            version:     version.into(),
            state:       AppLifecycleState::Installed,
            pid:         None,
            uid:         10000 + rand::random::<u32>() % 10000,
            components:  Vec::new(),
            permissions: Vec::new(),
            memory_mb:   0,
            cpu_pct:     0.0,
        }
    }

    pub fn is_running(&self) -> bool {
        self.state == AppLifecycleState::Running
    }
}

// ---------------------------------------------------------------------------
// Binder IPC bridge
// ---------------------------------------------------------------------------

/// Binder transaction (Android IPC → ZIB translation)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BinderTransaction {
    pub id:          Uuid,
    pub from_pid:    u32,
    pub to_service:  String,
    pub method:      String,
    pub payload:     Vec<u8>,
    pub one_way:     bool,
    pub timestamp:   std::time::Instant,
}

impl BinderTransaction {
    pub fn new(from_pid: u32, to_service: impl Into<String>, method: impl Into<String>, payload: Vec<u8>) -> Self {
        Self {
            id:         Uuid::new_v4(),
            from_pid,
            to_service: to_service.into(),
            method:     method.into(),
            payload,
            one_way:    false,
            timestamp:  std::time::Instant::now(),
        }
    }
}

// ---------------------------------------------------------------------------
// Telephony state
// ---------------------------------------------------------------------------

/// Telephony call state
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum CallState {
    Idle,
    Ringing { number: String },
    Active  { number: String, duration_s: u32 },
    Holding { number: String },
    Ended,
}

/// Telephony manager
#[derive(Debug, Default)]
pub struct TelephonyManager {
    pub call_state:    CallState,
    pub signal_bars:   u8,
    pub network_type:  String,
    pub carrier:       String,
    pub roaming:       bool,
    pub data_enabled:  bool,
    pub calls_made:    u64,
    pub calls_received: u64,
}

impl TelephonyManager {
    pub fn new() -> Self {
        Self {
            call_state:   CallState::Idle,
            signal_bars:  4,
            network_type: "5G".into(),
            carrier:      "Zenith Mobile".into(),
            roaming:      false,
            data_enabled: true,
            ..Default::default()
        }
    }

    pub fn answer_call(&mut self, number: impl Into<String>) {
        self.call_state = CallState::Active { number: number.into(), duration_s: 0 };
        self.calls_received += 1;
    }

    pub fn make_call(&mut self, number: impl Into<String>) {
        self.call_state = CallState::Active { number: number.into(), duration_s: 0 };
        self.calls_made += 1;
    }

    pub fn end_call(&mut self) {
        self.call_state = CallState::Ended;
    }

    pub fn is_in_call(&self) -> bool {
        matches!(self.call_state, CallState::Active { .. } | CallState::Ringing { .. })
    }
}

// ---------------------------------------------------------------------------
// Sensor manager
// ---------------------------------------------------------------------------

/// Sensor reading
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SensorReading {
    pub sensor_type: String,
    pub values:      Vec<f32>,
    pub accuracy:    u8,
    pub timestamp:   std::time::Instant,
}

/// Android sensor manager
#[derive(Debug, Default)]
pub struct SensorManager {
    pub readings:        HashMap<String, SensorReading>,
    pub active_sensors:  Vec<String>,
    pub total_readings:  u64,
}

impl SensorManager {
    pub fn new() -> Self { Self::default() }

    pub fn update_reading(&mut self, sensor_type: impl Into<String>, values: Vec<f32>) {
        let sensor_type = sensor_type.into();
        self.readings.insert(sensor_type.clone(), SensorReading {
            sensor_type: sensor_type.clone(),
            values,
            accuracy: 3,
            timestamp: std::time::Instant::now(),
        });
        self.total_readings += 1;
    }

    pub fn get_reading(&self, sensor_type: &str) -> Option<&SensorReading> {
        self.readings.get(sensor_type)
    }

    pub fn activate_sensor(&mut self, sensor_type: impl Into<String>) {
        let s = sensor_type.into();
        if !self.active_sensors.contains(&s) {
            self.active_sensors.push(s);
        }
    }

    pub fn deactivate_sensor(&mut self, sensor_type: &str) {
        self.active_sensors.retain(|s| s != sensor_type);
    }

    pub fn active_count(&self) -> usize { self.active_sensors.len() }
}

// ---------------------------------------------------------------------------
// Android Runtime
// ---------------------------------------------------------------------------

/// The Android Domain Runtime
///
/// Manages all Android subsystems and provides the IZDomainRuntime interface
/// to the Zenith Hypervisor Layer.
#[derive(Debug)]
pub struct AndroidRuntime {
    /// Runtime health state
    health:          DomainHealth,
    /// Installed and running apps
    apps:            HashMap<String, AndroidApp>,
    /// Active tasks
    active_tasks:    HashMap<ZTaskId, ZenithTask>,
    /// Telephony manager
    telephony:       TelephonyManager,
    /// Sensor manager
    sensors:         SensorManager,
    /// Binder transaction log
    binder_log:      Vec<BinderTransaction>,
    /// Runtime metrics
    metrics:         DomainMetrics,
    /// Task executor
    executor:        TaskExecutor,
    /// Whether the runtime is initialized
    initialized:     bool,
    /// Hinge angle (for form factor detection)
    hinge_angle:     f64,
    /// Current form factor
    form_factor:     String,
    /// ART heap size in MB
    art_heap_mb:     u32,
    /// Dalvik/ART JIT compilation enabled
    jit_enabled:     bool,
    /// Android API level
    api_level:       u32,
}

impl AndroidRuntime {
    /// Create a new Android Runtime
    pub fn new() -> Self {
        Self {
            health:       DomainHealth::Initializing,
            apps:         HashMap::new(),
            active_tasks: HashMap::new(),
            telephony:    TelephonyManager::new(),
            sensors:      SensorManager::new(),
            binder_log:   Vec::new(),
            metrics:      DomainMetrics::new(Domain::Android),
            executor:     TaskExecutor::new(Domain::Android),
            initialized:  false,
            hinge_angle:  0.0,
            form_factor:  "phone_folded".into(),
            art_heap_mb:  512,
            jit_enabled:  true,
            api_level:    35, // Android 15
        }
    }

    /// Install an app
    pub fn install_app(&mut self, app: AndroidApp) {
        self.apps.insert(app.package.clone(), app);
        self.metrics.record_event("app_installed");
    }

    /// Launch an app
    pub fn launch_app(&mut self, package: &str) -> Result<u32, RuntimeError> {
        let app = self.apps.get_mut(package)
            .ok_or_else(|| RuntimeError::AppNotFound { package: package.to_string() })?;

        if app.is_running() {
            return Ok(app.pid.unwrap_or(0));
        }

        let pid = 1000 + self.apps.len() as u32;
        app.state = AppLifecycleState::Running;
        app.pid   = Some(pid);
        self.metrics.record_event("app_launched");
        tracing::info!("Android app launched: {} (PID {})", package, pid);
        Ok(pid)
    }

    /// Stop an app
    pub fn stop_app(&mut self, package: &str) -> bool {
        if let Some(app) = self.apps.get_mut(package) {
            app.state = AppLifecycleState::Stopped;
            app.pid   = None;
            self.metrics.record_event("app_stopped");
            true
        } else {
            false
        }
    }

    /// Handle a Binder transaction
    pub fn handle_binder(&mut self, tx: BinderTransaction) -> Vec<u8> {
        self.binder_log.push(tx.clone());
        if self.binder_log.len() > 10_000 {
            self.binder_log.drain(0..1000);
        }
        self.metrics.record_event("binder_transaction");
        // Simulate response
        format!("{{\"result\":\"ok\",\"method\":\"{}\"}}", tx.method).into_bytes()
    }

    /// Update hinge angle (triggers form factor adaptation)
    pub fn update_hinge_angle(&mut self, angle: f64) {
        self.hinge_angle = angle;
        self.form_factor = if angle < 10.0 {
            "phone_folded".into()
        } else if angle < 160.0 {
            "tablet_unfolded".into()
        } else {
            "flat".into()
        };
        self.metrics.record_event("hinge_angle_changed");
    }

    /// Get running apps
    pub fn running_apps(&self) -> Vec<&AndroidApp> {
        self.apps.values().filter(|a| a.is_running()).collect()
    }

    /// Total installed apps
    pub fn installed_app_count(&self) -> usize { self.apps.len() }

    /// Running app count
    pub fn running_app_count(&self) -> usize { self.running_apps().len() }

    /// Telephony manager reference
    pub fn telephony(&self) -> &TelephonyManager { &self.telephony }

    /// Mutable telephony manager
    pub fn telephony_mut(&mut self) -> &mut TelephonyManager { &mut self.telephony }

    /// Sensor manager reference
    pub fn sensors(&self) -> &SensorManager { &self.sensors }

    /// Mutable sensor manager
    pub fn sensors_mut(&mut self) -> &mut SensorManager { &mut self.sensors }

    /// Runtime metrics
    pub fn metrics(&self) -> &DomainMetrics { &self.metrics }

    /// Current hinge angle
    pub fn hinge_angle(&self) -> f64 { self.hinge_angle }

    /// Current form factor
    pub fn form_factor(&self) -> &str { &self.form_factor }

    /// Android API level
    pub fn api_level(&self) -> u32 { self.api_level }
}

impl IZDomainRuntime for AndroidRuntime {
    fn start(&mut self) -> zenith_abi::types::ZResult<()> {
        self.initialized = true;
        self.health = DomainHealth::Healthy;

        // Initialize default sensors
        self.sensors.activate_sensor("accelerometer");
        self.sensors.activate_sensor("gyroscope");
        self.sensors.activate_sensor("magnetometer");
        self.sensors.activate_sensor("barometer");
        self.sensors.activate_sensor("proximity");
        self.sensors.activate_sensor("ambient_light");

        // Simulate initial sensor readings
        self.sensors.update_reading("accelerometer", vec![0.0, 0.0, 9.81]);
        self.sensors.update_reading("gyroscope",     vec![0.0, 0.0, 0.0]);
        self.sensors.update_reading("magnetometer",  vec![25.0, -10.0, 40.0]);

        tracing::info!("Android Runtime started (API level {})", self.api_level);
        Ok(())
    }

    fn stop(&mut self) -> zenith_abi::types::ZResult<()> {
        // Stop all running apps
        let packages: Vec<String> = self.apps.keys().cloned().collect();
        for pkg in packages {
            self.stop_app(&pkg);
        }
        self.health = DomainHealth::ShuttingDown;
        self.initialized = false;
        tracing::info!("Android Runtime stopped");
        Ok(())
    }

    fn health(&self) -> DomainHealth {
        self.health.clone()
    }

    fn accept_task(&mut self, mut task: ZenithTask, snapshot: &[u8]) -> zenith_abi::types::ZResult<()> {
        task.resume();
        self.active_tasks.insert(task.id, task);
        self.metrics.record_task_accepted();
        Ok(())
    }

    fn snapshot_all(&mut self) -> zenith_abi::types::ZResult<Vec<(ZTaskId, Vec<u8>)>> {
        let snapshots: Vec<(ZTaskId, Vec<u8>)> = self.active_tasks.iter()
            .map(|(&id, task)| {
                let snapshot = serde_json::to_vec(task).unwrap_or_default();
                (id, snapshot)
            })
            .collect();
        Ok(snapshots)
    }

    fn domain(&self) -> Domain {
        Domain::Android
    }
}

impl Default for AndroidRuntime {
    fn default() -> Self { Self::new() }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn android_runtime_start_stop() {
        let mut rt = AndroidRuntime::new();
        assert!(!rt.initialized);
        rt.start().unwrap();
        assert!(rt.initialized);
        assert_eq!(rt.health(), DomainHealth::Healthy);
        rt.stop().unwrap();
        assert!(!rt.initialized);
    }

    #[test]
    fn android_app_lifecycle() {
        let mut rt = AndroidRuntime::new();
        rt.start().unwrap();

        let app = AndroidApp::new("com.whatsapp", "2.24.0");
        rt.install_app(app);
        assert_eq!(rt.installed_app_count(), 1);

        let pid = rt.launch_app("com.whatsapp").unwrap();
        assert!(pid > 0);
        assert_eq!(rt.running_app_count(), 1);

        rt.stop_app("com.whatsapp");
        assert_eq!(rt.running_app_count(), 0);
    }

    #[test]
    fn android_telephony() {
        let mut rt = AndroidRuntime::new();
        rt.start().unwrap();
        assert!(!rt.telephony().is_in_call());
        rt.telephony_mut().make_call("+1-555-0100");
        assert!(rt.telephony().is_in_call());
        rt.telephony_mut().end_call();
        assert!(!rt.telephony().is_in_call());
    }

    #[test]
    fn android_sensors() {
        let mut rt = AndroidRuntime::new();
        rt.start().unwrap();
        assert!(rt.sensors().active_count() > 0);
        let accel = rt.sensors().get_reading("accelerometer");
        assert!(accel.is_some());
        assert_eq!(accel.unwrap().values.len(), 3);
    }

    #[test]
    fn android_hinge_angle() {
        let mut rt = AndroidRuntime::new();
        rt.update_hinge_angle(0.0);
        assert_eq!(rt.form_factor(), "phone_folded");
        rt.update_hinge_angle(90.0);
        assert_eq!(rt.form_factor(), "tablet_unfolded");
        rt.update_hinge_angle(180.0);
        assert_eq!(rt.form_factor(), "flat");
    }

    #[test]
    fn android_binder_transaction() {
        let mut rt = AndroidRuntime::new();
        rt.start().unwrap();
        let tx = BinderTransaction::new(1234, "com.android.camera", "takePicture", vec![]);
        let response = rt.handle_binder(tx);
        assert!(!response.is_empty());
    }

    #[test]
    fn android_domain_identity() {
        let rt = AndroidRuntime::new();
        assert_eq!(rt.domain(), Domain::Android);
    }
}