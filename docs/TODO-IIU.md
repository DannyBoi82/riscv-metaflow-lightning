# IIU build plan

Verdict: keep `BranchShelf`, rewrite the `InstructionIssueUnit` wrapper (it references
undeclared signals, dangles every cache3 port, and bypasses the bus-arbitration seam).

## Phase 0 — design decision (DECIDED)

- [x] **Branch execution model: (b).** Branches dispatch through the Scheduler/ALUs like
  any instruction; the ALU computes the correct target PC; the shelf snoops the update
  bus for the branch's own ID and compares `correct_pc` vs `predicted_pc`.
  Deviation from Lightning ("IIU executes branches internally") — the IIU *resolves*
  branches, ALUs compute targets. JALR resolution comes free (ALU computes rs1+imm).
  Consequences: delete `br_rs1/br_rs2` regfile ports.
- [x] **Refinement (Jul 2026) — split the writeback into regfile-bound vs PC-bound.**
  The exec way's `result_data_W` always carries the register-file-bound value (the
  pc+4 link for JAL/JALR — decode's usePC + ALU_ADD4 path already produces this);
  the computed next PC rides a dedicated `next_pc_W` field consumed only by the
  shelf's snoop. The shelf writes **nothing** to the DRIS (`iiu_writeback` deleted;
  DRIS `WRITEBACK_PORTS` no longer reserves a branch slot): exec ways are the sole
  producers of register-file-bound data, the IIU the sole owner of the PC. This
  kills the stale-target window where a link-register dependent could dispatch
  between the ALU's target writeback and a shelf link overwrite.

## Phase 1 — seam prerequisites (outside the IIU)

- [x] Widen `cache_controller2`: `FETCH_WORDS` parameter -> cache3 instance, `read_data`,
      FIFO payload, `core_rsp_data`, miss fill-forward mux with block-end clamp.
      D-side instantiation stays at FETCH_WORDS=1 (bit-identical behavior).
- [x] Regression the baseline (`make autograde LAB_18447=4b`) — D-side must be unchanged.
- [ ] Bump `INSTR_CACHE_BLOCK_OFFSET_BITS` 2 -> 3 (8-word blocks; only offsets 5-7 truncate).

## Phase 2 — new IIU wrapper: fetch

- [x] Rewrite module shell: ports are `core_req_*`/`core_rsp_*` (I-side controller),
      DRIS intake + `fetch_ptr`, `dris_entries`, update-bus snoop, `retire_ptr`,
      trap redirect, shelf outputs. No bare cache3, no raw `mem_*` ports.
- [x] Fetch pipeline: PC register, request generation, 2-cycle latency tracking,
      `core_req_cancel` on mispredict/trap (replaces `~correct_branch_prediction`
      hardwiring in riscv_core_interface).
- [x] Per-slot validity derived from response addr:
      `valid_count = min(FETCH_WORDS, BLOCK_SIZE - rsp_addr.offset)`. Holes, never noops.

## Phase 3 — group formation and intake

- [x] Decode per slot (one `riscv_decode` per fetch way).
- [x] Group-cut rules: program order, cut AFTER the first *redirecting* CT
      (JAL, or predicted-taken branch/JALR) and BEFORE a younger JALR (pc+4
      would be a guaranteed mispredict; refetch it as oldest of next group).
      Multiple CTs per group allowed behind a not-taken-predicted branch;
      truncate on DRIS-full / shelf-room.
- [x] Per-slot PC + BTB predicted next PC; slot PC goes in its intake packet.
- [x] Build `dris_intake_pkt_t` per slot; advance `fetch_ptr` by valid-slot count
      (color bit lives in the extra MSB; IIU owns the register).
- [x] DRIS-full detection from `fetch_ptr` vs `retire_ptr` occupancy; stall front end.
- [x] Gate `valid_R` on `mispredict_valid | trap_valid` (same-cycle flush-vs-intake race).

## Phase 4 — branch machinery

- [x] Wire BTBPredictor for real; train from shelf resolutions (one resolve/cycle;
      branches + JALR only, JAL targets come from decode; 2-bit counter bits ride
      through the shelf entry as `btb_hist`).
- [x] Wire BranchShelf intake (`shelf_in_pkt` per valid CT slot);
      issue stalls when `shelf_free_count` < CTs in the group.
- [x] `fetch_ptr` rollback on mispredict: mispredicted ID + 1 = next allocation point;
      restart PC from `mispredict_pc`.
- [x] JAL/JALR link values: carried by the exec way's `result_data_W` (pc+4 via the
      usePC + ALU_ADD4 decode path); `iiu_writeback` deleted — the shelf is not a
      DRIS producer. Exactly one producer (exec, per the Phase 0 refinement).
- [x] Execute ways — built in `src/ooo/LightningCore.sv` per the spec: per-way
      `riscv_alu` + next-PC block, `result_data_W = alu_out` for everything except
      PC_indirect (override with `pc_I + 4`; ALU_ADD4 on rs1 is garbage there).
      `next_pc_W`: PC_cond = `alu_out[0] ? pc_I+imm_I : pc_I+4`; PC_uncond =
      `pc_I + imm_I`; PC_indirect = `(rs1_data_I + imm_I) & ~1` — JALR keeps
      decode's usePC link setup (op_1 = PC, ALU_ADD4 → pc+4 link) and its target
      rs1 rides the issue packet's dedicated `rs1_data_I` field. Issue packets
      register at the I/E boundary (`issue_pkts_reg`), so execute is a real stage:
      writeback lands one cycle after issue, one issue group is in flight across a
      flush (never clear the register — older-than-branch instructions must
      complete), and the DRIS drops writebacks whose target entry is no longer
      valid so a wrong-path in-flight writeback can't corrupt a reallocated entry.
      Packed-vs-unpacked DRIS/IIU port mismatch reconciled in LightningCore.
      Open: ready_vector doesn't segregate loads/stores from ALU ways (memory unit
      TBD) — loads/stores currently execute through the ALUs, so only memory-free
      programs are correct.
- ~~Shrink shelf allocation to one entry/cycle~~ — dropped: multi-CT groups
      (younger not-taken branches share a group) make the FETCH_WAYS-wide
      allocation load-bearing.

## Phase 5 — integration and verification

- [x] Move the OoO files back into src/ — they live in `src/ooo/` now; `DRIS_defs.sv` was renamed `1DRIS_defs.sv` so the sorted build compiles the package before its importers (Scheduler + SSC moved too; all five compile).
- [x] Compile-only milestone before behavioral tests — `LightningCore.sv` (top:
      DRIS + IIU + Scheduler + SSC + 447src register_file at WAYS=7 + exec ways)
      compiles and elaborates as a VCS top module; baseline regression unaffected.
      Also fixed in DRIS.sv: writeback assigned 32-bit `result_data_W` to the
      33-bit `result` struct (shifted data, `result_valid` = data bit 0; now sets
      `result_valid <= '1` explicitly), and allocation now clears `result` so a
      recycled entry can't inherit a stale `result_valid`.
- [x] Instantiate LightningCore in riscv_core_interface (replace riscv_core) with
      the FETCH_WORDS-wide I-side controller. Done: I-side controller now built
      at FETCH_WORDS=FETCH_WAYS, D-side controller kept instantiated but tied
      off idle (no memory unit yet). As of 2026-07-06 all ten memory-free
      447 tests pass (additest, addtest, arithtest, beqtest, brtest0-2,
      depend, dependLow, shifttest) after the two fixes below; syscalltest
      still fails on `halted` semantics.
- [x] Branch-test hangs (beqtest, brtest0-2) — root cause was in the SSC, not
      the shelf: the retire fence only covers UNDET branches, so the cycle a
      branch resolved WRONG the fence lifted while flush_mask was still
      combinational — already-executed wrong-path youngers retired (register
      file corruption) and pushed retire_ptr past the IIU's fetch_ptr rollback,
      wrapping occupancy and wedging intake forever. Fix: retire_ready_vector
      now masks each slot with ~flush_mask.
- [x] Scheduler out-of-bounds operand indexing: dispatch indexed the way-sized
      operand arrays (operand_1/2, operand_source_entries, rs1_data_intermed)
      by raw window position (0..ENTRIES_CHECKED-1), silently reading X for any
      pick past position EXEC_UNITS-1 — build-sensitive wrong-operand issues
      (the first-boot additest x29 mismatch). Restructured: selection first
      (sel_idx/sel_valid), then per-way operand muxing on sel_entries.
- [x] ~~Intra-fetch-group lockers~~ — stale TODO: DRIS_ff's
      locker_init_comb_logic already scans earlier ways of the incoming group
      and forces locked=1 (fetch_group_dep*_valid), with locker_valid=1 via
      slot_id. Verified by depend/dependLow/additest passing.
- [ ] Fix `halted` semantics: ECALL at DRIS head should halt only when a0==0x0a
      (447 convention); otherwise retire it as a no-op (syscalltest).
- [ ] Directed tests in custom-tests/: straight-line fill, taken-branch redirect,
      mispredict flush, back-to-back branches (shelf fence), JAL link write.
- [ ] Update DRIS.sv header + CLAUDE.md: IIU decides what/whether to issue;
      DRIS records IDs and lockers at intake.
