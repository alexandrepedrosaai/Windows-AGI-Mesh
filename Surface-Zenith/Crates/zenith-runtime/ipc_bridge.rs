//! # IPC Bridge
//!
//! Bridges domain-specific IPC protocols to the Zenith Interdomain Bus.

use std::collections::HashMap;
use uuid::Uuid;
use serde::{Deserialize, Serialize};
use zenith_abi::domain::Domain;
use zenith_abi::types::ZSessionId;
use crate::error::RuntimeError;

/// IPC protocol type
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum IpcProtocol {
    /// Android Binder
    Binder,
    /// Windows COM/RPC
    ComRpc,
    /// D-Bus (Linux)
    DBus,
    /// gRPC
    Grpc,
    /// WebSocket
    WebSocket,
    /// Shared Memory
    SharedMemory,
    /// Zenith ZIB (native)
    Zib,
}

/// An IPC message being bridged
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgedMessage {
    pub id:           Uuid,
    pub source:       Domain,
    pub target:       Domain,
    pub protocol:     IpcProtocol,
    pub method:       String,
    pub payload:      Vec<u8>,
    pub session_id:   ZSessionId,
    pub timestamp:    std::time::Instant,
    pub translated:   bool,
}

impl BridgedMessage {
    pub fn new(source: Domain, target: Domain, protocol: IpcProtocol, method: impl Into<String>, payload: Vec<u8>, session_id: ZSessionId) -> Self {
        Self {
            id:         Uuid::new_v4(),
            source,
            target,
            protocol,
            method:     method.into(),
            payload,
            session_id,
            timestamp:  std::time::Instant::now(),
            translated: false,
        }
    }
}

/// Translation rule: maps a domain-specific call to a ZIB topic
#[derive(Debug, Clone)]
pub struct TranslationRule {
    pub source_protocol: IpcProtocol,
    pub source_method:   String,
    pub zib_topic:       String,
    pub transform:       fn(&[u8]) -> Vec<u8>,
}

/// The IPC Bridge
#[derive(Debug, Default)]
pub struct IpcBridge {
    rules:           Vec<TranslationRule>,
    message_log:     Vec<BridgedMessage>,
    total_bridged:   u64,
    total_failed:    u64,
    protocol_counts: HashMap<String, u64>,
}

impl IpcBridge {
    pub fn new() -> Self { Self::default() }

    /// Add a translation rule
    pub fn add_rule(&mut self, rule: TranslationRule) {
        self.rules.push(rule);
    }

    /// Bridge a message from a domain-specific protocol to ZIB
    pub fn bridge(&mut self, mut msg: BridgedMessage) -> Result<String, RuntimeError> {
        self.total_bridged += 1;
        let proto_key = format!("{:?}", msg.protocol);
        *self.protocol_counts.entry(proto_key).or_insert(0) += 1;

        // Find matching translation rule
        let topic = self.rules.iter()
            .find(|r| r.source_protocol == msg.protocol && r.source_method == msg.method)
            .map(|r| r.zib_topic.clone())
            .unwrap_or_else(|| format!("custom.{}.{}", msg.source.name(), msg.method));

        msg.translated = true;
        self.message_log.push(msg);
        if self.message_log.len() > 10_000 {
            self.message_log.drain(0..1000);
        }

        Ok(topic)
    }

    /// Build standard Zenith IPC bridge rules
    pub fn with_standard_rules(mut self) -> Self {
        // Android Binder → ZIB translations
        self.add_rule(TranslationRule {
            source_protocol: IpcProtocol::Binder,
            source_method:   "takePicture".into(),
            zib_topic:       "device.camera.capture".into(),
            transform:       |b| b.to_vec(),
        });
        self.add_rule(TranslationRule {
            source_protocol: IpcProtocol::Binder,
            source_method:   "sendSms".into(),
            zib_topic:       "telephony.sms.send".into(),
            transform:       |b| b.to_vec(),
        });

        // Windows COM → ZIB translations
        self.add_rule(TranslationRule {
            source_protocol: IpcProtocol::ComRpc,
            source_method:   "OpenDocument".into(),
            zib_topic:       "memory.object.created".into(),
            transform:       |b| b.to_vec(),
        });
        self.add_rule(TranslationRule {
            source_protocol: IpcProtocol::ComRpc,
            source_method:   "SaveDocument".into(),
            zib_topic:       "memory.update".into(),
            transform:       |b| b.to_vec(),
        });

        self
    }

    pub fn total_bridged(&self) -> u64 { self.total_bridged }
    pub fn total_failed(&self) -> u64 { self.total_failed }
    pub fn protocol_count(&self, protocol: &IpcProtocol) -> u64 {
        *self.protocol_counts.get(&format!("{protocol:?}")).unwrap_or(&0)
    }
    pub fn message_log_len(&self) -> usize { self.message_log.len() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ipc_bridge_binder_translation() {
        let mut bridge = IpcBridge::new().with_standard_rules();
        let msg = BridgedMessage::new(
            Domain::Android, Domain::Windows,
            IpcProtocol::Binder, "takePicture",
            b"camera_params".to_vec(), Uuid::new_v4(),
        );
        let topic = bridge.bridge(msg).unwrap();
        assert_eq!(topic, "device.camera.capture");
        assert_eq!(bridge.total_bridged(), 1);
    }

    #[test]
    fn ipc_bridge_unknown_method() {
        let mut bridge = IpcBridge::new().with_standard_rules();
        let msg = BridgedMessage::new(
            Domain::Android, Domain::AI,
            IpcProtocol::Binder, "unknownMethod",
            vec![], Uuid::new_v4(),
        );
        let topic = bridge.bridge(msg).unwrap();
        assert!(topic.starts_with("custom."));
    }

    #[test]
    fn ipc_bridge_protocol_counts() {
        let mut bridge = IpcBridge::new().with_standard_rules();
        for _ in 0..3 {
            let msg = BridgedMessage::new(
                Domain::Windows, Domain::Android,
                IpcProtocol::ComRpc, "OpenDocument",
                vec![], Uuid::new_v4(),
            );
            bridge.bridge(msg).unwrap();
        }
        assert_eq!(bridge.protocol_count(&IpcProtocol::ComRpc), 3);
    }
}