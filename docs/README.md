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

The two documents are companions. `Dev_Bench_Architecture` is the
top-down view (what the system is, how it boots, what each board does);
`IP_Internals` is the bottom-up view (what each register bit means, what
each RTL module does). For any question that touches both layers, load
both.

## Document conventions

A few conventions used across these documents — worth knowing before
editing or contributing:

- **Versioning lives inside each document**, not in the filename. The
  current version is stated at the top of every document, and a
  Document History table at the end records what changed in each
  revision. Git already provides the file-level history; renaming files
  on every revision would clutter the directory without adding
  information.
- **`Critical Lessons Learned` sections are append-only.** They record
  bugs found and constraints discovered during bring-up, with commit
  hashes and dates where applicable. Existing items are never renumbered
  or removed — they are part of the project's institutional memory.
- **`Known Issues & Cleanup TODO` sections are mutable.** They list
  current housekeeping items that should be fixed (drifted comments,
  rudiment files, cosmetic typos). When an item is fixed, the entry is
  removed and the closure is recorded in Document History. Cleanup item
  numbers are stable once assigned and not reused after closure.
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

---

*Documents in this folder are part of the open side of the MuroSync
project. The proprietary timing core is developed separately and is not
included in this repository.*
