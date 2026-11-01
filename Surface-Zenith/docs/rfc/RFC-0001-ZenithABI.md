# RFC-0001: Zenith Universal ABI (ZUABI)

**Status:** Draft  
**Version:** 0.1.0  
**Authors:** Surface Zenith Architecture Team  
**Date:** 2026-10-23

---

## Abstract

This RFC defines the Zenith Universal Application Binary Interface (ZUABI) — the foundational contract layer of the Surface Zenith OS. Applications compile against ZUABI rather than Win32 or Android Framework, enabling transparent execution across all Zenith domains.

## Motivation

Traditional operating systems bind applications to a specific runtime:
- Win32 applications require Windows
- Android applications require the Android Runtime (ART)

This creates the fundamental incompatibility that prevents a single device from being both a phone and a full PC. The ZUABI eliminates this boundary by providing a single compilation target that abstracts all domain-specific runtimes.

## Specification

### 1. Core Types

All IDs are 128-bit UUIDs (RFC 4122 v4):

```
ZSessionId  = UUID
ZTaskId     = UUID
ZObjectId   = UUID
ZDomainId   = UUID
ZIdentityId = UUID
ZMessageId  = UUID
```

### 2. Domain Enumeration

```
Domain ::= Android | Windows | AI | Quantum | RealTime | Cloud | Custom(String)
```

### 3. Capability Token Format

```
CapabilityToken {
    id:          UUID,
    subject:     ZIdentityId,
    session:     ZSessionId,
    issuer:      Domain,
    audience:    [Domain],
    permissions: [Permission],
    issued_at:   Timestamp,
    expires_at:  Timestamp?,
    signature:   [u8; 32],  // HMAC-SHA256
}
```

### 4. Universal Memory Object

```
UMO {
    id:         ZObjectId,
    name:       String,
    kind:       UmoKind,
    session:    ZSessionId,
    pages:      [MemoryPage],
    version:    u64,
    write_lock: Domain?,
}
```

### 5. ABI Stability Guarantee

ZUABI follows semantic versioning. Minor version increments are backward-compatible. Major version increments require migration.

## Security Considerations

All cross-domain operations require a valid, unexpired CapabilityToken. Tokens are cryptographically signed by the Security Broker and verified by the microkernel on every operation.

## References

- RFC 4122: UUID specification
- ARM64 ABI specification
- seL4 capability model
