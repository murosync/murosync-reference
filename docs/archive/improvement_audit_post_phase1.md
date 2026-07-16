# MuroSync — Post-Phase 1 Improvement Audit

**Дата:** 2026-05-31
**Метод:** read-only анализ всех .sv + driver.c/.h + regs.h + main.c
**Цель:** найти возможности для упрощения, дедупликации, очистки и
улучшения читаемости — **без архитектурных изменений** и без изменения
наблюдаемого поведения.
**Контекст:** IP версия v1.5, Phase 1 функционально закрыт (Bug #1, #2 и
правильный ch_mask привели к BER ~1e-6 на CH0). Архитектура работает,
теперь имеет смысл навести порядок.

---

## Объём аудита

| Файл | Строк | Покрыто |
|---|---|---|
| `murosync_serdes_array.sv` | 750 | full re-read |
| `murosync_serdes_array_axi_ctrl.sv` | 833 | full re-read |
| `murosync_serdes_link_test.sv` | 812 | full re-read |
| `murosync_gt_wrapper.sv` | 349 | full re-read |
| `murosync_gtwizard_ports.sv` | 220 | full re-read |
| `murosync_gt_userclk_tx.sv` | 111 | full re-read |
| `murosync_gt_userclk_rx.sv` | 106 | full re-read |
| `murosync_cdc_level_sync.sv` | 60 | full re-read |
| `murosync_cdc_slow_to_fast.sv` | 58 | full re-read |
| `murosync_serdes_array_S00_AXI.sv` | 279 | skipped (generated AXI shell) |
| `murosync_serdes_array_mode.sv` | 335 | DEAD FILE — см. ниже |
| `murosync_serdes_driver.c` | 1439 | full re-read |
| `murosync_serdes_driver.h` | 297 | full re-read |
| `murosync_serdes_regs.h` | 780 | full re-read |
| `main.c` | 234 | full re-read |

**Всего активного кода:** ~5870 строк (без mode.sv leftover и AXI shell).

---

## Часть 1: Driver-side (наиболее easy wins)

### 1.1 Dедупликация 64-битных LO+HI getter'ов

**Текущее состояние:** три функции идентичной формы, отличающиеся только парой регистров:

```c
// driver.c lines 611-619, 623-631, 635-643 — три почти-одинаковых блока
int murosync_serdes_link_test_get_rx_data_at_lock(unsigned long long *data)
{
    unsigned int lo, hi;
    int stat;
    stat = murosync_serdes_reg_rd(MUROSYNC_LNK_RX_DATA_AT_LOCK_LO_REG, &lo);
    if (stat != XST_SUCCESS) return stat;
    stat = murosync_serdes_reg_rd(MUROSYNC_LNK_RX_DATA_AT_LOCK_HI_REG, &hi);
    if (stat != XST_SUCCESS) return stat;
    *data = ((unsigned long long)hi << 32) | (unsigned long long)lo;
    return XST_SUCCESS;
}
// + at_first_err, + exp_data_at_first_err  — те же 9 строк × 3
```

**Предложение:** static helper:

```c
static int read64_lo_hi(unsigned int lo_off, unsigned int hi_off,
                        unsigned long long *out)
{
    unsigned int lo, hi;
    int rc = murosync_serdes_reg_rd(lo_off, &lo);
    if (rc != XST_SUCCESS) return rc;
    rc = murosync_serdes_reg_rd(hi_off, &hi);
    if (rc != XST_SUCCESS) return rc;
    *out = ((unsigned long long)hi << 32) | (unsigned long long)lo;
    return XST_SUCCESS;
}

int murosync_serdes_link_test_get_rx_data_at_lock(unsigned long long *data)
{ return read64_lo_hi(MUROSYNC_LNK_RX_DATA_AT_LOCK_LO_REG,
                      MUROSYNC_LNK_RX_DATA_AT_LOCK_HI_REG, data); }
// + 2 одноstrok'и для других двух
```

**Экономия:** ~27 строк превращаются в ~12. API не меняется.

### 1.2 Дедупликация per-channel getter'ов

**Текущее состояние:** `get_rxbyterealign_cnt` и `get_eyescandataerror_cnt`
делают одно и то же — packed 16-бит-на-канал в LO/HI парах регистров —
с разными парами регистров. Около 30 строк дублирующейся логики.

```c
// lines 670-697 (приблизительно): два почти-одинаковых блока
int murosync_serdes_get_rxbyterealign_cnt(unsigned char ch, unsigned int *cnt)
{
    if (ch > 3) return XST_FAILURE;
    unsigned int reg_val;
    unsigned int reg_ofs = (ch < 2) ? MUROSYNC_GT_RXBYTEREALIGN_CNT_LO_REG
                                    : MUROSYNC_GT_RXBYTEREALIGN_CNT_HI_REG;
    int stat = murosync_serdes_reg_rd(reg_ofs, &reg_val);
    if (stat != XST_SUCCESS) return stat;
    unsigned int shift = (ch & 1) ? MUROSYNC_GT_STICKY_CNT_CH_HI_OFS
                                  : MUROSYNC_GT_STICKY_CNT_CH_LO_OFS;
    *cnt = (reg_val >> shift) & 0xFFFFu;
    return XST_SUCCESS;
}
// + get_eyescandataerror_cnt: identical except register pair
```

**Предложение:** static helper с тремя параметрами (LO, HI, channel):

```c
static int read_packed16_ch(unsigned int lo_off, unsigned int hi_off,
                             unsigned char ch, unsigned int *cnt)
{
    if (ch > 3) return XST_FAILURE;
    unsigned int reg_val;
    unsigned int reg_ofs = (ch < 2) ? lo_off : hi_off;
    int rc = murosync_serdes_reg_rd(reg_ofs, &reg_val);
    if (rc != XST_SUCCESS) return rc;
    unsigned int shift = (ch & 1) ? 16 : 0;
    *cnt = (reg_val >> shift) & 0xFFFFu;
    return XST_SUCCESS;
}
```

**Экономия:** ~15 строк.

### 1.3 Дедупликация single-bit status getter'ов из STATUS2

В драйвере 4 функции читают регистр `LNK_DIAG_STATUS2` (0x070), выбирают
маской один бит/поле, возвращают:

- `get_ever_locked` (bit 0)
- `get_last_fsm_state` (bits 7:4)
- `get_rx_data_at_lock_valid` (bit 16)
- `get_first_err_valid` (bit 17)

Каждая — это 5 строк дубля. **Предложение:** static helper

```c
static int read_status2_field(unsigned int mask, unsigned int shift,
                              unsigned int *out)
{
    unsigned int v;
    int rc = murosync_serdes_reg_rd(MUROSYNC_LNK_DIAG_STATUS2_REG, &v);
    if (rc != XST_SUCCESS) return rc;
    *out = (v & mask) >> shift;
    return XST_SUCCESS;
}
```

Экономия: ~10 строк.

### 1.4 `run_link_test` — функция >150 строк, можно разбить

`murosync_serdes_run_link_test()` делает в одной функции:
1. Print test parameters (banner)
2. Reset counters
3. Configure cnfg/ch_mask/mode/pol_mask/pattern
4. Start
5. Sleep
6. Stop
7. Read err_cnt/wrd_cnt/ever_locked/at_lock_valid/per-CH errors
8. Verdict computation (5 fail conditions, 1 warn, 1 pass)
9. Print results

Можно разбить на 3-4 внутренних helper'а:
- `link_test_configure(mode, mask, pol, pattern)` — шаги 2-3
- `link_test_collect_results(struct *out)` — шаг 7
- `link_test_verdict(results)` — шаг 8

Это сделает функцию читаемее и позволит `phase1_test_one_pattern()` из
main.c использовать те же helper'ы (сейчас она дублирует
configure-логику).

### 1.5 `print_diag` — 95 строк, можно разделить на тематические блоки

`murosync_serdes_link_test_print_diag()` печатает три логические группы:
- Tier 0/1 (FSM, alignment, locked, RX/EXP data, ever_locked, last_state)
- Tier 2 timing (time_to_lock, locked_cycle_cnt)
- Tier 2 snapshots (at_lock, at_first_err GOT/EXP/XOR)
- Tier 2 counters (per-CH errors, byte_realign, eye scan)

Каждая группа — самостоятельная подсекция и могла бы быть отдельной
функцией `print_diag_tier0()`, `print_diag_timing()` и т.д. Это упростит
тестовые сценарии где нужна только часть телеметрии (например,
быстрый BER-snapshot хотел бы только Tier 2 counters).

### 1.6 BIST result decoder — table-driven

`murosync_serdes_print_bist_result()` сейчас — длинная цепочка
if-stmt'ов:

```c
if (result & MUROSYNC_SERDES_TEST_RESULT_AXI_FAIL)
    xil_printf("[BIST]     [bit 0]  AXI selftest failed\r\n");
if (result & MUROSYNC_SERDES_TEST_RESULT_BRINGUP_FAIL)
    xil_printf("[BIST]     [bit 1]  GT bring-up failed\r\n");
// ... ещё 5 таких
```

**Предложение:** static array of struct {mask, msg}:

```c
static const struct { unsigned int mask; const char *msg; }
bist_fail_table[] = {
    { MUROSYNC_SERDES_TEST_RESULT_AXI_FAIL,
      "[bit 0]  AXI selftest failed" },
    { MUROSYNC_SERDES_TEST_RESULT_BRINGUP_FAIL,
      "[bit 1]  GT bring-up failed" },
    /* ... */
};

for (size_t i = 0; i < ARRAY_SIZE(bist_fail_table); i++)
    if (result & bist_fail_table[i].mask)
        xil_printf("[BIST]     %s\r\n", bist_fail_table[i].msg);
```

Экономия меньше, но **добавить новый failure bit** становится одна
строка в таблице вместо два места.

### 1.7 Уровень шумности `xil_printf` в bring_up

`murosync_serdes_bring_up()` сейчас печатает 6+ статусных строк подряд.
Это полезно для интерактивного debug, но **в production main loop'е**
с пышным probe scaffolding уже накапливается серьёзная UART-нагрузка
(каждый bring_up = ~30 строк).

Опция: добавить параметр `verbose` к bring_up и pringing функциям,
либо ввести compile-time flag `#define MUROSYNC_VERBOSE` который
gating'ит non-fatal xil_printf вызовы. Production-режим выводит только
banner + final status, debug-режим — всё.

### 1.8 Naming inconsistency: `LOOPBACK_FAR` и `LOOPBACK_EXT`

```c
// driver.h:62-65
MUROSYNC_SERDES_LOOPBACK_NONE  = 0x0,    // Normal — OK
MUROSYNC_SERDES_LOOPBACK_NEAR  = 0x1,    // PCS NEAR-END — OK
MUROSYNC_SERDES_LOOPBACK_FAR   = 0x2,    // ⚠️ имя обманчивое — это PMA NEAR-END
MUROSYNC_SERDES_LOOPBACK_EXT   = 0x4     // ⚠️ имя обманчивое — это PMA FAR-END
```

Per PG182 / UG576:
- `0x1` = PCS Near-end (правильно `NEAR_PCS`)
- `0x2` = **PMA Near-end** (текущее имя `FAR` — наоборот)
- `0x4` = **PMA Far-end** (текущее имя `EXT` — невнятно)

**Предложение:** добавить более точные имена и оставить старые как
deprecated alias:

```c
typedef enum {
    MUROSYNC_SERDES_LOOPBACK_NONE      = 0x0,
    MUROSYNC_SERDES_LOOPBACK_NEAR_PCS  = 0x1,  /* digital, internal */
    MUROSYNC_SERDES_LOOPBACK_NEAR_PMA  = 0x2,  /* analog SerDes loopback */
    MUROSYNC_SERDES_LOOPBACK_FAR_PMA   = 0x4,  /* RX wire → TX reflection */
    MUROSYNC_SERDES_LOOPBACK_FAR_PCS  = 0x6,  /* RX PCS → TX PCS reflection */

    /* deprecated — kept for backward compatibility */
    MUROSYNC_SERDES_LOOPBACK_NEAR = MUROSYNC_SERDES_LOOPBACK_NEAR_PCS,
    MUROSYNC_SERDES_LOOPBACK_FAR  = MUROSYNC_SERDES_LOOPBACK_NEAR_PMA,
    MUROSYNC_SERDES_LOOPBACK_EXT  = MUROSYNC_SERDES_LOOPBACK_FAR_PMA,
} murosync_serdes_loopback_t;
```

Существующий код продолжает работать; новый код пользуется правильными
именами.

---

## Часть 2: `regs.h` consistency

### 2.1 Inconsistent `_REG` suffix

Tier 0/1 регистры (offsets 0x000-0x054) — **без** `_REG` суффикса:
- `MUROSYNC_SERDES_CTRL` (0x000)
- `MUROSYNC_LNK_TEST_CTRL` (0x01C)
- `MUROSYNC_LNK_DIAG_RX_LO` (0x034)

Tier 2 и более поздние (GT debug, Tier 2, IP_INFO) — **с** `_REG`:
- `MUROSYNC_GT_DEBUG_COMMA_ALIGN_REG` (0x058)
- `MUROSYNC_LNK_DIAG_STATUS2_REG` (0x070)
- `MUROSYNC_IP_INFO_REG` (0x074)
- `MUROSYNC_LNK_RX_DATA_AT_LOCK_LO_REG` (0x088)

**Источник:** более старые defines добавлялись без `_REG`, более новые —
с. Никакого функционального значения нет, чисто косметика.

**Предложение:** прийти к единому стилю. Поскольку большинство firmware
кода уже использует существующие имена, проще **добавить `_REG` ко всем
старым** через `#define` алиасы:

```c
/* Canonical names (with _REG suffix) */
#define MUROSYNC_SERDES_CTRL_REG       (0x000)
/* ... */

/* Legacy aliases (kept for source compatibility) */
#define MUROSYNC_SERDES_CTRL           MUROSYNC_SERDES_CTRL_REG
```

Или наоборот, убрать `_REG` со всех новых — но тогда нужно поправить
driver.c (он использует `_REG` сейчас в Tier 2). Альтернативный путь —
оставить как есть и просто **задокументировать соглашение** в
вступительном комментарии файла («исторически: Tier 0/1 без `_REG`,
Tier 2+ с `_REG`; новый код добавляет `_REG`»).

### 2.2 Tier 2 layout: EXP_DATA_AT_FIRST_ERR разорван с RX_DATA_AT_FIRST_ERR

Текущая раскладка (offsets):
- `0x090/094` — RX_DATA_AT_FIRST_ERR_LO/HI
- `0x098..0x0A4` — per-CH error counts (CH0..CH3)
- `0x0A8..0x0AC` — GT_RXBYTEREALIGN_CNT_LO/HI
- `0x0B0..0x0B4` — GT_EYESCANDATAERROR_CNT_LO/HI
- **`0x0B8/0BC` — EXP_DATA_AT_FIRST_ERR_LO/HI** ← добавлен в Stage 5

Логически `EXP_DATA_AT_FIRST_ERR` должен идти **сразу после**
`RX_DATA_AT_FIRST_ERR` (это пара для XOR-диагностики). Сейчас он
"приклеен" в конец карты потому что Stage 5 добавил его после того, как
free слотов между Tier 2 группами уже не было (0x09C занят).

**Это уже исторически — изменять offset = breaking change** и потребует
re-sync со всем firmware'ом. Не рекомендую трогать в "non-architectural"
улучшениях.

**Минимальное улучшение:** добавить в summary-table в начале файла явный
комментарий:
```
*  ⚠️  EXP_DATA_AT_FIRST_ERR (0x0B8/BC) логически парный с
*      RX_DATA_AT_FIRST_ERR (0x090/94), но размещён в конце Tier 2
*      из-за исторического порядка добавления (Stage 5).
```

### 2.3 Удалить устаревший комментарий про `BTRING-UP`

В `driver.h:99` и `driver.c` есть комментарии с опечаткой
`BTRING-UP` / `BTING-UP`. Это уже было flagged в CLAUDE.md cleanup #3
от 2026-05-25 но не закрыто:

```c
/*************************** BTRING-UP **********************************/
// driver.h line ~99
```

```c
xil_printf("\r\nAXI MUROSYNC SERDES BTING-UP\r\n");
// driver.c — каждый boot этот typo светится в UART логах
```

**Cost:** 2-3 строки. **Impact:** косметика, но видно в каждом UART логе.

### 2.4 Stale comment про LNK_TEST_CNFG modes

`regs.h` header (header summary block at top) утверждает что mode
`0/1/2 = Fixed/Counter/PRBS`, а RTL и regs.h defines говорят
`0/1/2 = Fixed/Toggle/Counter` (нет PRBS). Это уже было flagged в
cleanup #1 от 2026-05-25.

```c
// regs.h:42-44 — устарелое
*    0x020  MUROSYNC_LNK_TEST_CNFG        (RW)
*           [1:0]    MODE_SEL             Test Mode: 0=Fixed, 1=Counter, 2=PRBS
```

vs реальные defines на line 333-335:

```c
#define MUROSYNC_LNK_TEST_MODE_FIXED                  0
#define MUROSYNC_LNK_TEST_MODE_TOGGLE                 1
#define MUROSYNC_LNK_TEST_MODE_COUNTER                2
```

**Fix:** одна строка в комментарии.

---

## Часть 3: RTL improvements (low-risk refactor candidates)

### 3.1 axi_ctrl.sv: per-channel ASYNC_REG declarations можно унифицировать

**Текущее состояние:** смешанный стиль для CDC-синхронизаторов:

```systemverilog
// Style A: индивидуальные регистры (line 368)
(* ASYNC_REG="TRUE" *) logic [1:0] pll0_sync, pll1_sync, pll2_sync, pll3_sync;

// Style B: массив (line 388-390)
(* ASYNC_REG="TRUE" *) logic [1:0] gtp_sync [0:3];
(* ASYNC_REG="TRUE" *) logic [1:0] txp_sync [0:3];
(* ASYNC_REG="TRUE" *) logic [1:0] rxp_sync [0:3];
```

Style B (массивы + generate) — лучше: можно прокрутить через genvar и
обработать все каналы одной структурой. Style A написан расширенно.

**Предложение:** перевести pll_sync (line 368) на массив style, и
объединить с gtp/txp/rxp в один `generate for (gi=0; gi<4; gi++)` блок.
Сейчас три отдельных генерата на lines 393-411 — все три можно
объединить:

```systemverilog
// До: 3 отдельных generate × ~6 строк каждый
// После: 1 generate × ~12 строк, плюс единое объявление all-vectors

(* ASYNC_REG="TRUE" *) logic [1:0] pll_sync [0:3];
(* ASYNC_REG="TRUE" *) logic [1:0] gtp_sync [0:3];
(* ASYNC_REG="TRUE" *) logic [1:0] txp_sync [0:3];
(* ASYNC_REG="TRUE" *) logic [1:0] rxp_sync [0:3];

generate
    for (gi = 0; gi < 4; gi = gi + 1) begin : g_status_vec_sync
        always_ff @(posedge axi_clk or negedge axi_rst_n) begin
            if (!axi_rst_n) begin
                pll_sync[gi] <= '0;
                gtp_sync[gi] <= '0;
                txp_sync[gi] <= '0;
                rxp_sync[gi] <= '0;
            end else begin
                pll_sync[gi] <= {pll_sync[gi][0], pll_lock_in[gi]};
                gtp_sync[gi] <= {gtp_sync[gi][0], gtpowergood_in[gi]};
                txp_sync[gi] <= {txp_sync[gi][0], txpmaresetdone_in[gi]};
                rxp_sync[gi] <= {rxp_sync[gi][0], rxpmaresetdone_in[gi]};
            end
        end
    end
endgenerate
```

**Размер:** ~30 строк → ~15. Никаких функциональных изменений.

### 3.2 axi_ctrl.sv: Tier 2 per-CH err_cnt CDC — 4 одинаковых level_sync

Lines 736-747 содержат 4 индивидуальных инстанса
`murosync_cdc_level_sync` для err_cnt_ch0..ch3 — все одинаковые с
разными портами. **Можно генерат с массивом**:

```systemverilog
wire [15:0] diag_err_cnt_ch_axi [0:3];
wire [15:0] link_test_err_cnt_ch [0:3];
assign link_test_err_cnt_ch[0] = link_test_err_cnt_ch0;
// ...

generate
    for (gi = 0; gi < 4; gi = gi + 1) begin : g_err_ch_cdc
        murosync_cdc_level_sync #(.WIDTH(16), .SYNC_STAGES(2)) u_cdc (
            .clk  (axi_clk), .rst_n(axi_rst_n),
            .in   (link_test_err_cnt_ch[gi]),
            .out  (diag_err_cnt_ch_axi[gi])
        );
    end
endgenerate
```

**Размер:** ~12 строк → ~8.

Аналогично можно сделать для txctrl2_in packing (lines 591-596 в
serdes_array.sv) — 4 строки идентичной формы только индексы меняются.

### 3.3 serdes_array.sv: rxcharisk_int extraction комментарий — load-bearing, не трогать

Lines 497-525 — комментарий ~60 строк объясняющий 4-строчный wire
assignment. Это load-bearing документация про bit-position bug fix
2026-05-20 (Lesson #8). **Не упрощать.**

### 3.4 link_test.sv: txctrl2_out echo pattern

Lines 297-305:

```systemverilog
else if (IS_SLAVE)   txctrl2_out <= {rxcharisk[3], rxcharisk[3],
                                     rxcharisk[2], rxcharisk[2],
                                     rxcharisk[1], rxcharisk[1],
                                     rxcharisk[0], rxcharisk[0]};
```

Это дублирование per-channel бит на 2 байта в slice. **Можно через
generate** или `function`:

```systemverilog
function automatic [7:0] dup_charisk(input [3:0] in);
    dup_charisk = {in[3], in[3], in[2], in[2], in[1], in[1], in[0], in[0]};
endfunction

// usage:
else if (IS_SLAVE)   txctrl2_out <= dup_charisk(rxcharisk);
```

**Cosmetic** — выгода маленькая (читаемость), не trade-off.

### 3.5 link_test.sv: Tier 2 snapshot pattern repetition

Lines 514-531 (rx_data_at_lock) и lines 548-568 (rx_data_at_first_err
+ exp_data_at_first_err) — два очень похожих блока:

- Сигнал `capture_at_*` (комбинационный trigger)
- always_ff с reset/capture_cfg/capture логикой

```systemverilog
wire capture_at_lock = !rx_data_at_lock_valid && (...state == LOCKED);

always_ff @(posedge rx_clk or negedge core_rst_n) begin
    if (!core_rst_n)                          { reset to 0 }
    else if (rx_reset_pulse || capture_cfg)   { reset to 0 }
    else if (capture_at_lock)                 { snapshot rx_data }
end
```

Можно вынести в **локальный module** `snapshot_latch` с параметрами
WIDTH и портами:

```systemverilog
module snapshot_latch #(
    parameter int WIDTH = 64
)(
    input  wire              clk,
    input  wire              core_rst_n,
    input  wire              reset_pulse,    // sync reset
    input  wire              trigger,        // capture on this
    input  wire [WIDTH-1:0]  data_in,
    output reg  [WIDTH-1:0]  data_latched,
    output reg               valid
);
    wire capture = !valid && trigger;
    always_ff @(posedge clk or negedge core_rst_n) begin
        if (!core_rst_n)               { reset }
        else if (reset_pulse)          { reset }
        else if (capture) begin
            data_latched <= data_in;
            valid <= 1'b1;
        end
    end
endmodule
```

Тогда `rx_data_at_lock`, `rx_data_at_first_err`, `exp_data_at_first_err`
становятся три инстанса одного модуля. **Cost:** добавить новый файл
(или sub-module внутри link_test). **Benefit:** будущие Tier 2
snapshots добавляются однострочно.

### 3.6 link_test.sv: per-channel error counters generate уже хорош

Lines 596-606 уже используют generate. Это хороший pattern для других
мест.

---

## Часть 4: Top-level / serdes_array.sv

### 4.1 Закомментированные "rollback-safe" варианты

Lines 568-570 и 626-628 содержат закомментированный код:

```systemverilog
// rollback-safe: keep ONLY external reset applied to GT
//.gtwiz_reset_all_in (hb_gtwiz_reset_all_int),
.gtwiz_reset_all_in (hb_gtwiz_reset_all_int | gt_reset_all_pulse_axi),

// rollback-safe: force normal mode while debugging (3 bits per channel)
//.loopback_in ({4{3'b000}}),
.loopback_in ({4{loopback_ctrl}}),
```

Это **debug-rollback хуки** — если что-то начнёт глючить с AXI-driven
controls, переключение даст известно-безопасное поведение. Текущее
состояние работает, и закомментированные строки **остаются как
живой rollback knob**.

**Рекомендация:** оставить, но добавить более явный комментарий:
```
// rollback-safe: if AXI control becomes unreliable during debug,
// swap commented and uncommented lines below to force fixed-safe behavior.
// Currently active: AXI drives this signal. Last verified working: v1.5.
```

### 4.2 Wire declarations внутри instance body

Lines 470-481 объявляют wires **после** GT wrapper instantiation, но
**внутри** что было бы декорировано как proper module scope. Это уже
flagged как load-bearing комментарий (Lesson #98 в CLAUDE.md):

> 469: «Wire declarations - must come BEFORE GT wrapper instantiation
> to avoid implicit 1-bit nets»

Текущий порядок корректен (wire'ы используются GT wrapper'ом). **Не
трогать.**

### 4.3 Diagnostic wire bundles можно вынести в struct/interface

В serdes_array.sv lines 267-296 объявляется ~17 indvidual wires для
diagnostic сигналов от link_test → axi_ctrl. Это можно собрать в
`typedef struct`:

```systemverilog
typedef struct packed {
    logic [3:0]  fsm_state;
    logic [3:0]  rx_aligned;
    logic [3:0]  rx_aligned_seen;
    logic [3:0]  rx_charisk;
    logic        checker_locked;
    logic [63:0] rx_data;
    logic [63:0] exp_data;
    // ... Tier 2 fields
} link_test_diag_t;

link_test_diag_t link_test_diag;
```

И тогда `link_test → axi_ctrl` передача — одним struct port.

**Catch:** SystemVerilog struct + port в IP-XACT IP интерфейсе может
давать проблемы с Re-Package IP (Vivado packager не всегда хорошо
обрабатывает struct ports). **Risk vs benefit:** скорее не рекомендую,
оставить explicit wires (более safe для IP packager).

---

## Часть 5: Firmware (main.c)

### 5.1 Production vs debug разделение

Текущее состояние:
- `phase1_test_one_pattern` — debug probe scaffolding, живёт в `main.c`
- `bringup_master` сейчас НЕ использует `bring_up_with_bist` (orchestrator),
  а просто `bring_up + sweep` — это **debug mode**
- `bringup_master` имеет комментарий "Phase 1 pattern sweep" — debug
- BIST функционал в драйвере есть, но не вызывается из main

**Рекомендация:** перевести debug код в отдельный файл, и оставить
production main.c минималистичным:

```c
// main.c — production version (минималистичный):
static int murosync_app_bringup_master(void) {
    return murosync_serdes_bring_up_with_bist(
        MUROSYNC_SERDES_LOOPBACK_NONE, 5000000);
}

// + новый файл diag_probes.c с phase1_test_one_pattern,
//   phase1_pattern_sweep, etc.
```

Затем добавить **compile-time switch** в main.c:
```c
#ifdef MUROSYNC_DEBUG_PHASE1_PROBE
    extern int diag_run_phase1_sweep(void);
    rc = diag_run_phase1_sweep();
#else
    rc = murosync_app_bringup_master();
#endif
```

Это даёт **чистый production firmware** для нормальной работы, и
**вкл-able debug build** для probe-сценариев.

### 5.2 `main_loop` periodic GT ground truth — verbose

Каждые 10 alive heartbeats печатается ground truth (alignment +
realign). Это полезно для мониторинга но **очень многословно** в UART
логах. Опции:

- Снизить частоту (каждые 60s вместо каждых 10s)
- Печатать только при **изменении** ground truth (event-driven, не
  periodic)
- `#ifdef MUROSYNC_VERBOSE_HEARTBEAT` gate

### 5.3 Hardcoded constants в main.c

Magic numbers в main.c:
- `usleep(1000000)` — 1s settle delay (line 198) — `BOOT_SETTLE_USEC`
- `5000000` — bring_up timeout 5s — `BRINGUP_TIMEOUT_USEC`
- `1000000` — alive heartbeat 1s — `HEARTBEAT_INTERVAL_USEC`
- `alive_cnt % 10` — ground_truth periodicity — `GT_TRUTH_HEARTBEAT_DIV`
- `300000` в `phase1_test_one_pattern` — 300ms test window —
   `PHASE1_TEST_DURATION_USEC`

**Предложение:** `#define` named constants в начале main.c или
в новом `main_config.h`.

---

## Часть 6: Cross-cutting cleanup

### 6.1 Dead file: `murosync_serdes_array_mode.sv`

335 строк не-используемого RTL в IP src/. Уже flagged в CLAUDE.md
cleanup #2. Действие: `git rm` файл, run `update_ip_ports.tcl`,
re-package IP, rebuild bitstreams. **Cost:** ~30 минут.

### 6.2 CLAUDE.md cleanup checklist уже содержит 3 items

Из 2026-05-25:
1. `regs.h` LNK_TEST_CNFG MODE_SEL комментарий устарел — ВСЁ ЕЩЁ ОТКРЫТ
2. Удалить `murosync_serdes_array_mode.sv` — ВСЁ ЕЩЁ ОТКРЫТ
3. `BTRING-UP` typo fix — ВСЁ ЕЩЁ ОТКРЫТ

Закрытие всех трёх — ~1 час работы (включая rebuild IP).

### 6.3 Stale CLAUDE.md фрагменты

После Phase 1 closure (Bug #1, #2 fix, loop timing) CLAUDE.md и
Dev_Bench_Architecture **не обновлены** с финальной IP version (1.5)
и архитектурным выбором (SLAVE TX from RXOUTCLK). Также нужно добавить:

- Lesson про **mux в line 578** (Bug #1) — критичен для будущих
  refactors
- Lesson про **clock domain топологию SLAVE** (Bug #2) — для
  понимания почему SLAVE использует RXOUTCLK
- Раздел про **правильный ch_mask** (CH0 = SFP1 = fiber) в
  Dev_Bench_Architecture
- Финальная BER оценка (~1e-6 на CH0 с Bug #3 residual)

### 6.4 Документация по IP API в driver.h

`driver.h` сейчас — это список deklaracji без API-документации. Для
production library стоит:

- Doxygen-style comments перед каждой публичной функцией: что делает,
  inputs, outputs, return codes, side effects
- Группировка по подсистемам (CTRL, STATUS, LINK_TEST, BIST, GT_DEBUG,
  IP_INFO) с заголовочными комментариями
- Example usage в начале файла

Cost: ~3-4 часа документации, без code changes.

---

## Часть 7: Priority recommendations

### 🔴 High priority (low cost, high value)

| # | Action | Cost | Files |
|---|---|---|---|
| 1 | Fix typo `BTRING-UP` → `BRING-UP` | 5 мин | driver.h, driver.c |
| 2 | Fix `LNK_TEST_CNFG` mode comment | 2 мин | regs.h |
| 3 | Дедупликация 64-битных getter'ов | 15 мин | driver.c |
| 4 | Дедупликация per-channel getter'ов | 10 мин | driver.c |
| 5 | Дедупликация single-bit STATUS2 getter'ов | 10 мин | driver.c |
| 6 | Удалить `murosync_serdes_array_mode.sv` + rebuild IP | 30 мин | gateware |
| 7 | Добавить deprecated aliases для LOOPBACK_FAR/EXT | 5 мин | driver.h |
| 8 | Обновить CLAUDE.md (Bug #1, #2, ch_mask, v1.5) | 20 мин | docs |

**Total:** ~1.5 часа работы → драйвер чище на ~80 строк, документация
актуальна, dead file удалён.

### 🟡 Medium priority (cosmetic + readability)

| # | Action | Cost | Files |
|---|---|---|---|
| 9 | Разбить `run_link_test` на configure + run + verdict helpers | 30 мин | driver.c |
| 10 | Разбить `print_diag` на tematic groups | 20 мин | driver.c |
| 11 | BIST decoder → table-driven | 15 мин | driver.c |
| 12 | axi_ctrl: унификация per-channel ASYNC_REG в массив + generate | 20 мин | axi_ctrl.sv |
| 13 | Привести regs.h к единому `_REG` suffix style (через aliases) | 30 мин | regs.h |
| 14 | Magic numbers в main.c → named constants | 15 мин | main.c |

**Total:** ~2 часа → читаемее, расширяемее.

### 🟢 Low priority (nice-to-have, requires care)

| # | Action | Cost | Files |
|---|---|---|---|
| 15 | Tier 2 snapshot pattern → `snapshot_latch` submodule | 1 час | link_test.sv |
| 16 | Production/debug разделение main.c (phase1 probes → отдельный файл) | 2 часа | main.c + new file |
| 17 | Verbose mode flag для bring_up xil_printf | 1 час | driver.c/.h |
| 18 | API doc Doxygen-style в driver.h | 3-4 часа | driver.h |
| 19 | Diagnostic wire bundle → struct (если IP packager OK) | 2 часа | serdes_array.sv |
| 20 | Move `phase1_test_one_pattern` логику внутрь driver.c для переиспользования | 1 час | driver.c, main.c |

---

## Часть 8: Что НЕ рекомендую трогать

Эти места выглядят как кандидаты на улучшение, но имеют скрытые причины
оставить как есть:

- **`rxcharisk_int` extraction comment block** (60 строк коммента vs 4
  строки RTL в `serdes_array.sv:497-525`). Это историческая
  документация про bit-position bug 2026-05-20. Не упрощать —
  load-bearing.

- **Wire declarations after GT wrapper inst в `serdes_array.sv`**.
  Порядок load-bearing (Lesson #98 в CLAUDE.md). Не reorganize.

- **"Rollback-safe" закомментированные варианты в `serdes_array.sv`**.
  Это debug knobs которые могут понадобиться при future GT
  instability. Оставить, но дописать комментарий.

- **EXP_DATA_AT_FIRST_ERR layout (0x0B8/0xBC)**. Логически должно идти
  рядом с RX_DATA_AT_FIRST_ERR (0x090/0x094), но менять offsets =
  breaking change. Оставить.

- **`murosync_cdc_level_sync` comment про non-coherent bits** —
  важное предупреждение, не trim.

- **`localparam IS_SLAVE`** в serdes_array.sv. Раньше был `parameter` и
  это вызвало Bug #6 (Lesson #6 в CLAUDE.md). Сейчас правильно. **Не
  возвращать к parameter ни при каких условиях.**

- **Single-flop `rx_data_r` register cascade pattern (тут уже всё
  правильно)** — fix #2 сделал clocks одинаковыми на SLAVE, так что
  безопасно. На MASTER cascade не используется (gating IS_SLAVE).

---

## TL;DR

**Quick wins (1.5 часа):** fix два typo, удалить dead file, дедупликация
~60 строк в driver.c через 3 static helper'а, обновить CLAUDE.md.

**Medium polish (2 часа):** generate-based unification в axi_ctrl,
разбиение длинных функций в driver, naming consistency в regs.h.

**Production hardening (~5-7 часов):** API doc, разделение
debug/production, generic snapshot_latch module, magic numbers cleanup.

**Не трогать:** load-bearing комментарии, rollback-safe knobs, IS_SLAVE
localparam, существующие register offsets, wire declaration order.

Архитектура работает чисто после Phase 1. Все предложенные улучшения —
**code hygiene без поведенческих изменений**.
