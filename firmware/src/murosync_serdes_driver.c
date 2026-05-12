/******************************************************************************
 *  Project    : MuroSync
 *  File       : murosync_serdes_driver.c
 *  Created    : 2026-01-02
 *  Author     : Mikhail Vasilev
 *
 *  Description:
 *  Low-level driver for the MuroSync SERDES subsystem.
 *
 *  This module provides register-level access and control functions for
 *  the MuroSync optical SERDES array, including:
 *    - AXI register read/write and masked modification
 *    - SERDES reset and bring-up sequencing
 *    - Loopback configuration
 *    - Link status monitoring and polling
 *    - Debug and self-test utilities for AXI and SERDES validation
 *
 *  The driver is intended for FPGA-based bring-up, diagnostics, and
 *  experimental validation of high-precision optical timing links.
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

#include "murosync_serdes_driver.h"

/************************* Register access ******************************/
int murosync_serdes_reg_rd(unsigned int reg_ofs, unsigned int *data)
{
    if (!data) return XST_FAILURE;

    *data = (XIo_In32(MUROSYNC_SERDES_ARRAY_BASEADDR + reg_ofs) & 0xFFFFFFFF);
    return XST_SUCCESS;
}

int murosync_serdes_reg_wr(unsigned int reg_ofs, unsigned int data)
{
    XIo_Out32(MUROSYNC_SERDES_ARRAY_BASEADDR + reg_ofs, data);
    return XST_SUCCESS;
}

int murosync_serdes_reg_modify(unsigned int reg_ofs, unsigned int data, unsigned int mask)
{
    unsigned int val;
    if (murosync_serdes_reg_rd(reg_ofs, &val) != XST_SUCCESS) return XST_FAILURE;

    val = (val & ~mask) | (data & mask);
    return murosync_serdes_reg_wr(reg_ofs, val);
}

void murosync_serdes_dump_registers(unsigned int start_ofs, unsigned int end_ofs)
{
    for (unsigned int ofs = start_ofs; ofs <= end_ofs; ofs += 4)
    {
        unsigned int data;
        murosync_serdes_reg_rd(ofs, &data);
        xil_printf("\t\t\t[0x%04X] : 0x%08X\r\n", ofs, data);
    }
}
/************************************************************************/

/*************************** Commands ***********************************/
int murosync_serdes_set_loopback(unsigned char loopback)
{
    // LOOPBACK is a level [2:0]
    unsigned int lb_ctrl = ((unsigned int)loopback << MUROSYNC_SERDES_LOOPBACK_CTRL_OFS) & MUROSYNC_SERDES_LOOPBACK_CTRL_MSK;
    return murosync_serdes_reg_modify(MUROSYNC_SERDES_LOOPBACK, lb_ctrl, MUROSYNC_SERDES_LOOPBACK_CTRL_MSK);
}

int murosync_serdes_w1p_pulse(unsigned int bit_mask)
{
    int rc;

    rc = murosync_serdes_reg_wr(MUROSYNC_SERDES_CTRL, bit_mask);
    if (rc != XST_SUCCESS) return rc;

    unsigned int dummy;
    (void)murosync_serdes_reg_rd(MUROSYNC_SERDES_CTRL, &dummy);

    rc = murosync_serdes_reg_wr(MUROSYNC_SERDES_CTRL, 0x00000000u);
    return rc;
}

int murosync_serdes_pulse_link_latch_reset(void) { return murosync_serdes_w1p_pulse(MUROSYNC_SERDES_CTRL_LINK_LATCH_RESET_MSK); }
int murosync_serdes_pulse_gt_reset_all(void) { return murosync_serdes_w1p_pulse(MUROSYNC_SERDES_CTRL_GT_RESET_ALL_MSK); }

int murosync_serdes_reset_sequence(void)
{
    xil_printf("\tMUROSYNC SERDES | Reset sequence\r\n");
    xil_printf("\t\tPulse LINK_LATCH_RESET...\r\n");
    if (murosync_serdes_pulse_link_latch_reset() != XST_SUCCESS) {
        xil_printf("\t\tERROR: LINK_LATCH_RESET pulse failed\r\n");
        return XST_FAILURE;
    }

    xil_printf("\t\tPulse GT_RESET_ALL...\r\n");
    if (murosync_serdes_pulse_gt_reset_all() != XST_SUCCESS) {
        xil_printf("\t\tERROR: GT_RESET_ALL pulse failed\r\n");
        return XST_FAILURE;
    }

    return XST_SUCCESS;
}
/************************************************************************/

/************************* Status helpers *******************************/
int murosync_serdes_get_status(unsigned int *stat)
{
    return murosync_serdes_reg_rd(MUROSYNC_SERDES_STATUS, stat);
}

int murosync_serdes_is_link_up(void)
{
    unsigned int stat;
    if (murosync_serdes_get_status(&stat) != XST_SUCCESS)
        return XST_FAILURE;

    return (stat & MUROSYNC_SERDES_STATUS_LINK_UP_MSK)
           ? MUROSYNC_GT_LINK_UP
           : MUROSYNC_GT_LINK_DOWN;
}

int murosync_serdes_wait_link_up(int timeout_usec)
{
    int timeout = 0;
    const int poll = MUROSYNC_SERDES_POLL_INTERVAL_USEC;
    const int max  = (timeout_usec <= 0)
        ? (MUROSYNC_SERDES_TIMEOUT_USEC / poll)
        : (timeout_usec / poll);

    while (1)
    {
        int link = murosync_serdes_is_link_up();

        if (link == XST_FAILURE)         return XST_FAILURE;
        if (link == MUROSYNC_GT_LINK_UP) return XST_SUCCESS;
        if (++timeout >= max)            return XST_FAILURE;

        usleep(poll);
    }
}

void murosync_serdes_print_status(void)
{
    unsigned int stat = 0;
    if (murosync_serdes_get_status(&stat) != XST_SUCCESS) {
        xil_printf("\tMUROSYNC SERDES | STATUS read ERROR\r\n");
        return;
    }

    unsigned int link_up   = (stat & MUROSYNC_SERDES_STATUS_LINK_UP_MSK) ? 1 : 0;
    unsigned int link_lat  = (stat & MUROSYNC_SERDES_STATUS_LINK_DOWN_LAT_MSK) ? 1 : 0;

    unsigned int pll_lock  = (unsigned)((stat & MUROSYNC_SERDES_STATUS_PLL_LOCK_MSK) >> MUROSYNC_SERDES_STATUS_PLL_LOCK_OFS);
    unsigned int pwr_good  = (unsigned)((stat & MUROSYNC_SERDES_STATUS_GTPOWERGOOD_MSK) >> MUROSYNC_SERDES_STATUS_GTPOWERGOOD_OFS);
    unsigned int tx_done   = (unsigned)((stat & MUROSYNC_SERDES_STATUS_TXPMARESETDONE_MSK) >> MUROSYNC_SERDES_STATUS_TXPMARESETDONE_OFS);
    unsigned int rx_done   = (unsigned)((stat & MUROSYNC_SERDES_STATUS_RXPMARESETDONE_MSK) >> MUROSYNC_SERDES_STATUS_RXPMARESETDONE_OFS);

    xil_printf("\tMUROSYNC SERDES | STATUS=0x%08X\r\n", stat);
    xil_printf("\t\tLINK_UP            : %u\r\n", link_up);
    xil_printf("\t\tLINK_DOWN_LATCHED  : %u\r\n", link_lat);
    xil_printf("\t\tPLL_LOCK_VEC       : 0x%X\r\n", pll_lock);
    xil_printf("\t\tGTPOWERGOOD_VEC    : 0x%X\r\n", pwr_good);
    xil_printf("\t\tTXPMARESETDONE_VEC : 0x%X\r\n", tx_done);
    xil_printf("\t\tRXPMARESETDONE_VEC : 0x%X\r\n", rx_done);
}
/************************************************************************/

/************************* Debug helpers ********************************/
int murosync_serdes_get_dbg64(unsigned long long *dbg)
{
    if (!dbg)
        return XST_FAILURE;

    unsigned int lo, hi;
    if (murosync_serdes_reg_rd(MUROSYNC_SERDES_DBG_LO, &lo) != XST_SUCCESS)
        return XST_FAILURE;
    if (murosync_serdes_reg_rd(MUROSYNC_SERDES_DBG_HI, &hi) != XST_SUCCESS)
        return XST_FAILURE;

    *dbg = ((unsigned long long)hi << 32) | (unsigned long long)lo;
    return XST_SUCCESS;
}

void murosync_serdes_print_dbg(void)
{
    unsigned long long dbg = 0;
    if (murosync_serdes_get_dbg64(&dbg) == XST_SUCCESS)
        xil_printf("\tMUROSYNC SERDES | DBG=0x%08X%08X\r\n", (u32)(dbg >> 32), (u32)dbg);
}

int murosync_serdes_selftest_const(void)
{
    unsigned int rd_reg = 0;

    xil_printf("\tMUROSYNC SERDES | Checking RD-access over AXI\r\n");
    if (murosync_serdes_reg_rd(MUROSYNC_SERDES_TEST_CONST, &rd_reg) != XST_SUCCESS)
    {
        xil_printf("\t\tAXI ERROR: TEST_CONST read failed!\r\n");
        return XST_FAILURE;
    }

    if (rd_reg != MUROSYNC_SERDES_TEST_MAGIC)
    {
        xil_printf("\t\tAXI ERROR: TEST_CONST mismatch!\r\n");
        xil_printf("\t\t\tRead : 0x%08X\r\n", rd_reg);
        xil_printf("\t\t\tExp  : 0x%08X\r\n", MUROSYNC_SERDES_TEST_MAGIC);
        return XST_FAILURE;
    }

    xil_printf("\t\tAXI OK: TEST_CONST = 0x%08X\r\n", rd_reg);
    return XST_SUCCESS;
}

int murosync_serdes_scratch_wr_rd_check(unsigned int pattern, const char *tag)
{
    unsigned int rd_reg = 0;

    xil_printf("\t\tTEST_SCRATCH %s pattern 0x%08X\r\n", tag, pattern);

    if (murosync_serdes_reg_wr(MUROSYNC_SERDES_TEST_SCRATCH, pattern) != XST_SUCCESS)
    {
        xil_printf("\t\t\tAXI ERROR: write failed\r\n");
        return XST_FAILURE;
    }

    if (murosync_serdes_reg_rd(MUROSYNC_SERDES_TEST_SCRATCH, &rd_reg) != XST_SUCCESS)
    {
        xil_printf("\t\t\tAXI ERROR: read failed\r\n");
        return XST_FAILURE;
    }

    if (rd_reg != pattern)
    {
        xil_printf("\t\t\tAXI ERROR: mismatch\r\n");
        xil_printf("\t\t\t\tRead : 0x%08X\r\n", rd_reg);
        xil_printf("\t\t\t\tExp  : 0x%08X\r\n", pattern);
        return XST_FAILURE;
    }

    return XST_SUCCESS;
}

int murosync_serdes_selftest_scratch(void)
{
    xil_printf("\tMUROSYNC SERDES | Checking WR/RD-access over AXI\r\n");

    if (murosync_serdes_scratch_wr_rd_check(0xA5A55A5A, "PAT1") != XST_SUCCESS)
        return XST_FAILURE;

    if (murosync_serdes_scratch_wr_rd_check(0x5AA5A55A, "PAT2") != XST_SUCCESS)
        return XST_FAILURE;

    (void)murosync_serdes_reg_wr(MUROSYNC_SERDES_TEST_SCRATCH, 0x00000000);

    xil_printf("\t\tAXI OK: TEST_SCRATCH write/readback OK\r\n");
    return XST_SUCCESS;
}
/************************************************************************/

/*************************** BTRING-UP **********************************/
int murosync_serdes_bring_up(unsigned char loopback, int timeout_usec)
{
    unsigned int reg = 0;

    xil_printf("\r\nAXI MUROSYNC SERDES BTING-UP\r\n");

    if (murosync_serdes_selftest_const()   != XST_SUCCESS) return XST_FAILURE; // AXI RD test
    if (murosync_serdes_selftest_scratch() != XST_SUCCESS) return XST_FAILURE; // AXI WR/RD test
    if (murosync_serdes_reset_sequence()   != XST_SUCCESS) return XST_FAILURE;

    xil_printf("\tMUROSYNC SERDES | Set loopback = %d\r\n", loopback);
    if (murosync_serdes_set_loopback(loopback) != XST_SUCCESS) {
        xil_printf("\t\tERROR: set loopback failed\r\n");
        return XST_FAILURE;
    }

    xil_printf("\tMUROSYNC SERDES | Waiting link up...\r\n");
    if (murosync_serdes_wait_link_up(timeout_usec) != XST_SUCCESS)
    {
        (void)murosync_serdes_get_status(&reg);
        xil_printf("\t\tERROR: link up timeout, STATUS=0x%08X\r\n", reg);
        xil_printf("\t\tLINK_UP mask=0x%08X (STATUS&mask=0x%08X)\r\n",
                   (unsigned)MUROSYNC_SERDES_STATUS_LINK_UP_MSK,
                   (unsigned)(reg & MUROSYNC_SERDES_STATUS_LINK_UP_MSK));

        murosync_serdes_print_dbg();
        return XST_FAILURE;
    }

    xil_printf("\tMUROSYNC SERDES | Link is up, clear sticky latch again...\r\n");
    if (murosync_serdes_pulse_link_latch_reset() != XST_SUCCESS)
    {
        xil_printf("\t\tERROR: LINK_LATCH_RESET pulse failed\r\n");
        return XST_FAILURE;
    }

    usleep(1000); // 1 ms guard time

    (void)murosync_serdes_get_status(&reg);
    xil_printf("\tMUROSYNC SERDES | LINK UP! STATUS=0x%08X\r\n", reg);

    murosync_serdes_print_status();
    murosync_serdes_print_dbg();

    return XST_SUCCESS;
}
/************************************************************************/

/************************* LINK TEST ************************************/

int murosync_serdes_link_test_set_mode(unsigned char mode)
{
    unsigned int val = ((unsigned int)mode << MUROSYNC_LNK_TEST_CNFG_MODE_OFS) & MUROSYNC_LNK_TEST_CNFG_MODE_MSK;
    return murosync_serdes_reg_modify(MUROSYNC_LNK_TEST_CNFG, val, MUROSYNC_LNK_TEST_CNFG_MODE_MSK);
}

int murosync_serdes_link_test_set_ch_mask(unsigned char ch_mask)
{
    unsigned int val = ((unsigned int)ch_mask << MUROSYNC_LNK_TEST_CNFG_CH_MASK_OFS) & MUROSYNC_LNK_TEST_CNFG_CH_MASK_MSK;
    return murosync_serdes_reg_modify(MUROSYNC_LNK_TEST_CNFG, val, MUROSYNC_LNK_TEST_CNFG_CH_MASK_MSK);
}

int murosync_serdes_link_test_set_pol_mask(unsigned char rx_pol_mask, unsigned char tx_pol_mask)
{
    unsigned int val = (((unsigned int)rx_pol_mask << MUROSYNC_LNK_TEST_CNFG_RX_POL_MASK_OFS) & MUROSYNC_LNK_TEST_CNFG_RX_POL_MASK_MSK) |
                       (((unsigned int)tx_pol_mask << MUROSYNC_LNK_TEST_CNFG_TX_POL_MASK_OFS) & MUROSYNC_LNK_TEST_CNFG_TX_POL_MASK_MSK);
    return murosync_serdes_reg_modify(MUROSYNC_LNK_TEST_CNFG, val, MUROSYNC_LNK_TEST_CNFG_RX_POL_MASK_MSK | MUROSYNC_LNK_TEST_CNFG_TX_POL_MASK_MSK);
}

int murosync_serdes_link_test_start(void)
{
    return murosync_serdes_reg_modify(MUROSYNC_LNK_TEST_CTRL, MUROSYNC_LNK_TEST_CTRL_EN_MSK, MUROSYNC_LNK_TEST_CTRL_EN_MSK);
}

int murosync_serdes_link_test_stop(void)
{
    return murosync_serdes_reg_modify(MUROSYNC_LNK_TEST_CTRL, 0x0, MUROSYNC_LNK_TEST_CTRL_EN_MSK);
}

int murosync_serdes_link_test_reset_cnt(void)
{
    int rc;

    // Set RST bit
    rc = murosync_serdes_reg_modify(MUROSYNC_LNK_TEST_CTRL, MUROSYNC_LNK_TEST_CTRL_RST_MSK, MUROSYNC_LNK_TEST_CTRL_RST_MSK);
    if (rc != XST_SUCCESS) return rc;

    // Clear RST bit
    return murosync_serdes_reg_modify(MUROSYNC_LNK_TEST_CTRL, 0x0, MUROSYNC_LNK_TEST_CTRL_RST_MSK);
}

int murosync_serdes_link_test_set_patt(unsigned int pattern)
{
    return murosync_serdes_reg_wr(MUROSYNC_LNK_TEST_PATT, pattern);
}

int murosync_serdes_link_test_get_err_cnt(unsigned int *err_cnt)
{
    return murosync_serdes_reg_rd(MUROSYNC_LNK_RX_ERR_CNT, err_cnt);
}

int murosync_serdes_link_test_get_wrd_cnt(unsigned int *wrd_cnt)
{
    return murosync_serdes_reg_rd(MUROSYNC_LNK_RX_WRD_CNT, wrd_cnt);
}

int murosync_serdes_run_link_test(unsigned char mode, unsigned char ch_mask, unsigned char rx_pol_mask, unsigned char tx_pol_mask, unsigned int pattern, unsigned int test_time_ms)
{
    unsigned int err_cnt = 0;
    unsigned int wrd_cnt = 0;

    xil_printf("\r\n\tMUROSYNC SERDES | --- LINK TEST START ---\r\n");
    xil_printf("\t\tMode        : %u\r\n", mode);
    xil_printf("\t\tCh Mask     : 0x%X\r\n", ch_mask);
    xil_printf("\t\tRX Pol Mask : 0x%X\r\n", rx_pol_mask);
    xil_printf("\t\tTX Pol Mask : 0x%X\r\n", tx_pol_mask);
    xil_printf("\t\tPattern     : 0x%08X\r\n", pattern);
    xil_printf("\t\tDuration    : %u ms\r\n", test_time_ms);

    // 1. Reset counters
    if (murosync_serdes_link_test_reset_cnt() != XST_SUCCESS)
    {
        xil_printf("\t\tERROR: Failed to reset counters\r\n");
        return XST_FAILURE;
    }

    usleep(1000); // 1 ms delay

    // 2. Set channel mask
    if (murosync_serdes_link_test_set_ch_mask(ch_mask) != XST_SUCCESS)
    {
        xil_printf("\t\tERROR: Failed to set channel mask\r\n");
        return XST_FAILURE;
    }

    // 3. Set mode
    if (murosync_serdes_link_test_set_mode(mode) != XST_SUCCESS)
    {
        xil_printf("\t\tERROR: Failed to set mode\r\n");
        return XST_FAILURE;
    }

    // 4. Set polarity masks
    if (murosync_serdes_link_test_set_pol_mask(rx_pol_mask, tx_pol_mask) != XST_SUCCESS)
    {
        xil_printf("\t\tERROR: Failed to set polarity masks\r\n");
        return XST_FAILURE;
    }

    // 4. If mode requires test pattern, set it
    if (mode == MUROSYNC_LNK_TEST_MODE_FIXED || mode == MUROSYNC_LNK_TEST_MODE_TOGGLE)
    {
        if (murosync_serdes_link_test_set_patt(pattern) != XST_SUCCESS)
        {
            xil_printf("\t\tERROR: Failed to set pattern\r\n");
            return XST_FAILURE;
        }
    }

    // 5. Start test
    xil_printf("\t\tTest Running...\r\n");
    if (murosync_serdes_link_test_start() != XST_SUCCESS)
    {
        xil_printf("\t\tERROR: Failed to start test\r\n");
        return XST_FAILURE;
    }

    // 6. Delay (adequate test time)
    usleep(test_time_ms * 1000);

    // 7. Stop test
    if (murosync_serdes_link_test_stop() != XST_SUCCESS)
    {
        xil_printf("\t\tERROR: Failed to stop test\r\n");
        return XST_FAILURE;
    }

    // 8. Read statuses
    if (murosync_serdes_link_test_get_err_cnt(&err_cnt) != XST_SUCCESS)
    {
        xil_printf("\t\tERROR: Failed to read error count\r\n");
        return XST_FAILURE;
    }

    if (murosync_serdes_link_test_get_wrd_cnt(&wrd_cnt) != XST_SUCCESS)
    {
        xil_printf("\t\tERROR: Failed to read word count\r\n");
        return XST_FAILURE;
    }

    // 9. Make conclusions
    xil_printf("\tMUROSYNC SERDES | --- LINK TEST RESULTS ---\r\n");
    xil_printf("\t\tWords Rx    : %u\r\n", wrd_cnt);
    xil_printf("\t\tErrors      : %u\r\n", err_cnt);

    if (wrd_cnt == 0)
    {
        xil_printf("\t\tRESULT      : FAIL (No data received)\r\n");
        return XST_FAILURE;
    } else if (err_cnt > 0)
    {
        xil_printf("\t\tRESULT      : FAIL (Errors detected)\r\n");
        return XST_FAILURE;
    } else
    {
        xil_printf("\t\tRESULT      : PASS\r\n");
        return XST_SUCCESS;
    }
}
/************************************************************************/

/************************* LINK TEST DIAGNOSTICS ************************/

void murosync_serdes_link_test_print_diag(void)
{
    unsigned int diag  = 0;
    unsigned int rx_lo = 0, rx_hi = 0;
    unsigned int ex_lo = 0, ex_hi = 0;

    murosync_serdes_reg_rd(MUROSYNC_LNK_DIAG_STATUS, &diag);
    murosync_serdes_reg_rd(MUROSYNC_LNK_DIAG_RX_LO,  &rx_lo);
    murosync_serdes_reg_rd(MUROSYNC_LNK_DIAG_RX_HI,  &rx_hi);
    murosync_serdes_reg_rd(MUROSYNC_LNK_DIAG_EXP_LO, &ex_lo);
    murosync_serdes_reg_rd(MUROSYNC_LNK_DIAG_EXP_HI, &ex_hi);

    unsigned int fsm     = (diag & MUROSYNC_LNK_DIAG_FSM_STATE_MSK) >> MUROSYNC_LNK_DIAG_FSM_STATE_OFS;
    unsigned int aligned = (diag & MUROSYNC_LNK_DIAG_RX_ALIGNED_MSK) >> MUROSYNC_LNK_DIAG_RX_ALIGNED_OFS;
    unsigned int comma   = (diag & MUROSYNC_LNK_DIAG_RX_COMMA_MSK)   >> MUROSYNC_LNK_DIAG_RX_COMMA_OFS;
    unsigned int charisk = (diag & MUROSYNC_LNK_DIAG_RX_CHARISK_MSK) >> MUROSYNC_LNK_DIAG_RX_CHARISK_OFS;
    unsigned int locked  = (diag & MUROSYNC_LNK_DIAG_LOCKED_MSK)     >> MUROSYNC_LNK_DIAG_LOCKED_OFS;

    const char *fsm_name[] = { "IDLE", "CAPTURE_CFG", "WAIT_ALIGN", "SEARCH", "LOCKED" };
    const char *fsm_str = (fsm <= 4u) ? fsm_name[fsm] : "UNKNOWN";

    xil_printf("\t[DIAG] FSM         : %u (%s)\r\n", fsm, fsm_str);
    xil_printf("\t[DIAG] RX aligned  : 0x%X [CH3=%u CH2=%u CH1=%u CH0=%u]\r\n",
               aligned, (aligned>>3)&1u, (aligned>>2)&1u, (aligned>>1)&1u, aligned&1u);
    xil_printf("\t[DIAG] Comma seen  : 0x%X [CH3=%u CH2=%u CH1=%u CH0=%u]\r\n",
               comma, (comma>>3)&1u, (comma>>2)&1u, (comma>>1)&1u, comma&1u);
    xil_printf("\t[DIAG] RX charisk  : 0x%X\r\n", charisk);
    xil_printf("\t[DIAG] Locked      : %u\r\n", locked);
    xil_printf("\t[DIAG] RX data     : 0x%08X%08X\r\n", rx_hi, rx_lo);
    xil_printf("\t[DIAG] EXP data    : 0x%08X%08X\r\n", ex_hi, ex_lo);
}

static void murosync_serdes_link_test_run_one(
    const char   *label,
    unsigned char mode,
    unsigned char ch_mask,
    unsigned char rx_pol,
    unsigned char tx_pol,
    unsigned int  pattern,
    unsigned int  duration_ms)
{
    xil_printf("\r\n--- %s ---\r\n", label);

    // Phase 1: run 500ms — enough time for alignment and lock
    murosync_serdes_run_link_test(mode, ch_mask, rx_pol, tx_pol, pattern, 500);

    // Read diagnostics immediately after stop — FSM will be IDLE but
    // aligned/comma_seen are sticky and reflect what happened during the run
    xil_printf("\t[DIAG after 500ms run]\r\n");
    murosync_serdes_link_test_print_diag();

    // Phase 2: full duration run to get accurate word/error counts
    murosync_serdes_run_link_test(mode, ch_mask, rx_pol, tx_pol, pattern, duration_ms);
}

void murosync_serdes_link_test_run_diagnostics(void)
{
    murosync_serdes_link_test_run_one(
        "FIXED 0x0000 all channels",
        MUROSYNC_LNK_TEST_MODE_FIXED, 0xF, 0x0, 0x0, 0x00000000, 1000);

    murosync_serdes_link_test_run_one(
        "COUNTER CH0",
        MUROSYNC_LNK_TEST_MODE_COUNTER, 0x1, 0x0, 0x0, 0x0, 2000);

    murosync_serdes_link_test_run_one(
        "COUNTER CH1",
        MUROSYNC_LNK_TEST_MODE_COUNTER, 0x2, 0x0, 0x0, 0x0, 2000);

    murosync_serdes_link_test_run_one(
        "COUNTER CH2",
        MUROSYNC_LNK_TEST_MODE_COUNTER, 0x4, 0x0, 0x0, 0x0, 2000);

    murosync_serdes_link_test_run_one(
        "COUNTER CH3",
        MUROSYNC_LNK_TEST_MODE_COUNTER, 0x8, 0x0, 0x0, 0x0, 2000);

    murosync_serdes_link_test_run_one(
        "P/N SWAP CHECK CH0 rx_pol=1",
        MUROSYNC_LNK_TEST_MODE_COUNTER, 0x1, 0x1, 0x0, 0x0, 2000);
}

/************************************************************************/

/******************************* TASK ***********************************/
int murosync_serdes_link_monitor(void)
{
    static int last_link = -1;

    int link = murosync_serdes_is_link_up();

    if (link == XST_FAILURE)
        return MUROSYNC_SERDES_EVENT_NONE;

    if (link != last_link)
    {
        last_link = link;

        if (link == MUROSYNC_GT_LINK_UP) return MUROSYNC_SERDES_EVENT_LINK_UP;
        else                             return MUROSYNC_SERDES_EVENT_LINK_DOWN;
    }

    return MUROSYNC_SERDES_EVENT_NONE;
}

void murosync_serdes_link_task(void)
{
    switch (murosync_serdes_link_monitor())
    {
        case MUROSYNC_SERDES_EVENT_LINK_UP:
        {
            xil_printf("[MUROSYNC] SERDES LINK UP\r\n");
            break;
        }

        case MUROSYNC_SERDES_EVENT_LINK_DOWN:
        {
            xil_printf("[MUROSYNC] SERDES LINK DOWN\r\n");
            murosync_serdes_print_status();
            murosync_serdes_print_dbg();
            /*
                LINK_DOWN
                    ↓
                stop timing distribution
                   ↓
                recover link
                   ↓
                re-lock phase

                if (murosync_serdes_bring_up(0, 5000000) == XST_SUCCESS)
                {
                    xil_printf("[MUROSYNC] SERDES LINK RECOVERED\r\n");
                }
                else
                {
                    xil_printf("[MUROSYNC][ERROR] SERDES RECOVERY FAILED\r\n");
                }
            */
            break;
        }

        default:
            break;
    }
}
/************************************************************************/



