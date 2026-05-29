# GT Wizard Parameter Snapshot — `gtwizard_ultrascale_0`

**Extracted:** 2026-05-29 01:59
**Method:** Vivado TCL `get_property CONFIG.*` against live main project IP
**Source project:** murosync_poc_v1 at C:/_vivado/murosync_poc_v1
**IP_DIR (build chain):**
  `c:/_vivado/murosync_poc_v1/murosync_poc_v1.gen/sources_1/bd/bd_murosync_poc/ip/bd_murosync_poc_murosync_serdes_array_0_1/prj/gtwizard_ultrascale_0_ex.srcs/sources_1/ip/gtwizard_ultrascale_0`
**Authority:** This is the IP that synthesis uses to build the bitstream.

## IP State

| Property | Value |
|---|---|
| NAME | gtwizard_ultrascale_0 |
| IPDEF | xilinx.com:ip:gtwizard_ultrascale:1.7 |
| IS_LOCKED | 0 |
| USER_LOCKED | 0 |
| STALE_TARGETS | '' |
| CORE_REVISION | 14 |
| SW_VERSION | 2022.2 |
| PART | xcau15p-ffvb676-2-i |

## Key parameters (Phase 1 critical)

### RX physical layer

| Parameter | Value | Note |
|---|---|---|
| RX_PPM_OFFSET | 200 | 200 = plesiochronous |
| RX_TERMINATION | AVTT | AVTT = SFP+ standard |
| RX_COUPLING | AC | AC for SFP+ |
| RX_EQ_MODE | AUTO | AUTO  LPM at 7 dB IL |
| INS_LOSS_NYQ | 7 | dB |

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
| FREERUN_FREQUENCY | 100 MHz |

### Comma & alignment

| Parameter | Value |
|---|---|
| RX_COMMA_PRESET | K28.5 |
| RX_COMMA_P_ENABLE | true |
| RX_COMMA_M_ENABLE | true |
| RX_COMMA_P_VAL | 0101111100 |
| RX_COMMA_M_VAL | 1010000011 |
| RX_COMMA_VALID_ONLY | 0 |
| RX_COMMA_ALIGN_WORD | 1 |
| RX_SLIDE_MODE | PCS |

### Buffer config

| Parameter | Value |
|---|---|
| RX_BUFFER_MODE | 1 |
| TX_BUFFER_MODE | 1 |
| RX_BUFFER_RESET_ON_COMMAALIGN | DISABLE |
| RX_BUFFER_RESET_ON_RATE_CHANGE | ENABLE |
| TX_BUFFER_RESET_ON_RATE_CHANGE | ENABLE |

### Channels & locations

| Parameter | Value |
|---|---|
| CHANNEL_ENABLE | X0Y7 X0Y6 X0Y5 X0Y4 |
| RX_MASTER_CHANNEL | X0Y4 |
| TX_MASTER_CHANNEL | X0Y4 |
| SECONDARY_QPLL_ENABLE | false |

### TX driver

| Parameter | Value |
|---|---|
| TX_DIFF_SWING_EMPH_MODE | CUSTOM |
| TXPROGDIV_FREQ_VAL | 312.5 MHz |

Note: TX_DIFF_SWING_EMPH_MODE=CUSTOM  swing/emphasis stored in
primitive attributes. Generated wrapper shows TXDIFFCTRL=0x18
(\~880 mV) all 4 channels, TXPRECURSOR=0, TXPOSTCURSOR=0 —
direct mode, no emphasis.

### Channel bonding & clock correction (both disabled)

| Parameter | Value |
|---|---|
| RX_CB_NUM_SEQ | 0 |
| RX_CC_NUM_SEQ | 0 |

---

## All CONFIG.* parameters (full sorted list)

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

---

*Generated by Vivado TCL on live project. Authoritative — this is what
synthesis sees and what goes into the bitstream.*
