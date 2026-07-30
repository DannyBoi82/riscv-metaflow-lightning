# Memory subsystem build plan (memory scheduler + D-cache path)

**Provenance.** This doc merges two sources. The *mechanism* sections (Phase 0, Phase 2,
Phase 3) are rewritten from the primary specs — the DRIS patent, the Metaflow architecture
paper, and the Lightning chipset paper — cross-checked against `memory-spec???.md`, a
research summary of those same papers. The *seam* sections (Phase 1, Phase 4, Phase 5) are
the original hand-written plan and are the only record of how the memory unit attaches to
the inherited 18-447 testbench; the spec has nothing to say about those.

**How to read the deviation tags.** Metaflow-the-architecture and Lightning-the-chipset are
not the same authority level. Architecture requirements (two-phase execution, the domain
check, ID-tagged returns, store-at-retire) are binding per CLAUDE.md. Lightning
implementation choices (a dedicated address ALU, a direct-mapped 1 MB external cache, a
non-blocking CMB) describe one instantiation, and the inherited testbench forces different
choices. Everywhere we knowingly depart, the line is tagged **[DEVIATION]** with the reason.
An untagged statement is meant to be spec-faithful; if the RTL disagrees with it, the RTL is
wrong.

## Spec anchors

Two-phase execution (Metaflow arch, IEEE Micro pp. 64–65): memory instructions go through
Issue/Schedule/Execute/Update **twice** — first to compute the address, then to fetch the
data. *"Loads must effectively go through the Issue, Schedule, Execute, and Update phases
twice: first to compute the address, then again to fetch the memory data. Also, a
significantly different form of data dependency governs the second cycle."*

Where the address goes (patent, col. 9): *"The address is placed in the result field 31 of
dynamic register file 11 and compared with the memory addresses of older store instructions
that may be in the dynamic register file 11 via the domain check 59."* The arch paper says
the same in prose — written back *"into the DRIS adjacent to the memory reference
instruction."*

The return (arch paper p. 65, second execute): *"Send the load instruction's one operand,
the target memory address, to memory and receive the addressed data in return. Present the
ID of the load instruction to the Update phase at the same time as the data (details of this
coordination will vary with memory subsystem design)."* And p. 66: *"The second Update phase
of a load instruction is identical to the single Update phase of a register-to-register
instruction."*

Stores (chipset §2.3): *"STORE requests are always sent to memory in strict program-defined
order, at the time the STORE instructions are retired from the DCAF. This insures that the
processor's memory system always contains the correct ('sane') in-order state."*

## Build status

`src/ooo/MemoryScheduler.sv` exists (248 lines) and **both halves of the D-side are now wired**
in `LightningCore.sv` — the load return path landed (`LightningCore.sv:328-330` drives
`writeback_pkts[EXEC_UNITS]` from `core_rsp_*_d`). **The tree compiles and simulates** —
`make build` exits clean and additest / addtest / shifttest / brtest0 pass.

**Loads work end to end: `lwtest` passes** (finishes at sim time 5200). **Stores deadlock the
core** — `memtest0` hangs, and so does a hand-cut single-`sw` program; replacing that one `sw`
with an `addi` makes the identical test terminate at 2300. The store retire/issue cycle below
is the one thing standing between here and the first memory-bearing program.

**Build noise that is not a bug**, so nobody re-investigates it from the compile log: VCS
emits a dozen-odd `ENUMASSIGN` warnings on `'{default: '0}` struct initializers (DRIS,
Scheduler, `issue_pkts_reg` in LightningCore). `ctrl_signals_t` contains a `pc_source_t`
enum and VCS will not take an untyped `'0` for it. Codebase-wide and pre-existing; if it ever
becomes worth silencing, do it once in the struct default rather than at each assignment
site. The `UI`/`ONGS` lints on the MemoryScheduler's `clock`, `reset_n`, and `rs1_data` are
also expected — the unit is purely combinational and the memory path has no use for rs1.

- [x] **Compile error — fixed.** `.TOTAL_PORTS(1)` against `MEM_ISSUE_WAYS = 2` gave five
      port-connection-type mismatches on the `ms` instance: `mem_issue_pkts`, `rs1_addr`,
      `rs2_addr`, `rs1_data`, `rs2_data` are unpacked arrays sized by that parameter, and VCS
      rejects unpacked-array port connections on size rather than truncating the way it does
      for a packed vector (`read_rf`, which only drew a width lint). Resolved toward the
      single-ported cache, which is what the instantiation comment always intended:
      `MEM_ISSUE_WAYS` is now a plain `localparam int = 1` at `LightningCore.sv:101` and the
      instance passes `.TOTAL_PORTS(MEM_ISSUE_WAYS)`. One knob instead of two that have to
      agree by luck. Widening the D-side means changing that localparam only.
- [x] **`rs1_addr` was never driven — fixed.** An undriven MemoryScheduler output feeding the
      register file's address port, so RF read way 4 indexed on X. The memory path genuinely
      never needs rs1 (the address comes from the entry's `result` field, computed in phase 1;
      only store data is read from the RF, on rs2), so it is now tied to zero with a comment
      saying why. `rs1_data` stays an unused input — an honest lint rather than a latent X.
- [x] ~~**Stores never set `mem_addr_ready`.**~~ Stale — `DRIS.sv:124` now gates on
      `(memRead || memWrite)`, so a store's address bit does get set. The deadlock it
      predicted still happens, but for the different reason immediately below.
- [ ] **Store retire/issue deadlock — the live hang.** A store can never satisfy either side
      of a circular dependency, so it parks at the retire head forever; in-order retirement
      then wedges everything younger, the DRIS fills, fetch stops. Four pieces close the loop:
      1. `Scheduler.sv:55-61` issues the store once to an ALU way to compute its address
         (gate is `!executed && !mem_addr_ready`).
      2. `DRIS.sv:124-130` takes that address writeback and sets `mem_addr_ready <= 1` but
         then forces `executed <= 0` and `dispatched <= 0` for **anything** with
         `memRead || memWrite` — stores included.
      3. `MemoryScheduler.sv:74-76` gates a store's ready bit on `retire_vector[...]`, so it
         only issues to the D-cache in the cycle the SSC retires it.
      4. `SaneStateController.sv:76-83` (`entry_eligible`) refuses to retire anything that is
         not `executed`.

      So the store must retire in order to issue, and must issue in order to become `executed`
      and be allowed to retire. **The fix is already specified in Phase 2 below** (the "store"
      writeback case): don't clear `executed` for a store — its result field holds the address
      and that address *is* valid; the memory write happens at retirement by design. One line
      at `DRIS.sv:127`, `executed <= writeback_pkts[i].ctrl_signals_W.memWrite;`. That makes
      the SSC see the store as eligible, which raises `retire_vector`, which lets the
      MemoryScheduler issue it in the same cycle — exactly the simultaneity
      `LightningCore.sv:254-260` already documents as the intent.

      Loads are immune because their `MemoryScheduler.sv:65-69` gate carries no
      `retire_vector` term, and the return writeback leaves `ctrl_signals_W` at zero so
      `DRIS.sv:124` does not re-clear `executed` the second time. That asymmetry is the whole
      reason `lwtest` passes and `memtest0` does not.
- [ ] **A store hit gets a cache response too, and it will land as a second writeback.**
      `core_hit_valid` fires on `read_hit` regardless of direction
      (`cache_controller2.sv:272-281`), so once stores actually issue, the store's own DRIS ID
      comes back on `core_rsp_*_d` and overwrites `result.result_data` with read data. The
      `entry_state.valid` guard in `DRIS.sv:112-113` drops it if the entry already retired —
      but that is a timing accident, not a guarantee, and it is exactly the case the Phase 2
      color check is meant to cover. Check the 2-cycle response against entry reallocation.
- [ ] **`MemoryScheduler`'s store-ready gate never checks `mem_addr_ready`**
      (`MemoryScheduler.sv:74-76`) — it trusts the SSC to have vetted the address. True today
      only because `entry_eligible` implies it. Add the term defensively; it costs nothing and
      stops a garbage address from ever reaching the port.
- [ ] **Load phase-1 writeback leaks the address as data.** `DRIS.sv:120-121` set
      `result_valid` unconditionally before the memRead branch, and the branch clears
      `executed`/`dispatched` but not `result_valid`. Dependents unlock early and consume the
      *address* as the loaded value. Violates the patent's core result-field invariant.
- [x] **D-cache request drive — rebuilt.** The old `always_ff` block had three faults, all
      fixed together at `LightningCore.sv:270-289` (`d_request_drive`):
      - It selected on `core_req_re` alone, so a store — which sets `we` with `re` low — could
        never win the port, despite the comment claiming writes win.
      - It gated on the *registered* `core_req_we_d`, i.e. the previous cycle's state.
      - It had no default assignment, so on an idle cycle it held the previous request and
        replayed it. For a store that means committing the same write every cycle.
      Now a combinational priority select with an explicit idle default. At
      `MEM_ISSUE_WAYS = 1` it degenerates to a pass-through (the MemoryScheduler's dispatch
      loop already fills the single way with a store before considering a load, so writes win
      inside the scheduler), but it stays a priority select so widening the D-side later
      cannot drive `re` and `we` together.
- [x] **The request is no longer registered.** `cache_controller2` accepts live on a
      same-cycle probe; CLAUDE.md flags pipelining the request inputs as a documented desync
      hazard, and the SSC gates a store's retirement on `d_cache_ready` in the very cycle the
      MemoryScheduler issues it (`SaneStateController.sv:107`) — so a registered request
      retired the store a cycle before the cache ever saw it. Combinational now; keep it that
      way. This is the seam contract Phase 1 still needs to write down properly.
- [x] **Return path — built.** No longer tied to zero: `LightningCore.sv:328-330` drives
      `writeback_pkts[EXEC_UNITS]` with `core_rsp_id_d` / `core_rsp_data_valid_d` /
      `core_rsp_data_d`. `lwtest` passes on the strength of it, so the "only memory-free
      programs are meaningful" caveat is retired. Note the port deliberately leaves
      `ctrl_signals_W` at zero, which is what stops `DRIS.sv:124` from re-clearing `executed`
      on a load's second update — load it back in if that ever changes. Phase 3's remaining
      items (real ID tagging, sub-word extract, flush cancel) are still open.
- [x] **`SEPARATE_RW_PORTS` un-broken.** The branch never reached the compiler, because
      `UNIFIED_RW_PORTS` is defined and selects the other arm — so its errors sat latent
      behind the macro. It referenced an undefined `MEM_`, had an `end else if` dangling off a `for`
      (so the `else` bound to nothing and `i` was out of scope), and used the running
      `write_idx` as the base for read-port indices, which slid the load ports around as
      stores issued — the read base is now the fixed `CACHE_WRITE_PORTS`. The `` `else ``
      arm's bare `$fatal` was also illegal at module scope; it is wrapped in an `initial`.
      Still dead code, but flipping the macro is now a real experiment rather than a
      syntax error.

## Phase 0 — mechanism (settled, spec-derived)

- [x] **Two-phase execution.** Phase 1 computes the effective address; phase 2 for loads is
      the actual memory access. Stores have no phase 2 — they go to memory at retire.
- [x] **Phase 1 rides the general ALU ways.** **[DEVIATION]** Lightning had a dedicated
      memory-address ALU (the patent's "memory only ALU 310", ALU 3; arch paper p. 69 lists
      "two integer ALUs, a memory address ALU"). We reuse the inherited exec-way structure
      instead. Costs a general ALU slot per memory op; no semantic difference.
- [x] **The address lives in the entry's `result` field**, per the patent, *not* in a
      separate `mem_addr` field. `result_valid` stays 0 through phase 1 — a load's address
      must never be readable as its data — and a separate `mem_addr_ready` state bit carries
      "address known." This is the one place where the field is overloaded on purpose: the
      patent overloads it too, and the extra state bit is what keeps locker semantics honest.
- [x] **Domain check: safe / unsafe / imprecise** (patent col. 9, FIG. 5). After a load's
      address is known, compare against all older unretired stores:
      - **safe** — no older store matches, and every older store's address is known. Go.
      - **unsafe** — an older store's known address matches. Wait until that store has been
        sent to memory (i.e. has retired).
      - **imprecise** — some older store's address is not yet computed. Wait; it resolves to
        safe or unsafe once that address lands.
- [ ] **Word-granularity compare.** Compare `[XLEN-1:2]`, not the full byte address. The
      request truncates to `[31:2]` at the port, so two sub-word accesses to different bytes
      of the same word alias in the cache and must alias in the check. `MemoryScheduler.sv`
      currently compares full `result_data` — a latent miss.
- [x] **Store data is read from the register file at retire**, addressed by the entry's `rs2`
      field — patent col. 9: *"The store data is read from the register file 17 which is
      addressed with the register address field 41 of the dynamic register file. The store
      data is known to be in the register file because when the store instruction is sent to
      memory, every previous instruction has completed execution and transferred its result
      to the register file."* Rejected alternative: capturing rs2 at phase-1 issue and
      parking it in `result`. The patent's argument for why the RF read is safe *is* the
      retire ordering we already enforce, and it keeps `result` free for the address.
      **Caveat found while debugging the store hang, and it is load-bearing:** the patent's
      safety argument is *"every previous instruction has completed execution and transferred
      its result to the register file."* Our SSC retires up to 8 per cycle
      (`REG_FILE_WRITE_PORTS = 7` plus the memory port), and reg commits land on the clock
      edge — so an older instruction retiring in the **same cycle** as the store has not
      transferred yet, and `MemoryScheduler.sv:171-177` reads a stale rs2. `memtest0` hits
      this directly (`sw x5` a few instructions after the `addi`/`add` chain producing `x5`).
      The Phase 4 slot-0 retire rule closes it exactly — if a store may only retire from slot
      0, everything older necessarily retired in a strictly earlier cycle. That makes the
      slot-0 rule a *correctness* prerequisite for store data, not just store-store
      serialization; do it in the same pass as the deadlock fix, or the first thing memtest0
      does after it stops hanging is store the wrong value.
- [ ] **No store-to-load forwarding.** **[DEVIATION]** — and note the earlier version of this
      doc justified it wrongly. The arch paper doesn't forward, but patent FIG. 5 *does*: on
      the unsafe path it asks "is store data valid?" and if so returns the store data
      straight into the load's result field and marks it valid, never going to memory. We
      skip it for now as a performance feature, not a spec-faithfulness one. Measure first.
- [x] **One load in flight.** **[DEVIATION]** Lightning's CMB is non-blocking — *"continues
      to accept requests and respond to hits while processing outstanding misses"* — which is
      precisely why the architecture needs ID-tagged returns (Phase 3). Our D-cache is
      single-ported with a 2-cycle hit. Keep `MEMORY_READ_PORTS` sized for the writeback
      array; use one.

## Phase 1 — seam prerequisites (outside the memory unit)

- [ ] Nail down the D-side acceptance/busy handshake in `cache_controller2` before wiring
      anything further: what the baseline's `d_cache_ready` maps to, how a store behaves
      during a miss / write-allocate fill / dirty-victim streamout, and what "request
      accepted" means for a live same-cycle-probe controller. Write the answer here. The
      request drive is now combinational and must stay that way (do NOT pipeline core request
      inputs — documented desync hazard); what is still unwritten is what the controller
      *promises* when it raises `d_cache_ready`, which is what the Phase 4 retire gate leans
      on.
- [ ] Un-tie the D-side in `riscv_core_interface`: replace the constant tie-offs
      (`core_req_re_d = 0`, etc.) with ports routed up from LightningCore. Controller
      instance (`tony_d`) and the `choose_d_cache` arbitration stay as-is.
- [ ] Sanity-check arbitration under load: `choose_d_cache` gives D the bus
      unconditionally; confirm I-fetch can't be starved by store/miss streams
      (icacheloop + memstalltest are the existing probes).

## Phase 2 — DRIS changes

- [x] `mem_addr_ready` in `dris_entry_state_t`; the address itself lives in `result`.
- [x] ~~**Set `mem_addr_ready` for stores too.**~~ Done — `DRIS.sv:124` gates on
      `(memRead || memWrite)`. What is still wrong is that the same branch clears `executed`
      for stores; see the deadlock item in Build status.
- [ ] **Split writeback semantics by `ctrl_signals_W`** in `DRIS_ff.writeback_writes`. The
      three cases are distinct and only the third is the plain register-to-register path:
      - **load, phase 1** (from an ALU way): write the address into `result.result_data`, set
        `mem_addr_ready`, clear `dispatched` so the second schedule can re-pick it. Do NOT
        set `executed`, do NOT set `result_valid`, do NOT broadcast the locker unlock.
      - **store** (from an ALU way): write the address into `result.result_data`, set
        `mem_addr_ready` and `executed` — a store is complete once its address is shelved;
        retirement does the memory write. `result_valid` stays 0 (rd is x0; nothing locks).
      - **load, phase 2** (from the memory read port): write `result` + `result_valid`, set
        `executed`, broadcast the unlock. Identical to a register-to-register update, per the
        arch paper.
- [ ] **Color check on writeback.** Today a writeback is dropped only if the target entry is
      invalid. A multi-cycle in-flight load can outlive a flush *and* a refetch to the same
      index (fetch_ptr rolls back), landing data in a newborn entry. Compare
      `id_W.id_color` against the entry's color before accepting. Latent for 1-cycle ALU
      writebacks; real the moment memory latency exists.

## Phase 3 — the load's second schedule and the ID-tagged return

The return path is the part the earlier plan got wrong: it proposed matching responses by
`core_rsp_addr_d`. The architecture matches by **instruction ID**, and the reason is
structural — a non-blocking cache returns out of order, so the response must be
self-identifying. Address-matching only survives here because of the one-load-in-flight
deviation, and it silently becomes a correctness bug the moment a second load is allowed
(two loads to the same address are indistinguishable).

- [x] `MemoryScheduler.sv` scans `SCHEDULER_ENTRIES_CHECKED` entries from `retire_ptr`;
      load candidate = valid ∧ `memRead` ∧ `mem_addr_ready` ∧ `!executed` ∧ `!dispatched`.
- [x] Ready rule = the Phase 0 trichotomy (`check_older_writes`). Scanning the window from
      `retire_ptr` is sufficient: `retire_ptr` is the oldest entry, so every store older than
      a candidate at window position *i* sits at a position < *i*.
- [ ] Issue the oldest ready load only; set the once-only guard on issue.
- [ ] **Carry the DRIS ID with the request.** The ID is the index plus the color bit (arch
      paper: IDs are allocated in strict numerical order, *"toggling the color bit when the
      index portion wraps around"*). Track it alongside the in-flight request.
- [ ] **Return: ID in, entry located by ID, result field written, lockers broadcast.** The
      patent's Update is two simultaneous associative searches on the returning ID (FIG. 6):
      one against all instruction IDs to find where the data goes — *"the Issue ID CAF is
      searched with the ID of the executed instruction to find where the result should be
      placed"*, and *"the match outputs of these ports become write enables into the result
      field"* — and one against all locker IDs to unlock dependents.
      **[DEVIATION]** We index directly rather than CAM: our ID *is* the entry index, so the
      match degenerates into a lookup. That is only equivalent if the color is checked
      (Phase 2), which is what makes the direct index safe. Their ID CAF is a FIFO whose
      entries shift as instructions retire, so they had no fixed index to use.
      **[DEVIATION]** The 447 cache carries no tag through the controller, so the ID is held
      in a core-side in-flight tracker and re-attached on response rather than travelling
      with the request. Sound only for one load in flight.
- [ ] Response data path: sub-word extract + sign-extend (factor the `RDDataMux` byte/half
      logic out of `lib.sv` — it wants `ctrl_signals` + `byte_offset`), then a
      `dris_writeback_pkt_t` on the memory read port.
- [ ] Flush handling: on `mispredict_valid | trap_valid`, assert `core_req_cancel_d` for the
      in-flight speculative load and clear the tracker; the DRIS valid+color guard drops
      anything still in flight. `core_req_cancel_d` is currently hardwired to 0
      (`LightningCore.sv:282`) — check that against the controller's FSM, which the comment
      there claims cannot tolerate a mid-fill cancel.
- [x] `Scheduler.sv` keeps dispatching loads/stores through the ALU ways (that *is* the
      address computation), and `!mem_addr_ready` in its ready vector stops phase 1 from
      re-firing. This closes the TODO-IIU Phase 4 item about `ready_vector` not segregating
      loads/stores — the segregation happens at DRIS writeback semantics and retire, not at
      issue.

## Phase 4 — store commit path (SSC)

- [ ] Retire rule: a store may only retire from **slot 0** of the retire window (also
      serializes store-store, honoring `MEMORY_WRITE_PORTS = 1`). A store at slot > 0
      goes not-ready — the existing `retire_ready_vector` chaining then correctly holds
      back everything younger. Make the vector enforce what the code already assumes.
      **Promoted to correctness, not just serialization:** it is also what makes the Phase 0
      rs2-at-retire register-file read safe under multi-retire. See the caveat there.
- [ ] Gate the store's slot-0 readiness on D-cache acceptance (the Phase 1 handshake
      answer): retire stalls — store and all youngers — while the D-side is busy with a
      miss/eviction. Once accepted, same-cycle younger retires are fine (the cache orders
      subsequent reads). The registered-request bug that made "accepted" a cycle stale is
      fixed, so the SSC's same-cycle `d_cache_ready` check is now sound in timing; what it
      still needs is the Phase 1 answer about what acceptance actually guarantees.
- [ ] Drive the write: `core_req_we_d` + `core_req_addr_d` from the entry's `result`,
      `DataStoreMaskGenerator` + `DataMasker` at retire from `ldst_mode` +
      address `[1:0]` + rs2 read from the register file. Emit `memory_commit_pkt_t` (or
      delete the struct if direct wiring is cleaner — decide when wiring).
- [ ] Blocked-load release falls out for free: the unsafe rule tests "older store
      unretired"; retirement clears `valid`, and next cycle the load is safe. Confirm
      there's no same-cycle window where the load issues while the store's write is still
      in flight in the controller (2-cycle store vs same-cycle probe — check).
- [ ] Load/store D-side exceptions (`core_rsp_excpt_d`): set the entry's `trap` bit via the
      writeback, let the existing SSC trap path handle it. Low priority — note which tests
      (if any) exercise it.

## Phase 5 — integration and verification

- [ ] LightningCore: ~~fix the port-width mismatch~~ (done), ~~add the response ports~~ (done),
      route the D-side through `riscv_core_interface` (un-tie per Phase 1). Update the
      module-header comment (the "response half is not wired" paragraph) and CLAUDE.md.
      **Specifically stale now:** the NOTE at `LightningCore.sv:268-271` still says "the load
      return path is not built yet — `core_rsp_*_d` is brought to this module's boundary but
      not yet consumed." Lines 328-330 consume it. Delete that paragraph; it will send the
      next reader (or the next model) looking for a bug that is already fixed.
- [x] First target `lwtest` — **passes.**
- [ ] Next targets `memtest0`–`memtest2`; `memtest0` currently hangs on the store deadlock
      (Build status). `make verify-trace` on failures (cycle-by-cycle regfile diff). >60 s
      wall time = hang, kill and debug. Fastest repro for the deadlock is a 5-instruction
      single-`sw` program — it hangs, and swapping that `sw` for an `addi` terminates at 2300.
- [ ] Directed tests in `custom-tests/` (with `gen_ref_reg.sh` oracles): store→load same
      address (must wait for retire), load bypassing an older store with a *different* known
      address (must NOT wait), load blocked by an older store with an *unknown* address
      (the imprecise case), sub-word SB/LB/LH sign-extension, mispredict flushing an
      in-flight load, store at retire-slot > 0 (retire fencing), back-to-back stores.
      Re-run the existing customs: wbevict, wbevict2, memstalltest, load_branch_hazard,
      jalswtest.
- [ ] Full regression `make autograde LAB_18447=4b`, then `benchmarks/` and `benchmarksO3/`
      (first real workloads with memory traffic).
- [ ] Update TODO-IIU.md: strike the "only memory-free programs are correct" caveat and the
      `ready_vector` open item; syscalltest's `halted` fix (a0==0x0a) is tracked there.

## Deferred (performance, post-correctness)

- Store-to-load forwarding out of the DRIS — patent FIG. 5 has it on the unsafe path;
  measure before building.
- Multiple loads in flight / second D-cache port. **Requires the real ID-tagged return**
  (carry the ID through the controller, or a multi-entry in-flight tracker) — the current
  one-load shortcut does not generalize.
- Nonblocking D-cache with outstanding misses, as the CMB had.
- Relax store phase-1 gating on rs2 (address shouldn't wait on data) if it shows up.
- D-cache geometry sweep (`cache_sweep.py`) once behavior is correct. Lightning's external
  cache was physically addressed and direct-mapped, 128 KB–1 MB, serving as L1-data and
  L2-instruction (chipset §3.5) — **[DEVIATION]**, our geometry is set by `parameters.vh`
  and the inherited 2-cycle set-associative `cache3.sv`.
