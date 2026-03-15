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
