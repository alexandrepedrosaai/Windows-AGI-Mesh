//! # Prompt Engineering Engine

use std::collections::HashMap;
use serde::{Deserialize, Serialize};

/// A prompt template with variable substitution
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PromptTemplate {
    pub name:     String,
    pub template: String,
    pub variables: Vec<String>,
    pub system_prompt: Option<String>,
    pub examples: Vec<(String, String)>,
}

impl PromptTemplate {
    pub fn new(name: impl Into<String>, template: impl Into<String>) -> Self {
        let template = template.into();
        let variables = Self::extract_variables(&template);
        Self {
            name: name.into(),
            template,
            variables,
            system_prompt: None,
            examples: Vec::new(),
        }
    }

    fn extract_variables(template: &str) -> Vec<String> {
        let mut vars = Vec::new();
        let mut i = 0;
        let chars: Vec<char> = template.chars().collect();
        while i < chars.len() {
            if chars[i] == '{' && i + 1 < chars.len() && chars[i + 1] == '{' {
                let start = i + 2;
                let mut end = start;
                while end < chars.len() && !(chars[end] == '}' && end + 1 < chars.len() && chars[end + 1] == '}') {
                    end += 1;
                }
                if end < chars.len() {
                    let var: String = chars[start..end].iter().collect();
                    vars.push(var.trim().to_string());
                    i = end + 2;
                    continue;
                }
            }
            i += 1;
        }
        vars
    }

    pub fn render(&self, vars: &HashMap<String, String>) -> String {
        let mut result = self.template.clone();
        for (key, value) in vars {
            result = result.replace(&format!("{{{{{key}}}}}"), value);
        }
        result
    }

    pub fn with_system(mut self, system: impl Into<String>) -> Self {
        self.system_prompt = Some(system.into());
        self
    }

    pub fn with_example(mut self, input: impl Into<String>, output: impl Into<String>) -> Self {
        self.examples.push((input.into(), output.into()));
        self
    }
}

/// Built-in prompt templates for Zenith Copilot
pub struct ZenithPrompts;

impl ZenithPrompts {
    pub fn intent_classification() -> PromptTemplate {
        PromptTemplate::new(
            "intent-classification",
            "Classify the following user intent into one of these categories: \
             Messaging, Telephony, Productivity, Development, Graphics, Inference, \
             Media, SensorFusion, Quantum, CloudSync, System, Unknown.\n\n\
             User intent: {{intent}}\n\n\
             Classification:",
        ).with_system(
            "You are the Zenith Intent Classifier. Classify user intents accurately \
             to route them to the correct execution domain."
        )
    }

    pub fn document_summarization() -> PromptTemplate {
        PromptTemplate::new(
            "document-summarization",
            "Please provide a concise summary of the following document:\n\n\
             Document: {{document}}\n\n\
             Summary:",
        ).with_system(
            "You are Zenith Copilot. Provide accurate, concise summaries."
        )
    }

    pub fn code_generation() -> PromptTemplate {
        PromptTemplate::new(
            "code-generation",
            "Generate {{language}} code for the following requirement:\n\n\
             Requirement: {{requirement}}\n\n\
             Additional context: {{context}}\n\n\
             Code:",
        ).with_system(
            "You are Zenith Copilot, an expert software engineer. \
             Generate clean, efficient, well-documented code."
        )
    }

    pub fn data_analysis() -> PromptTemplate {
        PromptTemplate::new(
            "data-analysis",
            "Analyze the following data and provide insights:\n\n\
             Data: {{data}}\n\n\
             Analysis question: {{question}}\n\n\
             Analysis:",
        ).with_system(
            "You are Zenith Copilot, a data analysis expert. \
             Provide actionable insights from data."
        )
    }

    pub fn email_draft() -> PromptTemplate {
        PromptTemplate::new(
            "email-draft",
            "Draft a professional email based on the following:\n\n\
             To: {{recipient}}\n\
             Subject: {{subject}}\n\
             Key points: {{key_points}}\n\
             Tone: {{tone}}\n\n\
             Email:",
        ).with_system(
            "You are Zenith Copilot. Draft professional, clear emails."
        )
    }

    pub fn rag_qa() -> PromptTemplate {
        PromptTemplate::new(
            "rag-qa",
            "Based on the following context, answer the question:\n\n\
             Context:\n{{context}}\n\n\
             Question: {{question}}\n\n\
             Answer:",
        ).with_system(
            "You are Zenith Copilot. Answer questions based only on the provided context. \
             If the answer is not in the context, say so."
        )
    }

    pub fn domain_migration_explanation() -> PromptTemplate {
        PromptTemplate::new(
            "domain-migration",
            "Explain why the task '{{task}}' is being migrated from {{from_domain}} \
             to {{to_domain}} domain in the Zenith OS.\n\n\
             Migration reason: {{reason}}\n\n\
             Explanation:",
        ).with_system(
            "You are Zenith Copilot. Explain technical decisions in user-friendly terms."
        )
    }
}

/// Prompt registry
#[derive(Debug, Default)]
pub struct PromptRegistry {
    templates: HashMap<String, PromptTemplate>,
}

impl PromptRegistry {
    pub fn new() -> Self { Self::default() }

    pub fn with_zenith_defaults() -> Self {
        let mut registry = Self::new();
        registry.register(ZenithPrompts::intent_classification());
        registry.register(ZenithPrompts::document_summarization());
        registry.register(ZenithPrompts::code_generation());
        registry.register(ZenithPrompts::data_analysis());
        registry.register(ZenithPrompts::email_draft());
        registry.register(ZenithPrompts::rag_qa());
        registry.register(ZenithPrompts::domain_migration_explanation());
        registry
    }

    pub fn register(&mut self, template: PromptTemplate) {
        self.templates.insert(template.name.clone(), template);
    }

    pub fn get(&self, name: &str) -> Option<&PromptTemplate> {
        self.templates.get(name)
    }

    pub fn render(&self, name: &str, vars: &HashMap<String, String>) -> Option<String> {
        self.templates.get(name).map(|t| t.render(vars))
    }

    pub fn count(&self) -> usize { self.templates.len() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn template_variable_extraction() {
        let t = PromptTemplate::new("test", "Hello {{name}}, your task is {{task}}.");
        assert_eq!(t.variables.len(), 2);
        assert!(t.variables.contains(&"name".to_string()));
        assert!(t.variables.contains(&"task".to_string()));
    }

    #[test]
    fn template_render() {
        let t = PromptTemplate::new("test", "Classify: {{intent}}");
        let mut vars = HashMap::new();
        vars.insert("intent".into(), "open excel".into());
        let rendered = t.render(&vars);
        assert_eq!(rendered, "Classify: open excel");
    }

    #[test]
    fn prompt_registry_zenith_defaults() {
        let registry = PromptRegistry::with_zenith_defaults();
        assert!(registry.count() >= 6);
        assert!(registry.get("intent-classification").is_some());
        assert!(registry.get("code-generation").is_some());
    }

    #[test]
    fn prompt_registry_render() {
        let registry = PromptRegistry::with_zenith_defaults();
        let mut vars = HashMap::new();
        vars.insert("intent".into(), "run quantum circuit".into());
        let rendered = registry.render("intent-classification", &vars);
        assert!(rendered.is_some());
        assert!(rendered.unwrap().contains("quantum circuit"));
    }
}