# Phase 1 Debug Logs

Captured UART output from the MASTER board during Phase 1 closure debug
(XCAU15P, two-board optical link over BiDi SFP+).

## CRITICAL — read before comparing any logs

These logs are **NOT all comparable to each other.** Two things changed
across the set and both affect every number in the logs:

1. **Which channel the checker measured (`ch_mask`).**
   - `v1.3` logs (the four `20260530_111x` files): checker measured **CH1**.
   - `v1.5` log (`20260531_1302`): checker measured **CH0**.
   - Only **CH0 is physically connected** over fiber. CH1/CH2/CH3 are
     unconnected lanes — their RX data and RXBYTEREALIGN counts are noise
     (receiver listening to an open input), not link errors.
   - Therefore the `v1.3` "BER ~1e-4 on CH1" was measuring an **unconnected
     channel**. It is not a real link BER and must not be compared to the
     `v1.5` CH0 numbers.

2. **IP version (which RTL fixes are in the bitstream).**
   - `v1.3`: pre-fix (neither Bug #1 nor loop timing).
   - `v1.5`: Bug #1 fix + loop timing fix applied.

When comparing logs, always check BOTH the IP version (banner: "IP version")
and which channel `Per-CH errors` is non-zero on (that's the measured channel).

## The three fixes (in order applied)

1. **Bug #1 — TX user-data mux gating** (`murosync_serdes_array.sv:578`).
   SLAVE TX serializer was fed `64'h0` because `link_test_ctrl_en_core` is
   never asserted on SLAVE (firmware never calls `_start()` there). Fixed to
   `(IS_SLAVE | link_test_ctrl_en_core) ? link_test_tx_data : 64'h0`.
   Symptom it explained: constant `0x1717` low-word tail in RX data.

2. **Loop timing — SLAVE TX from RX recovered clock** (`murosync_gt_wrapper.sv`).
   Added `IS_SLAVE` param; on SLAVE the TX user clock is sourced from
   `rxoutclk_int[RX_MASTER_CH]` instead of `txoutclk_int[TX_MASTER_CH]`, and
   the TX userclk reset is tied to the RX reset domain (avoids a startup race
   where TX BUFG_GT releases CLR on an unlocked recovered clock). This makes
   the link_test cascade `rx_data_r <= rx_data` a safe same-clock register.
   `IS_SLAVE` plumbed through the `u_gtw` instance in `murosync_serdes_array.sv`.
   Effect: CH0 finally byte-aligned (RXBYTEISALIGNED 0xE -> 0xF), lock
   recovered on asymmetric patterns (12341234), RX data correlated to TX.

3. **ch_mask 0x2 -> 0x1** (`main.c`, `phase1_test_one_pattern`).
   Measure the connected channel (CH0), not the floating CH1.

## Result after all three fixes (v1.5, CH0)

- `RXBYTEISALIGNED = 0xF` (all lanes show aligned; only CH0 meaningful).
- `at_lock` CH0 = expected pattern on all 7 trials, including asymmetric
  12341234 and 12345678.
- Residual post-lock errors on CH0 (~1-8 bit XOR per first-error) are an
  eye/jitter floor on the real channel, not a data-path bug. This is the
  honest starting point for BER optimization / long-form measurement.

## Naming convention

`YYYYMMDD_HHMM_<test_type>[_<tag>]_serdes_v<X.Y>_<board>.log`

`<tag>` is optional and used to disambiguate otherwise-similar runs
(e.g. `ch0` marks that the checker measured CH0).

## Files

| File | IP ver | Loopback | Measured ch | Notes |
|---|---|---|---|---|
| `20260530_002401_master.log` | mixed | — | — | Raw ~24h debug-session capture (147 KB, pre-matrix). |
| `20260530_1110_loop_none_serdes_v1.3_master.log` | v1.3 | NONE (0x0) | CH1 (noise) | Pre-fix external loop. CH1 unconnected. |
| `20260530_1113_loop_pcs_near_serdes_v1.3_master.log` | v1.3 | NEAR (0x1) | CH1 (noise) | Pre-fix PCS digital loopback (MASTER). |
| `20260530_1116_loop_pma_near_serdes_v1.3_master.log` | v1.3 | FAR (0x2) | CH1 (noise) | Pre-fix PMA analog loopback (MASTER). |
| `20260530_1117_loop_pma_far_serdes_v1.3_master.log` | v1.3 | EXT (0x4) | CH1 (noise) | Pre-fix PMA far-end via SLAVE reflection. |
| `20260531_1302_loop_none_ch0_serdes_v1.5_master.log` | v1.5 | NONE (0x0) | **CH0 (real)** | Post Bug#1 + loop-timing. First clean link on connected channel. |

## Loopback constant mapping (driver)

| Constant | Numeric | Description |
|---|---|---|
| `MUROSYNC_SERDES_LOOPBACK_NONE` | 0x0 | Normal external (through SLAVE) |
| `MUROSYNC_SERDES_LOOPBACK_NEAR` | 0x1 | PCS near-end (digital) |
| `MUROSYNC_SERDES_LOOPBACK_FAR`  | 0x2 | PMA near-end (analog SerDes, MASTER only) |
| `MUROSYNC_SERDES_LOOPBACK_EXT`  | 0x4 | PMA far-end (via SLAVE PMA reflection) |

Note: the constant *names* don't match the near/far semantics intuitively
(`FAR` = PMA near-end, `EXT` = PMA far-end). Trust the numeric + description,
not the name.
