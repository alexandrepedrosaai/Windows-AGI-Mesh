//! # RealTime Domain Runtime
//!
//! The RealTime Runtime manages DSP, audio, sensor fusion, and low-latency I/O.

use std::collections::HashMap;
use uuid::Uuid;
use serde::{Deserialize, Serialize};
use zenith_abi::domain::{Domain, DomainHealth};
use zenith_abi::task::{ZenithTask, TaskState};
use zenith_abi::types::ZTaskId;
use zenith_abi::contract::IZDomainRuntime;
use crate::error::RuntimeError;
use crate::metrics::DomainMetrics;
use crate::task_executor::TaskExecutor;

/// Audio stream state
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum AudioStreamState {
    Idle,
    Recording { sample_rate: u32, channels: u8 },
    Playing   { sample_rate: u32, channels: u8 },
    Processing,
}

/// Audio stream
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioStream {
    pub id:          Uuid,
    pub name:        String,
    pub state:       AudioStreamState,
    pub sample_rate: u32,
    pub channels:    u8,
    pub bit_depth:   u8,
    pub buffer_ms:   u32,
    pub latency_ms:  f32,
}

impl AudioStream {
    pub fn new(name: impl Into<String>, sample_rate: u32, channels: u8) -> Self {
        Self {
            id:          Uuid::new_v4(),
            name:        name.into(),
            state:       AudioStreamState::Idle,
            sample_rate,
            channels,
            bit_depth:   24,
            buffer_ms:   10,
            latency_ms:  5.0,
        }
    }

    pub fn start_recording(&mut self) {
        self.state = AudioStreamState::Recording {
            sample_rate: self.sample_rate,
            channels:    self.channels,
        };
    }

    pub fn start_playing(&mut self) {
        self.state = AudioStreamState::Playing {
            sample_rate: self.sample_rate,
            channels:    self.channels,
        };
    }

    pub fn stop(&mut self) {
        self.state = AudioStreamState::Idle;
    }

    pub fn is_active(&self) -> bool {
        !matches!(self.state, AudioStreamState::Idle)
    }
}

/// DSP effect type
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum DspEffect {
    NoiseReduction { strength: u8 },
    EchoCancellation,
    Equalizer { bands: Vec<i8> },
    Compressor { threshold_db: i8, ratio: u8 },
    Reverb { room_size: u8, damping: u8 },
    Limiter { ceiling_db: i8 },
    BeamForming { mic_count: u8 },
}

/// DSP pipeline
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DspPipeline {
    pub id:      Uuid,
    pub name:    String,
    pub effects: Vec<DspEffect>,
    pub active:  bool,
    pub latency_us: u32,
}

impl DspPipeline {
    pub fn new(name: impl Into<String>) -> Self {
        Self {
            id:         Uuid::new_v4(),
            name:       name.into(),
            effects:    Vec::new(),
            active:     false,
            latency_us: 500,
        }
    }

    pub fn add_effect(&mut self, effect: DspEffect) {
        self.effects.push(effect);
        self.latency_us += 50; // Each effect adds ~50µs
    }

    pub fn activate(&mut self) { self.active = true; }
    pub fn deactivate(&mut self) { self.active = false; }
}

/// Sensor fusion result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FusedSensorData {
    pub timestamp_us:  u64,
    pub orientation:   [f32; 4], // Quaternion (w, x, y, z)
    pub position:      [f32; 3], // (x, y, z) in meters
    pub velocity:      [f32; 3], // (vx, vy, vz) in m/s
    pub acceleration:  [f32; 3], // (ax, ay, az) in m/s²
    pub angular_rate:  [f32; 3], // (rx, ry, rz) in rad/s
    pub magnetic_field:[f32; 3], // (mx, my, mz) in µT
    pub confidence:    f32,
}

impl FusedSensorData {
    pub fn identity() -> Self {
        Self {
            timestamp_us:  0,
            orientation:   [1.0, 0.0, 0.0, 0.0],
            position:      [0.0, 0.0, 0.0],
            velocity:      [0.0, 0.0, 0.0],
            acceleration:  [0.0, 0.0, 9.81],
            angular_rate:  [0.0, 0.0, 0.0],
            magnetic_field:[25.0, -10.0, 40.0],
            confidence:    1.0,
        }
    }
}

/// The RealTime Domain Runtime
#[derive(Debug)]
pub struct RealTimeRuntime {
    health:          DomainHealth,
    active_tasks:    HashMap<ZTaskId, ZenithTask>,
    audio_streams:   HashMap<Uuid, AudioStream>,
    dsp_pipelines:   HashMap<Uuid, DspPipeline>,
    fused_data:      Option<FusedSensorData>,
    metrics:         DomainMetrics,
    executor:        TaskExecutor,
    initialized:     bool,
    dsp_sample_rate: u32,
    audio_latency_ms: f32,
    sensor_rate_hz:  u32,
    total_audio_frames: u64,
    total_sensor_updates: u64,
}

impl RealTimeRuntime {
    pub fn new() -> Self {
        Self {
            health:               DomainHealth::Initializing,
            active_tasks:         HashMap::new(),
            audio_streams:        HashMap::new(),
            dsp_pipelines:        HashMap::new(),
            fused_data:           None,
            metrics:              DomainMetrics::new(Domain::RealTime),
            executor:             TaskExecutor::new(Domain::RealTime),
            initialized:          false,
            dsp_sample_rate:      48_000,
            audio_latency_ms:     5.0,
            sensor_rate_hz:       200,
            total_audio_frames:   0,
            total_sensor_updates: 0,
        }
    }

    /// Create an audio stream
    pub fn create_audio_stream(&mut self, name: impl Into<String>, sample_rate: u32, channels: u8) -> Uuid {
        let stream = AudioStream::new(name, sample_rate, channels);
        let id = stream.id;
        self.audio_streams.insert(id, stream);
        self.metrics.record_event("audio_stream_created");
        id
    }

    /// Start recording on a stream
    pub fn start_recording(&mut self, id: &Uuid) -> bool {
        if let Some(stream) = self.audio_streams.get_mut(id) {
            stream.start_recording();
            self.metrics.record_event("recording_started");
            true
        } else {
            false
        }
    }

    /// Start playback on a stream
    pub fn start_playback(&mut self, id: &Uuid) -> bool {
        if let Some(stream) = self.audio_streams.get_mut(id) {
            stream.start_playing();
            self.metrics.record_event("playback_started");
            true
        } else {
            false
        }
    }

    /// Stop a stream
    pub fn stop_stream(&mut self, id: &Uuid) -> bool {
        if let Some(stream) = self.audio_streams.get_mut(id) {
            stream.stop();
            true
        } else {
            false
        }
    }

    /// Create a DSP pipeline
    pub fn create_dsp_pipeline(&mut self, name: impl Into<String>) -> Uuid {
        let pipeline = DspPipeline::new(name);
        let id = pipeline.id;
        self.dsp_pipelines.insert(id, pipeline);
        id
    }

    /// Add an effect to a DSP pipeline
    pub fn add_dsp_effect(&mut self, pipeline_id: &Uuid, effect: DspEffect) -> bool {
        if let Some(pipeline) = self.dsp_pipelines.get_mut(pipeline_id) {
            pipeline.add_effect(effect);
            self.metrics.record_event("dsp_effect_added");
            true
        } else {
            false
        }
    }

    /// Update fused sensor data
    pub fn update_sensor_fusion(&mut self, data: FusedSensorData) {
        self.fused_data = Some(data);
        self.total_sensor_updates += 1;
        self.metrics.record_event("sensor_fusion_updated");
    }

    /// Get latest fused sensor data
    pub fn fused_data(&self) -> Option<&FusedSensorData> { self.fused_data.as_ref() }

    /// Active audio stream count
    pub fn active_stream_count(&self) -> usize {
        self.audio_streams.values().filter(|s| s.is_active()).count()
    }

    /// Audio latency in milliseconds
    pub fn audio_latency_ms(&self) -> f32 { self.audio_latency_ms }

    /// Sensor update rate in Hz
    pub fn sensor_rate_hz(&self) -> u32 { self.sensor_rate_hz }

    /// Total sensor updates
    pub fn total_sensor_updates(&self) -> u64 { self.total_sensor_updates }

    /// Metrics
    pub fn metrics(&self) -> &DomainMetrics { &self.metrics }
}

impl IZDomainRuntime for RealTimeRuntime {
    fn start(&mut self) -> zenith_abi::types::ZResult<()> {
        self.initialized = true;
        self.health = DomainHealth::Healthy;

        // Initialize default audio pipeline
        let pipeline_id = self.create_dsp_pipeline("default-audio");
        self.add_dsp_effect(&pipeline_id, DspEffect::NoiseReduction { strength: 50 });
        self.add_dsp_effect(&pipeline_id, DspEffect::EchoCancellation);

        // Initialize sensor fusion with identity state
        self.update_sensor_fusion(FusedSensorData::identity());

        tracing::info!("RealTime Runtime started (DSP: {}Hz, latency: {}ms)",
            self.dsp_sample_rate, self.audio_latency_ms);
        Ok(())
    }

    fn stop(&mut self) -> zenith_abi::types::ZResult<()> {
        // Stop all audio streams
        let ids: Vec<Uuid> = self.audio_streams.keys().copied().collect();
        for id in ids {
            self.stop_stream(&id);
        }
        self.health = DomainHealth::ShuttingDown;
        self.initialized = false;
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

    fn domain(&self) -> Domain { Domain::RealTime }
}

impl Default for RealTimeRuntime {
    fn default() -> Self { Self::new() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn realtime_runtime_start() {
        let mut rt = RealTimeRuntime::new();
        rt.start().unwrap();
        assert_eq!(rt.health(), DomainHealth::Healthy);
        assert!(rt.fused_data().is_some());
    }

    #[test]
    fn realtime_audio_streams() {
        let mut rt = RealTimeRuntime::new();
        rt.start().unwrap();
        let id = rt.create_audio_stream("microphone", 48_000, 2);
        assert!(rt.start_recording(&id));
        assert_eq!(rt.active_stream_count(), 1);
        rt.stop_stream(&id);
        assert_eq!(rt.active_stream_count(), 0);
    }

    #[test]
    fn realtime_dsp_pipeline() {
        let mut rt = RealTimeRuntime::new();
        rt.start().unwrap();
        let pid = rt.create_dsp_pipeline("voice-processing");
        assert!(rt.add_dsp_effect(&pid, DspEffect::BeamForming { mic_count: 4 }));
        let pipeline = rt.dsp_pipelines.get(&pid).unwrap();
        assert!(!pipeline.effects.is_empty());
    }

    #[test]
    fn realtime_sensor_fusion() {
        let mut rt = RealTimeRuntime::new();
        rt.start().unwrap();
        let mut data = FusedSensorData::identity();
        data.acceleration = [0.5, 0.0, 9.81];
        rt.update_sensor_fusion(data);
        assert_eq!(rt.total_sensor_updates(), 2); // 1 from start + 1 from update
        let fused = rt.fused_data().unwrap();
        assert_eq!(fused.acceleration[0], 0.5);
    }

    #[test]
    fn realtime_domain_identity() {
        let rt = RealTimeRuntime::new();
        assert_eq!(rt.domain(), Domain::RealTime);
    }
}