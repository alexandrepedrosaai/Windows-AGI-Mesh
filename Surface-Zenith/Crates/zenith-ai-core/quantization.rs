//! # Model Quantization Manager

use serde::{Deserialize, Serialize};
use zenith_abi::inference::Quantization;

/// Quantization configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuantizationConfig {
    pub method:          Quantization,
    pub calibration_samples: usize,
    pub symmetric:       bool,
    pub per_channel:     bool,
    pub mixed_precision: bool,
}

impl QuantizationConfig {
    pub fn int4() -> Self {
        Self { method: Quantization::Int4, calibration_samples: 512, symmetric: true, per_channel: true, mixed_precision: true }
    }

    pub fn int8() -> Self {
        Self { method: Quantization::Int8, calibration_samples: 256, symmetric: true, per_channel: false, mixed_precision: false }
    }

    pub fn fp16() -> Self {
        Self { method: Quantization::Fp16, calibration_samples: 0, symmetric: false, per_channel: false, mixed_precision: false }
    }

    /// Estimated compression ratio vs FP32
    pub fn compression_ratio(&self) -> f32 {
        match self.method {
            Quantization::Fp32 => 1.0,
            Quantization::Fp16 | Quantization::Bf16 => 2.0,
            Quantization::Int8 => 4.0,
            Quantization::Int4 => 8.0,
            Quantization::Int2 => 16.0,
        }
    }

    /// Estimated accuracy loss (0.0 = no loss, 1.0 = complete loss)
    pub fn estimated_accuracy_loss(&self) -> f32 {
        match self.method {
            Quantization::Fp32 => 0.0,
            Quantization::Fp16 | Quantization::Bf16 => 0.001,
            Quantization::Int8 => 0.01,
            Quantization::Int4 => 0.03,
            Quantization::Int2 => 0.15,
        }
    }

    /// Estimated speedup vs FP32 on NPU
    pub fn npu_speedup(&self) -> f32 {
        match self.method {
            Quantization::Fp32 => 1.0,
            Quantization::Fp16 | Quantization::Bf16 => 2.0,
            Quantization::Int8 => 4.0,
            Quantization::Int4 => 8.0,
            Quantization::Int2 => 12.0,
        }
    }
}

/// Quantization manager
#[derive(Debug, Default)]
pub struct QuantizationManager {
    configs:         std::collections::HashMap<uuid::Uuid, QuantizationConfig>,
    total_quantized: u64,
}

impl QuantizationManager {
    pub fn new() -> Self { Self::default() }

    /// Register a quantization config for a model
    pub fn register(&mut self, model_id: uuid::Uuid, config: QuantizationConfig) {
        self.configs.insert(model_id, config);
        self.total_quantized += 1;
    }

    /// Get config for a model
    pub fn get(&self, model_id: &uuid::Uuid) -> Option<&QuantizationConfig> {
        self.configs.get(model_id)
    }

    /// Recommend quantization for a model based on hardware constraints
    pub fn recommend(&self, model_size_bytes: u64, available_memory_bytes: u64) -> QuantizationConfig {
        let ratio_needed = model_size_bytes as f32 / available_memory_bytes as f32;
        if ratio_needed <= 1.0 {
            QuantizationConfig::fp16()
        } else if ratio_needed <= 2.0 {
            QuantizationConfig::int8()
        } else {
            QuantizationConfig::int4()
        }
    }

    pub fn total_quantized(&self) -> u64 { self.total_quantized }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quantization_compression_ratios() {
        assert_eq!(QuantizationConfig::fp16().compression_ratio(), 2.0);
        assert_eq!(QuantizationConfig::int8().compression_ratio(), 4.0);
        assert_eq!(QuantizationConfig::int4().compression_ratio(), 8.0);
    }

    #[test]
    fn quantization_accuracy_loss_ordering() {
        let fp16 = QuantizationConfig::fp16();
        let int8 = QuantizationConfig::int8();
        let int4 = QuantizationConfig::int4();
        assert!(fp16.estimated_accuracy_loss() < int8.estimated_accuracy_loss());
        assert!(int8.estimated_accuracy_loss() < int4.estimated_accuracy_loss());
    }

    #[test]
    fn quantization_recommendation() {
        let mgr = QuantizationManager::new();
        let model_size = 8 * 1024 * 1024 * 1024u64; // 8 GB
        let mem_8gb = 8 * 1024 * 1024 * 1024u64;
        let mem_4gb = 4 * 1024 * 1024 * 1024u64;
        let mem_2gb = 2 * 1024 * 1024 * 1024u64;

        let rec_8gb = mgr.recommend(model_size, mem_8gb);
        let rec_4gb = mgr.recommend(model_size, mem_4gb);
        let rec_2gb = mgr.recommend(model_size, mem_2gb);

        // More memory → less aggressive quantization
        assert!(rec_8gb.compression_ratio() <= rec_4gb.compression_ratio());
        assert!(rec_4gb.compression_ratio() <= rec_2gb.compression_ratio());
    }
}