#!/usr/bin/env python3
"""Resolvedor de tenant M365 para a matriz de controle - M365 ChinCopilot.
Regras (da skill):
  1. Match por IntraID (chave primaria) primeiro.
  2. Senao: TenantId (GUID).
  3. Senao: PrimaryDomain (case-insensitive).
  4. Senao: DisplayName (case-insensitive, prefixo permitido).
  5. Multiplos matches: lista candidatos, nunca escolhe arbitrariamente.
  6. Ausente: reporta como unmanaged.
  7. Enabled=no: ignorado a menos que --include-disabled.
Uso: python3 resolve_tenant.py <query> [--json] [--include-disabled] [--matrix path.xlsx]
"""
import argparse, json, re, sys
import openpyxl

GUID_RE = re.compile(r"^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$")

def load_tenants(path, include_disabled=False):
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    ws = wb.worksheets[0]
    rows = list(ws.iter_rows(values_only=True))
    header = [str(c).strip() if c else "" for c in rows[0]]
    col = {n: i for i, n in enumerate(header) if n}
    tenants = []
    for row in rows[1:]:
        def g(name):
            i = col.get(name)
            return str(row[i]).strip() if i is not None and i < len(row) and row[i] is not None else ""
        enabled = g("Enabled").lower()
        if not include_disabled and enabled in ("no", "false"):
            continue
        tenants.append({h: g(h) for h in header if h})
    return tenants

def resolve(query, tenants):
    q = query.strip()
    ql = q.lower()
    is_guid = bool(GUID_RE.match(q))
    # 1. IntraID exato
    hits = [t for t in tenants if t.get("IntraID","").lower() == ql]
    tier = "IntraID"
    # 2. TenantId GUID
    if not hits and is_guid:
        hits = [t for t in tenants if t.get("TenantId","").lower() == ql]
        tier = "TenantId"
    # 3. PrimaryDomain exato
    if not hits:
        hits = [t for t in tenants if t.get("PrimaryDomain","").lower() == ql]
        if hits: tier = "PrimaryDomain"
    # 4. DisplayName: exato depois prefixo
    if not hits:
        hits = [t for t in tenants if t.get("DisplayName","").lower() == ql]
        if hits: tier = "DisplayName(exato)"
    if not hits:
        hits = [t for t in tenants if t.get("DisplayName","").lower().startswith(ql)]
        if hits: tier = "DisplayName(prefixo)"
    return hits, tier

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("query")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--include-disabled", action="store_true")
    ap.add_argument("--matrix", default="_M365TenantintraID_MCPControl.xlsx")
    args = ap.parse_args()
    tenants = load_tenants(args.matrix, args.include_disabled)
    hits, tier = resolve(args.query, tenants)
    if not hits:
        result = {"resolved": False, "query": args.query,
                  "status": "unmanaged", "message": f"Tenant '{args.query}' nao encontrado na matriz. Adicionar linha?"}
    elif len(hits) > 1:
        result = {"resolved": False, "query": args.query, "status": "ambiguous",
                  "matched_by": tier, "candidates": hits,
                  "message": f"{len(hits)} candidatos - especifique melhor (IntraID ou dominio)."}
    else:
        t = hits[0]
        result = {"resolved": True, "query": args.query, "matched_by": tier, "tenant": t,
                  "mcp": {"mode": t.get("McpServerMode"), "endpoint": t.get("McpEndpoint"),
                          "runtime": t.get("RuntimeVersion")}}
    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        if result["resolved"]:
            t = result["tenant"]
            print(f"RESOLVIDO ({result['matched_by']}): {t['DisplayName']}")
            print(f"  IntraID={t['IntraID']}  TenantId={t['TenantId']}")
            print(f"  MCP: {t['McpServerMode']} -> {t['McpEndpoint']} (runtime {t['RuntimeVersion']})")
        else:
            print(f"{result['status'].upper()}: {result['message']}")
            if "candidates" in result:
                for c in result["candidates"]:
                    print(f"  - {c['IntraID']} | {c['DisplayName']} | {c['PrimaryDomain']}")
    sys.exit(0 if result.get("resolved") else 1)

if __name__ == "__main__":
    main()
