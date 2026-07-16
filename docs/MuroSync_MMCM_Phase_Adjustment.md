# MuroSync — MMCM Phase Adjustment Reference
 
**Document type:** Clocking-mechanics reference (actuator mechanics — no RTL code, no control law)
**Scope:** The MMCM dynamic fine phase-shift mechanism as used by the MuroSync `clk_ctrl` actuator wrapper — interface, mechanism, VCO/step relationship, VCO selection for resolution, and the discrete-grid / full-360° behaviour. Target silicon: **XCAU15P-2** (Artix UltraScale+, MMCME4_ADV).
**Version:** 0.3 (2026-06-24) — designates the recommended **design-target VCO**: the headline recommendation is now the **`-2` ceiling (F_VCO ≈ 1440 MHz → step ≈ 12.4 ps, floor ±6.2 ps, RMS ≈ 3.6 ps)** for best resolution, with the integer-`O` **1250 MHz** kept as the clean fallback (§6). This ceiling figure is the one carried by `MuroSync_Phasing_Math` (§5a/§8). **PROVISIONAL** — assumes input 156.25 / output 312.5 MHz; the real VCO is fixed when `clk_ctrl` is designed (OPEN-B), at which point all step/floor/budget numbers in **both** documents must be re-derived against the chosen VCO.
**Version:** 0.2 (2026-06-24) — conceptual sharpening from the phase-grid discussion; **no mechanism or number change**. (1) Adds §7 "why the unit is the VCO period" — the output clock is a divided copy of the VCO, so its edge-placement resolution is *inherited from the VCO*, not from its own (slower) period. (2) Makes the absolute-time-vs-angle reading explicit: one step = `T_VCO/56` absolute = `1/56` of the VCO period = `1/(56·O)` of the output period. (3) Generalises the output divider `O` (any integer 1–128, or 1/8-fractional on `CLKOUT0`/`CLKFBOUT`; `O = 2` was only the dev instance) and **standardises the symbol — `O` = `CLKOUT_DIVIDE` (output divider), distinct from `D` = `DIVCLK_DIVIDE` (input pre-divider); v0.1 loosely used `D` for both.** (4) Reframes §6 around the `O ↔ F_VCO` coupling at fixed output (`F_VCO = O · F_out` → they are one knob; the resolution lever is the choice of `O ≈ 2 … 4.56`).
**Version:** 0.1 (2026-06-24) — initial. Extracts and expands the actuator mechanics referenced in `RTL_Architecture §8.3`; closes the open question of the `-2` VCO window (DRC-confirmed 600–1440 MHz) and the dev-board VCO legitimacy.
**Status:** Reference. Hardware-independent (mechanism is Xilinx-defined); the MuroSync-specific numbers (input clock, output frequency, dev VCO) are stated as assumptions and flagged where they need a hand-check. The control loop (`phase_servo`) and measurement (`phase_meas`/TDC) are **out of scope** — this document covers only the public actuator.
**Author:** Mikhail Vasilev / MuroSync · info@murosync.com
**Copyright / licence:** Copyright (c) 2026 Mikhail Vasilev / MuroSync. **Open reference** — the actuator mechanics (PSEN/PSINCDEC/PSDONE handshake) and MMCM parameters are public per `RTL_Architecture §0.1`. Openly shareable with **attribution retained — not public domain**. Contains no proprietary servo/TDC content.
 
> **Relationship to other documents.** This refines the one-paragraph actuator note in `RTL_Architecture §8.3` into a standalone reference. It does **not** touch `phase_servo` (§9.2, core-pro, the control law) or `phase_meas` (§9.1, core-pro, the carry-chain TDC). Where it cites accuracy numbers it cross-references `RTL_Architecture §0.2`; the error budget itself is a separate session.
 
---
 
## 1. Two phase mechanisms — and which one this is
 
An MMCM offers **two independent** ways to move output-clock phase. They are not interchangeable, and the distinction matters because the AMD documentation often shown first (the Clocking Wizard DRP register map, PG065) describes the **wrong one** for a servo.
 
| | (A) Dynamic **fine** phase shift | (B) DRP `CLKOUT_PHASE` reconfig |
|---|---|---|
| Ports / path | `PSEN / PSINCDEC / PSCLK / PSDONE` | AXI/DRP writes to `CLKOUTx_PHASE` regs + `LOAD/SEN` |
| Effect | Live, **glitch-free**, MMCM stays `locked` | Runs the reconfiguration FSM → **MMCM re-locks** |
| Granularity | `T_VCO / 56` per step | degrees × 1000 (coarse, set-and-forget) |
| Use | **Closed-loop correction** (this is what `clk_ctrl` uses) | Static/initial offset, occasional retune |
| In Clocking Wizard | "Dynamic Phase Shift" checkbox → exposes the 4 ports | "Phase Duty Cycle Config" + DRP register space (PG065) |
 
**MuroSync uses (A).** The PG065 registers (`0x20C` = `CLKOUT0_PHASE`, etc.) are mechanism (B) and are **not** on the correction path. This document is entirely about (A).
 
---
 
## 2. Interface (mechanism A)
 
Four ports on `MMCME4_ADV`, all **synchronous to `PSCLK`**:
 
| Port | Dir | Role |
|---|---|---|
| `PSCLK` | in | Phase-shift clock. Drives the handshake. In MuroSync = **local oscillator** (see §8). |
| `PSEN` | in | Phase-shift enable. Held High for **exactly one** `PSCLK` cycle to request one step. |
| `PSINCDEC` | in | Direction: **1 = increment**, **0 = decrement**. Sampled with `PSEN`; hold stable across the move. |
| `PSDONE` | out | Done strobe. High for **exactly one** `PSCLK` cycle when the step completes. |
 
**Enable attributes.** Per output: `CLKOUT[0:6]_USE_FINE_PS = TRUE` (and/or `CLKFBOUT_USE_FINE_PS`). The dynamic shift amount is **common to all selected outputs**. → In MuroSync, set `USE_FINE_PS = TRUE` on the **timing output only**; otherwise every fabric clock moves together.
 
The fine shift accumulates **on top of** the static `CLKOUT_PHASE` initial offset, and is **unbounded in both directions** (you may keep stepping indefinitely — see §7).
 
---
 
## 3. Adjustment mechanism + timing diagram
 
**One step** = `set PSINCDEC` → `pulse PSEN (1 PSCLK)` → `wait PSDONE`. The `PSEN → PSDONE` latency is **deterministic = 12 PSCLK cycles** on UltraScale / UltraScale+. After `PSDONE`, the next step may be requested. The phase does **not** jump: after `PSEN`, the output edge **ramps linearly and glitch-free** to its new position.
 
```
            0   1   2   3   4   5   6   7   8   9  10  11  12  13
          _   _   _   _   _   _   _   _   _   _   _   _   _   _
PSCLK    | |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_
 
PSINCDEC ==<      direction held stable (1 = inc / 0 = dec)      >==
            ___
PSEN     __|   |________________________________________________
            (1 PSCLK wide, cycle 1)                       ___
PSDONE   ________________________________________________|   |__
                                  (12 PSCLK cycles after PSEN)
 
phase     old ----[ linear, glitch-free ramp ]----> new, then HELD
          Δφ per step = T_VCO / 56   (same picoseconds on every selected output)
```
 
**Throughput ceiling.** One step per ~12 `PSCLK` cycles. With `PSCLK` = local osc (~156.25 MHz), that is ~77 ns/step → ~13 Msteps/s raw, far above any need: the correction loop runs at single-/tens-of-Hz bandwidth. The wrapper's `busy`/`done` handshake (§8) serialises requests so the loop never issues a step before `PSDONE`.
 
---
 
## 4. VCO frequency range (the binding device constraint)
 
The step size is set **entirely** by the VCO frequency (§5), so the usable VCO window defines both the achievable resolution and whether a configuration will even build. The authoritative limit is the Vivado VCO-range DRC (`PDRC-34`), which reads the device speed file; the datasheet (DS931) is the formal source.
 
**UltraScale+ MMCM (MMCME4) VCO window — DRC-confirmed:**
 
| Speed grade | F_VCO min | F_VCO max |
|---|---|---|
| −1 | 600 MHz | 1200 MHz |
| **−2 (this part)** | **600 MHz** | **1440 MHz** |
| −3 | 600 MHz | 1600 MHz |
 
- **F_VCO_MIN = 600 MHz** across grades (not 800 — a common misremembering; the 7-series figure of 600 carries forward).
- **PFD frequency range = 10–550 MHz** (`F_PFD = F_in / D`, must stay in band; `D` = `DIVCLK_DIVIDE`).
- Out-of-window configs fail synthesis with `[DRC PDRC-34] … falls outside the operating range of the MMCM VCO frequency for this device`.
> **Dev-board VCO is legitimate.** The MuroSync dev figure of **VCO ≈ 625 MHz** (28.6 ps step, see `RTL_Arch §0.2`) sits **above** the 600 MHz floor → valid, builds, no DRC violation. It is simply at the **coarse end** of the window. The resolution argument in §6 is about moving off it, not fixing a bug.
 
---
 
## 5. Step size
 
**One step = `T_VCO / 56`.**
 
Where the **56** comes from: the VCO exposes **8 equally-spaced phase taps** (0°/45°/…/315° = 1/8 of `T_VCO` each); the fine phase shifter interpolates each tap into **7** sub-steps → **8 × 7 = 56** sub-steps across one full VCO period.
 
**Step vs VCO frequency (Δt = 1 / (56 · F_VCO)):**
 
| F_VCO | Step Δt | Quantisation floor (±½ step) | Notes |
|---|---|---|---|
| 600 MHz | 29.8 ps | ±14.9 ps | window floor |
| **625** | **28.6 ps** | **±14.3 ps** | **current dev** |
| 1000 | 17.9 ps | ±8.9 ps | "target" in §0.2 |
| **1250** | **14.3 ps** | **±7.2 ps** | clean integer (`O = 4`) → 312.5 |
| 1406 | 12.7 ps | ±6.3 ps | near ceiling (fractional `O`) |
| **1440** | **12.4 ps** | **±6.2 ps** | **−2 ceiling (best)** |
| 1600 | 11.2 ps | ±5.6 ps | −3 only |
 
Cross-check of the `1/56` law: AMD's own datasheet states the phase-shift increment is **12.5 ps at F_VCO = 1440 MHz** — matches `1/(56·1440 MHz) = 12.4 ps`.
 
The **step is the actuator's resolution floor**: best-case residual phase error ≈ **±½ step**, independent of loop quality.
 
**One step is an absolute time** = `T_VCO / 56`, identical on every selected output. As a fraction of a *clock's own* period it is **1/56 of the VCO period** but **1/(56·O) of the timing output** (`O` = the output divider) — the same physical move reads as two different angles because the two clocks' periods differ. §7 explains why it is the **VCO** period, not the output period, that sets the resolution.
 
---
 
## 6. Choosing the VCO for best adjustment precision
 
**Principle: push F_VCO to the speed-grade ceiling.** Step size is inversely proportional to F_VCO, so for the `-2` part, **target VCO ≈ 1440 MHz → ~12.4 ps step (~±6.2 ps floor)** — better than 2× finer than the current 625 MHz dev choice, and finer than the 1000 MHz "target" recorded in `§0.2`.
 
**At a fixed output frequency, the output divider and the VCO are one knob, not two.** Since `F_VCO = O · F_out` (`O` = `CLKOUT_DIVIDE`, the output divider), choosing `O` *is* choosing the VCO frequency — and therefore the step: **larger `O` → higher VCO → finer step**, because `step = T_VCO/56 = 1 / (56 · O · F_out)`. For the fixed 312.5 MHz timing output the whole resolution lever is the choice of `O`, bounded by the VCO window:
 
| `O` (→ 312.5 MHz) | F_VCO | M (`CLKFBOUT`, D = 1) | Step | Verdict |
|---|---|---|---|---|
| 2 | 625 MHz | 4 | 28.6 ps | current dev — at the window floor, valid but coarse |
| 3 | 937.5 MHz | 6 | 19.0 ps | integer |
| **4** | **1250 MHz** | **8** | **14.3 ps** | **integer — recommended easy win (2× finer)** |
| ≈ 4.56 | 1426 MHz | 9.125 | 12.5 ps | fractional `O` (`CLKOUT0`), at the `-2` ceiling |
 
`O = 1` is forbidden (312.5 MHz < 600 MHz floor); `O = 5` (1562.5 MHz) exceeds the `-2` ceiling and would need a `-3` part. **The usable band is `O ≈ 2 … 4.56`, and its top edge gives the best step.** (`M = 9.25 → 1445.3 MHz` exceeds 1440 → not allowed; `M = 9.125` is the highest valid 1/8 step. `F_PFD = 156.25 / 1 = 156.25 MHz` ✓ for all rows.)
 
**Constraints to satisfy simultaneously** when picking the multiplier M (`CLKFBOUT_MULT_F`), the input pre-divider D (`DIVCLK_DIVIDE`), and the output divider O (`CLKOUT_DIVIDE`):
1. `600 ≤ F_VCO ≤ 1440` MHz (`-2`), where `F_VCO = F_in · M / D`.
2. `10 ≤ F_PFD = F_in / D ≤ 550` MHz.
3. `O` reaches the timing-output frequency (`F_out = F_VCO / O`). **Integer O** on any `CLKOUTx`; **fractional O** (1/8 steps) only on `CLKOUT0` (and the feedback path). M is likewise fractional in 1/8 steps.
(Assumption for the table above: MMCM input = recovered clock **156.25 MHz**, `D = 1`, timing output **312.5 MHz** — verify against the actual `clk_ctrl` plan.)
 
**Recommendation (design target).** Run F_VCO at the **`-2` ceiling, ≈ 1440 MHz** → **step ≈ 12.4 ps, floor ±6.2 ps** — the finest the part allows, and the figure carried by `MuroSync_Phasing_Math` (§5a/§8). From the assumed 156.25 MHz input the nearest *achievable* point is `M = 9.125` → 1425.78 MHz (12.5 ps, fractional `O ≈ 4.56`). If a fractional output divide is undesirable, the clean **integer fallback is 1250 MHz** (`O = 4`, `M = 8`, 14.3 ps) — still 2× finer than the 625 MHz dev value. Either way this supersedes the `§0.2` "1000 MHz / 17.9 ps" working figure. **PROVISIONAL** — re-derive against the real VCO once `clk_ctrl` is designed (OPEN-B).
 
**Trade-offs of higher VCO.** Marginally higher MMCM power and output jitter; for a tens-of-ps timing budget the resolution gain dominates and MMCM output jitter is spec'd small. (Jitter enters the error budget separately.)
 
---
 
## 7. Discrete grid and full-360° coverage — the conceptual point
 
This is the property to be precise about, because "infinite phase shift" and "wrap at 56" are both easy to misread. *(Throughout this section `O` = the timing-output divider `CLKOUT_DIVIDE`; it is **not** the §6 input pre-divider `D` = `DIVCLK_DIVIDE`.)*
 
**Why the unit is the VCO period, not the output period.** The output clock is not an independent time-base — it is a **divided copy of the VCO**: its counter rolls over after `O` VCO cycles, and *that rollover is the output edge*. So the edge can only be placed where the VCO grid allows — on the fine grid of `T_VCO/56` (§5). The output's own, longer period gives **no** finer placement; **the placement resolution is inherited from the VCO.** That is the whole reason the shift is quantised in VCO-period units even though the clock being moved is the (slower) output. One step is therefore an absolute `T_VCO/56` — `1/56` of the VCO period, but only `1/(56·O)` of the output period.
 
**Within one output-clock period the reachable phase positions form a uniform discrete grid of `56·O` points** (output period = `O · T_VCO`; spacing = `T_VCO/56`):
 
```
 one output-clock period  =  O · T_VCO            (O = CLKOUT_DIVIDE)
 0° |---|---|---|---| ... |---|---|---|---| 360° (= 0°)
    p0  p1  p2                          p(56·O − 1)
    spacing between adjacent points = T_VCO / 56
```
 
This holds for **any** `O` (integer 1–128, or 1/8-fractional on `CLKOUT0`/`CLKFBOUT`): `O = 2` (the dev case, 112 points) was only one instance. Three facts define the behaviour:
 
1. **Full 360° is reachable.** Any position in the period can be reached — no forbidden zones, no sub-range cap, no "operation limited to 56 steps." The loop never has a *range* problem; it can always drive to the required phase.
2. **Discrete, not continuous.** You land on a grid point, never between two. Best-case residual = **±½ step**. This is the floor that §6 minimises by raising F_VCO.
3. **One continuous click, not two mechanisms.** The actuator only ever advances by one `T_VCO/56` tooth; the edge crosses VCO-period boundaries with **no switching** and keeps going indefinitely in either direction. The numbers **56** and **56·O** are *repetition points* — where the phase re-coincides with itself, against the VCO at 56 and against the output at `56·O` — **not** discrete stages and **not** range limits.
> **On the `§8.3` "wrap at 56" note.** That `mod 56` is the **actuator wrapper's accumulator bookkeeping** (the fine offset within one VCO period) — it is **not** a hardware limit, and **not** the output-period wrap. If `phase_servo` needs to express position over a full **output** period, its unwrap arithmetic must use **`56·O`**, not 56. (If the fine layer only ever covers a sub-range and the integer part is carried by the RTT/coarse layer, this is moot — but state explicitly in the servo which one the accumulator represents.)
 
**Consequence for the loop.** Because the actuator is quantised, a **deadband ≥ ~1 step is mandatory** in `phase_servo` (anti-chatter): without it the loop limit-cycles between adjacent grid points. The grid spacing (= the step) is exactly why raising F_VCO toward the ceiling is worthwhile.
 
---
 
## 8. MuroSync integration notes
 
- **Correction lands on the slave.** The actuator is active on the slave (the master is the reference and does not phase-shift itself). On the master, `clk_ctrl` runs on local osc as the system reference. (`RTL_Arch §8.4`.)
- **`PSCLK` = local oscillator**, never a switched/recovered clock. The step command crosses from the protocol/AXI domain into the `PSCLK` domain via the wrapper's CDC (level-sync + req/ack multibit capture). (`§8.3`.)
- **MMCM RESET pulse required when switching the BUFGMUX source** (local ↔ recovered) — existing lesson; the select-FSM's switch action must issue it. (`§8.2`.)
- **Only the timing output carries `USE_FINE_PS`** — see §2.
- **Command-source agnostic.** Steps come from the decoded protocol command (operational) or from a hand-written AXI register (bring-up). This agnosticism is what keeps the wrapper public. (`§8.3`.)
- **Error-budget hook.** The step (= `T_VCO/56`) is the actuator resolution floor; it must appear explicitly in the alignment error budget (`σ_align ≥ ½·step`). The `§0.2` reconciliation (5–10 ps RMS is **not** achievable MMCM-only; floor ≈ ½ step) is consistent with this and is resolved in the error-budget session.
---
 
## 9. Open / verify-by-hand items
 
- **OPEN-A.** Confirm the exact `-2` VCO window in **DS931** (MMCM Switching Characteristics table). DRC reports **600–1440 MHz** consistently for `-2`; the datasheet is the formal authority. *(The AMD doc portal renders this table only via JavaScript — read it in the PDF or in Vivado's IP report.)*
- **OPEN-B.** **Decide the production VCO.** Design target = the **`-2` ceiling ≈ 1440 MHz** (finest step ≈ 12.4 ps); nearest achievable from the assumed input is **~1426 MHz** (`O ≈ 4.56`, ≈12.5 ps), with **1250 MHz** (`O = 4`, 14.3 ps) as the clean integer fallback. Supersedes the `§0.2` "1000 MHz" figure. Verify the assumed input (156.25 MHz) and timing-output (312.5 MHz) frequencies against the real `clk_ctrl` plan before fixing M/D/O — **and once fixed, refresh the step/floor numbers in `MuroSync_Phasing_Math` (§5a/§8) to match.**
- **OPEN-C.** In `phase_servo`, fix and document **which wrap the accumulator represents** — `mod 56` (one VCO period) vs `mod 56·O` (one output period). §7.
- **XREF.** The accuracy reconciliation (no sub-tens-of-ps MMCM-only) lives in the error-budget session; this document only supplies the actuator floor.
---
 
## References
 
- **UG572** — UltraScale Architecture Clocking Resources (MMCME4_ADV ≡ MMCME3_ADV with E4): dynamic fine phase shift, `PSEN/PSINCDEC/PSCLK/PSDONE`, `1/56·T_VCO` step, linear glitch-free move, `USE_FINE_PS` attributes, 8 VCO phase taps.
- **DS931** — Artix UltraScale+ Data Sheet (DC/AC Switching Characteristics): MMCM Switching Characteristics (F_VCO, F_PFD windows). *(Not DS923 — that is Virtex UltraScale+.)*
- **DS197 / DS180** — 7-series datasheets: cross-check of the `1/56` law (12.5 ps @ 1440 MHz).
- **PG065** — Clocking Wizard (mechanism **B**, DRP `CLKOUT_PHASE` — for contrast only).
- **UG576** — UltraScale GTH Transceivers (recovered-clock source for the actuator input).
- **Internal:** `RTL_Architecture` §0.1 (public/private boundary — actuator is public), §8.2–8.4 (`clk_ctrl`), §9.1–9.2 (core-pro `phase_meas` / `phase_servo` — out of scope here), §0.2 (accuracy reconciliation).
 
