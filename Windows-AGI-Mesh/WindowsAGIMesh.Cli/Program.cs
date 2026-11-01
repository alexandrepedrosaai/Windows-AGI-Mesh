// ─────────────────────────────────────────────────────────────────────────────
// Windows AGI Mesh — CLI Entry Point
// ─────────────────────────────────────────────────────────────────────────────

using WindowsAGIMesh.Cli;

int exitCode = await CliRouter.DispatchAsync(args);

Environment.Exit(exitCode);
