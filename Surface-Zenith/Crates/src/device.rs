//! # Zenith Device Abstraction Layer
//!
//! Applications never access hardware directly. All device access is mediated
//! through the Zenith Device Broker, which routes requests to the appropriate
//! domain and hardware resource.
//!
//! ## Device API
//!
//! ```text
//! Application calls: IZDevice::Camera()
//! Device Broker resolves: Android Domain → Camera HAL → ISP → Sensor
//! Application receives: Unified frame buffer
//! ```

use serde::{Deserialize, Serialize};
use uuid::Uuid;
use crate::types::{ZDeviceId, ZSessionId, ZTimestamp};
use crate::domain::Domain;
use crate::capability::CapabilityToken;

// ---------------------------------------------------------------------------
// Device class
// ---------------------------------------------------------------------------

/// Class of physical or virtual device
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum DeviceClass {
    /// RGB camera (front/rear)
    Camera { position: CameraPosition },
    /// Microphone array
    Microphone,
    /// Speaker / audio output
    Speaker,
    /// Display panel
    Display { panel: DisplayPanel },
    /// Cellular modem (5G/LTE)
    Modem,
    /// Wi-Fi radio
    WiFi,
    /// Bluetooth radio
    Bluetooth,
    /// GPS / GNSS receiver
    Gps,
    /// Accelerometer
    Accelerometer,
    /// Gyroscope
    Gyroscope,
    /// Magnetometer (compass)
    Magnetometer,
    /// Barometer
    Barometer,
    /// Fingerprint sensor
    Fingerprint,
    /// Face recognition sensor (IR + depth)
    FaceId,
    /// Stylus / pen input
    Stylus,
    /// Keyboard (physical or virtual)
    Keyboard,
    /// Touchscreen
    Touchscreen,
    /// USB-C port
    UsbC { port: u8 },
    /// Thunderbolt / USB4
    Thunderbolt { port: u8 },
    /// Neural Processing Unit
    Npu,
    /// GPU
    Gpu,
    /// Quantum Processing Unit
    Qpu,
    /// Storage (UFS / NVMe)
    Storage { kind: StorageKind },
    /// Battery
    Battery,
    /// Hinge sensor (fold angle)
    HingeSensor,
    /// Satellite communication
    Satellite,
}

/// Camera position
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum CameraPosition {
    Front,
    Rear,
    Periscope,
    Under,
}

/// Display panel identifier
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum DisplayPanel {
    /// Primary inner display (unfolded)
    Inner,
    /// Secondary outer display (folded)
    Outer,
    /// External monitor
    External { index: u8 },
}

/// Storage medium kind
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum StorageKind {
    Ufs,
    Nvme,
    Emmc,
    Cloud,
}

// ---------------------------------------------------------------------------
// Device state
// ---------------------------------------------------------------------------

/// Current state of a device
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum DeviceState {
    /// Device is available and idle
    Available,
    /// Device is in use by a domain
    InUse { domain: Domain },
    /// Device is unavailable (hardware fault)
    Unavailable { reason: String },
    /// Device is in low-power mode
    LowPower,
    /// Device is being initialized
    Initializing,
}

// ---------------------------------------------------------------------------
// Device descriptor
// ---------------------------------------------------------------------------

/// Full descriptor of a physical device registered with the Device Broker
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceDescriptor {
    /// Unique device ID
    pub id: ZDeviceId,
    /// Device class
    pub class: DeviceClass,
    /// Human-readable name
    pub name: String,
    /// Firmware version
    pub firmware_version: String,
    /// Current state
    pub state: DeviceState,
    /// Domain that currently owns this device
    pub owner: Option<Domain>,
    /// Whether this device supports shared access
    pub shareable: bool,
    /// Power consumption in milliwatts (idle)
    pub idle_power_mw: u32,
    /// Power consumption in milliwatts (active)
    pub active_power_mw: u32,
    /// Registration timestamp
    pub registered_at: ZTimestamp,
    /// Device capabilities (feature flags)
    pub capabilities: Vec<String>,
}

impl DeviceDescriptor {
    /// Create a new device descriptor
    pub fn new(class: DeviceClass, name: impl Into<String>) -> Self {
        let now = ZTimestamp(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_micros() as i64,
        );
        Self {
            id: Uuid::new_v4(),
            class,
            name: name.into(),
            firmware_version: "1.0.0".into(),
            state: DeviceState::Available,
            owner: None,
            shareable: false,
            idle_power_mw: 0,
            active_power_mw: 100,
            registered_at: now,
            capabilities: Vec::new(),
        }
    }

    /// Acquire this device for a domain
    pub fn acquire(&mut self, domain: Domain) -> bool {
        if self.state == DeviceState::Available
            || (self.shareable && matches!(self.state, DeviceState::InUse { .. }))
        {
            self.state = DeviceState::InUse { domain: domain.clone() };
            self.owner = Some(domain);
            true
        } else {
            false
        }
    }

    /// Release this device
    pub fn release(&mut self, domain: &Domain) -> bool {
        if self.owner.as_ref() == Some(domain) {
            self.state = DeviceState::Available;
            self.owner = None;
            true
        } else {
            false
        }
    }

    /// Whether this device is currently available
    pub fn is_available(&self) -> bool {
        self.state == DeviceState::Available
    }

    /// Add a capability flag
    pub fn add_capability(&mut self, cap: impl Into<String>) {
        self.capabilities.push(cap.into());
    }
}

// ---------------------------------------------------------------------------
// Device access request
// ---------------------------------------------------------------------------

/// A request to access a device, submitted to the Device Broker
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceAccessRequest {
    /// Requesting session
    pub session: ZSessionId,
    /// Requesting domain
    pub domain: Domain,
    /// Target device class
    pub device_class: DeviceClass,
    /// Capability token authorizing this request
    pub capability: CapabilityToken,
    /// Whether exclusive access is required
    pub exclusive: bool,
    /// Request timestamp
    pub requested_at: ZTimestamp,
}

// ---------------------------------------------------------------------------
// Device broker
// ---------------------------------------------------------------------------

/// The Device Broker — mediates all hardware access
///
/// No domain accesses hardware directly. All requests go through the broker,
/// which validates capabilities, resolves conflicts, and routes to the
/// appropriate domain's HAL.
#[derive(Debug, Default)]
pub struct DeviceBroker {
    devices: std::collections::HashMap<ZDeviceId, DeviceDescriptor>,
    /// Class → device ID index
    class_index: std::collections::HashMap<String, Vec<ZDeviceId>>,
}

impl DeviceBroker {
    /// Create a new device broker
    pub fn new() -> Self {
        Self::default()
    }

    /// Register a device
    pub fn register(&mut self, device: DeviceDescriptor) -> ZDeviceId {
        let id = device.id;
        let class_key = format!("{:?}", device.class);
        self.class_index.entry(class_key).or_default().push(id);
        self.devices.insert(id, device);
        id
    }

    /// Get a device by ID
    pub fn get(&self, id: &ZDeviceId) -> Option<&DeviceDescriptor> {
        self.devices.get(id)
    }

    /// Get a mutable device by ID
    pub fn get_mut(&mut self, id: &ZDeviceId) -> Option<&mut DeviceDescriptor> {
        self.devices.get_mut(id)
    }

    /// Find the first available device of a given class
    pub fn find_available(&self, class: &DeviceClass) -> Option<&DeviceDescriptor> {
        let key = format!("{class:?}");
        self.class_index.get(&key)?.iter().find_map(|id| {
            let dev = self.devices.get(id)?;
            if dev.is_available() { Some(dev) } else { None }
        })
    }

    /// Acquire a device for a domain (returns device ID if successful)
    pub fn acquire(&mut self, class: &DeviceClass, domain: Domain) -> Option<ZDeviceId> {
        let key = format!("{class:?}");
        let ids = self.class_index.get(&key)?.clone();
        for id in ids {
            if let Some(dev) = self.devices.get_mut(&id) {
                if dev.acquire(domain.clone()) {
                    return Some(id);
                }
            }
        }
        None
    }

    /// Release a device
    pub fn release(&mut self, id: &ZDeviceId, domain: &Domain) -> bool {
        self.devices.get_mut(id).map(|d| d.release(domain)).unwrap_or(false)
    }

    /// Total device count
    pub fn count(&self) -> usize {
        self.devices.len()
    }

    /// Count of available devices
    pub fn available_count(&self) -> usize {
        self.devices.values().filter(|d| d.is_available()).count()
    }

    /// Build a standard Surface Zenith device set
    pub fn build_surface_zenith_devices() -> Self {
        let mut broker = Self::new();

        // Cameras
        let mut cam_rear = DeviceDescriptor::new(
            DeviceClass::Camera { position: CameraPosition::Rear },
            "Rear Camera 200MP",
        );
        cam_rear.active_power_mw = 800;
        cam_rear.add_capability("4K@120fps");
        cam_rear.add_capability("optical-zoom-10x");
        broker.register(cam_rear);

        let mut cam_front = DeviceDescriptor::new(
            DeviceClass::Camera { position: CameraPosition::Front },
            "Front Camera 12MP",
        );
        cam_front.active_power_mw = 300;
        broker.register(cam_front);

        // Displays
        let mut inner_display = DeviceDescriptor::new(
            DeviceClass::Display { panel: DisplayPanel::Inner },
            "Inner OLED 8.9\" 2880x2160",
        );
        inner_display.active_power_mw = 1200;
        inner_display.add_capability("120Hz");
        inner_display.add_capability("HDR10+");
        broker.register(inner_display);

        let mut outer_display = DeviceDescriptor::new(
            DeviceClass::Display { panel: DisplayPanel::Outer },
            "Outer OLED 6.2\" 2520x1080",
        );
        outer_display.active_power_mw = 600;
        broker.register(outer_display);

        // NPU
        let mut npu = DeviceDescriptor::new(DeviceClass::Npu, "Zenith NPU 300 TOPS");
        npu.active_power_mw = 5000;
        npu.add_capability("300-tops");
        npu.add_capability("int4-quantization");
        broker.register(npu);

        // GPU
        let mut gpu = DeviceDescriptor::new(DeviceClass::Gpu, "Adreno 850");
        gpu.active_power_mw = 8000;
        gpu.add_capability("ray-tracing");
        gpu.add_capability("vulkan-1.3");
        broker.register(gpu);

        // Modem
        let mut modem = DeviceDescriptor::new(DeviceClass::Modem, "5G SA/NSA Modem");
        modem.active_power_mw = 2000;
        modem.add_capability("5g-mmwave");
        modem.add_capability("satellite");
        broker.register(modem);

        // Hinge sensor
        broker.register(DeviceDescriptor::new(DeviceClass::HingeSensor, "Dual-axis Hinge Sensor"));

        // QPU (simulated)
        let mut qpu = DeviceDescriptor::new(DeviceClass::Qpu, "Zenith QPU Simulator");
        qpu.add_capability("50-qubits");
        qpu.add_capability("error-correction");
        broker.register(qpu);

        broker
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn device_acquire_release() {
        let mut dev = DeviceDescriptor::new(
            DeviceClass::Camera { position: CameraPosition::Rear },
            "Test Camera",
        );
        assert!(dev.is_available());
        assert!(dev.acquire(Domain::Android));
        assert!(!dev.is_available());
        assert!(!dev.acquire(Domain::Windows)); // already in use
        assert!(dev.release(&Domain::Android));
        assert!(dev.is_available());
    }

    #[test]
    fn device_broker_acquire() {
        let mut broker = DeviceBroker::new();
        let dev = DeviceDescriptor::new(DeviceClass::Npu, "NPU");
        broker.register(dev);
        let id = broker.acquire(&DeviceClass::Npu, Domain::AI);
        assert!(id.is_some());
        // Second acquire should fail (not shareable)
        let id2 = broker.acquire(&DeviceClass::Npu, Domain::Windows);
        assert!(id2.is_none());
    }

    #[test]
    fn surface_zenith_device_set() {
        let broker = DeviceBroker::build_surface_zenith_devices();
        assert!(broker.count() >= 8);
        assert!(broker.find_available(&DeviceClass::Npu).is_some());
        assert!(broker.find_available(&DeviceClass::Qpu).is_some());
    }
}