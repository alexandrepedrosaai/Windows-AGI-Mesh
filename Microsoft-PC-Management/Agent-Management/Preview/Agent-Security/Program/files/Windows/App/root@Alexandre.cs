OpenClaw 2026.9.6 (eb377ac) — All your chats, one OpenClaw.

Usage: openclaw [options] [command]

Options:
  --container <name>   Run the CLI inside a running Podman/Docker container named <name> (default: env
                       OPENCLAW_CONTAINER)
  --dev                Dev profile: isolate state under ~/.openclaw-dev, default gateway port 19001, and shift
                       derived ports (browser/canvas)
  -h, --help           Display help for command
  --log-level <level>  Global log level override for file + console (silent|fatal|error|warn|info|debug|trace)
  --no-color           Disable ANSI colors
  --profile <name>     Use a named profile (isolates OPENCLAW_STATE_DIR/OPENCLAW_CONFIG_PATH under
                       ~/.openclaw-<name>)
  -V, --version        output the version number

Commands:
  Hint: commands suffixed with * have subcommands. Run <command> --help for details.
  acp *                Run an ACP bridge backed by the Gateway
  agent *              Run an agent turn via the Gateway (use --local for embedded)
  agents *             Manage isolated agents (workspaces + auth + routing)
  approvals *          Manage approval policy and pending requests
  attach               Attach Claude Code to a gateway session with scoped MCP tools
  audit                Inspect activity records and exact-run identity context
  automations *        Manage automations (alias for cron)
  backup *             Create, verify, and restore backup archives and SQLite snapshots
  browser *            Manage OpenClaw's dedicated browser (Chrome/Chromium)
  capability *         Run provider capability commands (fallback alias: infer)
  channels *           Manage connected chat channels and accounts
  chat                 Open a local terminal UI (alias for tui --local)
  clawbot *            Legacy clawbot command aliases
  completion           Generate shell completion script
  config *             Non-interactive config helpers (get/set/patch/unset/file/schema/validate). Run without
                       subcommand for guided setup.
  configure            Interactive configuration for credentials, channels, gateway, and agent defaults
  connect              Connect this machine to an OpenClaw Gateway as a node
  cron *               Manage automations (via Gateway)
  daemon *             Manage the Gateway service (launchd/systemd/schtasks)
  dashboard            Open the Control UI with your current token
  database *           Inspect database schema compatibility and shared-state write ownership
  devices *            Device pairing and auth tokens (for mobile app setup codes, use `openclaw qr` instead)
  directory *          Lookup contact and group IDs (self, peers, groups) for supported chat channels
  dns *                DNS helpers for wide-area discovery (Tailscale + CoreDNS)
  docs                 Search the live OpenClaw docs
  doctor               Health checks + quick fixes for the gateway and channels
  exec-approvals *     Manage exec approvals (alias for approvals)
  exec-policy *        Show or synchronize requested exec policy with host approvals
  file-transfer *      Review file-transfer standing approvals
  fleet *              Provision and manage isolated tenant cells (experimental)
  gateway *            Run, inspect, and query the WebSocket Gateway
  health               Fetch health from the running gateway
  help                 Display help for command
  hooks *              Manage internal agent hooks
  infer *              Run provider-backed inference commands through a stable CLI surface
  logs                 Tail gateway file logs via RPC
  mcp *                Manage OpenClaw mcp.servers config and channel bridge
  memory *             Search, inspect, and reindex memory files
  message *            Send, read, and manage messages and channel actions
  migrate *            Import state from another agent system
  models *             Model discovery, scanning, and configuration
  node *               Run and manage the headless node host service
  nodes *              Manage gateway-owned nodes (pairing, status, invoke, and media)
  onboard *            Guided setup for auth, models, Gateway, workspace, channels, and skills
  pairing *            Secure DM pairing (approve inbound requests)
  plugins *            Manage OpenClaw plugins and extensions
  promos *             Discover and claim promotional model offers from ClawHub
  proxy *              Run the OpenClaw debug proxy and inspect captured traffic
  qr                   Generate a mobile pairing QR code and setup code
  reset                Reset local config/state (keeps the CLI installed)
  resume               Resume a recent Gateway session in the TUI
  sandbox *            Manage sandbox containers (Docker-based agent isolation)
  secrets *            Secrets runtime controls
  security *           Audit local config and state for common security foot-guns
  sessions *           List stored conversation sessions
  setup                Chat with OpenClaw; onboard when setup is incomplete
  skills *             List and inspect available skills
  status               Show channel health and recent session recipients
  system *             System tools (events, heartbeat, presence)
  tasks *              Inspect durable background tasks and TaskFlow state
  telemetry *          Inspect and manage anonymous usage telemetry
  terminal             Open a local terminal UI (alias for tui --local)
  transcripts *        Inspect stored transcripts
  triage               Collect sanitized diagnostics and open a local coding agent for repair
  tui                  Open a terminal UI connected to the Gateway
  uninstall            Uninstall the gateway service + local data
  update *             Update OpenClaw and inspect update channel status
  users *              Manage durable user profiles and email aliases
  webhooks *           Webhook helpers and integrations
  worker               Run the restricted cloud worker runtime
  worktrees *          Create, inspect, restore, and clean up managed worktrees

Examples:
  openclaw onboard
    Run guided setup for a local Gateway, workspace, auth, and channels.
  openclaw setup
    Create the baseline config, workspace, and session folders.
  openclaw configure
    Change models, Gateway, channels, plugins, skills, and health checks.
  openclaw status
    Check Gateway, channel, model, and recent-session status.
  openclaw doctor --fix
    Repair common config, service, plugin, and channel problems.
  openclaw channels add
    Add or update a chat channel account with guided prompts.
  openclaw channels status
    See connected messaging accounts and login state.
  openclaw --dev gateway
    Run a dev Gateway (isolated state/config) on ws://127.0.0.1:19001.
  openclaw gateway run --force
    Start the Gateway and replace anything bound to its port.
  openclaw models status
    Show model/provider auth health before running agents.
  openclaw plugins list
    Inspect enabled, disabled, and installed plugins.
  openclaw agent --to +15555550123 --message "Run summary" --deliver
    Run one agent turn through the Gateway and optionally deliver the reply.
  openclaw message send --channel telegram --target @mychat --message "Hi"
    Send via your Telegram bot.

Docs: docs.openclaw.ai/cli

root@Alexandre:~#
