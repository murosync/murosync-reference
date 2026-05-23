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
    unsigned int alive_cnt = 0;

    init_platform();
    usleep(1000000);
    murosync_print_banner();

    xil_printf("\r\n[MUROSYNC] === FMC LOOPBACK BRING-UP ===\r\n");

    /* Step 1: Bring-up with internal BIST validation.
     * Runs AXI selftest, GT reset, NEAR-END loopback bring-up, BIST link test,
     * then switches to requested final loopback (external = NONE = 0). */
    if (murosync_serdes_bring_up_with_bist(MUROSYNC_SERDES_LOOPBACK_NONE, 5000000)
        != XST_SUCCESS)
    {
        xil_printf("[MUROSYNC][FATAL] Bring-up FAILED\r\n");
        return XST_FAILURE;
    }

    /* Step 2: GT ground-truth check after bring-up.
     * Expect RXBYTEISALIGNED = 0xF (BIST burst left GT aligned). */
    murosync_serdes_print_gt_ground_truth("post bring-up");

    /* Step 3: External loopback smoke test — confirm full data path works
     * after BIST-to-external switch. */
    if (murosync_serdes_run_all_channels_smoke_test() != XST_SUCCESS)
    {
        xil_printf("[MUROSYNC][FATAL] External loopback smoke test FAILED\r\n");
        return XST_FAILURE;
    }

    /* Step 4: GT ground-truth check after smoke test.
     * Confirm alignment held through data traffic. */
    murosync_serdes_print_gt_ground_truth("post smoke test");

    /* Production main loop — heartbeat + link monitor */
    for (;;)
    {
        xil_printf("[MUROSYNC] alive #%u\r\n", alive_cnt++);
        murosync_serdes_link_task();
        usleep(1000000);
    }

    cleanup_platform();
    return 0;
}
