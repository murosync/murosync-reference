# MuroSync — Full IP Audit для Phase 1 (оптика)

**Дата:** 2026-05-31
**Метод:** Read-only review всех .sv в `murosync_serdes_array/src/`,
generated GT wrapper, кросс-проверка с эмпирическими тестами
(loop=0/1/2/4, MASTER v1.3, SLAVE v1.3).
**Цель:** определить, что мешает оптическому линку давать BER ≪ 1e-4
и составить конкретный план "как оживить оптику".

---

## TL;DR — главное

Cascade RTL в SLAVE-режиме на самом деле **не работает в production**.
Найдено **два независимых бага** в data path:

### Bug #1 (КРИТИЧЕСКИЙ, найден сегодня) — мьютекс в top wire

`murosync_serdes_array.sv:578`:

```systemverilog
.gtwiz_userdata_tx_in (link_test_ctrl_en_core ? link_test_tx_data : 64'h0),
```

В SLAVE-firmware `link_test` **никогда не enableится** (см. `main.c:bringup_slave`).
Значит `link_test_ctrl_en_core = 0` всегда. Значит SLAVE TX user-data
**жёстко прибит к 64'h0**. То есть **cascade `tx_data <= rx_data_r`
внутри link_test выполняется, но его выход отбрасывается этим
мьютексом на самом верху** до GT TX serializer.

**SLAVE отправляет в волокно постоянный D0.0** (плюс случайные K-symbol
echoes через `txctrl2_in`, который НЕ загейчен). Никаких реальных
данных от MASTER не возвращается.

Все наблюдаемые "локи с ошибками BER ~1e-4" на external loop — это
шум от SLAVE-side artifacts (echo K-symbols + invalid 8B/10B
combinations data=0+K=1 от GT encoder), а **не реальный cascade**.

### Bug #2 (известный, подтверждён вчерашним анализом) — single-flop CDC в cascade

`murosync_serdes_link_test.sv:284` и `:299`:
- `rx_data_r <= rx_data` на `posedge tx_clk` — 64-битная асинхронная шина через 1 флоп
- `txctrl2_out <= {rxcharisk...}` на `posedge tx_clk` — то же на 4 бит

Когда Bug #1 будет исправлен, Bug #2 станет видимой проблемой: lock
будет, но метастабильность даст битфлипы из-за того что `tx_clk` и
`rx_clk` на SLAVE имеют независимые источники.

### Чтобы оживить оптику нужно решить **оба** в правильном порядке

1. Сначала Bug #1 (firmware-only fix или одна строка RTL) — без этого
   нет смысла тестировать дальше, потому что cascade не выполняется
2. Затем Bug #2 (RTL — изменить источник tx_clk на SLAVE)
3. Тогда optical link должен дать clean BER

---

## Часть 1: Анализ всех RTL-файлов

### `murosync_serdes_array.sv` (top-level)

**Что делает:** инстанцирует GT wrapper, AXI-ctrl, link_test, разбирается
с MASTER/SLAVE port muxing, генерирует dbg-bus.

**Найденные проблемы:**

| Локация | Severity | Описание |
|---|---|---|
| **Line 578** | 🔴 КРИТИЧНО | TX user data мьютекс `link_test_ctrl_en_core ? link_test_tx_data : 64'h0` — отрубает cascade на SLAVE |
| Line 591–596 | ✅ OK | txctrl2_in wiring — корректные битовые позиции для per-channel K-symbol |
| Line 520–525 | ✅ OK | rxcharisk_int extraction из rxctrl0_int — корректно по комментариям и uG576 |
| Line 628 | ✅ OK | loopback_in fanout — корректный fan-out 3'b на 4 канала |
| Line 569–570 | ⚠️ КОММЕНТАРИЙ | Rollback-safe вариант закомментирован — текущая версия принимает AXI reset pulse, OK |
| Line 173–175 | ✅ OK | refclk через IBUFDS_GTE4 + BUFG_GT — стандарт |

**Конкретные строки которые касаются проблемы #1:**

```
570:        .gtwiz_reset_all_in (hb_gtwiz_reset_all_int | gt_reset_all_pulse_axi),
...
578:        .gtwiz_userdata_tx_in (link_test_ctrl_en_core ? link_test_tx_data : 64'h0),
579:        .gtwiz_userdata_rx_out(gtwiz_userdata_rx_int),
...
591:        .txctrl2_in ({                                          // НЕ загейчен!
592:            6'h0, link_test_txctrl2[7:6],   // CH3
593:            6'h0, link_test_txctrl2[5:4],   // CH2
594:            6'h0, link_test_txctrl2[3:2],   // CH1
595:            6'h0, link_test_txctrl2[1:0]    // CH0
596:        }),
```

Асимметрия: data загейчена, K-symbol control — нет. Это и создаёт
странную физическую картину: SLAVE отправляет (data=0, K=echoed_value).
Когда K=1 на каком-то байте, GT 8B/10B encoder вынужден обрабатывать
комбинацию data=0x00 + K=1 = "K0.0", которая **невалидна** в 8B/10B.
Реальное поведение GT в этом случае depends on UG576 — скорее всего
подставляется default K28.5 или генерится runt.

### `murosync_serdes_link_test.sv` (TX gen + RX checker)

**Что делает:** генерация тест-паттернов, RX checker FSM с Tier 1/2
снапшотами, cascade-логика для SLAVE.

**Найденные проблемы:**

| Локация | Severity | Описание |
|---|---|---|
| **Line 280–285** | 🔴 КРИТИЧНО | `rx_data_r <= rx_data` — 64-бит async CDC через 1 флоп |
| **Line 296–305** | 🔴 КРИТИЧНО | `txctrl2_out` echo из `rxcharisk` — тот же single-flop CDC на 4 бит |
| Line 307–329 | ✅ OK | `tx_data` always block — внутри одного домена (tx_clk) |
| Line 220, 225, 233 | ✅ OK | TX comma FSM gating `!IS_SLAVE` — корректно, SLAVE не генерит K-burst сам |
| Line 665 | ✅ OK | RX checker FSM gating `!IS_SLAVE` — корректно, SLAVE checker отключён |
| Line 391, 374 | ✅ OK | `is_match_by_channel` — простая equality check, корректна |
| Line 416–423 | ✅ OK | `rx_aligned_seen` sticky latch — для tolerance к transient byteisaligned drops |
| Line 692–730 | ✅ OK | LOCKED state error counter logic — корректно, никогда не выходит из LOCKED на error |
| Line 549–568 | ✅ OK | Tier 2 snapshot capture — корректно (1-shot latch) |

### `murosync_serdes_array_axi_ctrl.sv` (AXI register file + CDC)

**Что делает:** AXI4-Lite slave с register file (49 регистров), CDC для
всех status/control сигналов, IP_INFO register.

**Найденные проблемы:**

| Локация | Severity | Описание |
|---|---|---|
| Line 460–476 | ✅ OK | `link_test_ctrl_en_core` 2FF sync — стандартный level CDC |
| Line 478–487 | ✅ OK | `link_test_cnfg` 2FF sync (16 бит) — bits not coherent, но cnfg меняется редко, OK |
| Line 443–450 | ✅ OK | `link_test_ctrl_rst_axi_pulse` через `slow_to_fast` — корректный W1P CDC |
| Line 517–550 | ✅ OK | Diagnostic CDC через `level_sync` — debug-only, OK |
| Line 555–562 | ⚠️ ДОКУМЕНТИРОВАНО | 64-бит rx_data/exp_data sample на axi_clk через 1 регистр — non-coherent, но это debug only (комментарий явно говорит) |
| Line 700–747 | ✅ OK | Tier 2 CDC через `level_sync` (включая 64-битные frozen snapshots) — корректно для frozen значений |

Все CDC в этом файле корректные. **link_test cascade — это единственное
место в IP с broken CDC.**

### `murosync_gt_wrapper.sv` (GT wrapper + user clocking)

**Что делает:** инстанцирует gtwizard_ports + 2 user clock generators
(один для TX, один для RX), Tier 2 sticky counters.

**Найденные проблемы:**

| Локация | Severity | Описание |
|---|---|---|
| Line 155–164 | 🔴 АРХИТЕКТУРНОЕ | TX user clock generator берёт `txoutclk_int[0]` — производный от **local** QPLL → local refclk. В SLAVE это создаёт второй clock domain, отличный от RX recovered |
| Line 166–175 | ✅ OK (по дизайну) | RX user clock generator берёт `rxoutclk_int[0]` — CDR recovered clock от incoming serial |
| Line 178–181 | ✅ OK | TX/RX clocks fanned out replicate to all 4 channels — стандарт |
| Line 188 | ⚠️ ИНТЕРЕСНО | `slave_recclk_out = gtwiz_userclk_rx_usrclk2` — recovered clock уже экспортирован наружу. **Тот же net мог бы быть и SLAVE's TX user clock — это часть архитектурного fix для Bug #2** |
| Line 289–320 | ✅ OK | Tier 2 sticky counters в rx_clk domain — корректные always-blocks |

### `murosync_gtwizard_ports.sv` (port isolation layer)

**Что делает:** port-level wrapper вокруг generated GT IP, форвардит
сигналы 1:1.

**Найденные проблемы:**

| Локация | Severity | Описание |
|---|---|---|
| Line 110 (комментарий) | ⚠️ УСТАРЕВШИЙ КОММЕНТАРИЙ | "your current gtwizard_ultrascale_0 top does NOT have loopback_in port enabled" — comment lies, port реально включён (проверено grep на сгенерированном wrapper line 486) |
| Line 177–180 | ✅ OK | `rxcommadeten_in/rxmcommaalignen_in/rxpcommaalignen_in` все привязаны к 1 — comma detection включён, это **разрешает empirical странность** что RXBYTEISALIGNED работает несмотря на XCI flag |
| Line 138–140 | ✅ OK | `pll_lock_vec_out = cplllock | qpll0lock | qpll1lock` — OR трёх lock-индикаторов, корректно для нашей QPLL0-конфигурации |
| Line 215 | ✅ OK | `loopback_in` передаётся вниз — корректно (несмотря на комментарий) |

### `murosync_gt_userclk_tx.sv` / `_rx.sv` (BUFG_GT helpers)

**Что делает:** тонкая обёртка вокруг BUFG_GT с integer divide.

Корректные модули. `active_meta`/`active_sync` 2FF synchronizer для
"clock alive" flag — стандарт.

### `murosync_cdc_level_sync.sv`

Стандартный per-bit ASYNC_REG 2FF sync. Корректный. Используется
в axi_ctrl везде. **НЕ используется** в link_test cascade.

### `murosync_cdc_slow_to_fast.sv`

Стандартный sync+edge_detect для W1P pulse generation.
SYNC_STAGES default 3, можно понизить до 2. Используется только
для CTRL pulses. Корректный.

---

## Часть 2: Анализ test results через призму найденных багов

Все 4 loop-теста повторно интерпретируются:

### Test PMA NEAR-END (loop=2): chistый результат

**Путь:** MASTER `link_test_tx_data` → mux (en=1 → pass) → GT TX serializer
→ internal PMA loopback → GT RX deserializer → `gtwiz_userdata_rx_out` →
MASTER `link_test rx_data`.

- Cascade RTL **не задействован**
- Bug #1 **не задействован** (en=1 на MASTER во время теста, mux pass-through)
- Bug #2 **не задействован** (нет cross-board clock)
- Результат: 0 errors на симметричных trials. **MASTER local hardware
  и RTL — чисты.**

### Test PCS NEAR-END (loop=1): tiny single-bit errors

**Путь:** MASTER `link_test_tx_data` → mux pass → GT TX 8B/10B encoder
→ digital PCS loopback → GT RX 8B/10B decoder → back to user data.

- Errors ~400/trial, XOR всегда low popcount (1-2 бит), часто bit 25
  или bit 16 в CH1 slice
- Это **скорее всего внутренний quirk GT PCS** или артефакт
  rx_clk/tx_clk хоть и одного источника (local QPLL), но через две
  разные BUFG_GT цепочки
- BER ~5e-6, не main issue

### Test External loopback (loop=0): "BER 1e-4" — НЕ то что мы думали

**Текущая интерпретация (после Bug #1):**

- MASTER TX = реальный pattern + K28.5 burst
- Wire → SLAVE RX
- SLAVE link_test cascade `tx_data <= rx_data_r` РАБОТАЕТ внутри link_test
- НО line 578 mux GATES SLAVE's tx_data → SLAVE TX wire = **constant 0x00**
- SLAVE's `txctrl2` echo `rxcharisk` is NOT gated → K-flag echoes через
- Когда MASTER K28.5 приходит на SLAVE, SLAVE TX отправляет
  (data=0x00, K=1) → "K0.0" — invalid 8B/10B → GT может либо
  substitute default (K28.5 = 0xBC), либо генерить runt
- MASTER RX получает: mostly 0x00 + occasional 0xBC/garbage
- MASTER checker для pattern 0xAA: 0xAA НИКОГДА не match-ится с 0x00,
  но FSM может locknут-ся на одну случайно совпавшую байт-комбинацию
  во время K-burst noise → immediate errors

Это объясняет **все** странности теста loop=0:
- "Lock" происходит на random match
- "at_lock != expected" — конечно, данные мусор
- Big per-CH errors — ровно потому что данных от MASTER не возвращается
- byte_realign постоянно растёт — из-за invalid 8B/10B periodic events

### Test PMA FAR-END (loop=4): "BER 1e-4" — это вообще другой experiment

**Что на самом деле делает loop=4:**

Per UG576 GTH loopback 4 = "Far-end PCS Loopback" — на own GT primitive.
MASTER's incoming RX отражается обратно из своего же PCS в свой же TX,
**user data input игнорируется**.

- MASTER TX serializer берёт данные из MASTER RX PCS (НЕ из user
  data input → MASTER's pattern generator output **не на wire**)
- Wire получает только то что MASTER когда-то получил
- Замкнутая петля: MASTER reflects ← what's on wire ← SLAVE TX ← SLAVE
  cascade ← MASTER reflects ← ...
- SLAVE TX = constant 0 (Bug #1) + K-echo
- Закрытая петля заполняется этим мусором, он циркулирует
- MASTER checker иногда случайно лочится на этот мусор

**Этот тест по сути не проверяет ничего полезного.** Не диscriminator.

### Что мы НЕ знаем из-за Bug #1

- Какой реально BER на physical layer (fiber + SFPs + MASTER PMA TX/RX)
- Работает ли SLAVE cascade при ИСПРАВЛЕННОЙ Bug #1
- Виноваты ли оптика/cable/SFPs
- Виноваты ли PPM/CDR/clock-domain issues

**Все эти вопросы остаются открытыми пока Bug #1 не исправлен.**

---

## Часть 3: План "как оживить оптику" — пошагово

### Шаг 1: Исправить Bug #1 (отгейтить cascade на SLAVE)

**Вариант A — RTL fix (рекомендуется, чисто).** Изменить
`murosync_serdes_array.sv:578`:

```systemverilog
// Было:
.gtwiz_userdata_tx_in (link_test_ctrl_en_core ? link_test_tx_data : 64'h0),

// Стало:
.gtwiz_userdata_tx_in (IS_SLAVE ? link_test_tx_data :
                       (link_test_ctrl_en_core ? link_test_tx_data : 64'h0)),
```

Один символ изменения семантики: в SLAVE-режиме всегда пропускать
cascade output напрямую (без проверки test_en). В MASTER оставить
текущее поведение (защита от мусорного TX до старта теста).

**Cost:** один edit в RTL, требует re-package IP (auto MINOR bump v1.4),
rebuild ОБОИХ bitstreams, прошить обе платы.

**Вариант B — firmware fix (быстрее, но менее чисто).** Изменить
`murosync_app_bringup_slave()` чтобы он включал link_test_ctrl_en:

```c
// После bring_up:
murosync_serdes_link_test_set_ch_mask(0xF);   // any non-zero mask
murosync_serdes_link_test_start();              // enables link_test_ctrl_en
```

В SLAVE-режиме link_test FSM сам по себе **gated off** by `IS_SLAVE`
(line 665 link_test.sv → RX checker stays IDLE; line 220/225/233 →
TX comma FSM stays IDLE). Так что enable не запустит pattern generator
или checker — оно просто пропустит mux в cascade direction.

**Cost:** одна строка firmware, rebuild firmware (~2 мин), прошить
только SLAVE. Не нужен Vivado rebuild.

**Я рекомендую Вариант B первым** — за 2 минуты получим эмпирическое
подтверждение что cascade сам по себе работает (или нет). Если работает
— делать Вариант A для чистоты. Если не работает — диагностируем Bug #2.

### Шаг 2: Повторить external loop test после Шага 1

Запустить тот же 7-pattern sweep с MASTER в LOOPBACK=0. Что ожидать:

**Если Bug #2 (CDC) — единственная оставшаяся проблема:**
- FSM лочится быстро на все паттерны (cascade теперь работает)
- BER заметно лучше чем 1e-4 (возможно 1e-5 — 1e-6)
- byte_realign delta upper-bounded но не нулевой

**Если Bug #2 — основная проблема:**
- Clean lock на all patterns
- но errors всё ещё ~1e-4 (метастабильность от async clocks)
- `at_1st_err XOR` показывает small popcount (бит-флипы а не байт-сдвиги)

**Если есть третья проблема (optical / SFPs):**
- Lock работает, но errors > expected, byte_realign очень высокий
- `eyescan_errors > 0` (сейчас всегда 0)

### Шаг 3 (если нужен): Исправить Bug #2 — clock SLAVE TX from RXUSRCLK2

Самый чистый архитектурный фикс. В `murosync_gt_wrapper.sv` line 159
изменить SLAVE-specific:

```systemverilog
// Было:
.gtwiz_userclk_tx_srcclk_in (txoutclk_int[TX_MASTER_CH]),

// Стало (концептуально):
.gtwiz_userclk_tx_srcclk_in (IS_SLAVE_PARAM ? rxoutclk_int[RX_MASTER_CH]
                                            : txoutclk_int[TX_MASTER_CH]),
```

При IS_SLAVE: TX user clock = RX user clock (один и тот же net). Тогда
`tx_clk == rx_clk` физически в link_test. Cascade становится same-clock
register, никакого CDC. Безопасно по построению.

**Внимание:** требуется передать `IS_SLAVE` параметр в gt_wrapper
(сейчас это компиле-time константа в parent serdes_array, но не
параметр gt_wrapper). Нужно добавить parameter в gt_wrapper.sv и
propagate down.

Также: TXOUTCLKSEL в GT Wizard config возможно нужно поменять с
`010 (TXOUTCLKPMA)` на `101 (TXUSRCLK)` или `RXRECCLK` для SLAVE-build,
чтобы TX PMA serializer корректно clock-овался от recovered RX clock.

**Cost:** RTL edit + GT Wizard parameter change для SLAVE bitstream
(или для обоих — нужно подумать). Re-package IP. Rebuild оба bitstream.

### Шаг 4 (диагностика, если Шаги 1-3 не дают clean BER): physical layer

Если после правильного cascade всё ещё есть остаточный BER:
- Перетестировать на FMC loop board (без оптики) — должно быть clean
- Если FMC clean, optical dirty → physical layer (fiber, SFPs, dirt)
- Чистка LC connectors fiber, swap SFP+ модули

---

## Часть 4: Другие мелкие находки (не блокеры)

1. **`murosync_serdes_array_mode.sv`** — leftover файл, не используется
   нигде. Удалить (Cleanup #2 в Dev_Bench_Architecture).
2. **`murosync_gtwizard_ports.sv:110`** — комментарий устарел, loopback
   на самом деле работает.
3. **`RX_BUFFER_RESET_ON_COMMAALIGN = DISABLE`** в XCI — Wizard default,
   возможно стоит включить если byte_realign churn останется проблемой
   после Шагов 1-3.
4. **Inconsistent register naming `LOOPBACK_FAR = 0x2` vs реально
   PMA NEAR-END** — переименовать enum в driver.h для ясности
   (Cleanup, не блокер).

---

## Часть 5: Open questions / unclear

1. **Точное поведение GT 8B/10B encoder при (data=0x00, K=1)** —
   неизвестно из RTL анализа, требует UG576 deep dive или симуляции.
   Не критично для diagnosis — известно эмпирически что что-то
   некорректное выходит на wire.

2. **Почему PCS NEAR-END даёт systematic single-bit error на bit 25
   CH1 slice** — возможно артефакт internal GT clock crossing
   tx_clk → rx_clk даже в loopback. Очень маленький BER, не блокер,
   отложить.

3. **Что делать с TX_DIFF_SWING = 24 (0x18)** — middle-range
   value. Может потребоваться калибровка для конкретного SFP+
   модуля. Можно попробовать после Шагов 1-3.

4. **MASTER-side: должен ли быть отдельный mux на TX data для
   training-mode (отправка commas без user pattern)?** — Текущий
   код полагается на link_test TX comma FSM. Если link_test
   disabled, MASTER TX тоже отправляет 0. Это правильно
   для production, но может быть проблема если когда-то нужен
   "comma-only training mode" отдельно от link_test.

---

## Резюме рекомендаций по приоритету

| # | Действие | Где | Cost | Expected impact |
|---|---|---|---|---|
| 1 | Включить link_test на SLAVE bringup (Вариант B Шага 1) | firmware:bringup_slave | 1 line, 2 min build | Разблокирует cascade. Главный фикс |
| 2 | Повторить 7-pattern external loop test после #1 | firmware unchanged | прошить SLAVE, 5 min | Discriminator: cascade сам по себе OK или есть Bug #2 |
| 3 | Если errors всё ещё высокие — исправить cascade clocking (Bug #2) | RTL: gt_wrapper.sv | RTL edit + 2× bitstream rebuild ~1.5h | Clean BER |
| 4 | Очистить вариант B и сделать вариант A Шага 1 (чистое RTL fix) | RTL: serdes_array.sv:578 | 1 line edit + 2× bitstream rebuild | Production-grade |
| 5 | Physical layer test если BER всё ещё > expected | hardware | clean LC, swap SFPs | Last-resort |

**Если делать только одно действие из всего списка:** **#1** —
оно эмпирически verifiable за 5 минут и **может полностью закрыть
Phase 1**, если Bug #2 не такой страшный как кажется в теории.

---

## Структура файлов (для reference при дальнейшей работе)

```
C:\_vivado\ip\murosync_serdes_array\src\
├── murosync_serdes_array.sv         (top, line 578 — main bug)
├── murosync_serdes_array_axi_ctrl.sv (AXI regs + CDC, all OK)
├── murosync_serdes_array_S00_AXI.sv  (AXI protocol, generated)
├── murosync_serdes_link_test.sv     (lines 280–305 — CDC bug)
├── murosync_gt_wrapper.sv           (line 159 — for Bug #2 fix)
├── murosync_gtwizard_ports.sv       (forwarding wrapper)
├── murosync_gt_userclk_tx.sv        (BUFG_GT for TX)
├── murosync_gt_userclk_rx.sv        (BUFG_GT for RX)
├── murosync_cdc_level_sync.sv       (per-bit 2FF)
├── murosync_cdc_slow_to_fast.sv     (pulse generator)
└── murosync_serdes_array_mode.sv    (leftover, unused)

C:\Users\mikha\workspace_murosync\murosync_poc_fw\src\
├── main.c                            (bringup_slave — for fix #1B)
├── murosync_serdes_driver.c/.h       (link_test_set_ch_mask, _start)
└── murosync_serdes_regs.h            (register defines)
```

---

*Generated 2026-05-31. Read-only analysis, no code/IP modifications.
No git mutations.*
