# Grok plan v2 (gerçek ölçümlere göre)

The current score is already past the old 3.94M baseline. At 724359 Toffolis × 1229 qubits ≈ 8.902e8, a 1% win is anything under ~8.81e8 and a 3% win is under ~8.63e8. Width is the better first lever: same Toffolis at 1200 qubits is already ~2.4% better, so that cut wins if Toffolis rise by less than 2.4%. At 1220 the Toffoli budget is only +0.7%; at 1180 it is +4.2%. A Toffoli-only 1% needs ~7.2k fewer gates. Multiply is ~368k (51%) and divide ~357k (49%), so a 2% multiply cut is about a 1% score cut. Square (~36k) cannot move the score 1% by itself.

Do not edit frozen tables or anything upstream of `bind81_followup.txt`, `qstep87_*.txt`, `armi94_followup.txt`, `sq_leader.zst`, or `frozen_stack.hnk`. A knob that changes the op stream can make those tables miss silently. After each run, require 9024/9024 and an unchanged frozen-apply count in the log.

**1. Joint pin sweep (highest probability, lowest risk).** Peak 1229 is a cap hit in divide, square, and multiply, so lowering only one pin does nothing. Sweep `HEO_PIN_PP_WALK_MAX_QUBITS` and `LF_SQUARE_CAP` together, plus any other `1229` that `rg -n 1229 src/point_add` finds in `env_raw()` / `bind81_recipe.txt`. Try 1224, 1216, 1208, 1200, 1184, 1168. Keep a point only if `new_toffoli/724359 < 1229/new_qubits`. Stop when the build fails or Toffoli inflation exceeds that ratio. Expectation: 1–2% if 1229 is a round cap; ~0 if it is the true minimum live width.

**2. Multiply profile neighbors (medium probability).** In `env_raw()`, try only adjacent `I12_MUL_PROFILE` values already named in `src/point_add/memory/` or comments. Do not invent profiles. Multiply is the largest Toffoli bucket and a legal neighbor is usually a width/Toffoli retune, not a new op-stream shape. Keep a profile only if the frozen-apply log is unchanged and the iso-score test above passes. A 2% multiply drop at 1229 is ~1% score; combined with a 16-qubit pin drop it can reach ~2%.

**3. Do not lead with divide or `I41_ROUNDS`.** Same size lever as multiply, but more likely to sit under the frozen edit keys. Touch `I12_DIV_PROFILE` only after (1) and (2) stall, one adjacent value at a time, same accept test.

**4. Measurement uncompute only if a multiply uncompute is still unitary Toffolis.** The harness already rewards skipped Toffolis via HMR, and uncompute is often ~half of multiply. Reuse the existing HMR helper; do not add phase-kickback CZ by hand. Accept only if the reverse-pass check is clean and non-output qubits are |0>. This is the only item that can beat 3%, and the easiest way to fail correctness.

```bash
# Linux/sandbox: benchmark.sh needs bubblewrap (not native macOS).
# If env is ignored, sed the same keys in the recipe, benchmark, then restore.
rg -n "1229|HEO_PIN_PP_WALK_MAX_QUBITS|LF_SQUARE_CAP" src/point_add
for q in 1224 1216 1208 1200 1184 1168; do
  HEO_PIN_PP_WALK_MAX_QUBITS=$q LF_SQUARE_CAP=$q \
    ./benchmark.sh --note "pin sweep q=$q"
done
```
