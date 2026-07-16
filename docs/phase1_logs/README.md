# Phase 1 Debug Logs

Captured UART output from the MASTER (and one SLAVE) board during Phase 1
closure debug (XCAU15P, two-board optical link over BiDi SFP+).
Range: 2026-05-30 .. 2026-06-07.

## CRITICAL — read before comparing any logs

These logs are **NOT all comparable to each other.** Three things changed
across the set; every one of them affects the numbers:

1. **Which channel the checker measured (`ch_mask`).**
   - `v1.3` logs (the four `20260530_111x` files): checker measured **CH1**.
   - `v1.5` and later: checker measured **CH0**.
   - Only **CH0 is physically connected** over fiber. CH1/CH2/CH3 are
     unconnected lanes — their RX data and RXBYTEREALIGN counts are noise
     (receiver listening to an open input), not link errors.
   - The `v1.3` "BER ~1e-4 on CH1" measured an **unconnected channel**. It is
     not a real link BER and must not be compared to any CH0 number.

2. **IP version (which RTL fixes are in the bitstream).** See the bug list below.
   - `v1.3`: pre-fix (no Bug #1, no loop timing, no TXCHARISK echo).
   - `v1.5` / `v1.7`: Bug #1 + loop timing + CH0 mask. **TXCHARISK bug (Bug #4)
     still present.**
   - `v1.9`: + Bug #4 fix (TXCHARISK echo restored through the cascade).

3. **Loopback configuration AND the partner board's state.** The MASTER's local
   `LOOPBACK` register alone does not identify a test — a far-end PMA test has the
   MASTER at `loopback=0` while the SLAVE reflects (`loopback=4`). So two files
   can both be named `loop_none` (MASTER lb=0) yet measure completely different
   paths (see `_2007` vs `_2316` in the file table). Always check the paired
   SLAVE log / context.

Also note the **log format changed**: `v1.3`/`v1.5` use per-trial `[DIAG]` dumps
(per-channel counters, XOR snapshots); `v1.7`+ use the compact verdict sweep
(`WER` / `BER(est)` / `comma` / `verdict` columns). Read the two formats
accordingly — the sweep reports rate bounds, the DIAG dump reports raw counters.

## The bugs found and fixes applied (in order)

1. **Bug #1 — TX user-data mux gating** (`murosync_serdes_array.sv:578`).
   SLAVE TX serializer was fed `64'h0` because `link_test_ctrl_en_core` is never
   asserted on SLAVE. Fixed to
   `(IS_SLAVE | link_test_ctrl_en_core) ? link_test_tx_data : 64'h0`.
   Symptom explained: constant `0x1717` low-word tail in RX data.

2. **Loop timing — SLAVE TX from RX recovered clock** (`murosync_gt_wrapper.sv`).
   On SLAVE the TX user clock is sourced from `rxoutclk_int[RX_MASTER_CH]` instead
   of `txoutclk_int[TX_MASTER_CH]`, with the TX userclk reset tied to the RX reset
   domain. Makes the cascade `rx_data_r <= rx_data` a frequency-coherent register.
   Effect: CH0 byte-aligned (RXBYTEISALIGNED 0xE -> 0xF), lock recovered on
   asymmetric patterns, RX correlated to TX.

3. **ch_mask 0x2 -> 0x1** (`main.c`). Measure the connected channel (CH0), not the
   floating CH1.

4. **Bug #4 — SLAVE TXCHARISK dropped through cascade**
   (`murosync_serdes_link_test.sv`). **Found 2026-06-05; this — not an eye/jitter
   floor — was the real source of the "~3e-4 dirty link".**
   - The `txctrl2_out` register had no `IS_SLAVE` branch. On the SLAVE `send_comma`
     is always 0 (TX comma FSM is gated off by `!IS_SLAVE`), so `txctrl2_out` was
     driven to `8'h00` every cycle. The cascade echoed RX *data*
     (`tx_data <= rx_data_r`) but not the K-symbol flags.
   - Consequence: each K28.5 comma the SLAVE received (one per `COMMA_PERIOD = 1024`
     cycles, from the MASTER) was re-encoded by the SLAVE 8B10B encoder as **data
     D28.5 = `0xBC`**, not as a control K28.5. Round-tripped to the MASTER it
     arrived as `rx_data = 0xBCBC` with `rxcharisk = 0`, so the MASTER's LOCKED
     K-skip (`any_ksymbol_r = |(rxcharisk & mask)`) did not skip it and the checker
     counted it as a data error.
   - Footprint (deterministic, not random noise): one error per ~1024 words,
     first-error data = `0xBC` pattern. `WER ~ 1/1024 ~ 9.8e-4`;
     `BER ~ (1/1024) * popcount(0xBCBC XOR pattern)/16` (~3.7e-4 for `0xAAAA`).
     Matches the pre-fix numbers quantitatively.
   - Fix (two edits): delay `rxcharisk` by one `tx_clk` (`rxcharisk_r`) to match the
     `rx_data -> rx_data_r -> tx_data` two-stage pipeline, and add an `IS_SLAVE`
     branch to `txctrl2_out` echoing
     `{rxcharisk_r[3],rxcharisk_r[3], ... rxcharisk_r[0],rxcharisk_r[0]}`
     (each per-channel bit duplicated for the 2 bytes per 16-bit slice).
   - Doc note: the IP-internals doc claimed this echo already existed (commit
     `6052c75`, "Lesson #7/#8"). It did **not** in the v1.7 source — the doc
     described intent, not shipped RTL. Doc to be corrected; verify with `git log -p`.

## 2026-06-05 diagnostic campaign — loopback decomposition

The "~3e-4 dirty link" was isolated by measuring CH0 under three loopback paths and
comparing. All three with `ch_mask=0x1`:

| Path | Config | Symmetric patterns | 0xBC | Floor when locked |
|---|---|---|---|---|
| PMA near-end (MASTER internal) | MASTER lb=2 (`_1940`) | lock, clean | no | ~1e-8 |
| PMA far-end (through fiber + both SFP+) | SLAVE lb=4 + MASTER lb=0 (`_2006`/`_2007`) | lock, clean | no | ~1e-8 |
| Cascade (normal, SLAVE echo) | SLAVE normal + MASTER lb=0 | lock | **yes** | ~3e-4 (pre-fix) |

Conclusions:
- **MASTER is clean** — PMA near-end at floor on all 7 patterns: fabric, 8B10B,
  SerDes, CDR all good.
- **Optics are clean** — PMA far-end at floor on every symmetric pattern that locks,
  through both fiber legs and both SFP+, no 0xBC. The eye is NOT the problem.
- **0xBC appears only in the cascade** — the one path that adds the SLAVE's
  8B10B-decode -> fabric-echo -> 8B10B-encode chain. That localised the fault to the
  SLAVE cascade and led directly to Bug #4.
- Asymmetric patterns (`12341234` / `12345678`) fail to lock in PMA far-end: a
  framing artifact of raw PMA reflection (symmetric patterns are byte-shift-invariant
  and tolerate the offset), **not** a fault.

This **supersedes** the earlier (v1.5) note that the residual was an "eye/jitter floor
on the real channel." It was not — it was Bug #4.

## Current state — after v1.9 (TXCHARISK fix)

**Bug #4 is fixed:** the `comma` column is empty across all patterns in the v1.9
cascade log (`_2316`) and no first-error shows the `0xBC` signature.

**But the link is not yet at the floor.** The residual is **not random run-to-run
noise — it is discretely multi-modal, and the mode is selected by the reset path.**
The link settles into one of a few fixed phase states; within a state the per-pattern
WER is reproducible (repeated runs match to within sampling noise), but the state can
jump by orders of magnitude.

Two states observed on the *same* v1.9 bitstream, `loopback=0` cascade, CH0:

| Pattern | State A (soft `GT_RESET_ALL`) | State B (full reconfig: bit then ELF) |
|---|---|---|
| 0xAAAAAAAA | 9.85e-4 | 1.41e-5 |
| 0x00000000 | 1.08e-6 | 1.13e-5 |
| 0xFFFFFFFF | 3.98e-6 | 4.45e-6 |
| 0x55555555 | 2.17e-3 (worst) | 1.63e-4 (worst) |
| 0x12121212 | 4.39e-6 | 7.84e-6 |
| 0x12341234 | locks @ ~9.4e-4 | **does not lock** |
| 0x12345678 | locks @ ~9.8e-4 | **does not lock** |

A given pattern flips good<->bad between states (e.g. `0x55555555`: worst in A, still
worst but 13x lower in B; `0xAAAAAAAA`: 70x lower in B), so no pattern is intrinsically
"hard" — what is marginal is the **pattern x phase** interaction. Within a state, the
worst patterns are the high-transition-density ones (`AAAA`, `5555`); the cleanest are
low-density (`0000`, `FFFF`). Patterns flagged `FAIL` at WER far below the FAIL
threshold are structural (`last_state != LOCKED` at sample), not rate-driven.

A fixed eye/jitter floor cannot switch in a step with the load method. The cause is a
**fixed phase offset captured at reset** — different reset paths bring the GT clocks to
a different mutual phase, each phase giving its own setup/hold profile.

The reference points bracket it: PMA near-end (`_1940`) and PMA far-end (`_2007`) are
both at the floor; the residual lives in the SLAVE cascade *between* them — the chain
far-end PMA bypasses. Leading suspect: the `rx_usrclk2 -> tx_usrclk2` crossing in the
fabric echo (`rx_data_r <= rx_data`). Loop timing (fix #2) made the two clocks
frequency-coherent, but if they are separate `BUFG_GT` outputs there is a fixed phase
offset and the single-flop echo is marginal.

Open (lower priority): asymmetric patterns (`12341234` / `12345678`) lock in State A
but not in State B — i.e. their lock tracks the phase state, so this is part of the
same phase profile, not a separate byte-order bug. Should clear with the clocking fix;
if not, revisit a 16-bit-slice byte-order effect (`0x1234` <-> `0x3412`) afterward.

**Phase 1 is not closed on these numbers.** Next:
- Discriminator (no rebuild): far-end PCS loopback (`loopback=0b110=6`) on the SLAVE —
  exercises 8B10B decode+encode but bypasses the fabric echo. Floor -> residual is the
  fabric crossing; not floor -> it's in the PCS.
- Static (no rebuild): `report_clock_interaction` / `report_cdc` on the SLAVE build —
  confirm whether `rx_usrclk2` / `tx_usrclk2` are separate clocks and whether
  `rx_data -> rx_data_r` is flagged.
- Candidate fix if the crossing is confirmed: shared GT clocking for the repeater (one
  `BUFG_GT` off `RXOUTCLK` feeding both user clocks) so the echo is single-domain and
  the phase is no longer a free variable.
- **Validate the fix against the multi-modality, not a single run:** re-test through
  *every* reset path — soft `GT_RESET_ALL`, full reconfig (bit then ELF), and a power
  cycle. Phase 1 closes only if the per-pattern profile is identical across all load
  methods AND at the floor. A good number from one reset path is not a result while the
  phase remains a degree of freedom (State B's `1.4e-5` would still degrade to State
  A's `~2e-3` after a power cycle).
- Then a long-form BER run to close Phase 1.

## 2026-06-07 — v1.10 NEAR_PMA vs EXTERNAL, single-run discriminator

Log: `20260607_1446_loop_near_pma_vs_external_serdes_v1.10_master.log` (IP **v1.10**, firmware **v1.122**).

IP advanced v1.9 -> v1.10: **per-byte K-marker plumb-through** through the SLAVE
cascade (`RXCTRL0[7:0]` byte-resolution, replacing v1.9's 4-bit duplicated
`rxcharisk`). This is a refinement of the Bug #4 cascade-K-symbol area, not a new
bug class. (Numbering note: the v1.10 commit message labels this "bug #1" — that
collides with **this** README's Bug #1 = TX-mux gating. The README's #1..#4
numbering is the canonical one here; reconcile the commit wording when convenient.)

A single firmware build now runs the discriminator as an **A/B in one boot**:
NEAR_PMA sweep (MASTER internal, `loopback=2`), then restore the external cascade
(`loopback=0`, SLAVE echoing) and re-run the same sweep. One reset, both paths —
directly comparable, none of the cross-run caveats in the CRITICAL section apply.

| Pattern | NEAR_PMA (internal) | EXTERNAL (cascade + fiber) |
|---|---|---|
| 0xAAAAAAAA | < 4.7e-9 (realign 2) | 2.5e-6 (realign 2) |
| 0x00000000 | 6.3e-9 | 2.5e-6 |
| 0xFFFFFFFF | < 4.7e-9 | 6.6e-7 |
| 0x55555555 | < 4.7e-9 | 4.7e-6 |
| 0x12121212 | < 4.7e-9 | 8.4e-7 |
| 0x12341234 | **does not lock** (realign 0) | realign **1493**, WER 1.3e-3 |
| 0x12345678 | **does not lock** (realign 0) | realign 8, WER 1.5e-5 |

Long-form external: `0x12341234` realign(test) 1336, WER 1.48e-3, first-error XOR
`0x0200` (1 bit, byte1: `0x1034` vs `0x1234`) — a byte-slip signature, not a bit
error. `0xAAAAAAAA` realign 0, WER 7.2e-6.

**This re-confirms the 2026-06-05 decomposition in a single run, and tightens it:**

- **MASTER internal is sub-1e-9, not "~1e-8".** Every symmetric pattern in NEAR_PMA
  is at `< 4.7e-9` (zero errors, rule-of-three bound). The earlier `~1e-8` (`_1940`)
  was a coarser bound — the MASTER PCS / SerDes / eye is effectively perfect.
- **The residual is external, and it is realign-driven.** `0x12341234` shows
  realign(test) **0 internal / ~1493 external** — the false-comma re-alignment that
  produces the ~1e-3 WER happens **only on the external path** (SLAVE cascade +
  fiber), never in the MASTER receiver. The realign counter makes this explicit,
  beyond the earlier 0xBC / floor evidence.
- **The ~e-6 symmetric floor is entirely external-path.** Internal `< 4.7e-9` vs
  external `~e-6` on the same patterns — the eye/jitter floor on the real link is the
  cascade + optics, not silicon.

**On asymmetric-not-locking in NEAR_PMA (no contradiction):**
`0x12341234`/`0x12345678` fail to lock in NEAR_PMA here while symmetric patterns are
clean. This is the **same raw-PMA-reflection framing artifact already documented for
far-end PMA** in the 2026-06-05 campaign — symmetric patterns are byte-shift-invariant
and tolerate the reflection's byte offset; asymmetric ones do not. It is **not** a
fault, and it does **not** conflict with the `_1940` "all 7 lock at floor" note —
`_1940` caught a favorable byte-phase; asymmetric lock through any PMA reflection is
phase-dependent (cf. the State A/B lock behaviour in "Current state").

**Relation to the State A/B hypothesis:** this run was a single reset, so it does not
itself probe the reset-selected multi-modality. What it adds is a clean localisation —
the realign mechanism behind the asymmetric residual lives on the **external** path.
Whether the reset-captured phase offset (leading suspect: `rx_usrclk2 -> tx_usrclk2`
in the fabric echo) is the same root that modulates the realign rate is still open;
the next steps in "Current state" (PCS far-end `loopback=6` on the SLAVE;
`report_clock_interaction` / `report_cdc`) remain the way to settle it.

> Firmware here is v1.122 (settle-gate + NEAR_PMA/external A/B sequencing) on v1.10
> gateware. The settle-gate's `CH0 aligned stable` / `CDR settle` lines appear only in
> the external phase. Firmware and gateware versions advance independently — see banner.

## 2026-06-07 — clock-crossing hypothesis DISPROVEN (static, SLAVE build)

Static check on the **SLAVE** implemented design (`impl_1`, IP v1.10). Artifact:
`20260607_1522_static_cdc_clkint_serdes_v1.10_slave.log` (`report_cdc` +
`report_clock_interaction` + cell-property / userclk trace). This closes the
"Current state" Next item "Static (no rebuild): report_clock_interaction / report_cdc
on the SLAVE build."

**Board confirmed SLAVE, fix #2 present in silicon:**
- `IS_SLAVE = 1'b1`, `IS_MASTER = 1'b0` — read off the serdes cell. The reports
  are therefore on the board where the cascade echo actually lives.
- TX userclk is driven from `rxoutclk_int` (not `txoutclk`): the `u_userclk_tx`
  clock input net traces to `.../u_gtw/rxoutclk_int`. Fix #2 is in the netlist —
  TX is folded into the recovered-RX domain.

**`report_clock_interaction`:** the serdes echo domain
`rxoutclk_out[0] -> rxoutclk_out[0]` is **Clean, 0 failing, 2171 endpoints,
WNS +0.86 ns**. There is **no separate `txoutclk` domain** and **no
`rxoutclk <-> txoutclk` row** — TX and RX user clocks are the same BUFG_GT output.
The `rx_data_r <= rx_data` echo register is single-domain; it does not cross an
async boundary.

**`report_cdc`:** the large `rxoutclk_out[0] -> clk_wiz` crossing (773 EP, 11
unsafe, 363 unknown) — and the symmetric `clk_wiz -> rxoutclk_out[0]` (162 EP) —
is the **AXI / debug 100 MHz domain** (diagnostic registers), marked Asynchronous
Groups / Ignored. It is not the serdes data path and is unrelated to the residual.

**Conclusion — the "Current state" leading suspect is wrong.** The
`rx_usrclk2 -> tx_usrclk2` fixed-phase-offset hypothesis is **disproven**: fix #2
already made the repeater single-domain, and that domain is clean with positive
slack. **Do NOT do the shared-BUFG_GT repeater fix — it is already effectively
done.** Like the earlier PPM hypothesis, the measurement overturned the theory.

The external residual (mechanism A: false-comma realign on `0x12341234`, realign 0
internal / ~1493 external per the NEAR_PMA run above) is therefore **not** a clock
crossing. It is localised to either the **SLAVE PCS decode/encode tract** or the
**fabric echo on data** (the data path through `rx_data_r`, which is timing-clean
but may still be functionally wrong on asymmetric words) — not the clock domains.

**This also re-frames the State A/B multi-modality.** With the clock crossing ruled
out, the reset-selected step-changes are unlikely to be a clock *phase* offset. More
likely the reset path selects whether the asymmetric patterns achieve byte-lock at
all (cf. their lock/no-lock flip between State A and B) — i.e. a framing/lock-phase
lottery, not a setup/hold phase. The PCS far-end `loopback=6` test is the way to
confirm.

**Remaining discriminator (unchanged):** PCS far-end `loopback=6` on the SLAVE —
exercises the SLAVE 8B10B decode+encode but bypasses the fabric echo. Dirty
(realign ~1500) → residual is in the PCS tract (frame-layer / Phase 2 territory).
Clean (<1e-9) → residual is the fabric-echo-on-data, a targeted RTL fix. After this
one behavioural test: **fix, do not measure** — three of four hypotheses are now
dead (PPM, optics/MASTER-eye, clock-crossing).

## Naming convention

`YYYYMMDD_HHMM_<test_type>[_<tag>]_serdes_v<X.Y>_<board>.log`

`<tag>` is optional, used to disambiguate otherwise-similar runs (e.g. `ch0` marks
that the checker measured CH0). `v<X.Y>` is the **IP** version (the firmware version
is separate, shown in the banner).

## Files

| File | IP ver | Loopback | Measured ch | Notes |
|---|---|---|---|---|
| `20260530_002401_master.log` | mixed | — | — | Raw ~24h debug-session capture (147 KB, pre-matrix). |
| `20260530_1110_loop_none_serdes_v1.3_master.log` | v1.3 | NONE (0x0) | CH1 (noise) | Pre-fix external loop. CH1 unconnected. |
| `20260530_1113_loop_pcs_near_serdes_v1.3_master.log` | v1.3 | NEAR (0x1) | CH1 (noise) | Pre-fix PCS digital loopback (MASTER). |
| `20260530_1116_loop_pma_near_serdes_v1.3_master.log` | v1.3 | FAR (0x2) | CH1 (noise) | Pre-fix PMA near-end loopback (MASTER). |
| `20260530_1117_loop_pma_far_serdes_v1.3_master.log` | v1.3 | EXT (0x4) | CH1 (noise) | Pre-fix PMA far-end via SLAVE reflection. |
| `20260531_1302_loop_none_ch0_serdes_v1.5_master.log` | v1.5 | NONE (0x0) | **CH0 (real)** | Post Bug#1 + loop-timing. First locked link on the connected channel. (Residual here was Bug #4, not eye/jitter.) |
| `20260605_1940_loop_pma_near_serdes_v1.7_master.log` | v1.7 | FAR (0x2) | CH0 | PMA near-end (MASTER internal). All 7 patterns lock at floor (~1e-8). MASTER path proven clean. Verdict-sweep format. |
| `20260605_2006_loop_pma_far_serdes_v1.7_slave.log` | v1.7 | EXT (0x4) | — | SLAVE side of the far-end PMA test (pure repeater — no checker / no sweep). Pairs with `_2007`. |
| `20260605_2007_loop_none_serdes_v1.7_master.log` | v1.7 | NONE (0x0) *local* | CH0 | **Far-end PMA measurement** — MASTER lb=0 but the SLAVE was reflecting (lb=4, see `_2006`). Symmetric patterns at floor, no 0xBC; asymmetric don't lock (raw-reflection framing). NOT a normal cascade. |
| `20260605_2316_loop_none_serdes_v1.9_master.log` | v1.9 | NONE (0x0) | CH0 | **True cascade**, post-Bug#4 fix. SLAVE ran its normal echo. `comma` column empty (0xBC gone). This is **State A** (soft `GT_RESET_ALL`): WER `1e-6..2.2e-3` by pattern. See "Current state" for the reset-selected State A/B multi-modality. Phase 1 not yet closed. |
| `20260607_1446_loop_near_pma_vs_external_serdes_v1.10_master.log` | v1.10 | FAR (0x2) -> NONE (0x0), A/B one run | CH0 | **Single-run discriminator.** NEAR_PMA (MASTER internal) then external cascade in one boot. Internal: symmetric **< 4.7e-9 (CLEAN)** — tightens the v1.7 ~1e-8. External: symmetric ~e-6; `0x12341234` realign **1493** / WER 1.3e-3. **The asymmetric residual (false-comma realign) is external: realign 0 internal / ~1493 external.** Asymmetric don't lock in NEAR_PMA = same raw-PMA-reflection framing artifact as far-end (not a fault). Firmware v1.122 (settle-gate). |
| `20260607_1522_static_cdc_clkint_serdes_v1.10_slave.log` | v1.10 | — (static, SLAVE impl) | — | **Static timing artifact, NOT a UART log.** `report_cdc` + `report_clock_interaction` + cell-property / userclk trace on the SLAVE `impl_1`. Confirms `IS_SLAVE=1'b1`, TX userclk from `rxoutclk_int` (fix #2), echo domain `rxoutclk_out[0]` Clean (0 failing, +0.86 ns), no separate txoutclk domain. **Disproves the clock-crossing hypothesis** — do not do the shared-BUFG_GT fix. |

## Loopback constant mapping (driver)

| Constant | Numeric | Description |
|---|---|---|
| `MUROSYNC_SERDES_LOOPBACK_NONE` | 0x0 | Normal external (through SLAVE) |
| `MUROSYNC_SERDES_LOOPBACK_NEAR` | 0x1 | PCS near-end (digital) |
| `MUROSYNC_SERDES_LOOPBACK_FAR`  | 0x2 | PMA near-end (analog SerDes, MASTER only) |
| `MUROSYNC_SERDES_LOOPBACK_EXT`  | 0x4 | PMA far-end (via SLAVE PMA reflection) |

Note: the constant *names* don't match the near/far semantics intuitively
(`FAR` = PMA near-end, `EXT` = PMA far-end). Trust the numeric + description, not the
name. `loopback=0b110=6` (PCS far-end) has no driver constant yet — see "Next" above.
