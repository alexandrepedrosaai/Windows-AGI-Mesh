//! # Zenith Session Model
//!
//! The Session is the primary unit of user identity in the Zenith OS.
//! Users do not own devices — they own **sessions** that migrate across
//! physical form factors.
//!
//! ## Session Philosophy
//!
//! Traditional OS: "My phone" + "My laptop" + "My tablet"
//! Zenith OS:      "My session" (manifests on any hardware)
//!
//! A session contains:
//! - Active intents and their task graphs
//! - Universal Memory Objects (documents, emails, media)
//! - Domain state snapshots
//! - Capability tokens
//! - Persistent Intent Graph (PIG)

use serde::{Deserialize, Serialize};
use uuid::Uuid;
use std::collections::HashMap;
use crate::types::{ZSessionId, ZIdentityId, ZTaskId, ZObjectId, ZTimestamp};
use crate::domain::Domain;
use crate::intent::{Intent, IntentState};

// ---------------------------------------------------------------------------
// Session state
// ---------------------------------------------------------------------------

/// Current lifecycle state of a session
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum SessionState {
    /// Session is active and processing intents
    Active,
    /// Session is idle (no active intents)
    Idle,
    /// Session is suspended (device sleeping)
    Suspended,
    /// Session is migrating to another device
    Migrating,
    /// Session has been terminated
    Terminated,
    /// Session is being restored from snapshot
    Restoring,
}

// ---------------------------------------------------------------------------
// Form factor
// ---------------------------------------------------------------------------

/// Physical form factor the session is currently manifesting on
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum FormFactor {
    /// Folded phone mode (single screen, compact)
    PhoneFolded,
    /// Unfolded tablet mode (dual screen, expanded)
    TabletUnfolded,
    /// Desktop mode (external monitor + keyboard + mouse)
    Desktop,
    /// Laptop mode (keyboard attached, clamshell)
    Laptop,
    /// Headless / server mode
    Headless,
    /// Mixed reality / AR overlay
    MixedReality,
}

impl FormFactor {
    /// Whether this form factor supports full desktop-class workloads
    pub fn is_desktop_class(&self) -> bool {
        matches!(self, FormFactor::Desktop | FormFactor::Laptop)
    }

    /// Whether this form factor is mobile-primary
    pub fn is_mobile_primary(&self) -> bool {
        matches!(self, FormFactor::PhoneFolded | FormFactor::TabletUnfolded)
    }

    /// Recommended primary domain for this form factor
    pub fn recommended_domain(&self) -> Domain {
        match self {
            FormFactor::PhoneFolded    => Domain::Android,
            FormFactor::TabletUnfolded => Domain::Android,
            FormFactor::Desktop        => Domain::Windows,
            FormFactor::Laptop         => Domain::Windows,
            FormFactor::Headless       => Domain::AI,
            FormFactor::MixedReality   => Domain::AI,
        }
    }
}

// ---------------------------------------------------------------------------
// Persistent Intent Graph (PIG)
// ---------------------------------------------------------------------------

/// A node in the Persistent Intent Graph
///
/// The PIG represents the user's ongoing computational context as a graph
/// of related intents. Unlike a process list, the PIG persists across
/// reboots, migrations, and form factor changes.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PigNode {
    /// Intent ID
    pub intent_id: ZTaskId,
    /// Human-readable label
    pub label: String,
    /// Domain where this intent last executed
    pub last_domain: Domain,
    /// Whether this intent is currently active
    pub active: bool,
    /// Related object IDs (documents, emails, etc.)
    pub related_objects: Vec<ZObjectId>,
    /// Timestamp of last activity
    pub last_active: ZTimestamp,
}

/// The Persistent Intent Graph — the user's computational identity
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct PersistentIntentGraph {
    /// All nodes in the graph
    pub nodes: Vec<PigNode>,
    /// Edges as (from_intent, to_intent) semantic relationships
    pub edges: Vec<(ZTaskId, ZTaskId)>,
}

impl PersistentIntentGraph {
    /// Add an intent to the graph
    pub fn add_intent(&mut self, node: PigNode) {
        self.nodes.push(node);
    }

    /// Add a semantic relationship between intents
    pub fn add_relation(&mut self, from: ZTaskId, to: ZTaskId) {
        self.edges.push((from, to));
    }

    /// Get all currently active intents
    pub fn active_intents(&self) -> Vec<&PigNode> {
        self.nodes.iter().filter(|n| n.active).collect()
    }

    /// Find intents related to a specific object
    pub fn intents_for_object(&self, object_id: &ZObjectId) -> Vec<&PigNode> {
        self.nodes
            .iter()
            .filter(|n| n.related_objects.contains(object_id))
            .collect()
    }
}

// ---------------------------------------------------------------------------
// Session
// ---------------------------------------------------------------------------

/// A Zenith user session — the primary unit of computational identity
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    /// Unique session ID
    pub id: ZSessionId,
    /// Owning identity
    pub identity: ZIdentityId,
    /// Human-readable session name
    pub name: String,
    /// Current lifecycle state
    pub state: SessionState,
    /// Current form factor
    pub form_factor: FormFactor,
    /// Active domain (primary execution environment)
    pub active_domain: Domain,
    /// All intents in this session (active and historical)
    pub intents: HashMap<ZTaskId, Intent>,
    /// Universal Memory Objects owned by this session
    pub objects: Vec<ZObjectId>,
    /// Persistent Intent Graph
    pub pig: PersistentIntentGraph,
    /// Session creation timestamp
    pub created_at: ZTimestamp,
    /// Last activity timestamp
    pub last_active: ZTimestamp,
    /// Session metadata
    pub metadata: HashMap<String, String>,
    /// Whether this session is the primary session for the identity
    pub is_primary: bool,
    /// Device ID this session is currently bound to
    pub device_id: Option<String>,
}

impl Session {
    /// Create a new session
    pub fn new(
        identity: ZIdentityId,
        name: impl Into<String>,
        form_factor: FormFactor,
    ) -> Self {
        let now = ZTimestamp(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_micros() as i64,
        );
        let active_domain = form_factor.recommended_domain();
        Self {
            id: Uuid::new_v4(),
            identity,
            name: name.into(),
            state: SessionState::Active,
            form_factor,
            active_domain,
            intents: HashMap::new(),
            objects: Vec::new(),
            pig: PersistentIntentGraph::default(),
            created_at: now,
            last_active: now,
            metadata: HashMap::new(),
            is_primary: true,
            device_id: None,
        }
    }

    /// Submit an intent to this session
    pub fn submit_intent(&mut self, intent: Intent) {
        self.pig.add_intent(PigNode {
            intent_id: intent.id,
            label: intent.goal.clone(),
            last_domain: intent.preferred_domain.clone().unwrap_or(Domain::Windows),
            active: true,
            related_objects: Vec::new(),
            last_active: intent.submitted_at,
        });
        self.intents.insert(intent.id, intent);
        self.touch();
    }

    /// Complete an intent
    pub fn complete_intent(&mut self, intent_id: &ZTaskId) {
        if let Some(intent) = self.intents.get_mut(intent_id) {
            intent.state = IntentState::Completed;
        }
        if let Some(node) = self.pig.nodes.iter_mut().find(|n| &n.intent_id == intent_id) {
            node.active = false;
        }
        self.touch();
    }

    /// Transition form factor (triggers domain migration if needed)
    pub fn transition_form_factor(&mut self, new_form: FormFactor) {
        let new_domain = new_form.recommended_domain();
        let domain_changed = new_domain != self.active_domain;
        self.form_factor = new_form;
        if domain_changed {
            self.active_domain = new_domain;
            self.state = SessionState::Migrating;
        }
        self.touch();
    }

    /// Suspend the session
    pub fn suspend(&mut self) {
        self.state = SessionState::Suspended;
    }

    /// Resume the session
    pub fn resume(&mut self) {
        self.state = SessionState::Active;
        self.touch();
    }

    /// Terminate the session
    pub fn terminate(&mut self) {
        self.state = SessionState::Terminated;
    }

    /// Register a UMO with this session
    pub fn register_object(&mut self, object_id: ZObjectId) {
        if !self.objects.contains(&object_id) {
            self.objects.push(object_id);
        }
    }

    /// Count of active intents
    pub fn active_intent_count(&self) -> usize {
        self.intents
            .values()
            .filter(|i| i.state.is_active())
            .count()
    }

    /// Update last-active timestamp
    fn touch(&mut self) {
        self.last_active = ZTimestamp(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_micros() as i64,
        );
    }

    /// Set metadata
    pub fn set_metadata(&mut self, key: impl Into<String>, value: impl Into<String>) {
        self.metadata.insert(key.into(), value.into());
    }
}

// ---------------------------------------------------------------------------
// Session registry
// ---------------------------------------------------------------------------

/// Global registry of all active sessions
#[derive(Debug, Default)]
pub struct SessionRegistry {
    sessions: HashMap<ZSessionId, Session>,
}

impl SessionRegistry {
    /// Create a new empty registry
    pub fn new() -> Self {
        Self::default()
    }

    /// Register a new session
    pub fn register(&mut self, session: Session) -> ZSessionId {
        let id = session.id;
        self.sessions.insert(id, session);
        id
    }

    /// Get a session by ID
    pub fn get(&self, id: &ZSessionId) -> Option<&Session> {
        self.sessions.get(id)
    }

    /// Get a mutable session by ID
    pub fn get_mut(&mut self, id: &ZSessionId) -> Option<&mut Session> {
        self.sessions.get_mut(id)
    }

    /// Get all sessions for an identity
    pub fn sessions_for_identity(&self, identity: &ZIdentityId) -> Vec<&Session> {
        self.sessions
            .values()
            .filter(|s| &s.identity == identity)
            .collect()
    }

    /// Remove a terminated session
    pub fn remove(&mut self, id: &ZSessionId) -> Option<Session> {
        self.sessions.remove(id)
    }

    /// Total session count
    pub fn count(&self) -> usize {
        self.sessions.len()
    }

    /// Count of active sessions
    pub fn active_count(&self) -> usize {
        self.sessions
            .values()
            .filter(|s| s.state == SessionState::Active)
            .count()
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::intent::{Intent, IntentClass};

    #[test]
    fn session_creation() {
        let identity = Uuid::new_v4();
        let session = Session::new(identity, "work-session", FormFactor::Desktop);
        assert_eq!(session.state, SessionState::Active);
        assert_eq!(session.active_domain, Domain::Windows);
    }

    #[test]
    fn session_form_factor_transition() {
        let identity = Uuid::new_v4();
        let mut session = Session::new(identity, "mobile", FormFactor::PhoneFolded);
        assert_eq!(session.active_domain, Domain::Android);
        session.transition_form_factor(FormFactor::Desktop);
        assert_eq!(session.active_domain, Domain::Windows);
        assert_eq!(session.state, SessionState::Migrating);
    }

    #[test]
    fn session_intent_lifecycle() {
        let identity = Uuid::new_v4();
        let mut session = Session::new(identity, "test", FormFactor::Laptop);
        let intent = Intent::new(
            session.id, identity,
            "open excel", IntentClass::Productivity, 100,
        );
        let intent_id = intent.id;
        session.submit_intent(intent);
        assert_eq!(session.intents.len(), 1);
        session.complete_intent(&intent_id);
        assert_eq!(session.active_intent_count(), 0);
    }

    #[test]
    fn session_registry() {
        let mut registry = SessionRegistry::new();
        let identity = Uuid::new_v4();
        let s1 = Session::new(identity, "s1", FormFactor::Desktop);
        let s2 = Session::new(identity, "s2", FormFactor::PhoneFolded);
        registry.register(s1);
        registry.register(s2);
        assert_eq!(registry.sessions_for_identity(&identity).len(), 2);
        assert_eq!(registry.active_count(), 2);
    }
}