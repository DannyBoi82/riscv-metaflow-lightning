# NewIIU swap — status

**As of 2026-08-19. Work is in the tree, uncommitted, and NOT finished:
`tests/asm` is clean but `tests/perf/fft` and `tests/perf/spmv` regressed.**

Plan this came from: `~/.claude/plans/glowing-finding-sketch.md`.

---

## What changed

| File | Change |
|---|---|
| `rtl/ooo/InstructionIssueUnit.sv` | was `NewIIU.sv`; completed and promoted |
| `rtl/ooo/OldIIU.sv` | was `InstructionIssueUnit.sv`; module renamed `OldIIU`, now dead uninstantiated code, kept for reference |
| `rtl/ooo/LightningCore.sv` | `perf_intake_stall` → `perf_stall_pc` (3 sites: `:206`, `:273`, `:1036`) |

`git status` shows only these. No test binaries were rebuilt, so none of the
failures below are the class-toolchain oracle-residue problem.

## The design, as built

Two mechanisms from the old IIU are gone.

**Prediction.** `BTBPredictor4` looks up all four slots, so group shape falls
out of the predictions alone: slot `w` is valid iff its PC is what slot `w-1`
predicted. No decode-stage cuts — no JAL exact-target override, no
cut-before-younger-JALR, no `CT_PER_GROUP_MAX`. A cold JAL/JALR mispredicts
once, the shelf trains the exact target, and it predicts correctly after. The
only redirect sources are `trap_valid` and `mispredict_valid`; `ct_redirect` no
longer exists.

**Tracking.** The 2-entry F-queue (busy/good bits) is replaced by a positional
`pc → F1 → F2 → D` shift register, the in-order core's fetch side widened to
`FETCH_WORDS`. **F2 is the response stage**: a request accepted at cycle N sits
in `block_pc_F2` at N+2, which is the cycle its response reaches the
controller's FIFO head. Nothing counts outstanding requests — the stall table
is what keeps position honest.

Wrong-path groups die by PC tag, in-order style: a flush stamps `WPC_FLUSH`
into every stage, a stall bubble stamps `WPC_BUBBLE` into F2, reset stamps a
bubble, and D drops any group whose PC is tagged before it reaches the DRIS.

Non-obvious things that had to be right:

- **The BTB outputs ride three registers, not two.** The read is combinational
  off the PC stage, so `btb_pred_pc_block`/`btb_read_hist` need the same
  PC→F1→F2→D depth `block_pc` gets. The draft registered them from the PC stage
  straight into `_F2`, which pairs every group with the *next* group's
  predictions.
- **The bubble insertion at F1→F2** (`~stall_F2 & stall_F1`, the `5'b11100`
  stall row). Without it that row re-latches the held F1 group and writes it to
  the DRIS twice. It is also what keeps FIFO pops equal to real groups latched
  at D, since `core_req_stall_mem` holds the head for exactly that cycle.
- **The block-boundary term inside the valid chain**
  (`block_pc_F2[w][BLOCK_OFFSET_BITS+1:2] != '0`). The chain cannot see the
  boundary by itself — an out-of-block slot is forced to miss in the BTB, so it
  predicts fall-through, and `block_pc[w+1] == block_pc[w]+1` always holds.
  `cache3.sv:486` only fills `read_data[word]` while
  `block_offset + word < BLOCK_SIZE`, so without this the tail slots of an
  unaligned group decode zero words into the DRIS.
- **The valid chain carries a prefix.** Slot `w`'s DRIS ID is `fetch_ptr + w`,
  so a hole shifts every younger slot's ID off its own instruction.
- `tagged` is a reserved SV keyword (tagged unions) — the tag predicate is
  `is_tag()`.
- Word-address tags: the `block_pc` pipeline carries `[XLEN-1:2]`, and
  `pc_mispredict_flush` (4'd11) is odd, so it cannot survive the narrowing.
  `WPC_FLUSH`/`WPC_BUBBLE` are byte 0x2C/0x34, below `USER_TEXT_START`.

Added: a `$fatal` assertion checking `core_rsp_addr == block_pc_F2[0]` whenever
a response arrives on an untagged group. That is the positional invariant
stated directly, and it is what makes this scheme safe to iterate on.

Kept deliberately: `core_req_cancel = mispredict_valid` (commit `b3855c5`'s I$
fix).

## Test results

Build is clean under VCS. `make lint` **could not run** — Verilator is not
installed on this box (`/home/daniello/.local/bin/verilator` missing), so the
zero-lint requirement is unverified.

`make regress` (everything with an oracle, `SIM=vcs`, `CORE=lightning`):

**`tests/asm` — clean.** Exactly `dependMul`, `dependMulLow`, `multest` fail,
which is the documented baseline in CLAUDE.md. Nothing else in `tests/asm`
regressed. `beq`/`bne`/`blt` pass, and `tests/custom/icacheloop.S` and
`load_branch_hazard.S` pass.

**Regressions.** CLAUDE.md states that on `CORE=lightning` three of the four
`tests/perf` benchmarks verify clean and only `kosarajus` watchdogs. Now:

| test | documented | now |
|---|---|---|
| `tests/perf/dhrystone.c` | passes | passes |
| `tests/perf/fft.c` | passes | **fails** |
| `tests/perf/spmv.c` | passes | **fails** |
| `tests/perf/kosarajus.c` | watchdog | fails (expected) |

**Unknown — no baseline established.** These failed, and CLAUDE.md does not
say either way whether they passed before, so I do not know if they are mine:

`tests/c/fibr.c`, `tests/c/mmmFpRV32I.c`, `tests/c/mmmIntRV32I.c`,
`tests/c/quicksort.c`, `tests/custom/wbevict.S`.

`tests/c/fibi.c` — the designated iteration target — passes, along with
bubblesort, bumergesort, gaussian, insertionsort, max_path_sum, mixed,
selectionsort, tdmergesort, transpose.

Noise to ignore: the `cache_controller2.sv:520` and `:180` assertion errors "at
time 0" appear in **passing** runs too (beq/bne/blt). They are the known 4-state
X-propagation artifacts at time 0, not a symptom.

## Next steps, in order

1. **Did the position assertion fire?** `grep "fetch position desync"
   output/failed_sims/*/*/simulation.log`. Not yet checked. If it fired, the
   stall table drifted and that is the whole bug. If it did not, the fetch
   pipeline stayed in sync and the fault is downstream — group formation, the
   shelf, or the DRIS intake.
2. **Establish the baseline.** Worktree at `HEAD` with `rtl/ooo/NewIIU.sv`
   deleted (so only the old IIU compiles), then `make regress`. That is the
   only thing that separates the five unknown failures from real regressions,
   and it settles whether fft/spmv were genuinely passing on this box.
3. **Diff fft/spmv**: `make verify-trace` reports the first divergent commit
   with pc/insn/regs/cycle and the `$time` to jump to. Add
   `PARAMS='+define+DEBUG'` for the `insn` annotation.
4. `make lint` once Verilator is available again.
5. `PARAMS='+define+DEBUG'` full regress — CLAUDE.md records this configuration
   silently rotting once before.
6. Perf comparison vs `docs/perf-counters.md` (fibi cycle count; four real
   predictions per group instead of one should raise IPC), and I$ misses via
   `PARAMS='+define+ICACHE_SHADOW'` + `scripts/icache_shadow_report.py`.

## Suspect list for fft/spmv

Untested hypotheses, ranked by how much this change moved them:

- **Cold JAL/JALR now mispredicts.** The old IIU computed JAL targets exactly at
  decode and never mispredicted them. fft and spmv are call-heavy relative to
  the asm tests, so they exercise the new JALR path far harder — and a JALR
  whose BTB entry is stale predicts a *wrong target*, not just a wrong
  direction. If the shelf's repair path has a hole, this is where it shows.
- **Shelf pressure.** `shelf_full` now reserves a whole `FETCH_WORDS` group up
  front, and every CT in a group takes an entry (the old design capped CTs per
  group). Deeper call nesting means more concurrent unresolved branches.
- **`core_req_cancel` on mispredict + positional tracking.** A cancel flushes
  the controller's response FIFO while the shift register still holds stages.
  I reasoned it self-corrects (the cancelled requests occupy exactly the stages
  holding tags), but that reasoning is untested against a mispredict-heavy
  workload. Tying it to `1'b0` is a one-line experiment and would also recover
  the ~7 fills the old IIU's comment flags as still lost.

## Documentation still owed

`docs/architecture.md` `:174-180` still describes the F-queue and the
single-BTB-read model, both gone. A `docs/porting-log.md` entry is owed once
this passes.
