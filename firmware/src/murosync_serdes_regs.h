/******************************************************************************
 *  Project    : MuroSync
 *  File       : murosync_serdes_regs.h
 *  Created    : 2026-01-02
 *  Author     : Mikhail Vasilev
 *
 *  Description:
 *  AXI4-Lite register map definitions for the MuroSync SERDES subsystem
 *  (murosync_serdes_array_axi_ctrl, 32-bit data width).
 *
 *  This header provides register offsets, bit-field masks, and self-test
 *  constants used by firmware and test applications to configure, bring up,
 *  and monitor the MuroSync optical SERDES array.
 *
 *  Register Map Summary:
 *
 *    0x000  MUROSYNC_SERDES_CTRL          (WO / W1P)
 *           [0]  LINK_LATCH_RESET         Clear LINK_DOWN_LATCHED sticky flag (W1P)
 *           [1]  GT_RESET_ALL             Optional GT reset pulse, OR into hb_gtwiz_reset_all (W1P)
 *
 *    0x004  MUROSYNC_SERDES_LOOPBACK      (RW)
 *           [2:0] LOOPBACK_CTRL           Forwarded to GT Wizard loopback_in (if enabled)
 *
 *    0x008  MUROSYNC_SERDES_STATUS        (RO)
 *           [0]      LINK_UP
 *           [1]      LINK_DOWN_LATCHED
 *           [19:16]  PLL_LOCK[3:0]
 *           [23:20]  GTPOWERGOOD[3:0]
 *           [27:24]  TXPMARESETDONE[3:0]
 *           [31:28]  RXPMARESETDONE[3:0]
 *
 *    0x00C  MUROSYNC_SERDES_DBG_LO        (RO)  Debug bus [31:0]
 *    0x010  MUROSYNC_SERDES_DBG_HI        (RO)  Debug bus [63:32]
 *
 *    0x014  MUROSYNC_SERDES_TEST_CONST    (RO)  Constant magic ("MURO" = 0x4D55524F)
 *    0x018  MUROSYNC_SERDES_TEST_SCRATCH  (RW)  Scratch register (R/W)
 * 
 *    0x01C  MUROSYNC_LNK_TEST_CTRL        (RW / W1P)
 *           [0]      ENABLE               Enable Link Test Engine (RW)
 *           [1]      RESET                Reset Test Counters (W1P)
 *
 *    0x020  MUROSYNC_LNK_TEST_CNFG        (RW)
 *           [1:0]    MODE_SEL             Test Mode: 0=Fixed, 1=Counter, 2=PRBS
 *
 *    0x024  MUROSYNC_LNK_TEST_PATT        (RW)  Fixed Test Pattern [31:0]
 *    0x028  MUROSYNC_LNK_RX_ERR_CNT       (RO)  RX Error Counter [31:0]
 *    0x02C  MUROSYNC_LNK_RX_WRD_CNT       (RO)  RX Word Counter [31:0]
 *
 *  Intended usage:
 *    - Firmware drivers (MicroBlaze / bare-metal) for bring-up and diagnostics
 *    - Consistent HW/SW integration via shared offsets and masks
 *
 *  Copyright (c) 2026 Mikhail Vasilev / MuroSync
 *
 *  License:
 *  This file is currently released under a restricted research license.
 *  Licensing terms may change in future revisions of the project.
 *
 *  Commercial use, redistribution, or integration into commercial products
 *  requires an explicit license agreement.
 *
 *  For licensing inquiries, please contact:
 *      info@murosync.com
 *
 *****************************************************************************/

#ifndef MUROSYNC_SERDES_ARRAY_REGS_H
#define MUROSYNC_SERDES_ARRAY_REGS_H

/* ========================================================================
 * MuroSync SERDES Array — AXI Register Map Summary
 *
 *  Offset    Name                              RW   Purpose
 *  --------  --------------------------------  ---- ----------------------------------
 *  Control / Status:
 *  0x000     CTRL                              W1P  LINK_LATCH_RESET, GT_RESET_ALL
 *  0x004     LOOPBACK                          RW   GT loopback mode
 *  0x008     STATUS                            RO   link_up, latched, pll_lock, ...
 *  0x00C     DBG_LO / 0x010 DBG_HI             RO   64-bit debug snapshot
 *  0x014     TEST_CONST                        RO   0x4D55524F (AXI self-test)
 *  0x018     TEST_SCRATCH                      RW   AXI write/read self-test
 *
 *  Link Test (basic):
 *  0x01C     LNK_TEST_CTRL                     W1P  ENABLE, RESET (W1P bit 1)
 *  0x020     LNK_TEST_CNFG                     RW   Mode, Ch Mask, Pol Mask
 *  0x024     LNK_TEST_PATT                     RW   Fixed test pattern [31:0]
 *  0x028     LNK_RX_ERR_CNT                    RO   Global error count
 *  0x02C     LNK_RX_WRD_CNT                    RO   Global word count
 *
 *  Link Test Diagnostic (Tier 0):
 *  0x030     LNK_DIAG_STATUS                   RO   FSM, aligned, aligned_seen, charisk, locked
 *  0x034/038 LNK_DIAG_RX_LO/HI                 RO   Last received word (64-bit)
 *  0x03C/040 LNK_DIAG_EXP_LO/HI                RO   Current expected word (64-bit)
 *  0x044/048 LNK_DIAG_TX_DATA_LO/HI            RO   Current TX pattern
 *  0x04C/050 LNK_DIAG_TX_COUNTERS_LO/HI        RO   Per-channel TX counter values
 *  0x054     LNK_DIAG_TX_STATUS                RO   TX comma active, comma count
 *
 *  GT Wizard Debug:
 *  0x058     GT_DEBUG_COMMA_ALIGN              RO   rxcommadet, rxbyteisaligned, rxbyterealign
 *  0x05C     GT_DEBUG_RXBUF_STATUS             RO
 *  0x060     GT_DEBUG_TXBUF_STATUS             RO
 *  0x064     GT_DEBUG_SYNC_STATUS              RO
 *  0x068     GT_DEBUG_SIGNAL_QUAL              RO
 *  0x06C     GT_DEBUG_RESET_STATUS             RO
 *
 *  Tier 1+2 Sticky Diagnostic:
 *  0x070     LNK_DIAG_STATUS2                  RO   ever_locked, last_fsm_state, snapshot valid bits
 *
 *  Build Identity:
 *  0x074     IP_INFO                           RO   IS_SLAVE/IS_MASTER, IP_VERSION, NUM_CHANNELS
 *
 *  Tier 2 Snapshots & Timing:
 *  0x080     LNK_TIME_TO_LOCK                  RO   Cycles WAIT_ALIGN -> LOCKED (frozen)
 *  0x084     LNK_LOCKED_CYCLE_COUNT            RO   Total cycles in LOCKED
 *  0x088/08C LNK_RX_DATA_AT_LOCK_LO/HI         RO   rx_data at first LOCKED entry
 *  0x090/094 LNK_RX_DATA_AT_FIRST_ERR_LO/HI    RO   rx_data at first error
 *
 *  Tier 2 Per-Channel Errors (16-bit in lower half each):
 *  0x098..0A4  LNK_ERR_CNT_CH0..CH3            RO   Per-channel error counters
 *
 *  Tier 2 GT Sticky Counters (CH packed: LO[15:0]=CHn, LO[31:16]=CHn+1):
 *  0x0A8/0AC GT_RXBYTEREALIGN_CNT_LO/HI        RO   Per-channel realign events
 *  0x0B0/0B4 GT_EYESCANDATAERROR_CNT_LO/HI     RO   Per-channel eye scan errors
 *
 *  Tier 2 Stage 5 — paired snapshot for diff diagnostic:
 *  0x0B8/0BC LNK_EXP_DATA_AT_FIRST_ERR_LO/HI   RO   Expected pattern at first error
 *                                                   (XOR with RX_DATA_AT_FIRST_ERR =
 *                                                    error pattern; popcount = bit-flip count)
 *
 *  Validity bits (read from LNK_DIAG_STATUS2 at 0x070):
 *    [0]    ever_locked
 *    [7:4]  last_fsm_state
 *    [16]   rx_data_at_lock_valid
 *    [17]   first_err_valid  (covers RX_DATA_AT_FIRST_ERR and EXP_DATA_AT_FIRST_ERR)
 *
 *  Total registers used: 49 (0x000 - 0x0BC). Free slots: 0x078-0x07C (2 slots).
 * ======================================================================== */

////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////  SERDES_CTRL  ///////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////

#define MUROSYNC_SERDES_CTRL						(0x000)  // SERDES_CTRL (Control Register)

	/*
	Type		:	WO / W1P
	Default		:	0
	Description :	Control register (Write-One-Pulse bits).
					Writing '1' generates a pulse in core_clk domain (via CDC).
					Bits are typically self-cleared by SW (write 0) or by HW register clear policy.
	*/

	/*
	Type		:	WO / W1P
	Default		:	0
	Description :	LINK_DOWN_LATCHED_RESET
					Write '1' to generate a pulse that clears link_down_latched flag in core domain.
	*/

	#define MUROSYNC_SERDES_CTRL_LINK_LATCH_RESET_OFS			0
	#define MUROSYNC_SERDES_CTRL_LINK_LATCH_RESET_MSK			(0x1u << MUROSYNC_SERDES_CTRL_LINK_LATCH_RESET_OFS)

	/*
	Type		:	WO / W1P
	Default		:	0
	Description :	GT_RESET_ALL_PULSE
					Write '1' to generate a pulse that can be OR'ed into hb_gtwiz_reset_all (optional).
					Use only if top-level integrates this pulse into GT reset logic.
	*/

	#define MUROSYNC_SERDES_CTRL_GT_RESET_ALL_OFS				1
	#define MUROSYNC_SERDES_CTRL_GT_RESET_ALL_MSK				(0x1u << MUROSYNC_SERDES_CTRL_GT_RESET_ALL_OFS)


////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////  SERDES_LOOPBACK  /////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////

#define MUROSYNC_SERDES_LOOPBACK					(0x004)  // SERDES_LOOPBACK (Loopback Control Register)

	/*
	Type		:	R/W
	Default		:	0
	Description :	Loopback control (3-bit level).
					Value is synchronized into core_clk domain and forwarded to GT Wizard loopback_in,
					*only if* GT Wizard was generated with LOOPBACK port enabled.
					Otherwise this field is harmless (ignored).
	*/

	#define MUROSYNC_SERDES_LOOPBACK_CTRL_OFS					0
	#define MUROSYNC_SERDES_LOOPBACK_CTRL_MSK					(0x7u << MUROSYNC_SERDES_LOOPBACK_CTRL_OFS)


////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////  SERDES_STATUS  /////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////

#define MUROSYNC_SERDES_STATUS                        (0x008)  // SERDES_STATUS (Status Register)

	/*
	Type        :   R
	Default     :   0
	Description :   LINK_UP
	                '1' indicates GT bring-up considered OK by top-level definition (link_up_raw).
	*/
	#define MUROSYNC_SERDES_STATUS_LINK_UP_OFS            0
	#define MUROSYNC_SERDES_STATUS_LINK_UP_MSK            (0x1u << MUROSYNC_SERDES_STATUS_LINK_UP_OFS)
	
	/*
	Type        :   R
	Default     :   0
	Description :   LINK_DOWN_LATCHED
	                Sticky fault indicator latched in core logic.
	                Can be cleared via MUROSYNC_SERDES_CTRL_LINK_LATCH_RESET (W1P).
	*/
	#define MUROSYNC_SERDES_STATUS_LINK_DOWN_LAT_OFS      1
	#define MUROSYNC_SERDES_STATUS_LINK_DOWN_LAT_MSK      (0x1u << MUROSYNC_SERDES_STATUS_LINK_DOWN_LAT_OFS)
	
	/*
	Type        :   R
	Default     :   0
	Description :   PLL_LOCK[3:0]  (unified lock vector)
	*/
	#define MUROSYNC_SERDES_STATUS_PLL_LOCK_OFS           16
	#define MUROSYNC_SERDES_STATUS_PLL_LOCK_MSK           (0xFu << MUROSYNC_SERDES_STATUS_PLL_LOCK_OFS)
	
	/*
	Type        :   R
	Default     :   0
	Description :   GTPOWERGOOD[3:0]
	                Per-channel GT powergood indicators (from GT wizard).
	*/
	#define MUROSYNC_SERDES_STATUS_GTPOWERGOOD_OFS        20
	#define MUROSYNC_SERDES_STATUS_GTPOWERGOOD_MSK        (0xFu << MUROSYNC_SERDES_STATUS_GTPOWERGOOD_OFS)
	
	/*
	Type        :   R
	Default     :   0
	Description :   TXPMARESETDONE[3:0]
	                Per-channel TX PMA reset done indicators.
	*/
	#define MUROSYNC_SERDES_STATUS_TXPMARESETDONE_OFS     24
	#define MUROSYNC_SERDES_STATUS_TXPMARESETDONE_MSK     (0xFu << MUROSYNC_SERDES_STATUS_TXPMARESETDONE_OFS)
	
	/*
	Type        :   R
	Default     :   0
	Description :   RXPMARESETDONE[3:0]
	                Per-channel RX PMA reset done indicators.
	*/
	#define MUROSYNC_SERDES_STATUS_RXPMARESETDONE_OFS     28
	#define MUROSYNC_SERDES_STATUS_RXPMARESETDONE_MSK     (0xFu << MUROSYNC_SERDES_STATUS_RXPMARESETDONE_OFS)


////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////  SERDES_DBG_LO  ////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////

#define MUROSYNC_SERDES_DBG_LO						(0x00C)  // SERDES_DBG_LO (Debug bus [31:0])

	/*
	Type		:	R
	Default		:	0
	Description :	Debug bus low word.
					Contains dbg[31:0] sampled into AXI clock domain (debug-only).
	*/

	#define MUROSYNC_SERDES_DBG_LO_DATA_OFS						0
	#define MUROSYNC_SERDES_DBG_LO_DATA_MSK						(0xFFFFFFFFu)


////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////  SERDES_DBG_HI  ////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////

#define MUROSYNC_SERDES_DBG_HI						(0x010)  // SERDES_DBG_HI (Debug bus [63:32])

	/*
	Type		:	R
	Default		:	0
	Description :	Debug bus high word.
					Contains dbg[63:32] sampled into AXI clock domain (debug-only).
	*/

	#define MUROSYNC_SERDES_DBG_HI_DATA_OFS						0
	#define MUROSYNC_SERDES_DBG_HI_DATA_MSK						(0xFFFFFFFFu)

////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////  SERDES_TEST_CONST  //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////

#define MUROSYNC_SERDES_TEST_CONST                  (0x014)  // RO constant

	#define MUROSYNC_SERDES_TEST_MAGIC                  (0x4D55524Fu) // "MURO"

////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////  SERDES_TEST_SCRATCH  ////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////

#define MUROSYNC_SERDES_TEST_SCRATCH                (0x018)  // RW scratch register

	#define MUROSYNC_SERDES_TEST_SCRATCH_MSK            (0xFFFFFFFFu)

////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////  LNK_TEST_CTRL  ///////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////

#define MUROSYNC_LNK_TEST_CTRL                      (0x01C)  // Link Test Control

	/*
	Type        :   R/W (bit 0), WO/W1P (bit 1)
	Description :   [0] ENABLE: 1 = Enable Link Test Engine
	                [1] RESET:  1 = Pulse to reset counters (W1P)
	*/

	#define MUROSYNC_LNK_TEST_CTRL_EN_OFS                 0
	#define MUROSYNC_LNK_TEST_CTRL_EN_MSK                 (0x1u << MUROSYNC_LNK_TEST_CTRL_EN_OFS)

	#define MUROSYNC_LNK_TEST_CTRL_RST_OFS                1
	#define MUROSYNC_LNK_TEST_CTRL_RST_MSK                (0x1u << MUROSYNC_LNK_TEST_CTRL_RST_OFS)

////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////  LNK_TEST_CNFG  ///////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////

#define MUROSYNC_LNK_TEST_CNFG                      (0x020)  // Test Configuration

	/*
	Type        :   R/W
	Description :   [1:0] MODE_SEL: 0=Fixed, 1=Toggle, 2=Counter
	                [7:4] CH_MASK:  Channel select mask (1 = Test this channel, 0 = Ignore)
	                [11:8] RX_POL_MASK: RX Logic Polarity Inversion Mask
	                [15:12] TX_POL_MASK: TX Logic Polarity Inversion Mask
	*/

	#define MUROSYNC_LNK_TEST_CNFG_MODE_OFS               0
	#define MUROSYNC_LNK_TEST_CNFG_MODE_MSK               (0x3u << MUROSYNC_LNK_TEST_CNFG_MODE_OFS)

	#define MUROSYNC_LNK_TEST_MODE_FIXED                  0
	#define MUROSYNC_LNK_TEST_MODE_TOGGLE                 1
	#define MUROSYNC_LNK_TEST_MODE_COUNTER                2

	#define MUROSYNC_LNK_TEST_CNFG_CH_MASK_OFS            4
	#define MUROSYNC_LNK_TEST_CNFG_CH_MASK_MSK            (0xFu << MUROSYNC_LNK_TEST_CNFG_CH_MASK_OFS)

	#define MUROSYNC_LNK_TEST_CNFG_RX_POL_MASK_OFS        8
	#define MUROSYNC_LNK_TEST_CNFG_RX_POL_MASK_MSK        (0xFu << MUROSYNC_LNK_TEST_CNFG_RX_POL_MASK_OFS)

	#define MUROSYNC_LNK_TEST_CNFG_TX_POL_MASK_OFS        12
	#define MUROSYNC_LNK_TEST_CNFG_TX_POL_MASK_MSK        (0xFu << MUROSYNC_LNK_TEST_CNFG_TX_POL_MASK_OFS)

////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////  LNK_TEST_PATT  ///////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////

#define MUROSYNC_LNK_TEST_PATT                      (0x024)  // Fixed Test Pattern

	/*
	Type        :   R/W
	Description :   32-bit fixed pattern used in MODE 0.
	*/

	#define MUROSYNC_LNK_TEST_PATT_MSK                    (0xFFFFFFFFu)

////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////  LNK_RX_ERR_CNT  ///////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////

#define MUROSYNC_LNK_RX_ERR_CNT                     (0x028)  // RX Error Counter

	/*
	Type        :   R
	Description :   Total detected errors (CDC-synchronized).
	*/

	#define MUROSYNC_LNK_RX_ERR_CNT_MSK                   (0xFFFFFFFFu)

////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////  LNK_RX_WRD_CNT  ///////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////

#define MUROSYNC_LNK_RX_WRD_CNT                     (0x02C)  // RX Word Counter

	/*
	Type        :   R
	Description :   Total words received during test (CDC-synchronized).
	*/

	#define MUROSYNC_LNK_RX_WRD_CNT_MSK                   (0xFFFFFFFFu)

////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////  LINK TEST DIAGNOSTIC REGISTERS  //////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////

#define MUROSYNC_LNK_DIAG_STATUS                (0x030)  // RO: FSM state + alignment

	// [3:0]   FSM_STATE:         0=IDLE 1=CAPTURE_CFG 2=WAIT_ALIGN 3=SEARCH 4=LOCKED
	// [7:4]   RX_ALIGNED:        rxbyteisaligned per channel [CH3..CH0] (current)
	// [11:8]  RX_ALIGNED_SEEN:   sticky rxbyteisaligned per channel (latched OR over test run)
	// [15:12] RX_CHARISK:        current cycle K-symbol per channel
	// [16]    CHECKER_LOCKED:    1 = FSM in ST_LOCKED

	#define MUROSYNC_LNK_DIAG_FSM_STATE_OFS       0
	#define MUROSYNC_LNK_DIAG_FSM_STATE_MSK       (0xFu << MUROSYNC_LNK_DIAG_FSM_STATE_OFS)

	#define MUROSYNC_LNK_DIAG_RX_ALIGNED_OFS      4
	#define MUROSYNC_LNK_DIAG_RX_ALIGNED_MSK      (0xFu << MUROSYNC_LNK_DIAG_RX_ALIGNED_OFS)

	#define MUROSYNC_LNK_DIAG_RX_ALIGNED_SEEN_OFS 8
	#define MUROSYNC_LNK_DIAG_RX_ALIGNED_SEEN_MSK (0xFu << MUROSYNC_LNK_DIAG_RX_ALIGNED_SEEN_OFS)

	#define MUROSYNC_LNK_DIAG_RX_CHARISK_OFS      12
	#define MUROSYNC_LNK_DIAG_RX_CHARISK_MSK      (0xFu << MUROSYNC_LNK_DIAG_RX_CHARISK_OFS)

	#define MUROSYNC_LNK_DIAG_LOCKED_OFS          16
	#define MUROSYNC_LNK_DIAG_LOCKED_MSK          (0x1u << MUROSYNC_LNK_DIAG_LOCKED_OFS)

	// FSM state values  must match RTL localparam in murosync_serdes_link_test.sv
	#define MUROSYNC_LNK_FSM_IDLE                 0u
	#define MUROSYNC_LNK_FSM_CAPTURE_CFG          1u
	#define MUROSYNC_LNK_FSM_WAIT_ALIGN           2u
	#define MUROSYNC_LNK_FSM_SEARCH               3u
	#define MUROSYNC_LNK_FSM_LOCKED               4u

#define MUROSYNC_LNK_DIAG_RX_LO                 (0x034)  // RO: last received word [31:0]
#define MUROSYNC_LNK_DIAG_RX_HI                 (0x038)  // RO: last received word [63:32]
#define MUROSYNC_LNK_DIAG_EXP_LO                (0x03C)  // RO: current expected word [31:0]
#define MUROSYNC_LNK_DIAG_EXP_HI                (0x040)  // RO: current expected word [63:32]



//========================================================================================
// TX Diagnostics
//========================================================================================

#define MUROSYNC_LNK_DIAG_TX_DATA_LO                (0x044)

	/*
	Type        :   RO
	Description :   Last transmitted word [31:0]
	*/

#define MUROSYNC_LNK_DIAG_TX_DATA_HI                (0x048)

	/*
	Type        :   RO
	Description :   Last transmitted word [63:32]
	*/

#define MUROSYNC_LNK_DIAG_TX_COUNTERS_LO            (0x04C)

	/*
	Type        :   RO
	Description :   TX counters for Channels 0 and 1
	                [15:0] CH0_COUNT: Counter for CH0
	                [31:16] CH1_COUNT: Counter for CH1
	*/

	#define MUROSYNC_LNK_DIAG_TX_CH0_COUNT_OFS          0
	#define MUROSYNC_LNK_DIAG_TX_CH0_COUNT_MSK          (0xFFFFu << MUROSYNC_LNK_DIAG_TX_CH0_COUNT_OFS)

	#define MUROSYNC_LNK_DIAG_TX_CH1_COUNT_OFS          16
	#define MUROSYNC_LNK_DIAG_TX_CH1_COUNT_MSK          (0xFFFFu << MUROSYNC_LNK_DIAG_TX_CH1_COUNT_OFS)

#define MUROSYNC_LNK_DIAG_TX_COUNTERS_HI            (0x050)

	/*
	Type        :   RO
	Description :   TX counters for Channels 2 and 3
	                [15:0] CH2_COUNT: Counter for CH2
	                [31:16] CH3_COUNT: Counter for CH3
	*/

	#define MUROSYNC_LNK_DIAG_TX_CH2_COUNT_OFS          0
	#define MUROSYNC_LNK_DIAG_TX_CH2_COUNT_MSK          (0xFFFFu << MUROSYNC_LNK_DIAG_TX_CH2_COUNT_OFS)

	#define MUROSYNC_LNK_DIAG_TX_CH3_COUNT_OFS          16
	#define MUROSYNC_LNK_DIAG_TX_CH3_COUNT_MSK          (0xFFFFu << MUROSYNC_LNK_DIAG_TX_CH3_COUNT_OFS)

#define MUROSYNC_LNK_DIAG_TX_STATUS                 (0x054)

	/*
	Type        :   RO
	Description :   TX Comma status
	                [3:0] COMMA_ACTIVE: Active comma transmission per channel
	                [15:4] COMMA_COUNT: Total commas transmitted
	*/

	#define MUROSYNC_LNK_DIAG_TX_COMMA_ACTIVE_OFS       0
	#define MUROSYNC_LNK_DIAG_TX_COMMA_ACTIVE_MSK       (0xFu << MUROSYNC_LNK_DIAG_TX_COMMA_ACTIVE_OFS)

	#define MUROSYNC_LNK_DIAG_TX_COMMA_COUNT_OFS        4
	#define MUROSYNC_LNK_DIAG_TX_COMMA_COUNT_MSK        (0xFFFu << MUROSYNC_LNK_DIAG_TX_COMMA_COUNT_OFS)


//========================================================================================
// GT DEBUG REGISTERS
//========================================================================================
// Based on hardware implementation in murosync_serdes_array_axi_ctrl.sv
// Registers 0x16-0x1B (word offsets) = 0x58-0x6C (byte offsets)

#define MUROSYNC_GT_DEBUG_COMMA_ALIGN_REG           (0x058)

	/*
	Type        :   RO
	Description :   GT comma detection and byte alignment status
	                [3:0] RXCOMMADET: Comma detected per channel [CH3..CH0]
	                [7:4] RXBYTEISALIGNED: Byte alignment status per channel [CH3..CH0]  
	                [11:8] RXBYTEREALIGN: Realignment events per channel [CH3..CH0]
	*/

	#define MUROSYNC_GT_DEBUG_RXCOMMADET_OFS            0
	#define MUROSYNC_GT_DEBUG_RXCOMMADET_MSK            (0xFu << MUROSYNC_GT_DEBUG_RXCOMMADET_OFS)

	#define MUROSYNC_GT_DEBUG_RXBYTEISALIGNED_OFS       4  
	#define MUROSYNC_GT_DEBUG_RXBYTEISALIGNED_MSK       (0xFu << MUROSYNC_GT_DEBUG_RXBYTEISALIGNED_OFS)

	#define MUROSYNC_GT_DEBUG_RXBYTEREALIGN_OFS         8
	#define MUROSYNC_GT_DEBUG_RXBYTEREALIGN_MSK         (0xFu << MUROSYNC_GT_DEBUG_RXBYTEREALIGN_OFS)

#define MUROSYNC_GT_DEBUG_RXBUF_STATUS_REG          (0x05C)

	/*
	Type        :   RO  
	Description :   RX buffer status per channel
	                [2:0] CH0_RXBUF: RX buffer status for channel 0
	                [5:3] CH1_RXBUF: RX buffer status for channel 1
	                [8:6] CH2_RXBUF: RX buffer status for channel 2
	                [11:9] CH3_RXBUF: RX buffer status for channel 3
	*/

	#define MUROSYNC_GT_DEBUG_RXBUF_CH0_OFS             0
	#define MUROSYNC_GT_DEBUG_RXBUF_CH0_MSK             (0x7u << MUROSYNC_GT_DEBUG_RXBUF_CH0_OFS)

	#define MUROSYNC_GT_DEBUG_RXBUF_CH1_OFS             3
	#define MUROSYNC_GT_DEBUG_RXBUF_CH1_MSK             (0x7u << MUROSYNC_GT_DEBUG_RXBUF_CH1_OFS)

	#define MUROSYNC_GT_DEBUG_RXBUF_CH2_OFS             6
	#define MUROSYNC_GT_DEBUG_RXBUF_CH2_MSK             (0x7u << MUROSYNC_GT_DEBUG_RXBUF_CH2_OFS)

	#define MUROSYNC_GT_DEBUG_RXBUF_CH3_OFS             9  
	#define MUROSYNC_GT_DEBUG_RXBUF_CH3_MSK             (0x7u << MUROSYNC_GT_DEBUG_RXBUF_CH3_OFS)

#define MUROSYNC_GT_DEBUG_TXBUF_STATUS_REG          (0x060)

	/*
	Type        :   RO  
	Description :   TX buffer status per channel
	                [1:0] CH0_TXBUF: TX buffer status for channel 0
	                [3:2] CH1_TXBUF: TX buffer status for channel 1
	                [5:4] CH2_TXBUF: TX buffer status for channel 2
	                [7:6] CH3_TXBUF: TX buffer status for channel 3
	*/

	#define MUROSYNC_GT_DEBUG_TXBUF_CH0_OFS             0
	#define MUROSYNC_GT_DEBUG_TXBUF_CH0_MSK             (0x3u << MUROSYNC_GT_DEBUG_TXBUF_CH0_OFS)

	#define MUROSYNC_GT_DEBUG_TXBUF_CH1_OFS             2
	#define MUROSYNC_GT_DEBUG_TXBUF_CH1_MSK             (0x3u << MUROSYNC_GT_DEBUG_TXBUF_CH1_OFS)

	#define MUROSYNC_GT_DEBUG_TXBUF_CH2_OFS             4
	#define MUROSYNC_GT_DEBUG_TXBUF_CH2_MSK             (0x3u << MUROSYNC_GT_DEBUG_TXBUF_CH2_OFS)

	#define MUROSYNC_GT_DEBUG_TXBUF_CH3_OFS             6  
	#define MUROSYNC_GT_DEBUG_TXBUF_CH3_MSK             (0x3u << MUROSYNC_GT_DEBUG_TXBUF_CH3_OFS)


#define MUROSYNC_GT_DEBUG_SYNC_STATUS_REG           (0x064)

	/*
	Type        :   RO
	Description :   Synchronization and phase alignment status
	                [3:0] RXSYNCDONE: RX sync completion per channel [CH3..CH0]
	                [7:4] RXPHALIGNDONE: RX phase alignment done per channel [CH3..CH0]
	*/

	#define MUROSYNC_GT_DEBUG_RXSYNCDONE_OFS            0
	#define MUROSYNC_GT_DEBUG_RXSYNCDONE_MSK            (0xFu << MUROSYNC_GT_DEBUG_RXSYNCDONE_OFS)

	#define MUROSYNC_GT_DEBUG_RXPHALIGNDONE_OFS         4
	#define MUROSYNC_GT_DEBUG_RXPHALIGNDONE_MSK         (0xFu << MUROSYNC_GT_DEBUG_RXPHALIGNDONE_OFS)

#define MUROSYNC_GT_DEBUG_SIGNAL_QUAL_REG           (0x068)

	/*
	Type        :   RO
	Description :   Signal Quality (Eyescan error)
	                [3:0] EYESCANDATAERROR: Eyescan error per channel [CH3..CH0]
	*/

	#define MUROSYNC_GT_DEBUG_EYESCANDATAERROR_OFS      0
	#define MUROSYNC_GT_DEBUG_EYESCANDATAERROR_MSK      (0xFu << MUROSYNC_GT_DEBUG_EYESCANDATAERROR_OFS)

#define MUROSYNC_GT_DEBUG_RESET_STATUS_REG          (0x06C)

	/*
	Type        :   RO
	Description :   Reset Completion Status
	                [3:0] RXRESETDONE: RX reset done per channel [CH3..CH0]
	                [7:4] TXRESETDONE: TX reset done per channel [CH3..CH0]
	                [11:8] RXPMARESETDONE: RX PMA reset done per channel [CH3..CH0]
	                [15:12] TXPMARESETDONE: TX PMA reset done per channel [CH3..CH0]
	*/

	#define MUROSYNC_GT_DEBUG_RXRESETDONE_OFS           0
	#define MUROSYNC_GT_DEBUG_RXRESETDONE_MSK           (0xFu << MUROSYNC_GT_DEBUG_RXRESETDONE_OFS)

	#define MUROSYNC_GT_DEBUG_TXRESETDONE_OFS           4
	#define MUROSYNC_GT_DEBUG_TXRESETDONE_MSK           (0xFu << MUROSYNC_GT_DEBUG_TXRESETDONE_OFS)

	#define MUROSYNC_GT_DEBUG_RXPMARESETDONE_OFS        8
	#define MUROSYNC_GT_DEBUG_RXPMARESETDONE_MSK        (0xFu << MUROSYNC_GT_DEBUG_RXPMARESETDONE_OFS)

	#define MUROSYNC_GT_DEBUG_TXPMARESETDONE_OFS        12
	#define MUROSYNC_GT_DEBUG_TXPMARESETDONE_MSK        (0xFu << MUROSYNC_GT_DEBUG_TXPMARESETDONE_OFS)


/* ========================================================================
 * LNK_DIAG_STATUS2 — Tier 1 + Tier 2 sticky diagnostic flags (offset 0x070)
 *
 * Sticky values held until next test start (capture_cfg) or reset.
 * Read AFTER link_test_stop() for post-mortem diagnostic.
 *
 * Layout:
 *   [0]     ever_locked            (Tier 1) 1 = FSM reached LOCKED at least once
 *   [3:1]   reserved
 *   [7:4]   last_fsm_state         (Tier 1) last non-IDLE state before drop
 *   [15:8]  reserved
 *   [16]    rx_data_at_lock_valid  (Tier 2) 1 = at_lock snapshot was taken
 *   [17]    first_err_valid        (Tier 2) 1 = at_first_err snapshot was taken
 *   [31:18] reserved
 * ======================================================================== */
#define MUROSYNC_LNK_DIAG_STATUS2_REG            (0x070)

    /* [0] EVER_LOCKED: 1 = FSM reached LOCKED at least once during this test run */
    #define MUROSYNC_LNK_DIAG_EVER_LOCKED_OFS        0
    #define MUROSYNC_LNK_DIAG_EVER_LOCKED_MSK        (0x1u << MUROSYNC_LNK_DIAG_EVER_LOCKED_OFS)

    /* [7:4] LAST_FSM_STATE: last non-IDLE state before FSM dropped to IDLE on rx_enable=0 */
    #define MUROSYNC_LNK_DIAG_LAST_FSM_STATE_OFS     4
    #define MUROSYNC_LNK_DIAG_LAST_FSM_STATE_MSK     (0xFu << MUROSYNC_LNK_DIAG_LAST_FSM_STATE_OFS)

    /* [16] RX_DATA_AT_LOCK_VALID: 1 = at_lock snapshot was taken */
    #define MUROSYNC_LNK_DIAG_RX_DATA_AT_LOCK_VALID_OFS  16
    #define MUROSYNC_LNK_DIAG_RX_DATA_AT_LOCK_VALID_MSK  (0x1u << MUROSYNC_LNK_DIAG_RX_DATA_AT_LOCK_VALID_OFS)

    /* [17] FIRST_ERR_VALID: 1 = at_first_err snapshot was taken */
    #define MUROSYNC_LNK_DIAG_FIRST_ERR_VALID_OFS     17
    #define MUROSYNC_LNK_DIAG_FIRST_ERR_VALID_MSK     (0x1u << MUROSYNC_LNK_DIAG_FIRST_ERR_VALID_OFS)


/* ========================================================================
 * Tier 2 Link Test Snapshots and Counters (offsets 0x080-0x094)
 *
 * All cleared on rx_reset_pulse or on test start (capture_cfg).
 * Snapshots are frozen after first event (latch-once semantics).
 * Validity indicated by LNK_DIAG_STATUS2 bits [16] and [17].
 * ======================================================================== */

/* TIME_TO_LOCK — cycles from first WAIT_ALIGN entry to first LOCKED entry.
 * Frozen on first LOCKED. Metric of link convergence speed.
 * At 312.5 MHz, 1 cycle = 3.2 ns. */
#define MUROSYNC_LNK_TIME_TO_LOCK_REG            (0x080)
    #define MUROSYNC_LNK_TIME_TO_LOCK_MSK            (0xFFFFFFFFu)

/* LOCKED_CYCLE_COUNT — total cycles spent in RX_ST_LOCKED.
 * Includes K-symbol cycles. Metric of link stability. */
#define MUROSYNC_LNK_LOCKED_CYCLE_COUNT_REG      (0x084)
    #define MUROSYNC_LNK_LOCKED_CYCLE_COUNT_MSK      (0xFFFFFFFFu)

/* RX_DATA_AT_LOCK — snapshot of rx_data_corrected at first LOCKED entry.
 * Latched once. Verify lock acquired on expected pattern.
 * Validity: LNK_DIAG_STATUS2 [16]. */
#define MUROSYNC_LNK_RX_DATA_AT_LOCK_LO_REG      (0x088)  /* rx_data_at_lock[31:0] */
#define MUROSYNC_LNK_RX_DATA_AT_LOCK_HI_REG      (0x08C)  /* rx_data_at_lock[63:32] */

/* RX_DATA_AT_FIRST_ERR — snapshot of rx_data_corrected at first error.
 * Latched once on first err_cnt_inc.
 * Validity: LNK_DIAG_STATUS2 [17]. */
#define MUROSYNC_LNK_RX_DATA_AT_FIRST_ERR_LO_REG (0x090)
#define MUROSYNC_LNK_RX_DATA_AT_FIRST_ERR_HI_REG (0x094)

/* EXP_DATA_AT_FIRST_ERR — expected pattern snapshot at first error in LOCKED.
 * Paired with RX_DATA_AT_FIRST_ERR. Use both to distinguish bit-flip from
 * full decorrelation: bit-flip = small XOR popcount, decorrelation = large XOR.
 * Validity: LNK_DIAG_STATUS2 [17] (same as RX_DATA_AT_FIRST_ERR — captured together). */
#define MUROSYNC_LNK_EXP_DATA_AT_FIRST_ERR_LO_REG (0x0B8)
#define MUROSYNC_LNK_EXP_DATA_AT_FIRST_ERR_HI_REG (0x0BC)


/* ========================================================================
 * Tier 2 Per-Channel Error Counters (offsets 0x098-0x0A4)
 *
 * Each counter is 16 bits in the lower half of its 32-bit register.
 * Counters increment in LOCKED state on non-K-symbol cycles when this
 * channel's 16-bit slice doesn't match expected_rx.
 * Global err_cnt is unchanged for backwards compatibility.
 * On FMC loopback (symmetric channels) expect all = 0.
 * ======================================================================== */
#define MUROSYNC_LNK_ERR_CNT_CH0_REG             (0x098)
    #define MUROSYNC_LNK_ERR_CNT_CH_MSK              (0xFFFFu)   /* shared mask for all channels */
#define MUROSYNC_LNK_ERR_CNT_CH1_REG             (0x09C)
#define MUROSYNC_LNK_ERR_CNT_CH2_REG             (0x0A0)
#define MUROSYNC_LNK_ERR_CNT_CH3_REG             (0x0A4)


/* ========================================================================
 * Tier 2 GT Sticky Event Counters (offsets 0x0A8-0x0B4)
 *
 * RXBYTEREALIGN — counts GT byte-alignment re-acquisition events.
 *   Frequent counts = channel instability.
 * EYESCANDATAERROR — counts GT eye scan error events.
 *   Direct signal quality indicator.
 *
 * Layout per register pair (LO/HI):
 *   LO  [15:0]  CH0,   LO  [31:16] CH1
 *   HI  [15:0]  CH2,   HI  [31:16] CH3
 *
 * Reset: tied to gtwiz_reset_all_in (full GT reset clears all counters).
 * ======================================================================== */
#define MUROSYNC_GT_RXBYTEREALIGN_CNT_LO_REG     (0x0A8)
#define MUROSYNC_GT_RXBYTEREALIGN_CNT_HI_REG     (0x0AC)
#define MUROSYNC_GT_EYESCANDATAERROR_CNT_LO_REG  (0x0B0)
#define MUROSYNC_GT_EYESCANDATAERROR_CNT_HI_REG  (0x0B4)

    /* Shared masks for extracting per-channel 16-bit counters from packed registers */
    #define MUROSYNC_GT_STICKY_CNT_CH_LO_OFS         0
    #define MUROSYNC_GT_STICKY_CNT_CH_LO_MSK         (0xFFFFu << MUROSYNC_GT_STICKY_CNT_CH_LO_OFS)
    #define MUROSYNC_GT_STICKY_CNT_CH_HI_OFS         16
    #define MUROSYNC_GT_STICKY_CNT_CH_HI_MSK         (0xFFFFu << MUROSYNC_GT_STICKY_CNT_CH_HI_OFS)


/* ========================================================================
 * IP_INFO — Build identity register (offset 0x074)
 *
 * Read-only. Reflects build-time constants of the loaded bitstream:
 *   - MODE (IS_SLAVE / IS_MASTER bits)
 *   - IP_VERSION_MAJOR / IP_VERSION_MINOR (semantic + build counter)
 *   - NUM_CHANNELS (fixed at 4 for current dev board)
 *
 * Layout:
 *   [0]      IS_SLAVE             1 = SLAVE mode active in this bitstream
 *   [1]      IS_MASTER            1 = MASTER mode active in this bitstream
 *   [3:2]    reserved
 *   [7:4]    IP_VERSION_MAJOR     (4 bits, max 15)
 *   [23:8]   IP_VERSION_MINOR     (16 bits, max 65535)
 *   [27:24]  NUM_CHANNELS         (4 bits, max 15)
 *   [31:28]  reserved
 *
 * Versioning policy:
 *   MAJOR — bumped manually in RTL on breaking changes.
 *   MINOR — auto-incremented by update_ip_ports.tcl on every re-package.
 *
 * Traceability: version number in this register is in sync with
 *   <spirit:version> in component.xml (under git). To reproduce sources
 *   of a given bitstream, find the commit where component.xml has the
 *   matching version.
 *
 * Slot 0x074 was previously reserved (see top-of-file register map summary).
 * ======================================================================== */
#define MUROSYNC_IP_INFO_REG                    (0x074)

    #define MUROSYNC_IP_INFO_IS_SLAVE_OFS               0
    #define MUROSYNC_IP_INFO_IS_SLAVE_MSK               (0x1u << MUROSYNC_IP_INFO_IS_SLAVE_OFS)

    #define MUROSYNC_IP_INFO_IS_MASTER_OFS              1
    #define MUROSYNC_IP_INFO_IS_MASTER_MSK              (0x1u << MUROSYNC_IP_INFO_IS_MASTER_OFS)

    #define MUROSYNC_IP_INFO_VERSION_MAJOR_OFS          4
    #define MUROSYNC_IP_INFO_VERSION_MAJOR_MSK          (0xFu << MUROSYNC_IP_INFO_VERSION_MAJOR_OFS)

    #define MUROSYNC_IP_INFO_VERSION_MINOR_OFS          8
    #define MUROSYNC_IP_INFO_VERSION_MINOR_MSK          (0xFFFFu << MUROSYNC_IP_INFO_VERSION_MINOR_OFS)

    #define MUROSYNC_IP_INFO_NUM_CHANNELS_OFS           24
    #define MUROSYNC_IP_INFO_NUM_CHANNELS_MSK           (0xFu << MUROSYNC_IP_INFO_NUM_CHANNELS_OFS)


#endif // MUROSYNC_SERDES_ARRAY_REGS_H

