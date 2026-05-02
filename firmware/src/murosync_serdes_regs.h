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
	Type        :   R/W[cite: 4]
	Description :   [1:0] MODE_SEL: 0=Fixed, 1=Counter, 2=PRBS
	*/

	#define MUROSYNC_LNK_TEST_CNFG_MODE_OFS               0
	#define MUROSYNC_LNK_TEST_CNFG_MODE_MSK               (0x3u << MUROSYNC_LNK_TEST_CNFG_MODE_OFS)

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

#endif // MUROSYNC_SERDES_ARRAY_REGS_H
