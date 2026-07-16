# MuroSync — Reference Documentation

This folder contains operational and architectural reference documents for
the [MuroSync](https://murosync.com) FPGA timing platform — specifically
the parts that are open and published as part of the `murosync-reference`
repository.

These are **engineering reference documents**, not research papers or
marketing material. They describe how the current development bench is
wired and how the open IP (`murosync_serdes_array`) behaves at the RTL and
firmware level. They are written to be read together with the source code
in `gateware/` and `firmware/`.

## Documents

| File | Scope | When to read |
|---|---|---|
| [`MuroSync_Dev_Bench_Architecture.md`](MuroSync_Dev_Bench_Architecture.md) | Whole bench: 2-board setup, GT/SFP channel mapping, IP architecture (open/closed boundary), firmware flows, BIST mechanism, bring-up lessons, known issues. Includes an appendix with annotated UART logs from a real boot session. | Start here. Anyone touching the dev bench, reading the codebase, or trying to reproduce results should read this first. |
| [`MuroSync_IP_Internals.md`](MuroSync_IP_Internals.md) | The `murosync_serdes_array` IP at RTL level: full AXI register bit decode, RX checker FSM, mode-specific behaviors (SLAVE cascade loopback vs MASTER pattern generator), debug bus packing. | Read when working on the IP itself, debugging at register level, or adding new test modes. Treat as the authoritative source for register semantics — `regs.h` is the C-side mirror, this document explains the intent. |
| [`MuroSync_Phase1_GT_Research.md`](MuroSync_Phase1_GT_Research.md) | Phase-1 transceiver research record: GT configuration reasoning (PPM offset, termination, equalization), hypotheses tested on hardware, and their outcomes. | Read for the *why* behind the GT configuration before proposing transceiver changes. |
| [`gt_parameters_snapshot_v1_13.md`](gt_parameters_snapshot_v1_13.md) | Canonical GT Wizard configuration baseline: full `CONFIG.*` dump from the live IP object plus GTHE4_CHANNEL primitive attributes from the synthesized netlist. Configuration-only public edition. | The single source of truth for "what is the GT actually configured as." Cite this — not the wizard GUI — in any configuration claim. |
| [`MuroSync_Applicability_Envelope.md`](MuroSync_Applicability_Envelope.md) | The niche, honestly bounded: distance limits, cascade depth, BiDi wavelength asymmetry numbers, what the system is NOT for. | Read before positioning MuroSync against any use case. |
| [`MuroSync_MMCM_Phase_Adjustment.md`](MuroSync_MMCM_Phase_Adjustment.md) | MMCM dynamic phase shift as an actuator: mechanism, step size vs VCO, port-level behavior. Open reference. | Read when working with the clock IP or reasoning about phase-step granularity. |

`Dev_Bench_Architecture` is the top-down view; `IP_Internals` is the
bottom-up view. For any question that touches both layers, load both.

### `archive/`

Point-in-time engineering audits from the Phase-1 bring-up
(`full_ip_audit_optical_revival`, `slave_cascade_clocking_analysis`,
`improvement_audit_post_phase1`). They record how bugs were found and are
kept as institutional memory; their conclusions are superseded by
`MuroSync_IP_Internals.md` and the current RTL. Some are written in
Russian (internal working language of the audits).

### `phase1_logs/`

Raw annotated UART logs from Phase-1 bring-up sessions. See the folder's
own README.

## Document conventions

- **Versioning lives inside each document**, not in the filename. The
  current version is stated at the top of every document, and a
  Document History table at the end records what changed in each
  revision. (The GT snapshot's `_v1_13` names the *IP version it
  captures*, not the document revision.)
- **`Critical Lessons Learned` sections are append-only.** Existing items
  are never renumbered or removed — they are part of the project's
  institutional memory.
- **`Known Issues & Cleanup TODO` sections are mutable.** Item numbers
  are stable once assigned and not reused after closure.
- **Documents travel only as files** (repository ↔ any working copy) —
  never through a rendered-text viewer/copy path, which silently strips
  markup.
- **Configuration claims cite the primitive-level dump** (the GT
  snapshot), never the wizard GUI alone.
- **Open/closed boundary.** These documents cover only the open
  transport layer (GT bring-up, AXI register interface, link-test
  engine, frame layer once implemented). Proprietary timing algorithms
  (carry-chain TDC, phase servo loop, histogram estimator) live in a
  separate private repository and are not documented here.

## Reading order for a new contributor

1. Project website: [murosync.com](https://murosync.com) — what MuroSync
   is and why it exists.
2. Repository root `README.md` and `CLAUDE.md` — what this repository
   contains.
3. `MuroSync_Dev_Bench_Architecture.md` (this folder) — the dev bench in
   detail.
4. `MuroSync_IP_Internals.md` (this folder) — the IP in detail.
5. Source code in `gateware/` and `firmware/`.

## License

The repository license is **to be finalized** (Apache-2.0 intended for the
open transport layer). Until the license file appears in the repository
root, all rights are reserved; documents in this folder carry their own
attribution notice.

---

*Documents in this folder are part of the open side of the MuroSync
project. The proprietary timing core is developed separately and is not
included in this repository.*
