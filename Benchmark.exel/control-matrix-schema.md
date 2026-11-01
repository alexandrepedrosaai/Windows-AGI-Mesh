# Control Matrix Schema (`_M365TenantintraID_MCPControl.xlsx`)

## Sheet

The matrix lives on the first worksheet (any sheet name). Header row = row 1. One tenant per row.

## Required columns

| Column | Type | Rules |
|---|---|---|
| `IntraID` | string | Primary key. Required, non-empty, unique across rows. |
| `TenantId` | GUID | Entra ID tenant ID. Must match `^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$`. |
| `PrimaryDomain` | string | Verified domain. Required. Lowercase. |
| `DisplayName` | string | Required. |
| `McpServerMode` | enum | `stdio` or `http` (case-insensitive). Required. |
| `McpEndpoint` | string | For `stdio`: path to the MCP server `.dll` (or `dotnet` + project). For `http`: full URL (`http(s)://host:port/…`, SSE endpoint). Required. |
| `RuntimeVersion` | string | Required. Expected `10.0.13` (win-x64). Must be a valid SemVer-ish `MAJOR.MINOR.PATCH`. |

## Optional columns

| Column | Type | Purpose |
|---|---|---|
| `Owner` | string | Team or person responsible for the tenant. |
| `Environment` | enum | `prod`, `preprod`, `test`, `dev`, `sandbox`. |
| `Region` | string | e.g. `BR-South`, `US-East`, `EU-West`. |
| `Enabled` | bool | `yes/no` or `true/false`. If `no/false`, skip this tenant for operations unless explicitly targeted. |
| `Scopes` | string | Comma-separated MCP tool scopes allowed (e.g. `user.read,group.readwrite`). If present, restrict tool calls to listed scopes. |
| `Notes` | string | Free text. |
| `AuditLog` | string | Append-only. See format below. |

Extra columns are allowed and preserved. The validator warns on unrecognized columns but does not fail.

## AuditLog format

Append one line per change, separated by ` | ` (pipe with spaces):

```
YYYY-MM-DD HH:MM:SS (UTC) | <agent-or-user> | <verb> <object-id> | <result> | <short note>
```

Example:

```
2026-10-22 19:30:00 (UTC) | ChinCopilot | create user john.doe@contoso.onmicrosoft.com | success | onboarding ticket #4521
```

Never overwrite existing AuditLog content; always append.

## Validation

Run `scripts/validate_control_matrix.py <xlsx>`. Exit code `0` = valid, `1` = errors, `2` = warnings only. Use `--json` to emit resolved tenant rows as JSON for downstream scripting.
