# Siamese Twin AI — Module 01 `majorana_phase_shift.arm64.asm`
## Code Review & Validation Report

**Project:** Siamese Twin AI — Microsoft WebTransport 5B
**Module:** 01_majorana_inference
**Date:** 2026-10-15

---

## TL;DR

The kernel's **math structure is correct** (unitarity, round-trip, purity, identity formula all verified by a C reference). But the original assembly had **7 bugs** — including an ABI violation that would silently corrupt registers and an unencodable immediate that won't even assemble. A corrected, annotated version is provided in `majorana_phase_shift_fixed.arm64.s`.

---

## Bugs found & fixed

| # | Severity | Bug | Consequence | Fix |
|---|----------|-----|-------------|-----|
| 1 | **Critical** | Uses `v8`–`v15` without saving. Per AAPCS64 / Apple ABI, the lower 64 bits of `v8`–`v15` are **callee-saved**. | Silent corruption of caller's floating-point state → intermittent wrong results / crashes. | Rewrote to use **only volatile** `v0`–`v7` and `v16`–`v31`. |
| 2 | **Critical (build)** | `fmov s15, #0.70710678` — `1/√2` is **not encodable** as an `fmov` immediate (only a restricted set of values is). | **Assembler error** — file does not build. | Load `1/√2` from the constant table (`v28`). |
| 3 | **Critical (build)** | `_compute_phase_angles_neon` declared `.global` but **never defined**. | **Linker error** (`undefined symbol`). | Implemented: `phi[j] = omega[j]*t`, reduced to `[-π,π]`. |
| 4 | **High (precision)** | Taylor sin/cos truncated at cos→φ⁶, sin→φ⁷ with **no range reduction**. | Up to **21% error** on cos at |φ|≈π (measured). Inference drift. | Added `frintn`-based range reduction to `[-π,π]` **and** extended polynomials to cos→φ¹⁰, sin→φ¹¹. Measured worst-case error now **0.18%** (cos) / **0.04%** (sin) over `[-20,20]`. |
| 5 | **Medium** | In `_majorana_phase_shift_neon`, `adrp`/`add` for constants executed **inside the loop** every iteration. | Performance: unnecessary address arithmetic per 4 elements. | All 13 constants loaded **once** into `v16`–`v28` before the loop (via `L_load_constants`). |
| 6 | **Medium** | `dim` required to be a multiple of 4; remainder silently ignored. | Last `dim%4` elements unprocessed. | Scalar tail loop added to every kernel. |
| 7 | **Low (correctness)** | Pointer writeback pattern inconsistent (post-index on ψ load would misalign stores). | Would store to wrong offsets if both load & store used writeback. | Enforced: ψ loads use **no writeback**; stores do the writeback. φ loads (read-only) use post-index. |

---

## Validation (C reference, `majorana_test.c`)

Compiled with `gcc -O2` on x86_64. Results:

```
Test A — Taylor sin/cos vs libm (original poly, tol=1e-3):
  poly_sin max error = 7.52e-02   [FAIL]   ← original precision bug
  poly_cos max error = 2.11e-01   [FAIL]   ← 21% error at |φ|≈π

Test B — U(φ) unitary (norm preserved):                 [PASS]
Test C — U(φ)·U(-φ) = identity (round-trip):            [PASS]  delta 2.4e-7
Test D — purity of normalized state = 1.0:              [PASS]
Test E — |Ψ> = (|Edge>+conj|Chrome>)/√2:                [PASS]  (6/6 lanes)
```

Fixed-polynomial precision check (`prec_check.c`), x ∈ [-20,20]:
```
max cos err = 1.83e-03   max sin err = 4.45e-04   (both < 0.2%)
```

---

## Notes

- **Target:** The corrected file uses **Mach-O / Apple Silicon** syntax (`@PAGE`/`@PAGEOFF`, `__TEXT`/`__const`, leading underscores). ELF/Linux-AArch64 porting instructions are in the footer of the `.s` file.
- **Could not assemble on this VM** (no clang/aarch64 cross-toolchain; apt install timed out). The corrected file was carefully hand-checked; recommend running `clang --target=arm64-apple-macosx -c majorana_phase_shift_fixed.arm64.s` once to confirm zero warnings.
- **For best accuracy** in production, if phase angles can grow beyond ±π, consider a proper octant range-reduction (reduce to ±π/4) or call `sinf`/`cosf` from a vectorized libm; the current fix is a good balance of speed vs. accuracy.
- `compute_phase_angles_neon` signature: `(const float* omega, float t, float* phi, int dim)` — under AAPCS64, `omega` arrives in **x0**, `t` in **s0**, `phi` in **x1**, and `dim` in **w2**.

---

## Files delivered

| File | Purpose |
|------|---------|
| `majorana_phase_shift_fixed.arm64.s` | Corrected, annotated ARM64 NEON kernels (all 4 symbols) |
| `majorana_test.c` | C reference + test harness (compile: `gcc -O2 majorana_test.c -lm -o test && ./test`) |
| `REVIEW.md` | This report |
