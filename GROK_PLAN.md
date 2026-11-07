# Grok'un optimizasyon planı (grok-4.7)

The product gap is algorithmic, not a missed peephole. I cannot see the 45k lines or a `benchmark.sh` split, so the ranking below is conditional on a measurement you still have to take. What follows is the decision tree I would actually use, plus the reversibility constraints that will get a run rejected.

## How to read the score

At the cited points, \(T/Q\) is almost the same:

- baseline \(3.94\times10^6 / 2715 \approx 1450\)
- Google \(2.1\times10^6 / 1425 \approx 1470\), and \(2.7\times10^6 / 1175 \approx 2300\) at the narrow end

Google is not a different point on your Pareto curve. They are better on **both** axes by about \(1.9\times\). Cutting only Toffolis to 2.1M at 2715 qubits, or only width to 1425 at 3.94M Toffolis, still lands near \(5.6\times10^9\), almost \(2\times\) short of \(3\times10^9\). A 10% peephole cannot close this. You need a change that moves \(T\) and peak \(Q\) together, or a \(\sim3\times\) cut on one axis with the other held flat.

Local exchange rate near those points: \(1\%\) of \(T\) equals \(1\%\) of \(Q\). At 2715 qubits that is about 27 qubits \(\leftrightarrow\) 39k Toffolis. A width spike is never “just a few ancilla.”

“Executed per shot” is the circuit Toffoli count the simulator applies on that basis shot, including classical-offset predicates that skip ops. It is not the count of CCX gates whose quantum controls happen to be 1 (that would sit far below the 2.1M literature-scale number you quoted). Peak qubits is a high-water mark over live, not-yet-freed qubits. Ancilla counts until it is back at \(|0\rangle\) and freed.

Affine mixed addition is only this:

\[
\lambda=(y_2-y_1)\,(x_2-x_1)^{-1},\quad
x_3=\lambda^2-x_1-x_2,\quad
y_3=\lambda(x_1-x_3)-y_1
\]

with \((x_2,y_2)\) classical. That is two cheap classical-quantum subs, **one field inversion or one fused division**, one square, one quantum-quantum mul, and a few subs. Jacobian/projective does not help a single affine add: you still pay the final inversion, plus extra muls.

## Where the cost has to be

I have not measured HEAD. Structurally, for a 256-bit prime field, the split is not subtle.

**Toffolis.** Inversion/division is the dominant stage unless it has already been replaced by a tight extended-gcd loop. Two reference shapes:

- Fermat \(a^{p-2}\) on secp256k1 is 255 squarings plus a short addition chain (\(\sim\)15–30 muls). Each reversible square that must preserve its input is “compute + uncompute,” so the square circuit is paid twice per exponent bit. A schoolbook reversible square is bounded below by \(\sim n^2/2 \approx 33\text{k}\) partial-product Toffolis before reduction and before uncomputation. Even a \(4\times\) window only gets that near \(\sim8\text{–}15\text{k}\) per square direction. \(255\times 2\times 8\text{k}\) already blows past 2.1M before the surrounding mul. So a Fermat HEAD at Google’s width is implausible; a Fermat HEAD at \(\sim4\text{M}\) Toffolis and \(\sim2700\) qubits is plausible.
- Binary extended gcd / Bernstein–Yang / Kaliski almost-inverse is \(O(n)\) divsteps, each a constant number of conditional \(n\)-bit ripple adds. Order of magnitude \(0.5\text{–}1.5\text{M}\) Toffolis including cleanup of \(f,g\) and the unused coefficient, which fits inside 2.1M with one mul and one square left over. The low-qubit Google points (\(1175=512+663\), i.e. under three extra field registers) fit a packed divstep state. They do not fit “point + accumulator + 512-bit square workspace + a saved addition-chain power.”

The large, heavily knobbed `square.rs` (groups, split, `SQC_LEAF_D`, `SQC_G`, `SQC_T`) is the tell. If those knobs move the score, squaring is on a hot loop and HEAD is still Fermat-like or mul-via-squares. If they barely move it, square is the one \(\lambda^2\) and the win is in `pingpong.rs` / `leapfrog.rs`.

**Peak qubits.** The 512 coordinate qubits are live the whole time (\(x_1\) is needed after \(\lambda\) exists; \(y_1\) is needed at the end). Everything else is workspace. 2715 means about \(2200\) extra qubits \(\approx 8\) field registers held at once, or a window/table plus several registers. 1425 means about \(3.5\) extra registers total. The peak is whichever of these is co-live at the widest tick:

- inversion state \((f,g,u,v)\) or Fermat accumulator + saved powers
- square/mul scratch and reduction temps (`pingpong.rs`, `square.rs`)
- carry-lookahead ancilla (`heo_carry.rs`) if it is allocated inside that tick
- rails/pages that are reserved up front rather than freed (`a2_rails.rs`, `rail_s6.rs`, `LFF_PAGE5`)

A mul table that is live during inversion is a pure score bug, even if it saves Toffolis inside the mul.

**Process hazard before any of the edits below.** `build_generated` emits a stream, then `compose_post`, `stream_pipeline`, `frozen_stack`, and the `source_edits` tables (`bind81_followup.txt`, `qstep87_*.txt`, `armi94_followup.txt`) patch **that** stream by anchor. Those tables are not semantics-preserving under an upstream opcode change; they will mis-apply or silently no-op. Also treat `sq_leader.zst` and `frozen_stack.hnk` as untrusted and non-portable. After any generator change, regenerate or disable stream-bound patches and re-score with `benchmark.sh`. A “smarter” generator that invalidates the frozen edits can easily score worse.

## Ranked plan

### 1. Phase split, then stop guessing
**Gain:** does not change the score; prevents weeks on the wrong stage. **Effort:** low. **Files:** `mod.rs` around the `build_point_add()` call, plus whatever builds inv / mul / square.

Emit, under a local-only env flag, per-stage op counts and the running high-water qubit id. You want four numbers: Toffolis in inversion/division, in \(\lambda^2\), in the one quantum-quantum mul, and in everything else; and the high-water mark at the end of each stage. Also log whether peak is inside divstep/exponentiation, inside a square window, or inside carry lookahead.

Do not leave that instrumentation in a submitted stream (no extra X, no extra ancilla). `HEO_EMIT_ONLY` already shows the house style: stderr, then exit.

How this stays reversible: it is not on the submitted op list.

What the numbers mean:

- Square+mul \(>40\%\) of \(T\) \(\Rightarrow\) you are still on a Fermat / repeated-square inversion. Priority is item 2, not more `SQUARE_*` knobs.
- Inversion \(>70\%\) of \(T\) and peak \(\ge 2000\) \(\Rightarrow\) priority is item 3 (de-overlap) and item 4 (packed gcd), in that order.
- Peak sits in `heo_carry` or a page reservation, while arithmetic \(T\) is already \(\sim2\text{–}2.5\text{M}\) \(\Rightarrow\) item 3 alone can move you more than any arithmetic rewrite.

### 2. If the hot path is Fermat: replace it with a narrow fused division
**Expected gain:** the whole \(1.5\text{–}2\times\) on \(T\) and a large cut in \(Q\), if item 1 confirms Fermat. This is the only change I believe can reach \(3\times10^9\). **Effort:** high. **Uncertainty:** high until item 1 is done; if HEAD is already Bernstein–Yang, this item is a rewrite backward. **Files:** the inversion driver (`leapfrog.rs`, `y15_onefold.rs`, `y15_fold_core.rs`, `y15_a2.rs`) and the div entry in `pingpong.rs`. Leave `square.rs` alone until the exponentiation loop is gone.

Use a reversible binary extended gcd or Bernstein–Yang divsteps, and compute \(\lambda = dy/dx\) directly so the coefficient register **is** \(\lambda\). Do not invert and then multiply.

State to keep, and nothing else, during the loop: \(f,g\) (or the BY pair), one coefficient that will become \(\lambda\), a small iteration/sign counter, one ripple-carry bit. Target workspace \(\le 3\times256 + O(1)\) on top of the 512 coordinate qubits, i.e. peak \(\lesssim 1400\) before you add back whatever `heo_carry` insists on. Ripple-carry the conditional adds. Carry-lookahead here buys \(T\) you do not need and spends \(Q\) the product punishes.

Reversibility, the part that usually fails review:

- Divsteps are not self-inverse. Run the forward loop into \(\lambda\), copy \(\lambda\) out with CNOTs into a clean register, then uncompute the loop by gate reversal so \(f,g\) and the other coefficient return to \(|0\rangle\). That doubles divstep \(T\). Budget for it. Do not “uncompute by measuring.”
- The harness requires that the **gate-reversed** op list restore the input. No mid-circuit measurement, no feedforward, no phase kickback into the ancilla you are about to free. Classical conditions on the **offset** bits are fine, because the reversed circuit sees the same classical bits.
- Fusing \(dy\): scale the initial coefficient by the classical-quantum register \(dy\) once, reversibly, then let divsteps act on that register. After the copy-out of \(\lambda\), uncompute back through the same initial scaling. Do not allocate a second register for \(dy\cdot u\).
- Exceptional \(dx=0\) will not appear in 9024 Fiat–Shamir shots. Do not spend a flag qubit on it.

secp256k1 only enters this design in the final square and the final mul (item 5), not inside the gcd. That is a feature: special reduction stops being on the \(255\times\) path.

### 3. De-overlap the peak, even if you do not swap algorithms
**Expected gain:** up to \(\sim1.5\times\) on the product if the high-water is two workspaces co-live; much less if one workspace already dominates. Does not by itself reach Google if \(T\) stays 3.94M. **Effort:** medium, and it is the right first code change while item 1 is in flight. **Files:** `leapfrog.rs` (schedule), `a2_rails.rs`, `rail_s6.rs` (reservations), `pingpong.rs` (mul scratch lifetime), `mod.rs` caps (`HEO_PIN_PP_WALK_MAX_QUBITS`, `LF_SQUARE_CAP`, `LFA2_EMAX`, `LFF_PAGE5`).

Concrete rules:

- Serialize. The mul/square scratch must be freed to \(|0\rangle\) before the inversion allocates, and the inversion scratch must be freed before \(\lambda^2\). Peak becomes \(\max(\text{inv},\text{mul},\text{square})+512+\text{carry}\), not the sum.
- Overwrite the point. \(R_x,R_y\) replace \((x_1,y_1)\). A second live output pair is 512 qubits on the peak for no reason.
- Do not reserve the page/rail high-water up front. `LFF_PAGE5` and `RAIL_OPT_RESERVE` style reservations count toward peak even during ticks that do not use them. Allocate at the tick, free at uncompute.
- Sweep the existing caps against **product**, not against Toffolis. A cap that adds 5% Toffolis and drops 15% qubits is a win. The recipe in `bind81_recipe.txt` is in-tree; change it there so `mod.rs` stays the single installer. Re-run the full shot set: several of those flags are documented as stream-affecting, and a cap that changes opcode order will desynchronize the frozen edit tables (see the hazard above).

Reversibility: you are only moving uncompute earlier. Free a qubit only after it is \(|0\rangle\) on every basis state, which you already have to guarantee. Do not drop an uncompute because the next stage does not read the qubit; the inverse pass and the “non-output qubits are \(|0\rangle\)” rule both need it.

### 4. Narrow the carry, if item 1 says the peak is in `heo_carry.rs`
**Expected gain:** large on \(Q\) if lookahead or carry-save limbs are live across the inversion; small on \(T\) (ripple is \(\sim n\) Toffolis per add, and you have \(O(n)\) adds). **Effort:** medium. **File:** `heo_carry.rs`, called from `pingpong.rs` / the divstep adder.

For this product, the right adder during inversion is a ripple with one carry ancilla, uncomputed at the end of the add (the carry-out of a field add is consumed by the secp reduction, or is zero after reduction). Wide carry-lookahead, carry-save that is not resolved and freed inside the tick, or a second copy of the limb vector will show up as hundreds of peak qubits. Keep a wider adder only inside the one modular mul, and only if that mul is **not** the peak tick. `EXACT_PAIR_CARRY` is already on; do not disable a correctness guard to save a carry bit.

Reversibility: the carry qubit is borrowed clean, returned clean, same as any other ancilla. Do not leave a carry-save residue in a register you also read as a binary integer later; resolve, use, uncompute the residue.

### 5. Special-form reduction, only on the mul/square that remain
**Expected gain:** small if item 2 landed (reduction runs a handful of times); large if you stayed on Fermat and every squaring still does a generic Montgomery/Barrett. **Effort:** low–medium. **File:** `modular.rs`, used by `square.rs` and `pingpong.rs`.

\(p=2^{256}-2^{32}-977\), so \(2^{256}\equiv 2^{32}+977\). A 512-bit product \(z_\mathrm{hi}\|z_\mathrm{lo}\) reduces by adding \(z_\mathrm{hi}\cdot(2^{32}+977)\) into \(z_\mathrm{lo}\), then one conditional subtract of \(p\). \(977=2^9+2^8+2^7+2^6+2^4+1\), so the multiply is shifts and adds, not a multiplier. Second overflow is at most a few bits; fold it the same way. No Barrett \(\mu\), no Montgomery \(R\), no extra 256-bit modulus register.

Reversibility: do the reduction into a clean accumulator, CNOT the reduced result out, uncompute the accumulator with the reverse adds. The conditional subtract of \(p\) is a compare (borrow chain) plus a controlled add; uncompute the compare borrow. Constant shifts are CNOTs and Xs, which are free in the score but still have to reverse, so do not skip their uncompute.

### 6. One in-place square for \(\lambda^2\), not a better exponentiation square
**Expected gain:** one square is \(<10\%\) of a gcd-based add, and up to \(\sim30\%\) of a Fermat add only if `square.rs` is still schoolbook. **Effort:** medium. **Files:** `square.rs`, `square_split.rs`.

After item 2 there is a single squaring. Exploit symmetry once: the cross term \(2a_i a_j\) is a shift of \(a_i a_j\), so the strict upper triangle is the whole square. Compute it into a clean register with the item-5 reducer, then uncompute. Do not keep the square group/window machinery (`SQC_G`, `SQC_T`, leaf depth) if its table is on the peak for a single use; a narrow \(O(n^2/2)\) square that does not raise the high-water beats a windowed square that does. Check that with the item-1 high-water, not by Toffoli count.

Reversibility: same compute / copy / uncompute pattern. The factor-of-two shift must be undone on the uncompute path or the ancilla is not \(|0\rangle\).

### 7. Knob sweep, only after 3–5, and only on the product
**Expected gain:** \(0\text{–}20\%\) if the current `bind81_recipe.txt` was tuned for an older stream. Not a path to \(3\times10^9\). **Effort:** low per run, high in wall time. **Files:** `bind81_recipe.txt`, the `env::set_var` block in `mod.rs`. Do not add passes to `PP_SIMPLIFY`; affine/quadratic/truth/product plus the cond/sqtop/pscan chain is already past the point of useful generic cancellation.

Sweep `I12_DIV_PROFILE`, `I12_MUL_PROFILE`, `I41_ROUNDS`, `LF_SQUARE_CAP`, `HEO_PIN_PP_WALK_MAX_QUBITS`, `SQC_LEAF_D` one at a time. Keep a point only if \(T\times Q\) drops **and** the 9024-shot check plus the forward-then-reverse check still pass. Discard any point that wins by desynchronizing a frozen edit table into a shorter wrong circuit.

## What I would not spend time on

- More generic CCX cancellation. The pasted `build_generated` already runs product, affine, quadratic, truth, witness, pscan, cond, sqtop, and two stream pipelines. Remaining wins there are noise compared with the \(1.9\times\) gap.
- Measurement-based uncomputation (Gidney-style QROM uncompute, phase kickback, “free” uncompute via measure-and-fix). The rules you pasted forbid it: ancilla must be \(|0\rangle\), no phase garbage, and the gate-reversed list must restore the input. A circuit that only uncomputes in the presence of feedforward will fail that check even if every shot looks right.
- Projective or Jacobian intermediates for a single affine add.
- Large QROM windows. They are how you buy Toffolis with qubits. At \(T/Q\approx 1450\), a window that adds a few hundred peak qubits has to save on the order of \(10^5\) Toffolis **at the peak tick** or it loses. Google’s 1175-qubit point is what a small-or-no-table design looks like.
- Editing anything outside `src/point_add/**`, or loading the `.zst` / `.hnk` blobs into the generator to “see what they do” inside the submitted path.
- Doubling / point-at-infinity logic. It will not be hit, and a flag qubit on the peak is all cost.

## Order of work

1. Phase split (item 1). Half a day. Do not rewrite `leapfrog.rs` before that printout exists.
2. If squares dominate \(T\): item 2, and accept that every stream-bound table has to be regenerated. If a packed workspace dominates \(Q\) and inversion \(T\) is already \(\sim2\text{M}\): items 3 and 4 only.
3. Items 5 and 6 on whatever mul/square remain.
4. Only then the recipe sweep.

I am reasonably confident about the product arithmetic, the Fermat-vs-gcd width argument, and the reversibility constraints. I am not confident which branch HEAD is on: the size of `square.rs` suggests Fermat or mul-via-squares, while the names `pingpong` / `leapfrog` and the walk caps suggest someone already moved partway to a scheduled division. Item 1 decides it; until you have those four numbers, any patch to `y15_onefold.rs` or `heo_carry.rs` is a guess.