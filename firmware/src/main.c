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

/* Identify the loaded IP: verify AXI alive, read IP_INFO, print identity.
 * Does NOT touch GT — only register access on common AXI registers and IP_INFO.
 * On success, populates *info with mode, version, num_channels. */
static int murosync_app_identify(murosync_ip_info_t *info)
{
    /* AXI selftest — confirm register interface works before reading IP_INFO */
    if (murosync_serdes_selftest_const() != XST_SUCCESS)
    {
        xil_printf("[MUROSYNC][FATAL] AXI selftest (TEST_CONST) FAILED\r\n");
        return XST_FAILURE;
    }
    if (murosync_serdes_selftest_scratch() != XST_SUCCESS)
    {
        xil_printf("[MUROSYNC][FATAL] AXI selftest (TEST_SCRATCH) FAILED\r\n");
        return XST_FAILURE;
    }

    /* Read IP identity */
    if (murosync_serdes_get_ip_info(info) != XST_SUCCESS)
    {
        xil_printf("[MUROSYNC][FATAL] IP_INFO read FAILED\r\n");
        return XST_FAILURE;
    }
    murosync_serdes_print_ip_info();
    return XST_SUCCESS;
}

/* MASTER bring-up: orchestrated bring-up + BIST in NEAR-END loopback,
 * then switch to NONE loopback (external/optical) and run smoke test. */
static int murosync_app_bringup_master(void)
{
    xil_printf("\r\n[MUROSYNC] === MASTER FLOW ===\r\n");

    /* bring_up_with_bist does: AXI selftest, GT reset, NEAR-END bring-up,
     * BIST link test, switch to final loopback (NONE). */
    if (murosync_serdes_bring_up_with_bist(MUROSYNC_SERDES_LOOPBACK_NONE, 5000000)
        != XST_SUCCESS)
    {
        xil_printf("[MUROSYNC][FATAL] MASTER bring-up + BIST FAILED\r\n");
        return XST_FAILURE;
    }
    murosync_serdes_print_gt_ground_truth("post bring-up");

    /* External loopback smoke test (FMC loopback board or optical line) */
    if (murosync_serdes_run_all_channels_smoke_test() != XST_SUCCESS)
    {
        xil_printf("[MUROSYNC][FATAL] Smoke test FAILED\r\n");
        return XST_FAILURE;
    }
    murosync_serdes_print_gt_ground_truth("post smoke test");

    return XST_SUCCESS;
}

/* SLAVE bring-up: passive only. No BIST — SLAVE has no TX pattern generator
 * and no RX checker (both gated by IS_SLAVE in RTL). On FMC loopback the
 * GT will still align (cascade echo), but no validation pattern flows.
 * Real validation requires MASTER<->SLAVE optical link. */
static int murosync_app_bringup_slave(void)
{
    xil_printf("\r\n[MUROSYNC] === SLAVE FLOW ===\r\n");

    if (murosync_serdes_bring_up(MUROSYNC_SERDES_LOOPBACK_NONE, 5000000)
        != XST_SUCCESS)
    {
        xil_printf("[MUROSYNC][FATAL] SLAVE bring-up FAILED\r\n");
        return XST_FAILURE;
    }
    murosync_serdes_print_gt_ground_truth("post bring-up");

    return XST_SUCCESS;
}

/* Production main loop: heartbeat + link monitor. Never returns. */
static void murosync_app_main_loop(const murosync_ip_info_t *info)
{
    unsigned int alive_cnt = 0;
    const char *mode_tag = (info->mode == MUROSYNC_MODE_MASTER) ? "M" : "S";

    for (;;)
    {
        xil_printf("[MUROSYNC] alive #%u (%s v%u.%u)\r\n",
                   alive_cnt++,
                   mode_tag,
                   info->version_major, info->version_minor);
        murosync_serdes_link_task();
        usleep(1000000);
    }
}

int main(void)
{
    init_platform();
    usleep(1000000);
    murosync_print_banner();

    murosync_ip_info_t info;
    if (murosync_app_identify(&info) != XST_SUCCESS)
    {
        return XST_FAILURE;
    }

    int rc;
    switch (info.mode)
    {
        case MUROSYNC_MODE_MASTER:
            rc = murosync_app_bringup_master();
            break;
        case MUROSYNC_MODE_SLAVE:
            rc = murosync_app_bringup_slave();
            break;
        default:
            xil_printf("[MUROSYNC][FATAL] Unknown IP mode (raw=0x%08X)\r\n",
                       info.raw);
            return XST_FAILURE;
    }
    if (rc != XST_SUCCESS)
    {
        return XST_FAILURE;
    }

    murosync_app_main_loop(&info);

    cleanup_platform();
    return 0;
}
