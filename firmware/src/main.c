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

/* Helper: run one short test with given pattern, print RX/TX state */
static void phase1_test_one_pattern(unsigned int pattern, int trial_idx)
{
    xil_printf("\r\n[PROBE] === trial %d: pattern = 0x%08X ===\r\n",
               trial_idx, pattern);

    /* Clean state before each trial */
    (void)murosync_serdes_link_test_stop();
    usleep(5000);
    (void)murosync_serdes_link_test_reset_cnt();
    usleep(5000);

    /* Configure */
    /* CH0 — the only fiber-connected channel in this bench setup.
     * Earlier probes used 0x2 (CH1) by mistake; CH1 has no fiber so
     * checker was reading dark-channel noise. CH0 is the real link. */
    (void)murosync_serdes_link_test_set_ch_mask(0x1);
    (void)murosync_serdes_link_test_set_mode(MUROSYNC_LNK_TEST_MODE_FIXED);
    (void)murosync_serdes_link_test_set_pol_mask(0x0, 0x0);
    (void)murosync_serdes_link_test_set_patt(pattern);

    /* Start */
    (void)murosync_serdes_link_test_start();
    usleep(300000);   /* 300 ms — enough to settle FSM, run pattern */

    /* Snapshot while running — print_diag gives Tier 1+2 telemetry:
     * err_cnt, wrd_cnt, ever_locked, last_fsm_state, at_lock snapshot
     * (coherent!), at_first_err GOT/EXP/XOR for byte-shift diagnosis. */
    xil_printf("\r\n[PROBE] trial %d snapshot (running):\r\n", trial_idx);
    murosync_serdes_link_test_print_diag();

    /* Stop and final snapshot */
    (void)murosync_serdes_link_test_stop();
    usleep(5000);
    xil_printf("\r\n[PROBE] trial %d snapshot (after stop):\r\n", trial_idx);
    murosync_serdes_link_test_print_diag();
}

/* MASTER bring-up: Phase 1 pattern sweep — characterise whether RX is
 * decorrelated from TX (no loopback at all) or correlated but distorted
 * (polarity / 8B10B / channel mismatch). Five trials with distinct TX
 * patterns; each prints RX data so we can see how (or whether) it
 * tracks the TX side. */
static int murosync_app_bringup_master(void)
{
    xil_printf("\r\n[MUROSYNC] === MASTER FLOW ===\r\n");
    xil_printf("[MUROSYNC] Phase 1: pattern sweep diagnostic\r\n");

    if (murosync_serdes_bring_up(MUROSYNC_SERDES_LOOPBACK_NONE, 5000000)
        != XST_SUCCESS)
    {
        xil_printf("[MUROSYNC][FATAL] MASTER bring-up FAILED\r\n");
        return XST_FAILURE;
    }
    murosync_serdes_print_gt_ground_truth("post bring-up");

    /* Pattern sweep — extended to test byte-alignment hypothesis.
     * Symmetry classes (informative for misalignment diagnosis):
     *   - byte-symmetric (1-4, 5): match in any byte phase
     *   - 16-bit symmetric but byte-asymmetric (6): match in 0 or 2-byte phase
     *   - fully asymmetric (7): match only at exact byte alignment */
    phase1_test_one_pattern(0xAAAAAAAA, 1);   /* byte-symmetric: AA AA AA AA */
    phase1_test_one_pattern(0x00000000, 2);   /* byte-symmetric: 00 00 00 00 */
    phase1_test_one_pattern(0xFFFFFFFF, 3);   /* byte-symmetric: FF FF FF FF */
    phase1_test_one_pattern(0x55555555, 4);   /* byte-symmetric: 55 55 55 55 */
    phase1_test_one_pattern(0x12121212, 5);   /* byte-symmetric, non-trivial: 12 12 12 12 */
    phase1_test_one_pattern(0x12341234, 6);   /* 16-bit symmetric, byte-asymmetric: 12 34 12 34 */
    phase1_test_one_pattern(0x12345678, 7);   /* fully asymmetric: 12 34 56 78 */

    xil_printf("\r\n[MUROSYNC] === pattern sweep complete, entering main loop ===\r\n");
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
                   alive_cnt,
                   mode_tag,
                   info->version_major, info->version_minor);
        murosync_serdes_link_task();

        /* Every 10 seconds, dump GT ground truth so we can see if optical
         * alignment is still held — useful for both MASTER and SLAVE to
         * monitor link health from external observer. */
        if ((alive_cnt % 10) == 0) {
            murosync_serdes_print_gt_ground_truth("periodic");
        }

        alive_cnt++;
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
