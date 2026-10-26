//! # Domain API Layer
//!
//! Provides the unified API surface that applications use to interact
//! with domain runtimes without knowing which domain they're in.

use std::collections::HashMap;
use uuid::Uuid;
use serde::{Deserialize, Serialize};
use zenith_abi::domain::Domain;
use zenith_abi::types::{ZSessionId, ZObjectId};
use crate::error::RuntimeError;

/// A domain API call
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiCall {
    pub id:         Uuid,
    pub session_id: ZSessionId,
    pub api:        String,
    pub method:     String,
    pub args:       Vec<u8>,
    pub domain:     Domain,
    pub timestamp:  std::time::Instant,
}

impl ApiCall {
    pub fn new(session_id: ZSessionId, api: impl Into<String>, method: impl Into<String>, args: Vec<u8>, domain: Domain) -> Self {
        Self {
            id:         Uuid::new_v4(),
            session_id,
            api:        api.into(),
            method:     method.into(),
            args,
            domain,
            timestamp:  std::time::Instant::now(),
        }
    }
}

/// API call result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiResult {
    pub call_id:    Uuid,
    pub success:    bool,
    pub data:       Vec<u8>,
    pub error:      Option<String>,
    pub latency_ms: u32,
}

impl ApiResult {
    pub fn ok(call_id: Uuid, data: Vec<u8>, latency_ms: u32) -> Self {
        Self { call_id, success: true, data, error: None, latency_ms }
    }

    pub fn err(call_id: Uuid, error: impl Into<String>) -> Self {
        Self { call_id, success: false, data: Vec::new(), error: Some(error.into()), latency_ms: 0 }
    }
}

/// The Domain API dispatcher
#[derive(Debug, Default)]
pub struct DomainApiDispatcher {
    call_log:       Vec<ApiCall>,
    total_calls:    u64,
    total_errors:   u64,
    api_counts:     HashMap<String, u64>,
}

impl DomainApiDispatcher {
    pub fn new() -> Self { Self::default() }

    /// Dispatch an API call to the appropriate domain
    pub fn dispatch(&mut self, call: ApiCall) -> ApiResult {
        let start = std::time::Instant::now();
        self.total_calls += 1;
        *self.api_counts.entry(call.api.clone()).or_insert(0) += 1;

        let call_id = call.id;
        let result_data = self.execute_api(&call);
        let latency_ms = start.elapsed().as_millis() as u32;

        self.call_log.push(call);
        if self.call_log.len() > 10_000 {
            self.call_log.drain(0..1000);
        }

        match result_data {
            Ok(data) => ApiResult::ok(call_id, data, latency_ms),
            Err(e)   => {
                self.total_errors += 1;
                ApiResult::err(call_id, e.to_string())
            }
        }
    }

    fn execute_api(&self, call: &ApiCall) -> Result<Vec<u8>, RuntimeError> {
        // Route to appropriate domain handler
        let response = match call.api.as_str() {
            "IZDevice"  => self.handle_device_api(call),
            "IZMemory"  => self.handle_memory_api(call),
            "IZSession" => self.handle_session_api(call),
            "IZIntent"  => self.handle_intent_api(call),
            _           => Ok(format!("{{\"api\":\"{}\",\"method\":\"{}\",\"status\":\"ok\"}}",
                                call.api, call.method).into_bytes()),
        };
        response
    }

    fn handle_device_api(&self, call: &ApiCall) -> Result<Vec<u8>, RuntimeError> {
        let response = match call.method.as_str() {
            "Camera.Open"   => b"{\"camera\":\"opened\",\"resolution\":\"200MP\"}".to_vec(),
            "Camera.Close"  => b"{\"camera\":\"closed\"}".to_vec(),
            "Npu.Submit"    => b"{\"npu\":\"submitted\",\"queue_depth\":1}".to_vec(),
            "Display.SetBrightness" => b"{\"brightness\":\"set\"}".to_vec(),
            _               => format!("{{\"method\":\"{}\",\"status\":\"ok\"}}", call.method).into_bytes(),
        };
        Ok(response)
    }

    fn handle_memory_api(&self, call: &ApiCall) -> Result<Vec<u8>, RuntimeError> {
        let response = match call.method.as_str() {
            "UMO.Create"  => format!("{{\"umo_id\":\"{}\"}}", Uuid::new_v4()).into_bytes(),
            "UMO.Write"   => b"{\"bytes_written\":4096}".to_vec(),
            "UMO.Read"    => b"{\"data\":\"...\",\"bytes_read\":4096}".to_vec(),
            "UMO.Destroy" => b"{\"status\":\"destroyed\"}".to_vec(),
            _             => format!("{{\"method\":\"{}\",\"status\":\"ok\"}}", call.method).into_bytes(),
        };
        Ok(response)
    }

    fn handle_session_api(&self, call: &ApiCall) -> Result<Vec<u8>, RuntimeError> {
        let response = match call.method.as_str() {
            "Session.Open"    => format!("{{\"session_id\":\"{}\"}}", Uuid::new_v4()).into_bytes(),
            "Session.Close"   => b"{\"status\":\"closed\"}".to_vec(),
            "Session.Suspend" => b"{\"status\":\"suspended\"}".to_vec(),
            "Session.Resume"  => b"{\"status\":\"resumed\"}".to_vec(),
            _                 => format!("{{\"method\":\"{}\",\"status\":\"ok\"}}", call.method).into_bytes(),
        };
        Ok(response)
    }

    fn handle_intent_api(&self, call: &ApiCall) -> Result<Vec<u8>, RuntimeError> {
        let response = match call.method.as_str() {
            "Intent.Submit" => format!("{{\"intent_id\":\"{}\",\"state\":\"Pending\"}}", Uuid::new_v4()).into_bytes(),
            "Intent.Cancel" => b"{\"status\":\"cancelled\"}".to_vec(),
            "Intent.Status" => b"{\"state\":\"Running\",\"domain\":\"windows\"}".to_vec(),
            _               => format!("{{\"method\":\"{}\",\"status\":\"ok\"}}", call.method).into_bytes(),
        };
        Ok(response)
    }

    pub fn total_calls(&self) -> u64 { self.total_calls }
    pub fn total_errors(&self) -> u64 { self.total_errors }
    pub fn error_rate(&self) -> f64 {
        if self.total_calls == 0 { return 0.0; }
        self.total_errors as f64 / self.total_calls as f64
    }
    pub fn api_call_count(&self, api: &str) -> u64 {
        *self.api_counts.get(api).unwrap_or(&0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_call(api: &str, method: &str) -> ApiCall {
        ApiCall::new(Uuid::new_v4(), api, method, vec![], Domain::Windows)
    }

    #[test]
    fn api_dispatcher_device_camera() {
        let mut dispatcher = DomainApiDispatcher::new();
        let call = make_call("IZDevice", "Camera.Open");
        let result = dispatcher.dispatch(call);
        assert!(result.success);
        assert!(!result.data.is_empty());
    }

    #[test]
    fn api_dispatcher_memory_umo() {
        let mut dispatcher = DomainApiDispatcher::new();
        let result = dispatcher.dispatch(make_call("IZMemory", "UMO.Create"));
        assert!(result.success);
        let json = String::from_utf8(result.data).unwrap();
        assert!(json.contains("umo_id"));
    }

    #[test]
    fn api_dispatcher_session() {
        let mut dispatcher = DomainApiDispatcher::new();
        let result = dispatcher.dispatch(make_call("IZSession", "Session.Open"));
        assert!(result.success);
        let json = String::from_utf8(result.data).unwrap();
        assert!(json.contains("session_id"));
    }

    #[test]
    fn api_dispatcher_metrics() {
        let mut dispatcher = DomainApiDispatcher::new();
        for _ in 0..5 {
            dispatcher.dispatch(make_call("IZDevice", "Npu.Submit"));
        }
        assert_eq!(dispatcher.total_calls(), 5);
        assert_eq!(dispatcher.api_call_count("IZDevice"), 5);
        assert_eq!(dispatcher.error_rate(), 0.0);
    }
}