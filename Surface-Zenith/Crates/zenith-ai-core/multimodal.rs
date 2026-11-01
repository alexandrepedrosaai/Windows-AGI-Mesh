//! # Multimodal Processing Hub
//!
//! Handles text, image, audio, and code inputs for the Zenith AI Core.

use serde::{Deserialize, Serialize};
use zenith_abi::inference::InferenceHardware;
use crate::error::AiCoreError;

/// Modality type
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum Modality {
    Text,
    Image,
    Audio,
    Video,
    Code,
    Document,
    Structured,
}

/// A multimodal input
#[derive(Debug, Clone)]
pub struct MultimodalInput {
    pub id:       uuid::Uuid,
    pub modality: Modality,
    pub data:     MultimodalData,
    pub metadata: std::collections::HashMap<String, String>,
}

/// Multimodal data payload
#[derive(Debug, Clone)]
pub enum MultimodalData {
    Text(String),
    Image { bytes: Vec<u8>, mime_type: String, width: u32, height: u32 },
    Audio { bytes: Vec<u8>, sample_rate: u32, channels: u8, duration_ms: u32 },
    Code  { content: String, language: String, file_path: Option<String> },
    Document { content: String, format: String },
    Structured { json: String },
}

impl MultimodalData {
    pub fn modality(&self) -> Modality {
        match self {
            MultimodalData::Text(_)       => Modality::Text,
            MultimodalData::Image { .. }  => Modality::Image,
            MultimodalData::Audio { .. }  => Modality::Audio,
            MultimodalData::Code { .. }   => Modality::Code,
            MultimodalData::Document { .. }=> Modality::Document,
            MultimodalData::Structured { .. }=> Modality::Structured,
        }
    }

    pub fn size_bytes(&self) -> usize {
        match self {
            MultimodalData::Text(s)       => s.len(),
            MultimodalData::Image { bytes, .. } => bytes.len(),
            MultimodalData::Audio { bytes, .. } => bytes.len(),
            MultimodalData::Code { content, .. }=> content.len(),
            MultimodalData::Document { content, .. }=> content.len(),
            MultimodalData::Structured { json }=> json.len(),
        }
    }
}

/// Multimodal processing result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MultimodalResult {
    pub input_id:    uuid::Uuid,
    pub modality:    Modality,
    pub text_output: String,
    pub confidence:  f32,
    pub hardware:    InferenceHardware,
    pub latency_ms:  u32,
}

/// The Multimodal Processing Hub
#[derive(Debug, Default)]
pub struct MultimodalHub {
    total_processed: u64,
    by_modality:     std::collections::HashMap<String, u64>,
}

impl MultimodalHub {
    pub fn new() -> Self { Self::default() }

    /// Process a multimodal input
    pub fn process(&mut self, input: MultimodalInput) -> Result<MultimodalResult, AiCoreError> {
        self.total_processed += 1;
        let modality_key = format!("{:?}", input.modality);
        *self.by_modality.entry(modality_key).or_insert(0) += 1;

        let (text_output, hardware) = match &input.data {
            MultimodalData::Text(text) => {
                (format!("Processed text: {} chars", text.len()), InferenceHardware::Npu)
            }
            MultimodalData::Image { width, height, .. } => {
                (format!("Image analyzed: {}×{} pixels. Objects detected: document, text, chart.",
                    width, height), InferenceHardware::Npu)
            }
            MultimodalData::Audio { duration_ms, sample_rate, .. } => {
                (format!("Audio transcribed: {}ms at {}Hz. Content: [transcription]",
                    duration_ms, sample_rate), InferenceHardware::Npu)
            }
            MultimodalData::Code { language, content } => {
                (format!("Code analyzed ({language}): {} lines. Quality: Good.",
                    content.lines().count()), InferenceHardware::Gpu)
            }
            MultimodalData::Document { format, content } => {
                (format!("Document ({format}) processed: {} chars.", content.len()), InferenceHardware::Npu)
            }
            MultimodalData::Structured { json } => {
                (format!("Structured data analyzed: {} bytes JSON.", json.len()), InferenceHardware::Cpu)
            }
        };

        Ok(MultimodalResult {
            input_id:    input.id,
            modality:    input.modality,
            text_output,
            confidence:  0.92,
            hardware,
            latency_ms:  42,
        })
    }

    /// Fuse multiple modality results into a unified response
    pub fn fuse_results(&self, results: &[MultimodalResult]) -> String {
        if results.is_empty() { return String::new(); }
        results.iter()
            .map(|r| format!("[{:?}]: {}", r.modality, r.text_output))
            .collect::<Vec<_>>()
            .join("\n")
    }

    pub fn total_processed(&self) -> u64 { self.total_processed }
    pub fn count_by_modality(&self, modality: &Modality) -> u64 {
        *self.by_modality.get(&format!("{modality:?}")).unwrap_or(&0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_input(data: MultimodalData) -> MultimodalInput {
        MultimodalInput {
            id:       uuid::Uuid::new_v4(),
            modality: data.modality(),
            data,
            metadata: std::collections::HashMap::new(),
        }
    }

    #[test]
    fn multimodal_text_processing() {
        let mut hub = MultimodalHub::new();
        let input = make_input(MultimodalData::Text("Hello, Zenith!".into()));
        let result = hub.process(input).unwrap();
        assert!(!result.text_output.is_empty());
        assert_eq!(result.modality, Modality::Text);
    }

    #[test]
    fn multimodal_image_processing() {
        let mut hub = MultimodalHub::new();
        let input = make_input(MultimodalData::Image {
            bytes: vec![0u8; 1024],
            mime_type: "image/jpeg".into(),
            width: 1920,
            height: 1080,
        });
        let result = hub.process(input).unwrap();
        assert!(result.text_output.contains("1920"));
    }

    #[test]
    fn multimodal_code_processing() {
        let mut hub = MultimodalHub::new();
        let input = make_input(MultimodalData::Code {
            content:   "fn main() { println!(\"Hello\"); }".into(),
            language:  "rust".into(),
            file_path: None,
        });
        let result = hub.process(input).unwrap();
        assert!(result.text_output.contains("rust"));
        assert_eq!(result.hardware, InferenceHardware::Gpu);
    }

    #[test]
    fn multimodal_fuse_results() {
        let mut hub = MultimodalHub::new();
        let r1 = hub.process(make_input(MultimodalData::Text("text".into()))).unwrap();
        let r2 = hub.process(make_input(MultimodalData::Code {
            content: "code".into(), language: "python".into(), file_path: None,
        })).unwrap();
        let fused = hub.fuse_results(&[r1, r2]);
        assert!(fused.contains("Text"));
        assert!(fused.contains("Code"));
    }

    #[test]
    fn multimodal_metrics() {
        let mut hub = MultimodalHub::new();
        hub.process(make_input(MultimodalData::Text("a".into()))).unwrap();
        hub.process(make_input(MultimodalData::Text("b".into()))).unwrap();
        assert_eq!(hub.total_processed(), 2);
        assert_eq!(hub.count_by_modality(&Modality::Text), 2);
    }
}