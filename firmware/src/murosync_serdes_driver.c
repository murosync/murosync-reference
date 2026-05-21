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

/************************* GT DEBUG *************************************/
/************************* GT DEBUG FUNCTIONS ****************************/
 
int murosync_gt_debug_read_status(murosync_gt_debug_status_t *status) {
    if (!status) return XST_FAILURE;
    
    uint32_t comma_reg, rxbuf_reg, txbuf_reg, sync_reg, signal_reg, reset_reg;
    
    // Read all GT debug registers
    if (murosync_serdes_reg_rd(MUROSYNC_GT_DEBUG_COMMA_ALIGN_REG, &comma_reg) != XST_SUCCESS) return XST_FAILURE;
    if (murosync_serdes_reg_rd(MUROSYNC_GT_DEBUG_RXBUF_STATUS_REG, &rxbuf_reg) != XST_SUCCESS) return XST_FAILURE;
    if (murosync_serdes_reg_rd(MUROSYNC_GT_DEBUG_TXBUF_STATUS_REG, &txbuf_reg) != XST_SUCCESS) return XST_FAILURE;
    if (murosync_serdes_reg_rd(MUROSYNC_GT_DEBUG_SYNC_STATUS_REG, &sync_reg) != XST_SUCCESS) return XST_FAILURE;
    if (murosync_serdes_reg_rd(MUROSYNC_GT_DEBUG_SIGNAL_QUAL_REG, &signal_reg) != XST_SUCCESS) return XST_FAILURE;
    if (murosync_serdes_reg_rd(MUROSYNC_GT_DEBUG_RESET_STATUS_REG, &reset_reg) != XST_SUCCESS) return XST_FAILURE;
    
    // Extract per-channel data
    for (int ch = 0; ch < 4; ch++) {
        // Comma detection and alignment (from COMMA_ALIGN register)
        status->rxcommadet[ch] = (comma_reg >> (MUROSYNC_GT_DEBUG_RXCOMMADET_OFS + ch)) & 0x1;
        status->rxbyteisaligned[ch] = (comma_reg >> (MUROSYNC_GT_DEBUG_RXBYTEISALIGNED_OFS + ch)) & 0x1;
        status->rxbyterealign[ch] = (comma_reg >> (MUROSYNC_GT_DEBUG_RXBYTEREALIGN_OFS + ch)) & 0x1;
        
        // Buffer status (3 bits for RX, 2 bits for TX per channel)
        status->rxbuf_status[ch] = (rxbuf_reg >> (ch * 3)) & 0x7;
        status->txbuf_status[ch] = (txbuf_reg >> (ch * 2)) & 0x3;
        
        // Sync status
        status->rxsyncdone[ch] = (sync_reg >> (MUROSYNC_GT_DEBUG_RXSYNCDONE_OFS + ch)) & 0x1;
        status->rxphaligndone[ch] = (sync_reg >> (MUROSYNC_GT_DEBUG_RXPHALIGNDONE_OFS + ch)) & 0x1;
        status->rxcdrlock[ch] = 0; // Not available in current GT config
        
        // Signal quality
        status->eyescandataerror[ch] = (signal_reg >> ch) & 0x1;
        
        // Reset status
        status->rxresetdone[ch] = (reset_reg >> ch) & 0x1;
        status->txresetdone[ch] = (reset_reg >> (ch + 4)) & 0x1;
        status->rxpmaresetdone[ch] = (reset_reg >> (ch + 8)) & 0x1;
        status->txpmaresetdone[ch] = (reset_reg >> (ch + 12)) & 0x1;
    }
    
    return XST_SUCCESS;
}
 
void murosync_gt_debug_print_status(murosync_gt_debug_status_t *status) {
    xil_printf("\r\n=== GT Debug Status Report ===\r\n");
    
    xil_printf("COMMA DETECTION:\r\n");
    for (int ch = 0; ch < 4; ch++) {
        xil_printf("  CH%d: comma_det=%d byte_aligned=%d realign_events=%d\r\n",
                   ch, status->rxcommadet[ch], status->rxbyteisaligned[ch], status->rxbyterealign[ch]);
    }
    
    xil_printf("BUFFER STATUS:\r\n");
    for (int ch = 0; ch < 4; ch++) {
        xil_printf("  CH%d: rxbuf=0x%x txbuf=0x%x\r\n", 
                   ch, status->rxbuf_status[ch], status->txbuf_status[ch]);
    }
    
    xil_printf("SYNC STATUS:\r\n");
    for (int ch = 0; ch < 4; ch++) {
        xil_printf("  CH%d: sync_done=%d phase_align=%d\r\n",
                   ch, status->rxsyncdone[ch], status->rxphaligndone[ch]);
    }
    
    xil_printf("SIGNAL QUALITY:\r\n");
    for (int ch = 0; ch < 4; ch++) {
        xil_printf("  CH%d: eyescan_error=%d\r\n", ch, status->eyescandataerror[ch]);
    }
    
    xil_printf("RESET STATUS:\r\n");
    for (int ch = 0; ch < 4; ch++) {
        xil_printf("  CH%d: rx_reset=%d tx_reset=%d rx_pma=%d tx_pma=%d\r\n",
                   ch, status->rxresetdone[ch], status->txresetdone[ch], 
                   status->rxpmaresetdone[ch], status->txpmaresetdone[ch]);
    }
}
 
int murosync_gt_debug_check_comma_detection(void) {
    uint32_t comma_reg;
    if (murosync_serdes_reg_rd(MUROSYNC_GT_DEBUG_COMMA_ALIGN_REG, &comma_reg) != XST_SUCCESS) {
        xil_printf("[GT_DEBUG][ERROR] Failed to read comma detection register\r\n");
        return 0;
    }
    
    uint8_t comma_det = (comma_reg & MUROSYNC_GT_DEBUG_RXCOMMADET_MSK) >> MUROSYNC_GT_DEBUG_RXCOMMADET_OFS;
    uint8_t byte_aligned = (comma_reg & MUROSYNC_GT_DEBUG_RXBYTEISALIGNED_MSK) >> MUROSYNC_GT_DEBUG_RXBYTEISALIGNED_OFS;
    
    xil_printf("[GT_DEBUG] Comma check: comma_det=0x%x byte_aligned=0x%x\r\n", comma_det, byte_aligned);
    
    return (comma_det != 0) && (byte_aligned != 0);
}
 
void murosync_gt_debug_monitor_comma_detection(int duration_seconds) {
    xil_printf("=== Monitoring GT Comma Detection for %d seconds ===\r\n", duration_seconds);
    
    for (int i = 0; i < duration_seconds; i++) {
        uint32_t comma_reg;
        if (murosync_serdes_reg_rd(MUROSYNC_GT_DEBUG_COMMA_ALIGN_REG, &comma_reg) == XST_SUCCESS) {
            uint8_t comma_det = (comma_reg & MUROSYNC_GT_DEBUG_RXCOMMADET_MSK) >> MUROSYNC_GT_DEBUG_RXCOMMADET_OFS;
            uint8_t byte_aligned = (comma_reg & MUROSYNC_GT_DEBUG_RXBYTEISALIGNED_MSK) >> MUROSYNC_GT_DEBUG_RXBYTEISALIGNED_OFS;
            uint8_t realign_events = (comma_reg & MUROSYNC_GT_DEBUG_RXBYTEREALIGN_MSK) >> MUROSYNC_GT_DEBUG_RXBYTEREALIGN_OFS;
            
            xil_printf("T+%02d: comma=0x%x aligned=0x%x realign=0x%x\r\n", 
                       i, comma_det, byte_aligned, realign_events);
        } else {
            xil_printf("T+%02d: [ERROR] Register read failed\r\n", i);
        }
        
        usleep(1000000); // 1 second delay
    }
}
 
void murosync_serdes_test_comma_detection(void) {
    xil_printf("\r\n[MUROSYNC] === GT COMMA DETECTION TEST ===\r\n");
    
    // Quick check first
    int comma_ok = murosync_gt_debug_check_comma_detection();
    
    if (comma_ok) {
        xil_printf("[MUROSYNC] SUCCESS: GT comma detection working!\r\n");
    } else {
        xil_printf("[MUROSYNC] PROBLEM: No comma detection - analyzing...\r\n");
        
        // Read full GT debug status
        murosync_gt_debug_status_t status;
        if (murosync_gt_debug_read_status(&status) == XST_SUCCESS) {
            murosync_gt_debug_print_status(&status);
        } else {
            xil_printf("[MUROSYNC][ERROR] Failed to read GT debug status\r\n");
        }
    }
    
    // Monitor for 5 seconds to see dynamic behavior
    xil_printf("\r\n[MUROSYNC] Monitoring comma detection...\r\n");
    murosync_gt_debug_monitor_comma_detection(5);
    
    xil_printf("[MUROSYNC] === GT COMMA DETECTION TEST COMPLETE ===\r\n\r\n");
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

int murosync_serdes_link_test_get_ever_locked(unsigned int *ever_locked)
{
    unsigned int reg_val;
    int stat = murosync_serdes_reg_rd(MUROSYNC_LNK_DIAG_STATUS2_REG, &reg_val);
    if (stat != XST_SUCCESS) return stat;
    *ever_locked = (reg_val & MUROSYNC_LNK_DIAG_EVER_LOCKED_MSK) >> MUROSYNC_LNK_DIAG_EVER_LOCKED_OFS;
    return XST_SUCCESS;
}

int murosync_serdes_link_test_get_last_fsm_state(unsigned int *last_state)
{
    unsigned int reg_val;
    int stat = murosync_serdes_reg_rd(MUROSYNC_LNK_DIAG_STATUS2_REG, &reg_val);
    if (stat != XST_SUCCESS) return stat;
    *last_state = (reg_val & MUROSYNC_LNK_DIAG_LAST_FSM_STATE_MSK) >> MUROSYNC_LNK_DIAG_LAST_FSM_STATE_OFS;
    return XST_SUCCESS;
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

    // 1. Reset counters & Extended reset sequence for clean state
    if (murosync_serdes_link_test_reset_cnt() != XST_SUCCESS)
    {
        xil_printf("\t\tERROR: Failed to reset counters\r\n");
        return XST_FAILURE;
    }

    usleep(10000); // 10ms delay for reset propagation

    // Disable test engine 
    if (murosync_serdes_link_test_stop() != XST_SUCCESS) {
        xil_printf("\t\tERROR: Failed to stop test\r\n");
        return XST_FAILURE;
    }

    usleep(5000); // 5ms delay

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
    unsigned int ever_locked = 0;
    unsigned int last_state  = 0;
    murosync_serdes_link_test_get_ever_locked(&ever_locked);
    murosync_serdes_link_test_get_last_fsm_state(&last_state);

    xil_printf("\tMUROSYNC SERDES | --- LINK TEST RESULTS ---\r\n");
    xil_printf("\t\tWords Rx    : %u\r\n", wrd_cnt);
    xil_printf("\t\tErrors      : %u\r\n", err_cnt);

    const char *result;
    int rc;
    if (wrd_cnt == 0) {
        result = "FAIL (no data)";
        rc = XST_FAILURE;
    } else if (err_cnt > 0) {
        result = "FAIL (errors)";
        rc = XST_FAILURE;
    } else if (!ever_locked) {
        result = "FAIL (FSM never locked)";
        rc = XST_FAILURE;
    } else if (last_state != MUROSYNC_LNK_FSM_LOCKED) {
        result = "WARN (FSM exited not from LOCKED)";
        rc = XST_SUCCESS;
    } else {
        result = "PASS";
        rc = XST_SUCCESS;
    }

    xil_printf("\t\tRESULT      : %s\r\n", result);
    return rc;
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

    unsigned int ever_locked = 0, last_state = 0;
    murosync_serdes_link_test_get_ever_locked(&ever_locked);
    murosync_serdes_link_test_get_last_fsm_state(&last_state);

    static const char *fsm_names[] = {
        "IDLE", "CAPTURE_CFG", "WAIT_ALIGN", "SEARCH", "LOCKED"
    };
    const char *fsm_str  = (fsm       <= 4u) ? fsm_names[fsm]       : "UNKNOWN";
    const char *last_str = (last_state <= 4u) ? fsm_names[last_state] : "UNKNOWN";

    xil_printf("\t[DIAG] FSM         : %u (%s)\r\n", fsm, fsm_str);
    xil_printf("\t[DIAG] RX aligned  : 0x%X [CH3=%u CH2=%u CH1=%u CH0=%u]\r\n",
               aligned, (aligned>>3)&1u, (aligned>>2)&1u, (aligned>>1)&1u, aligned&1u);
    xil_printf("\t[DIAG] Comma seen  : 0x%X [CH3=%u CH2=%u CH1=%u CH0=%u]\r\n",
               comma, (comma>>3)&1u, (comma>>2)&1u, (comma>>1)&1u, comma&1u);
    xil_printf("\t[DIAG] RX charisk  : 0x%X\r\n", charisk);
    xil_printf("\t[DIAG] Locked      : %u\r\n", locked);
    xil_printf("\t[DIAG] Ever locked : %u  (1 = FSM reached LOCKED at least once)\r\n", ever_locked);
    xil_printf("\t[DIAG] Last state  : %u (%s)  (last active state before stop)\r\n", last_state, last_str);
    xil_printf("\t[DIAG] RX data     : 0x%08X%08X\r\n", rx_hi, rx_lo);
    xil_printf("\t[DIAG] EXP data    : 0x%08X%08X\r\n", ex_hi, ex_lo);
}

void murosync_serdes_link_test_print_full_diag(void)
{
    unsigned int tx_lo, tx_hi, tx_cnt_lo, tx_cnt_hi, tx_stat;
    unsigned int diag, rx_lo, rx_hi, exp_lo, exp_hi;

    // Read all diagnostic registers
    murosync_serdes_reg_rd(MUROSYNC_LNK_DIAG_TX_DATA_LO, &tx_lo);
    murosync_serdes_reg_rd(MUROSYNC_LNK_DIAG_TX_DATA_HI, &tx_hi);
    murosync_serdes_reg_rd(MUROSYNC_LNK_DIAG_TX_COUNTERS_LO, &tx_cnt_lo);
    murosync_serdes_reg_rd(MUROSYNC_LNK_DIAG_TX_COUNTERS_HI, &tx_cnt_hi);
    murosync_serdes_reg_rd(MUROSYNC_LNK_DIAG_TX_STATUS, &tx_stat);
    
    murosync_serdes_reg_rd(MUROSYNC_LNK_DIAG_STATUS, &diag);
    murosync_serdes_reg_rd(MUROSYNC_LNK_DIAG_RX_LO, &rx_lo);
    murosync_serdes_reg_rd(MUROSYNC_LNK_DIAG_RX_HI, &rx_hi);
    murosync_serdes_reg_rd(MUROSYNC_LNK_DIAG_EXP_LO, &exp_lo);
    murosync_serdes_reg_rd(MUROSYNC_LNK_DIAG_EXP_HI, &exp_hi);

    // Print TX state
    xil_printf("\t[TX] Data        : 0x%08X%08X\r\n", tx_hi, tx_lo);
    xil_printf("\t[TX] Counters    : CH3=%u CH2=%u CH1=%u CH0=%u\r\n", 
               (tx_cnt_hi >> 16) & 0xFFFF, tx_cnt_hi & 0xFFFF, 
               (tx_cnt_lo >> 16) & 0xFFFF, tx_cnt_lo & 0xFFFF);
    xil_printf("\t[TX] Comma       : %s (count=%u)\r\n", 
               (tx_stat & 1) ? "ACTIVE" : "DATA", (tx_stat >> 1) & 0xFFF);
    
    // Print RX state
    unsigned int fsm = (diag & 0xF);
    xil_printf("\t[RX] FSM         : %u (%s)\r\n", fsm, 
               (fsm==0)?"IDLE":(fsm==1)?"CAPTURE_CFG":(fsm==2)?"WAIT_ALIGN":
               (fsm==3)?"SEARCH":(fsm==4)?"LOCKED":"UNKNOWN");
               
    unsigned int aligned = (diag >> 4) & 0xF;
    unsigned int comma   = (diag >> 8) & 0xF;
    unsigned int charisk = (diag >> 12) & 0xF;
    unsigned int locked  = (diag >> 16) & 1;
               
    xil_printf("\t[RX] aligned     : 0x%X\r\n", aligned);
    xil_printf("\t[RX] comma_seen  : 0x%X\r\n", comma);
    xil_printf("\t[RX] charisk     : 0x%X\r\n", charisk);
    xil_printf("\t[RX] locked      : %u\r\n", locked);
               
    xil_printf("\t[RX] Data        : 0x%08X%08X\r\n", rx_hi, rx_lo);
    xil_printf("\t[RX] Expected    : 0x%08X%08X\r\n", exp_hi, exp_lo);
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
    murosync_serdes_link_test_print_full_diag();

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

int murosync_serdes_connectivity_test(void) {
    xil_printf("\r\n=== RUNNING CONNECTIVITY TEST ===\r\n");
    for (int ch = 0; ch < 4; ch++) {
        unsigned char ch_mask = (1 << ch);
        // Run short FIXED pattern test on single channel
        int result = murosync_serdes_run_link_test(
            MUROSYNC_LNK_TEST_MODE_FIXED, ch_mask, 0, 0, 0xAAAAAAAA, 100);
        xil_printf("CH%d: %s\r\n", ch, (result == XST_SUCCESS) ? "CONNECTED" : "DISCONNECTED");
    }
    return XST_SUCCESS;
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



