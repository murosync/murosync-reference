# MuroSync Phase 1 — GT Tuning Research

**Версия документа:** 3.0 (обновлено 2026-06-13)
**Контекст:** Phase 1 closure debug — extended optical BER test через BiDi SFP+
**Статус:** physical link рабочий (CH0 aligns, symmetric patterns ~10⁻⁶); residual
data-intrinsic realign на 0x12341234 (~1568/2s, WER 1.3×10⁻³) — **архитектурно
относится к frame-layer (Phase 2), не к physical layer.**
**Источники:** UG576, PG182, Xilinx Community Forums, Xillybus working SFP+ design,
ADI EngineerZone, Eli Billauer empirical findings

> ⚠️ **ВАЖНО — читать §10 перед действиями.** Тело §1–§9 ниже — честный снимок
> состояния на **2026-05-29** (v2.0). Несколько его выводов и весь action plan
> (§5 secondary tuning, §6 steps) **с тех пор пройдены и пересмотрены** — в
> частности предложенные `RX_COMMA_VALID_ONLY` и `RX_BUFFER_RESET_ON_COMMAALIGN`
> tuning'и оказались неполными, а PMA NEAR-END discriminator выполнен. Главный
> вывод июня — **realign data-intrinsic и не лечится на physical layer; gating
> через freeze RXPCOMMAALIGNEN убит как несовместимый с конфигом (H2).** Актуальное
> состояние и killed-hypothesis — в **§10 (2026-06-13 update)**. §1–§9 сохранены
> как research-история, не как текущее руководство.

---

## TL;DR

После применения двух GT Wizard параметров (`RX_PPM_OFFSET = 0 → 200`,
`RX_TERMINATION = PROGRAMMABLE → AVTT`):

- **2/7 → 7/7 patterns** достигают FSM LOCKED
- Lock на trial AAAA теперь **honest** (XOR 0x00A0, 3 битфлипа) вместо
  **false** (XOR 0xBDBD, 12 битфлипов в предыдущей iteration)
- CDR tracking подтверждённо работает

**Phase 1 НЕ закрыта:**
- BER ~10⁻⁴ на CH1 по всем паттернам
- RXBYTEREALIGN counter растёт (~5-50k events / 300ms trial)
- Источник остающихся errors — НЕ PPM (это починили)

**Следующий шаг:** PMA NEAR-END loopback diagnostic для discrimination
"local vs external loop signal integrity issue".

---

## 1. Reversal of "force DFE" hypothesis

В начале сессии была гипотеза: переключить equalization с LPM на DFE,
потому что `INS_LOSS_NYQ` в одном из reports показывался как 20 dB
(порог Auto → DFE). На практике это оказалось неверным заходом, и три
независимых источника подтвердили что LPM правильный выбор.

### 1.1 Xilinx official recommendation

Xilinx Community Forums (Ashish post):

> LPM mode recommended for applications with line rates up to 11.2 Gb/s
> for short reach applications, with channel losses of 12 dB or less at
> the Nyquist frequency. Whilst DFE mode is suitable for medium- to
> long-reach applications, with channel losses of 8 dB and above at the
> Nyquist frequency.

Наш случай (6.25 Gbps, FH1223 FMC + SFP+ cage, ~3m fiber, total loss
~5-7 dB на Nyquist 3.125 GHz) — **точно в LPM range**.

### 1.2 Eli Billauer empirical study

billauer.co.il/blog/2020/09 — UltraScale GTH eye scan comparison
LPM vs DFE на USB 3.0 5 Gbps:

> ...even with the AGC issue away, the eye scan for DFE is slightly
> worse than LPM. There are three connectors on the signal paths, each
> making its reflections. DFE should have done better.

> This, along with the Wizard's mechanism for turning off the AGC for
> stronger signals, seems to indicate that the DFE didn't turn out all
> that well on Ultrascale devices, and that it's better avoided.

И критически важно для нашего сетапа:

> while the insertion loss setting doesn't make any difference with the
> LPM equalizer (at least not in the range between 0 and 14 dB), it
> does influence the behavior of DFE.

То есть **INS_LOSS_NYQ влияет только на DFE branch**. На LPM (наш
выбор) этот параметр в диапазоне 0-14 dB ничего не меняет.

### 1.3 ADI EngineerZone DAQ2.KCU105 case

ez.analog.com/fpga/f/q-a/51713 — JESD204B link на Kintex UltraScale GTH:

ADI's no-OS software для DAQ2.KCU105 изначально ставил DFE по дефолту.
Intermittent errors (~1 ошибка на 10⁵ samples). Переключение на **LPM
полностью устранило errors**.

> Xilinx recommends LPM rather than DFE. This results in the default
> equalization mode being set to DFE rather than LPM. This is unlikely
> to be suitable in the majority of applications. We saw eye scan
> violating the JESD mask.

### 1.4 Critical insight (edaboard / AR# 61695, 56894)

> The 8B/10B coding of the ethernet link does not guarantee enough
> randomness of the data for the DFE mode to be stable in all
> circumstances.
> http://www.xilinx.com/support/answers/61695.html
> http://www.xilinx.com/support/answers/56894.html
>
> The default DFE mode is not good when you use SFP modules close to
> the FPGA.

**Это прямо описывает наш сетап.** Мы используем 8B/10B (FIXED pattern
с K28.5 comma maintenance), SFP+ модули близко к FPGA через короткий
FMC. DFE adaptation требует data randomness; наши паттерны (особенно
FIXED 0xAA повторяющийся) — антоним randomness.

### 1.5 Финальное решение

**Оставлен AUTO → LPM** (через `INS_LOSS_NYQ=7` < 14 dB порог).
Hypothesis "force DFE" отбракована.

---

## 2. PPM offset hypothesis (verified ✓)

### 2.1 Hardware setup

Из `MuroSync_Dev_Bench_Architecture.md`:

- 2× ACAU15 SoM with SiTime **SIT9121AI** @ 156.25 MHz on-board oscillator
- Each board has its **own independent refclk** (GTREFCLK00 = MGTREFCLK1_225)
- No shared clock distribution between boards on this dev bench

### 2.2 SiT9121AI tolerance анализ

Из SiTime datasheet, family SIT9121:
- Frequency stability: typical ±25 ppm initial, ±50 ppm total over
  lifetime/temperature
- Two independent parts → worst case difference = sum of both =
  **±50 to ±100 ppm**

На line rate 6.25 Gbps: 100 ppm drift = 1 UI per 10000 bits. CDR
обязан tracking phase через phase interpolator на rate ~625 kHz
(если drift accumulation = 1 UI per 10000 bits).

### 2.3 PPM offset = 0 — что значило

Параметр `RX_PPM_OFFSET` в GT Wizard Advanced конфигурирует **CDR
tracking loop bandwidth** и **phase interpolator update rate**.

PPM=0 означает: Xilinx tool предполагает frequency match exactly
между TX и RX, оптимизирует CDR на minimal tracking effort.

При реальном PPM mismatch 50-100 ppm CDR:
- Не успевает компенсировать phase drift на длинных run lengths
- Накапливает phase error → desync на patterns с density transitions
  ниже порога
- Особенно страдают patterns после 8B/10B где transitions distributed
  неравномерно

### 2.4 Working reference: Xillybus SFP+ optical

xillybus.com/xillyp2p/optical-fiber-ultrascale-gth — public working
example UltraScale GTH + optical SFP+ @ 5 Gb/s, two boards two refclks.

Их Wizard settings:

| Parameter | Xillybus | Наш сетап (after fix) |
|---|---|---|
| PPM offset | **200** | **200** ✓ |
| Termination | **AVTT** | **AVTT** ✓ |
| Encoding | Raw (none) | 8B/10B |
| Equalizer | Auto (LPM) | Auto (LPM) ✓ |
| Link coupling | (n/a) | AC ✓ |

Цитата:

> The ppm frequency offset is set to 200 ppm, accounting for a 100 ppm
> clock oscillator tolerance on each side. This is likely an
> exaggerated figure.

### 2.5 Empirical verification на железе

**Pattern sweep results (CH1, ch_mask=0x2):**

| Pattern | Before (PPM=0) | After (PPM=200 + AVTT) |
|---|---|---|
| AAAA | LOCKED, false (XOR 0xBDBD = 12 flips) | LOCKED, honest (XOR 0x00A0 = 3 flips) |
| 0000 | LOCKED | LOCKED |
| FFFF | never locked | LOCKED |
| 5555 | never locked | LOCKED |
| 1212 | never locked | LOCKED |
| 1234 | never locked | LOCKED (slow ~370 ms) |
| 12345678 | never locked | LOCKED |
| **Score** | **2/7** | **7/7** |

Honest-vs-false lock distinction в trial AAAA — критический evidence:
до fix lock защёлкивался на garbage data (12-bit mismatch); после fix
lock защёлкивается на **реально совпадающие** bytes с минимальным
post-lock noise (3-bit flips, что соответствует ~10⁻⁴ BER).

**PPM hypothesis confirmed.**

### 2.6 TCL verification of applied parameters

```
set gt [get_ips -all gtwizard_ultrascale_0]
IP_DIR  = murosync_poc_v1.gen/.../
          gtwizard_ultrascale_0_ex.srcs/.../
          ip/gtwizard_ultrascale_0
CONFIG.RX_PPM_OFFSET    = 200    ✓
CONFIG.RX_TERMINATION   = AVTT   ✓
CONFIG.RX_COUPLING      = AC     ✓
CONFIG.RX_EQ_MODE       = AUTO   ✓ (→ LPM at INS_LOSS_NYQ=7)
CONFIG.INS_LOSS_NYQ     = 7      ✓
CONFIG.RX_COMMA_PRESET  = K28.5  ✓
STALE_TARGETS = (empty)          ✓
IS_LOCKED     = 0                ✓
```

Это authoritative — параметры из live Vivado проекта, из active build
chain. Эти значения попадают в bitstream напрямую.

---

## 3. Lesson: XCI extraction vs TCL authority

В ходе сессии возникла критическая путаница: GT Wizard XCI files
существуют в **нескольких местах**, не все из них actual.

### 3.1 Структура

```
C:\_vivado\ip\murosync_serdes_array\
  prj\gtwizard_ultrascale_0_ex.srcs\sources_1\ip\
    gtwizard_ultrascale_0\
      gtwizard_ultrascale_0.xci        ← IP REPO source (master copy)

C:\_vivado\murosync_poc_v1\
  murosync_poc_v1.srcs\sources_1\ip\
    gtwizard_ultrascale_0\
      gtwizard_ultrascale_0.xci        ← STALE copy (НЕ используется)

  murosync_poc_v1.gen\sources_1\bd\bd_murosync_poc\
    ip\bd_murosync_poc_murosync_serdes_array_0_1\
      prj\gtwizard_ultrascale_0_ex.srcs\sources_1\
        ip\gtwizard_ultrascale_0\
          gtwizard_ultrascale_0.xci    ← REGENERATED (build chain ВЕРСИЯ)
```

Vivado при сборке использует **`.gen/`** дерево (regenerated copy
from packaged IP source), не **`.srcs/`** (stale copy которая остаётся
с момента первой инстанциации).

### 3.2 Урок

**Source of truth для GT Wizard parameters:** Vivado TCL команда
`get_property CONFIG.* [get_ips -all <name>]` на live проекте.

Любая file-based extraction (grep по XCI) может смотреть на устаревший
XCI и давать неверные results. В этой сессии это привело к 30 минутам
анализа "почему параметры не применились" пока не достали authoritative
state через TCL.

### 3.3 Предлагаемый Lesson для master reference

Добавить в `MuroSync_Dev_Bench_Architecture.md` §8 Lessons как Lesson #20:

> **Vivado regenerates IP into `.gen/` from packaged IP source.** When
> the IP is provided by a user-packaged repo (like `murosync_serdes_array`),
> changes to the IP's GT Wizard settings in the repo propagate via
> regeneration into `<project>.gen/sources_1/bd/...`. The XCI files in
> `<project>.srcs/sources_1/ip/` are **not the source of truth** for
> what synthesis sees — they may be stale copies. Authoritative state
> via `get_property CONFIG.* [get_ips -all <name>]` in Vivado TCL.

---

## 4. Hypothesis status сводка

| # | Hypothesis | Status |
|---|---|---|
| A | Force LPM → DFE switch | **REJECTED** (LPM правильный для нашего сетапа) |
| B | Cascade clocking on SLAVE (TX clk != RX clk без proper buffer) | **OPEN** (не дискриминирована) |
| C | PPM offset misconfiguration (CDR tracking failure) | **CONFIRMED** (2/7 → 7/7) |
| D | 6.25 Gbps на 10G optics suboptimal | **REJECTED** (FS modules spec 2.5-10.3 Gbps) |

Hypothesis C объясняет ~80% наблюдаемой симптоматики. Остающиеся ошибки
требуют либо verification B (PMA NEAR-END test), либо secondary tuning
buffer/comma parameters.

---

## 5. Open secondary settings (для второго rebuild если нужен)

После PPM/AVTT остаются три параметра которые могут быть tuned:

### 5.1 `RX_BUFFER_RESET_ON_COMMAALIGN`

Сейчас `DISABLE` (Wizard default). На churn'ном линке (15k+ realigns
за 7 trials) старые байты в elastic buffer смешиваются с новыми после
realign event → byte-phase glitches что выглядят как data errors даже
когда wire-level 8B/10B был correct.

**Trial change:** `DISABLE → ENABLE`. Эффект: при каждом RXBYTEISALIGNED
toggle буфер drainается, downstream видит fresh aligned bytes.

### 5.2 `RX_COMMA_VALID_ONLY`

Сейчас `0` (match disparity-invalid commas too). На noisy line distorted
data bytes могут look like K28.5 pattern → false realign events.

**Trial change:** `0 → 1`. Эффект: только disparity-valid K28.5 матчи
триггерят realign — блокирует false alarms на noise.

### 5.3 `INS_LOSS_NYQ`

Сейчас `7 dB`. На LPM этот параметр **не действует** (Eli's empirical
finding). Поэтому **трогать не надо**. Включаю в этот список только
ради completeness — если кто-то захочет experiment, ничего не изменится.

---

## 6. Recommended action plan

### Step 0: PMA NEAR-END diagnostic test ← **NEXT**

**Firmware-only patch** в `bringup_master`:
```c
- murosync_serdes_bring_up(MUROSYNC_SERDES_LOOPBACK_NONE, 5000000)
+ murosync_serdes_bring_up(MUROSYNC_SERDES_LOOPBACK_FAR, 5000000)
  /* PMA NEAR-END: MASTER TX → own PMA → own RX, no SLAVE/optics */
```

Rebuild firmware (~2 минуты), reflash MASTER, прогнать тот же 7-pattern
sweep.

**Interpretation:**

| PMA NEAR-END result | Diagnosis | Next action |
|---|---|---|
| All clean (err=0, BER < 10⁻⁹) | External loop is the bottleneck | Investigate cascade or accept current state |
| Same ~10⁻⁴ errors as external | Local MASTER issue | Apply secondary tuning §5.1, §5.2 |
| Different pattern errors | Something subtle | Deeper investigation |

Cost: 5-10 минут, никакого Vivado rebuild.

### Step 1 (if external loop is bottleneck): Long-form BER test

60-секундный test на чистом паттерне (AAAA), single channel:
- ~1.88×10¹⁰ words за 60 секунд
- errors < 1000 → BER < 5×10⁻⁸ → close to Phase 1 PASS criterion
- errors ~10⁵ → BER ~10⁻⁵ → не PASS, смиряемся со status quo или копаем cascade

### Step 2 (if local issue): Apply secondary GT tuning

Открыть GT Wizard, изменить:
- `RX_BUFFER_RESET_ON_COMMAALIGN: DISABLE → ENABLE`
- `RX_COMMA_VALID_ONLY: 0 → 1`

Regenerate, rebuild MASTER + SLAVE bitstreams, retest.

### Step 3: Document final state

Если Phase 1 PASS — обновить:
- `MuroSync_Dev_Bench_Architecture.md` → v1.3 с appendix B (debug story)
- `MuroSync_IP_Internals.md` — финальные GT параметры
- New file: `docs/gt_parameters_snapshot.md` (через TCL extraction)
- Commit с тегом `phase1-closed`

---

## 7. Что НЕ делать

1. **Не переключать LPM → DFE.** Confirmed wrong direction для нашего сетапа.

2. **Не менять `INS_LOSS_NYQ`.** На LPM значение в диапазоне 0-14 dB
   не влияет.

3. **Не поднимать line rate до 10.3 Gbps.** Требует пересмотр всего
   timing budget MuroSync (refclk 156.25 не делит на 10.3125). Не main
   issue.

4. **Не лезть в `RXDFE_GC_CFG*` и недокументированные регистры.** Требует
   Xilinx FAE; не путь для bench debug.

5. **Не делать piecemeal rebuilds.** Если решили менять параметры —
   менять все нужные за **один** rebuild. Каждый rebuild = 40-60 минут
   × 2 (MASTER + SLAVE).

6. **Не trust XCI files в `.srcs/`.** Source of truth = TCL
   `get_property` на live project. See §3.

---

## 8. Reference material

### Primary documents

- **UG576** (UltraScale Architecture GTH Transceivers User Guide):
  https://docs.xilinx.com/v/u/en-US/ug576-ultrascale-gth-transceivers
  Глава 4 — Receiver Equalization (DFE and LPM)

- **PG182** (UltraScale FPGAs Transceivers Wizard v1.7):
  https://docs.xilinx.com/v/u/en-US/pg182-gtwizard-ultrascale
  Wizard configuration reference

- **Xilinx AR# 61695, 56894** — 8B/10B + DFE stability limitation

### Empirical / working examples

- **Eli Billauer — UltraScale GTH equalizer empirical study:**
  https://billauer.co.il/blog/2020/09/xilinx-gth-gtx-gtp-eye-scan/
  Eye scans LPM vs DFE на UltraScale GTH, USB 3.0 5 Gbps

- **Xillybus — Optical fiber link with Ultrascale GTH + Xillyp2p:**
  https://www.xillybus.com/xillyp2p/optical-fiber-ultrascale-gth
  Working SFP+ optical fiber example, KCU105, 5 Gbps, two boards.
  Reference Wizard parameters (PPM=200, Termination=AVTT)

- **ADI EngineerZone — DAQ2.KCU105 DFE→LPM fix:**
  https://ez.analog.com/fpga/f/q-a/51713
  Empirical confirmation LPM > DFE on UltraScale (JESD204B context)

### ADI HDL reference designs (для будущей работы)

- **github.com/analogdevicesinc/hdl** — full HDL stack for ADI converters.
  Projects on KCU105 (`projects/daq2/kcu105`, `projects/fmcomms*`) demonstrate
  GT Wizard configuration patterns for high-speed SerDes (mostly JESD204B
  context, but useful for cross-reference)

- **github.com/analogdevicesinc/no-OS** — software stack for ADI eval boards.
  Contains the actual code path that led to the LPM-over-DFE EngineerZone
  conclusion

### Forums / discussion

- Xilinx Community Forums — LPM vs DFE recommendation
- edaboard — SFP+ DFE→LPM thread (links to AR# 61695, 56894)

---

## 9. Document history

| Version | Date | Notes |
|---|---|---|
| 1.0 | 2026-05-28 | Initial research deliverable — Step 2 of session |
| 2.0 | 2026-05-29 | Updated post-application: PPM/AVTT confirmed working empirically (7/7 patterns lock), added §3 TCL authority lesson, refined hypothesis status, updated action plan to reflect PMA NEAR-END as next discriminator |
| 3.0 | 2026-06-13 | Added §10: June results (cascade-clocking hypothesis closed, PMA NEAR-END done, residual 0x12341234 characterised) and the gating killed-hypothesis (freeze RXPCOMMAALIGNEN → H2, phase-tracking dies on buffer-bypass + plesiochronous). Top banner added pointing readers to §10; §1–§9 retained as 29-May research history, several conclusions/action-items therein superseded. |

---

## 10. June 2026 update — what was learned after 29 May (current state)

*This section supersedes the conclusions and action plan in §4–§7 where they
conflict. §1–§3 (LPM-over-DFE, PPM/AVTT, TCL authority lesson) remain valid.*

### 10.1 Status correction vs §1/§2

"7/7 patterns lock" (§2.5) was true but incomplete. With full per-pattern WER
measurement:

| Pattern class | lock | realign | WER | note |
|---|---|---|---|---|
| Symmetric (AAAA, 0000, FFFF, 5555, 1212) | OK | ~0 | ~10⁻⁶ (eye floor) | clean |
| **0x12341234** | OK | **~1568 / 2 s** | **1.3×10⁻³** | residual — see 10.4 |
| 0x12345678 | OK | ~16 | ~2×10⁻⁵ | minor |

So the physical link is genuinely working on symmetric traffic at the eye floor,
but **0x12341234 carries a 3-orders-above-floor residual driven by realign**, not
by raw BER. This is the real Phase-1 residual, and §10.4 explains why it does not
belong to the physical layer.

### 10.2 Hypothesis status — updated

| # | Hypothesis | 29-May status | **Current status** |
|---|---|---|---|
| A | Force LPM → DFE | REJECTED | REJECTED (unchanged) |
| B | Cascade clocking on SLAVE (TX clk ≠ RX clk) | OPEN | **CLOSED — DISPROVEN.** SLAVE echo runs in a single recovered-clock domain (rxoutclk sourcing fix); not a clock-crossing issue. |
| C | PPM offset misconfiguration | CONFIRMED | CONFIRMED (unchanged) |
| D | 6.25 G on 10 G optics suboptimal | REJECTED | REJECTED (unchanged) |

### 10.3 PMA NEAR-END discriminator — DONE (was §6 Step 0 "NEXT")

The PMA near-end / external-cascade loopback discriminator was run. Result:
MASTER receiver is clean (<10⁻⁹ near-end); the residual originates **externally**,
in the SLAVE re-encode cascade — roughly 70% fabric-echo / 30% PCS-tract by the
loopback-matrix decomposition. This localised mechanism A to the SLAVE echo path,
not the MASTER RX.

### 10.4 Root cause of the 0x12341234 residual — data-intrinsic false-commas

The realign on 0x12341234 is **not noise** and **not a tunable-away artifact**. The
aggressive aligner config required for plesiochronous buffer-bypass acquisition —
`RX_COMMA_ALIGN_WORD=1` + `RX_COMMA_DOUBLE_ENABLE=false` + `RX_COMMA_VALID_ONLY=0`
— makes the comma detector match any 10-bit pattern that looks like K28.5 at a
bit-boundary. Correctly 8B/10B-encoded 0x12/0x34 bytes **produce comma-matching
bit windows at 10-bit boundaries**. The detector looks at raw bits, ignores the
K-flag, and slides. → false-commas are **data-intrinsic**, a property of the byte
sequence, not a signal-integrity problem.

**This invalidates the §5 secondary-tuning plan:**
- §5.2 `RX_COMMA_VALID_ONLY: 0→1` would block *noise* false-commas but not
  *data-intrinsic* ones (the bytes are validly encoded). Not a fix.
- §5.1 `RX_BUFFER_RESET_ON_COMMAALIGN: DISABLE→ENABLE` addresses buffer staleness
  after realign, not the realign cause. Not a fix.
- Weakening the aligner (WORD=2 / DOUBLE=true) was tested separately and
  **regresses bring-up** — the aggressive config is required for acquisition on
  buffer-bypass + plesiochronous. Not available.

### 10.5 KILLED HYPOTHESIS — comma-align gating (freeze RXPCOMMAALIGNEN)

*Status: KILLED — proven incompatible with the GT config. June 2026.*

**Idea.** Suppress the realign by latching RXMCOMMAALIGNEN/RXPCOMMAALIGNEN low once
CH0 has aligned ("align then freeze"), so the byte aligner stops re-sliding on the
data-intrinsic false-commas.

**Implementation.** Per-channel freerun-domain sticky latch: `rxbyteisaligned` →
2FF CDC → debounce 256 cycles → sticky → `~sticky` drives the aligner-enable
(default-high so bring-up is unaffected). Arming progressively gated to reject
false latches: + `gtwiz_reset_rx_done` (link-ready), + `commadet_seen` (a real
10-bit K28.5 was detected on the channel, not a 7-bit noise window).

**Result — KILLED by H2.** The arming gates fixed their target symptoms (dark
channels and pre-lock transients stopped false-latching — provable: dark channels
never assert a real RXCOMMADET, so they never armed). But the link still failed:
CH0 froze on a wrong boundary, WER → 0.5 (pure garbage). Diagnostic readback
(`rxphaligndone` exposed to `SERDES_DBG_HI`, polled via a `[DBGCAP]` burst) gave
the decisive evidence: **once the sticky latches and RXPCOMMAALIGNEN goes low,
`rxphaligndone[0]` drops to 0 and never recovers — 100/100 samples over 1 s show
`stk=1, ph=0`.**

**Root cause of H2.** On `RX_BUFFER_MODE=1` (bypass) + `BYPASS_MODE=MULTI` +
controller in CORE, combined with the plesiochronous link (`RX_PPM_OFFSET=200`),
comma-alignment carries **continuous phase tracking**, not a one-shot acquisition.
The in-wizard buffer-bypass controller uses RXMCOMMAALIGNEN/RXPCOMMAALIGNEN to
maintain phase alignment against the 200 ppm refclk offset. Freezing the
aligner-enable kills that tracking → `rxphaligndone` collapses → byte boundary
decorrelates. **Freezing comma-alignment is fundamentally incompatible with this
config — independent of *when* the latch arms.** A longer debounce (the obvious
"option A") would NOT help: H2 is about the freeze *action*, not the arming time.

**Control proof.** Neutralising the gate (`rx_comma_align_en_int = 4'b1111`)
returned the link to the v1.10 baseline exactly: CH0 aligns, realign ~1568 on
0x12341234, symmetric patterns ~10⁻⁶. The link base is healthy; gating alone was
the breakage. (This is the working state captured at IP v1.13.)

**Verify-discipline note.** Early "v1.13" runs were misleading: the gating RTL was
emitted as a diff but not written to the synthesized source, so logs labeled v1.13
were actually the v1.10 baseline. Lesson reinforced: verify the change in the
**synthesized netlist / live object** (primitive RXPCOMMAALIGNEN driver), not in a
loose source file or an IP version label. (Same `.gen`-vs-`.srcs` /
working-vs-mirror divergence as §3.)

### 10.6 Consequence — realign belongs to the frame layer (Phase 2)

The chain 10.4 + 10.5 establishes, by measurement rather than assumption:

> Data-intrinsic realign is an **inherent property of the physical layer** on this
> config. It cannot be removed at the physical layer (gating kills phase-tracking;
> weakening the aligner kills acquisition; the offending commas are validly
> encoded). It must be **tolerated**, with word-alignment recovered at the **frame
> layer (Phase 2)** — K-symbols only between frames, single-lane comma in TX
> training, and frame structure to re-establish the word boundary after a realign.

Gating attempted to solve a frame-layer problem with physical-layer means. The
correct Phase-1 exit is: accept the working physical link (v1.13), record gating as
this killed hypothesis, and move word-alignment recovery to Phase 2.

### 10.7 Open question for Phase 2 (before building realign-tolerance)

0x12341234 is a **synthetic worst-case** test pattern, chosen to maximise
data-intrinsic false-commas. Real framed Phase-2 traffic (K-delimited, structured
or scrambled payload) may not produce such byte sequences at all. **Verify whether
mechanism A manifests under realistic framing before building realign-tolerance
machinery** — it is possible the frame layer avoids the problem for free rather
than having to tolerate it, in which case no realign-recovery mechanism is needed.

### 10.8 Retained artifacts

The diagnostic readback (`rxphaligndone` / `rx_aligned_sticky` / `commadet_seen` →
`SERDES_DBG_HI`) and the firmware `[DBGCAP]` fast-capture pattern are reusable for
Phase-2 phase-alignment debugging — re-add when needed. The gating RTL itself is
**not** carried into the repo (killed; it lives only as this note). The committed
IP at v1.13 is the clean working baseline equivalent to v1.10 plus the version bump.

---

*This is a research / planning document, not a normative reference. §1–§9 are the
29-May research history; §10 (13-Jun) is the current state. Authoritative GT
parameter state lives in `gt_parameters_snapshot_v1.13.md` (TCL-extracted) and in
the live Vivado project itself.*
