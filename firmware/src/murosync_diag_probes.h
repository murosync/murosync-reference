/******************************************************************************
 *  Project    : MuroSync
 *  File       : murosync_diag_probes.h
 *  Created    : 2026-05-31
 *  Author     : Mikhail Vasilev
 *
 *  Description:
 *  Diagnostic probe scaffolding for MuroSync SERDES bring-up.
 *
 *  These probes are NOT production code — they exist to characterise the
 *  optical link during board bring-up, channel verification, and Phase 1
 *  pattern-sweep investigations. Keep them out of main.c so the runtime
 *  flow stays small and obvious.
 *
 *  Usage: invoke from main.c (or a future debug CLI) under explicit
 *  enable flags. None of these are called automatically.
 *
 *  Copyright (c) 2026 Mikhail Vasilev / MuroSync
 *
 *  License:
 *  This file is currently released under a restricted research license.
 *
 *****************************************************************************/

#ifndef MUROSYNC_DIAG_PROBES_H_
#define MUROSYNC_DIAG_PROBES_H_

/* Phase 1 pattern sweep — drives TX with 7 distinct patterns covering
 * byte-symmetric and byte-asymmetric symmetry classes, prints RX state
 * for each, and lets a human diagnose whether RX is decorrelated or
 * correlated-but-distorted. Used only during optical-link bring-up.
 *
 * Side effects:
 *   - Stops/resets the link-test engine between trials.
 *   - Leaves the engine stopped after the last trial.
 *   - Does NOT reconfigure the GT — caller must have already brought it up.
 *
 * Channel mask used: 0x1 (CH0 only — the only fiber-connected channel
 * on the current bench setup). Change here if the wiring changes. */
void murosync_diag_phase1_pattern_sweep(void);

/* ========================================================================
 * Verdict-style link characterisation (WER / BER + verdict).
 *
 * Same measurement engine as the pattern sweep, but prints a compact verdict
 * per run instead of the full [DIAG] dump. Built on the existing SERDES driver
 * getters; no RTL change.
 *
 * Metric honesty:
 *   - WER is exact (native per-word error counter).
 *   - BER (no RTL bit-accumulator yet):
 *       err == 0 -> upper bound  BER < 3/N_bits  (95% CL, rule of three)
 *       err  > 0 -> ESTIMATE     BER ~ WER * popcount(first_err)/16
 *   - comma-misframe is a HINT from the first-error snapshot only.
 * ======================================================================== */

/* CH0 carries 16 user bits per user-clock cycle (one 16-bit bus slice). */
#define MUROSYNC_DIAG_BITS_PER_WORD     (16ULL)

/* Verdict thresholds — tune here; the logic never hardcodes a number. */
#define MUROSYNC_DIAG_WER_FAIL_ABOVE    (1.0e-2)    /* WER above this => FAIL even if locked */
#define MUROSYNC_DIAG_BER_CLEAN_BELOW   (1.0e-9)    /* 0 err + bound under this => CLEAN      */
#define MUROSYNC_DIAG_BER_PROD_BELOW    (1.0e-12)   /* 0 err + bound under this => PRODUCTION */
#define MUROSYNC_DIAG_CL_RULE_OF_THREE  (3ULL)      /* 0-event 95% CL bound = 3/N            */

/* Long-run counter poll period. MUST be < 13.7 s: LNK_RX_WRD_CNT is 32-bit and
 * wraps at 2^32 words (~13.7 s @ 312.5 MHz). We poll & accumulate in 64-bit. */
#define MUROSYNC_DIAG_BER_POLL_MS       (4000u)

/* Run one config and print a verdict block.
 *   mode: MUROSYNC_LNK_TEST_MODE_FIXED / _TOGGLE / _COUNTER
 *   test_ms: keep < ~4000; for longer use murosync_diag_link_ber_run(). */
void murosync_diag_link_test_verdict(unsigned char mode, unsigned int pattern,
                                     unsigned char ch_mask, unsigned int test_ms);

/* Concise 7-pattern sweep on CH0 (ch_mask=0x1): one verdict line per pattern
 * plus an overall worst-case. Drop-in replacement for the verbose
 * murosync_diag_phase1_pattern_sweep() in the normal bring-up flow. */
void murosync_diag_link_sweep_verdict(void);

/* Long FIXED BER run on CH0 (wrap-safe). For formal Phase-1 closure. */
void murosync_diag_link_ber_run(unsigned int seconds);

#endif /* MUROSYNC_DIAG_PROBES_H_ */
