# Phase 1 Debug Logs

Captured UART output from the MASTER (and one SLAVE) board during Phase 1
closure debug (XCAU15P, two-board optical link over BiDi SFP+).
Range: 2026-05-30 .. 2026-06-05.

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
