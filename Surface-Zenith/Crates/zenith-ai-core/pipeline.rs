//! # AI Processing Pipeline
//!
//! Composable pipeline for chaining AI operations.

use serde::{Deserialize, Serialize};
use crate::error::AiCoreError;

/// A pipeline stage
pub trait PipelineStage: std::fmt::Debug + Send + Sync {
    fn name(&self) -> &str;
    fn process(&self, input: PipelineData) -> Result<PipelineData, AiCoreError>;
}

/// Data flowing through the pipeline
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PipelineData {
    pub text:     String,
    pub metadata: std::collections::HashMap<String, String>,
    pub tokens:   usize,
    pub stage:    usize,
}

impl PipelineData {
    pub fn new(text: impl Into<String>) -> Self {
        let text = text.into();
        let tokens = text.len() / 4;
        Self { text, metadata: std::collections::HashMap::new(), tokens, stage: 0 }
    }

    pub fn with_meta(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.metadata.insert(key.into(), value.into());
        self
    }
}

/// Text preprocessing stage
#[derive(Debug)]
pub struct PreprocessStage {
    pub max_length: usize,
    pub lowercase:  bool,
    pub trim:       bool,
}

impl PreprocessStage {
    pub fn new(max_length: usize) -> Self {
        Self { max_length, lowercase: false, trim: true }
    }
}

impl PipelineStage for PreprocessStage {
    fn name(&self) -> &str { "preprocess" }

    fn process(&self, mut input: PipelineData) -> Result<PipelineData, AiCoreError> {
        if self.trim {
            input.text = input.text.trim().to_string();
        }
        if self.lowercase {
            input.text = input.text.to_lowercase();
        }
        if input.text.len() > self.max_length {
            input.text = input.text[..self.max_length].to_string();
        }
        input.tokens = input.text.len() / 4;
        input.stage += 1;
        Ok(input)
    }
}

/// Token counting stage
#[derive(Debug)]
pub struct TokenCountStage;

impl PipelineStage for TokenCountStage {
    fn name(&self) -> &str { "token-count" }

    fn process(&self, mut input: PipelineData) -> Result<PipelineData, AiCoreError> {
        input.tokens = input.text.len() / 4;
        input.metadata.insert("token_count".into(), input.tokens.to_string());
        input.stage += 1;
        Ok(input)
    }
}

/// Language detection stage
#[derive(Debug)]
pub struct LanguageDetectionStage;

impl PipelineStage for LanguageDetectionStage {
    fn name(&self) -> &str { "language-detection" }

    fn process(&self, mut input: PipelineData) -> Result<PipelineData, AiCoreError> {
        // Simplified: detect based on character patterns
        let lang = if input.text.chars().any(|c| c as u32 > 0x4E00 && c as u32 < 0x9FFF) {
            "zh"
        } else if input.text.chars().any(|c| c as u32 > 0x3040 && c as u32 < 0x30FF) {
            "ja"
        } else {
            "en"
        };
        input.metadata.insert("language".into(), lang.to_string());
        input.stage += 1;
        Ok(input)
    }
}

/// The AI Processing Pipeline
#[derive(Debug, Default)]
pub struct AiPipeline {
    stages:          Vec<Box<dyn PipelineStage>>,
    total_processed: u64,
    total_errors:    u64,
}

impl AiPipeline {
    pub fn new() -> Self { Self::default() }

    pub fn add_stage(mut self, stage: Box<dyn PipelineStage>) -> Self {
        self.stages.push(stage);
        self
    }

    pub fn standard() -> Self {
        Self::new()
            .add_stage(Box::new(PreprocessStage::new(crate::MAX_CONTEXT_TOKENS * 4)))
            .add_stage(Box::new(TokenCountStage))
            .add_stage(Box::new(LanguageDetectionStage))
    }

    pub fn process(&mut self, input: PipelineData) -> Result<PipelineData, AiCoreError> {
        self.total_processed += 1;
        let mut data = input;
        for stage in &self.stages {
            data = stage.process(data).map_err(|e| {
                self.total_errors += 1;
                e
            })?;
        }
        Ok(data)
    }

    pub fn stage_count(&self) -> usize { self.stages.len() }
    pub fn total_processed(&self) -> u64 { self.total_processed }
    pub fn error_rate(&self) -> f64 {
        if self.total_processed == 0 { return 0.0; }
        self.total_errors as f64 / self.total_processed as f64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pipeline_preprocess() {
        let stage = PreprocessStage::new(100);
        let input = PipelineData::new("  Hello, Zenith!  ");
        let output = stage.process(input).unwrap();
        assert_eq!(output.text, "Hello, Zenith!");
        assert_eq!(output.stage, 1);
    }

    #[test]
    fn pipeline_standard() {
        let mut pipeline = AiPipeline::standard();
        assert_eq!(pipeline.stage_count(), 3);
        let input = PipelineData::new("Analyze this document");
        let output = pipeline.process(input).unwrap();
        assert!(output.metadata.contains_key("language"));
        assert!(output.metadata.contains_key("token_count"));
    }

    #[test]
    fn pipeline_truncation() {
        let stage = PreprocessStage::new(10);
        let input = PipelineData::new("a".repeat(100));
        let output = stage.process(input).unwrap();
        assert_eq!(output.text.len(), 10);
    }

    #[test]
    fn pipeline_metrics() {
        let mut pipeline = AiPipeline::standard();
        for _ in 0..5 {
            pipeline.process(PipelineData::new("test")).unwrap();
        }
        assert_eq!(pipeline.total_processed(), 5);
        assert_eq!(pipeline.error_rate(), 0.0);
    }
}