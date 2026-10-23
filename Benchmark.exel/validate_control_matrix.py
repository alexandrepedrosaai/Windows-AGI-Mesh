#!/usr/bin/env python3
"""Validate the _M365TenantintraID_MCPControl.xlsx control matrix.

Usage:
    python3 validate_control_matrix.py <path-to-xlsx> [--json] [--sheet NAME]

Exit codes: 0 = valid, 1 = errors, 2 = warnings only.
"""
import argparse
import json
import re
import sys

try:
    import openpyxl
except ImportError:
    print("ERROR: openpyxl is required. Install with: pip install openpyxl", file=sys.stderr)
    sys.exit(1)

REQUIRED = ["IntraID", "TenantId", "PrimaryDomain", "DisplayName",
            "McpServerMode", "McpEndpoint", "RuntimeVersion"]
OPTIONAL = {"Owner", "Environment", "Region", "Enabled", "Scopes", "Notes", "AuditLog"}
GUID_RE = re.compile(r"^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$")
VER_RE = re.compile(r"^\d+\.\d+\.\d+$")
MODES = {"stdio", "http"}


def norm(s):
    return str(s).strip() if s is not None else ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("xlsx")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--sheet", default=None)
    args = ap.parse_args()

    errors, warnings, tenants = [], [], []
    try:
        wb = openpyxl.load_workbook(args.xlsx, read_only=True, data_only=True)
    except Exception as e:
        print(f"ERROR: cannot open workbook: {e}", file=sys.stderr)
        sys.exit(1)

    ws = wb[args.sheet] if args.sheet else wb.worksheets[0]
    rows = list(ws.iter_rows(values_only=True))
    if not rows:
        print("ERROR: sheet is empty", file=sys.stderr)
        sys.exit(1)

    header = [norm(c) for c in rows[0]]
    col = {name: i for i, name in enumerate(header) if name}

    missing = [c for c in REQUIRED if c not in col]
    if missing:
        errors.append(f"missing required columns: {', '.join(missing)}")

    unknown = [c for c in col if c not in REQUIRED and c not in OPTIONAL]
    if unknown:
        warnings.append(f"unrecognized columns (preserved): {', '.join(unknown)}")

    seen_intra = {}
    for rnum, row in enumerate(rows[1:], start=2):
        def get(name):
            i = col.get(name)
            return norm(row[i]) if i is not None and i < len(row) else ""

        for name in REQUIRED:
            if not get(name):
                errors.append(f"row {rnum}: empty {name}")
        intra = get("IntraID")
        if not intra:
            continue
        intra_key = intra.lower()
        if intra_key in seen_intra:
            errors.append(f"row {rnum}: duplicate IntraID '{intra}' (also row {seen_intra[intra_key]})")
        else:
            seen_intra[intra_key] = rnum

        tid = get("TenantId")
        if tid and not GUID_RE.match(tid):
            errors.append(f"row {rnum} ({intra}): invalid TenantId '{tid}'")

        mode = get("McpServerMode").lower()
        if mode and mode not in MODES:
            errors.append(f"row {rnum} ({intra}): invalid McpServerMode '{mode}' (expected stdio/http)")

        ep = get("McpEndpoint")
        if mode == "http" and ep and not re.match(r"^https?://", ep):
            warnings.append(f"row {rnum} ({intra}): http McpEndpoint does not start with http(s)://")
        if mode == "stdio" and ep and not ep.lower().endswith((".dll", ".csproj", ".exe")):
            warnings.append(f"row {rnum} ({intra}): stdio McpEndpoint is not a .dll/.csproj/.exe path")

        ver = get("RuntimeVersion")
        if ver and not VER_RE.match(ver):
            errors.append(f"row {rnum} ({intra}): invalid RuntimeVersion '{ver}' (expect MAJOR.MINOR.PATCH)")
        elif ver and ver != "10.0.13":
            warnings.append(f"row {rnum} ({intra}): RuntimeVersion '{ver}' != expected 10.0.13")

        enabled = get("Enabled").lower()
        if enabled and enabled not in ("yes", "true", "no", "false", ""):
            warnings.append(f"row {rnum} ({intra}): Enabled '{enabled}' not yes/no/true/false")

        tenants.append({c: get(c) for c in col if c not in OPTIONAL or get(c)})

    if args.json:
        print(json.dumps({"valid": not errors, "errors": errors,
                          "warnings": warnings, "tenants": tenants}, indent=2))
    else:
        for e in errors:
            print("ERROR:", e)
        for w in warnings:
            print("WARN :", w)
        print(f"\n{len(tenants)} tenant row(s), {len(errors)} error(s), {len(warnings)} warning(s).")

    if errors:
        sys.exit(1)
    if warnings:
        sys.exit(2)
    sys.exit(0)


if __name__ == "__main__":
    main()
