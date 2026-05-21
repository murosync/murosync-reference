/******************************************************************************
 *  Project    : MuroSync
 *  File       : main.c
 *  Created    : 2026-01-20
 *  Author     : Mikhail Vasilev
 *
 *  Description:
 *  Firmware entry point for the MuroSync system.
 *
 *  This file contains the main application loop used for system bring-up,
 *  diagnostics, and execution control on the target FPGA platform.
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

#include "platform.h"
#include "xil_printf.h"
#include "sleep.h"

#include "murosync_build_info.h"
#include "murosync_serdes_driver.h"

static void murosync_print_banner(void)
{
    xil_printf("\r\n");
    xil_printf("============================================================\r\n");
    xil_printf("                    M U R O S Y N C\r\n");
    xil_printf("      High-Precision Optical Timing & Synchronization\r\n");
    xil_printf("============================================================\r\n");
    xil_printf(" Platform : FPGA  XCAU15P\r\n");
    xil_printf(" CPU      : MicroBlaze\r\n");
    xil_printf(" Firmware : v%d.%d  (code %lu)\r\n",
               MUROSYNC_VERSION_MAJOR,
               MUROSYNC_VERSION_SUB,
               MUROSYNC_VERSION_CODE);
    xil_printf(" Build    : GT Bring-Up\r\n");
    xil_printf(" Built at : %s\r\n", MUROSYNC_BUILD_TIME_STR);
    xil_printf("            (%lu UTC)\r\n", MUROSYNC_BUILD_UNIX_TIME);
    xil_printf("============================================================\r\n");
    xil_printf("\r\n");
}

int main(void)
{
    int stat;
    unsigned int alive_cnt = 0;
    init_platform();
    usleep(1000000);
    murosync_print_banner();

    // Single bring-up — single GT reset
    xil_printf("\r\n[MUROSYNC] === FMC LOOPBACK — ALL CHANNELS ===\r\n");
    stat = murosync_serdes_bring_up(0, 5000000);  // loopback=0, external
    if (stat != XST_SUCCESS)
    {
        xil_printf("[MUROSYNC][ERROR] Bring-up FAILED\r\n");
        return XST_FAILURE;
    }
    xil_printf("[MUROSYNC] Bring-up OK\r\n");

    // ============================================================
    // GROUND TRUTH CHECK: read RXBYTEISALIGNED directly from GT Wizard
    // dedicated port (via 0x058 debug register).
    //
    // This is the clean per-channel signal exported by GT Wizard itself,
    // bypassing the manual rxctrl2_int[1]/[9]/[17]/[25] unpacking in
    // murosync_serdes_array.sv.
    //
    // Expected outcomes:
    //   0xF  -> GT is aligned on all 4 channels; manual indexing in
    //           serdes_array is wrong; RTL fix needed (point link_test
    //           to gt_debug_rxbyteisaligned_int).
    //   0x1  -> Only CH0 aligned; TX K28.5 not reaching CH1-3; need ILA
    //           on txctrl2_in to verify per-channel slice bits.
    //   0x0  -> GT does not see alignment at all; check IP comma config.
    //
    // We probe twice: immediately after bring-up (cold), and after the
    // first run_link_test cycle (TX has been actively sending K28.5).
    // ============================================================
    {
        unsigned int comma_reg = 0;
        murosync_serdes_reg_rd(MUROSYNC_GT_DEBUG_COMMA_ALIGN_REG, &comma_reg);
        unsigned char comma_det     = (comma_reg & MUROSYNC_GT_DEBUG_RXCOMMADET_MSK)      >> MUROSYNC_GT_DEBUG_RXCOMMADET_OFS;
        unsigned char byte_aligned  = (comma_reg & MUROSYNC_GT_DEBUG_RXBYTEISALIGNED_MSK) >> MUROSYNC_GT_DEBUG_RXBYTEISALIGNED_OFS;
        unsigned char realign       = (comma_reg & MUROSYNC_GT_DEBUG_RXBYTEREALIGN_MSK)   >> MUROSYNC_GT_DEBUG_RXBYTEREALIGN_OFS;

        xil_printf("\r\n[MUROSYNC] === GT WIZARD GROUND TRUTH (post bring-up, idle TX) ===\r\n");
        xil_printf("\tRXCOMMADET       : 0x%X [CH3=%u CH2=%u CH1=%u CH0=%u]\r\n",
                   comma_det,
                   (comma_det>>3)&1u, (comma_det>>2)&1u, (comma_det>>1)&1u, comma_det&1u);
        xil_printf("\tRXBYTEISALIGNED  : 0x%X [CH3=%u CH2=%u CH1=%u CH0=%u]   <-- KEY SIGNAL\r\n",
                   byte_aligned,
                   (byte_aligned>>3)&1u, (byte_aligned>>2)&1u, (byte_aligned>>1)&1u, byte_aligned&1u);
        xil_printf("\tRXBYTEREALIGN    : 0x%X\r\n", realign);
    }

    // Immediately after bring-up — all 4 channels in one test.
    // CDR is fresh, comma burst aligns all channels simultaneously.
    xil_printf("\r\n=== TEST: ALL CHANNELS, no reset between ===\r\n");
    murosync_serdes_run_link_test(MUROSYNC_LNK_TEST_MODE_FIXED, 0xF, 0x0, 0x0, 0xAAAAAAAA, 2000);
    murosync_serdes_link_test_print_diag();

    // Second ground-truth read AFTER TX has been sending K28.5 burst.
    // If TX-side fix is working, alignment should now be set on all
    // channels that comma actually reached.
    {
        unsigned int comma_reg = 0;
        murosync_serdes_reg_rd(MUROSYNC_GT_DEBUG_COMMA_ALIGN_REG, &comma_reg);
        unsigned char comma_det     = (comma_reg & MUROSYNC_GT_DEBUG_RXCOMMADET_MSK)      >> MUROSYNC_GT_DEBUG_RXCOMMADET_OFS;
        unsigned char byte_aligned  = (comma_reg & MUROSYNC_GT_DEBUG_RXBYTEISALIGNED_MSK) >> MUROSYNC_GT_DEBUG_RXBYTEISALIGNED_OFS;
        unsigned char realign       = (comma_reg & MUROSYNC_GT_DEBUG_RXBYTEREALIGN_MSK)   >> MUROSYNC_GT_DEBUG_RXBYTEREALIGN_OFS;

        xil_printf("\r\n[MUROSYNC] === GT WIZARD GROUND TRUTH (after TX comma burst) ===\r\n");
        xil_printf("\tRXCOMMADET       : 0x%X [CH3=%u CH2=%u CH1=%u CH0=%u]\r\n",
                   comma_det,
                   (comma_det>>3)&1u, (comma_det>>2)&1u, (comma_det>>1)&1u, comma_det&1u);
        xil_printf("\tRXBYTEISALIGNED  : 0x%X [CH3=%u CH2=%u CH1=%u CH0=%u]   <-- KEY SIGNAL\r\n",
                   byte_aligned,
                   (byte_aligned>>3)&1u, (byte_aligned>>2)&1u, (byte_aligned>>1)&1u, byte_aligned&1u);
        xil_printf("\tRXBYTEREALIGN    : 0x%X\r\n", realign);
    }

    // Per-channel tests — no bring-up between them
    for (int ch = 0; ch < 4; ch++)
    {
        xil_printf("\r\n=== TEST: CH%d only ===\r\n", ch);
        murosync_serdes_run_link_test(MUROSYNC_LNK_TEST_MODE_FIXED, 1 << ch, 0x0, 0x0, 0xAAAAAAAA, 500);
        murosync_serdes_link_test_print_diag();
    }

    for (;;)
    {
        xil_printf("[MUROSYNC] alive #%u\r\n", alive_cnt++);
        murosync_serdes_link_task();
        usleep(1000000);
    }

    cleanup_platform();
    return 0;
}
