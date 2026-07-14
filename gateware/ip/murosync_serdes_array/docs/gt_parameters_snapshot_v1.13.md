# GT Wizard Parameter Snapshot — `gtwizard_ultrascale_0`

**Extracted:** 2026-05-29 01:49
**Re-captured:** 2026-06-13 (post WORD 2→1 revert) — values confirmed **identical** to the 2026-05-29 baseline below. Wrapper IP was labeled `murosync_serdes_array:1.13` at re-capture, but that bitstream's RTL logic equals v1.10 (the comma-align-gating latch was not present in the synthesized design). The GT Wizard CONFIG is unchanged: `RX_COMMA_ALIGN_WORD=1`, `RX_COMMA_DOUBLE_ENABLE=false`, `RX_COMMA_SHOW_REALIGN_ENABLE=true`, `RX_PPM_OFFSET=200`, `RX_COUPLING=AC`, `RX_TERMINATION=AVTT`, 6.25 Gb/s, QPLL0. CORE_REVISION advanced to 14 (WORD 2↔1 regen churn) but functional state is the baseline.
**Re-verified (r2):** 2026-07-14 — **two-level verification.** Level 1: full `CONFIG.*` dump against live IP object — **identical to baseline, zero diffs** (third consecutive confirmation: 05-29, 06-13, 07-14). Level 2 (**new**): GTHE4_CHANNEL primitive attributes read from the synthesized netlist (`open_run synth_1`) — see §"Primitive attributes" below. **Verdict: buffered RX and TX, clock correction disabled at silicon level.** This corrects the "buffer-bypass" wording in the RTL Architecture H2 lesson (the empirical lesson itself — never freeze `RXPCOMMAALIGNEN` — stands unchanged; only the configuration characterisation in its text was wrong).
**Method:** Vivado TCL `get_property CONFIG.*` against live main project IP; r2 adds `get_property` on GTHE4_CHANNEL cells in the synthesized netlist
**Source project:** murosync_poc_v1 at C:/_vivado/murosync_poc_v1
**IP_DIR (build chain):**
  `c:/_vivado/murosync_poc_v1/murosync_poc_v1.gen/sources_1/bd/bd_murosync_poc/ip/bd_murosync_poc_murosync_serdes_array_0_1/prj/gtwizard_ultrascale_0_ex.srcs/sources_1/ip/gtwizard_ultrascale_0`
**Authority:** This is the IP that synthesis uses to build the bitstream.
Output products from this IP propagate directly into MASTER and SLAVE .bit files.
This document is the canonical **GT configuration baseline** (Phase1 GT Research §9, update-plan item 3).

## IP State

| Property | Value |
|---|---|
| NAME | gtwizard_ultrascale_0 |
| IPDEF | xilinx.com:ip:gtwizard_ultrascale:1.7 |
| IS_LOCKED | 0 |
| USER_LOCKED | 0 |
| STALE_TARGETS | '' (empty = up-to-date) |
| CORE_REVISION | 14 |
| SW_VERSION | 2022.2 |
| PART | xcau15p-ffvb676-2-i |

## Primitive attributes (synthesized netlist, r2 — 2026-07-14)

Read from GTHE4_CHANNEL cells in `synth_1`; **all four channels (X0Y4–X0Y7) identical**:

| Attribute | Value | Meaning |
|---|---|---|
| `RXBUF_EN` | `TRUE` | RX elastic buffer **in the datapath** (not bypass) |
| `RX_XCLK_SEL` | `RXDES` | RX read side clocked through the buffer (buffered mode) |
| `CLK_CORRECT_USE` | `FALSE` | GT clock correction **disabled** — buffer never inserts/removes symbols |
| `CLK_COR_SEQ_LEN` | `1` | inactive (CC disabled) |
| `CLK_COR_KEEP_IDLE` | `FALSE` | inactive |
| `CLK_COR_MIN_LAT` / `MAX_LAT` | `4` / `6` | defaults, inactive |
| `CBCC_DATA_SOURCE_SEL` | `DECODED` | default, CB/CC both disabled |
| `TXBUF_EN` | `TRUE` | TX buffer in the datapath |
| `TX_XCLK_SEL` | `TXOUT` | buffered TX clocking |
| `ALIGN_MCOMMA_DET` / `ALIGN_PCOMMA_DET` | `TRUE` | comma detection active both polarities |
| `SHOW_REALIGN_COMMA` | `FALSE` | see divergence note below |

**Configuration verdict (authoritative):** v1.13 RX path = **elastic buffer, no clock correction, no channel bonding** (`RX_CB_NUM_SEQ=0`, `RX_CC_NUM_SEQ=0` at CONFIG level, `CLK_CORRECT_USE=FALSE` at primitive level — consistent). RX user clocks derive from `RX_OUTCLK_SOURCE = RXOUTCLKPMA` of `RX_MASTER_CHANNEL = X0Y4`.

**Observed CONFIG-vs-primitive divergence (informational):** `CONFIG.RX_COMMA_SHOW_REALIGN_ENABLE = true` but primitive `SHOW_REALIGN_COMMA = FALSE` — the wizard forces the attribute off in the buffered configuration (realign inside the buffer must not propagate an alignment glitch downstream). Typical example of CONFIG saying one thing and the primitive another; always verify at netlist level.

**Timing implications (recorded for error-budget / DC-loop sessions):**
1. **CH0 / dev bench:** buffer write side (own recovered clock) and read side (RXOUTCLK of X0Y4 = the same recovered clock) are frequency-identical → static fill, no slips. Current bench and the slave uplink are stable by construction; **protocol-level CCS frames are not needed** (Command Spec §6 CCS item → resolved).
2. **GT clock correction must stay disabled permanently:** CC inserts/removes symbols → variable transport latency → breaks the LOAD_TIME zero-tick contract and RTT constancy. Structural invariant, not a tuning choice.
3. **Multi-uplink master (channels ≠ X0Y4 with live traffic):** each RX writes on its own slave's recovered clock, all read on X0Y4's — with unsyntonised downstream TX (QPLL ← local osc, v1.13) the ppm difference makes those buffers creep and periodically slip. Resolution candidates (deferred to TX-mux / scaling design): per-channel RX user clocking, or downstream TX syntonisation (QPLL from cleaned recovered clock).
4. **Buffer fill = per-session constant:** RX latency through the buffer is constant within a link session but need not reproduce across buffer resets / re-locks. Periodic RTT re-measures it; zero-tick contract requires within-session determinism only.

## All CONFIG.* Parameters (sorted)

| Parameter | Value |
|---|---|
| `CONFIG.CHANNEL_ENABLE` | `X0Y7 X0Y6 X0Y5 X0Y4` |
| `CONFIG.Component_Name` | `gtwizard_ultrascale_0` |
| `CONFIG.DISABLE_LOC_XDC` | `0` |
| `CONFIG.ENABLE_COMMON_USRCLK` | `0` |
| `CONFIG.ENABLE_OPTIONAL_PORTS` | `loopback_in cplllock_out eyescandataerror_out qpll0lock_out qpll1lock_out rxbufstatus_out rxcdrlock_out rxphaligndone_out rxresetdone_out rxsyncdone_out txbufstatus_out txdlysresetdone_out txphaligndone_out txresetdone_out` |
| `CONFIG.FREERUN_FREQUENCY` | `100` |
| `CONFIG.GT_DIRECTION` | `BOTH` |
| `CONFIG.GT_REV` | `0` |
| `CONFIG.GT_TYPE` | `GTH` |
| `CONFIG.INCLUDE_CPLL_CAL` | `2` |
| `CONFIG.INS_LOSS_NYQ` | `7` |
| `CONFIG.INTERNAL_PRESET` | `None` |
| `CONFIG.LOCATE_COMMON` | `CORE` |
| `CONFIG.LOCATE_IN_SYSTEM_IBERT_CORE` | `NONE` |
| `CONFIG.LOCATE_RESET_CONTROLLER` | `CORE` |
| `CONFIG.LOCATE_RX_BUFFER_BYPASS_CONTROLLER` | `CORE` |
| `CONFIG.LOCATE_RX_USER_CLOCKING` | `EXAMPLE_DESIGN` |
| `CONFIG.LOCATE_TX_BUFFER_BYPASS_CONTROLLER` | `CORE` |
| `CONFIG.LOCATE_TX_USER_CLOCKING` | `EXAMPLE_DESIGN` |
| `CONFIG.LOCATE_USER_DATA_WIDTH_SIZING` | `CORE` |
| `CONFIG.OOB_ENABLE` | `false` |
| `CONFIG.ORGANIZE_PORTS_BY` | `NAME` |
| `CONFIG.PCIE_64BIT` | `false` |
| `CONFIG.PCIE_CORECLK_FREQ` | `250` |
| `CONFIG.PCIE_ENABLE` | `false` |
| `CONFIG.PCIE_GEN4_EIOS` | `false` |
| `CONFIG.PCIE_USERCLK_FREQ` | `250` |
| `CONFIG.PRESET` | `None` |
| `CONFIG.RESET_SEQUENCE_INTERVAL` | `0` |
| `CONFIG.RX_BUFFER_BYPASS_MODE` | `MULTI` |
| `CONFIG.RX_BUFFER_MODE` | `1` |
| `CONFIG.RX_BUFFER_RESET_ON_CB_CHANGE` | `ENABLE` |
| `CONFIG.RX_BUFFER_RESET_ON_COMMAALIGN` | `DISABLE` |
| `CONFIG.RX_BUFFER_RESET_ON_RATE_CHANGE` | `ENABLE` |
| `CONFIG.RX_CB_DISP_0_0` | `false` |
| `CONFIG.RX_CB_DISP_0_1` | `false` |
| `CONFIG.RX_CB_DISP_0_2` | `false` |
| `CONFIG.RX_CB_DISP_0_3` | `false` |
| `CONFIG.RX_CB_DISP_1_0` | `false` |
| `CONFIG.RX_CB_DISP_1_1` | `false` |
| `CONFIG.RX_CB_DISP_1_2` | `false` |
| `CONFIG.RX_CB_DISP_1_3` | `false` |
| `CONFIG.RX_CB_K_0_0` | `false` |
| `CONFIG.RX_CB_K_0_1` | `false` |
| `CONFIG.RX_CB_K_0_2` | `false` |
| `CONFIG.RX_CB_K_0_3` | `false` |
| `CONFIG.RX_CB_K_1_0` | `false` |
| `CONFIG.RX_CB_K_1_1` | `false` |
| `CONFIG.RX_CB_K_1_2` | `false` |
| `CONFIG.RX_CB_K_1_3` | `false` |
| `CONFIG.RX_CB_LEN_SEQ` | `1` |
| `CONFIG.RX_CB_MASK_0_0` | `false` |
| `CONFIG.RX_CB_MASK_0_1` | `false` |
| `CONFIG.RX_CB_MASK_0_2` | `false` |
| `CONFIG.RX_CB_MASK_0_3` | `false` |
| `CONFIG.RX_CB_MASK_1_0` | `false` |
| `CONFIG.RX_CB_MASK_1_1` | `false` |
| `CONFIG.RX_CB_MASK_1_2` | `false` |
| `CONFIG.RX_CB_MASK_1_3` | `false` |
| `CONFIG.RX_CB_MAX_LEVEL` | `2` |
| `CONFIG.RX_CB_MAX_SKEW` | `1` |
| `CONFIG.RX_CB_NUM_SEQ` | `0` |
| `CONFIG.RX_CB_VAL_0_0` | `00000000` |
| `CONFIG.RX_CB_VAL_0_1` | `00000000` |
| `CONFIG.RX_CB_VAL_0_2` | `00000000` |
| `CONFIG.RX_CB_VAL_0_3` | `00000000` |
| `CONFIG.RX_CB_VAL_1_0` | `00000000` |
| `CONFIG.RX_CB_VAL_1_1` | `00000000` |
| `CONFIG.RX_CB_VAL_1_2` | `00000000` |
| `CONFIG.RX_CB_VAL_1_3` | `00000000` |
| `CONFIG.RX_CC_DISP_0_0` | `false` |
| `CONFIG.RX_CC_DISP_0_1` | `false` |
| `CONFIG.RX_CC_DISP_0_2` | `false` |
| `CONFIG.RX_CC_DISP_0_3` | `false` |
| `CONFIG.RX_CC_DISP_1_0` | `false` |
| `CONFIG.RX_CC_DISP_1_1` | `false` |
| `CONFIG.RX_CC_DISP_1_2` | `false` |
| `CONFIG.RX_CC_DISP_1_3` | `false` |
| `CONFIG.RX_CC_KEEP_IDLE` | `DISABLE` |
| `CONFIG.RX_CC_K_0_0` | `false` |
| `CONFIG.RX_CC_K_0_1` | `false` |
| `CONFIG.RX_CC_K_0_2` | `false` |
| `CONFIG.RX_CC_K_0_3` | `false` |
| `CONFIG.RX_CC_K_1_0` | `false` |
| `CONFIG.RX_CC_K_1_1` | `false` |
| `CONFIG.RX_CC_K_1_2` | `false` |
| `CONFIG.RX_CC_K_1_3` | `false` |
| `CONFIG.RX_CC_LEN_SEQ` | `1` |
| `CONFIG.RX_CC_MASK_0_0` | `false` |
| `CONFIG.RX_CC_MASK_0_1` | `false` |
| `CONFIG.RX_CC_MASK_0_2` | `false` |
| `CONFIG.RX_CC_MASK_0_3` | `false` |
| `CONFIG.RX_CC_MASK_1_0` | `false` |
| `CONFIG.RX_CC_MASK_1_1` | `false` |
| `CONFIG.RX_CC_MASK_1_2` | `false` |
| `CONFIG.RX_CC_MASK_1_3` | `false` |
| `CONFIG.RX_CC_NUM_SEQ` | `0` |
| `CONFIG.RX_CC_PERIODICITY` | `5000` |
| `CONFIG.RX_CC_PRECEDENCE` | `ENABLE` |
| `CONFIG.RX_CC_REPEAT_WAIT` | `0` |
| `CONFIG.RX_CC_VAL` | `00000000000000000000000000000000000000000000000000000000000000000000000000000000` |
| `CONFIG.RX_CC_VAL_0_0` | `00000000` |
| `CONFIG.RX_CC_VAL_0_1` | `00000000` |
| `CONFIG.RX_CC_VAL_0_2` | `00000000` |
| `CONFIG.RX_CC_VAL_0_3` | `00000000` |
| `CONFIG.RX_CC_VAL_1_0` | `00000000` |
| `CONFIG.RX_CC_VAL_1_1` | `00000000` |
| `CONFIG.RX_CC_VAL_1_2` | `00000000` |
| `CONFIG.RX_CC_VAL_1_3` | `00000000` |
| `CONFIG.RX_COMMA_ALIGN_WORD` | `1` |
| `CONFIG.RX_COMMA_DOUBLE_ENABLE` | `false` |
| `CONFIG.RX_COMMA_MASK` | `1111111111` |
| `CONFIG.RX_COMMA_M_ENABLE` | `true` |
| `CONFIG.RX_COMMA_M_VAL` | `1010000011` |
| `CONFIG.RX_COMMA_PRESET` | `K28.5` |
| `CONFIG.RX_COMMA_P_ENABLE` | `true` |
| `CONFIG.RX_COMMA_P_VAL` | `0101111100` |
| `CONFIG.RX_COMMA_SHOW_REALIGN_ENABLE` | `true` |
| `CONFIG.RX_COMMA_VALID_ONLY` | `0` |
| `CONFIG.RX_COUPLING` | `AC` |
| `CONFIG.RX_DATA_DECODING` | `8B10B` |
| `CONFIG.RX_EQ_MODE` | `AUTO` |
| `CONFIG.RX_INT_DATA_WIDTH` | `20` |
| `CONFIG.RX_JTOL_FC` | `3.7492501` |
| `CONFIG.RX_JTOL_LF_SLOPE` | `-20` |
| `CONFIG.RX_LINE_RATE` | `6.25` |
| `CONFIG.RX_MASTER_CHANNEL` | `X0Y4` |
| `CONFIG.RX_OUTCLK_SOURCE` | `RXOUTCLKPMA` |
| `CONFIG.RX_PLL_TYPE` | `QPLL0` |
| `CONFIG.RX_PPM_OFFSET` | `200` |
| `CONFIG.RX_QPLL_FRACN_NUMERATOR` | `0` |
| `CONFIG.RX_RECCLK_OUTPUT` | `` |
| `CONFIG.RX_REFCLK_FREQUENCY` | `156.25` |
| `CONFIG.RX_REFCLK_SOURCE` | `` |
| `CONFIG.RX_SLIDE_MODE` | `PCS` |
| `CONFIG.RX_SSC_PPM` | `0` |
| `CONFIG.RX_TERMINATION` | `AVTT` |
| `CONFIG.RX_TERMINATION_PROG_VALUE` | `800` |
| `CONFIG.RX_USER_DATA_WIDTH` | `16` |
| `CONFIG.SATA_TX_BURST_LEN` | `15` |
| `CONFIG.SECONDARY_QPLL_ENABLE` | `false` |
| `CONFIG.SECONDARY_QPLL_FRACN_NUMERATOR` | `0` |
| `CONFIG.SECONDARY_QPLL_LINE_RATE` | `10.3125` |
| `CONFIG.SECONDARY_QPLL_REFCLK_FREQUENCY` | `257.8125` |
| `CONFIG.SIM_CPLL_CAL_BYPASS` | `1` |
| `CONFIG.TXPROGDIV_FREQ_ENABLE` | `false` |
| `CONFIG.TXPROGDIV_FREQ_SOURCE` | `QPLL0` |
| `CONFIG.TXPROGDIV_FREQ_VAL` | `312.5` |
| `CONFIG.TX_BUFFER_MODE` | `1` |
| `CONFIG.TX_BUFFER_RESET_ON_RATE_CHANGE` | `ENABLE` |
| `CONFIG.TX_DATA_ENCODING` | `8B10B` |
| `CONFIG.TX_DIFF_SWING_EMPH_MODE` | `CUSTOM` |
| `CONFIG.TX_INT_DATA_WIDTH` | `20` |
| `CONFIG.TX_LINE_RATE` | `6.25` |
| `CONFIG.TX_MASTER_CHANNEL` | `X0Y4` |
| `CONFIG.TX_OUTCLK_SOURCE` | `TXOUTCLKPMA` |
| `CONFIG.TX_PLL_TYPE` | `QPLL0` |
| `CONFIG.TX_QPLL_FRACN_NUMERATOR` | `0` |
| `CONFIG.TX_REFCLK_FREQUENCY` | `156.25` |
| `CONFIG.TX_REFCLK_SOURCE` | `` |
| `CONFIG.TX_USER_DATA_WIDTH` | `16` |
| `CONFIG.USB_ENABLE` | `false` |
| `CONFIG.USER_GTPOWERGOOD_DELAY_EN` | `1` |

## Key Parameters Highlighted

### RX Physical Layer (Phase 1 critical)

| Parameter | Value | Notes |
|---|---|---|
| RX_PPM_OFFSET | 200 | 200 = applied for plesiochronous link |
| RX_TERMINATION | AVTT | AVTT = SFP+ standard |
| RX_COUPLING | AC | AC required for SFP+ |
| RX_EQ_MODE | AUTO | AUTO → LPM at 7 dB IL |
| INS_LOSS_NYQ | 7 | dB; <14 → LPM |

### Rate & data path

| Parameter | Value |
|---|---|
| RX_LINE_RATE | 6.25 Gbps |
| TX_LINE_RATE | 6.25 Gbps |
| RX_REFCLK_FREQUENCY | 156.25 MHz |
| RX_USER_DATA_WIDTH | 16 bits |
| RX_INT_DATA_WIDTH | 20 bits |
| RX_DATA_DECODING | 8B10B |
| RX_PLL_TYPE | QPLL0 |

### Comma & alignment

| Parameter | Value |
|---|---|
| RX_COMMA_PRESET | K28.5 |
| RX_COMMA_P_ENABLE | true |
| RX_COMMA_M_ENABLE | true |
| RX_COMMA_VALID_ONLY | 0 |
| RX_COMMA_ALIGN_WORD | 1 |
| RX_SLIDE_MODE | PCS |

### Buffer config (r2: verified at primitive level)

| Parameter | CONFIG value | Primitive attribute |
|---|---|---|
| RX buffer | RX_BUFFER_MODE = 1 | RXBUF_EN = TRUE, RX_XCLK_SEL = RXDES |
| TX buffer | TX_BUFFER_MODE = 1 | TXBUF_EN = TRUE, TX_XCLK_SEL = TXOUT |
| Clock correction | RX_CC_NUM_SEQ = 0 | CLK_CORRECT_USE = FALSE |
| Channel bonding | RX_CB_NUM_SEQ = 0 | (disabled) |
| RX_BUFFER_RESET_ON_COMMAALIGN | DISABLE | — |

### Channels & PLL

| Parameter | Value |
|---|---|
| CHANNEL_ENABLE | X0Y7 X0Y6 X0Y5 X0Y4 |
| RX_MASTER_CHANNEL | X0Y4 |
| TX_MASTER_CHANNEL | X0Y4 |
| RX_PLL_TYPE | QPLL0 |
| TX_PLL_TYPE | QPLL0 |
| SECONDARY_QPLL_ENABLE | false |
| FREERUN_FREQUENCY | 100 MHz |

### TX driver

| Parameter | Value |
|---|---|
| TX_DIFF_SWING_EMPH_MODE | CUSTOM |
| TXPROGDIV_FREQ_VAL | 312.5 MHz |

Note: With TX_DIFF_SWING_EMPH_MODE=CUSTOM, individual swing/emphasis
values are encoded in primitive attributes (not exposed at this CONFIG level).
Generated wrapper shows TXDIFFCTRL=0x18 (~880 mV) all 4 channels,
TXPRECURSOR=0, TXPOSTCURSOR=0 — direct mode, no emphasis.

### Channel bonding & clock correction

| Parameter | Value |
|---|---|
| RX_CB_NUM_SEQ | 0 (0=disabled) |
| RX_CC_NUM_SEQ | 0 (0=disabled) |

---

## Notes on extraction method — authoritative IP path (important)

This snapshot is the canonical GT-parameter record. Values were read with
`get_property CONFIG.*` / `report_property` against the **live IP object** in
the open project — not from an XCI file on disk. The r2 primitive-attribute
dump was read from GTHE4_CHANNEL cells in the **synthesized netlist**
(`open_run synth_1`) — one level below CONFIG, i.e. what actually enters the
bitstream.

**Path lesson (recurring pitfall).** An earlier attempt extracted parameters
by reading XCI files under
`murosync_poc_v1.srcs/sources_1/ip/gtwizard_ultrascale_0/` — those are
**stale copies that synthesis does NOT use**. The authoritative IP that
synthesis actually builds from lives under the `.gen` tree
(`murosync_poc_v1.gen/sources_1/bd/bd_murosync_poc/ip/.../prj/gtwizard_ultrascale_0_ex.srcs/sources_1/ip/gtwizard_ultrascale_0`),
NOT `.srcs`. Always query the live IP object, or read from `.gen`. The same
`.srcs`-vs-`.gen` (and `src/`-vs-imported) divergence bites RTL edits too:
verify against the synthesized netlist / live object, never a loose file in `.srcs`.

**Verification lesson (r2).** CONFIG-level truth and primitive-level truth can
diverge (observed here: `RX_COMMA_SHOW_REALIGN_ENABLE=true` vs
`SHOW_REALIGN_COMMA=FALSE` — wizard override in buffered mode). Configuration
claims in architecture documents must cite the primitive-attribute dump, not
the wizard GUI or CONFIG table alone.

---

*GT Wizard Parameter Snapshot — v1.13-r2 — 2026-05-29 (r2: 2026-07-14) — Mikhail Vasilev / MuroSync.*
*Engineering record; canonical GT configuration baseline for `murosync_serdes_array`.*
*Restricted / proprietary — NOT Apache-2.0. Copyright (c) 2026 Mikhail Vasilev / MuroSync. info@murosync.com.*
