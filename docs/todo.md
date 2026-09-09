# TODO

Ordered. Rule of thumb: measure before building, and keep something
hour-sized at the top so a spare hour is spendable.

## Now

- [ ] **Finish the load-admission counters.** Uncommitted in the tree
  (`MemoryScheduler.sv` + `LightningCore.sv`, since ~2026-08-31). Splits a
  non-issuing load into D$-busy / older-store-addr-unknown / older-store-alias.
  Sizes both memory items below. ~1h.
  - [ ] Gate on `issue_count < TOTAL_PORTS`; today a load that lost the port
    counts in `load_ready_cycles` with no reason set. Label the residual
    port contention, or the three won't sum to ready.
  - [ ] Note in `perf-counters.md` that `blk_alias` is exact word-address
    equality (inherited from `check_older_writes`) — partial overlaps
    aren't counted, so it's a lower bound.
  - [ ] Run fibi + spmv under the T-2022.06 pin, record numbers.

## Next, once the counters have spoken

- [ ] **Store-to-load forwarding.** Only if `blk_alias` is non-trivial.
  Near-zero ⇒ drop this item.
- [ ] **Non-blocking D$.** Only if `blk_dcache` dominates. See
  `new-cache-wishlist.md` (items 2 and 3 first).

## The design work

- [ ] **Split the scheduler** into an N-entry ready-finder + per-op
  dispatchers. Load-bearing: makes dedicated memory ALUs and a mul/div
  unit cheap. The one item with real design content.

## No discovery in these — timebox or defer

- [ ] **Synthesis chain.** `synth/dc_synth.tcl`, `riscv_core_timing.sv`.
- [ ] **DRIS rewrite.** Readability only; risks 53 passing tests.
  `DRIS.sv` (415) + `NewDris.sv` (150) + `1DRIS_defs.sv` (348).

## Last

- [ ] **kosarajus livelock.** Capacity-dependent: 8/4 completes in 19.3M
  cycles, 32/32/8 hangs at 112,300 retired. Unbounded debug — bad
  candidate for a scrounged hour.
- [ ] **X-at-reset bug** under VCS Y-2026.03 (see CLAUDE.md pin).
