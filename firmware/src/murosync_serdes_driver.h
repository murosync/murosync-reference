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

typedef enum {
    MUROSYNC_SERDES_LOOPBACK_NONE  = 0x0,
    MUROSYNC_SERDES_LOOPBACK_NEAR  = 0x1,
    MUROSYNC_SERDES_LOOPBACK_FAR   = 0x2,
    MUROSYNC_SERDES_LOOPBACK_EXT   = 0x4
} murosync_serdes_loopback_t;

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

#endif /* MUROSYNC_SERDES_ARRAY_DRIVER_H_ */
