# M365 MCP Operations Catalog

Read this file only when you need tool-level detail for an operation. Tool names follow the Microsoft Graph MCP server conventions; the .NET MCP server in this skill exposes equivalent tools. Always verify actual tool names via `initialize`/`tools/list` on the resolved MCP server before calling.

## Identity & users

| Operation | Typical tool | Key parameters | Notes |
|---|---|---|---|
| List users | `users_list` | `$filter`, `$top`, `$select` | Prefer server-side `$filter` by UPN/domain. |
| Get user | `users_get` | `userId` (id or UPN) | |
| Create user | `users_create` | `displayName`, `userPrincipalName`, `passwordProfile`, `accountEnabled` | Force password change on first login. |
| Update user | `users_update` | `userId`, patch fields | Only send changed fields. |
| Delete user | `users_delete` | `userId` | Soft-delete; recoverable for 30 days. |
| Restore deleted user | `directory_deletedItems_restore` | `id` | |
| Reset password | `users_authentication_methods_reset` or `users_update` + `passwordProfile` | Requires admin role; force change at next sign-in. |

## Groups & licensing

| Operation | Typical tool | Key parameters | Notes |
|---|---|---|---|
| List/get/create/update/delete group | `groups_*` | `displayName`, `mailEnabled`, `securityEnabled`, `groupTypes` | M365 group = `groupTypes: ["Unified"]`. |
| Add/remove member | `groups_members_*` | `groupId`, `userId` | |
| Assign license | `users_assignLicense` | `userId`, `addLicenses:[{skuId}]`, `removeLicenses:[]` | Resolve `skuId` via `subscribedSkus_list`. |
| Disable service plan | `users_assignLicense` with `disabledPlans` | | Never remove a license just to disable a plan. |

## Workloads

- **Exchange Online**: mailbox settings, `inferenceClassification`, retention, transport rules via `users`/`mailboxSettings` tools.
- **SharePoint Online**: `sites_*`, `drives_*` for sites/lists/files; sharing links via `driveItem_createLink`.
- **Teams**: `teams_*`, `channels_*`, `teams_apps_*`; policies via Graph `/teamwork`.

## Security & governance

- Conditional access: `identity_conditionalAccess_policies_*` (read by default; write = destructive-class, confirm first).
- Audit/sign-in logs: `auditLogs_signIns_list`, `auditLogs_directoryAudits_list` — filter by `createdDateTime` and `userPrincipalName`.
- Risky users: `identityProtection_riskyUsers_list`.

## Reporting

- License/compliance: `reports_*` (e.g. `getOffice365ActiveUserDetail`, `getOneDriveUsageStorage`).
- Inactive users: filter `users_list` by `lastSignInDateTime` (requires `signInActivity` select).
- Guest inventory: `$filter=userType eq 'Guest'`.

## Common pitfalls

1. **Throttling**: Graph returns `429`. Respect `Retry-After`; batch with `$top` and `$select`.
2. **UPN vs Id**: Many tools accept both; when in doubt resolve UPN → `id` first.
3. **Bulk writes**: Use JSON batching (`/$batch`) for >5 operations; never sequential awaits in a tight loop.
4. **Delegated vs app-only**: The MCP server's auth mode determines reachable APIs. If a call returns `403`, check `Scopes` column in the matrix.
5. **Multi-tenant**: Always pass the resolved tenant's authority (`https://login.microsoftonline.com/<TenantId>`) when the MCP server is app-only.
