# MuroSync — Dev Bench Architecture Reference

**Setup:** two-board optical timing dev bench (SLAVE ↔ MASTER over BiDi SFP+)
**Hardware:** 2× AXAU15 (carrier) + 2× ACAU15 (SoM, XCAU15P-2FFVB676I) + 2× FH1223 (FMC SFP+ card)
**Toolchain:** Vivado 2022.2 + Vitis 2022.2 (Windows host)
**Version:** 1.2 (2026-05-26)
**Status:** Authoritative bench reference. Drop this into any new chat alongside `MuroSync_Claude_Context.md` for full standing context.

> Scope: physical and logical architecture of the current MuroSync development
> bench — hardware stack, clock plane, per-channel signal mapping, BD topology,
> IP architecture, IP packaging workflow, bitstream build workflow, firmware
> bring-up, AXI register interface, and critical gotchas accumulated during
> bring-up. Reference-grade: facts only.
>
> **v1.1 changes**: split build section into IP packaging vs bitstream build
> (two distinct workflows); explained `enablement_dependency` mechanism as
> central concept; documented the IS_SLAVE/IS_MASTER localparam fix history;
> added BD topology section; added XSA hardware handoff; corrected clock
> domain count (single 100 MHz BD domain, not two); added ILA debug interface.

---

## 0. TL;DR

- **Two identical hardware stacks**, one runs `murosync_SLAVE.bit`, the other `murosync_MASTER.bit`.
- **Single source IP** (`murosync_serdes_array`) with compile-time `parameter MODE` → two bitstreams from one RTL tree.
- **The trick**: IP exposes **different port name sets** for MASTER vs SLAVE via IP-XACT `enablement_dependency`. Changing `CONFIG.MODE` makes old ports physically vanish; build script then reconnects external BD ports to the new pin names.
- **Single firmware ELF** runs on both boards — reads `IP_INFO` register at boot, dispatches to slave or master bring-up path.
- **Two independent version counters**: IP version (bumped by `update_ip_ports.tcl` on IP re-package, exposed in `IP_INFO[4:23]`) and firmware version (bumped by `gen_murosync_build_info.bat` on every build, exposed in boot banner). They advance at different rates — IP version moves only when RTL changes, firmware version moves on every compile.
- **Optical link**: one BiDi SFP+ pair (1270/1330 nm), single-strand SMF between boards.
- **Line rate**: 6.25 Gbps (dev-board limit, refclk 156.25 MHz × 40), user clock 312.5 MHz.
- **Channel mapping**: linear across every layer — FH1223 cage `SFP(N+1)` → wizard inst `[N]` → `RXBYTEISALIGNED` bit `N` → `ch_mask = 1<<N`.
- **Control**: ASCII over UART-to-ETH (TCP 115200 8N1) → Waveshare module → MicroBlaze UARTLite → AXI.
- **Slave channel** for recovered clock is **always CH0** (X0Y4, cage SFP1).

---

## 1. Physical Hardware

### 1.1 Per-board stack

Each of the two boards is identical hardware:

```
┌──────────────────────────────────────────────┐
│  FH1223 FMC card                             │
│   • 4× SFP+ cages (silkscreen SFP1..SFP4)    │
│   • FMC HPC connector (VITA 57.1)            │
│   • No on-board oscillator (GBTCLK Not Used) │
└──────────────────────────────────────────────┘
              ▲ FMC HPC mate
┌──────────────────────────────────────────────┐
│  AXAU15 carrier (PCIe form-factor)           │
│   • FMC HPC connector                        │
│   • 200 MHz on-board diff oscillator → BD    │
│   • Gigabit Ethernet (mgmt, not in BD)       │
│   • USB-UART (CP2102) — alternate control    │
│   • PCIe 4.0 x4 (unused on bench)            │
│   • 4× SoM connectors CON1..CON4             │
│   • Power: 12V → 5V/3.3V/1.8V/VADJ           │
└──────────────────────────────────────────────┘
              ▲ CON1..CON4 board-to-board (4× 80-pin)
┌──────────────────────────────────────────────┐
│  ACAU15 SoM                                  │
│   • XCAU15P-2FFVB676I (Artix UltraScale+)    │
│   • DDR4 (1 GB × 32-bit @ Bank 66) — NOT used│
│     in current BD (LMB BRAM only)            │
│   • QSPI Flash 256 Mb (Bank 0)               │
│   • On-board oscillator SiT9121AI @ 156.25 MHz│
│     → MGTREFCLK1_225 (pin T7/T6) — GT refclk │
│   • LED + DONE indicators                    │
└──────────────────────────────────────────────┘
```

### 1.2 Hardware inventory (on desk)

| Item | P/N | Qty | Status |
|---|---|---|---|
| AXAU15 carrier | ALINX AXAU15 | 2 | ✓ |
| ACAU15 SoM | ALINX ACAU15 (XCAU15P-2FFVB676I) | 2 | ✓ |
| FH1223 FMC card | ALINX FH1223 (4× SFP+) | 2 | ✓ |
| BiDi SFP+ (slave side) | FS.COM SFP-10G23-BX10 (#36351, TX 1270/RX 1330) | 1 | ✓ |
| BiDi SFP+ (master side) | FS.COM SFP-10G32-BX10 (#36353, TX 1330/RX 1270) | 1 | ✓ |
| Single-strand SMF patch | LC/LC, short | 1 | ✓ |
| Control plane | Waveshare UART-to-ETH module | 2 | ✓ |
| JTAG programmer | AMD-CN2 / Xilinx platform cable | 1 | ✓ |
| Loopback (debug) | FMC SFP+ electrical loopback board | 1 | ✓ |

### 1.3 Two-board topology

```
        ┌──────────────────────┐                       ┌──────────────────────┐
        │      SLAVE board     │                       │     MASTER board     │
        │ (murosync_SLAVE.bit) │                       │ (murosync_MASTER.bit)│
        │                      │                       │                      │
        │   FH1223 cage SFP?   │═════ single-strand ═══│   FH1223 cage SFP?   │
        │    BiDi #36351       │      SMF, BiDi        │    BiDi #36353       │
        │    TX 1270 / RX 1330 │      (1270 ⇄ 1330)    │    TX 1330 / RX 1270 │
        │                      │                       │                      │
        │ JTAG ────┐           │                       │           ┌──── JTAG │
        │ UART ────┼─→ Wavesh. │                       │  Wavesh. ─┼──── UART │
        │          │   UART-   │                       │  UART-    │          │
        │          │   ETH     │                       │  ETH      │          │
        │          │   TCP     │                       │  TCP      │          │
        └──────────┼───────────┘                       └───────────┼──────────┘
                   │                                               │
                   └──→ Host PC (Python/manual ASCII over TCP) ←───┘
```

### 1.4 Control plane

- Each board has a Waveshare UART-to-ETH module bridging the FPGA's UARTLite to a TCP socket.
- **Settings**: 115200 baud, 8N1, no flow control.
- **Protocol**: ASCII line-oriented, terminated by `\n`.
  - `PING` → `OK`
  - `VER` → `OK 0x00010000`
  - `RD 0x<ADDR>` → `OK 0x<DATA>`
  - `WR 0x<ADDR> 0x<DATA>` → `OK`
- **Transport**: TCP → Waveshare → UART → FPGA UARTLite → MicroBlaze.

### 1.5 JTAG / programming

- Single AMD-CN2 (or Xilinx Platform Cable) programmer, moved between boards as needed.
- Used for: bitstream load, ELF programming, ILA debug.
- Once bitstream and ELF are in QSPI flash, JTAG only needed for re-flash or live debug.

### 1.6 ILA debug

The current BD includes an ILA (`bd_murosync_poc_ila_0_0`) clocked by `microblaze_0_Clk` (100 MHz, see §2.3). Live probes:

| Probe | Width | Signal | Use |
|---|---|---|---|
| probe0 | 1 | `link_status_out` | Live link-up status from IP |
| probe1 | 1 | `link_down_latched_out` | Sticky link-down latch |
| probe2 | 4 | `refclk_out` (was `pll_lock_out`) | PLL lock per channel |
| probe3 | 64 | `dbg` | Internal IP debug bus snapshot |

Access via Vivado Hardware Manager → ILA dashboard. Useful when AXI debug is too slow or signal of interest doesn't reach a register.

---

## 2. Clock Architecture

### 2.1 Dev-board reality (current)

Constrained by ACAU15's hardwired SiT9121AI oscillator @ 156.25 MHz. 156.25 MHz is mathematically incompatible with 400 MHz sys_clk (see §2.5). Current bench operates at **312.5 MHz sys_clk inside the IP**.

```
GT line rate:    6.25 Gbps   (156.25 MHz × 40)
Encoding:        8B10B
User data width: 16-bit
RXUSRCLK2:       312.5 MHz   (inside IP — timing plane)
TDC coarse tick: 3.2 ns       (vs 2.5 ns at target)

Inside the IP (not in BD):
  MMCM:
    Input:    156.25 MHz (refclk or recovered)
    VCO:      625 MHz
    CLKOUT0:  312.5 MHz → timing plane (all logic)
```

### 2.2 Reference clock source for GTHE4

| Source | Pin (FPGA) | GTHE4 input | Status |
|---|---|---|---|
| ACAU15 on-board SiT9121AI @ 156.25 MHz | **T7/T6** | MGTREFCLK1_225 | ✓ **Active** |
| FMC_GBTCLK0_M2C (from FH1223) | V7/V6 | MGTREFCLK0_225 | ✗ Not used (FH1223 marks as "Not Used") |

**Note on BD pin name**: In the BD, the IP refclk pins are named `mgtrefclk0_x0y1_n/p` (Quad X0Y1 = Quad 225). This is the Wizard's internal naming convention; despite the `0` in the name, the **XDC** maps these to **MGTREFCLK1** (pin T7/T6) via:
```tcl
set_property PACKAGE_PIN T7 [get_ports gth_ref_p]
set_property PACKAGE_PIN T6 [get_ports gth_ref_n]
```

### 2.3 Clock domains in the dev-board BD

**Single 100 MHz domain in BD.** All BD logic — MicroBlaze, AXI Interconnect, AXI UARTLite, ILA, and the IP's AXI slave + GT freerun — run on one clock `microblaze_0_Clk = 100 MHz`, generated by `clk_wiz_0` from the 200 MHz external diff oscillator.

```
Board 200 MHz diff (LVDS, AXAU15) ──→ clk_wiz_0 ──→ 100 MHz (microblaze_0_Clk)
                                                          │
                                                          ├──→ microblaze_0 (CPU clk)
                                                          ├──→ AXI Interconnect ACLK
                                                          ├──→ axi_uartlite_0.s_axi_aclk
                                                          ├──→ murosync_serdes_array_0.s00_axi_aclk
                                                          ├──→ murosync_serdes_array_0.hb_gtwiz_reset_clk_freerun_in
                                                          └──→ ila_0 clk
```

**Inside the IP, three additional clock domains exist** (not visible at BD level):
- 312.5 MHz (RXUSRCLK2 = TXUSRCLK2) = sys_clk = timing plane
- 156.25 MHz recovered RX clock (from CDR) — used internally for recclk export
- The 100 MHz freerun comes IN from BD as the GT reset FSM freerun

So total: 1 clock at BD level, 3 inside IP, 1 CDC boundary between them (100 MHz BD ↔ 312.5 MHz IP timing plane via toggle synchronizers).

### 2.4 BUFGMUX (inside IP)

```
              ┌──────────────────────┐
   T7 ────────┤ input0 (local 156.25)│
   refclk     │                      │
              │      BUFGMUX         ├──→ MMCM input ──→ 312.5 MHz sys_clk
   slave_     │                      │                ┘
   recclk ────┤ input1 (recovered)   │
   from CH0   └──────────────────────┘
              select: 1 if slave_link_up else 0
              note: MMCM RESET pulse required on switchover
```

### 2.5 Target hardware (future, NOT current bench)

Target FMC card will populate a **160 MHz refclk** source (Si5341 or fixed osc) into MGTREFCLK0_225. This unlocks:

```
GT line rate:    8.0 Gbps   (160 MHz × 50)
RXUSRCLK2:       400 MHz = sys_clk
TDC coarse tick: 2.5 ns
```

Math reason 156.25 MHz cannot reach 400 MHz:
```
156.25 = 625/4   →   400 / (625/4) = 1600/625 = non-integer K
```
No combination of encoding × data width × PLL dividers makes 156.25 → 400 work. Hard hardware constraint, requires PCB change.

**Rule for all RTL on the bench**: code is written for 312.5 MHz; comments note "// 312.5 MHz (dev board) / 400 MHz (target custom PCB)". Migration to 400 MHz changes only GT Wizard parameters, not RTL.

---

## 3. Channel Mapping

### 3.1 Master table — RX path (cage → AXI bit)

| FH1223 silkscreen | FMC HPC RX pins | FMC DP | ACAU15 SoM | ACAU15 CON4 PIN | FPGA pin (P/N) | GTHE4 site | GT Wizard inst | RTL signal (SLAVE) | RTL signal (MASTER) | `RXBYTEISALIGNED` bit | `ch_mask` |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **SFP1** | C6/C7 | DP0_M2C | 225_RX0 | PIN34 | Y2/Y1 | X0Y4 | `[0]` | `muro_gth_slave` | `muro_gth_master_0` | bit 0 | `0x1` |
| **SFP2** | A2/A3 | DP1_M2C | 225_RX1 | PIN40 | V2/V1 | X0Y5 | `[1]` | `muro_gth_aux_0` | `muro_gth_master_1` | bit 1 | `0x2` |
| **SFP3** | A6/A7 | DP2_M2C | 225_RX2 | PIN46 | T2/T1 | X0Y6 | `[2]` | `muro_gth_aux_1` | `muro_gth_master_2` | bit 2 | `0x4` |
| **SFP4** | A10/A11 | DP3_M2C | 225_RX3 | PIN52 | P2/P1 | X0Y7 | `[3]` | `muro_gth_aux_2` | `muro_gth_master_3` | bit 3 | `0x8` |

### 3.2 Master table — TX path (cage → FPGA)

| FH1223 silkscreen | FMC HPC TX pins | FMC DP | ACAU15 SoM | ACAU15 CON4 PIN | FPGA pin (P/N) | GTHE4 site | GT Wizard inst |
|---|---|---|---|---|---|---|---|
| **SFP1** | C2/C3 | DP0_C2M | 225_TX0 | PIN33 | AA5/AA4 | X0Y4 | `[0]` |
| **SFP2** | A22/A23 | DP1_C2M | 225_TX1 | PIN39 | W5/W4 | X0Y5 | `[1]` |
| **SFP3** | A26/A27 | DP2_C2M | 225_TX2 | PIN45 | U5/U4 | X0Y6 | `[2]` |
| **SFP4** | A30/A31 | DP3_C2M | 225_TX3 | PIN51 | R5/R4 | X0Y7 | `[3]` |

### 3.3 GT Quad / PLL

| Property | Value |
|---|---|
| GTHE4 Common | `GTHE4_COMMON_X0Y1` |
| GTHE4 Channels | X0Y4, X0Y5, X0Y6, X0Y7 |
| PLL | QPLL0 (shared, one Common per Quad) |
| `IO_BUFFER_TYPE` on serial pins | `NONE` (not `BUFFER_TYPE` — that's legacy) |

### 3.4 RTL packing (from `murosync_serdes_array.sv`)

```systemverilog
// MODE = "SLAVE": CH0 is the slave optical input, CH1..3 are aux outputs
wire [3:0] gthrxn_int_slave  = {
    muro_gth_aux_2_rxn,    // bit 3 → wizard[3] → X0Y7 → SFP4 cage
    muro_gth_aux_1_rxn,    // bit 2 → wizard[2] → X0Y6 → SFP3 cage
    muro_gth_aux_0_rxn,    // bit 1 → wizard[1] → X0Y5 → SFP2 cage
    muro_gth_slave_rxn     // bit 0 → wizard[0] → X0Y4 → SFP1 cage
};

// MODE = "MASTER": all four are downstream master outputs
wire [3:0] gthrxn_int_master = {
    muro_gth_master_3_rxn, // bit 3 → wizard[3] → X0Y7 → SFP4 cage
    muro_gth_master_2_rxn, // bit 2 → wizard[2] → X0Y6 → SFP3 cage
    muro_gth_master_1_rxn, // bit 1 → wizard[1] → X0Y5 → SFP2 cage
    muro_gth_master_0_rxn  // bit 0 → wizard[0] → X0Y4 → SFP1 cage
};

wire [3:0] gthrxn_int = IS_SLAVE ? gthrxn_int_slave : gthrxn_int_master;
```

**Invariant:** `bit N of gthrxn_int` ≡ `wizard inst [N]` ≡ `GTHE4_CHANNEL_X0Y(4+N)` ≡ `cage SFP(N+1)`. Linear at every layer.

### 3.5 `ch_mask` cheat sheet

| Cage | `ch_mask` | Verify: `RXBYTEISALIGNED ==` |
|---|---|---|
| SFP1 only | `0x1` | `0x1` |
| SFP2 only | `0x2` | `0x2` |
| SFP3 only | `0x4` | `0x4` |
| SFP4 only | `0x8` | `0x8` |
| All four | `0xF` | `0xF` |

### 3.6 Diagnostic register bit mapping

Bit `N` = channel `N` = wizard `[N]` = cage `SFP(N+1)`.

| Field | Bits | Meaning |
|---|---|---|
| `STATUS.pll_lock` | [19:16] | bit `16+N` = QPLL0 lock for channel `N` |
| `STATUS.gtpowergood` | [23:20] | bit `20+N` = GT power good for channel `N` |
| `STATUS.txpmaresetdone` | [27:24] | bit `24+N` = TX PMA reset done |
| `STATUS.rxpmaresetdone` | [31:28] | bit `28+N` = RX PMA reset done |
| `RXBYTEISALIGNED` | [3:0] | bit `N` = 8B10B byte alignment on channel `N` |
| `err_cnt[N]`, `wrd_cnt[N]` | per-ch | indexed by channel `N` |

### 3.7 Recovered clock export

| Parameter | Value |
|---|---|
| Source channel | CH0 = wizard `[0]` = X0Y4 = cage SFP1 |
| Output port | `slave_recclk_out` (top-level, SLAVE mode only) |
| Frequency | 156.25 MHz (recovered, /40 from 6.25 Gbps line) |
| Usage | BUFGMUX input1 → MMCM → 312.5 MHz sys_clk |
| Parameter | `RX_MASTER_CH = 0` |

### 3.8 Naming convention: silkscreen is 1-indexed, RTL is 0-indexed

The FH1223 board silkscreen labels SFP cages `SFP1..SFP4`. RTL port names
and XDC pin assignments are 0-indexed (`sfp0_*..sfp3_*`). The two are off
by 1: silkscreen `SFP(N+1)` corresponds to wizard inst `[N]`, FPGA pin pair
`sfp<N>_rx_*/tx_*`, and `RXBYTEISALIGNED` bit `N`. When debugging via UART
reads, always think in 0-indexed terms — `RXBYTEISALIGNED = 0x2` means
bit 1 is set, which is wizard `[1]` = cage `SFP2`. See also Lesson 17 in §8.

---

## 4. IP Architecture — `murosync_serdes_array`

### 4.1 File hierarchy

```
murosync_serdes_array.sv                  (top-level IP, integration)
  ├── murosync_serdes_array_axi_ctrl.sv   (AXI4-Lite register map + CDC)
  │     └── murosync_serdes_array_S00_AXI.sv
  ├── murosync_serdes_link_test.sv        (TX pattern gen + RX checker FSM)
  └── murosync_gt_wrapper.sv              (GT Wizard instantiation)
        ├── murosync_gt_userclk_tx.sv     (TX user clock divider)
        ├── murosync_gt_userclk_rx.sv     (RX user clock divider)
        ├── murosync_gtwizard_ports.sv    (stable port isolation layer)
        └── gtwizard_ultrascale_0         (Xilinx GT Wizard IP)
```

Packaged as IP-XACT, lives in `gateware/ip/murosync_serdes_array/`.

### 4.2 Single parameterized IP — `parameter MODE` + `enablement_dependency`

This is **the central mechanism** that turns one IP source into two distinct bitstreams. It works in two halves: a `parameter` declared in RTL, plus an IP-XACT `enablement_dependency` on every port that's mode-specific.

```systemverilog
module murosync_serdes_array #(
    parameter string MODE = "MASTER"  // "MASTER" or "SLAVE"
) (
    // Port groups conditionally exposed:
    //   muro_gth_slave_*       — enabled when MODE == "SLAVE"
    //   muro_gth_aux_{0,1,2}_* — enabled when MODE == "SLAVE"
    //   slave_recclk_out       — enabled when MODE == "SLAVE"
    //   muro_gth_master_{0..3}_* — enabled when MODE == "MASTER"
    ...
);
    localparam IS_SLAVE  = (MODE == "SLAVE");
    localparam IS_MASTER = (MODE == "MASTER");
    // ...
endmodule
```

**`enablement_dependency` semantics**: in IP-XACT (`component.xml`), each port can carry an expression that determines whether the port is **present at all** in instantiations of that IP. When `MODE == "SLAVE"`:
- All `muro_gth_slave_*` and `muro_gth_aux_*` and `slave_recclk_*` ports **exist** on the IP cell in the BD.
- All `muro_gth_master_*` ports **do not exist** — they're not present in the netlist, no pins to connect.

When MODE flips to MASTER, the situation reverses. Vivado does dead-code elimination per instance: a MASTER bitstream has zero gates for the SLAVE cascade loopback logic, and vice versa.

**The `enablement_dependency` is configured by `update_ip_ports.tcl`** (see §5.2), not declared inline in RTL. The script attaches the expressions to ports by name pattern.

### 4.3 IS_SLAVE / IS_MASTER must be `localparam`, not `parameter` — historical bug

`IS_SLAVE` and `IS_MASTER` derive from `MODE` and are used throughout RTL. They could in principle be declared as module parameters with default values, but they must NOT — and there's a real bug story behind why.

**Earlier project versions** declared them as parameters and tried to hide them from the IP Customization GUI via `ipgui::remove_param`. This had a subtle catastrophic effect:

> `ipgui::remove_param` **froze their values in component.xml as compile-time constants** (`IS_SLAVE=false`, `IS_MASTER=true`). Changing `CONFIG.MODE` in BD no longer re-evaluated them — the IP always ran as MASTER regardless of the selected MODE.

A SLAVE bitstream would build, link successfully, expose the SLAVE port set, but the IS_SLAVE-gated logic inside (cascade loopback, etc.) would not be active. The bug only manifested at runtime, in confusing ways.

**Fix**: declare both as `localparam` inside the RTL body. IP Packager does not see them at all; the synthesizer re-evaluates them at elaboration time based on the current `MODE`. The `update_ip_ports.tcl` script explicitly notes this and does NOT include `IS_SLAVE`/`IS_MASTER` in its `params_to_hide` list.

### 4.4 SLAVE-mode behaviors

- **Cascade loopback** (round-trip BER mechanism): `tx_data <= rx_data_r`, `txcharisk <= rxcharisk_r`. Slave echoes RX data back to TX so master can run end-to-end BER over fiber.
- **TXCHARISK echo** must mirror RXCHARISK (not zeros) to preserve K-symbols — see Lesson §8 commit `6052c75`.
- **Recovered clock export** via `slave_recclk_out` from CH0.
- **TX comma FSM**: disabled. Slave does not initiate alignment; it follows.
- **RX checker FSM**: disabled. The `RX_ST_IDLE → ST_CAPTURE_CFG` transition is gated by `!IS_SLAVE`.

### 4.5 MASTER-mode behaviors

- **TX pattern generator**: FIXED / TOGGLE / COUNTER modes selectable via `TEST_CFG.mode[1:0]`.
- **TX comma FSM**:
  - `TRAIN_LEN = 4096`: initial K28.5 burst (~13 µs at 312.5 MHz) for CDR lock + byte alignment.
  - `MAINTENANCE`: subsequently inject one K28.5 every `COMMA_PERIOD = 1024` cycles (~3.3 µs).
- **RX checker FSM** states: `IDLE → CAPTURE_CFG → WAIT_ALIGN → SEARCH → LOCKED`.
- **Diagnostic snapshots**: Tier 1 (`time_to_lock`, `rx_data_at_lock`) and Tier 2 (`rx_data_at_first_err`, `exp_data_at_first_err`) latched per channel.

### 4.6 CDC architecture

The IP itself bridges between BD-level 100 MHz (AXI / freerun) and internal 312.5 MHz timing plane:

- **Control pulses** (axi → tx/rx): `murosync_cdc_slow_to_fast.sv`, toggle-based, `SYNC_STAGES = 5`.
- **Status / counters** (tx/rx → axi): `murosync_cdc_fast_to_slow.sv`, toggle-based.
- **Per-channel enables** (freerun → tx/rx clk): 4× `murosync_cdc_level_sync` (2 stages).
- **Per-channel observables** (`rxbyteisaligned`, `err_cnt`, `wrd_cnt`): 2-FF synchronizer in `murosync_serdes_array_axi_ctrl`.

Critical: `hb_gtwiz_reset_clk_freerun_in` must be a stable fabric clock. In the current BD it's `microblaze_0_Clk = 100 MHz` — correct (NOT a GT-derived clock — GT reset FSM won't complete otherwise).

### 4.7 `IP_INFO` runtime identity register

- **Offset**: `0x074`, RO.
- **Purpose**: lets firmware determine at boot which bitstream is running.
- **Encoding**:
  - bit 0: `IS_SLAVE`
  - bit 1: `IS_MASTER`
  - bits 31:8: version, num_channels, build flags
- **Confirmed values**:
  - MASTER bitstream → `IP_INFO = 0x04000112` (IS_MASTER=1)
  - SLAVE bitstream → `IP_INFO = 0x04000111` (IS_SLAVE=1)

### 4.8 IP versioning (auto-bump)

`murosync_serdes_array.sv` carries two parameters as the source of truth for IP version:

```systemverilog
parameter integer IP_VERSION_MAJOR = 1;
parameter integer IP_VERSION_MINOR = N;  // auto-bumped by update_ip_ports.tcl
```

When `update_ip_ports.tcl` runs (see §5.2), it:
1. Reads `IP_VERSION_MAJOR` and `IP_VERSION_MINOR` from RTL
2. Increments MINOR by 1
3. Writes new MINOR back to RTL via `regsub`
4. Calls `set_property version $MAJOR.$MINOR` on the IP core
5. Bumps `core_revision` (Vivado-internal cache invalidation counter)

**MAJOR bump**: manual. Edit RTL, change MAJOR, reset MINOR to 0. Next script run will increment 0 → 1.

This ensures every re-package produces a distinguishable IP version, so BD instances always see the latest logic (otherwise Vivado may cache and reuse stale).

**Firmware has an independent version counter** managed by `gen_murosync_build_info.bat` — see §6.2 for details. Two counters, two scripts, two different bump conditions. The IP version moves on RTL changes; the firmware version moves on every compile (including failed compiles — see Lesson 18 in §8).

---

## 5. Build Process — Two Workflows

There are **two distinct workflows**, both Tcl-driven, that must not be conflated:

| Workflow | Script | When to run | Where to run |
|---|---|---|---|
| **A. IP packaging** | `update_ip_ports.tcl` | After modifying IP source RTL or IP-XACT metadata | Vivado **IP Packager** tab (interactive) |
| **B. Bitstream build** | `build_bitstream.tcl` | To produce `.bit` + `.xsa` artifacts | Vivado **batch mode** (CLI) |

Workflow A is **infrequent** (only on IP RTL changes). Workflow B is **frequent** (every time you want a new bitstream).

### 5.1 Working tree layout

```
C:\murosync\
  murosync-reference\           ← public repo (gateware + firmware source)
    gateware\ip\murosync_serdes_array\
      src\
        murosync_serdes_array.sv        ← IP top, with IP_VERSION params
        ...
      update_ip_ports.tcl                ← Workflow A
      component.xml                      ← IP-XACT (auto-modified by A)
    firmware\
  murosync-core-pro\            ← private repo (proprietary timing + IP notebook)

C:\_vivado\
  murosync_poc_v1\              ← Vivado workdir (live, generated)
    murosync_poc_v1.xpr
    scripts\
      build_bitstream.tcl                ← Workflow B
      build_master.bat                   ← Workflow B wrapper
      build_slave.bat                    ← Workflow B wrapper
      build_both.bat                     ← Workflow B wrapper
    bitstreams\                          ← Workflow B output
      murosync_MASTER.bit
      murosync_MASTER.xsa
      murosync_SLAVE.bit
      murosync_SLAVE.xsa
```

### 5.2 Workflow A — IP Packaging (`update_ip_ports.tcl`)

**When to run**: after editing any IP source RTL, or after changing IP-XACT metadata that needs to be normalized.

**Where to run**: in Vivado, in the IP Packager workspace, with `component.xml` open. Tcl Console:
```tcl
source update_ip_ports.tcl
```

**What it does** (3 responsibilities):

1. **Auto-bump IP version** (see §4.8):
   - reads `IP_VERSION_MAJOR/MINOR` from RTL,
   - increments MINOR,
   - regsub back into RTL file,
   - syncs to `<spirit:version>` on the IP core,
   - bumps `core_revision` for Vivado cache.

2. **Assign `enablement_dependency` on ports** (see §4.2) by name pattern:
   - `*slave*` → `$MODE == "SLAVE"`
   - `*aux*` → `$MODE == "SLAVE"`
   - `*master*` → `$MODE == "MASTER"`
   - For **input** ports also sets `driver_value 0` so disabled inputs are tied off.

3. **Hide internal/derived parameters** from the Customization GUI (`IP_VERSION_MAJOR/MINOR`, `C_S00_AXI_*`, `OPT_MEM_ADDR_BITS`, `ADDR_WIDTH_NEEDED`). Uses `ipgui::remove_param` + `value_resolve_type dependent` so values still re-evaluate per instance (NOT frozen — see §4.3 for the cautionary tale).

**After running**: manually click **Review and Package → Re-Package IP** in the GUI. Then refresh the IP catalog in the project that uses this IP (`update_ip_catalog`).

### 5.3 Workflow B — Bitstream Build (`build_bitstream.tcl`)

**When to run**: every time you want a fresh `.bit` + `.xsa` for either MASTER or SLAVE.

**Where to run**: Windows CMD via `.bat` wrappers (see §5.4). Vivado must be **closed** before invocation (the script opens the project itself).

**Why it exists — the core problem it solves**:

The IP's port set physically **changes between modes**. When `set_property CONFIG.MODE` is applied to the IP cell, Vivado:
1. Disables ports that are no longer enabled (`enablement_dependency` evaluates false)
2. **Silently deletes the nets attached to those disabled ports** (BD emits warnings `BD 41-1684`)
3. Enables the now-active ports — but they have **different names**

The external BD ports (`GTH_IN_CH{0..3}_RX_*`, `GTH_OUT_CH{0..3}_TX_*`) still exist (they're top-level ports of the BD, independent of MODE). But after the switch, they're **dangling** — nothing connects them to the IP. **The build script's central job is to reconnect them to the new IP pin names.**

**Channel-to-pin mapping in the script**:

```tcl
if {$mode eq "MASTER"} {
    # CH0..3 each connect to muro_gth_master_{0..3}
    set channel_map {
        {0 muro_gth_master_0 muro_gth_master_0}
        {1 muro_gth_master_1 muro_gth_master_1}
        {2 muro_gth_master_2 muro_gth_master_2}
        {3 muro_gth_master_3 muro_gth_master_3}
    }
} else {
    # SLAVE: CH0 = sync link, CH1..3 = aux channels
    set channel_map {
        {0 muro_gth_slave   muro_gth_slave}
        {1 muro_gth_aux_0   muro_gth_aux_0}
        {2 muro_gth_aux_1   muro_gth_aux_1}
        {3 muro_gth_aux_2   muro_gth_aux_2}
    }
}
```

For each channel, the script reconnects 4 nets (RX_N, RX_P, TX_N, TX_P) → 16 connections total.

**Idempotency** (`ensure_connection` helper): if a port is already connected to the right pin, skip. If connected to a different pin (because BD remembers the previous build), delete the old net and create the new one. This makes the script safe to re-run, and means **a fresh project state and a re-build state both produce the same result**.

**Full step sequence**:

```
1. Open project (C:/_vivado/murosync_poc_v1/murosync_poc_v1.xpr)
2. Open BD (bd_murosync_poc)
3. set_property CONFIG.MODE $MODE [get_bd_cells murosync_serdes_array_0]
   → Old ports vanish, their nets are deleted (warnings expected)
4. Reconnect external ports for new MODE (16 nets, idempotent)
5. validate_bd_design + save_bd_design
6. generate_target all $bd_file (wrapper, hwdef, etc.)
7. reset_run synth_1 + launch_runs synth_1 -jobs 8 + wait_on_run
8. launch_runs impl_1 -to_step write_bitstream -jobs 8 + wait_on_run
9. Copy .bit to bitstreams\murosync_<MODE>.bit
10. write_hw_platform -fixed -include_bit -force bitstreams\murosync_<MODE>.xsa
11. close_project
```

**Build time**: 45-60 min per mode (synth + impl + bitstream, 8 jobs).

### 5.4 `.bat` wrappers (CMD invocation)

Three wrappers exist:

| Wrapper | Action | Behavior |
|---|---|---|
| `build_master.bat` | Build MASTER only | `vivado -mode batch -source build_bitstream.tcl -tclargs MASTER` |
| `build_slave.bat` | Build SLAVE only | `vivado -mode batch -source build_bitstream.tcl -tclargs SLAVE` |
| `build_both.bat` | Build MASTER then SLAVE | Sequential, MASTER first; aborts SLAVE if MASTER fails (~1.5-2h total) |

All wrappers:
- Hard-code paths to `vivado.bat` (`C:\Xilinx\Vivado\2022.2\bin\vivado.bat`) and the build script (`C:\_vivado\murosync_poc_v1\scripts\build_bitstream.tcl`)
- `pause` at end of run to keep the CMD window open for log inspection
- Return errorlevel 1 on failure (sequential wrapper uses this to skip SLAVE if MASTER failed)

**Convention**: double-click in Explorer, or run from CMD. Vivado **must be closed** beforehand or the project lock will block.

### 5.5 BD file on disk is an artifact, not a source

After a successful build the BD file (`bd_murosync_poc.bd` and generated `.v`) reflects the **last MODE** that was built. This is normal — the build script overwrites BD state each invocation. Don't treat BD contents as the source of truth when reasoning about both modes: the source of truth is `build_bitstream.tcl` (which describes both modes explicitly) plus IP-XACT `enablement_dependency` rules.

### 5.6 Output artifacts

| Artifact | Path | Purpose |
|---|---|---|
| MASTER bitstream | `C:\_vivado\murosync_poc_v1\bitstreams\murosync_MASTER.bit` | Flash to master board (JTAG or QSPI) |
| MASTER hardware platform | `C:\_vivado\murosync_poc_v1\bitstreams\murosync_MASTER.xsa` | Import in Vitis to build firmware ELF for MASTER (bitstream embedded with `-include_bit`) |
| SLAVE bitstream | `C:\_vivado\murosync_poc_v1\bitstreams\murosync_SLAVE.bit` | Flash to slave board |
| SLAVE hardware platform | `C:\_vivado\murosync_poc_v1\bitstreams\murosync_SLAVE.xsa` | Vitis platform for SLAVE firmware |
| Firmware ELF | `<Vitis workspace>\<app>\Debug\<app>.elf` | Same ELF works on both boards (dispatches via `IP_INFO`) |

**The XSA flow**: `write_hw_platform -fixed -include_bit -force` generates a Vitis-compatible static (non-extensible) hardware platform with bitstream embedded. Vitis imports it as a Platform Project; an Application Project sits on top. When the application is flashed, the XSA's embedded bitstream programs the FPGA first.

---

## 6. Firmware Architecture

The firmware is a single bare-metal application running on the MicroBlaze soft
core. One ELF binary is built once and runs on both boards — the bitstream
identity is read at boot via `IP_INFO` and the bring-up path branches
accordingly. The codebase lives directly inside the `murosync-reference`
repository under `firmware/`, so a clone-and-build cycle produces both the
hardware platform (from the XSA in `gateware/vivado/.../bitstreams/`) and the
firmware on the same checkout.

### 6.1 Repository layout

```
firmware/
├── .cproject              ← Eclipse/Vitis project descriptor
├── .project               ← Eclipse project metadata
├── murosync_poc_fw.prj    ← Vitis app project file
├── vitis_export_archive.ide.zip ← exported Vitis IDE state
├── src/
│   ├── main.c                       ← entry point (this section, §6.3)
│   ├── murosync_serdes_driver.c/.h  ← SERDES driver (§6.6)
│   ├── murosync_serdes_regs.h       ← AXI register map (offsets + bit masks)
│   ├── murosync_build_info.h        ← auto-generated, see §6.2
│   ├── platform.c/.h                ← Vitis BSP boilerplate (UART/cache init)
│   ├── platform_config.h            ← Vitis BSP config (UART, stdout, cache flags)
│   ├── lscript.ld                   ← linker script (LMB BRAM layout)
│   └── helloworld.c                 ← legacy template stub, unused
├── cmd/
│   ├── gen_murosync_build_info.bat  ← version bump + build_info.h generator
│   └── murosync_version_state.txt   ← persistent counter state (MAJOR SUB)
├── Debug/                  ← build output: .elf, .size, .build.ui.log
└── _ide/
    ├── bitstream/          ← bitstream picked up by Vitis "Run on Hardware"
    └── hwspec.checksum     ← XSA freshness tracking
```

**Vitis workspace location.** The Vitis IDE workspace is the `firmware/`
directory itself — `.cproject` and `.project` live here, the Debug output goes
to `firmware/Debug/`. There is no separate workspace under
`C:\Users\mikha\workspace_murosync\` in normal use; that path, if it exists,
is either an older import or has been retired. The repo-local workspace is the
single source of truth.

**Single ELF for both boards.** The application project is built once (linked
against the BSP generated from `murosync_MASTER.xsa` — register interface is
identical to SLAVE, so the same ELF runs on both boards). At boot, the
firmware reads `IP_INFO` (offset `0x074`) and dispatches to MASTER or SLAVE
bring-up. This is the third layer of the unification principle from the
Hardware Unification Concept document: one PCB, one bitstream-per-mode, one
firmware ELF.

### 6.2 Build metadata and versioning

The firmware carries **its own version counter**, independent from the IP
version counter described in §4.8. Two numbers are exposed at boot:

| Counter | Bumped by | Storage | Visible at boot |
|---|---|---|---|
| **IP version** (e.g. v1.1) | `update_ip_ports.tcl` on every IP re-package | RTL `parameter IP_VERSION_MAJOR/MINOR` → `IP_INFO[4:23]` | "IP version: v1.1" in `[MUROSYNC] === IP INFO ===` |
| **Firmware version** (e.g. v1.82) | `gen_murosync_build_info.bat` on every firmware build | `cmd/murosync_version_state.txt` → `src/murosync_build_info.h` | "Firmware : v1.82 (code 65618)" in banner |

The two are bumped under different conditions (RTL change vs. firmware
recompile), so they advance at different rates. Both are printed at startup;
the firmware version also includes a UTC build timestamp.

**Build info generator** (`cmd/gen_murosync_build_info.bat`) is invoked as a
pre-build step from the Vitis project. On each run:

1. Reads `cmd/murosync_version_state.txt` (current `MAJOR SUB`).
2. If `MAJOR` in the script (currently `1`) differs from the stored one, resets
   `SUB` to 0. Otherwise increments `SUB` by 1.
3. Writes new state back to `murosync_version_state.txt`.
4. Captures UTC unix time + human-readable time via PowerShell.
5. Generates `src/murosync_build_info.h` with `MUROSYNC_VERSION_MAJOR/SUB/CODE`
   and `MUROSYNC_BUILD_UNIX_TIME / TIME_STR` defines.
6. Computes a compact version code as `MAJOR*65536 + SUB` (currently `65618`
   for v1.82) — a single 32-bit integer that uniquely identifies the build.

**MAJOR bump:** edit the script (`set MAJOR=2`). Next run will reset `SUB` to 1.

**State file is committed.** `cmd/murosync_version_state.txt` lives in git, so
the counter is monotonic across machines and clones — not a per-machine
counter. After every successful build, `git add cmd/murosync_version_state.txt`
+ `git commit` is part of the normal session-end workflow.

### 6.3 Boot flow

`main()` executes a fixed sequence: platform init → banner → identify →
mode-specific bring-up → main loop. The high-level structure:

```c
int main(void) {
    init_platform();             // UART, cache, BSP init
    usleep(1000000);             // 1s settle (give UART-to-ETH bridge time)
    murosync_print_banner();

    murosync_ip_info_t info;
    if (murosync_app_identify(&info) != XST_SUCCESS) return XST_FAILURE;

    int rc;
    switch (info.mode) {
        case MUROSYNC_MODE_MASTER: rc = murosync_app_bringup_master(); break;
        case MUROSYNC_MODE_SLAVE:  rc = murosync_app_bringup_slave();  break;
        default: return XST_FAILURE;
    }
    if (rc != XST_SUCCESS) return XST_FAILURE;

    murosync_app_main_loop(&info);  // never returns
    return 0;
}
```

**Boot banner** is printed unconditionally and is the first signal that the
firmware is alive (UART-to-ETH receives this on TCP connect):

```
============================================================
                    M U R O S Y N C
      High-Precision Optical Timing & Synchronization
============================================================
 Platform : FPGA  XCAU15P
 CPU      : MicroBlaze
 Firmware : v1.82  (code 65618)
 Build    : GT Bring-Up
 Built at : 2026-05-25 21:19:58 UTC
            (1779743997 UTC)
============================================================
```

**Identify step** (`murosync_app_identify`) does two things before any GT
activity:

1. AXI self-test: `TEST_CONST` read (expects `0x4D55524F` = "MURO"), then
   `TEST_SCRATCH` write/read with several patterns. If either fails, prints
   `[MUROSYNC][FATAL] AXI selftest ... FAILED` and the bring-up aborts.
2. `IP_INFO` read and decode into `murosync_ip_info_t { mode, version_major,
   version_minor, num_channels, raw }`. Prints to UART as
   `[MUROSYNC] === IP INFO ===` block. Mode is derived from `IS_SLAVE` /
   `IS_MASTER` bits — exactly one must be set; both clear or both set yields
   `MUROSYNC_MODE_UNKNOWN` and an abort.

Expected `IP_INFO` values on the current bench:
- MASTER bitstream → `0x04000112` (IS_MASTER=1, ver=1.1, num_ch=4)
- SLAVE bitstream → `0x04000111` (IS_SLAVE=1, ver=1.1, num_ch=4)

### 6.4 Bring-up flows: MASTER vs SLAVE

The two flows are deliberately asymmetric. MASTER runs the full validation
chain because it owns the TX pattern generator and RX checker (both gated by
`!IS_SLAVE` in RTL — see IP Internals §1). SLAVE has no link-test logic in
silicon at all and acts as a pure cascade repeater — it can confirm GT
alignment but cannot self-validate the data path.

**MASTER flow** (`murosync_app_bringup_master`):

```c
bring_up_with_bist(LOOPBACK_NONE, 5_000_000)   // §6.5
print_gt_ground_truth("post bring-up")
run_all_channels_smoke_test()                  // 500ms FIXED 0xAAAAAAAA, all ch
print_gt_ground_truth("post smoke test")
```

The orchestrator brings the link up in NEAR-END PCS loopback, runs the BIST
(self-validation inside the FPGA, no fiber needed), then switches to
`LOOPBACK_NONE` (external optical) for the smoke test. The smoke test
exercises the same `run_link_test` engine over fiber, which is the path that
matters for production.

**SLAVE flow** (`murosync_app_bringup_slave`):

```c
bring_up(LOOPBACK_NONE, 5_000_000)
print_gt_ground_truth("post bring-up")
```

No BIST, no smoke test — because both require an active TX pattern generator
and RX checker which the SLAVE bitstream lacks. The bring-up only confirms
that GT comes up, CDR locks, and bytes align. The full validation of a SLAVE
requires a working MASTER on the other end of the fiber, sending a known
pattern that the SLAVE echoes back via cascade loopback for the MASTER's
checker to score.

**Why no BIST on SLAVE matters operationally:** if you only have a SLAVE-built
board on the bench, you cannot self-test it. The boot will reach "link up,
STATUS=0xFFFF0001" but that proves only the SerDes is functional, not the
end-to-end data path. Bench validation always needs both boards.

### 6.5 Boot Self-Test (BIST)

BIST validates the SERDES subsystem end-to-end inside the FPGA using
**NEAR-END PCS loopback** — no external SFP, no fiber, no second board
required. It is intentionally separate from the GT bring-up itself: bring-up
proves the transceiver is alive, BIST proves the data path through it carries
patterns intact.

**Result encoding.** BIST returns a 32-bit bitmask where each bit is a
specific failure mode. `0` = pass, any non-zero bit = that check failed. The
encoding is **fail-bits-set**, not pass-bits-set — this lets the function
start with all bits set ("nothing has passed yet") and clear each bit as the
check confirms success, which is symmetric with how a watchdog would work.

| Bit | Define | Meaning |
|---|---|---|
| `[0]` | `TEST_RESULT_AXI_FAIL` | AXI selftest failed (TEST_CONST / TEST_SCRATCH) |
| `[1]` | `TEST_RESULT_BRINGUP_FAIL` | GT never reached link-up |
| `[2]` | `TEST_RESULT_BIST_NO_DATA` | link test produced no data (wrd_cnt = 0) |
| `[3]` | `TEST_RESULT_BIST_GLOBAL_ERR` | global err_cnt > 0 |
| `[4]` | `TEST_RESULT_BIST_PER_CH_ERR` | any per-channel err_cnt > 0 |
| `[5]` | `TEST_RESULT_BIST_NOT_LOCKED` | FSM never reached LOCKED (ever_locked = 0) |
| `[6]` | `TEST_RESULT_BIST_AT_LOCK_VOID` | at_lock snapshot was not taken |
| `[15:7]` | reserved | future BIST extensions |
| `[31:16]` | reserved | future external-test results |

`TEST_RESULT_PASS = 0`. `TEST_RESULT_ALL_FAIL_MASK = 0x0000007F` (all 7 named
bits, used as initial value).

**Two-layer responsibility.** `murosync_serdes_bist()` only checks BIST-scope
bits (`[2:6]`); it leaves `AXI_FAIL` and `BRINGUP_FAIL` (`[0:1]`) set because
they're outside its scope. The orchestrator
`murosync_serdes_bring_up_with_bist()` is what clears those bits, after its
own (separately-performed) AXI selftest and GT bring-up have succeeded.

**`bring_up_with_bist()` sequence:**

1. `bring_up(LOOPBACK_NEAR, timeout)` — AXI selftest + GT reset + wait for
   link-up with NEAR-END PCS loopback active.
2. `bist()` — 200 ms FIXED-pattern test, channels = 0xF, pattern = `0xAAAAAAAA`.
3. Clear `AXI_FAIL` and `BRINGUP_FAIL` bits in the result (already proved by
   step 1).
4. `print_bist_result(result)` — decodes the bitmask to UART, prints each
   failed check by name.
5. If `result != PASS`, return failure. Otherwise switch to
   `final_loopback` (caller's choice — usually `LOOPBACK_NONE` for external
   optical) with a 50 ms settle delay.

**Current bench blocker.** As of 2026-05-26 the BIST step on MASTER reports
71 errors over 63.6 M words (~1×10⁻⁶ error rate) — non-zero, fails the test.
Suspected root cause: transient errors during loopback mode switch, not
catching enough settle time. **Phase 1 closure intentionally bypasses BIST**
by replacing `bring_up_with_bist(LOOPBACK_NONE)` with `bring_up(LOOPBACK_NONE)`
in `bringup_master`, then running an extended single-channel BER test
over the actual fiber. Once Phase 1 BER is clean, BIST root-cause comes
back as a separate investigation. The bitmask infrastructure stays — only
the call site in `main` changes.

### 6.6 Driver API surface

The driver in `murosync_serdes_driver.c/.h` is the only path from firmware
to the SERDES IP. It groups about 50 functions across seven logical layers:

| Layer | Functions | Purpose |
|---|---|---|
| **Register access** | `reg_rd`, `reg_wr`, `reg_modify`, `dump_registers` | raw AXI read/write/RMW + bulk dump |
| **Commands** | `set_loopback`, `w1p_pulse`, `pulse_link_latch_reset`, `pulse_gt_reset_all`, `reset_sequence` | write-side controls (loopback, reset pulses) |
| **Status** | `get_status`, `is_link_up`, `wait_link_up`, `print_status` | composite STATUS register decode |
| **AXI selftest** | `selftest_const`, `selftest_scratch`, `scratch_wr_rd_check`, `get_dbg64`, `print_dbg` | AXI sanity + DBG bus |
| **Link test** | `link_test_set_mode/ch_mask/pol_mask/patt`, `link_test_start/stop/reset_cnt`, `link_test_get_*` (Tier 1 + Tier 2 snapshots), `run_link_test`, `run_all_channels_smoke_test`, `run_per_channel_smoke_test`, `connectivity_test`, `link_test_print_diag`, `link_test_print_full_diag` | TX pattern + RX checker engine |
| **GT debug** | `gt_debug_read_status`, `gt_debug_print_status`, `gt_debug_check_comma_detection`, `gt_debug_monitor_comma_detection`, `print_gt_ground_truth` | low-level GT Wizard probes (RXCOMMADET, RXBYTEISALIGNED, etc.) |
| **BIST** | `bist`, `print_bist_result`, `bring_up_with_bist` | self-test orchestrator (§6.5) |
| **Task** | `link_monitor`, `link_task` | edge-triggered LINK_UP/DOWN event reporter for the main loop |

**Key wrapper:** `run_link_test(mode, ch_mask, rx_pol, tx_pol, pattern,
duration_ms)` is the single entry point that touches the TX/RX engine. It
resets counters, configures CNFG, starts the test, waits, stops, reads
Tier 1 + Tier 2 telemetry, and returns a pass/fail verdict against
strengthened criteria: `wrd_cnt > 0`, `err_cnt == 0`, no per-channel errors,
`ever_locked == 1`, `at_lock snapshot taken`, and `last_fsm_state == LOCKED`.
The smoke tests (`run_all_channels_smoke_test`, `run_per_channel_smoke_test`)
and `connectivity_test` are thin wrappers around this with hardcoded
parameters.

**`run_all_channels_smoke_test` is currently hardcoded** to `ch_mask = 0xF` /
`pattern = 0xAAAAAAAA` / `duration = 500 ms`. For Phase 1 closure (60+ s BER
on a specific channel), either a parameterized variant is added (taking
`ch_mask` and `duration`), or the bring-up code calls `run_link_test`
directly. The patch is firmware-only.

### 6.7 Bring-up sequence (low-level)

When `bring_up(loopback, timeout)` is called, the following steps execute in
order. This is what runs inside both `bringup_master` and `bringup_slave`
(and inside `bring_up_with_bist` as step 1):

```
1. selftest_const            // TEST_CONST == 0x4D55524F
2. selftest_scratch          // TEST_SCRATCH write/read pattern walk
3. pulse LINK_LATCH_RESET    // clear sticky latch from previous run
4. pulse GT_RESET_ALL        // reset GT Wizard
5. set_loopback(loopback)    // 0=none, 1=NEAR PCS, 2=NEAR PMA, 4/6=FAR
6. wait_link_up(timeout)     // poll STATUS.LINK_UP, default 5s budget
7. pulse LINK_LATCH_RESET    // post-link clear (LINK_DOWN_LATCHED is sticky
                             // from reset, harmless but ugly in dumps)
8. print_status              // final STATUS dump
```

**Expected post-bring-up state on healthy bench:** `STATUS = 0xFFFF0001`,
which decodes as `LINK_UP=1`, `LINK_DOWN_LATCHED=0`, `PLL_LOCK_VEC=0xF`,
`GTPOWERGOOD_VEC=0xF`, `TXPMARESETDONE_VEC=0xF`, `RXPMARESETDONE_VEC=0xF`.
Any other value means at least one channel is unhealthy at the GT layer.

After a successful bring-up, `print_gt_ground_truth(tag)` reads
`GT_DEBUG_COMMA_ALIGN` (offset `0x058`) and prints `RXCOMMADET`,
`RXBYTEISALIGNED`, `RXBYTEREALIGN` per channel. On the current optical
bench (single fiber pair, only `SFP2` cage populated) the expected reading
is `RXBYTEISALIGNED=0x2` — bit 1 set = wizard inst `[1]` = SFP2 cage. Any
deviation (e.g. `0x0` after bring-up) points to fiber-side problems before
any data-path test is meaningful.

### 6.8 Main loop and link monitor

After bring-up succeeds, `murosync_app_main_loop()` runs forever:

```c
for (;;) {
    xil_printf("[MUROSYNC] alive #%u (%s v%u.%u)\r\n",
               alive_cnt++, mode_tag, info.version_major, info.version_minor);
    murosync_serdes_link_task();
    usleep(1000000);   // 1 s
}
```

Two things happen per second: an alive heartbeat on UART (so a watcher on
TCP can confirm firmware is running), and a link state check.

**`link_task`** wraps `link_monitor`, which holds a `static int last_link`
and emits an event only on state change:

- `EVENT_LINK_UP` → prints `[MUROSYNC] SERDES LINK UP`.
- `EVENT_LINK_DOWN` → prints `[MUROSYNC] SERDES LINK DOWN`, dumps STATUS
  and DBG64. No automatic re-bring-up — the firmware deliberately does not
  recover, so failures are visible rather than masked. Recovery logic is
  drafted in a comment inside `link_task` (`bring_up + re-lock phase`) but
  is left dormant until Phase 3+.

This polling-only design has no interrupts, no preemption, no concurrency.
The BD ties `microblaze_0.Interrupt = 1'b0`, so there is no interrupt
controller in the design at all — by intent, for bring-up clarity.

### 6.9 Memory and runtime constraints

The firmware runs entirely from **LMB BRAM** (`microblaze_0_local_memory`,
see `bd_murosync_poc_lmb_bram_0` in the BD). DDR4 is physically present on
the ACAU15 SoM but the current BD does not connect MicroBlaze to it.

Consequences:
- Linker script (`lscript.ld`) targets BRAM regions only; total firmware
  footprint must fit. Current `.elf.size` is small (driver + main + BSP) and
  comfortably fits.
- No dynamic allocation worth speaking of — driver uses stack-only locals.
- No persistent storage from firmware side — all state is volatile, lost on
  power cycle. Build version state lives in git, not on the device.
- Adding any large feature (TCP stack, lwIP, file system) will require
  wiring DDR into the BD first.

### 6.10 What the firmware does NOT do (yet)

A few features are mentioned in code comments or in this document but are
not implemented in the current firmware:

- **TCP/IP control plane.** The current control path is ASCII over UART
  (PING / VER / RD / WR), bridged to TCP by an external Waveshare module.
  Internal lwIP stack and binary register protocol are future work.
- **UART command parser.** No interactive console — UART is output-only
  except for the Waveshare TCP bridge layer (which the firmware does not
  parse; it just emits printable lines and consumes incoming bytes via
  UARTLite reads if invoked).
- **Auto-recovery on LINK_DOWN.** Drafted as a commented-out block in
  `link_task`; intentionally not enabled (see §6.8).
- **Frame layer.** No BEACON / FEEDBACK / EVENT frame generation or parsing.
  Lives in the proprietary `murosync-core-pro` repo and will be exposed via
  AXI registers when ready.
- **Phase servo loop, carry-chain TDC, MMCM phase shift actuator.** All
  proprietary — accessed only via AXI register interface once integrated.
- **Per-board persistent identity.** No serial number, no MAC address,
  no calibration data stored on-device. Both boards run the same ELF and
  identify themselves only by which bitstream is loaded.

These boundaries are deliberate — the open reference firmware is the minimum
needed to bring up the optical transport layer and probe it from outside.
Anything that uses the time measurement layer crosses into proprietary
territory and stays out of this repo.

## 7. AXI Memory Map (MicroBlaze view)

### 7.1 BD interconnect topology

```
microblaze_0 (M_AXI_DP)
       │
       ▼
microblaze_0_axi_periph (AXI Interconnect, 1S → 2M)
       │
       ├──→ M00: axi_uartlite_0          (s_axi_araddr[3:0]  → 16 bytes addr space)
       │
       └──→ M01: murosync_serdes_array_0 (s00_axi_araddr[8:0] → 512 bytes addr space)
```

Both clocked from `microblaze_0_Clk = 100 MHz`. Resets driven by `rst_clk_wiz_0_100M`.

Base addresses are allocated by Vivado at BD assembly time and **are
intentionally not documented in this reference**. They can change when:
- the BD is regenerated from scratch
- the address editor is touched (manually or via auto-assign)
- the IP repository is re-imported into a new project
- peripherals are added or removed from the AXI Interconnect

Treating them as stable would create silent drift between docs and reality.
The authoritative source is always `xparameters.h` generated by Vitis from
the XSA — firmware uses `XPAR_MUROSYNC_SERDES_ARRAY_0_BASEADDR` and
`XPAR_AXI_UARTLITE_0_BASEADDR`, which resolve to whatever Vivado picked
this build.

For host-side AXI access over UART (`RD 0x<addr>`), the runtime user can
either: (a) read the current values from `xparameters.h` after a build, or
(b) read them from the bitstream's `.hwh` / `.mmi` files. Hardcoding
addresses in scripts is a known anti-pattern — use the firmware's `RD`/`WR`
command interface instead, which already speaks register offsets relative
to the IP base.

### 7.2 `murosync_serdes_array` AXI registers (offsets relative to IP base)

| Register | Offset | RW | Fields / Notes |
|---|---|---|---|
| `CTRL` | `0x000` | W1P | `LINK_LATCH_RESET[0]`, `GT_RESET_ALL[1]` |
| `LOOPBACK` | `0x004` | RW | `loopback_ctrl[2:0]`: 0=none, 1=NEAR-END PCS, 2=NEAR-END PMA, 4=FAR-END PMA, 6=FAR-END PCS |
| `STATUS` | `0x008` | RO | `link_up[0]`, `link_down_latched[1]`, `pll_lock[19:16]`, `gtpowergood[23:20]`, `txpmaresetdone[27:24]`, `rxpmaresetdone[31:28]` |
| `DBG_LO` | `0x00C` | RO | Debug snapshot (low 32 bits of 64-bit bus) |
| `DBG_HI` | `0x010` | RO | Debug snapshot (high 32 bits) |
| `TEST_CONST` | `0x014` | RO | `0x4D55524F` (fixed pattern, AXI self-test) |
| `TEST_SCRATCH` | `0x018` | RW | Scratch (AXI write/read test) |
| `TEST_CTRL` | `0x01C` | RW/W1P | enable, clear, snapshot, mode[1:0] |
| `TEST_CFG` | `0x020` | RW | role, test_id[7:0], ch_mask (planned) |
| `TEST_FIXED_LO/HI` | `0x024/028` | RW | Fixed pattern value |
| `TEST_STATUS` | `0x02C` | RO | running, checker_locked, error_seen, snapshot_valid |
| `RX_WORD_COUNT` | `0x030` | RO | Words received |
| `RX_ERROR_COUNT` | `0x034` | RO | Errors detected |
| `RX_LAST_WORD_LO/HI` | `0x038/03C` | RO | Last received word |
| `RX_EXPECTED_LO/HI` | `0x040/044` | RO | Expected word at error |
| `IP_INFO` | `0x074` | RO | Runtime identity (see §4.7) |

Exact link-test register offsets are authoritative in `murosync_serdes_regs.h`.

### 7.3 `link_down_latched_reset_in` is tied off in BD

Note: in the current BD, the IP's `link_down_latched_reset_in` port is connected to `xlconstant_0_dout` (a fixed-value module — almost certainly 0). The sticky link-down latch is **only cleared via the AXI `CTRL.LINK_LATCH_RESET` W1P bit**, not via a hardware pin. Don't expect external reset to clear the latch.

---

## 8. Critical Lessons Learned

Real bugs and gotchas accumulated during bring-up. This section is
**append-only**: each entry is a closed historical record (a bug that was
found, a constraint that was discovered) and stays in the document
indefinitely. Items 1-14 are carried over from v1.1; items 15-19 are new in
v1.2. Items that describe a *current state which needs to change* belong in
§10 Known Issues & Cleanup TODO, not here.

1. **`hb_gtwiz_reset_clk_freerun_in` MUST be a stable fabric clock.** In current
   BD it's `microblaze_0_Clk = 100 MHz`. NOT a GT-derived clock — GT reset FSM
   will not complete.

2. **`gtwiz_userclk_rx_active_out`** signals RXUSRCLK2 domain is alive, NOT CDR
   lock or link valid. Don't gate downstream logic on it alone.

3. **`LINK_DOWN_LATCHED=1` after bring-up is normal** (sticky flag latched
   during reset). Clear with post-link `LINK_LATCH_RESET` pulse.

4. **`IO_BUFFER_TYPE = "NONE"`** required on GT serial pins in XDC. NOT the
   legacy `BUFFER_TYPE`.

5. **MMCM RESET pulse required on BUFGMUX switchover** between local refclk
   and recovered clock. Without it, MMCM may carry over phase from previous
   source.

6. **`IS_SLAVE` / `IS_MASTER` MUST be `localparam`, not `parameter`** (commit
   `264b465`). Real story: when they were `parameter` and hidden via
   `ipgui::remove_param`, IP-XACT froze their values as compile-time constants
   (IS_MASTER=true always), so SLAVE bitstreams silently behaved as MASTER.
   See §4.3 for full history.

7. **TXCHARISK in SLAVE cascade loopback must echo RXCHARISK, not be zeroed**
   (commit `6052c75`). Without echoing, K-symbols stripped from return path,
   master's RX checker never locks.

8. **`rxcharisk` extraction** comes from `rxctrl0_int`, NOT `rxctrl3_int`
   (which is RXNOTINTABLE). Fixed 2026-05-20:
   ```systemverilog
   wire [3:0] rxcharisk_int = {
       rxctrl0_int[49] | rxctrl0_int[48],  // CH3 (X0Y7)
       rxctrl0_int[33] | rxctrl0_int[32],  // CH2 (X0Y6)
       rxctrl0_int[17] | rxctrl0_int[16],  // CH1 (X0Y5)
       rxctrl0_int[1]  | rxctrl0_int[0]    // CH0 (X0Y4)
   };
   ```

9. **`rxbyteisaligned` must come from dedicated wizard port**
   `gt_debug_rxbyteisaligned_int[3:0]`, NOT manually unpacked from
   `rxctrl2_int`. Fixed 2026-05-21.

10. **156.25 MHz refclk cannot produce 400 MHz sys_clk** at any rational K.
    Hard math, not solvable in RTL. Dev-board lives at 312.5 MHz; target
    hardware needs different refclk source.

11. **BD file on disk reflects last build state.** It's an artifact, not a
    source. Source of truth = `build_bitstream.tcl` + IP-XACT.

12. **Vivado must be closed before running `.bat` wrappers** — project lock
    blocks otherwise.

13. **Re-package IP manually after `update_ip_ports.tcl`**: the script does
    NOT call Re-Package; that's an explicit GUI click in the Package IP
    workspace. Then refresh IP catalog in dependent projects.

14. **XDC verified pin assignment** for refclk:
    ```tcl
    set_property PACKAGE_PIN T7 [get_ports gth_ref_p]
    set_property PACKAGE_PIN T6 [get_ports gth_ref_n]
    ```
    T7/T6 = MGTREFCLK1_225 = on-board ACAU15 oscillator (NOT FMC GBTCLK0).

15. **Timing XDC file is intentionally minimal — primary clocks are
    auto-inferred.** *(new in v1.2)* Both `create_clock` statements in
    `murosync_poc_timing_constraints.xdc` are commented out. Timing closure
    works because Vivado auto-infers `sys_clk` from the `clk_wiz_0` BD
    instance (200 MHz diff input → 100 MHz output) and the GT user clocks
    from the GT Wizard's internal XDC (`gtwizard_ultrascale_0.xdc` +
    `gtwizard_ultrascale_0_ooc.xdc`). **Risk:** moving the IP to a barebones
    project without these helpers will silently lose all timing constraints —
    synthesis succeeds, but no timing check happens. If you ever see a
    timing report with zero `create_clock` entries, this is why.

16. **`link_down_latched_reset_in` IP port is tied off in the BD via
    `xlconstant`.** *(new in v1.2)* The IP exposes a hardware-pin path to
    clear the sticky `LINK_DOWN_LATCHED` flag, but the BD wires it to
    `xlconstant_0_dout` (fixed value 0). The flag is therefore clearable only
    via the `CTRL.LINK_LATCH_RESET` W1P bit over AXI. Do not expect a
    hardware-pin reset to clear it.

17. **SFP cage naming is dual-indexed.** *(new in v1.2)* FH1223 silkscreen
    labels cages `SFP1..SFP4`, but RTL port names and XDC pin assignments use
    0-indexed names (`sfp0_*..sfp3_*`). The two are off-by-one. Reading
    `RXBYTEISALIGNED = 0x2` means **wizard inst `[1]` aligned = SFP2 cage**,
    not "SFP1 with bit 1 set". The full mapping is documented in §3.1;
    flagged here because it's easy to get wrong in conversation and in
    chat-based debugging.

18. **Firmware version counter advances on every build attempt, including
    failures.** *(new in v1.2)* The `gen_murosync_build_info.bat` pre-build
    hook runs unconditionally before `make`. If `make` then fails (compile
    error, missing include, linker problem), the `SUB` counter has already
    been incremented and the new `cmd/murosync_version_state.txt` has been
    written. The version visible at next successful boot may therefore jump
    by several units after a session of build errors. Not a bug — the
    counter identifies "the Nth build attempt", not "the Nth working
    binary". Just don't trust contiguous version numbers as evidence of
    contiguous working binaries.

19. **Vitis live workspace is outside the repository.** *(new in v1.2)* Live
    workspace lives at `C:\Users\mikha\workspace_murosync\murosync_poc_fw\`,
    outside git. The `firmware/` directory in the repo is a committed snapshot
    copied in before each commit — see §6.1. Consequences: (a) a fresh
    `git clone` does not yield a directly-buildable workspace — must re-import
    or use `vitis_export_archive.ide.zip`; (b) the committed `Debug/*.elf` is
    a known-good fallback paired with the bitstream snapshot in `_ide/`, not
    the latest experimental build; (c) live build state (uncommitted version
    bumps, debug printouts, work-in-progress edits) is invisible to anyone
    reading the repo.

## 9. Migration to Target Hardware (future, not bench)

| Aspect | Dev bench (now) | Target hardware (future) |
|---|---|---|
| Number of bitstreams | 2 (MASTER + SLAVE) | 1 (universal) |
| `parameter MODE` mechanism | Same — per single instance | Same — per each of 3 instances |
| Number of IP instances in top | 1 (in BD) | 3 (1× SLAVE on Quad 0 + 2× MASTER on Quad 1, Quad 2) |
| `enablement_dependency` mechanism | Same | Same |
| Bitstream switching script needed | Yes (this `build_bitstream.tcl`) | No — single build |
| Number of firmware ELFs | 1 (dispatched via IP_INFO) | 1 (same) |
| Refclk | T7 / 156.25 MHz (SiT9121AI) | New source — 160 MHz via Si5341 or fixed osc |
| sys_clk | 312.5 MHz | 400 MHz |
| Line rate | 6.25 Gbps | 8.0 Gbps |
| TDC coarse tick | 3.2 ns | 2.5 ns |
| Device type (slave/master/repeater) | Determined by which bitstream | Determined at boot via MOD_ABS readout |

See `MuroSync_Hardware_Unification_Concept.md` for the full Type 1/2/3/4 architecture.

---

## 10. Known Issues & Cleanup TODO

This section is **mutable**, opposite of §8. Each entry describes a current
state of the codebase that **needs to change**: documentation that has
drifted from reality, dead files that should be removed, small fixes pending,
constraints worth tightening. When a fix lands, the corresponding entry is
removed from this list and the action recorded in Document History at the end
of the document.

Treat this as a lightweight TODO scoped to bench-level housekeeping. Larger
work (Phase 2 frame layer, Phase 3 delay compensation, etc.) belongs in the
project roadmap, not here.

### Open items

1. **`murosync_serdes_regs.h` header comment for `LNK_TEST_CNFG.MODE_SEL` is
   out of date.** The summary block at the top of the file states
   `0=Fixed, 1=Counter, 2=PRBS`, but the actual RTL and driver implement
   `0=FIXED, 1=TOGGLE, 2=COUNTER` (no PRBS). The `MUROSYNC_LNK_TEST_MODE_*`
   defines later in the same header are correct. **Fix:** update the
   doc comment to match implementation. **Cost:** ~5 minutes.

2. **Remove `murosync_serdes_array_mode.sv`.** Present in
   `gateware/ip/murosync_serdes_array/src/`, committed to git, but not
   referenced anywhere — leftover from an abandoned approach to encapsulating
   mode-selection logic. **Fix:** `git rm` the file, run
   `update_ip_ports.tcl` (auto-bumps IP minor), re-package IP, rebuild both
   bitstreams to confirm nothing depends on it. **Cost:** ~30 minutes
   including bitstream rebuild.

3. **Fix typos in `BRING-UP` terminology.** Two instances of the same word
   misspelled in two different ways:
   - `firmware/src/murosync_serdes_driver.h`, comment block header:
     `/*************************** BTRING-UP **********************************/`
     — should be `BRING-UP`.
   - `firmware/src/murosync_serdes_driver.c`, printf inside
     `murosync_serdes_bring_up()`: emits `AXI MUROSYNC SERDES BTING-UP` to
     UART (visible in every boot log). Should be `BRING-UP`.

   Purely cosmetic, but ugly in UART output and confusing for anyone
   grepping the codebase. **Cost:** ~3 minutes.

### Process

When you close an item:
- Remove the entry from this section.
- Add a one-liner to Document History at the bottom of the document:
  *"v1.x: closed cleanup #N — short description of what was done."*
- If the closure also generated a lesson worth keeping (e.g. you discovered
  a subtlety while doing the cleanup), add it to §8 — the two sections feed
  each other in this direction only (cleanup discovers lessons, lessons
  rarely spawn cleanups).

New cleanup items get appended to this section with the next available
number. Numbers are **stable once assigned** — when an item is closed and
removed from the open list, its number is not reused. Document History
references closed items by these permanent numbers, so a reader can always
trace what "cleanup #2" referred to.

---

## 11. Source documents and cross-references

| Doc | Section | Provides |
|---|---|---|
| FH1223 User Manual | Part 2.2 | cage silkscreen → FMC HPC pin |
| AXAU15 User Manual | §3.4 | FMC HPC pin → ACAU15 SoM signal → FPGA pin |
| ACAU15 User Manual | §8 | ACAU15 SoM signal ↔ CON4 PIN ↔ FPGA pin |
| Xilinx XCAU15P FFVB676 | package file | FPGA pin → GTHE4 site |
| Vivado XDC constraints | `LOC` properties on `gen_gthe4_channel_inst[N]` | GTHE4 site → wizard inst |
| `murosync_serdes_array.sv` | RX/TX packing | wizard inst → external IP port name |
| `update_ip_ports.tcl` | header + body | IP packaging logic, version bump, enablement_dependency, historical bug note |
| `build_bitstream.tcl` | header + body | bitstream build, MODE switch, reconnection logic |
| `bd_murosync_poc.v` (generated) | top module | BD topology, clock connections, ILA probes |
| Empirical bring-up | 2026-05-26 | `RXBYTEISALIGNED = 0x2` confirms wizard `[1]` active |
| `firmware/src/main.c` | full | boot flow, IP_INFO dispatch, MASTER/SLAVE bring-up flows (§6.3-6.4) |
| `firmware/src/murosync_serdes_driver.c/.h` | full | driver API surface, BIST orchestrator, link_task (§6.6) |
| `firmware/src/murosync_serdes_regs.h` | full | AXI register offsets and bit-field masks (authoritative for register access) |
| `firmware/cmd/gen_murosync_build_info.bat` | full | firmware version bump mechanism (§6.2) |
| `gateware/vivado/.../constrs_1/new/murosync_poc_phys_constraints.xdc` | full | pin assignments + GT location constraints (§3) |
| `gateware/vivado/.../constrs_1/new/murosync_poc_timing_constraints.xdc` | full | mostly empty — clocks auto-inferred (see Lesson 15) |
| `MuroSync_IP_Internals.md` | full doc | RTL semantics, full AXI bit decode, FSM diagrams — companion document, load together for any RTL or register-level discussion |
| `MuroSync_Claude_Context.md` | full doc | personal/strategic context — load together |
| `MuroSync_Hardware_Unification_Concept.md` | §2, §5 | target hardware migration story |
| `MuroSync_Master_Reference_v2` | §3, §4, §10 | project overall, IP boundary, strategy |

---

## Appendix A — Bench Session Walkthrough

A real boot session captured from the bench on 2026-05-26 with firmware
v1.82 / IP v1.1. Two boards, two UART captures, annotated below. This is
what a healthy bring-up looks like end-to-end, and where the current bench
deviates from "fully clean" — useful for any future Claude or human picking
up the bench and trying to recognise normal vs anomalous behaviour.

### A.1 SLAVE boot — healthy, reaches main loop

```
============================================================
                    M U R O S Y N C
      High-Precision Optical Timing & Synchronization
============================================================
 Platform : FPGA  XCAU15P
 CPU      : MicroBlaze
 Firmware : v1.82  (code 65618)
 Build    : GT Bring-Up
 Built at : 2026-05-25 21:19:58 UTC
            (1779743997 UTC)
============================================================
```

Banner is emitted by `murosync_print_banner()` immediately after
`init_platform()` and a 1 s settle delay. First confirmation that the
firmware is alive and the UART chain (UARTLite → Waveshare → TCP) is wired
correctly. If you see this on TCP connect, the FPGA is configured and the
MicroBlaze is running.

```
        MUROSYNC SERDES | Checking RD-access over AXI
                AXI OK: TEST_CONST = 0x4D55524F
        MUROSYNC SERDES | Checking WR/RD-access over AXI
                TEST_SCRATCH PAT1 pattern 0xA5A55A5A
                TEST_SCRATCH PAT2 pattern 0x5AA5A55A
                AXI OK: TEST_SCRATCH write/readback OK
```

`murosync_app_identify()` runs AXI selftest before touching anything else.
`TEST_CONST = 0x4D55524F` is the literal ASCII "MURO" — invariant per IP
build. `TEST_SCRATCH` is exercised with two patterns to catch stuck bits
in both directions. If either fails, the firmware prints
`[MUROSYNC][FATAL] AXI selftest ... FAILED` and exits without bringing GT up.

```
[MUROSYNC] === IP INFO ===
        Raw          : 0x04000111
        Mode         : SLAVE
        IP version   : v1.1
        NUM_CHANNELS : 4
```

`Raw = 0x04000111` decodes per `IP_INFO` bit layout:
`[0]=IS_SLAVE=1`, `[1]=IS_MASTER=0`, `[7:4]=MAJOR=1`, `[23:8]=MINOR=1`,
`[27:24]=NUM_CHANNELS=4`. This confirms which bitstream is loaded on this
board and dispatches the bring-up path.

```
[MUROSYNC] === SLAVE FLOW ===
AXI MUROSYNC SERDES BTING-UP
```

`[MUROSYNC] === SLAVE FLOW ===` is the dispatch marker from `main()`.
The next line `AXI MUROSYNC SERDES BTING-UP` is from inside
`murosync_serdes_bring_up()` — note the typo (see Cleanup #3 in §10).

```
        MUROSYNC SERDES | Checking RD-access over AXI
                AXI OK: TEST_CONST = 0x4D55524F
        MUROSYNC SERDES | Checking WR/RD-access over AXI
                TEST_SCRATCH PAT1 pattern 0xA5A55A5A
                TEST_SCRATCH PAT2 pattern 0x5AA5A55A
                AXI OK: TEST_SCRATCH write/readback OK
```

AXI selftest is repeated inside `bring_up()` — defensive belt-and-braces.
Same patterns, same expected pass. The second redundant pass is harmless;
removing it is a candidate optimisation but not worth touching.

```
        MUROSYNC SERDES | Reset sequence
                Pulse LINK_LATCH_RESET...
                Pulse GT_RESET_ALL...
        MUROSYNC SERDES | Set loopback = 0
        MUROSYNC SERDES | Waiting link up...
        MUROSYNC SERDES | Link is up, clear sticky latch again...
        MUROSYNC SERDES | LINK UP! STATUS=0xFFFF0001
```

Steps 3-7 of the bring-up sequence documented in §6.7. Loopback = 0 means
external optical (BiDi SFP+ fiber). The "Link is up, clear sticky latch
again" line is the post-link `LINK_LATCH_RESET` pulse — needed because
`LINK_DOWN_LATCHED` is sticky from the reset itself (Lesson 3).

```
        MUROSYNC SERDES | STATUS=0xFFFF0001
                LINK_UP            : 1
                LINK_DOWN_LATCHED  : 0
                PLL_LOCK_VEC       : 0xF
                GTPOWERGOOD_VEC    : 0xF
                TXPMARESETDONE_VEC : 0xF
                RXPMARESETDONE_VEC : 0xF
```

The canonical "everything is healthy at GT layer" state. `0xFFFF0001`
decoded: all 4 channels have PLL lock, power good, and PMA reset done.
Any deviation means at least one GT channel is unhealthy.

```
        MUROSYNC SERDES | DBG=0x000000003C1FFFF2
```

64-bit `dbg` snapshot. Internal signals — useful for ILA-style debug.
Note: the SLAVE shows `0x3C1FFFF2`, the MASTER (next section) shows
`0x3E1FFFF2` — single bit differs. The bit is in the `0x02` position of
the high nibble of byte 3, which is in the IP's diagnostic packing region.
Documented in IP Internals §6 if a future investigation needs it.

```
[MUROSYNC] === GT WIZARD GROUND TRUTH (post bring-up) ===
        RXCOMMADET       : 0x0 [CH3=0 CH2=0 CH1=0 CH0=0]
        RXBYTEISALIGNED  : 0x2 [CH3=0 CH2=0 CH1=1 CH0=0]
        RXBYTEREALIGN    : 0x0
```

The smoking-gun confirmation that only one optical channel is active.
`RXBYTEISALIGNED = 0x2` = bit 1 set = wizard inst `[1]` = SFP2 cage
populated. CH0/CH2/CH3 see no light, no alignment. `RXCOMMADET = 0x0` is
expected here because the local board's RX is not seeing K28.5 commas in
the cascade-loopback return path at this moment (SLAVE doesn't inject
commas — only the MASTER does, and we're looking at the SLAVE's GT state).

```
[MUROSYNC] alive #0 (S v1.1)
[MUROSYNC] SERDES LINK UP
[MUROSYNC] alive #1 (S v1.1)
[MUROSYNC] alive #2 (S v1.1)
...
```

SLAVE bring-up complete. The firmware has dropped into `main_loop()`,
emitting heartbeat once per second. The `SERDES LINK UP` line is from
`link_task()` — first poll detected the link state change from "unknown"
to "up", edge-triggered event. After this, no further state changes
expected until something physically disconnects.

**A healthy SLAVE session ends here.** Heartbeats continue forever.

### A.2 MASTER boot — currently fails BIST, never reaches main loop

```
============================================================
                    M U R O S Y N C
      High-Precision Optical Timing & Synchronization
============================================================
 Platform : FPGA  XCAU15P
 CPU      : MicroBlaze
 Firmware : v1.82  (code 65618)
 Build    : GT Bring-Up
 Built at : 2026-05-25 21:19:58 UTC
            (1779743997 UTC)
============================================================
```

Same banner — same firmware ELF on both boards, the asymmetry comes from
which bitstream is loaded.

```
        MUROSYNC SERDES | Checking RD-access over AXI
                AXI OK: TEST_CONST = 0x4D55524F
        MUROSYNC SERDES | Checking WR/RD-access over AXI
                TEST_SCRATCH PAT1 pattern 0xA5A55A5A
                TEST_SCRATCH PAT2 pattern 0x5AA5A55A
                AXI OK: TEST_SCRATCH write/readback OK
[MUROSYNC] === IP INFO ===
        Raw          : 0x04000112
        Mode         : MASTER
        IP version   : v1.1
        NUM_CHANNELS : 4
```

`Raw = 0x04000112` differs from SLAVE's `0x04000111` only in the low
nibble: `[0]=IS_SLAVE=0`, `[1]=IS_MASTER=1`. Otherwise identical IP build.
This is the dispatch discriminator.

```
[MUROSYNC] === MASTER FLOW ===
[BRINGUP+BIST] === ORCHESTRATOR START ===
        Requested final loopback: 0
```

`main()` selected `murosync_app_bringup_master()`, which calls
`bring_up_with_bist(LOOPBACK_NONE, 5_000_000)`. The orchestrator prints
its banner and the final loopback target (0 = external optical, applied
after BIST succeeds).

```
AXI MUROSYNC SERDES BTING-UP
        ... (same AXI selftest + TEST_SCRATCH as SLAVE, omitted) ...
        MUROSYNC SERDES | Reset sequence
                Pulse LINK_LATCH_RESET...
                Pulse GT_RESET_ALL...
        MUROSYNC SERDES | Set loopback = 1
```

**Key difference vs SLAVE:** `Set loopback = 1` — NEAR-END PCS loopback,
not external optical. The orchestrator brings GT up in this internal
loopback first, so BIST can run without needing the partner board to be
correctly transmitting. Loopback path is digital, no PMA, no fiber.

```
        MUROSYNC SERDES | Waiting link up...
        MUROSYNC SERDES | Link is up, clear sticky latch again...
        MUROSYNC SERDES | LINK UP! STATUS=0xFFFF0001
        MUROSYNC SERDES | STATUS=0xFFFF0001
                LINK_UP            : 1
                LINK_DOWN_LATCHED  : 0
                PLL_LOCK_VEC       : 0xF
                GTPOWERGOOD_VEC    : 0xF
                TXPMARESETDONE_VEC : 0xF
                RXPMARESETDONE_VEC : 0xF
        MUROSYNC SERDES | DBG=0x000000003E1FFFF2
```

GT layer is fully healthy. Same `STATUS=0xFFFF0001` as SLAVE. NEAR-END PCS
loopback works at the GT level — that's why STATUS is happy. The BIST
that follows is the actual test of the data path.

```
[BIST] === BOOT SELF-TEST START ===
        Mode: PCS NEAR-END loopback
        Pattern: 0xAAAAAAAA, Duration: 200ms, Channels: 0xF
        MUROSYNC SERDES | --- LINK TEST START ---
                Mode        : 0
                Ch Mask     : 0xF
                RX Pol Mask : 0x0
                TX Pol Mask : 0x0
                Pattern     : 0xAAAAAAAA
                Duration    : 200 ms
                Test Running...
```

BIST configuration printed by `murosync_serdes_bist()`. Mode 0 = FIXED,
all 4 channels, alternating bit pattern `0xAAAAAAAA`. 200 ms at 312.5 MHz
sys_clk → ~62.5 M words expected.

```
        MUROSYNC SERDES | --- LINK TEST RESULTS ---
                Words Rx    : 63622096
                Errors      : 71
                Per-CH err  : CH0=18 CH1=13 CH2=33 CH3=25
                RESULT      : FAIL (errors, global)
```

**Here's the current bench blocker.** 63.6 M words received (matches
expectation: 312.5 MHz × 0.2 s × ~K-symbol overhead). 71 global errors,
distributed across all four channels.

**One subtle anomaly worth noting** (deferred from current investigation):
per-channel sum is `18+13+33+25 = 89`, but global is `71`. Discrepancy of
18 means about 18 of the failed words had errors on more than one channel
in the same cycle — i.e., the failures are at least partially **correlated
across channels**, not independent per-channel bit flips. This suggests a
common-cause mechanism (loopback path transient, PCS-level event, clock
disturbance) rather than random noise. Worth keeping in mind when BIST
root-cause comes back.

```
[BIST] === BOOT SELF-TEST COMPLETE ===
[BIST] === RESULT BITMASK = 0x00000018 ===
[BIST]   Failures detected:
[BIST]     [bit 3]  BIST link test had global errors (err_cnt > 0)
[BIST]     [bit 4]  BIST link test had per-channel errors
[BRINGUP+BIST][FAIL] BIST detected failures — stopping
[MUROSYNC][FATAL] MASTER bring-up + BIST FAILED
```

`0x00000018 = bit 3 | bit 4` decoded: global error count > 0, per-channel
error count > 0. Other bits clear: AXI fine, bring-up fine, data flowed
(`wrd_cnt > 0`), FSM reached LOCKED, at_lock snapshot taken. The only
failure is the error count itself.

The orchestrator returns `XST_FAILURE`, `main()` propagates that, and
`murosync_app_main_loop()` is never reached. **No heartbeat alive messages
appear after this point** — the firmware exits cleanly and the MicroBlaze
sits idle until the next reset. Watching for "alive #0" on UART is
therefore a quick liveness check: if it never appears on the MASTER, the
bring-up failed somewhere.

### A.3 What this tells you, at a glance

If both boards reach `[MUROSYNC] alive #0`, both are healthy and you can
proceed to whatever experiment is planned. If only the SLAVE reaches alive
but the MASTER doesn't:

- Check the FATAL line in MASTER log — it identifies which step failed.
- AXI selftest fail = serious, board-level problem.
- Bring-up fail = GT level, check pin assignments / SFP presence / refclk.
- BIST fail = current bench condition. Bypass per the Phase 1 plan
  (replace `bring_up_with_bist` with `bring_up` in `bringup_master`) and
  proceed to optical BER test.

For Phase 1 specifically, the bypass path doesn't run BIST at all and
goes straight from `bring_up(LOOPBACK_NONE)` to the parameterised
single-channel link test on CH1 (`ch_mask = 0x2`, longer duration). The
log will look like the SLAVE log above (loopback = 0, STATUS=0xFFFF0001,
RXBYTEISALIGNED=0x2) followed by an extended `--- LINK TEST RESULTS ---`
block with `Errors : 0` and `Words Rx` in the tens of billions.

### A.4 Differences between SLAVE and MASTER logs at a glance

| Aspect | SLAVE (healthy) | MASTER (current state) |
|---|---|---|
| `IP_INFO` raw | `0x04000111` | `0x04000112` |
| Dispatch marker | `=== SLAVE FLOW ===` | `=== MASTER FLOW ===` |
| Bring-up loopback | 0 (external optical) | 1 (NEAR-END PCS) |
| Final loopback after bring-up | n/a (no orchestrator) | 0 (would be set after BIST passes) |
| BIST runs | no | yes (and currently fails) |
| Smoke test runs | no | yes (only if BIST passes — currently skipped) |
| GT ground truth printed | yes ("post bring-up" tag) | yes (would print twice if smoke ran) |
| Reaches `main_loop()` | yes (`alive #0..#N`) | no (FATAL on BIST fail) |
| DBG bus | `0x3C1FFFF2` | `0x3E1FFFF2` |
| `RXBYTEISALIGNED` | `0x2` (CH1 / SFP2 only) | not printed before BIST fail |

The DBG single-bit difference between modes is expected — the IP packs
mode-specific status into the dbg bus, and the master/slave flag is one of
those bits.

---

## Document History

| Version | Date | Notes |
|---|---|---|
| 1.0 | 2026-05-26 | Initial version — consolidated Channel Mapping + IP architecture + build. |
| 1.2 | 2026-05-26 | Major expansion of firmware coverage and operational reference. §6 Firmware Architecture rewritten and extended ten-fold — new §6.1 (repository layout + workspace vs snapshot), §6.2 (build metadata + dual versioning), §6.3 (boot flow with banner template), §6.4 (asymmetric MASTER/SLAVE flows), §6.5 (BIST mechanism with TEST_RESULT_* bitmask), §6.6 (driver API surface table), §6.10 (what firmware doesn't do yet). §0 TL;DR — added bullet about dual versioning. §3 — added §3.8 naming convention note (0-index vs 1-index). §4.8 — cross-reference to firmware versioning in §6.2. §7 — replaced base-address paragraph with explicit rationale for NOT documenting them (they're BD-generated and unstable). §8 Lessons — added 15 (timing XDC auto-inference), 16 (link_down_latched_reset_in tied off), 17 (SFP dual-indexed naming), 18 (firmware version on failed builds), 19 (Vitis workspace outside repo). Section header explicitly marked as append-only. **New §10 Known Issues & Cleanup TODO** — mutable list of housekeeping items, opened with three entries (regs.h MODE_SEL doc comment outdated, murosync_serdes_array_mode.sv rudiment, BTING/BTRING typos in driver). Process for closing items documented inline. §11 (renamed from §10) Sources — added firmware sources, XDC files, IP_Internals companion doc. **New Appendix A** — bench session walkthrough with real UART logs from 2026-05-26 (healthy SLAVE, failing-BIST MASTER), annotated. |
| 1.1 | 2026-05-26 | Restructured §5 to separate IP packaging (Workflow A, `update_ip_ports.tcl`) from bitstream build (Workflow B, `build_bitstream.tcl`). Added §4.2 with full `enablement_dependency` explanation. Added §4.3 with IS_SLAVE/IS_MASTER localparam bug history. Added §4.8 IP versioning. Added §1.6 ILA. Added §7.1 BD interconnect topology. Added §7.3 `link_down_latched_reset_in` tied off note. Corrected §2.3 clock domain count (BD has one 100 MHz domain, not multiple). Added §6.3 no interrupts. Added §6.5 LMB BRAM only. Lesson #6 expanded with historical context. New Lesson #11 (BD is artifact). New Lesson #13 (re-package step). |

---

**End of document.**

Drop into any new chat together with `MuroSync_Claude_Context.md` for full standing context. When something on the bench changes, update this document — everything else inherits.
