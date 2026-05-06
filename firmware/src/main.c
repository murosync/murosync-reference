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

    /* SERDES bring-up: loopback=0 (normal), timeout=5 s */
    stat = murosync_serdes_bring_up(0, 5000000);
    if (stat != XST_SUCCESS)
    {
        xil_printf("\r\n[MUROSYNC][ERROR] Bring-up FAILED\r\n");
        return XST_FAILURE;
    }

    xil_printf("\r\n[MUROSYNC] Bring-up OK\r\n");

    /* Run tests on each channel individually */
    xil_printf("\r\n--- TESTING INDIVIDUAL CHANNELS ---\r\n");
    murosync_serdes_run_link_test(MUROSYNC_LNK_TEST_MODE_COUNTER, 0x1, 0x0, 1000); // Ch 0
    murosync_serdes_run_link_test(MUROSYNC_LNK_TEST_MODE_COUNTER, 0x2, 0x0, 1000); // Ch 1
    murosync_serdes_run_link_test(MUROSYNC_LNK_TEST_MODE_COUNTER, 0x4, 0x0, 1000); // Ch 2
    murosync_serdes_run_link_test(MUROSYNC_LNK_TEST_MODE_COUNTER, 0x8, 0x0, 1000); // Ch 3

    for (;;)
    {
        xil_printf("[MUROSYNC] alive #%u\r\n", alive_cnt++);
        murosync_serdes_link_task();
        usleep(1000000);
    }

    /* never reached */
    cleanup_platform();
    return 0;
}
