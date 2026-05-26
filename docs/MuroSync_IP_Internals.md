# MuroSync `murosync_serdes_array` — IP Internals Reference

**Status:** v1.0 — companion to `MuroSync_Dev_Bench_Architecture_v1.1.md`
**Source of truth:** RTL files extracted 2026-05-26
- `murosync_serdes_array.sv` (747 lines)
- `murosync_serdes_array_axi_ctrl.sv` (834 lines)
- `murosync_serdes_link_test.sv` (813 lines)
- `murosync_gt_wrapper.sv`
- `murosync_cdc_level_sync.sv`
- PG182 (UltraScale Transceivers Wizard v1.7)

**Purpose:** complete the gaps that v1.1 left open. v1.1 describes WHAT the system is. This document describes HOW the IP behaves at RTL level — what each bit does, what each FSM state means, what each register holds. Read this when:
- debugging why CHECKER_LOCKED won't assert,
- adding a new AXI register,
- understanding what pattern is on the wire in a given mode,
- writing or modifying firmware that touches the link test engine.

---

## §0 TL;DR cheatsheet

| Need to… | Section |
|---|---|
| Understand TX pattern bytes on the wire | §2.2 |
| Understand RX checker FSM transitions (Phase 1 blocker) | §3.2 |
| Look up register offset | §5.1 |
| Decode `LNK_TEST_CNFG` for `WR cnfg <value>` | §5.3 |
| Decode `LNK_DIAG_STATUS` | §5.4 |
| Decode `LNK_DIAG_STATUS2` (ever_locked, last_fsm_state) | §5.4 |
| Decode `DBG_LO/HI` (ILA bus also) | §6 |
| Understand SLAVE vs MASTER mode at RTL level | §1 |
| Choose LOOPBACK value | §4 |
| Read time_to_lock / err_cnt_ch / rx_data_at_lock | §7 |

---

## §1 Mode polarity: SLAVE vs MASTER

**Module parameter:** `parameter string MODE = "MASTER"` (top of `murosync_serdes_array`).
Derived inside body (NOT exposed to IP Packager — see Lesson #6):
```systemverilog
localparam bit IS_SLAVE  = (MODE == "SLAVE");
localparam bit IS_MASTER = (MODE == "MASTER");
```

**What changes between modes:**

| Aspect | SLAVE | MASTER |
|---|---|---|
| Optical SFP cage | SFP1 silkscreen (RTL wizard[0]) | SFP1..SFP4 |
| RX pin assignment | `muro_gth_slave` (CH0) + `muro_gth_aux_{0..2}` (CH1..3) | `muro_gth_master_{0..3}` |
| TX pin assignment | same — outputs to slave/aux pins, others tied 0 | outputs to master pins, others tied 0 |
| TX data source (in `link_test`) | `tx_data <= rx_data_r` (1-cycle delayed RX) | pattern generator (FIXED/TOGGLE/COUNTER) |
| TXCHARISK | echoes RXCHARISK (preserves K-symbols through cascade) | comma FSM drives during K28.5 burst |
| TX Comma FSM | stuck in `TX_ST_IDLE` (`!IS_SLAVE` guard at line 220, 225, 233) | runs IDLE→TRAINING→MAINTENANCE |
| RX Checker FSM | stuck in `RX_ST_IDLE` (`!IS_SLAVE` guard at line 665) | runs IDLE→CAPTURE_CFG→WAIT_ALIGN→SEARCH→LOCKED |

**Implication for firmware:** in SLAVE mode, `LNK_RX_ERR_CNT` and `LNK_RX_WRD_CNT` stay at 0, `LNK_DIAG_STATUS[3:0]` stays at `RX_ST_IDLE (0)`, `ever_locked` stays 0. Don't expect link test telemetry from SLAVE — it's a pure repeater. The BER measurement happens on the MASTER side.

**Cascade loopback** = the SLAVE's fabric echo (`tx_data <= rx_data_r`, line 311). Adds 1 tx_clk cycle of latency. K-symbols preserved because TXCHARISK is also echoed (line 299-302). This is **NOT** a GT loopback (see §4); it lives in fabric RTL.

---

## §2 TX path (MASTER)

### §2.1 TX Comma FSM

3 states (`localparam integer TX_ST_IDLE=0, TX_ST_TRAINING=1, TX_ST_MAINTENANCE=2`):

```
                tx_enable && !IS_SLAVE
       IDLE ──────────────────────────► TRAINING
        ▲                                    │
        │                                    │ comma_cnt == TRAIN_LEN-1
        │                                    │ (4096 cycles)
        │                                    ▼
        │    comma_cnt == COMMA_PERIOD-1     │
        └──── MAINTENANCE ◄───────────  MAINTENANCE
       !tx_en   (every 1024 cycles
       or IS_   one comma cycle)
       SLAVE
```

**Constants** (compile-time, NOT AXI tunable; in `murosync_serdes_link_test.sv` lines 145-149):
```systemverilog
localparam logic [7:0] K28_5        = 8'hBC;  // K28.5 = 0xBC in 8-bit (8B10B encoder produces wire symbol)
localparam integer     TRAIN_LEN    = 4096;   // ~13 µs at 312.5 MHz
localparam integer     COMMA_PERIOD = 1024;   // ~3.3 µs
```

**Wire behavior:**
- `TX_ST_TRAINING`: `tx_data = {8{K28_5}} = 64'hBC_BC_BC_BC_BC_BC_BC_BC`, `txctrl2_out = 8'hFF` (all bytes are K-symbols)
- `TX_ST_MAINTENANCE`: when `comma_cnt == COMMA_PERIOD-1`, ONE cycle of K28.5 burst (`send_comma=1`); other 1023 cycles pattern data
- otherwise normal pattern with `txctrl2_out = 8'h00`

**Diagnostic:** `LNK_DIAG_TX_STATUS` (0x054): `[0]=tx_comma_active`, `[12:1]=comma_cnt`. Reading this lets firmware verify the comma engine is running.

### §2.2 TX Pattern Generator

`tx_test_mode = cnfg[1:0]` (latched on rising edge of `tx_enable`, line 162):

| Mode | Code | Wire bytes (64-bit per tx_clk cycle, then per-channel polarity) |
|---|---|---|
| FIXED | 0b00 | `tx_data = {fixed_patt, fixed_patt}` — same 32-bit `fixed_patt` (from `LNK_TEST_PATT` reg) duplicated to 64 bits |
| TOGGLE | 0b01 | alternates every cycle between `tx_fixed_64` and `~tx_fixed_64` (toggle_state toggles each cycle while tx_enable) |
| COUNTER | 0b10 | `{ch3, ch2, ch1, ch0}` packed 16-bit each. Each `counter_val_ch[i]` is independent 16-bit counter, +1 every cycle, reset to 0 on `tx_reset_pulse`. **All 4 channels share the same start value (0)** — they're synchronized counters, not staggered |

**TX polarity mask:** `cnfg[15:12]` per channel. Applied AFTER pattern generation (lines 324-327):
```systemverilog
tx_data[15:0]  <= tx_pol_mask[0] ? ~raw[15:0]  : raw[15:0];   // CH0
tx_data[31:16] <= tx_pol_mask[1] ? ~raw[31:16] : raw[31:16];  // CH1
tx_data[47:32] <= tx_pol_mask[2] ? ~raw[47:32] : raw[47:32];  // CH2
tx_data[63:48] <= tx_pol_mask[3] ? ~raw[63:48] : raw[63:48];  // CH3
```

This is for boards with inverted optical/electrical polarity (e.g. inverted SFP pair). Per channel.

**8B10B validity:** all 3 patterns are RAW 32-bit/64-bit values passed to TXDATA. The GT's 8B10B encoder (always enabled, `tx8b10ben_in = 4'hF`) encodes each byte. If you pick `fixed_patt = 0xFFFFFFFF`, the encoder produces a valid 8B10B disparity-balanced sequence; same for 0x55555555 etc. There's no validity check in RTL — TXDATA bytes are just blindly encoded. K-symbols are signaled separately via `txctrl2_out`.

**Diagnostic:**
- `LNK_DIAG_TX_DATA_LO/HI` (0x044/0x048): current `tx_data` snapshot
- `LNK_DIAG_TX_COUNTERS_LO` (0x04C): `{ch1_cnt[15:0], ch0_cnt[15:0]}`
- `LNK_DIAG_TX_COUNTERS_HI` (0x050): `{ch3_cnt[15:0], ch2_cnt[15:0]}`

### §2.3 SLAVE TX (cascade loopback)

In SLAVE mode the FSM is bypassed entirely:
```systemverilog
if (IS_SLAVE)         tx_data <= rx_data_r;       // 1-cycle delay of rx_data
else if (send_comma)  tx_data <= {8{K28_5}};
else                  tx_data <= /* pattern */;
```

The SLAVE pumps received bytes back to the MASTER. The cascade loopback path is therefore:
```
MASTER TX → fiber → SLAVE RX → 1 tx_clk reg → SLAVE TX → fiber → MASTER RX
```
Round-trip latency includes both fiber propagation + 1 tx_clk_2 cycle of SLAVE fabric delay.

**Critical for K-symbol preservation** (Lesson #7, commit 6052c75):
```systemverilog
if (IS_SLAVE) txctrl2_out <= {rxcharisk[3], rxcharisk[3],
                              rxcharisk[2], rxcharisk[2],
                              rxcharisk[1], rxcharisk[1],
                              rxcharisk[0], rxcharisk[0]};
```
Each `rxcharisk[ch]` bit is duplicated because each 16-bit channel slice carries 2 bytes (each with its own TXCHARISK bit). Without this, MASTER would receive its own K28.5 commas back as D-symbols → checker mismatch.

---

## §3 RX path (MASTER)

### §3.1 RX Polarity Mask

`rx_pol_mask = cnfg[11:8]`, applied to `rx_data` → `rx_data_corrected` BEFORE any matching (lines 365-368). Symmetric to TX polarity mask: per-channel XOR inversion to compensate inverted optical/electrical polarity.

### §3.2 RX Checker FSM (complete — Phase 1 critical)

5 states. RX_ST_IDLE=0, RX_ST_CAPTURE_CFG=1, RX_ST_WAIT_ALIGN=2, RX_ST_SEARCH=3, RX_ST_LOCKED=4.

```
                                                  rx_enable && !IS_SLAVE && !rx_reset_pulse
                ┌────────────────────────────────────────────────────┐
                │                                                    ▼
              IDLE ◄────── (any state: !rx_enable || rx_reset_pulse)
                                                                  CAPTURE_CFG  (1 cycle)
                                                                     │
                                                                     │ unconditional
                                                                     ▼
                                                                  WAIT_ALIGN
                                                                     │
                                                                     │ aligned_or_nomask_r
                                                                     │ (all masked ch's have
                                                                     │  rxbyteisaligned set
                                                                     │  OR previously seen)
                                                                     ▼
                                                                  SEARCH
                                                                     │
                                                                     │ !any_ksymbol_r && match_any
                                                                     │ (current word is NOT K-symbol
                                                                     │  AND matches FIXED, TOGGLE+,
                                                                     │  TOGGLE-, or COUNTER expectation)
                                                                     ▼
                                                                  LOCKED  ──┐
                                                                     ▲      │ never auto-exits;
                                                                     └──────┘ counts errors but stays
```

**State transitions with exact RTL conditions:**

| From | To | Condition |
|---|---|---|
| IDLE | CAPTURE_CFG | `rx_enable && !IS_SLAVE && !rx_reset_pulse` (line 665) |
| CAPTURE_CFG | WAIT_ALIGN | unconditional after 1 cycle (line 676); on this cycle `capture_cfg=1` latches `rx_test_mode`, `rx_fixed_64`, `rx_ch_mask`, `rx_pol_mask` from `cnfg`/`fixed_patt` |
| CAPTURE_CFG | IDLE | `!rx_enable \|\| rx_reset_pulse` |
| WAIT_ALIGN | SEARCH | `aligned_or_nomask_r` (line 685) — see §3.3 below |
| WAIT_ALIGN | IDLE | `!rx_enable \|\| rx_reset_pulse` |
| SEARCH | LOCKED | `lock_acquired = !any_ksymbol_r && match_any` (line 692); also sets `next_expected_rx` for FIXED/TOGGLE/COUNTER mode |
| SEARCH | IDLE | `!rx_enable \|\| rx_reset_pulse` |
| LOCKED | LOCKED | always (never auto-exit on error!) |
| LOCKED | IDLE | only `!rx_enable \|\| rx_reset_pulse` (line 715) |

**`match_any`** = `match_fixed \|\| match_toggle_pos \|\| match_toggle_neg \|\| match_counter` (line 391). Each `match_*` is gated by `is_*_mode`, so only the active mode contributes. Important: SEARCH locks on first match against ANY of the 4 expected patterns regardless of the current `test_mode` — actually wait, no: `match_fixed = is_fixed_mode && is_match_by_channel(...)`. So `match_fixed` is only true in FIXED mode. Same for others. So SEARCH locks ONLY against the configured pattern.

**`is_match_by_channel(act, exp, mask)`** (line 334): returns 1 if every channel-bit set in `mask` matches the corresponding 16-bit slice; channels with mask bit = 0 are skipped (no constraint).

⚠ Edge case: if `rx_ch_mask == 4'h0`, then `is_match_by_channel` returns 1 trivially (vacuously match), and SEARCH locks immediately on first non-K cycle. `LNK_RX_WRD_CNT` will increment but `LNK_RX_ERR_CNT` stays 0 because per-channel mismatch checks are also gated by mask. Use `ch_mask=0` ONLY for "checker disabled but FSM running" testing.

### §3.3 Sticky alignment latch (`rx_aligned_seen`)

Per-channel 4-bit sticky register (lines 416-423):
```systemverilog
if (!core_rst_n)         rx_aligned_seen <= 4'b0;
else if (rx_reset_pulse) rx_aligned_seen <= 4'b0;
else if (capture_cfg)    rx_aligned_seen <= 4'b0;
else                     rx_aligned_seen <= rx_aligned_seen | rxbyteisaligned;
```

**Why sticky:** GT's `rxbyteisaligned` can transiently de-assert after alignment is achieved (rare but documented). Without stickiness, the FSM would bounce WAIT_ALIGN ↔ SEARCH. With stickiness, once a channel has shown aligned once during this test run, it counts as aligned forever.

The WAIT_ALIGN gating condition:
```systemverilog
wire all_masked_aligned = (((rx_aligned_seen | rxbyteisaligned) & rx_ch_mask) == rx_ch_mask);
```
Both live and sticky views are OR'd, then mask is applied. The result is registered (1 cycle delay) before being used by FSM:
```systemverilog
if (rx_ch_mask == 4'h0) aligned_or_nomask_r <= 1'b1;
else                    aligned_or_nomask_r <= all_masked_aligned;
```

⚠ If `rx_ch_mask == 4'h0`, WAIT_ALIGN is bypassed (always "aligned").

**Reset paths for `rx_aligned_seen`:** core reset, AXI `rx_reset_pulse` (LNK_TEST_CTRL[1] W1P), and `capture_cfg` (test start). Outside these, the bits are sticky for the whole test run.

**Diagnostic:** `LNK_DIAG_STATUS[7:4]` = live `rxbyteisaligned`, `[11:8]` = sticky `rx_aligned_seen`. If `[7:4]=0xF` but `[11:8]=0xF` and FSM still in WAIT_ALIGN — that's impossible by construction. If `[7:4]=0xF` and `[11:8]=0x0` it means test just started and capture_cfg cleared the latch but `rxbyteisaligned` wasn't sampled yet (1 cycle).

### §3.4 LOCKED state — error counting and COUNTER resync

In LOCKED (lines 713-746):
- if `any_ksymbol_r` (current word is a K-symbol — comma maintenance), SKIP: don't count, don't check, don't advance expected
- otherwise:
  - `wrd_cnt_inc = 1` (increments global `LNK_RX_WRD_CNT`)
  - if `!match_expected`: `err_cnt_inc = 1` (increments global `LNK_RX_ERR_CNT`)

**Expected pattern advancement:**
- FIXED mode: `next_expected_rx = rx_fixed_64` (never changes)
- TOGGLE mode: `next_expected_rx = ~expected_rx` (flip every non-K cycle)
- COUNTER mode:
  - on K-symbol: hold expected unchanged
  - on error: **resync** — `next_expected_rx = rx_data_corrected + 1` per channel slice (lines 731-735). This is the "auto-resync" feature. A single bit-flip counts ONE error then the checker re-tracks the received counter.
  - on match: `next_expected_rx = expected_rx + 1` per channel slice

⚠ This is why COUNTER mode shows low error counts even with bad channels — a single error doesn't cascade into thousands of phantom errors. But it also means the error count is "events" not "wrong bits".

### §3.5 K-symbol skip rules

`any_ksymbol_r = |(rxcharisk & rx_ch_mask)` registered (line 644-646). If ANY channel in mask shows a K-symbol this cycle, the whole 64-bit word is treated as K (skipped).

Why: K-symbols are unidirectional commas (only sent by MASTER's TX_ST_MAINTENANCE) but get cascaded through SLAVE's TXCHARISK echo. So they appear roughly every COMMA_PERIOD=1024 cycles in the MASTER's RX. Skipping prevents false errors.

---

## §4 LOOPBACK semantics (`LNK_LOOPBACK` reg 0x004)

3-bit value from AXI, fanned out to all 4 GT channels: `loopback_in = {4{loopback_ctrl}}` (line 628 in `serdes_array.sv`).

From PG182 / UltraScale GTH UG576, standard GT loopback values:

| Value | Mode | Path | Use |
|---|---|---|---|
| 0b000 | Normal | TX driver → fiber → RX | Production / real optical link |
| 0b001 | Near-end PCS Loopback | TX 8B10B encoder output → RX 8B10B decoder input (digital, no PMA) | Fastest digital BIST; no CDR involved; tests fabric + 8B10B |
| 0b010 | Near-end PMA Loopback | serializer output → deserializer input (analog SerDes, CDR runs on own signal) | Tests serializer/deserializer + CDR |
| 0b100 | Far-end PMA Loopback | incoming RX serial → TX driver (no PCS path) | For partner-side echo testing |
| 0b110 | Far-end PCS Loopback | RX 8B10B decoder output → TX 8B10B encoder input | For partner-side echo with PCS |

Cross-reference with the bootstrap document's NEAR-END PCS BIST (the test that showed 71 phantom errors / 63.6M words):
- `LOOPBACK = 0x1` in MASTER, no fiber attached → MASTER's TX data digitally loops back to its own RX, checker can compare against pattern generator.
- 71 errors over 63.6M words = ~1e-6 — most likely transient during reset stabilization. Root cause deferred per Phase 1 plan; bypass this step in firmware.

⚠ **"Cascade loopback" (§1, §2.3) is NOT a GT LOOPBACK.** It's the SLAVE's RTL `tx_data <= rx_data_r`. The GT loopback bus stays at 0 (normal) for the SLAVE in cascade mode; the SLAVE's TX driver actively transmits data on the fiber. Conflating these two is a common source of confusion.

---

## §5 AXI Register Map (complete)

`C_S00_AXI_NUM_REGS = 49`, 32-bit words, byte offsets shown. All reads return 32-bit values. Writes use byte strobes (WSTRB) — partial writes work for RW registers.

### §5.1 Full register table

| Offset | Word idx | Name | Type | Description |
|---|---|---|---|---|
| 0x000 | 0 | SERDES_CTRL | W1P | bit 0 = link_down_latched_reset; bit 1 = gt_reset_all. CDC pulse to core_clk (3-stage). Reads as 0. |
| 0x004 | 1 | SERDES_LOOPBACK | RW | `[2:0]` = GT loopback bus, fanned to all 4 channels. 2FF sync to core_clk. Other bits reserved. |
| 0x008 | 2 | SERDES_STATUS | RO | CDC-clean. See §5.2. |
| 0x00C | 3 | SERDES_DBG_LO | RO | `dbg_in[31:0]` sampled into axi_clk. Debug-only, **non-coherent** with DBG_HI. |
| 0x010 | 4 | SERDES_DBG_HI | RO | `dbg_in[63:32]` sampled. See §6 for bit map. |
| 0x014 | 5 | SERDES_TEST_CONST | RO | Fixed `0x4D55524F` = ASCII "MURO". AXI sanity check. |
| 0x018 | 6 | SERDES_TEST_SCRATCH | RW | Read-write storage. AXI sanity check (write X, read X). |
| 0x01C | 7 | LNK_TEST_CTRL | RW | bit 0 = enable (level → 2FF sync to core_clk); bit 1 = reset_counters W1P (3-stage CDC pulse). |
| 0x020 | 8 | LNK_TEST_CNFG | RW | `[15:0]` decoded per §5.3. 2FF sync to core_clk. |
| 0x024 | 9 | LNK_TEST_PATT | RW | 32-bit fixed pattern. Used in FIXED mode and SEARCH match. |
| 0x028 | A | LNK_RX_ERR_CNT | RO | 32-bit global error count, 2FF CDC rx_clk→axi_clk. |
| 0x02C | B | LNK_RX_WRD_CNT | RO | 32-bit global word count (excludes K-symbol cycles). |
| 0x030 | C | LNK_DIAG_STATUS | RO | FSM + alignment state. See §5.4. |
| 0x034 | D | LNK_DIAG_RX_LO | RO | `rx_data_corrected[31:0]` sampled. Non-coherent. |
| 0x038 | E | LNK_DIAG_RX_HI | RO | `rx_data_corrected[63:32]` sampled. |
| 0x03C | F | LNK_DIAG_EXP_LO | RO | `expected_rx[31:0]` sampled. |
| 0x040 | 10 | LNK_DIAG_EXP_HI | RO | `expected_rx[63:32]` sampled. |
| 0x044 | 11 | LNK_DIAG_TX_DATA_LO | RO | `tx_data[31:0]` snapshot, axi_clk single-reg sample. |
| 0x048 | 12 | LNK_DIAG_TX_DATA_HI | RO | `tx_data[63:32]` snapshot. |
| 0x04C | 13 | LNK_DIAG_TX_COUNTERS_LO | RO | `{ch1_counter[15:0], ch0_counter[15:0]}`. |
| 0x050 | 14 | LNK_DIAG_TX_COUNTERS_HI | RO | `{ch3_counter[15:0], ch2_counter[15:0]}`. |
| 0x054 | 15 | LNK_DIAG_TX_STATUS | RO | `[0]=tx_comma_active`, `[12:1]=comma_cnt`. |
| 0x058 | 16 | GT_DEBUG_COMMA_ALIGN | RO | `[3:0]=rxcommadet, [7:4]=rxbyteisaligned, [11:8]=rxbyterealign`. |
| 0x05C | 17 | GT_DEBUG_RXBUF_STATUS | RO | `[11:0]` = 3-bit-per-channel rxbufstatus (4 chs). |
| 0x060 | 18 | GT_DEBUG_TXBUF_STATUS | RO | `[7:0]` = 2-bit-per-channel txbufstatus. |
| 0x064 | 19 | GT_DEBUG_SYNC_STATUS | RO | `[3:0]=rxsyncdone, [7:4]=rxphaligndone`. |
| 0x068 | 1A | GT_DEBUG_SIGNAL_QUAL | RO | `[3:0]=eyescandataerror`. |
| 0x06C | 1B | GT_DEBUG_RESET_STATUS | RO | `[3:0]=rxresetdone, [7:4]=txresetdone, [11:8]=rxpmaresetdone, [15:12]=txpmaresetdone`. |
| 0x070 | 1C | LNK_DIAG_STATUS2 | RO | sticky FSM diag. See §5.4. |
| 0x074 | 1D | IP_INFO | RO | Build identity. See §5.5. |
| 0x078 | 1E | reserved | — | reads as 0 |
| 0x07C | 1F | reserved | — | reads as 0 |
| 0x080 | 20 | LNK_TIME_TO_LOCK | RO | 32-bit cycles WAIT_ALIGN entry → first LOCKED. Frozen after first lock. |
| 0x084 | 21 | LNK_LOCKED_CYCLE_CNT | RO | 32-bit running counter of cycles spent in LOCKED. |
| 0x088 | 22 | LNK_RX_DATA_AT_LOCK_LO | RO | `rx_data_at_lock[31:0]` — frozen snapshot. |
| 0x08C | 23 | LNK_RX_DATA_AT_LOCK_HI | RO | `rx_data_at_lock[63:32]`. |
| 0x090 | 24 | LNK_RX_DATA_AT_FIRST_ERR_LO | RO | `rx_data_at_first_err[31:0]` — frozen snapshot. |
| 0x094 | 25 | LNK_RX_DATA_AT_FIRST_ERR_HI | RO | `rx_data_at_first_err[63:32]`. |
| 0x098 | 26 | LNK_ERR_CNT_CH0 | RO | `[15:0]` per-channel error count, CH0. |
| 0x09C | 27 | LNK_ERR_CNT_CH1 | RO | per-channel CH1. |
| 0x0A0 | 28 | LNK_ERR_CNT_CH2 | RO | per-channel CH2. |
| 0x0A4 | 29 | LNK_ERR_CNT_CH3 | RO | per-channel CH3. |
| 0x0A8 | 2A | GT_RXBYTEREALIGN_CNT_LO | RO | `[15:0]=CH0 cnt, [31:16]=CH1 cnt`. GT-sticky. |
| 0x0AC | 2B | GT_RXBYTEREALIGN_CNT_HI | RO | `[15:0]=CH2 cnt, [31:16]=CH3 cnt`. |
| 0x0B0 | 2C | GT_EYESCANDATAERROR_CNT_LO | RO | `[15:0]=CH0 cnt, [31:16]=CH1 cnt`. |
| 0x0B4 | 2D | GT_EYESCANDATAERROR_CNT_HI | RO | `[15:0]=CH2 cnt, [31:16]=CH3 cnt`. |
| 0x0B8 | 2E | LNK_EXP_DATA_AT_FIRST_ERR_LO | RO | `exp_data_at_first_err[31:0]` — paired with FIRST_ERR. |
| 0x0BC | 2F | LNK_EXP_DATA_AT_FIRST_ERR_HI | RO | `exp_data_at_first_err[63:32]`. |

⚠ `C_S00_AXI_NUM_REGS = 49`, so word indices 0..48 are valid. Index 29 = IP_INFO at offset 0x074. Indices 30 and 31 (offsets 0x078, 0x07C) are reserved (return 0).

### §5.2 SERDES_STATUS (0x008) decode

CDC-clean composite of all per-channel transceiver healthiness signals:

| Bits | Meaning |
|---|---|
| `[0]` | `link_up` — composite (`AND` of gtpowergood + tx/rxpmaresetdone + gtwiz_reset_{tx,rx}_done + userclk_{tx,rx}_active across all 4 channels) |
| `[1]` | `link_down_latched` — sticky version of NOT(link_up), cleared via CTRL bit 0 W1P |
| `[15:2]` | reserved (read 0) |
| `[19:16]` | `pll_lock[3:0]` — per-channel QPLL0 lock indicator |
| `[23:20]` | `gtpowergood[3:0]` — per-channel GT power good |
| `[27:24]` | `txpmaresetdone[3:0]` — per-channel TX PMA reset complete |
| `[31:28]` | `rxpmaresetdone[3:0]` — per-channel RX PMA reset complete |

**Reference: STATUS = 0xFFFF0001** (the "perfect bring-up" value):
- bit 0 = 1 (link_up)
- bit 1 = 0 (latch cleared)
- pll_lock = 0xF, gtpowergood = 0xF, txpmaresetdone = 0xF, rxpmaresetdone = 0xF

Firmware bring-up should poll until STATUS = 0xFFFF0001 (or at minimum bit 0 = 1) before enabling the link test.

### §5.3 LNK_TEST_CNFG (0x020) decode

| Bits | Meaning |
|---|---|
| `[1:0]` | `test_mode`: 00=FIXED, 01=TOGGLE, 10=COUNTER, 11=reserved |
| `[3:2]` | reserved |
| `[7:4]` | `rx_ch_mask` — which channels participate in alignment-wait and matching |
| `[11:8]` | `rx_pol_mask` — per-channel RX invert (compensate inverted polarity) |
| `[15:12]` | `tx_pol_mask` — per-channel TX invert (compensate inverted polarity) |

Common values:
- `0x00F0` = FIXED mode, all 4 channels masked, no polarity inversion → standard 4-channel BIST
- `0x0020` = FIXED mode, only CH1 masked (`ch_mask=0x2`), no polarity → single-channel BER on CH1 (matches current optical bench config)
- `0x0021` = TOGGLE mode, CH0 masked
- `0x00F2` = COUNTER mode, all 4 channels masked

### §5.4 LNK_DIAG_STATUS / STATUS2 decode

**LNK_DIAG_STATUS (0x030):**

| Bits | Field |
|---|---|
| `[3:0]` | `rx_checker_curr_state` (0=IDLE, 1=CAPTURE_CFG, 2=WAIT_ALIGN, 3=SEARCH, 4=LOCKED) |
| `[7:4]` | live `rxbyteisaligned[3:0]` |
| `[11:8]` | sticky `rx_aligned_seen[3:0]` (latched OR) |
| `[15:12]` | live `rxcharisk[3:0]` |
| `[16]` | `checker_locked` (1 when FSM in LOCKED state) |
| `[31:17]` | reserved (read 0) |

**LNK_DIAG_STATUS2 (0x070):**

| Bits | Field |
|---|---|
| `[0]` | `ever_locked` — sticky 1 if FSM was ever in LOCKED during this test run |
| `[3:1]` | reserved |
| `[7:4]` | `last_fsm_state` — last non-IDLE state before `rx_enable=0` |
| `[15:8]` | reserved |
| `[16]` | `rx_data_at_lock_valid` — 1 if at_lock snapshot was taken |
| `[17]` | `first_err_valid` — 1 if first_err snapshot was taken |
| `[31:18]` | reserved |

⚠ `last_fsm_state` is critical for post-mortem: if test ran 10 seconds and after stopping you see `last_fsm_state = 2 (WAIT_ALIGN)` and `ever_locked = 0`, you know alignment was never achieved (probably optical issue or wrong channel). If `last_fsm_state = 3 (SEARCH)` and `ever_locked = 0`, alignment OK but pattern never matched (probably wrong `test_mode` or `fixed_patt` mismatch between MASTER and… wait, MASTER pattern is also the SEARCH target, so that's a config issue).

### §5.5 IP_INFO (0x074) decode

Build identity. Build-time constants, no CDC needed:

| Bits | Field | Width |
|---|---|---|
| `[0]` | `IS_SLAVE` | 1 |
| `[1]` | `IS_MASTER` | 1 |
| `[3:2]` | reserved | 2 |
| `[7:4]` | `IP_VERSION_MAJOR` | 4 (max 15) |
| `[23:8]` | `IP_VERSION_MINOR` | 16 (max 65535) |
| `[27:24]` | `NUM_CHANNELS` | 4 (max 15) |
| `[31:28]` | reserved | 4 |

**Examples:**
- `0x04000111` = SLAVE, ver 1.1, 4 channels
- `0x04000112` = MASTER, ver 1.1, 4 channels
- Auto-bumped by `update_ip_ports.tcl` (Workflow A): minor field increments on every IP re-package

### §5.6 W1P (write-1-to-pulse) semantics

For CTRL (0x000) and LNK_TEST_CTRL[1]:
- Firmware writes 1 to a bit
- The 1 propagates to `slv_reg[*]` (held there indefinitely until firmware writes 0)
- `murosync_cdc_slow_to_fast` (SYNC_STAGES=3) converts the rising edge into a 1-cycle pulse in core_clk domain
- After firmware sees the action took effect, it should write 0 back to allow another pulse

⚠ **CTRL bit is NOT auto-cleared.** The driver must do `WR ctrl 0x01; ... WR ctrl 0x00`. If you leave it at 1, the next write of 1 won't produce a new pulse (no rising edge).

⚠ AXI write address out of range (offset > 0xBC for current `C_S00_AXI_NUM_REGS=49`): behavior depends on internal `murosync_serdes_array_S00_AXI` decoder — not visible in this RTL extract. Conservative assumption: writes ignored, reads return 0.

**WSTRB:** standard AXI4-Lite — partial-word writes work for RW registers. Driver typically writes full 32-bit words anyway.

---

## §6 DBG bus bit map (`dbg[63:0]`)

Drives the ILA `probe3[63:0]` (in BD), and is also AXI-sampled into `SERDES_DBG_LO/HI` (0x00C/0x010). Sourced from `core_clk` (100 MHz freerun) domain.

| Bit(s) | Signal | Notes |
|---|---|---|
| `[0]` | `hb_gtwiz_reset_all_int` | synchronized reset_all |
| `[1]` | `link_up_raw` | composite link up (see §5.2 for components) |
| `[2]` | `link_down_latched_out` | sticky version, same as STATUS[1] |
| `[3]` | `link_latch_reset_comb` | latched reset combinational (`link_down_latched_reset_in \| link_latch_reset_axi`) |
| `[7:4]` | `gtpowergood_int[3:0]` | per-channel |
| `[11:8]` | `txpmaresetdone_int[3:0]` | per-channel |
| `[15:12]` | `rxpmaresetdone_int[3:0]` | per-channel |
| `[16]` | `gtwiz_reset_tx_done_int` | composite TX reset done across all channels |
| `[17]` | `gtwiz_reset_rx_done_int` | composite RX reset done |
| `[18]` | `gtwiz_reset_rx_cdr_stable_int` | CDR stable (per Lesson #2 — NOT lock; not safe to gate on) |
| `[19]` | `gtwiz_userclk_tx_active_int` | TX user clock buffers out of reset |
| `[20]` | `gtwiz_userclk_rx_active_int` | RX user clock buffers out of reset |
| `[24:21]` | unused (0) | |
| `[25]` | `refclk_out` | refclk after BUFG_GT divide-by-2 (78.125 MHz), fabric-visible |
| `[29:26]` | `pll_lock_out[3:0]` | per-channel QPLL0 lock |
| `[63:30]` | '0 | |

**Use in firmware bring-up:** read DBG_LO first to confirm `(reset_tx_done && reset_rx_done && userclk_tx_active && userclk_rx_active) == 1`. If any of these is 0, bring-up is incomplete.

---

## §7 Tier 2 diagnostic snapshots — semantics

All counters and snapshots live in rx_clk domain, CDC'd via `murosync_cdc_level_sync` (2-stage). Cleared on `core_rst_n=0`, `rx_reset_pulse` (CTRL[1] W1P), or `capture_cfg` (FSM CAPTURE_CFG transition — i.e. start of each new test).

### §7.1 `time_to_lock` (0x080)

32-bit counter, units = rx_clk cycles (3.2 ns at 312.5 MHz). Counts from first entry into WAIT_ALIGN to first entry into LOCKED. Frozen after first LOCKED — reads stable value thereafter.

Range: 32 bits = ~13.7 seconds at 312.5 MHz. Plenty for any reasonable optical link.

Use: "how long did alignment+search take?" — single number for bring-up profiling.

### §7.2 `locked_cycle_cnt` (0x084)

32-bit running counter of cycles spent in LOCKED. Includes K-symbol cycles (FSM is still LOCKED, just no data progress). Use ratio `locked_cycle_cnt / wrd_cnt` to estimate K-symbol overhead (~1/1024 in steady state).

### §7.3 `rx_data_at_lock_*` (0x088/0x08C)

64-bit frozen snapshot. Latched once at first cycle `curr_state == LOCKED`. Valid bit = `LNK_DIAG_STATUS2[16]`.

Use: confirm SEARCH locked on the EXPECTED pattern (compare with `LNK_TEST_PATT` for FIXED mode). If `rx_data_at_lock` shows garbage like 0xDEADBEEF instead of the configured pattern → FSM locked on noise. Should never happen, but useful for confidence.

### §7.4 `rx_data_at_first_err_*` (0x090/0x094) + `exp_data_at_first_err_*` (0x0B8/0x0BC)

Paired 64-bit snapshots: at the first error event in LOCKED, latch BOTH `rx_data_corrected` and `expected_rx`. Valid bit = `LNK_DIAG_STATUS2[17]`.

Use:
- single bit-flip → `rx_data_at_first_err ^ exp_data_at_first_err` has Hamming weight 1
- full decorrelation → XOR has random pattern
- per-channel slicing: bits `[15:0]` = CH0, `[31:16]` = CH1, etc. — tells you WHICH channel had the first error

### §7.5 Per-channel error counters (0x098 / 0x09C / 0x0A0 / 0x0A4)

16-bit each. Saturate at 0xFFFF (no wrap protection per RTL — they just stop incrementing? Let me re-check… actually line 619: `err_cnt_ch[gi_ch] <= err_cnt_ch[gi_ch] + 1` — no saturation guard, so they DO wrap at 0x10000. Use with care for long tests; the global `LNK_RX_ERR_CNT` is 32-bit and safer for accumulated metric.

⚠ **Per-channel vs global semantics differ:** if N channels error in same cycle, global err_cnt increments by 1; per-channel each increments separately. So `sum(err_cnt_ch[0..3]) >= LNK_RX_ERR_CNT`, with equality only when each error event involves exactly 1 channel.

### §7.6 GT sticky event counters (0x0A8..0x0B4)

`rxbyterealign_cnt` — how many times each channel had to re-align (post-initial alignment). Healthy link should show 0; a value > 0 indicates GT has lost and regained byte alignment, which is a serious data integrity signal.

`eyescandataerror_cnt` — eyescan-detected data errors per channel. Mostly informational.

Both come from `murosync_gt_wrapper`'s `gt_debug_*_cnt_out` ports; sampled directly into axi_clk single-reg (non-coherent across HI/LO words).

---

## §8 CDC architecture summary

The IP has **four clock domains** internally:
1. **axi_clk** = `microblaze_0_Clk` = 100 MHz (clk_wiz_0 output from 200 MHz diff)
2. **core_clk** (freerun) = same 100 MHz, drives reset controller + dbg bus generation
3. **tx_clk** (`gt_userclk_tx_usrclk2_int`) = 312.5 MHz (refclk × 40 / 20)
4. **rx_clk** (`gt_userclk_rx_usrclk2_int`) = 312.5 MHz (recovered, asynchronous to tx_clk)

**CDC primitives used:**
- `murosync_cdc_slow_to_fast` (SYNC_STAGES=3): edge-to-pulse for AXI W1P → core_clk pulses (CTRL, LNK_TEST_CTRL[1] reset)
- `murosync_cdc_level_sync` (SYNC_STAGES=2): level signals for `link_test_en` (axi→core, axi→tx, axi→rx), `cnfg`, diagnostic outputs (rx→axi, tx→axi)
- Direct `ASYNC_REG` 2FF: STATUS bits, loopback ctrl, GT debug status
- Raw single-cycle latch: `dbg_in` into `dbg_axi_r` (debug-only, NOT coherent)

⚠ **Multi-bit buses (`rx_data`, `expected_rx`, `tx_data`)** are sampled with a single axi_clk register — bits are NOT coherent across the 64-bit word when the source is changing rapidly. Comment in RTL: "debug-only, no coherence guarantee". For coherent snapshots, use Tier 2 frozen snapshots (`rx_data_at_lock`, `rx_data_at_first_err`).

---

## §9 Compile-time constants

In `murosync_serdes_link_test.sv`:
```systemverilog
localparam logic [7:0] K28_5        = 8'hBC;
localparam integer     TRAIN_LEN    = 4096;  // ~13 µs at 312.5 MHz
localparam integer     COMMA_PERIOD = 1024;  // ~3.3 µs
```

In `murosync_serdes_array.sv`:
```systemverilog
parameter integer IP_VERSION_MAJOR    = 1;
parameter integer IP_VERSION_MINOR    = 1;  // auto-bumped by update_ip_ports.tcl
parameter integer C_S00_AXI_DATA_WIDTH = 32;
parameter integer C_S00_AXI_NUM_REGS   = 49;
```

In `murosync_gt_wrapper`:
```systemverilog
parameter int NCH              = 4;
parameter int TX_MASTER_CH     = 0;  // CH0 sources TXOUTCLK
parameter int RX_MASTER_CH     = 0;  // CH0 sources recovered clock (slave_recclk_out)
```

⚠ `TX_MASTER_CH=0` and `RX_MASTER_CH=0` are hardcoded at instantiation in `murosync_serdes_array.sv` — the recovered clock path is fixed to wizard[0]. In SLAVE mode wizard[0] = `muro_gth_slave` = SFP1 cage. In MASTER mode wizard[0] = `muro_gth_master_0` = SFP1 cage. For the current optical bench where SFP2 is the populated cage (RXBYTEISALIGNED=0x2), wizard[1] data goes into rx_data[31:16]. The recovered clock output (`slave_recclk_out`) however still comes from wizard[0], which has no signal — but that's OK because `slave_recclk_out` is only used in SLAVE mode for downstream clock distribution, not for the BER test.

---

## §10 Phase 1 troubleshooting guide using new info

Given current bench state:
- SLAVE: STATUS=0xFFFF0001 ✓
- MASTER: STATUS=0xFFFF0001 ✓ but NEAR-END PCS BIST gives 71 errors over 63.6M words

**Goal:** 60+ sec optical BER on CH1, zero errors → Phase 1 closure.

**Step-by-step using newly-extracted info:**

1. **Verify optical link is alive (alignment).** Read 0x030 (LNK_DIAG_STATUS):
   - Expected: `[7:4]=0x2` (live rxbyteisaligned on CH1), `[11:8]=0x2` (sticky too), `[3:0]=0` (IDLE — link test not running yet)
   - If `[7:4] != 0x2`: optical link not aligned. Check fiber connection, SFP+ pair seating, refclk_out toggling at 78.125 MHz (DBG_LO[25]).

2. **Configure for single-channel CH1 test.** Write:
   - 0x024 LNK_TEST_PATT = 0x55AA55AA (or any 32-bit value)
   - 0x020 LNK_TEST_CNFG = 0x0020 (FIXED mode, ch_mask=0x2, no polarity)

3. **Bypass NEAR-END PCS BIST** in MASTER bring-up flow (was producing 71 phantom errors). Then proceed directly to:

4. **Start test.** Write:
   - 0x01C LNK_TEST_CTRL = 0x01 (enable)

5. **Verify SEARCH→LOCKED happens.** Poll 0x030:
   - Within ~13 µs (TRAIN_LEN) + ~few µs SEARCH: `[3:0]` should be `4 (LOCKED)`, `[16]=1`.
   - Read 0x070 LNK_DIAG_STATUS2: `[0]=1` (ever_locked).
   - Read 0x080 LNK_TIME_TO_LOCK: should be small (~5000 cycles = ~16 µs).
   - Read 0x088/0x08C LNK_RX_DATA_AT_LOCK_LO/HI: should be `0x55AA55AA_55AA55AA` (for the pattern above) on bits [31:16] (CH1 slice).

6. **Run for 60 seconds.** Periodically poll:
   - 0x02C LNK_RX_WRD_CNT — should grow linearly (~312 Mwords/sec)
   - 0x028 LNK_RX_ERR_CNT — must stay 0
   - 0x09C LNK_ERR_CNT_CH1 — must stay 0
   - 0x070 LNK_DIAG_STATUS2[17] = first_err_valid — must stay 0

7. **Pass condition:** after 60+ sec, `err_cnt=0`, `wrd_cnt > 1.8e10`, `ever_locked=1`, `first_err_valid=0`.

8. **If errors appear:** read snapshots 0x090/0x094 (rx_at_first_err) and 0x0B8/0x0BC (exp_at_first_err). XOR to identify failure mode (single-bit, channel-wide, decorrelation).

**Stop test:** Write 0x01C = 0x00 (disable). FSM goes to IDLE. Read 0x070[7:4] to confirm `last_fsm_state = 4 (LOCKED)` — post-mortem witness that link was locked at stop time.

---

## §11 Remaining unresolved gaps (require user input — not in RTL)

These can't be answered from the IP sources. Need user notebook or empirical observation:

1. **Successful firmware UART banner template** — what does `main.c` actually print? Banner format, per-step progress lines, error messages. Provide example for v1.2 of `MuroSync_Dev_Bench_Architecture` once observed.

2. **Source file paths** — where do `murosync_serdes_driver.c/.h`, `main.c`, `murosync_serdes_regs.h`, `xparameters.h` live in the repo tree?

3. **Vitis firmware build flow** — step-by-step: workspace location, platform import from `.xsa`, application project creation (sysroot? OS=standalone? domain?), Debug vs Release config, output `.elf` location.

4. **Flashing/programming sequence** — JTAG-only via Hardware Manager → Program Device + Vitis Launch on Hardware? Or QSPI persistent flash? DIP switches on ACAU15 for boot mode? What does DONE LED do at successful config?

5. **Waveshare module details** — model number (USR-TCP232-?), default IP, TCP port, web UI URL, power source.

6. **Power-on dependency timing** — observed time from 12V plug to first UART output. Order of events: FPGA config → QSPI boot → clock stable → MicroBlaze running → firmware banner.

7. **XDC file contents** — beyond `PACKAGE_PIN T7/T6` for refclk: what `create_clock`, `set_clock_groups -asynchronous`, `set_false_path` constraints exist? (Not provided in uploads.)

8. **`murosync_app_bringup_master` driver-level details** — what's in `firmware/main.c` or `app/` for the auto bring-up sequence?

When these are addressed, v1.2 of Dev Bench Architecture can include them; alternatively a separate `MuroSync_Firmware_Build_Guide.md` companion doc.

---

## Source-file cross-reference

| Topic | File | Lines |
|---|---|---|
| MODE param + IS_SLAVE/IS_MASTER | murosync_serdes_array.sv | 36-40, 154-158 |
| RX/TX pin muxing | murosync_serdes_array.sv | 183-203 |
| dbg bus assembly | murosync_serdes_array.sv | 351-370 |
| link_up_raw composition | murosync_serdes_array.sv | 322-330 |
| GT wrapper instantiation (refclk, 8B10B, loopback) | murosync_serdes_array.sv | 570-646 |
| Link test enable CDC | murosync_serdes_array.sv | 654-686 |
| TX Comma FSM | murosync_serdes_link_test.sv | 192-257 |
| TX Pattern Generator | murosync_serdes_link_test.sv | 188-329 |
| TX K28.5 + TXCHARISK echo (SLAVE) | murosync_serdes_link_test.sv | 287-305 |
| RX polarity correction | murosync_serdes_link_test.sv | 360-370 |
| Match logic + FSM | murosync_serdes_link_test.sv | 334-757 |
| Sticky rx_aligned_seen | murosync_serdes_link_test.sv | 416-423 |
| Tier 2: time_to_lock | murosync_serdes_link_test.sv | 452-500 |
| Tier 2: rx_data_at_lock | murosync_serdes_link_test.sv | 516-547 |
| Tier 2: rx_data_at_first_err + exp_data_at_first_err | murosync_serdes_link_test.sv | 549-584 |
| Per-channel err_cnt_ch | murosync_serdes_link_test.sv | 586-622 |
| AXI register map (localparam) | murosync_serdes_array_axi_ctrl.sv | 174-242 |
| STATUS register assembly | murosync_serdes_array_axi_ctrl.sv | 434-440 |
| LNK_DIAG_STATUS assembly | murosync_serdes_array_axi_ctrl.sv | 600-608 |
| LNK_DIAG_STATUS2 assembly | murosync_serdes_array_axi_ctrl.sv | 658-675 |
| GT debug regs assembly | murosync_serdes_array_axi_ctrl.sv | 685-708 |
| Tier 2 register assignments | murosync_serdes_array_axi_ctrl.sv | 717-806 |
| IP_INFO register | murosync_serdes_array_axi_ctrl.sv | 808-830 |
| W1P CDC | murosync_serdes_array_axi_ctrl.sv | 307-322, 461-468 |

---

*Generated 2026-05-26 from RTL extraction session. v1.0 — initial release.*
