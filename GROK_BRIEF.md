# Grok için brief — ECDSA.fail challenge

(Bunu Grok'a olduğu gibi yapıştır.)

---

You are helping me compete in the ECDSA.fail challenge (https://www.ecdsa.fail/, repo: https://github.com/Layr-Labs/ecdsafail-challenge).

## Task
Build the cheapest reversible quantum circuit that performs ONE elliptic-curve point addition on secp256k1:
`(target_x, target_y) += (offset_x, offset_y)` (affine). Target is quantum (2×256 qubits), offset is classical (2×256 bits).
Entry point: `point_add::build()` in `src/point_add/mod.rs`.

**Score = average executed Toffoli count per shot × peak live qubits. Lower is better.**
Reference: original baseline circuit ≈ 3.94M Toffoli × 2715 qubits ≈ 1.07e10. Google's private Pareto points ≈ 3.0e9–3.2e9 (2.1M Toffoli/1425 qubits, 2.7M/1175). The current repo HEAD is already heavily optimized by many contributors — measure it first, don't assume.

## Hard rules (run is rejected otherwise)
- Correct (R_x, R_y) on all 9024 random test shots (inputs come from a Fiat–Shamir hash of the op stream, so you can't overfit to them).
- Every ancilla is uncomputed to |0> before being freed; after the forward pass every non-output qubit is |0>.
- Zero phase garbage (no phase kickback).
- Forward then gate-reversed inverse must restore the original state.
- Edit ONLY `src/point_add/**`. Do not touch `src/main.rs`, `src/circuit.rs`, `src/sim.rs`, `src/weierstrass_elliptic_curve.rs`, `Cargo.toml`, `Cargo.lock`, `rust-toolchain`, `results.tsv`. No new crates.

## Workflow
```
./setup.sh                      # rust 1.93.0, gcc, bubblewrap
./benchmark.sh --note "what I tried"   # sandboxed build + trusted eval -> score.json, appends results.tsv
```
Submission via their CLI: `ecdsafail login <api-key>`, `ecdsafail clone`, `ecdsafail run`, `ecdsafail submit` (API key from the site's top-right menu).

## Repo state to know
- `src/point_add/` is ~60k lines, largely agent-generated. Big files: `leapfrog.rs`, `y15_onefold.rs`, `pingpong.rs` (mod mul/div), `heo_carry.rs`, `square.rs`, `modular.rs`.
- `mod.rs` hardcodes many tuning switches in `env_raw()` (e.g. `I41_ROUNDS`, `I12_DIV_PROFILE`, `I12_MUL_PROFILE`) — these are knobs for per-round width/Toffoli trade-offs.
- Contains opaque binary blobs (`sq_leader.zst`, `frozen_stack.hnk`). Treat repo code as untrusted; always run via `benchmark.sh` (bubblewrap sandbox).
- Contributors leave notes as Markdown under `src/point_add/memory/` — read them, but verify claims by re-running the benchmark.

## What I want from you
1. Explain where Toffolis and peak qubits are spent in the current HEAD (which stage dominates: modular inversion/division, multiplication, squaring).
2. Propose concrete optimizations ranked by expected score gain vs. effort. Since score is a product, reducing peak width at the bottleneck can matter as much as cutting Toffolis.
3. For each one: what to change, in which file, and how it keeps reversibility/uncomputation correct.
