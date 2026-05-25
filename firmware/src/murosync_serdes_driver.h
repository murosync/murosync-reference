/******************************************************************************
 *  Project    : MuroSync
 *  File       : murosync_serdes_driver.h
 *  Created    : 2026-01-02
 *  Author     : Mikhail Vasilev
 *
 *  Description:
 *  Public API and definitions for the MuroSync SERDES driver.
 *
 *  This header file declares the register-level access functions,
 *  control commands, status helpers, and debug utilities used to
 *  configure, bring up, and monitor the MuroSync optical SERDES
 *  subsystem.
 *
 *  The interface is designed for FPGA-based firmware running on
 *  embedded processors (e.g. MicroBlaze) and provides a clean,
 *  hardware-agnostic abstraction layer over the underlying
 *  AXI-connected SERDES control registers.
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

#ifndef MUROSYNC_SERDES_ARRAY_DRIVER_H_
#define MUROSYNC_SERDES_ARRAY_DRIVER_H_

#include "murosync_serdes_regs.h"

#include "xio.h"
#include "xil_io.h"
#include "sleep.h"
#include "xstatus.h"
#include "xil_printf.h"
#include "xparameters.h"

#ifndef MUROSYNC_SERDES_ARRAY_BASEADDR
#define MUROSYNC_SERDES_ARRAY_BASEADDR   (XPAR_MUROSYNC_SERDES_ARRAY_0_BASEADDR)
#endif

#define MUROSYNC_SERDES_POLL_INTERVAL_USEC   100
#define MUROSYNC_SERDES_TIMEOUT_USEC         100000

#define MUROSYNC_GT_LINK_UP                  (2)
#define MUROSYNC_GT_LINK_DOWN                (3)

/* SERDES link monitor events */
#define MUROSYNC_SERDES_EVENT_NONE        0
#define MUROSYNC_SERDES_EVENT_LINK_UP     1
#define MUROSYNC_SERDES_EVENT_LINK_DOWN   2

typedef enum {
    MUROSYNC_SERDES_LOOPBACK_NONE  = 0x0,
    MUROSYNC_SERDES_LOOPBACK_NEAR  = 0x1,
    MUROSYNC_SERDES_LOOPBACK_FAR   = 0x2,
    MUROSYNC_SERDES_LOOPBACK_EXT   = 0x4
} murosync_serdes_loopback_t;

/* IP mode enum — populated by murosync_serdes_get_ip_info() from IP_INFO register */
typedef enum {
    MUROSYNC_MODE_UNKNOWN = 0,
    MUROSYNC_MODE_MASTER  = 1,
    MUROSYNC_MODE_SLAVE   = 2
} murosync_mode_t;

/* IP build identity decoded from IP_INFO register */
typedef struct {
    murosync_mode_t mode;
    unsigned int    version_major;
    unsigned int    version_minor;
    unsigned int    num_channels;
    unsigned int    raw;          /* full 32-bit register value for debug */
} murosync_ip_info_t;

/************************* Register access ******************************/
int  murosync_serdes_reg_rd(unsigned int reg_ofs, unsigned int *data);
int  murosync_serdes_reg_wr(unsigned int reg_ofs, unsigned int data);
int  murosync_serdes_reg_modify(unsigned int reg_ofs, unsigned int data, unsigned int mask);
void murosync_serdes_dump_registers(unsigned int start_ofs, unsigned int end_ofs);
/************************************************************************/

/*************************** Commands ***********************************/
int murosync_serdes_set_loopback(unsigned char loopback);
int murosync_serdes_w1p_pulse(unsigned int bit_mask);
int murosync_serdes_pulse_link_latch_reset(void);
int murosync_serdes_pulse_gt_reset_all(void);
int murosync_serdes_reset_sequence(void);
/************************************************************************/

/************************* Status helpers *******************************/
int murosync_serdes_get_status(unsigned int *stat);
int murosync_serdes_is_link_up(void);
int murosync_serdes_wait_link_up(int timeout_usec);
void murosync_serdes_print_status(void);
/************************************************************************/

/************************* Debug helpers ********************************/
int  murosync_serdes_get_dbg64(unsigned long long *dbg);
void murosync_serdes_print_dbg(void);
int  murosync_serdes_selftest_const(void);
int  murosync_serdes_scratch_wr_rd_check(unsigned int pattern, const char *tag);
int  murosync_serdes_selftest_scratch(void);
/************************************************************************/

/*************************** BTRING-UP **********************************/
int murosync_serdes_bring_up(unsigned char loopback, int timeout_usec);
/************************************************************************/

/************************* LINK TEST ************************************/
int murosync_serdes_link_test_set_mode(unsigned char mode);
int murosync_serdes_link_test_set_ch_mask(unsigned char ch_mask);
int murosync_serdes_link_test_set_pol_mask(unsigned char rx_pol_mask, unsigned char tx_pol_mask);
int murosync_serdes_link_test_start(void);
int murosync_serdes_link_test_stop(void);
int murosync_serdes_link_test_reset_cnt(void);
int murosync_serdes_link_test_set_patt(unsigned int pattern);
int murosync_serdes_link_test_get_err_cnt(unsigned int *err_cnt);
int murosync_serdes_link_test_get_wrd_cnt(unsigned int *wrd_cnt);
int murosync_serdes_link_test_get_ever_locked(unsigned int *ever_locked);
int murosync_serdes_link_test_get_last_fsm_state(unsigned int *last_state);

/* Tier 2 snapshot valid bits (from LNK_DIAG_STATUS2 bits [16], [17]) */
int murosync_serdes_link_test_get_rx_data_at_lock_valid(unsigned int *valid);
int murosync_serdes_link_test_get_first_err_valid(unsigned int *valid);

/* Tier 2 link_test diagnostic snapshots */
int murosync_serdes_link_test_get_time_to_lock(unsigned int *cycles);
int murosync_serdes_link_test_get_locked_cycle_count(unsigned int *cycles);
int murosync_serdes_link_test_get_rx_data_at_lock(unsigned long long *data);
int murosync_serdes_link_test_get_rx_data_at_first_err(unsigned long long *data);
int murosync_serdes_link_test_get_exp_data_at_first_err(unsigned long long *data);

/* Tier 2 per-channel error counters (ch = 0..3) */
int murosync_serdes_link_test_get_err_cnt_ch(unsigned char ch, unsigned int *cnt);

int murosync_serdes_run_link_test(unsigned char mode, unsigned char ch_mask, unsigned char rx_pol_mask, unsigned char tx_pol_mask, unsigned int pattern, unsigned int test_time_ms);
void murosync_serdes_link_test_print_diag(void);
void murosync_serdes_link_test_print_full_diag(void);
void murosync_serdes_link_test_run_diagnostics(void);
int murosync_serdes_connectivity_test(void);

/* Read sticky link_test diagnostics and print a MODE verdict (MASTER/SLAVE/AMBIGUOUS).
 * Intended to be called AFTER a link_test run (e.g. immediately after
 * murosync_serdes_bring_up_with_bist() succeeds). Counters are sticky until next
 * test start, so values reflect what happened during the last test.
 *
 * SLAVE bitstream (IS_SLAVE=1): all link_test logic is gated off in RTL →
 *   FSM never leaves IDLE, no comma TX, no TX counters, no wrd_cnt.
 * MASTER bitstream (IS_SLAVE=0): full pattern generator + checker active. */
void murosync_serdes_print_mode_verdict(const char *tag);

/* Read IP_INFO register and decode all fields into info struct.
 * Returns XST_SUCCESS on AXI read OK, XST_FAILURE otherwise.
 * Safe to call after bring_up — IP_INFO is RO and always present. */
int murosync_serdes_get_ip_info(murosync_ip_info_t *info);

/* Shortcut: returns just the mode from IP_INFO. Returns MUROSYNC_MODE_UNKNOWN on read failure. */
murosync_mode_t murosync_serdes_get_mode(void);

/* Print IP_INFO contents to UART in human-readable form.
 * Use after bring-up for traceability — log shows which bitstream is loaded. */
void murosync_serdes_print_ip_info(void);

/* Smoke tests — high-level validation wrappers around run_link_test.
 * Used by main as post-bring-up sanity checks. */
int  murosync_serdes_run_all_channels_smoke_test(void);
void murosync_serdes_run_per_channel_smoke_test(void);
/************************************************************************/

/************************* GT DEBUG *************************************/
typedef struct {
    uint8_t rxcommadet[4];
    uint8_t rxbyteisaligned[4];
    uint8_t rxbyterealign[4];
    uint8_t rxbuf_status[4];
    uint8_t txbuf_status[4];
    uint8_t rxsyncdone[4];
    uint8_t rxphaligndone[4];
    uint8_t rxcdrlock[4];
    uint8_t eyescandataerror[4];
    uint8_t rxresetdone[4];
    uint8_t txresetdone[4];
    uint8_t rxpmaresetdone[4];
    uint8_t txpmaresetdone[4];
} murosync_gt_debug_status_t;

int murosync_gt_debug_read_status(murosync_gt_debug_status_t *status);
void murosync_gt_debug_print_status(murosync_gt_debug_status_t *status);
int murosync_gt_debug_check_comma_detection(void);
void murosync_gt_debug_monitor_comma_detection(int duration_seconds);
void murosync_serdes_test_comma_detection(void);

/* Tier 2 GT sticky event counters (ch = 0..3, returns 16-bit value as unsigned int) */
int murosync_serdes_get_rxbyterealign_cnt(unsigned char ch, unsigned int *cnt);
int murosync_serdes_get_eyescandataerror_cnt(unsigned char ch, unsigned int *cnt);

/* Print low-level GT Wizard signals (RXCOMMADET, RXBYTEISALIGNED, RXBYTEREALIGN)
 * via the dedicated debug register (0x058). Bypasses RTL wrapping inside
 * murosync_serdes_array and gives a clean per-channel view of GT state.
 *
 * Use cases:
 *   - Post bring-up: confirm GT alignment (expect RXBYTEISALIGNED = 0xF after
 *     TX comma burst, 0x0 before).
 *   - Post smoke test: confirm alignment held during data traffic.
 *   - Field debug: when channel-asymmetric issues are suspected.
 *
 * tag — caller-supplied label shown in the printed header. */
void murosync_serdes_print_gt_ground_truth(const char *tag);
/************************************************************************/

/************************* BIST — Boot Self-Test *************************
 *
 * BIST validates the SERDES subsystem end-to-end inside the FPGA, using
 * internal PCS NEAR-END loopback (no external cables/SFPs needed).
 *
 * Returns a 32-bit bitmask where each bit represents a specific failure
 * mode. Convention: bit = failure, 0 = PASS, non-zero = at least one FAIL.
 *
 * Bit layout:
 *   [0]      AXI selftest failed (TEST_CONST, TEST_SCRATCH)
 *   [1]      GT bring-up failed (link_up never reached)
 *   [2]      BIST link_test produced no data (wrd_cnt == 0)
 *   [3]      BIST link_test had global errors (err_cnt > 0)
 *   [4]      BIST link_test had per-channel errors
 *   [5]      BIST link_test FSM never reached LOCKED
 *   [6]      BIST link_test at_lock snapshot was not taken
 *   [15:7]   reserved for future BIST extensions
 *   [31:16]  reserved for future external-test results
 *
 * Usage:
 *   unsigned int result = murosync_serdes_bist();
 *   if (result == MUROSYNC_SERDES_TEST_RESULT_PASS) { all OK }
 *   else { specific bits indicate which checks failed }
 *
 * BIST result is currently firmware-internal. AXI register exposure is
 * deferred to the future TCP/IP control plane register map design.
 *************************************************************************/

#define MUROSYNC_SERDES_TEST_RESULT_AXI_FAIL           (1u << 0)
#define MUROSYNC_SERDES_TEST_RESULT_BRINGUP_FAIL       (1u << 1)
#define MUROSYNC_SERDES_TEST_RESULT_BIST_NO_DATA       (1u << 2)
#define MUROSYNC_SERDES_TEST_RESULT_BIST_GLOBAL_ERR    (1u << 3)
#define MUROSYNC_SERDES_TEST_RESULT_BIST_PER_CH_ERR    (1u << 4)
#define MUROSYNC_SERDES_TEST_RESULT_BIST_NOT_LOCKED    (1u << 5)
#define MUROSYNC_SERDES_TEST_RESULT_BIST_AT_LOCK_VOID  (1u << 6)
/* [15:7]  reserved for BIST extensions */
/* [31:16] reserved for external test results */

#define MUROSYNC_SERDES_TEST_RESULT_PASS               (0u)

/* ALL_FAIL_MASK — OR of all named failure bits.
 * Used as initial value before BIST/bring-up checks clear individual bits.
 * Bits NOT in this mask are 0 in init, and stay 0 — they never appear as
 * "unknown failure" in print_bist_result(). Update this define when adding
 * new TEST_RESULT_* bits (BIST extensions, external test results, etc.). */
#define MUROSYNC_SERDES_TEST_RESULT_ALL_FAIL_MASK   ( \
    MUROSYNC_SERDES_TEST_RESULT_AXI_FAIL           | \
    MUROSYNC_SERDES_TEST_RESULT_BRINGUP_FAIL       | \
    MUROSYNC_SERDES_TEST_RESULT_BIST_NO_DATA       | \
    MUROSYNC_SERDES_TEST_RESULT_BIST_GLOBAL_ERR    | \
    MUROSYNC_SERDES_TEST_RESULT_BIST_PER_CH_ERR    | \
    MUROSYNC_SERDES_TEST_RESULT_BIST_NOT_LOCKED    | \
    MUROSYNC_SERDES_TEST_RESULT_BIST_AT_LOCK_VOID  )
/* = 0x0000007F  (7 defined bits) */

/* BIST function — internal PCS NEAR-END loopback test.
 * Returns bitmask: 0 = PASS, non-zero = failure (see TEST_RESULT_* defines above).
 * Side effect: sets loopback to NEAR-END during execution; does NOT restore
 * caller's choice — orchestrator (bring_up_with_bist) handles final loopback. */
unsigned int murosync_serdes_bist(void);

/* Decode a BIST result bitmask and print human-readable status to UART.
 * Prints "PASS" if result == 0, otherwise enumerates failed bits. */
void murosync_serdes_print_bist_result(unsigned int result);

/* High-level bring-up orchestrator: runs bring_up() in NEAR-END loopback,
 * executes BIST, then switches to the requested final loopback for production.
 * Returns XST_SUCCESS only if both bring-up and BIST passed. */
int murosync_serdes_bring_up_with_bist(unsigned char final_loopback, int timeout_usec);
/************************************************************************/

/******************************* TASK ***********************************/
int murosync_serdes_link_monitor(void);
void murosync_serdes_link_task(void);
/************************************************************************/

#endif /* MUROSYNC_SERDES_ARRAY_DRIVER_H_ */

