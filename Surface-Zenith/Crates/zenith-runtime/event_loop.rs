//! # Domain Event Loop
//!
//! The event loop processes domain events, IPC messages, and task completions.

use std::collections::VecDeque;
use uuid::Uuid;
use serde::{Deserialize, Serialize};
use zenith_abi::domain::Domain;
use zenith_abi::types::ZSessionId;
use crate::error::RuntimeError;

/// Domain event type
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum DomainEvent {
    TaskSubmitted    { task_id: Uuid },
    TaskCompleted    { task_id: Uuid, result_bytes: usize },
    TaskFailed       { task_id: Uuid, reason: String },
    TaskMigrating    { task_id: Uuid, to_domain: Domain },
    IpcMessageReceived { topic: String, payload_size: usize },
    HealthCheckRequested,
    SessionOpened    { session_id: ZSessionId },
    SessionClosed    { session_id: ZSessionId },
    FormFactorChanged { hinge_angle: f64 },
    PowerStateChanged { state: String },
    MemoryPressure   { utilization: f64 },
    SecurityViolation { detail: String },
    Custom           { name: String, data: Vec<u8> },
}

impl DomainEvent {
    pub fn name(&self) -> &str {
        match self {
            DomainEvent::TaskSubmitted { .. }      => "task.submitted",
            DomainEvent::TaskCompleted { .. }      => "task.completed",
            DomainEvent::TaskFailed { .. }         => "task.failed",
            DomainEvent::TaskMigrating { .. }      => "task.migrating",
            DomainEvent::IpcMessageReceived { .. } => "ipc.received",
            DomainEvent::HealthCheckRequested      => "health.check",
            DomainEvent::SessionOpened { .. }      => "session.opened",
            DomainEvent::SessionClosed { .. }      => "session.closed",
            DomainEvent::FormFactorChanged { .. }  => "formfactor.changed",
            DomainEvent::PowerStateChanged { .. }  => "power.changed",
            DomainEvent::MemoryPressure { .. }     => "memory.pressure",
            DomainEvent::SecurityViolation { .. }  => "security.violation",
            DomainEvent::Custom { name, .. }       => name.as_str(),
        }
    }

    pub fn is_critical(&self) -> bool {
        matches!(self, DomainEvent::SecurityViolation { .. } | DomainEvent::MemoryPressure { utilization } if *utilization > 0.95)
    }
}

/// Event handler function type
pub type EventHandler = Box<dyn Fn(&DomainEvent) + Send + Sync>;

/// The Domain Event Loop
pub struct EventLoop {
    domain:          Domain,
    queue:           VecDeque<DomainEvent>,
    handlers:        Vec<(String, EventHandler)>,
    processed:       u64,
    dropped:         u64,
    max_queue_depth: usize,
    running:         bool,
}

impl EventLoop {
    pub fn new(domain: Domain) -> Self {
        Self {
            domain,
            queue:           VecDeque::new(),
            handlers:        Vec::new(),
            processed:       0,
            dropped:         0,
            max_queue_depth: crate::IPC_QUEUE_DEPTH,
            running:         false,
        }
    }

    /// Register an event handler
    pub fn on(&mut self, event_name: impl Into<String>, handler: EventHandler) {
        self.handlers.push((event_name.into(), handler));
    }

    /// Post an event to the queue
    pub fn post(&mut self, event: DomainEvent) -> bool {
        if self.queue.len() >= self.max_queue_depth {
            self.dropped += 1;
            return false;
        }
        self.queue.push_back(event);
        true
    }

    /// Process one event from the queue
    pub fn process_one(&mut self) -> Option<DomainEvent> {
        let event = self.queue.pop_front()?;
        self.processed += 1;

        // Dispatch to matching handlers
        let event_name = event.name().to_string();
        for (pattern, handler) in &self.handlers {
            if pattern == "*" || pattern == &event_name || event_name.starts_with(pattern.trim_end_matches('*')) {
                handler(&event);
            }
        }

        Some(event)
    }

    /// Process all pending events
    pub fn drain(&mut self) -> usize {
        let mut count = 0;
        while self.process_one().is_some() {
            count += 1;
        }
        count
    }

    /// Start the event loop
    pub fn start(&mut self) {
        self.running = true;
        tracing::info!("Event loop started for domain {:?}", self.domain);
    }

    /// Stop the event loop
    pub fn stop(&mut self) {
        self.running = false;
        self.queue.clear();
    }

    pub fn queue_depth(&self) -> usize { self.queue.len() }
    pub fn processed(&self) -> u64 { self.processed }
    pub fn dropped(&self) -> u64 { self.dropped }
    pub fn is_running(&self) -> bool { self.running }
    pub fn drop_rate(&self) -> f64 {
        let total = self.processed + self.dropped;
        if total == 0 { return 0.0; }
        self.dropped as f64 / total as f64
    }
}

impl std::fmt::Debug for EventLoop {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("EventLoop")
            .field("domain", &self.domain)
            .field("queue_depth", &self.queue.len())
            .field("processed", &self.processed)
            .field("running", &self.running)
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    #[test]
    fn event_loop_post_process() {
        let mut loop_ = EventLoop::new(Domain::Windows);
        loop_.start();
        loop_.post(DomainEvent::HealthCheckRequested);
        loop_.post(DomainEvent::TaskSubmitted { task_id: Uuid::new_v4() });
        assert_eq!(loop_.queue_depth(), 2);
        loop_.drain();
        assert_eq!(loop_.processed(), 2);
        assert_eq!(loop_.queue_depth(), 0);
    }

    #[test]
    fn event_loop_handler() {
        let mut loop_ = EventLoop::new(Domain::Android);
        loop_.start();
        let counter = Arc::new(Mutex::new(0u32));
        let counter_clone = counter.clone();
        loop_.on("task.completed", Box::new(move |_| {
            *counter_clone.lock().unwrap() += 1;
        }));
        loop_.post(DomainEvent::TaskCompleted { task_id: Uuid::new_v4(), result_bytes: 100 });
        loop_.post(DomainEvent::HealthCheckRequested);
        loop_.drain();
        assert_eq!(*counter.lock().unwrap(), 1);
    }

    #[test]
    fn event_loop_wildcard_handler() {
        let mut loop_ = EventLoop::new(Domain::AI);
        loop_.start();
        let counter = Arc::new(Mutex::new(0u32));
        let counter_clone = counter.clone();
        loop_.on("*", Box::new(move |_| {
            *counter_clone.lock().unwrap() += 1;
        }));
        for _ in 0..5 {
            loop_.post(DomainEvent::HealthCheckRequested);
        }
        loop_.drain();
        assert_eq!(*counter.lock().unwrap(), 5);
    }

    #[test]
    fn event_loop_queue_full() {
        let mut loop_ = EventLoop::new(Domain::Windows);
        loop_.start();
        // Fill queue
        for _ in 0..crate::IPC_QUEUE_DEPTH {
            loop_.post(DomainEvent::HealthCheckRequested);
        }
        // This should be dropped
        let accepted = loop_.post(DomainEvent::HealthCheckRequested);
        assert!(!accepted);
        assert_eq!(loop_.dropped(), 1);
    }

    #[test]
    fn event_is_critical() {
        let violation = DomainEvent::SecurityViolation { detail: "test".into() };
        assert!(violation.is_critical());
        let health = DomainEvent::HealthCheckRequested;
        assert!(!health.is_critical());
    }
}