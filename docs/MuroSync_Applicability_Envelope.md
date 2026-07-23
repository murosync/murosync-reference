# MuroSync — Applicability Envelope

**Distance, cascade depth, channel capacity, timing-layer definition, and application classes — derived from first principles.**

**Author:** Mikhail Vasilev · MuroSync · **Date:** 2026-06-19 (rev 2026-07-23) · **Status:** estimate (v0.2)

---

> **v0.2 (2026-07-23) — application taxonomy and timing-layer definition; no change to the physics or the headline numbers.**
> 1. **New §7 "Timing-layer definition"** — two framing principles distilled from the application review: (a) MuroSync is a *complementary* precision layer on top of facility-wide time distribution, not its replacement; (b) MuroSync operates at the *event-and-trigger* timing layer, not at the carrier-phase layer. These two principles explain every in/out-of-niche decision in §8 from a single vantage point.
> 2. **§8 "Applications by distance class"** (was §7) — table populated with the reviewed domain taxonomy: accelerator facilities (medical and industrial machines through km-class linacs), fusion fast-diagnostic clusters, particle-therapy centres, Cherenkov telescope arrays, TOF-PET, ultrafast-science setups (UED/UEM), crate-level integration via the FMC synchronization core. Out-of-niche examples extended (VLBI, power-grid PMU, telecom, UTC-traceability).
> 3. **§3 budget-as-a-knob** — one explicit conclusion added under the sub-budget table: the 50 ps budget is a design point, not a constant; relaxed budgets extend reach proportionally (e.g. ~2.9 km single-link at 100 ps), which covers 2–3 km-class linear machines.
> 4. **§2 / §12 σ_align note updated** — the recommended design-target VCO has since been designated (`MuroSync_MMCM_Phase_Adjustment.md` v0.3: F_VCO ≈ 1440 MHz → step ≈ 12.4 ps, floor ±6.2 ps, RMS ≈ 3.6 ps). The headline **σ_align ≈ 15 ps is deliberately retained** pending the error-budget session (MMCM OPEN-B not closed); the note records the trail.
> 5. **§8 relative-mode paragraph strengthened** — perturbation-class applications are relative measurements; the system operates there in its most favourable regime (asymmetry cancels as a DC constant).
> 6. **Cross-reference repair** — v0.1 contained stale section pointers ("→ §13", "(§11)" for the out-of-niche section) left over from an earlier renumbering; all internal references now match the actual section numbers. Sections after §6 are renumbered (+1) due to the new §7.

---

> **STATUS — read first.** This document is an **applicability envelope at current estimates**, not a guarantee sheet. Two inputs are *estimates*, flagged throughout and listed in §12:
> - **chromatic asymmetry ≈ 34 ps/km** — from *typical* G.652 datasheet parameters (S₀, λ₀), not a measured value for a specific fibre lot;
> - **node alignment residual σ_align ≈ 15 ps** — derived below from carry-chain and MMCM-step resolution; the exact figure depends on the live MMCM VCO period and carry-tap delay (verify via Vivado `get_property` / timing report).
>
> All length/cascade/channel limits scale with these two numbers. They are **refined by the error-budget session**. Treat the numbers here as *order-correct envelopes for positioning*, not final specifications.

---

## 0. Summary — the niche in one screen

| Quantity | Value (at current estimates) |
|---|---|
| One-way chromatic asymmetry (1270/1330 on G.652) | **≈ 34 ps/km** |
| Single-node alignment residual σ_align (MMCM-step-limited) | **≈ 15 ps** |
| Total sync budget (target accuracy) | **50 ps** |
| **Max protected length — single link** | **≈ 1.4 km** |
| **Max protected length — with cascade** | **≈ 2.4 km** (5–6 hops) |
| Cable-vs-cascade crossover | **≈ 1 km** (below: cable; above: cascade) |
| Max cascade depth (node-residual only) | **11 hops** (practically far fewer) |
| Channel capacity | **not the limit** — 8ᵈᵉᵖᵗʰ × 16 (128 / 1024 / 8192 at depth 1/2/3) |

**One-line positioning:** MuroSync is a **local / facility-scale** timing system — single hall, detector, or building, **≤ ~1.4 km on one link**, extendable to **~2.4 km** by boundary-clock cascade — delivering **WR-class (~tens of ps)** synchronization on **standard single-strand G.652 fibre**, with asymmetry handled **from cable datasheets alone, no per-cable calibration**. It is **not** a machine-wide (tens-of-km) accelerator timing system; that regime (e.g. LHC ring) belongs to WR-switch chains + RF distribution + active stabilization (§10).

---

## 1. Physical basis — chromatic asymmetry

Single-fibre bidirectional (BiDi) operation sends the two directions on **different wavelengths** (here **1270 nm** forward, **1330 nm** return). The two wavelengths travel at slightly different group velocities → the forward and return delays differ → `RTT/2 ≠ one-way delay`. This **chromatic group-delay asymmetry** is the dominant length-dependent error term for single-fibre links.

Around the G.652 zero-dispersion wavelength (λ₀ ≈ 1313 nm), dispersion is `D(λ) ≈ S₀·(λ − λ₀)` with slope `S₀ ≈ 0.086 ps/(nm²·km)`. The asymmetry (difference in group delay between the two wavelengths, per unit length) is:

```
Δτ/L = (S₀/2)·[(λ₂−λ₀)² − (λ₁−λ₀)²]
     = (0.086/2)·[(1330−1313)² − (1270−1313)²]
     = 0.043·[289 − 1849]  ≈ −67 ps/km   (round-trip)
```

The error that enters the one-way delay (and hence absolute alignment) is **half** of this:

> **One-way asymmetry ≈ 34 ps/km.**

**Wavelength choice matters — and ours is favourable.** 1270/1330 straddles λ₀ with a 60 nm split. Classic White Rabbit BiDi (1310/1490, 180 nm split, 1490 far from λ₀) yields a **several-fold larger** asymmetry. Our wavelength pair is **already near the practical optimum for standard fibre** (§11). *Estimate dependency:* the 34 ps/km figure uses typical G.652 S₀/λ₀; a specific fibre lot may differ by a few % (→ §12).

---

## 2. Node alignment residual σ_align

The per-node alignment error is set by **two instrument resolutions**, and the coarser one dominates:

**(a) Carry-chain TDC — what we can *measure*.** Phase is measured by propagation delay along a carry chain; LSB ≈ one carry-tap delay (~10 ps/tap in UltraScale+, ~320 taps span the 3.2 ns period). Window-averaging improves the statistical figure toward single ps, but differential nonlinearity (DNL) of the chain sets a floor of **~2–5 ps** after averaging. **Measurement is not the bottleneck.**

**(b) MMCM phase step — what we can *actuate*.** Phase is shifted in **discrete steps** of `T_VCO / 56`. For a VCO in the ~1–1.6 GHz range this is **≈ 11–18 ps per step**. The loop cannot align finer than one step; it dithers within ±step/2 of the target.

```
TDC (measure)   : ~2–5 ps after averaging   → not limiting
MMCM (actuate)  : ~11–18 ps per step        → DOMINATES (this is the floor)
```

> **σ_align ≈ 15 ps**, set by the MMCM step (≈ step/√12 plus jitter and TDC residual).
>
> **Floor:** alignment **cannot** be claimed below the MMCM step (~12–18 ps) without **interpolation / two-stage** phase control. Sub-step accuracy (the "5–10 ps" aspiration) is therefore an **open item** (two-stage interpolation), not a present capability.

*Estimate dependency:* exact step = live `T_VCO`/56; exact tap delay from the timing report. Verify both on the target build (→ §12).

*Design-target trail (v0.2):* since v0.1, the recommended design-target VCO has been designated — `MuroSync_MMCM_Phase_Adjustment.md` v0.3: **F_VCO ≈ 1440 MHz → step ≈ 12.4 ps, floor ±6.2 ps, RMS ≈ 3.6 ps** (provisional until `clk_ctrl` fixes the production VCO, MMCM OPEN-B). The headline **σ_align ≈ 15 ps is deliberately retained** here as the conservative envelope figure **pending the error-budget session**; all length limits in this document continue to use 15 ps.

---

## 3. Max protected length — single link

The total budget (50 ps) is shared between node residual and asymmetry. Treating them as independent (quadrature):

```
budget² = σ_align² + (34·L)²   →   L_max = √(budget² − σ_align²) / 34
        = √(50² − 15²) / 34 = 47.7 / 34 ≈ 1.40 km
```

For reference, the asymmetry-only length under different sub-budgets:

| Asymmetry sub-budget | Single-link L_max |
|---|---|
| 10 ps | 0.29 km |
| 25 ps | 0.74 km |
| 34 ps | 1.00 km |
| 50 ps | 1.47 km |
| 100 ps | 2.94 km |
| 200 ps | 5.88 km |

> **Single-link protected length ≈ 1.4 km at a 50 ps budget** (with the node already consuming 15 ps). Within one hall or building this is ample; asymmetry there is single- to low-tens of ps.
>
> **The budget is a knob, not a constant.** 50 ps is the design point for the headline niche, but the table above is the real deliverable: at a **100 ps** budget the single-link reach extends to **≈ 2.9 km** — covering **2–3 km-class linear machines** (SLAC- / European-XFEL-scale linacs) on a single link or a shallow cascade. Applications state their own budget; the envelope rescales accordingly.

---

## 4. Cascade — max hops and cable lengths

To exceed the single-link reach, the span is broken into short links joined by **boundary-clock repeaters** (Type-3 nodes: slave port upstream, master array downstream). Synchronization is **staged and transitive**: level 1 (master ↔ repeater), level 2 (repeater ↔ next), etc. Each short link's asymmetry is small; the cost is that **each hop adds its own alignment residual**, accumulating as **√N** (uncorrelated residuals):

```
σ_cascade(N, D) = √N · √( σ_align² + (34 · D/N)² )
```

where **D** is the total span and **N** the number of hops (link length = D/N). This has an **optimum N**: too few hops → large per-link asymmetry; too many → √N grows.

**No inline optical amplifiers.** An EDFA/repeater that merely re-amplifies breaks round-trip reciprocity and injects its own asymmetric, drifting delay. Only full boundary-clock **nodes** (which re-measure phase) are permitted in the path.

**Two hard limits on cascade depth:**

1. **Accuracy (node-residual only, short links):** `√N · σ_align ≤ budget` → `N ≤ (50/15)² ≈ 11 hops`.
2. **Accuracy (including per-link asymmetry):** the optimized cascade stays within 50 ps only up to **≈ 2.4 km** total (then even the best N exceeds budget — see §5).

So the **11-hop figure is a ceiling for node accumulation alone**; once realistic link asymmetry is included, the *distance* runs out (~2.4 km) well before the *hop count* does.

**Non-metrological cost of cascading.** Each repeater is a full timing node: it carries core-pro (TDC + loop filter), needs power, a chassis, and is an **active point of failure**. A passive cable has none of these. Near the crossover, prefer the cable for reliability even at equal accuracy.

---

## 5. Optimal setup — link length × hop count for a given span

Optimizing `σ_cascade(N, D)` over N:

| Total span D | Optimal N | Link length | σ_cascade | Single cable (asym) | Within 50 ps? |
|---|---|---|---|---|---|
| 0.5 km | 1 | 0.50 km | 22.7 ps | 17 ps | ✅ (cable simpler) |
| 1 km | 2 | 0.50 km | 32.1 ps | 34 ps | ✅ |
| 1.5 km | 3 | 0.50 km | 39.3 ps | 51 ps (over) | ✅ (cascade) |
| 2 km | 5 | 0.40 km | 45.3 ps | 68 ps (over) | ✅ (cascade) |
| 2.4 km | 5–6 | ~0.40 km | ~50 ps | — | ✅ (limit) |
| 3 km | 7 | 0.43 km | 55.3 ps | 102 ps | ❌ over budget |
| 13 km | 29 | 0.45 km | 115 ps | 442 ps | ❌ far over |
| 27 km | 39 | 0.69 km | 174 ps | 918 ps | ❌ far over |

**Reading the table:**
- **D ≤ ~1 km:** a **single cable** meets budget and is simplest — no repeaters. *This is the core operating point.*
- **~1 ≤ D ≤ ~2.4 km:** a **short cascade** (links ~0.4–0.5 km, N = 2–6) is required and works.
- **D > ~2.5 km:** even the optimal cascade exceeds 50 ps — **outside the niche** at this accuracy (→ §10).

> **Optimal setup rule of thumb:** keep individual links at **~0.4–0.5 km**, add repeaters only past ~1 km, and recognise a hard wall near **~2.4 km** for 50 ps accuracy. The crossover where cascade first beats a single cable is **≈ 1 km**.

---

## 6. Channel capacity

Two independent multipliers:

- **Fan-out per node:** **8** downstream ports (SFP+ array on master/repeater).
- **Endpoints per slave:** **16** trigger channels (SMA/LEMO).

A tree of depth *d* therefore reaches `8ᵈ` leaf nodes and:

```
channels(d) = 8ᵈ × 16
```

| Tree depth | Leaf (slave) nodes | Endpoint channels |
|---|---|---|
| 1 | 8 | 128 |
| 2 | 64 | 1,024 |
| 3 | 512 | 8,192 |
| 4 | 4,096 | 65,536 |

> **Channel count is *not* the binding constraint.** Even at depth 3 the system reaches **8,192 channels**, far beyond any plausible facility demand. The real limit is the **distance × accuracy** trade-off (§5): tree depth equals cascade-hop depth, so it is bounded by the accuracy budget, not by addressing or fan-out. In practice the channel number is **effectively unbounded for the niche**; specify it as "N endpoints across the tree, where N is limited by accuracy-bounded depth, not by the architecture."

---

## 7. Timing-layer definition — what layer MuroSync occupies

Two principles define the layer this envelope applies to. They were distilled from reviewing candidate application domains and explain every in/out decision in §8 from a single vantage point.

**(a) A complementary layer, not a replacement.** Large facilities already operate facility-wide time distribution — White Rabbit networks, PTP/IEEE-1588 infrastructure, MRF event systems, machine control timing (e.g. CODAC-class systems in fusion). MuroSync is a **local precision layer on top of, or alongside, that infrastructure**: it aligns a cluster of instruments to tens-of-ps where the facility-wide network's µs/ns class is insufficient — it does not replace the facility network, its traceability, or its management plane. (Corollary: applications whose *primary* requirement is traceability to an absolute time scale — UTC-anchored timestamping, regulatory compliance, metrological time transfer — are out of scope by definition: MuroSync synchronizes nodes *to each other*, not to UTC.)

**(b) The event-and-trigger layer, not the carrier-phase layer.** MuroSync aligns **when things happen** — trigger edges, event timestamps, acquisition windows — with tens-of-ps determinism. It does **not** stabilize the phase of carrier signals: femtosecond-class RF phase reference distribution (LLRF, klystron drive), heterodyne/local-oscillator coherence in interferometric arrays, MRI gradient/RF phase — all belong to dedicated stabilized-RF or photonic phase-transfer systems. The recurring boundary across domains (accelerators: event timing vs LLRF; fusion: diagnostics vs machine control; observatories: stereo trigger vs LO coherence) is this same watershed.

> **Layer in one line:** MuroSync aligns *events*, at *facility-local* scale, *on top of* existing time infrastructure — not carrier phase, not wide-area, not UTC.

---

## 8. Applications by distance class

| Distance class | Span | Setup | Fits the niche? | Example applications |
|---|---|---|---|---|
| **Intra-rack / crate** | < 10 m | single link, no calibration | ✅ ideal | VME/PXI/µTCA DAQ sync via the FMC synchronization core on platform carriers; module-to-module trigger; compact machines (medical linacs, industrial e-beam, ion implanters) |
| **Single hall / detector cavern** | tens–hundreds m | single link, datasheet asym | ✅ core niche | detector DAQ synchronization; trigger distribution; **timing-perturbation validation for event-based AI**; fusion fast-diagnostic clusters (scattering, neutron/ToF spectrometry, magnetics); TOF-PET detector rings and gantry instrumentation; ultrafast-science setups (UED/UEM, pump-probe endstations) |
| **Building / facility wing** | up to ~1.4 km | single link | ✅ | distributed DAQ across a building; multi-instrument sync; FEL-class linear accelerators (≤ ~1.4 km end-to-end); particle-therapy centres (machine + beamlines + treatment rooms) |
| **Campus** | ~1.4–2.4 km | short cascade (2–6 hops) | ✅ (with repeaters) | linked experimental areas; multi-building labs; Cherenkov telescope arrays (site-local stereo trigger and event correlation); 2–3 km-class linacs **at relaxed budgets** (§3: ~2.9 km single-link at 100 ps) |
| **Machine-wide / wide-area** | ≫ 10 km | — | ❌ out of niche | accelerator ring timing (→ WR-switch chains + RF, §10); VLBI and long-baseline interferometry (independent masers + post-correlation); geographically distributed networks (power-grid PMU, telecom); UTC-traceability / regulated timestamping (§7a corollary) |

**Primary application — timing-perturbation validation (relative).** The flagship use case (controlled timing skew/drift/jitter injection to measure ML/event-based-system sensitivity; SNN/STDP, event cameras, multi-sensor fusion, ToF-PET, scientific DAQ+ML) is a **relative** measurement: it detects *changes* in phase, not absolute moments against a remote device. For relative measurements, **asymmetry is a static DC constant that cancels** — it does not enter the perturbation signal, and its slow thermal drift is far below the perturbation bandwidth. **The system operates here in its most favourable regime, free of absolute-asymmetry constraints** — the entire asymmetry/length analysis above is secondary to the primary use case and matters only for the *absolute* synchronization regime.

---

## 9. Asymmetry handling — datasheet-only, no per-cable calibration

A defining constraint: asymmetry is compensated from **fibre datasheet parameters** (dispersion slope S₀, zero-dispersion wavelength λ₀) plus the **known link length** L (from installation records or coarse-RTT) — computed as `Δτ_asym = (S₀/2)·[(λ₂−λ₀)²−(λ₁−λ₀)²]·L`. **No per-cable metrological calibration is required.**

This preserves the core value proposition — **works on existing standard G.652 fibre** — and avoids the operational burden of calibrated cable assemblies on the optical line. (One-time loopback calibration of the deployed link *can* tighten the figure by measuring the actual fibre instead of using the datasheet, and remains available as an option for long links, but it is **not a requirement** of the base approach.)

> **Boundary note (copper, not fibre).** On the **copper trigger outputs** (SMA/LEMO, downstream of the FMC connector) there is no feedback loop; there, equal-length / calibrated cable assemblies or per-output offsets *are* the user's integration contract (per Master_Reference §2.3, two-level model). That is a separate, already-documented matter and is **not** the optical asymmetry discussed here.

---

## 10. Out-of-niche boundary — LHC as the worked example

The LHC ring (**26.7 km** circumference; ~13 km half-ring from a central source) makes the boundary concrete:

| Approach | σ at 13 km | Within 50 ps? |
|---|---|---|
| Single cable | 34 × 13 ≈ **442 ps** | ❌ (9× over) |
| Optimal cascade (N ≈ 23) | **~210 ps** | ❌ (4× over) |

> At machine scale, **neither a single link nor a boundary-clock cascade reaches ~50 ps** — single-fibre BiDi + boundary clocks is the wrong tool here. This regime requires **mature, specialized infrastructure**: WR-switch chains, separate **RF phase distribution**, temperature-stabilized runs, and active length compensation. This is the class of system CERN already operates (White Rabbit originated there for exactly this).

**This is a positioning boundary, not a deficiency.** MuroSync targets the **local** scale. The LHC distinction is illustrative:
- **LHC machine timing** (26 km ring) → **out of niche** (WR + RF, CERN-class).
- **An LHC experiment / detector** (ATLAS, CMS caverns — hundreds of metres) → **in niche** (DAQ sync, trigger, perturbation validation).

State this explicitly in grant materials: MuroSync is **local/experimental timing + perturbation validation**, **not** machine-wide accelerator timing.

---

## 11. Wavelength / fibre rationale (why standard fibre, not exotic)

A lower-dispersion fibre (DSF/NZ-DSF, zero-dispersion shifted into the operating window) *would* reduce asymmetry to single ps/km. It is **rejected** because: (a) it requires special fibre rarely present in real infrastructure; (b) DSF is largely obsolete (four-wave-mixing in DWDM); (c) requiring it would forfeit the **universality** ("runs on your existing G.652"). The asymmetry win has instead been taken **via wavelength choice** (1270/1330 near λ₀ on standard fibre — §1), which is the optimum available *without* demanding non-standard infrastructure. Further improvement is pursued through **calibration/cascade** (which work on any fibre), not exotic media.

---

## 12. Assumptions & dependencies (refine list)

Every length/cascade/channel figure above depends on the following. **All are to be confirmed/refined in the error-budget session before any number is treated as a specification.**

1. **Asymmetry 34 ps/km** — from typical G.652 S₀ ≈ 0.086 ps/nm²/km, λ₀ ≈ 1313 nm. *Refine:* use the actual deployed fibre's datasheet (lot-specific S₀/λ₀); a few-% variation moves all lengths proportionally.
2. **σ_align ≈ 15 ps** — from MMCM step (T_VCO/56) dominating carry-chain TDC. *Refine:* read the live VCO period (`get_property` on the MMCM instance) and the carry-tap delay (timing report) on the target build. **Floor = MMCM step (~12–18 ps); sub-step accuracy requires two-stage interpolation (open).** *Trail (v0.2):* design-target VCO designated (`MuroSync_MMCM_Phase_Adjustment.md` v0.3 — F_VCO ≈ 1440 MHz, step ≈ 12.4 ps, floor ±6.2 ps); headline retained at 15 ps pending the error-budget session and MMCM OPEN-B closure.
3. **Budget = 50 ps** — assumed target. *Refine:* set by the full error budget (TDC residual, clock jitter, optical/SFP, temperature, residual path asymmetry, loop BW). If the honest target differs, all L_max/cascade limits rescale (§3: the budget is a knob; the sub-budget table is the general deliverable).
4. **√N hop accumulation** — assumes uncorrelated per-node residuals. *Refine:* correlated error sources (shared reference, common-mode temperature) could change the exponent.
5. **Fan-out 8, endpoints 16** — from current hardware (8× SFP+, 16× SMA). Fixed by board design.
6. **Quadrature combination** of node + asymmetry — a modelling choice; worst-case linear addition would tighten limits (e.g. single-link L_max ≈ 1.0 km instead of 1.4 km).

---

*MuroSync Applicability Envelope v0.2 — 2026-07-23 — Mikhail Vasilev · MuroSync. Estimate for positioning and grant scoping; not a specification. Derived from chromatic asymmetry (≈34 ps/km on standard G.652 at 1270/1330) and MMCM-step-limited node residual (≈15 ps). Niche: local/facility timing ≤ ~1.4 km single-link, ~2.4 km cascaded, WR-class accuracy on standard single-strand fibre, datasheet-only asymmetry handling; event-and-trigger layer, complementary to facility-wide time distribution (§7). Out of niche: machine-wide (tens-of-km) timing, carrier-phase stabilization, UTC-traceability applications. Refine all figures via the error-budget session.*

---

Copyright (c) 2026 Mikhail Vasilev / MuroSync.

This document is openly shareable. Copyright and attribution are retained by the author; please preserve this notice when redistributing.

Contact: info@murosync.com
