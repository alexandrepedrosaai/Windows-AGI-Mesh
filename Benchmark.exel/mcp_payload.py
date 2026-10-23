#!/usr/bin/env python3
"""Gerador de payload M365 MCP - M365 ChinCopilot.
Resolve o tenant na matriz e emite a chamada MCP (ferramenta + parametros + autoridade Graph).
Nao executa - so prepara o payload (a execucao acontece no servidor MCP resolvido).
Operacoes suportadas: users_list, users_get, users_create, groups_list, groups_create,
  users_assignLicense, ca_policies_list, signins_list, active_users_report, guests_inventory
Uso: python3 mcp_payload.py <query> <operacao> [--filter ...] [--top N] [--json]
"""
import argparse, json, secrets, sys
from resolve_tenant import load_tenants, resolve

OPS = {
    "users_list": ("users_list", lambda a: {"$filter": a.filter or "", "$top": a.top or 100, "$select": "id,userPrincipalName,displayName,accountEnabled,assignedLicenses"}),
    "users_get":  ("users_get",  lambda a: {"userId": a.user or "REPLACE-WITH-UPN-OU-ID"}),
    "users_create": ("users_create", lambda a: {"displayName": a.name or "Novo Usuario", "userPrincipalName": a.upn or "novo@SEU-DOMINIO.onmicrosoft.com", "passwordProfile": {"forceChangePasswordNextSignIn": True, "password": secrets.token_urlsafe(24) + "aA1!"}, "accountEnabled": True}),
    "groups_list": ("groups_list", lambda a: {"$filter": a.filter or "", "$top": a.top or 100}),
    "groups_create": ("groups_create", lambda a: {"displayName": a.name or "Novo Grupo", "mailEnabled": False, "securityEnabled": True, "groupTypes": []}),
    "users_assignLicense": ("users_assignLicense", lambda a: {"userId": a.user or "REPLACE-WITH-UPN", "addLicenses": [{"skuId": "RESOLVER-VIA-subscribedSkus_list"}], "removeLicenses": []}),
    "ca_policies_list": ("identity_conditionalAccess_policies_list", lambda a: {"$top": a.top or 100}),
    "signins_list": ("auditLogs_signIns_list", lambda a: {"$filter": a.filter or "", "$top": a.top or 50}),
    "active_users_report": ("reports_getOffice365ActiveUserDetail", lambda a: {"period": "D30"}),
    "guests_inventory": ("users_list", lambda a: {"$filter": "userType eq 'Guest'", "$top": a.top or 100, "$select": "id,userPrincipalName,displayName,createdDateTime"}),
}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("query")
    ap.add_argument("operacao", choices=list(OPS.keys()))
    ap.add_argument("--matrix", default="_M365TenantintraID_MCPControl.xlsx")
    ap.add_argument("--filter", default=None)
    ap.add_argument("--top", type=int, default=None)
    ap.add_argument("--user", default=None)
    ap.add_argument("--name", default=None)
    ap.add_argument("--upn", default=None)
    ap.add_argument("--include-disabled", action="store_true")
    args = ap.parse_args()
    tenants = load_tenants(args.matrix, args.include_disabled)
    hits, tier = resolve(args.query, tenants)
    if not hits:
        print(json.dumps({"error": f"tenant '{args.query}' unmanaged"}, ensure_ascii=False)); sys.exit(1)
    if len(hits) > 1:
        print(json.dumps({"error": "ambiguo", "candidatos": [h["IntraID"] for h in hits]}, ensure_ascii=False)); sys.exit(1)
    t = hits[0]
    tool, param_fn = OPS[args.operacao]
    params = param_fn(args)
    scopes = t.get("Scopes", "")
    payload = {
        "tenant": {"displayName": t["DisplayName"], "intraId": t["IntraID"], "tenantId": t["TenantId"], "matched_by": tier},
        "mcp_server": {"mode": t["McpServerMode"], "endpoint": t["McpEndpoint"], "runtime": t["RuntimeVersion"]},
        "graph_authority": f"https://login.microsoftonline.com/{t['TenantId']}",
        "tool": tool,
        "params": params,
        "scopes_restricao": scopes or "(sem restricao na matriz)",
        "observacao": "Payload preparado - nao executado. Campos REPLACE-* precisam de valores reais.",
    }
    print(json.dumps(payload, indent=2, ensure_ascii=False))

if __name__ == "__main__":
    main()
