// =============================================================================
// session_manager.qs
// Q# WebTransport session manager for WT-MAIA/1.0 protocol
// Manages multi-node sessions, authentication, and connection lifecycle
// Namespace: SiameseTwinAI.WebTransport
// =============================================================================

namespace SiameseTwinAI.WebTransport {

    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Diagnostics;

    // =========================================================================
    // Node Types
    // =========================================================================

    function NodeTypeWindows() : Int { return 0; }
    function NodeTypeLinux()   : Int { return 1; }
    function NodeTypeMAIA()    : Int { return 2; }
    function NodeTypeEdge()    : Int { return 3; }
    function NodeTypeFirefox() : Int { return 4; }

    // =========================================================================
    // Node Registration
    // =========================================================================

    newtype NodeRegistration = (
        NodeId       : String,
        NodeType     : Int,
        Address      : String,
        Port         : Int,
        Capabilities : Int[],
        RegisteredAt : Int,
        LastSeen     : Int,
        IsActive     : Bool,
        SessionCount : Int,
        TrustLevel   : Int
    );

    function CreateNodeRegistration(
        nodeId : String,
        nodeType : Int,
        address : String,
        port : Int,
        capabilities : Int[],
        timestamp : Int
    ) : NodeRegistration {
        return NodeRegistration(
            nodeId, nodeType, address, port,
            capabilities, timestamp, timestamp,
            true, 0, 5
        );
    }

    function UpdateNodeLastSeen(
        node : NodeRegistration,
        timestamp : Int
    ) : NodeRegistration {
        return NodeRegistration(
            node::NodeId, node::NodeType, node::Address, node::Port,
            node::Capabilities, node::RegisteredAt, timestamp,
            true, node::SessionCount, node::TrustLevel
        );
    }

    function DeactivateNode(node : NodeRegistration) : NodeRegistration {
        return NodeRegistration(
            node::NodeId, node::NodeType, node::Address, node::Port,
            node::Capabilities, node::RegisteredAt, node::LastSeen,
            false, node::SessionCount, node::TrustLevel
        );
    }

    function IsNodeAlive(
        node : NodeRegistration,
        currentTimestamp : Int,
        timeoutMs : Int
    ) : Bool {
        return node::IsActive and
               (currentTimestamp - node::LastSeen) < timeoutMs;
    }

    // =========================================================================
    // Session Registry
    // =========================================================================

    newtype SessionRegistry = (
        Sessions     : SessionState[],
        Nodes        : NodeRegistration[],
        TotalSessions : Int,
        ActiveSessions : Int,
        MaxSessions  : Int,
        CreatedAt    : Int,
        LastUpdated  : Int
    );

    function InitSessionRegistry(
        maxSessions : Int,
        timestamp : Int
    ) : SessionRegistry {
        return SessionRegistry(
            new SessionState[0],
            new NodeRegistration[0],
            0, 0, maxSessions,
            timestamp, timestamp
        );
    }

    function RegisterNode(
        registry : SessionRegistry,
        node : NodeRegistration
    ) : SessionRegistry {
        // Check if node already registered
        mutable nodes = registry::Nodes;
        mutable found = false;
        for i in 0 .. Length(nodes) - 1 {
            if nodes[i]::NodeId == node::NodeId {
                set nodes w/= i <- node;
                set found = true;
            }
        }
        if not found {
            set nodes += [node];
        }
        return SessionRegistry(
            registry::Sessions, nodes,
            registry::TotalSessions, registry::ActiveSessions,
            registry::MaxSessions, registry::CreatedAt,
            node::RegisteredAt
        );
    }

    function AddSession(
        registry : SessionRegistry,
        session : SessionState,
        timestamp : Int
    ) : SessionRegistry {
        if registry::ActiveSessions >= registry::MaxSessions {
            return registry;  // Registry full
        }
        let sessions = registry::Sessions + [session];
        return SessionRegistry(
            sessions, registry::Nodes,
            registry::TotalSessions + 1,
            registry::ActiveSessions + 1,
            registry::MaxSessions,
            registry::CreatedAt, timestamp
        );
    }

    function RemoveSession(
        registry : SessionRegistry,
        sessionId : String,
        timestamp : Int
    ) : SessionRegistry {
        mutable sessions = new SessionState[0];
        mutable removed = 0;
        for s in registry::Sessions {
            if s::SessionId != sessionId {
                set sessions += [s];
            } else {
                set removed += 1;
            }
        }
        return SessionRegistry(
            sessions, registry::Nodes,
            registry::TotalSessions,
            registry::ActiveSessions - removed,
            registry::MaxSessions,
            registry::CreatedAt, timestamp
        );
    }

    function GetSession(
        registry : SessionRegistry,
        sessionId : String
    ) : (Bool, SessionState) {
        for s in registry::Sessions {
            if s::SessionId == sessionId {
                return (true, s);
            }
        }
        return (false, InitSession("", "", "", 0));
    }

    function UpdateSession(
        registry : SessionRegistry,
        updatedSession : SessionState,
        timestamp : Int
    ) : SessionRegistry {
        mutable sessions = registry::Sessions;
        for i in 0 .. Length(sessions) - 1 {
            if sessions[i]::SessionId == updatedSession::SessionId {
                set sessions w/= i <- updatedSession;
            }
        }
        return SessionRegistry(
            sessions, registry::Nodes,
            registry::TotalSessions, registry::ActiveSessions,
            registry::MaxSessions, registry::CreatedAt, timestamp
        );
    }

    function GetActiveSessionCount(registry : SessionRegistry) : Int {
        return registry::ActiveSessions;
    }

    function GetNodeByType(
        registry : SessionRegistry,
        nodeType : Int
    ) : NodeRegistration[] {
        mutable result = new NodeRegistration[0];
        for node in registry::Nodes {
            if node::NodeType == nodeType and node::IsActive {
                set result += [node];
            }
        }
        return result;
    }

    function GetAllActiveNodes(
        registry : SessionRegistry,
        currentTimestamp : Int,
        timeoutMs : Int
    ) : NodeRegistration[] {
        mutable result = new NodeRegistration[0];
        for node in registry::Nodes {
            if IsNodeAlive(node, currentTimestamp, timeoutMs) {
                set result += [node];
            }
        }
        return result;
    }

    // =========================================================================
    // Authentication
    // =========================================================================

    newtype AuthToken = (
        TokenId    : String,
        NodeId     : String,
        IssuedAt   : Int,
        ExpiresAt  : Int,
        Scopes     : Int[],
        IsRevoked  : Bool
    );

    function CreateAuthToken(
        tokenId : String,
        nodeId : String,
        issuedAt : Int,
        validityMs : Int,
        scopes : Int[]
    ) : AuthToken {
        return AuthToken(
            tokenId, nodeId,
            issuedAt, issuedAt + validityMs,
            scopes, false
        );
    }

    function IsTokenValid(
        token : AuthToken,
        currentTimestamp : Int
    ) : Bool {
        return not token::IsRevoked and
               currentTimestamp >= token::IssuedAt and
               currentTimestamp < token::ExpiresAt;
    }

    function RevokeToken(token : AuthToken) : AuthToken {
        return AuthToken(
            token::TokenId, token::NodeId,
            token::IssuedAt, token::ExpiresAt,
            token::Scopes, true
        );
    }

    function HasScope(token : AuthToken, scope : Int) : Bool {
        for s in token::Scopes {
            if s == scope or s == ScopeAdmin() { return true; }
        }
        return false;
    }

    // Scope constants
    function ScopeSensorRead()    : Int { return 0x01; }
    function ScopeGradientWrite() : Int { return 0x02; }
    function ScopeWeightRead()    : Int { return 0x04; }
    function ScopeWeightWrite()   : Int { return 0x08; }
    function ScopeMAIAInfer()     : Int { return 0x10; }
    function ScopeMAIATrain()     : Int { return 0x20; }
    function ScopeAdmin()         : Int { return 0xFF; }

    // =========================================================================
    // Connection Handshake
    // =========================================================================

    newtype HandshakeState = (
        Phase          : Int,
        NodeId         : String,
        PeerNodeId     : String,
        Nonce          : Int,
        PeerNonce      : Int,
        SharedSecret   : Int,
        Capabilities   : Int[],
        PeerCapabilities : Int[],
        StartedAt      : Int,
        CompletedAt    : Int,
        Success        : Bool
    );

    // Handshake phases
    function PhaseInit()      : Int { return 0; }
    function PhaseHello()     : Int { return 1; }
    function PhaseChallenge() : Int { return 2; }
    function PhaseVerify()    : Int { return 3; }
    function PhaseComplete()  : Int { return 4; }
    function PhaseFailed()    : Int { return 5; }

    function InitHandshake(
        nodeId : String,
        nonce : Int,
        capabilities : Int[],
        timestamp : Int
    ) : HandshakeState {
        return HandshakeState(
            PhaseInit(), nodeId, "",
            nonce, 0, 0,
            capabilities, new Int[0],
            timestamp, 0, false
        );
    }

    function ProcessHello(
        state : HandshakeState,
        peerNodeId : String,
        peerNonce : Int,
        peerCapabilities : Int[]
    ) : HandshakeState {
        return HandshakeState(
            PhaseHello(), state::NodeId, peerNodeId,
            state::Nonce, peerNonce, 0,
            state::Capabilities, peerCapabilities,
            state::StartedAt, 0, false
        );
    }

    function ProcessChallenge(
        state : HandshakeState,
        sharedSecret : Int
    ) : HandshakeState {
        return HandshakeState(
            PhaseChallenge(), state::NodeId, state::PeerNodeId,
            state::Nonce, state::PeerNonce, sharedSecret,
            state::Capabilities, state::PeerCapabilities,
            state::StartedAt, 0, false
        );
    }

    function CompleteHandshake(
        state : HandshakeState,
        timestamp : Int
    ) : HandshakeState {
        return HandshakeState(
            PhaseComplete(), state::NodeId, state::PeerNodeId,
            state::Nonce, state::PeerNonce, state::SharedSecret,
            state::Capabilities, state::PeerCapabilities,
            state::StartedAt, timestamp, true
        );
    }

    function FailHandshake(state : HandshakeState) : HandshakeState {
        return HandshakeState(
            PhaseFailed(), state::NodeId, state::PeerNodeId,
            state::Nonce, state::PeerNonce, 0,
            state::Capabilities, state::PeerCapabilities,
            state::StartedAt, 0, false
        );
    }

    function HandshakeDuration(state : HandshakeState) : Int {
        if state::CompletedAt > 0 {
            return state::CompletedAt - state::StartedAt;
        }
        return 0;
    }

    // =========================================================================
    // Session Multiplexer
    // =========================================================================

    newtype MultiplexerState = (
        Registry       : SessionRegistry,
        ActiveHandshakes : HandshakeState[],
        AuthTokens     : AuthToken[],
        TotalConnections : Int,
        FailedConnections : Int,
        LastCleanup    : Int
    );

    function InitMultiplexer(
        maxSessions : Int,
        timestamp : Int
    ) : MultiplexerState {
        return MultiplexerState(
            InitSessionRegistry(maxSessions, timestamp),
            new HandshakeState[0],
            new AuthToken[0],
            0, 0, timestamp
        );
    }

    function StartHandshake(
        mux : MultiplexerState,
        nodeId : String,
        nonce : Int,
        capabilities : Int[],
        timestamp : Int
    ) : MultiplexerState {
        let handshake = InitHandshake(nodeId, nonce, capabilities, timestamp);
        return MultiplexerState(
            mux::Registry,
            mux::ActiveHandshakes + [handshake],
            mux::AuthTokens,
            mux::TotalConnections + 1,
            mux::FailedConnections,
            mux::LastCleanup
        );
    }

    operation CompleteConnection(
        mux : MultiplexerState,
        sessionId : String,
        nodeId : String,
        peerAddress : String,
        token : AuthToken,
        timestamp : Int
    ) : MultiplexerState {
        let session = OpenSession(sessionId, nodeId, peerAddress, timestamp);
        let registry = AddSession(mux::Registry, session, timestamp);
        let registry2 = RegisterNode(
            registry,
            CreateNodeRegistration(nodeId, NodeTypeWindows(), peerAddress, 0, new Int[0], timestamp)
        );
        return MultiplexerState(
            registry2,
            mux::ActiveHandshakes,
            mux::AuthTokens + [token],
            mux::TotalConnections,
            mux::FailedConnections,
            mux::LastCleanup
        );
    }

    function DisconnectSession(
        mux : MultiplexerState,
        sessionId : String,
        timestamp : Int
    ) : MultiplexerState {
        let registry = RemoveSession(mux::Registry, sessionId, timestamp);
        return MultiplexerState(
            registry,
            mux::ActiveHandshakes,
            mux::AuthTokens,
            mux::TotalConnections,
            mux::FailedConnections,
            mux::LastCleanup
        );
    }

    function CleanupExpiredSessions(
        mux : MultiplexerState,
        currentTimestamp : Int,
        timeoutMs : Int
    ) : MultiplexerState {
        mutable activeSessions = new SessionState[0];
        mutable removed = 0;
        for s in mux::Registry::Sessions {
            if not DetectSessionTimeout(s, currentTimestamp, timeoutMs) {
                set activeSessions += [s];
            } else {
                set removed += 1;
            }
        }

        let registry = SessionRegistry(
            activeSessions, mux::Registry::Nodes,
            mux::Registry::TotalSessions,
            mux::Registry::ActiveSessions - removed,
            mux::Registry::MaxSessions,
            mux::Registry::CreatedAt, currentTimestamp
        );

        if removed > 0 {
            Message($"[SessionManager] Cleaned up {removed} expired sessions");
        }

        return MultiplexerState(
            registry,
            mux::ActiveHandshakes,
            mux::AuthTokens,
            mux::TotalConnections,
            mux::FailedConnections,
            currentTimestamp
        );
    }

    function GetMultiplexerStats(mux : MultiplexerState) : (Int, Int, Int, Int) {
        return (
            mux::Registry::ActiveSessions,
            Length(mux::Registry::Nodes),
            mux::TotalConnections,
            mux::FailedConnections
        );
    }

    // =========================================================================
    // Load Balancing
    // =========================================================================

    function SelectLeastLoadedNode(
        registry : SessionRegistry,
        nodeType : Int,
        currentTimestamp : Int,
        timeoutMs : Int
    ) : (Bool, NodeRegistration) {
        let candidates = GetNodeByType(registry, nodeType);
        let alive = Filtered(n -> IsNodeAlive(n, currentTimestamp, timeoutMs), candidates);

        if Length(alive) == 0 {
            return (false, CreateNodeRegistration("", 0, "", 0, new Int[0], 0));
        }

        // Select node with fewest sessions
        mutable bestNode = alive[0];
        mutable minSessions = alive[0]::SessionCount;

        for node in alive {
            if node::SessionCount < minSessions {
                set minSessions = node::SessionCount;
                set bestNode = node;
            }
        }

        return (true, bestNode);
    }

    function SelectNodeByCapability(
        registry : SessionRegistry,
        requiredCapability : Int,
        currentTimestamp : Int,
        timeoutMs : Int
    ) : (Bool, NodeRegistration) {
        let alive = GetAllActiveNodes(registry, currentTimestamp, timeoutMs);
        mutable candidates = new NodeRegistration[0];

        for node in alive {
            for cap in node::Capabilities {
                if cap == requiredCapability {
                    set candidates += [node];
                }
            }
        }

        if Length(candidates) == 0 {
            return (false, CreateNodeRegistration("", 0, "", 0, new Int[0], 0));
        }

        return (true, candidates[0]);
    }

    // =========================================================================
    // Logging Operations
    // =========================================================================

    operation LogNodeRegistered(node : NodeRegistration) : Unit {
        let typeStr = if node::NodeType == NodeTypeWindows() { "Windows" }
                      elif node::NodeType == NodeTypeLinux() { "Linux" }
                      elif node::NodeType == NodeTypeMAIA() { "MAIA-300" }
                      elif node::NodeType == NodeTypeEdge() { "Edge" }
                      else { "Firefox" };
        Message($"[SessionManager] Node registered: {node::NodeId} " +
                $"type={typeStr} addr={node::Address}:{node::Port}");
    }

    operation LogSessionCreated(session : SessionState) : Unit {
        Message($"[SessionManager] Session created: {session::SessionId} " +
                $"node={session::NodeId} peer={session::PeerAddress}");
    }

    operation LogSessionClosed(sessionId : String, reason : String) : Unit {
        Message($"[SessionManager] Session closed: {sessionId} reason={reason}");
    }

    operation LogHandshakeComplete(state : HandshakeState) : Unit {
        Message($"[SessionManager] Handshake complete: {state::NodeId} ↔ {state::PeerNodeId} " +
                $"duration={HandshakeDuration(state)}ms");
    }

    operation LogHandshakeFailed(state : HandshakeState, reason : String) : Unit {
        Message($"[SessionManager] Handshake failed: {state::NodeId} ↔ {state::PeerNodeId} " +
                $"reason={reason}");
    }

    operation LogMultiplexerStats(mux : MultiplexerState) : Unit {
        let (active, nodes, total, failed) = GetMultiplexerStats(mux);
        Message($"[SessionManager] active={active} nodes={nodes} " +
                $"total={total} failed={failed}");
    }

    operation LogAuthTokenIssued(token : AuthToken) : Unit {
        Message($"[Auth] Token issued: {token::TokenId} node={token::NodeId} " +
                $"expires={token::ExpiresAt}");
    }

    operation LogAuthTokenRevoked(tokenId : String) : Unit {
        Message($"[Auth] Token revoked: {tokenId}");
    }
}