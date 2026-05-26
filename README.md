# MuroSync Reference

Public reference implementation of the
[MuroSync](https://murosync.com) FPGA platform for optical timing,
synchronization, and programmable trigger distribution.

This repository contains the open transport layer of the system:
SerDes IP, AXI register interface, link-test engine, and the firmware
required to bring up and operate the hardware.

## Repository contents

| Path | What's inside |
|---|---|
| [`gateware/`](gateware/) | FPGA gateware — SystemVerilog source, packaged IP (`murosync_serdes_array`), Vivado project files. Target: Xilinx XCAU15P (UltraScale+). |
| [`firmware/`](firmware/) | MicroBlaze firmware (C) — bring-up flows, driver for `murosync_serdes_array`, build metadata. Committed snapshot of the working Vitis workspace. |
| [`docs/`](docs/) | Engineering reference documents — bench architecture, IP internals, annotated UART logs. See [`docs/README.md`](docs/README.md) for the document index. |
| [`CLAUDE.md`](CLAUDE.md) | Guidance file for Claude Code agents working with this repository. |

## Repository scope

This is the **public reference implementation** of MuroSync. It covers
the open transport layer — GT bring-up, optical link, AXI register
interface, link-test engine, frame layer — and the firmware required
to operate it.

The proprietary timing core (carry-chain TDC, phase-alignment servo
loop, histogram-based phase estimator, RTT computation) is developed
in a separate **private** repository. The two components interact
through a stable AXI4-Lite register interface defined in this
repository (`firmware/src/murosync_serdes_regs.h`).

This separation is intentional: the open transport layer is designed
for integration into existing scientific infrastructure (EPICS,
TANGO, MRF-based facilities), while the proprietary timing
algorithms are the subject of patent filings and commercial
licensing. For inquiries about the proprietary core, see contact
below.

## Status

This is a research project, not a finished product. The hardware bench
is currently at the GT bring-up stage with one optical channel active.
No performance claims (precision, jitter, drift) are made in this
repository until measured data is available; the published numbers
will appear here as they are obtained.

For the current development status and roadmap, see the project
website: <https://murosync.com>.

## Toolchain

- Vivado 2022.2 + Vitis 2022.2
- Target FPGA: Xilinx XCAU15P-2FFVB676I (Artix UltraScale+)
- Soft-core CPU: MicroBlaze

The GT Wizard IP inside `murosync_serdes_array` needs to be
regenerated from its `.xci` recipe after cloning — Vivado handles
this automatically when the IP repository is loaded. See `CLAUDE.md`
for details.

## Documentation

Start with [`docs/`](docs/) for engineering reference. The two main
documents are:

- [`docs/MuroSync_Dev_Bench_Architecture.md`](docs/MuroSync_Dev_Bench_Architecture.md) — bench setup, channel mapping, firmware flows, bring-up lessons.
- [`docs/MuroSync_IP_Internals.md`](docs/MuroSync_IP_Internals.md) — RTL-level reference for the `murosync_serdes_array` IP.

## License

No open-source license has been applied to this repository yet. The
code is shared publicly for visibility while intellectual-property
arrangements with the author's host institution are being finalised.
The current intent is to release the code in this repository under
**Apache License 2.0** once those arrangements are complete.

The proprietary timing core in the separate private repository
remains closed-source under a different licensing model. Commercial
licensing is available on request.

Until the open-source license is applied, this code is provided for
reading and reference only. For licensing inquiries, please contact
**info@murosync.com**.

## Contact

- Website: <https://murosync.com>
- Email: **info@murosync.com**
- Author: Mikhail Vasilev

---

*MuroSync — research platform for optical timing and phase synchronization.*
*Copyright 2025-2026 Mikhail Vasilev.*
