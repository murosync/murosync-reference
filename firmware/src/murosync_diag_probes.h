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

#endif /* MUROSYNC_DIAG_PROBES_H_ */
