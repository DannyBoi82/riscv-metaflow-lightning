# TODO — verify-trace redesign (commit-state trace compare)

**Status 2026-07-11 (end of day): LANDED and blessed on CORE=inorder.**
`make verify-trace TEST=... CORE=inorder` works end-to-end: full asm suite
passes (17 representative tests trace-verified incl. memtest0-2/depend;
full regress green except the 3 expected mul tests), and an injected ALU
fault was pinpointed to the exact commit/pc/insn/register. Old
TRACE=1/DEBUG_RFWRTRACE machinery and the 64 class `.vh` oracles deleted.
Remaining items are marked open below; usage docs live in README
("verify-trace"), file map in docs/architecture.md.

## Why

The class `make verify-trace` compared register **write events** (the
refsim `trace` command prints one `rd,value` line per `register_write`;
the RTL side checked writeback events against a compiled-in `changes`
array — `DEBUG_RFWRTRACE` in tb/register_file.sv). Pipeline bubbles /
`add x0,x0,x0` nops — abundant once memory latency exists — show up as
RTL write events with no refsim counterpart, so the streams can never
align. Unusable for exactly the debugging it was meant for.

### Prior art: how the class flow actually worked (fully understood,
### scripts recovered in stuff-from-ece447-folder/)

- `make gen-sv TEST=x` → `get_reg_dump.py` (assemble, then pipe
  `trace\ngo\nquit` into the class riscv-ref-sim → `trace.txt`, one
  `rd,value` line per architectural write, x0 excluded, program order)
  → `sv_from_diff.py` → SV package `reg_changes_pkg` with a compiled-in
  `changes[]` array. The committed per-test `.vh` files are these,
  pre-generated.
- `make verify-trace TEST=x` → copies the test's `.vh` to
  `output/reg_defs.vh`, **recompiles the whole simulator** as
  `_verbose` with `+define+DEBUG_RFWRTRACE`, runs it. The regfile
  checker asserts write event #N (ways scanned 0..WAYS-1, one-cycle
  buffer, x0 filtered) == `changes[N]`, `$fatal` with cycle + write
  index on first mismatch. Then the usual end-state regdump diff.
- So it *is* golden-model lockstep against the same refsim trace —
  same family as this redesign, at a different granularity. What it
  gets right (steal these): **online fail-fast with the cycle number**
  (no trace files, no post-hoc diff), and event checking at the write
  port sees both halves of a same-cycle WAW pair. What kills it: the
  alignment unit is the **write-event index**. Non-writing commits
  don't exist in the stream, and any disagreement about what counts as
  an event — x0 policy, write enables held/replayed across
  memory-latency stalls, wrong-path writes — slips the index once and
  every subsequent assert misfires with no way to re-anchor. No PC or
  insn anywhere: a `$fatal` gives "write #1234 at cycle T" and you
  count lines in trace.txt to find the instruction; a *dropped* write
  is reported at the next writing instruction with a confusing
  expected/actual pair. Plus a full simulator recompile per test
  (painful under Verilator).

Redesign: compare **full architectural register state per committed
instruction** instead — the alignment unit becomes "committed
instruction," which both sides define identically, and each line is a
full state so the diff self-anchors. Nops become identical consecutive lines on both
sides, traces align 1:1 by commit index, and the first divergent line is
the exact faulty instruction. No waypoint/collapse machinery needed once
both sides agree that the dump point is "one committed instruction."

## Design (decided)

- **The invariant this rides on:** any precise-state OoO core retires in
  program order — that is the definition of maintaining precise
  architectural state, not a Lightning-specific property. So the flow is
  **design-independent**: swap the core above the harness and the tool
  still works, as long as the new core emits commit packets.
- **Dump point is retirement, not the regfile write port.** The register
  file cannot host this: it never sees commits that don't write a
  register (branches, stores, the halting ecall) and it has no PC —
  but 1:1 alignment with the refsim trace requires one line per
  *committed instruction*, write or not. The retirement seam (SSC)
  emits a per-slot commit packet, oldest→youngest within the cycle:

      commit_pkt_t: { valid, pc, insn, rd_we, rd, rd_data, retire_cycle }

  Shape the field names as an RVFI subset (`rvfi_order`, `rvfi_pc_rdata`,
  `rvfi_rd_addr`, `rvfi_rd_wdata`...) — RVFI is the industry codification
  of exactly this idea, and matching it keeps the door open for
  riscv-formal / Spike co-sim later.
- **Who assembles the packets** (*decided 07-11*): `tb/register_file.sv`
  becomes a pure packet assembler — the core tells it which slots retire a
  real instruction (`commit_valid`/`commit_pc`/`commit_insn`) and its own
  write-port inputs supply the register-write half; it then just passes
  `commit_pkts` up to the testbench. All dump/trace/checking machinery
  leaves the regfile. **Using this module is optional, and the contract
  must be documented (README + riscv_commit.vh)**: a design with an
  architectural-vs-physical register file split has no regfile module that
  ever sees architectural commits, so such a core emits `commit_pkt_t`
  packets itself at its retirement point — the harness only ever consumes
  the packets. (Future-proofing; both current cores do use the module.)
- **End-state dump follows the packets** (*decided 07-11*): the
  end-of-run `simulation.reg` dump is printed by the tb verifier from its
  shadow regfile, not by the design — packets are the sole
  design-to-harness channel (a PRF design has no flop array to dump
  anyway). Consequence: `make verify` now also depends on faithful commit
  reporting; the shadow-vs-flops cross-check below is the guard.
- **Bring-up core** (*decided 07-11*): develop and bless the whole flow on
  the **in-order class core** (`CORE=inorder`, `rtl/core/riscv_core.sv` +
  `rtl/mem/riscv_core_interface_inorder.sv`, vendored from the old class
  seam) — it passes the full autograder suite, so flow bugs are never
  confused with Lightning bugs. Lightning meanwhile emits *write-only*
  packets (valid on register-writing retirements, pc/insn = 0) so its
  end-state verify keeps working; full verify-trace on Lightning is
  blocked on the SSC carrying pc/insn and non-writing retirements.
- **tb-side verifier module** consumes the packets, keeps a shadow
  architectural regfile, applies writes **slot-serialized in program
  order**, and prints one full state line per commit. This reconstructs
  the intermediate states the flopped regfile never physically holds
  (N-way retire) and makes same-cycle WAW pairs individually visible —
  a cycle-granular dump would silently hide a corrupted older write.
- **No retirement throttling.** Reconstruction is print-side only, zero
  simulation time: **cycle counts and perf counters are unaffected**.
  The cost is wall-clock slowdown and disk (~300 B/commit ≈ 300 MB per
  1M commits; the LTG_MAX_SIM_CYCLES watchdog bounds livelock traces).
  README must state this cost — and that it is *not* a cycle-count cost.
- **Line format (the only diffed format):** one line per commit —
  `pc` + 31 hex words x1..x31 (x0 elided). RTL side appends a
  ` #cycle=N` comment the checker strips (refsim has no cycles).
  Pretty 32-line dumps are a **viewer script** over compact lines, not a
  second RTL format — one source of truth, formatting lives in scripts/.
- **Initial anchor line:** state before the first commit (SP=STACK_END,
  GP=USER_DATA_START) printed by both sides, so diffs anchor at commit 0
  and a reset-state mismatch is caught immediately.
- **Divergence report → waveform:** checker prints commit index, pc,
  insn, which registers differ, and the RTL retire cycle; then
  `make waves TEST=...` and jump to that cycle. Note the retire cycle is
  an *upper bound* — the bad value was computed at issue/exec earlier;
  optionally carry dispatch/writeback cycles in the packet later.
- **Wrong-path is free:** only retired instructions produce packets, so
  flushed speculation never pollutes the trace by construction.

## Work items

- [x] refsim: `statetrace (file)?` command (anchor line on activation,
      one line per instruction from `run_simulator()`; the old `trace`
      command untouched). `make reftrace TEST=...` pipes it in.
- [ ] shadow-vs-flops cross-check: the verifier's shadow regfile is
      built from commit packets — if the real regfile flops diverge
      from what the packets claim (write-decode bug landing in the
      wrong physical register), the trace would still match refsim and
      the bug escapes to the end-state diff. Add a cheap per-cycle tb
      assert comparing the shadow against the actual `registers` array
      (hierarchical ref, same precedent as `top.mem_access`). The class
      scheme has the same hole (it checks write-port values, not stored
      state).
- [x] commit_pkt_t (`rtl/include/riscv_commit.vh`, RVFI-style fields,
      COMMIT_WAYS_MAX padding) + regfile converted to packet assembler.
- [x] in-order core commit plumbing: valid_F2..valid_W chain (bubbles and
      the mispredict M1→M2 double-latch marked invalid), pc/insn carried
      to W, `commit_fire = valid_W & ~stall_W`, packets out through a
      SIMULATION_18447-guarded port. `CORE={lightning,inorder}` selection
      in config.mk/Makefile (both wrappers define riscv_core_interface;
      exactly one is compiled).
- [x] inorder wrapper: commit_pkts plumbed up to the testbench (padded to
      COMMIT_WAYS_MAX); lightning wrapper likewise.
- [x] lightning: rf commit tie-off switched from '0 to write-only packets
      (commit_valid = write-port we) so the shadow-based end-state dump
      stays correct on CORE=lightning.
- [x] tb verifier module (tb/commit_verifier.sv): shadow regfile,
      slot-serialized state lines gated by a `+commit_trace` plusarg,
      `#cycle=N insn=X` annotation, initial anchor line, end-of-run
      simulation.reg dump from the shadow (took over the regfile's dump
      duty) — computed through a blocking temp so halt-edge commits are
      included (the old flop-read dump raced same-edge writes).
- [x] halting ecall (*decided 07-11*): produces a final trace line on
      both sides — refsim's step loop executes it anyway, so the RTL
      forces the last commit on the halt edge even if stall_W is high
      (`valid_W & (~stall_W | halted)`).
- [x] checker (scripts/check_commit_trace.py): field-wise compare
      ignoring `#` comments; first-divergence report (commit idx, pc,
      insn, regs w/ ABI names, RTL cycle); length-mismatch diagnosis.
      Proven against an injected ALU fault (exact commit identified).
- [x] `make verify-trace TEST=...`: reftrace + RTL sim (+commit_trace via
      the new PLUSARGS= knob) + checker.
- [x] pretty-print viewer: scripts/view_commit_trace.py (per-commit
      register deltas; --full for whole-state dumps).
- [x] deleted superseded TRACE=1 / DEBUG_RFWRTRACE / reg_defs.vh Makefile
      machinery and the 64 class .vh trace oracles. Nothing irrecoverable:
      git history has the .vh files and the old register_file.sv
      (`git show 00c8ebb:tb/register_file.sv`), class scripts are vendored
      in stuff-from-ece447-folder/, and the in-repo refsim keeps the
      `trace` command, so the whole old flow is reproducible.
- [ ] split config spaces: tb/ISA parameters (XLEN, superscalar/retire
      ways as the harness sees them, memory latency, RISCV_ARCH) vs
      design parameters (LTG_* stays the design's own space). Retarget
      the first for a different RISC-V flavor; the second only for
      Lightning-specific knobs.
- [x] README: verify-trace usage, the cost note, and the commit packet
      contract (how a design that doesn't use tb/register_file.sv hooks
      in by emitting commit_pkt_t packets itself).
- [x] sanity cross-check "final trace line == end-of-run dump": true by
      construction now — both are produced from the same shadow state in
      commit_verifier.
- [ ] lightning: SSC must carry pc/insn and non-writing retirements into
      reg_commits so verify-trace works on CORE=lightning (write-only
      packets today; see TODO(SSC) in LightningCore.sv).
- [ ] VCS parity: verify-trace flow has only been run under Verilator;
      exercise it in the next AFS run (tb is single-SV-top and uses only
      $fopen/$fwrite/plusargs, so no VCS-specific code expected).

## Scope / non-goals

- Architectural regfile only — no memory array, no CSRs (class tool
  didn't check them either). Store bugs surface when the value is loaded
  back; a test can pass verify-trace and still fail the end-state check.
- Post-hoc file diff first (simple, portable, debuggable). An online
  `$fscanf` checker ($fatal at first divergence, no giant trace files)
  is a natural follow-up, not v1.
- Halting ecall: decide once whether it produces a final line, and do
  the same on both sides.
