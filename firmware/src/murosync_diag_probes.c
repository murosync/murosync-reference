/******************************************************************************
 *  Project    : MuroSync
 *  File       : murosync_diag_probes.c
 *  Created    : 2026-05-31
 *  Author     : Mikhail Vasilev
 *
 *  Description:
 *  Phase 1 pattern-sweep diagnostic probes for the optical SERDES link.
 *  See murosync_diag_probes.h for the API contract.
 *
 *  Copyright (c) 2026 Mikhail Vasilev / MuroSync
 *
 *****************************************************************************/

#include "murosync_diag_probes.h"
#include "murosync_serdes_driver.h"

#include "sleep.h"
#include "xil_printf.h"

/* Per-trial timing constants. Tuned during Phase 1 — short enough to
 * iterate quickly, long enough to give the FSM time to settle and the
 * pattern enough cycles to expose byte-alignment issues. */
#define MUROSYNC_PROBE_INTER_STEP_USEC      (5000u)      /* 5 ms between W1P-style writes */
#define MUROSYNC_PROBE_RUN_WINDOW_USEC      (300000u)    /* 300 ms per pattern */

/* Channel mask. CH0 is the only fiber-connected channel in the current
 * bench setup; earlier probes used 0x2 (CH1) by mistake and were reading
 * dark-channel noise. Update here if the wiring changes. */
#define MUROSYNC_PROBE_CH_MASK              (0x1u)

/* Helper: run one short test with given pattern, print RX/TX state. */
static void phase1_test_one_pattern(unsigned int pattern, int trial_idx)
{
    xil_printf("\r\n[PROBE] === trial %d: pattern = 0x%08X ===\r\n",
               trial_idx, pattern);

    /* Clean state before each trial */
    (void)murosync_serdes_link_test_stop();
    usleep(MUROSYNC_PROBE_INTER_STEP_USEC);
    (void)murosync_serdes_link_test_reset_cnt();
    usleep(MUROSYNC_PROBE_INTER_STEP_USEC);

    /* Configure */
    (void)murosync_serdes_link_test_set_ch_mask(MUROSYNC_PROBE_CH_MASK);
    (void)murosync_serdes_link_test_set_mode(MUROSYNC_LNK_TEST_MODE_FIXED);
    (void)murosync_serdes_link_test_set_pol_mask(0x0, 0x0);
    (void)murosync_serdes_link_test_set_patt(pattern);

    /* Start */
    (void)murosync_serdes_link_test_start();
    usleep(MUROSYNC_PROBE_RUN_WINDOW_USEC);

    /* Snapshot while running — print_diag gives Tier 1+2 telemetry:
     * err_cnt, wrd_cnt, ever_locked, last_fsm_state, at_lock snapshot
     * (coherent!), at_first_err GOT/EXP/XOR for byte-shift diagnosis. */
    xil_printf("\r\n[PROBE] trial %d snapshot (running):\r\n", trial_idx);
    murosync_serdes_link_test_print_diag();

    /* Stop and final snapshot */
    (void)murosync_serdes_link_test_stop();
    usleep(MUROSYNC_PROBE_INTER_STEP_USEC);
    xil_printf("\r\n[PROBE] trial %d snapshot (after stop):\r\n", trial_idx);
    murosync_serdes_link_test_print_diag();
}

void murosync_diag_phase1_pattern_sweep(void)
{
    xil_printf("\r\n[MUROSYNC] === PHASE 1 PATTERN SWEEP ===\r\n");

    /* Pattern sweep — characterise byte-alignment / decorrelation.
     * Symmetry classes (informative for misalignment diagnosis):
     *   - byte-symmetric (1-5): match in any byte phase
     *   - 16-bit symmetric but byte-asymmetric (6): match in 0 or 2-byte phase
     *   - fully asymmetric (7): match only at exact byte alignment */
    phase1_test_one_pattern(0xAAAAAAAA, 1);   /* byte-symmetric: AA AA AA AA */
    phase1_test_one_pattern(0x00000000, 2);   /* byte-symmetric: 00 00 00 00 */
    phase1_test_one_pattern(0xFFFFFFFF, 3);   /* byte-symmetric: FF FF FF FF */
    phase1_test_one_pattern(0x55555555, 4);   /* byte-symmetric: 55 55 55 55 */
    phase1_test_one_pattern(0x12121212, 5);   /* byte-symmetric, non-trivial: 12 12 12 12 */
    phase1_test_one_pattern(0x12341234, 6);   /* 16-bit sym, byte-asym: 12 34 12 34 */
    phase1_test_one_pattern(0x12345678, 7);   /* fully asymmetric: 12 34 56 78 */

    xil_printf("\r\n[MUROSYNC] === PATTERN SWEEP COMPLETE ===\r\n");
}
