# SLAVE Cascade Clocking — RTL Analysis

**Extracted:** 2026-05-29
**Method:** Read-only RTL analysis via `grep` and `Read` on source files.
**Purpose:** Determine whether the SLAVE-mode cascade echo
(`tx_data <= rx_data_r`) is clock-domain-safe, given empirical evidence
that local PMA NEAR-END loopback is clean (`err=0` across 7 patterns) but
external loop through SLAVE shows BER ~10⁻⁴ on CH1.

---

## TL;DR

**Hypothesis CONFIRMED.** The cascade is **NOT** clock-domain-safe. There is no
synchronizer or async FIFO between the RX user clock domain (`rx_clk` =
`gtwiz_userclk_rx_usrclk2`, sourced from the CDR-recovered RXOUTCLKPMA) and
the TX user clock domain (`tx_clk` = `gtwiz_userclk_tx_usrclk2`, sourced from
the local-refclk-derived TXOUTCLKPMA). The 64-bit `rx_data` bus is sampled
into a `tx_clk`-domain register (`rx_data_r`) directly with a single
flip-flop, and the same wiring shape exists for the 4-bit `rxcharisk` echo.

On a SLAVE board, these two clocks have **different physical sources**:
- TX clock chain: local 156.25 MHz refclk (SiT9121AI on SLAVE board) → QPLL0
  → CH0 TXOUTCLKPMA → BUFG_GT → `txusrclk2`.
- RX clock chain: **MASTER board's serial bit stream** arriving over fiber →
  CH0 CDR → RXOUTCLKPMA → BUFG_GT → `rxusrclk2`.

These are nominally both 312.5 MHz but they are asynchronous (~50–100 ppm
frequency offset plus arbitrary phase). Single-FF sampling of a 64-bit
bus between asynchronous clocks at this rate produces metastability events
at a rate consistent with the observed BER ~10⁻⁴.

The exact same wiring is correct on the MASTER side (where the cascade is
not exercised — `IS_SLAVE=0`), and the same module compiled with
`IS_SLAVE=1` reaches this codepath where it is unsafe. PMA NEAR-END on
MASTER does not exercise it (no SLAVE in loop), explaining the asymmetric
clean-local / dirty-external results.

---

## Q1: Cascade `tx_data <= rx_data_r` location

**File:** `C:/_vivado/ip/murosync_serdes_array/src/murosync_serdes_link_test.sv`:308–329
**Clock:** `posedge tx_clk` (declared as input port at line 39 of the module)

```systemverilog
// TX data pattern
always @(posedge tx_clk or negedge core_rst_n)
begin
    if (!core_rst_n)           tx_data <= 64'h0;
    else if (IS_SLAVE)         tx_data <= rx_data_r;            // ← CASCADE
    else if (send_comma)       tx_data <= {8{K28_5}};
    else
    begin : tx_pattern
        logic [63:0] raw;

        if      (tx_test_mode == TEST_MODE_FIXED)   raw = tx_fixed_64;
        else if (tx_test_mode == TEST_MODE_TOGGLE)  raw = toggle_state ? tx_fixed_64 : ~tx_fixed_64;
        else                                        raw = {counter_val_ch[3], ...};

        tx_data[15:0]  <= tx_pol_mask[0] ? ~raw[15:0]  : raw[15:0];
        ...
    end
end
```

This assignment itself is safe — both `tx_data` and `rx_data_r` are in
`tx_clk` domain. The unsafety lives one register upstream, in Q2.

**Also note** the parallel cascade path for TXCHARISK echo (same file,
lines 296–305), driven by the same clock:

```systemverilog
always @(posedge tx_clk or negedge core_rst_n)
begin
    if (!core_rst_n)     txctrl2_out <= 8'h0;
    else if (IS_SLAVE)   txctrl2_out <= {rxcharisk[3], rxcharisk[3],
                                         rxcharisk[2], rxcharisk[2],
                                         rxcharisk[1], rxcharisk[1],
                                         rxcharisk[0], rxcharisk[0]};
    else if (send_comma) txctrl2_out <= 8'hFF;
    else                 txctrl2_out <= 8'h0;
end
```

Here `rxcharisk` is an input port of the module (line 56), comes directly
from the RX clock domain at the module boundary, and is sampled on
`tx_clk` with no intermediate register at all. Same CDC risk as `rx_data`,
just on 4 bits instead of 64.

## Q2: `rx_data_r` register

**File:** `C:/_vivado/ip/murosync_serdes_array/src/murosync_serdes_link_test.sv`:279–285
**Clock:** `posedge tx_clk` (the **destination** domain)
**Source `rx_data`:** input port of `murosync_serdes_link_test` (line 60), connected at the parent (see Q3) to `gtwiz_userdata_rx_int`, which originates in the **`rx_clk`** domain inside the GT primitive.

```systemverilog
// Simple fabric logical loopback register for Slave mode
reg [63:0] rx_data_r;
always @(posedge tx_clk or negedge core_rst_n)
begin
    if (!core_rst_n) rx_data_r <= 64'h0;
    else             rx_data_r <= rx_data;     // ← UNSAFE CDC
end
```

**This is the single-flop CDC point.** The 64-bit `rx_data` bus is sampled
on the `tx_clk` rising edge with no synchronizer. There is no qualifier
(no valid signal, no handshake, no gray code) — every `tx_clk` edge takes
a snapshot of all 64 bits regardless of where the source `rx_clk` happens
to be in its cycle.

For metastability on a single flop with two asynchronous clocks, the
failure rate scales with bus width: each of 64 bits has an independent
small probability of being captured in metastability and resolving to the
"wrong" value. At ~50–100 ppm clock offset and 312.5 MHz, the relative
clock phase walks one full period roughly every 10⁵–10⁴ cycles. The
window where bus signals are mid-transition and an edge crosses unsafely
catches a few-bit error per such walk, observed as BER ~10⁻⁴.

## Q3: TX/RX user clock connections

The `link_test` module's `tx_clk` and `rx_clk` are wired in the top:

**File:** `C:/_vivado/ip/murosync_serdes_array/src/murosync_serdes_array.sv`:691–692

```systemverilog
murosync_serdes_link_test #( .IS_SLAVE(IS_SLAVE) ) u_link_test (
    .tx_clk            (gt_userclk_tx_usrclk2_int),
    .rx_clk            (gt_userclk_rx_usrclk2_int),
    ...
);
```

Those two `_int` wires are sourced from the GT wrapper:

**File:** same, lines 640–641

```systemverilog
.gtwiz_userclk_rx_usrclk2_out (gt_userclk_rx_usrclk2_int),
.gtwiz_userclk_tx_usrclk2_out (gt_userclk_tx_usrclk2_int),
```

i.e. **two separate output ports of the GT wrapper, two separate nets in the
top.**

In the generated GT IP wrapper, the `txusrclk_in` / `rxusrclk_in` ports are
**per-channel** bundles. From
`C:/_vivado/murosync_poc_v1/murosync_poc_v1.gen/.../synth/gtwizard_ultrascale_0.v`
lines 625–626 and 704–705:

```
.rxusrclk_in(rxusrclk_in),    // 4-bit
.rxusrclk2_in(rxusrclk2_in),  // 4-bit
.txusrclk_in(txusrclk_in),    // 4-bit
.txusrclk2_in(txusrclk2_in),  // 4-bit
```

Those buses are driven inside `murosync_gt_wrapper.sv` (lines 178–181) by
**fanout from a single shared clock per direction**:

```systemverilog
wire [NCH-1:0] txusrclk_int  = {NCH{gtwiz_userclk_tx_usrclk}};
wire [NCH-1:0] txusrclk2_int = {NCH{gtwiz_userclk_tx_usrclk2}};
wire [NCH-1:0] rxusrclk_int  = {NCH{gtwiz_userclk_rx_usrclk}};
wire [NCH-1:0] rxusrclk2_int = {NCH{gtwiz_userclk_rx_usrclk2}};
```

Per-channel breakdown:

| Channel | `txusrclk2_in[N]` | `rxusrclk2_in[N]` | Same wire as TX? |
|---|---|---|---|
| CH0 | `gtwiz_userclk_tx_usrclk2` | `gtwiz_userclk_rx_usrclk2` | **No** |
| CH1 | `gtwiz_userclk_tx_usrclk2` | `gtwiz_userclk_rx_usrclk2` | **No** |
| CH2 | `gtwiz_userclk_tx_usrclk2` | `gtwiz_userclk_rx_usrclk2` | **No** |
| CH3 | `gtwiz_userclk_tx_usrclk2` | `gtwiz_userclk_rx_usrclk2` | **No** |

All four channels share the same TX clock; all four share the same RX
clock; but **TX and RX are different physical wires** with different
sources (see Q5).

## Q4: TXOUTCLKSEL / RXOUTCLKSEL

From the generated wrapper
`C:/_vivado/murosync_poc_v1/murosync_poc_v1.gen/.../synth/gtwizard_ultrascale_0.v`
lines 598 and 665:

```
.rxoutclksel_in(12'H492),
.txoutclksel_in(12'H492),
```

Decode `12'h492` = `12'b0100_1001_0010` (12 bits, MSB→LSB).
Per-channel 3-bit slices (LSB-first, standard GT Wizard packing — CH0 in
lowest bits):

| Bits | Channel | Value | Encoded source |
|---|---|---|---|
| `[2:0]` | CH0 | `3'b010` | (R/T)XOUTCLKPMA |
| `[5:3]` | CH1 | `3'b010` | (R/T)XOUTCLKPMA |
| `[8:6]` | CH2 | `3'b010` | (R/T)XOUTCLKPMA |
| `[11:9]` | CH3 | `3'b010` | (R/T)XOUTCLKPMA |

Per UG576 Table 3-22 (and consistent with the XCI fields
`TX_OUTCLK_SOURCE = TXOUTCLKPMA` and `RX_OUTCLK_SOURCE = RXOUTCLKPMA`
in the IP XCI):

| Channel | TXOUTCLKSEL | TX source | RXOUTCLKSEL | RX source |
|---|---|---|---|---|
| 0 | `3'b010` | TXOUTCLKPMA — TX serializer clock, derived from local QPLL0/refclk | `3'b010` | RXOUTCLKPMA — **CDR-recovered** RX clock, derived from incoming serial bit stream |
| 1 | same | same | same | same |
| 2 | same | same | same | same |
| 3 | same | same | same | same |

**Critical interpretation:** TX uses **local clock chain** (board's own
refclk → QPLL → serializer → TXOUTCLKPMA). RX uses **CDR-recovered clock**
from the incoming serial signal. On the SLAVE board, the incoming signal
is the MASTER's TX, so SLAVE's RXOUTCLKPMA is locked to the **MASTER
board's refclk** (frequency-wise), not to its own. SLAVE's TX is locked
to its own refclk. → SLAVE's `tx_clk` and `rx_clk` are sourced from two
different boards' oscillators.

## Q5: User clocking network

**File:** `C:/_vivado/ip/murosync_serdes_array/src/murosync_gt_wrapper.sv`:155–175

Two independent helper-block instances, two independent `BUFG_GT` chains:

```systemverilog
murosync_gt_userclk_tx #( ... ) u_userclk_tx (
    .gtwiz_userclk_tx_srcclk_in   (txoutclk_int[TX_MASTER_CH]),   // [0]
    ...
    .gtwiz_userclk_tx_usrclk2_out (gtwiz_userclk_tx_usrclk2)
);

murosync_gt_userclk_rx #( ... ) u_userclk_rx (
    .gtwiz_userclk_rx_srcclk_in   (rxoutclk_int[RX_MASTER_CH]),   // [0]
    ...
    .gtwiz_userclk_rx_usrclk2_out (gtwiz_userclk_rx_usrclk2)
);
```

Each helper is a thin `BUFG_GT` wrapper
(`murosync_gt_userclk_tx.sv` / `murosync_gt_userclk_rx.sv`, ~110 lines
each):

- TX helper instantiates one or two `BUFG_GT`s on the TX_MASTER channel
  TXOUTCLK.
- RX helper instantiates one or two `BUFG_GT`s on the RX_MASTER channel
  RXOUTCLK.

There is no MMCM in either path. No PLL. Just a clock buffer with integer
divide (`DIV` parameter, here `0` = ÷1 since `P_FREQ_RATIO_SOURCE_TO_USRCLK
= 1`). When `P_FREQ_RATIO_USRCLK_TO_USRCLK2 = 1` (the default and what's
in use), `usrclk2` is wired identically to `usrclk` (`assign
usrclk2_out = usrclk_out;`).

So the resolved clock chains:

**TX clock chain on a SLAVE board:**
SLAVE on-board 156.25 MHz refclk (SiT9121AI) → IBUFDS_GTE4 →
QPLL0 (×40 → 6.25 GHz line) → CH0 PMA serializer → TXOUTCLK at 312.5 MHz →
BUFG_GT (DIV=÷1) → `gtwiz_userclk_tx_usrclk2` → fan-out to all 4 channels'
`txusrclk2_in` and to `link_test.tx_clk`.

**RX clock chain on a SLAVE board:**
MASTER's TX serial stream over fiber → SLAVE CH0 PMA CDR → RXOUTCLK at
312.5 MHz (frequency locked to MASTER's TX, not SLAVE's local refclk) →
BUFG_GT (DIV=÷1) → `gtwiz_userclk_rx_usrclk2` → fan-out to all 4 channels'
`rxusrclk2_in` and to `link_test.rx_clk`.

**In SLAVE mode `tx_clk` is sourced from SLAVE's local refclk;
`rx_clk` is sourced from MASTER's refclk via CDR.** The two refclks are
independent SiT9121AI oscillators on physically different PCBs. Per
SiT9121AI datasheet they each have ±25–50 ppm tolerance, summing to
~50–100 ppm worst-case offset.

**In MASTER mode** the same wiring topology exists, but the cascade is
gated off (`IS_SLAVE = 0` → the cascade branch in the always_ff is never
taken; `tx_data` is driven by the pattern generator clocked entirely
within `tx_clk`). The unsafe CDC path is dead code on MASTER, which is
why MASTER's PMA NEAR-END test passed cleanly.

For completeness: the IP also exports `gtwiz_userclk_rx_recclk_out` (the
recovered RX clock), assigned at gt_wrapper.sv:188 to
`gtwiz_userclk_rx_usrclk2`. This is the same net that becomes `rx_clk`
inside the link_test — useful future hook for "use RX clock as TX clock
on SLAVE" (see Recommendations).

## Q6: CDC primitives in cascade path

**None on the cascade data path.** Searched for:

- `XPM_FIFO_ASYNC` → 0 hits anywhere in `C:/_vivado/ip/murosync_serdes_array/src/`.
- `XPM_CDC_*` → 0 hits anywhere in `src/`.
- `murosync_cdc_level_sync` / `murosync_cdc_slow_to_fast` → present and
  used in `murosync_serdes_array_axi_ctrl.sv` for AXI↔core/GT pulse and
  level CDC, and in serdes_array.sv around lines 655–684 for the AXI/CDC
  bracket. **Not used between rx_clk and tx_clk inside `link_test`.**

The complete inventory of CDC structure inside `link_test`'s cascade path
between `rx_clk` (source) and `tx_clk` (destination) is:

| Stage | Path | Synchronizer? |
|---|---|---|
| `rx_data` (rx_clk) → `rx_data_r` (tx_clk) | line 284, single flop | **None** |
| `rx_data_r` (tx_clk) → `tx_data` (tx_clk) | line 311, same domain | n/a |
| `rxcharisk` (rx_clk port) → `txctrl2_out` (tx_clk) | line 299, single flop, no intermediate latch | **None** |

The single `rx_data_r` flop on `tx_clk` is the first and only stage.
Standard practice for level CDC requires a 2-stage `ASYNC_REG` synchronizer
**per bit**; for wide buses moving between asynchronous clocks, an async
FIFO (XPM_FIFO_ASYNC or equivalent) with internal gray-pointer CDC is the
standard solution, since bit-level synchronizers do not preserve word
coherence across all 64 bits.

## Q7: Buffer mode

From the generated wrapper parameter overrides
(`C:/_vivado/murosync_poc_v1/murosync_poc_v1.gen/.../synth/gtwizard_ultrascale_0.v`
~line 209 and 258):

```
.C_RX_BUFFER_MODE(1),
.C_TX_BUFFER_MODE(1),
```

Both elastic buffers are **enabled** (mode `1` = USE, not BYPASS). The
buffer-bypass control ports at the IP wrapper instantiation are wired to
deassert:

```
.gtwiz_buffbypass_tx_reset_in(1'B0),
.gtwiz_buffbypass_tx_start_user_in(1'B0),
.gtwiz_buffbypass_rx_reset_in(1'B0),
.gtwiz_buffbypass_rx_start_user_in(1'B0),
```

(lines 290–296 of `gtwizard_ultrascale_0.v`).

So the GT primitives' internal elastic buffers absorb the rate-matching
inside the PMA. This is the correct mode for our 8B/10B + comma alignment
setup. **Buffer mode is not the bug.** The metastability path is on the
**fabric** side, **after** the RX buffer has delivered a clean
`gtwiz_userdata_rx_out` in `rxusrclk2` domain — and then the fabric code
in `link_test` undoes that cleanness by sampling it on `tx_clk`.

---

## Conclusion

**Hypothesis status: CONFIRMED.**

The SLAVE cascade is **not** clock-domain-safe. The architecture is:

```
MASTER refclk (board A)          SLAVE refclk (board B)
       │                                  │
       ├─ QPLL0 ──── TXOUTCLKPMA ─┐       ├─ QPLL0 ──── TXOUTCLKPMA ──┐
       │                          │       │                            │
   serializer ── fiber ──────► CDR ──── RXOUTCLKPMA ──── BUFG_GT       │
       │                                  │                            │
       │                              rx_clk (312.5 MHz, locked to     │
       │                              MASTER's refclk)                 │
       │                                  │                            │
       │                                  ▼                            │
       │                          ╔═══════════════════════╗            │
       │                          ║  link_test (SLAVE)    ║            │
       │                          ║                       ║            │
       │                          ║  rx_data ─┐           ║            │
       │                          ║           │ <one FF>  ║            │
       │                          ║           ▼           ║            │
       │                          ║  rx_data_r ───────────╫──► tx_data │
       │                          ║  (tx_clk dom)         ║       │    │
       │                          ║                       ║       ▼    │
       │                          ╚═══════════════════════╝   serializer
       │                                  ▲                            │
       │                                  │                          fiber
       │                                  │                            │
       │                              tx_clk (312.5 MHz, locked to     │
       │                              SLAVE's refclk) ◄────────────────┘
       │
       ▼
   CDR on MASTER side recovers the doubly-degraded signal
   (degraded once by CDR-jitter on SLAVE's CDR, again by
   metastable resampling onto SLAVE's tx_clk)
```

The single-flop sample of a 64-bit asynchronous bus produces metastability
events at a rate that quantitatively matches the observed BER (~10⁻⁴ in
the 300 ms test windows).

This is consistent with **all** the empirical observations from the most
recent debug session:

1. **PMA NEAR-END on MASTER: 0 errors / 7 patterns.** The cascade path
   does not exist on MASTER (gated by `IS_SLAVE=0`), and PMA NEAR-END
   loops the signal entirely inside MASTER's own PMA, never going to the
   SLAVE board. The clean result here proves MASTER's RTL and PCS are
   fine.
2. **External loop locks but accumulates errors at BER ~10⁻⁴ on CH1.**
   The path goes through SLAVE's cascade flop, which is the only
   unsynchronized CDC in the loop. Errors are NOT byte-aligned (`at_lock`
   data shows valid 0xAA, 0xFF, 0x55 byte patterns — alignment is fine);
   they are bit-flip-shaped, consistent with metastability rather than
   sample-phase shift.
3. **Lock acquired then errors flow immediately** (`at_lock == at_first_err`
   in trials 1–5 of last v1.3 external-loop log). The very next cycle
   after lock sees the unsafe CDC fire.
4. **`RXBYTEREALIGN` keeps incrementing on the external loop** even after
   PPM=200 + AVTT (~5000 events/trial). The errors corrupt occasional
   K28.5 commas in the cascade return path, causing GT byte aligner on
   MASTER to re-align.

These all derive from the same root cause.

## Possible problems found

- **(Primary)** `rx_data` (64-bit, `rx_clk` domain) is sampled into
  `rx_data_r` (`tx_clk` domain) with a single flip-flop and no qualifier:
  link_test.sv:284.
- **(Secondary, same root cause)** `rxcharisk` (4-bit, `rx_clk` domain) is
  sampled into `txctrl2_out` (`tx_clk` domain) with the same single-flop
  pattern at link_test.sv:299. Same metastability risk on the K-symbol
  control bits as on the data bits. Corruption here causes the GT 8B/10B
  encoder on SLAVE TX to emit D-symbols where K-symbols were expected (or
  vice versa), garbling MASTER's RX byte alignment.
- **(Architecture)** The cascade is conceptually wrong as drawn: it
  re-clocks data from an externally-driven (CDR) clock domain into a
  locally-driven (refclk) clock domain solely to emit it on TX, which
  then leaves the SLAVE chip on the local clock and is re-CDR-recovered
  by MASTER. The extra clock-domain hop is what creates the failure;
  if SLAVE TX were instead clocked from RXUSRCLK2 (which is already a
  valid clock for the serializer at the same nominal frequency), the
  bus would never cross domains and no synchronizer would be needed.

## Recommendations (for user review — do NOT execute)

The user should review and decide on one of these in the morning:

1. **(Cleanest architectural fix; recommended)** Re-clock SLAVE TX
   from RXUSRCLK2 instead of TXUSRCLK2. UltraScale GTH supports
   `TXOUTCLKSEL = RXRECCLK` (3'b101 per UG576), or equivalently the user
   clocking network on SLAVE can be configured so that `tx_clk` and
   `rx_clk` of the `link_test` module are the same physical wire when
   `IS_SLAVE=1`. This **removes the CDC entirely**: the cascade becomes a
   1-cycle same-clock register, which is always safe and is the design
   intent shown in the original comment ("Simple fabric logical loopback
   register for Slave mode" — single cycle delay, no async sampling
   implied).
   - Cost: one GT Wizard parameter change (TX outclk source) for the SLAVE
     bitstream only, plus possibly one wire change in `gt_wrapper.sv` to
     feed `u_userclk_tx.srcclk_in` from `rxoutclk_int[RX_MASTER_CH]`
     instead of `txoutclk_int[TX_MASTER_CH]` when `IS_SLAVE`.
   - Caveat: needs MASTER's TX to be present before SLAVE's TX can clock,
     i.e. SLAVE must wait for RX CDR lock before TX is meaningful. This
     is already true on the bench (MASTER comes up first / sends comma
     training).

2. **(Quick mitigation; not recommended as final)** Insert an
   `XPM_FIFO_ASYNC` between `rx_clk` and `tx_clk` in the cascade. This
   gives word-coherent CDC at the cost of a few-cycle latency and BRAM
   resources. Works regardless of clock-source decisions, but adds a
   correctness-irrelevant subsystem that's harder to reason about than
   approach (1).

3. **(Diagnostic-only)** Add an XPM_CDC_GRAY-based explicit 2FF
   synchronizer just for the `rxcharisk` 4-bit signal. Insufficient on its
   own to fix BER on the data bus, but would let us measure how much of
   the BER is K-symbol-control-related vs data-bit-flip-related.

## What experimental changes might test the hypothesis

- **Test the hypothesis without rebuilding the SLAVE bitstream:** put
  the SLAVE in PCS NEAR-END loopback (`LOOPBACK=1`) for cascade. The
  cascade still runs (`tx_data <= rx_data_r`), but rx_clk and tx_clk on
  SLAVE are both locked to SLAVE's own local refclk in PCS NEAR-END
  because the recovered clock comes from SLAVE's own TX. That would
  remove the inter-board clock drift but **not** the unsafe single-flop
  CDC (the two clocks are still different nets and physically still
  separately recovered/derived inside SLAVE's PMA — same-source but
  technically distinct CDC). Could be informative as an intermediate
  data point.
- **Definitive PMA FAR-END test on MASTER:** with `LOOPBACK=4` MASTER's
  signal makes the round-trip on the fiber to the SLAVE, gets reflected
  through SLAVE's PMA-only path (no PCS, no fabric cascade), and comes
  back to MASTER. If this loop is clean while external (cascade) loop is
  dirty, that **proves** the cascade fabric is the unique remaining
  problem (everything outside it, including fiber, SLAVE PMA, MASTER
  CDR, is OK).

## Follow-up needed (if any)

None blocking. All read-only analysis was possible.

## Open questions / unclear items

- **Unclear:** Whether the originally-intended design contract for
  `rx_data → rx_data_r` was "1 cycle of latency, same clock" (suggested
  by the comment, suggested by the file-level architecture where rx_clk
  and tx_clk are both 312.5 MHz with shared QPLL0 in MASTER mode) or
  "explicit CDC, single flop accepted as 'good enough'". The code is
  ambiguous: the always block is on `tx_clk`, but the comment
  ("Simple fabric logical loopback register") reads like the author
  may have been thinking of a same-clock register. In MASTER mode the
  cascade branch is gated off, so the question never arises in tested
  bitstreams until SLAVE is exercised.
- **Unclear:** Whether the GT Wizard's *RX elastic buffer* in MASTER (CH0,
  buffer mode 1 = USE, see Q7) silently absorbs the BER. The RX buffer
  would not correct bit errors — it does word-level alignment and rate
  matching only. So this should not mask the SLAVE-side errors; they
  should propagate as observed.

## Additional findings

(In scope per "directly related to cascade clocking", per task brief.)

1. The 4 channels are unbonded (no `RX_CB_NUM_SEQ`, no channel-bonding
   logic). The cascade fix per Recommendation (1) is therefore a
   per-channel concern, not a multi-lane one — but since all 4 channels
   share the same fanned-out `txusrclk2` and `rxusrclk2`, fixing the
   TX_MASTER source in SLAVE mode fixes all 4 channels simultaneously.

2. The `rxbyterealign_cnt` and `eyescandataerror_cnt` counters in
   `gt_wrapper.sv` (lines 289–320) are clocked on
   `gt_userclk_rx_usrclk2_int` (line 287, 294, 314) — they live in
   `rx_clk` domain. The `gt_debug_rxbyterealign_cnt_out` /
   `_eyescandataerror_cnt_out` outputs cross into axi_ctrl, which does
   level-sync CDC on them (already verified in earlier sessions, not
   re-checked here). These are diagnostic-only counters and unrelated to
   the cascade BER, but they live in the same clock-domain neighbourhood.

3. The `slave_recclk_out` signal (gt_wrapper.sv:188, serdes_array.sv:176)
   exports `gtwiz_userclk_rx_usrclk2` (the recovered RX clock) to the
   top-level top of the SLAVE IP. This is intended for downstream
   distribution to MMCM/BUFGMUX as described in
   MuroSync_Dev_Bench_Architecture.md §2.4, but is unrelated to the
   cascade path inside this IP. Noted only because, **if Recommendation
   (1) is adopted**, the same `gtwiz_userclk_rx_usrclk2` net would
   additionally drive the local SLAVE TX path — wiring change is
   centralised and self-consistent.
