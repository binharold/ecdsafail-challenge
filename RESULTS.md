# My ECDSA.fail results: low-qubit Pareto rows

This fork holds my entries in the [ECDSA.fail](https://ecdsa.fail) challenge: build the cheapest reversible
quantum circuit that adds a point on secp256k1, scored by **average executed Toffoli × peak qubits**.

## What I did

I worked on the low-qubit end of the Pareto frontier (774–785 qubits). At these widths the best rows came from
odinfree's lane. Their builder emits a long op stream and then folds Toffoli pairs (`gate_fold`, `gate_fold2`) and
holds repeated products on idle wires (`hold_idle`).

The promoted main tree has exact post-passes that this lane did not run. I inserted three of them on the unfolded
stream, before the folds, and left the rest of the circuit untouched:

1. `affine_simplify::simplify`: drops or weakens Toffolis that affine support identities prove redundant.
2. `truth_simplify::simplify_products`: the same with exact truth tables over at most six atoms.
3. `cond_pass::final_cap_cleanup`: a Toffoli whose result is only read by phase gates becomes Clifford phases.
   Its own three rounds do not reach a fixed point, so I call it three times; a fourth call finds nothing.

Two small engineering changes made it run:

- `cond_pass` stored every XOR set twice and ran out of memory on these 60–80M-instruction streams. It now stores
  each set once. This changes memory only; no rewrite rule changed.
- At 774 qubits I also retuned two of the builder's own constants (`LEAN_ZL = 4`, `CAPW = 0`). That gave about
  20k more Toffolis.

Each row keeps the parent's qubit count, its measurement count and zero conditional Toffolis. Each row passed all
9,024 validation shots locally and again on the official runner, with the same Toffoli count to the digit.

## Results (officially scored)

| Qubits | Previous best (odinfree) | Mine | Toffolis saved | Branch |
|---:|---:|---:|---:|---|
| 774 | 23,721,822 | **23,638,124** | 83,698 | `shadow-774` |
| 775 | 20,728,068 | **20,656,073** | 71,995 | `shadow-775` |
| 776 | 19,431,608 | **19,347,653** | 83,955 | `shadow-776` |
| 777 | 18,766,376 | **18,676,141** | 90,235 | `shadow-777` |
| 779 | 18,429,943 | **18,272,040** | 157,903 | `shadow-779` |
| 780 | 17,284,688 | **17,114,372** | 170,316 | `shadow-780` |
| 781 | 16,837,186 | **16,734,996** | 102,190 | `shadow-781` |
| 782 | 16,367,771 | **16,265,271** | 102,500 | `shadow-782` |
| 783 | 15,907,868 | **15,803,761** | 104,107 | `shadow-783` |
| 784 | 15,705,104 | **15,614,431** | 90,673 | `shadow-784` |
| 785 | 15,569,604 | **15,485,892** | 83,712 | `shadow-785` |

The same method was applied to rows 786–792 in a second session (branches `shadow-786` … `shadow-792`).

These rows are Pareto points. They do not beat the overall best score (about 890M at around 1,226 qubits), so the
scalar board lists them as "did not improve current best".

## Credits

The circuits are odinfree's, and the passes are other solvers' code from the main tree, used unchanged:
odinfree and mochimodev (`affine_simplify`, `truth_simplify`), jackylee0424 (`cond_pass`) and haotang1995
(`final_cap_cleanup`). My part is the wiring, the memory fix, the 774 tuning and the verification. Every
submission declares these dependencies.

## Reproduce one row

```bash
git checkout shadow-777
./benchmark.sh
```

The build needs more than 15 GB of memory (add swap) and takes about 45 minutes on a 4-core machine.

Built with Claude Code.
