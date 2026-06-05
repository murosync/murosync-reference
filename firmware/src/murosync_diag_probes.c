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

#include <stdint.h>

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

/* ========================================================================
 * Verdict-style link characterisation — implementation.
 * See murosync_diag_probes.h for the contract and metric-honesty notes.
 * ======================================================================== */

#define DIAG_LINK_SETTLE_USEC   (5000u)   /* settle between control writes */

typedef enum {
    DIAG_VERDICT_FAIL = 0,
    DIAG_VERDICT_DEGRADED,
    DIAG_VERDICT_CLEAN,
    DIAG_VERDICT_PRODUCTION
} diag_verdict_t;

typedef struct {
    unsigned char mode;
    unsigned int  pattern;
    unsigned char ch_mask;
    unsigned int  duration_ms;
    uint64_t words, bits, err_words;
    uint8_t  link_up, ever_locked, last_state;
    uint32_t time_to_lock, realign_test;
    uint8_t  first_err_valid;
    uint64_t first_err_got, first_err_exp;
    uint8_t  first_err_pop, comma_hint;
} diag_link_result_t;

/* ---- integer scientific notation (no float printf; xil_printf-safe) ----
 * Returns the number of characters printed (for column padding). */
static int diag_fmt_sci(uint64_t num, uint64_t den)
{
    if (den == 0ULL) { xil_printf("nan"); return 3; }
    if (num == 0ULL) { xil_printf("0");   return 1; }
    int e = 0;
    while (num < den) {
        if (num > (0xFFFFFFFFFFFFFFFFULL / 10ULL)) den /= 10ULL; else num *= 10ULL;
        e--;
    }
    while (num >= den * 10ULL) {
        if (den > (0xFFFFFFFFFFFFFFFFULL / 10ULL)) num /= 10ULL; else den *= 10ULL;
        e++;
    }
    uint64_t m100 = (num * 100ULL) / den;          /* 3 sig figs: 100..999 */
    int ea = (e < 0) ? -e : e;
    xil_printf("%d.%02de%c%02d", (int)(m100 / 100ULL), (int)(m100 % 100ULL),
               (e < 0) ? '-' : '+', ea);
    return 8;  /* "X.YYe[+-]NN" is always 8 chars */
}

/* Right-pad to a fixed column width (space-fill). */
static void diag_pad_to(int written, int width)
{
    while (written < width) { xil_printf(" "); written++; }
}

static int diag_popcount16(uint32_t v) { int c = 0; v &= 0xFFFFu; while (v) { v &= (v - 1u); c++; } return c; }
static uint32_t diag_ch0(uint64_t w) { return (uint32_t)(w & 0xFFFFu); }

static uint32_t diag_realign_ch0(void)
{
    unsigned int c = 0;
    (void)murosync_serdes_get_rxbyterealign_cnt(0, &c);
    return (uint32_t)c;
}

static void diag_apply_cfg(unsigned char mode, unsigned int pattern, unsigned char ch_mask)
{
    (void)murosync_serdes_link_test_set_ch_mask(ch_mask);
    (void)murosync_serdes_link_test_set_mode(mode);
    (void)murosync_serdes_link_test_set_pol_mask(0x0, 0x0);
    (void)murosync_serdes_link_test_set_patt(pattern);
}

/* Witness fields valid while LOCKED or just-stopped (all but last_fsm_state). */
static void diag_capture_witness(diag_link_result_t *r)
{
    unsigned int ev = 0, fv = 0, ttl = 0;
    (void)murosync_serdes_link_test_get_ever_locked(&ev);
    (void)murosync_serdes_link_test_get_first_err_valid(&fv);
    (void)murosync_serdes_link_test_get_time_to_lock(&ttl);
    r->ever_locked  = (uint8_t)(ev & 1u);
    r->time_to_lock = (uint32_t)ttl;
    r->link_up      = (uint8_t)(murosync_serdes_is_link_up() == MUROSYNC_GT_LINK_UP);
    r->first_err_valid = (uint8_t)(fv & 1u);
    if (r->first_err_valid) {
        unsigned long long got = 0, exp = 0;
        (void)murosync_serdes_link_test_get_rx_data_at_first_err(&got);
        (void)murosync_serdes_link_test_get_exp_data_at_first_err(&exp);
        r->first_err_got = (uint64_t)got;
        r->first_err_exp = (uint64_t)exp;
        uint32_t x = diag_ch0(got) ^ diag_ch0(exp);
        r->first_err_pop = (uint8_t)diag_popcount16(x);
        uint32_t s = diag_ch0(got);   /* K28.5 decoded as data shows as byte 0xBC */
        r->comma_hint = (uint8_t)(((s & 0xFFu) == 0xBCu) || (((s >> 8) & 0xFFu) == 0xBCu));
    }
}

/* Run one config, fill *r. Reads counters WHILE running (clean window, avoids
 * the pattern->idle stop-tail inflation); last_fsm_state read after stop.
 * Keep test_ms < ~4000 (usleep arg / counter wrap). */
static void diag_run_one(unsigned char mode, unsigned int pattern, unsigned char ch_mask,
                         unsigned int test_ms, diag_link_result_t *r)
{
    diag_link_result_t z = {0};
    *r = z;
    r->mode = mode; r->pattern = pattern; r->ch_mask = ch_mask; r->duration_ms = test_ms;

    (void)murosync_serdes_link_test_stop();
    usleep(DIAG_LINK_SETTLE_USEC);
    diag_apply_cfg(mode, pattern, ch_mask);
    (void)murosync_serdes_link_test_reset_cnt();
    usleep(DIAG_LINK_SETTLE_USEC);

    uint32_t realign0 = diag_realign_ch0();
    unsigned int w0 = 0, e0 = 0;
    (void)murosync_serdes_link_test_get_wrd_cnt(&w0);
    (void)murosync_serdes_link_test_get_err_cnt(&e0);

    (void)murosync_serdes_link_test_start();
    usleep((unsigned long)test_ms * 1000UL);

    unsigned int w1 = 0, e1 = 0;
    (void)murosync_serdes_link_test_get_wrd_cnt(&w1);
    (void)murosync_serdes_link_test_get_err_cnt(&e1);
    uint32_t realign1 = diag_realign_ch0();
    diag_capture_witness(r);

    (void)murosync_serdes_link_test_stop();
    usleep(DIAG_LINK_SETTLE_USEC);
    unsigned int last = 0;
    (void)murosync_serdes_link_test_get_last_fsm_state(&last);
    r->last_state = (uint8_t)last;

    r->words        = (uint64_t)(uint32_t)(w1 - w0);   /* wrap-safe unsigned delta */
    r->err_words    = (uint64_t)(uint32_t)(e1 - e0);
    r->bits         = r->words * MUROSYNC_DIAG_BITS_PER_WORD;
    r->realign_test = (uint32_t)(realign1 - realign0);
}

static diag_verdict_t diag_classify(const diag_link_result_t *r)
{
    if (!r->link_up)           return DIAG_VERDICT_FAIL;
    if (!r->ever_locked)       return DIAG_VERDICT_FAIL;
    if (r->last_state != 4u)   return DIAG_VERDICT_FAIL;   /* not LOCKED at stop */
    if (r->realign_test != 0u) return DIAG_VERDICT_FAIL;   /* lost byte sync mid-test */
    if (r->words == 0ULL)      return DIAG_VERDICT_FAIL;
    if (r->err_words == 0ULL) {
        double bound = (double)MUROSYNC_DIAG_CL_RULE_OF_THREE / (double)r->bits;
        if (bound < MUROSYNC_DIAG_BER_PROD_BELOW)  return DIAG_VERDICT_PRODUCTION;
        if (bound < MUROSYNC_DIAG_BER_CLEAN_BELOW) return DIAG_VERDICT_CLEAN;
        return DIAG_VERDICT_DEGRADED;   /* clean so far, too few bits to certify */
    }
    double wer = (double)r->err_words / (double)r->words;
    if (wer > MUROSYNC_DIAG_WER_FAIL_ABOVE) return DIAG_VERDICT_FAIL;
    return DIAG_VERDICT_DEGRADED;
}

static const char *diag_verdict_str(diag_verdict_t v)
{
    switch (v) {
        case DIAG_VERDICT_PRODUCTION: return "PRODUCTION";
        case DIAG_VERDICT_CLEAN:      return "CLEAN";
        case DIAG_VERDICT_DEGRADED:   return "DEGRADED";
        default:                      return "FAIL";
    }
}

static const char *diag_mode_str(unsigned char m)
{
    switch (m) { case 1: return "TOGGLE"; case 2: return "COUNTER"; default: return "FIXED"; }
}

static void diag_report(const diag_link_result_t *r)
{
    diag_verdict_t v = diag_classify(r);

    xil_printf("\r\n=== MUROSYNC LINK TEST ===  ch_mask=0x%x  %s", r->ch_mask, diag_mode_str(r->mode));
    if (r->mode == 0) xil_printf(" 0x%08x", r->pattern);
    xil_printf("\r\n");

    xil_printf("  duration       : %u ms\r\n", r->duration_ms);
    xil_printf("  observed       : ");
    diag_fmt_sci(r->words, 1ULL); xil_printf(" words / ");
    diag_fmt_sci(r->bits, 1ULL);  xil_printf(" bits\r\n");

    xil_printf("  lock           : %s  t_lock=%u cyc  realign(test)=%u\r\n",
               (r->ever_locked && r->last_state == 4u) ? "OK" : "BAD", r->time_to_lock, r->realign_test);

    xil_printf("  word errors    : ");
    diag_fmt_sci(r->err_words, 1ULL);
    xil_printf("   WER = ");
    if (r->words == 0ULL)          { xil_printf("N/A (never locked)"); }
    else if (r->err_words == 0ULL) { xil_printf("< "); diag_fmt_sci(MUROSYNC_DIAG_CL_RULE_OF_THREE, r->words); xil_printf(" (95pct CL)"); }
    else                           { diag_fmt_sci(r->err_words, r->words); }
    xil_printf("\r\n");

    xil_printf("  BER            : ");
    if (r->words == 0ULL)          { xil_printf("N/A (never locked)"); }
    else if (r->err_words == 0ULL) { xil_printf("< "); diag_fmt_sci(MUROSYNC_DIAG_CL_RULE_OF_THREE, r->bits); xil_printf(" (95pct CL, 0 err)"); }
    else {
        uint64_t pop = (r->first_err_pop > 0) ? r->first_err_pop : 1;
        diag_fmt_sci(r->err_words * pop, r->bits);
        xil_printf(" (est, %u-bit/err sample)", (unsigned)pop);
    }
    xil_printf("\r\n");

    if (r->first_err_valid) {
        uint32_t x = diag_ch0(r->first_err_got) ^ diag_ch0(r->first_err_exp);
        xil_printf("  first err XOR  : 0x%04x (%d bits)  got=0x%04x exp=0x%04x\r\n",
                   x, diag_popcount16(x), diag_ch0(r->first_err_got), diag_ch0(r->first_err_exp));
        if (r->comma_hint)
            xil_printf("  comma misframe : HINT - first-err CH0 byte = 0xBC -> K-echo (SLAVE charisk), NOT eye\r\n");
    }

    xil_printf("  --------------------------------------------------\r\n");
    xil_printf("  VERDICT: %s", diag_verdict_str(v));
    switch (v) {
        case DIAG_VERDICT_PRODUCTION: xil_printf("  (0 err, BER bound < 1e-12)\r\n"); break;
        case DIAG_VERDICT_CLEAN:      xil_printf("  (0 err, BER bound < 1e-9; run >=600 s for 1e-12)\r\n"); break;
        case DIAG_VERDICT_DEGRADED:
            if (r->err_words == 0ULL) xil_printf("  -- 0 errors but too few bits; run longer\r\n");
            else                      xil_printf("  -- link carries data, but has errors\r\n");
            break;
        default:
            xil_printf("  -- ");
            if (!r->link_up)              xil_printf("SERDES link down\r\n");
            else if (!r->ever_locked)     xil_printf("never locked (alignment/pattern)\r\n");
            else if (r->last_state != 4u) xil_printf("not LOCKED at stop\r\n");
            else if (r->realign_test)     xil_printf("lost byte alignment during test\r\n");
            else                          xil_printf("error rate above fail threshold\r\n");
            break;
    }
}

/* ---- public entry points ---- */
void murosync_diag_link_test_verdict(unsigned char mode, unsigned int pattern,
                                     unsigned char ch_mask, unsigned int test_ms)
{
    diag_link_result_t r;
    diag_run_one(mode, pattern, ch_mask, test_ms, &r);
    diag_report(&r);
}

void murosync_diag_link_sweep_verdict(void)
{
    static const unsigned int patt[7] = {
        0xAAAAAAAA, 0x00000000, 0xFFFFFFFF, 0x55555555, 0x12121212, 0x12341234, 0x12345678
    };
    /* Column widths (chars, excluding 2-char separators between):
     *   pattern=10  lock=4  WER=10  BER=10  comma=5  verdict=10
     * Total line width before verdict = 51 chars. */
    xil_printf("\r\n=== SWEEP ch_mask=0x1 (2000 ms each) ===\r\n\r\n");
    xil_printf("  %-10s  %-4s  %-10s  %-10s  %-5s  %s\r\n",
               "pattern", "lock", "WER", "BER(est)", "comma", "verdict");
    xil_printf("  ----------  ----  ----------  ----------  -----  ----------\r\n");

    diag_verdict_t worst = DIAG_VERDICT_PRODUCTION;
    unsigned int   worst_pat = 0;
    double         worst_wer = -1.0;
    int            w;

    for (int i = 0; i < 7; i++) {
        diag_link_result_t r;
        diag_run_one(MUROSYNC_LNK_TEST_MODE_FIXED, patt[i], 0x1u, 2000u, &r);
        diag_verdict_t v = diag_classify(&r);

        /* pattern col (10) + lock col (4) */
        xil_printf("  0x%08X  %-4s  ", patt[i], (r.ever_locked && r.last_state == 4u) ? "OK" : "BAD");

        /* WER col (10) */
        if (r.words == 0ULL)          { xil_printf("N/A"); w = 3; }
        else if (r.err_words == 0ULL) { xil_printf("< "); w = 2 + diag_fmt_sci(MUROSYNC_DIAG_CL_RULE_OF_THREE, r.words); }
        else                          { w = diag_fmt_sci(r.err_words, r.words); }
        diag_pad_to(w, 10);
        xil_printf("  ");

        /* BER col (10) */
        if (r.words == 0ULL)          { xil_printf("N/A"); w = 3; }
        else if (r.err_words == 0ULL) { xil_printf("< "); w = 2 + diag_fmt_sci(MUROSYNC_DIAG_CL_RULE_OF_THREE, r.bits); }
        else {
            uint64_t pop = (r.first_err_pop > 0) ? r.first_err_pop : 1;
            w = diag_fmt_sci(r.err_words * pop, r.bits);
        }
        diag_pad_to(w, 10);
        xil_printf("  ");

        /* comma col (5) + verdict */
        xil_printf("%-5s  %s\r\n", r.comma_hint ? "BC?" : "-", diag_verdict_str(v));

        double wer = (r.words) ? (double)r.err_words / (double)r.words : 1.0;
        if (wer > worst_wer) { worst_wer = wer; worst_pat = patt[i]; }
        if (v < worst) worst = v;   /* FAIL < DEGRADED < CLEAN < PRODUCTION */
    }
    xil_printf("  ----------  ----  ----------  ----------  -----  ----------\r\n");
    xil_printf("  WORST: 0x%08X  ->  overall %s\r\n", worst_pat, diag_verdict_str(worst));
}

void murosync_diag_link_ber_run(unsigned int seconds)
{
    diag_link_result_t r = {0};
    r.mode = MUROSYNC_LNK_TEST_MODE_FIXED; r.pattern = 0xAAAAAAAA; r.ch_mask = 0x1u;
    r.duration_ms = seconds * 1000u;

    (void)murosync_serdes_link_test_stop();
    usleep(DIAG_LINK_SETTLE_USEC);
    diag_apply_cfg(r.mode, r.pattern, r.ch_mask);
    (void)murosync_serdes_link_test_reset_cnt();
    usleep(DIAG_LINK_SETTLE_USEC);

    uint32_t realign0 = diag_realign_ch0();
    unsigned int prev_w = 0, prev_e = 0;
    (void)murosync_serdes_link_test_get_wrd_cnt(&prev_w);
    (void)murosync_serdes_link_test_get_err_cnt(&prev_e);

    (void)murosync_serdes_link_test_start();

    uint64_t words = 0, errs = 0;
    unsigned int elapsed = 0;
    while (elapsed < r.duration_ms) {
        unsigned int step = (r.duration_ms - elapsed < MUROSYNC_DIAG_BER_POLL_MS)
                          ? (r.duration_ms - elapsed) : MUROSYNC_DIAG_BER_POLL_MS;
        usleep((unsigned long)step * 1000UL);
        elapsed += step;
        unsigned int w = 0, e = 0;
        (void)murosync_serdes_link_test_get_wrd_cnt(&w);
        (void)murosync_serdes_link_test_get_err_cnt(&e);
        words += (uint64_t)(uint32_t)(w - prev_w);
        errs  += (uint64_t)(uint32_t)(e - prev_e);
        prev_w = w; prev_e = e;
    }

    uint32_t realign1 = diag_realign_ch0();
    diag_capture_witness(&r);
    (void)murosync_serdes_link_test_stop();
    usleep(DIAG_LINK_SETTLE_USEC);
    unsigned int last = 0;
    (void)murosync_serdes_link_test_get_last_fsm_state(&last);
    r.last_state = (uint8_t)last;

    r.words = words; r.err_words = errs; r.bits = words * MUROSYNC_DIAG_BITS_PER_WORD;
    r.realign_test = (uint32_t)(realign1 - realign0);
    diag_report(&r);
}
