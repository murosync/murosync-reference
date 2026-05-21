/******************************************************************************
 * Project    : MuroSync
 * File       : murosync_serdes_link_test.sv
 * Created    : 2026-05-05
 * Author     : Mikhail Vasilev
 *
 * Description:
 *   High-speed SERDES link testing and validation module.
 *
 *   Features a robust, two-process FSM architecture for generating and
 *   checking test patterns (FIXED, TOGGLE, COUNTER) across the SERDES link.
 *   Provides word and error counters, dynamic channel masking, and automatic
 *   resynchronization upon encountering transient bit errors in COUNTER mode.
 *
 * Notes:
 *   - The checker FSM explicitly requires `enable` to be high to run.
 *   - Error and word counters are preserved after testing for AXI readout.
 *   - `default_nettype none` is used for stricter compile-time checks.
 *
 *  Copyright (c) 2026 Mikhail Vasilev / MuroSync
 *
 *  License:
 *  This file is currently released under a restricted research license.
 *  Licensing terms may change in future revisions of the project.
 *
 *  Commercial use, redistribution, or integration into commercial products
 *  requires an explicit license agreement.
 *
 *  For licensing inquiries, please contact:
 *      info@murosync.com
 *
 *****************************************************************************/

`default_nettype none

module murosync_serdes_link_test #(
    parameter bit IS_SLAVE = 1'b0
)(
    input  wire        tx_clk,
    input  wire        rx_clk,
    input  wire        core_rst_n,

    // Control from AXI (core_clk domain)
    input  wire        tx_enable_in,
    input  wire        rx_enable_in,
    input  wire        tx_reset_counters,
    input  wire        rx_reset_counters,
    input  wire [15:0] cnfg,           // [15:12] TX Pol Mask, [11:8] RX Pol Mask, [7:4] Ch Mask, [1:0] Mode
    input  wire [31:0] fixed_patt,

    // 8B10B: RXCHARISCOMMA sticky — 1 bit per channel, latched in rx_clk domain
    input  wire [3:0]  rxbyteisaligned,

    // 8B10B: RXCHARISK — 1 bit per channel, high when current word contains a K-symbol
    // Checker must skip these words — they are comma/control, not data
    input  wire [3:0]  rxcharisk,

    // Data interfaces
    output logic [63:0] tx_data,
    input  wire  [63:0] rx_data,

    // 8B10B: TXCHARISK — [1:0]=CH0, [3:2]=CH1, [5:4]=CH2, [7:6]=CH3
    output logic [7:0]  txctrl2_out,

    // Status to AXI (will be CDC'd by axi_ctrl)
    output logic [31:0] err_cnt,
    output logic [31:0] wrd_cnt,

    // Diagnostic outputs — rx_clk domain, 2FF sync in axi_ctrl
    output wire [3:0]  diag_fsm_state,      // rx_checker_curr_state
    output wire [3:0]  diag_rx_aligned,     // rxbyteisaligned (direct from GT)
    output wire [3:0]  diag_rx_comma_seen,  // rx_comma_seen (sticky latch)
    output wire [3:0]  diag_rx_charisk,     // rxcharisk (current cycle)
    output wire        diag_checker_locked, // 1 = FSM in ST_LOCKED
    output wire [63:0] diag_rx_data,        // rx_data_corrected
    output wire [63:0] diag_exp_data,       // expected_rx
    
    // Additional diagnostic outputs (tx_clk domain)
    output wire [63:0] diag_tx_data,           // current TX pattern
    output wire [15:0] diag_tx_counter_ch0,    // TX counter channel 0
    output wire [15:0] diag_tx_counter_ch1,    // TX counter channel 1  
    output wire [15:0] diag_tx_counter_ch2,    // TX counter channel 2
    output wire [15:0] diag_tx_counter_ch3,    // TX counter channel 3
    output wire        diag_tx_comma_active,   // TX sending comma
    output wire [11:0] diag_tx_comma_count,    // comma training counter

    // Additional diagnostic outputs (rx_clk domain) — Tier 1
    output wire        diag_ever_locked,        // Sticky: FSM reached LOCKED at least once during this test
    output wire [3:0]  diag_last_fsm_state      // Last non-IDLE state before drop on rx_enable=0
);

    // ============================================================
    // Control Signals 
    // ============================================================
    wire rx_reset_pulse = rx_reset_counters;
    wire tx_reset_pulse = tx_reset_counters;
    wire tx_enable      = tx_enable_in;
    wire rx_enable      = rx_enable_in;

    // Edge detectors for TX enable
    reg tx_enable_d;
    always @(posedge tx_clk or negedge core_rst_n) 
    begin
        if (!core_rst_n) tx_enable_d <= 1'b0;
        else             tx_enable_d <= tx_enable;
    end
    wire tx_enable_re = tx_enable && !tx_enable_d;

    // ------------------------------------------------------------
    // Shadow Registers (Fool-Proofing)
    // ------------------------------------------------------------
    reg [63:0] tx_fixed_64;
    reg [1:0]  tx_test_mode;
    
    reg   [63:0] rx_fixed_64;
    reg   [3:0]  rx_ch_mask;
    reg   [3:0]  rx_pol_mask;
    reg   [3:0]  tx_pol_mask;
    reg   [1:0]  rx_test_mode;
    logic        capture_cfg; // Combinational — driven by always @(*)

    localparam  TEST_MODE_FIXED   = 2'b00;
    localparam  TEST_MODE_TOGGLE  = 2'b01;
    localparam  TEST_MODE_COUNTER = 2'b10;

    // K28.5 in 8-bit form (GT 8B10B encoder maps to 10-bit on the wire)
    localparam logic [7:0] K28_5        = 8'hBC;
    // Training: send continuous K28.5 for this many cycles at test start
    localparam integer     TRAIN_LEN    = 4096;  // ~13 us at 312.5 MHz
    // After training: send K28.5 periodically to maintain alignment
    localparam integer     COMMA_PERIOD = 1024;  // ~3.3 us

    always @(posedge tx_clk or negedge core_rst_n) 
    begin
        if (!core_rst_n) 
        begin
            tx_fixed_64  <= 64'h0;
            tx_test_mode <= TEST_MODE_FIXED;
            tx_pol_mask  <= 4'h0;
        end 
        else if (tx_enable_re) 
        begin
            tx_fixed_64  <= {fixed_patt, fixed_patt};
            tx_test_mode <= cnfg[1:0];
            tx_pol_mask  <= cnfg[15:12];
        end
    end

    always @(posedge rx_clk or negedge core_rst_n) 
    begin
        if (!core_rst_n) 
        begin
            rx_fixed_64  <= 64'h0;
            rx_test_mode <= TEST_MODE_FIXED;
            rx_ch_mask   <= 4'h0;
            rx_pol_mask  <= 4'h0;
        end 
        else if (capture_cfg) 
        begin
            rx_fixed_64  <= {fixed_patt, fixed_patt};
            rx_test_mode <= cnfg[1:0];
            rx_ch_mask   <= cnfg[7:4];
            rx_pol_mask  <= cnfg[11:8];
        end
    end

    // ============================================================
    // TX Pattern Generator + Comma Burst
    // ============================================================
    reg [15:0] counter_val_ch [0:3];
    reg        toggle_state;

    // ============================================================
    // TX Comma FSM
    // ============================================================
    localparam integer TX_ST_IDLE        = 0;
    localparam integer TX_ST_TRAINING    = 1;
    localparam integer TX_ST_MAINTENANCE = 2;

    reg [1:0] tx_comma_next_state;
    reg [1:0] tx_comma_curr_state;

    reg [11:0] comma_cnt;
    logic      send_comma;  // combinational output of FSM

    // 1. Sequential state update
    always @(posedge tx_clk or negedge core_rst_n)
    begin
        if (!core_rst_n) tx_comma_curr_state <= TX_ST_IDLE;
        else             tx_comma_curr_state <= tx_comma_next_state;
    end

    // 2. Combinational next state + output logic
    always @(*)
    begin
        tx_comma_next_state = tx_comma_curr_state;
        send_comma          = 1'b0;

        case (tx_comma_curr_state)
            TX_ST_IDLE:
            begin
                if (tx_enable && !IS_SLAVE) tx_comma_next_state = TX_ST_TRAINING;
            end

            TX_ST_TRAINING:
            begin
                if (!tx_enable || IS_SLAVE)          tx_comma_next_state = TX_ST_IDLE;
                else if (comma_cnt == TRAIN_LEN - 1) tx_comma_next_state = TX_ST_MAINTENANCE;

                send_comma = 1'b1;
            end

            TX_ST_MAINTENANCE:
            begin
                if (!tx_enable || IS_SLAVE)             tx_comma_next_state = TX_ST_IDLE;
                else if (comma_cnt == COMMA_PERIOD - 1) send_comma = 1'b1;
            end

            default: tx_comma_next_state = TX_ST_IDLE;
        endcase
    end

    // 3. Sequential counter
    always @(posedge tx_clk or negedge core_rst_n)
    begin
        if (!core_rst_n)
        begin
            comma_cnt <= '0;
        end
        else
        begin
            case (tx_comma_curr_state)
                TX_ST_IDLE:        comma_cnt <= '0;
                TX_ST_TRAINING:    comma_cnt <= (comma_cnt == TRAIN_LEN - 1)    ? '0 : comma_cnt + 1'b1;
                TX_ST_MAINTENANCE: comma_cnt <= (comma_cnt == COMMA_PERIOD - 1) ? '0 : comma_cnt + 1'b1;
                default:           comma_cnt <= '0;
            endcase
        end
    end

    always @(posedge tx_clk or negedge core_rst_n) 
    begin
        if (!core_rst_n) 
        begin
            counter_val_ch[0] <= 16'h0;
            counter_val_ch[1] <= 16'h0;
            counter_val_ch[2] <= 16'h0;
            counter_val_ch[3] <= 16'h0;
            toggle_state <= 1'b0;
        end
        else if (tx_enable && !IS_SLAVE) 
        begin
            counter_val_ch[0] <= (tx_reset_pulse) ? 16'h0 : (counter_val_ch[0] + 1);
            counter_val_ch[1] <= (tx_reset_pulse) ? 16'h0 : (counter_val_ch[1] + 1);
            counter_val_ch[2] <= (tx_reset_pulse) ? 16'h0 : (counter_val_ch[2] + 1);
            counter_val_ch[3] <= (tx_reset_pulse) ? 16'h0 : (counter_val_ch[3] + 1);
            toggle_state <= (tx_reset_pulse) ? 1'b0  : (~toggle_state);
        end            
    end

    // Simple fabric logical loopback register for Slave mode
    reg [63:0] rx_data_r;
    always @(posedge tx_clk or negedge core_rst_n) 
    begin
        if (!core_rst_n) rx_data_r <= 64'h0;
        else             rx_data_r <= rx_data;
    end

// TXCHARISK — K-symbol control
    always @(posedge tx_clk or negedge core_rst_n)
    begin
        if (!core_rst_n)     txctrl2_out <= 8'h0;
        else if (send_comma) txctrl2_out <= 8'hFF;
        else                 txctrl2_out <= 8'h0;
    end

    // TX data pattern
    always @(posedge tx_clk or negedge core_rst_n)
    begin
        if (!core_rst_n)           tx_data <= 64'h0;
        else if (IS_SLAVE)         tx_data <= rx_data_r;
        else if (send_comma)       tx_data <= {8{K28_5}};
        else 
        begin : tx_pattern
            logic [63:0] raw;

            if      (tx_test_mode == TEST_MODE_FIXED)   raw = tx_fixed_64;
            else if (tx_test_mode == TEST_MODE_TOGGLE)  raw = toggle_state ? tx_fixed_64 : ~tx_fixed_64;
            else                                        raw = {counter_val_ch[3],
                                                               counter_val_ch[2],
                                                               counter_val_ch[1],
                                                               counter_val_ch[0]};

            tx_data[15:0]  <= tx_pol_mask[0] ? ~raw[15:0]  : raw[15:0];
            tx_data[31:16] <= tx_pol_mask[1] ? ~raw[31:16] : raw[31:16];
            tx_data[47:32] <= tx_pol_mask[2] ? ~raw[47:32] : raw[47:32];
            tx_data[63:48] <= tx_pol_mask[3] ? ~raw[63:48] : raw[63:48];
        end
    end

    // ============================================================
    // RX Checker
    // ============================================================
    function logic is_match_by_channel(input [63:0] act, input [63:0] exp, input [3:0] mask);
        logic match;
        match = 1'b1;
        if (mask[0] && act[15:0]  != exp[15:0])  match = 1'b0;
        if (mask[1] && act[31:16] != exp[31:16]) match = 1'b0;
        if (mask[2] && act[47:32] != exp[47:32]) match = 1'b0;
        if (mask[3] && act[63:48] != exp[63:48]) match = 1'b0;
        return match;
    endfunction

    // ------------------------------------------------------------
    // FSM States
    // ------------------------------------------------------------
    localparam integer RX_ST_IDLE        = 0;
    localparam integer RX_ST_CAPTURE_CFG = 1;
    localparam integer RX_ST_WAIT_ALIGN  = 2;  // wait for rxbyteisaligned after config captured
    localparam integer RX_ST_SEARCH      = 3;
    localparam integer RX_ST_LOCKED      = 4;

    reg [3:0] rx_checker_next_state;
    (* keep = "true", mark_debug = "true" *) reg [3:0] rx_checker_curr_state;

    logic        checker_locked; // Combinational — driven by always @(*)
    reg   [63:0] expected_rx;
    
    reg [63:0] rx_data_corrected;
    always @(posedge rx_clk or negedge core_rst_n) 
    begin
        if (!core_rst_n) rx_data_corrected <= 64'h0;
        else 
        begin
            rx_data_corrected[15:0]  <= rx_pol_mask[0] ? ~rx_data[15:0]  : rx_data[15:0];
            rx_data_corrected[31:16] <= rx_pol_mask[1] ? ~rx_data[31:16] : rx_data[31:16];
            rx_data_corrected[47:32] <= rx_pol_mask[2] ? ~rx_data[47:32] : rx_data[47:32];
            rx_data_corrected[63:48] <= rx_pol_mask[3] ? ~rx_data[63:48] : rx_data[63:48];
        end
    end

    // Previous data register for robust COUNTER lock
    reg [63:0] rx_data_d;
    always @(posedge rx_clk or negedge core_rst_n) 
    begin
        if (!core_rst_n) rx_data_d <= 64'h0;
        else             rx_data_d <= rx_data_corrected;
    end

    wire is_fixed_mode   = (rx_test_mode == TEST_MODE_FIXED);
    wire is_toggle_mode  = (rx_test_mode == TEST_MODE_TOGGLE);
    wire is_counter_mode = (rx_test_mode == TEST_MODE_COUNTER);

    wire [63:0] rx_data_d_plus_1 = {rx_data_d[63:48] + 16'h1, rx_data_d[47:32] + 16'h1, rx_data_d[31:16] + 16'h1, rx_data_d[15:0] + 16'h1};

    wire match_fixed       = is_fixed_mode   && is_match_by_channel(rx_data_corrected, rx_fixed_64, rx_ch_mask);
    wire match_toggle_pos  = is_toggle_mode  && is_match_by_channel(rx_data_corrected, rx_fixed_64, rx_ch_mask);
    wire match_toggle_neg  = is_toggle_mode  && is_match_by_channel(rx_data_corrected, ~rx_fixed_64, rx_ch_mask);
    wire match_counter     = is_counter_mode && is_match_by_channel(rx_data_corrected, rx_data_d_plus_1, rx_ch_mask);
    wire match_expected    = is_match_by_channel(rx_data_corrected, expected_rx, rx_ch_mask);
    wire match_any         = match_fixed || match_toggle_pos || match_toggle_neg || match_counter;

    // ------------------------------------------------------------
    // Combinational Signals
    // ------------------------------------------------------------
    logic lock_acquired;
    logic err_cnt_inc;
    logic wrd_cnt_inc;
    logic [63:0] next_expected_rx;

    // 1. Sequential State Update
    always @(posedge rx_clk or negedge core_rst_n) 
    begin
        if (!core_rst_n) rx_checker_curr_state <= RX_ST_IDLE;
        else             rx_checker_curr_state <= rx_checker_next_state;
    end

    // Sticky alignment latch — per-channel.
    // Accumulates `rxbyteisaligned` (level signal from GT Wizard dedicated port).
    // Cleared on reset_pulse and on test start (capture_cfg).
    // Once a channel has been aligned during this test run, the bit stays high
    // even if alignment is momentarily lost — useful for post-mortem diagnostic.
    //
    // NOTE: prior name was rx_comma_seen — inaccurate, because what is latched is
    // rxbyteisaligned (post-alignment status), not rxchariscomma (comma detection).
    reg [3:0] rx_aligned_seen;
    always @(posedge rx_clk or negedge core_rst_n)
    begin
        if (!core_rst_n)         rx_aligned_seen <= 4'b0;
        else if (rx_reset_pulse) rx_aligned_seen <= 4'b0;
        else if (capture_cfg)    rx_aligned_seen <= 4'b0;
        else                     rx_aligned_seen <= rx_aligned_seen | rxbyteisaligned;
    end

    // Sticky flag — was the checker ever in LOCKED state during this test run?
    // Cleared on reset_pulse and on test start (capture_cfg).
    // Set when FSM enters RX_ST_LOCKED for the first time and held until next reset.
    // Survives transition back to IDLE on test stop — critical for post-mortem diagnostic.
    reg ever_locked;
    always @(posedge rx_clk or negedge core_rst_n)
    begin
        if (!core_rst_n)                                 ever_locked <= 1'b0;
        else if (rx_reset_pulse)                         ever_locked <= 1'b0;
        else if (capture_cfg)                            ever_locked <= 1'b0;
        else if (rx_checker_curr_state == RX_ST_LOCKED)  ever_locked <= 1'b1;
    end

    // Latches the LAST ACTIVE state before FSM drops to IDLE on rx_enable=0.
    // "Active" = any state other than IDLE.
    // Allows post-stop diagnostic: "FSM exit state was LOCKED" vs "FSM never left WAIT_ALIGN".
    // Reset on test start (capture_cfg), updated whenever current state is non-IDLE.
    reg [3:0] last_fsm_state;
    always @(posedge rx_clk or negedge core_rst_n)
    begin
        if (!core_rst_n)                              last_fsm_state <= RX_ST_IDLE;
        else if (rx_reset_pulse)                      last_fsm_state <= RX_ST_IDLE;
        else if (capture_cfg)                         last_fsm_state <= RX_ST_IDLE;
        else if (rx_checker_curr_state != RX_ST_IDLE) last_fsm_state <= rx_checker_curr_state[3:0];
        // else: FSM is in IDLE — hold last_fsm_state with the value before the transition
    end

    // Gate: all channels in mask must have rxbyteisaligned=1 (latched)
    // Registered to break combinational path into FSM next_expected_rx computation
    reg aligned_or_nomask_r;
    reg any_ksymbol_r;

    always @(posedge rx_clk or negedge core_rst_n) 
    begin
        if (!core_rst_n) aligned_or_nomask_r <= 1'b0;
        else             aligned_or_nomask_r <= (rx_ch_mask == 4'h0) ? 1'b1 :
                                                (((rx_aligned_seen | rxbyteisaligned) & rx_ch_mask) == rx_ch_mask);
    end

    always @(posedge rx_clk or negedge core_rst_n) 
    begin
        if (!core_rst_n) any_ksymbol_r <= 1'b0;
        else             any_ksymbol_r <= |(rxcharisk & rx_ch_mask);
    end

    // 2. Combinational Next State & Output Logic
    always @(*) 
    begin
        // Default assignments to prevent latches
        rx_checker_next_state = rx_checker_curr_state;
        
        capture_cfg           = 1'b0;
        lock_acquired         = 1'b0;
        err_cnt_inc           = 1'b0;
        wrd_cnt_inc           = 1'b0;
        checker_locked        = 1'b0;

        next_expected_rx      = expected_rx; // Default hold

        case (rx_checker_curr_state)
            RX_ST_IDLE: 
            begin
                if (rx_enable && !IS_SLAVE && !rx_reset_pulse) rx_checker_next_state = RX_ST_CAPTURE_CFG;
            end

            RX_ST_CAPTURE_CFG: 
            begin
                // 1 cycle only: capture config into shadow registers.
                // rx_ch_mask will be valid on the NEXT clock edge.
                // Transition unconditionally to ST_WAIT_ALIGN.
                capture_cfg = 1'b1;

                if (!rx_enable || rx_reset_pulse) rx_checker_next_state = RX_ST_IDLE;
                else                              rx_checker_next_state = RX_ST_WAIT_ALIGN;
            end

            RX_ST_WAIT_ALIGN:
            begin
                // rx_ch_mask is now valid (captured in ST_CAPTURE_CFG).
                // Wait here until all masked channels assert rxbyteisaligned.
                // rx_aligned_seen accumulates rxbyteisaligned OR each cycle.
                if (!rx_enable || rx_reset_pulse) rx_checker_next_state = RX_ST_IDLE;
                else if (aligned_or_nomask_r)     rx_checker_next_state = RX_ST_SEARCH;
                // else: stay until GT completes 8B10B word alignment
            end

            RX_ST_SEARCH: 
            begin
                // Skip K-symbol cycles — they are comma/control, not data
                if (!any_ksymbol_r && match_any) lock_acquired = 1'b1;

                if (!rx_enable || rx_reset_pulse) rx_checker_next_state = RX_ST_IDLE;
                else if (lock_acquired)           rx_checker_next_state = RX_ST_LOCKED;

                if (lock_acquired) begin
                    case (rx_test_mode)
                        TEST_MODE_FIXED:   next_expected_rx = rx_fixed_64;
                        TEST_MODE_TOGGLE:  next_expected_rx = match_toggle_pos ? ~rx_fixed_64 : rx_fixed_64;
                        TEST_MODE_COUNTER: next_expected_rx = {
                            rx_data_corrected[63:48] + 16'h1,
                            rx_data_corrected[47:32] + 16'h1,
                            rx_data_corrected[31:16] + 16'h1,
                            rx_data_corrected[15:0]  + 16'h1
                        };

                        default:           next_expected_rx = rx_fixed_64;
                    endcase
                end
            end

            RX_ST_LOCKED: 
            begin
                if (!rx_enable || rx_reset_pulse) rx_checker_next_state = RX_ST_IDLE;

                checker_locked = 1'b1;

                // Skip K-symbol words: don't count, don't check, don't advance expected
                if (!any_ksymbol_r) begin
                    wrd_cnt_inc = 1'b1;
                    if (!match_expected) err_cnt_inc = 1'b1;
                end

                case (rx_test_mode)
                    TEST_MODE_FIXED:   next_expected_rx = rx_fixed_64;
                    TEST_MODE_TOGGLE:  next_expected_rx = ~expected_rx;
                    TEST_MODE_COUNTER: next_expected_rx =
                        any_ksymbol_r    ? expected_rx :       // K-symbol: hold unchanged
                        err_cnt_inc      ?                     // Error: resync from received
                            {
                                rx_data_corrected[63:48] + 16'h1,
                                rx_data_corrected[47:32] + 16'h1,
                                rx_data_corrected[31:16] + 16'h1,
                                rx_data_corrected[15:0]  + 16'h1
                            } :
                            {
                                expected_rx[63:48] + 16'h1,
                                expected_rx[47:32] + 16'h1,
                                expected_rx[31:16] + 16'h1,
                                expected_rx[15:0]  + 16'h1
                            };

                    default: next_expected_rx = expected_rx;
                endcase
            end

            default: rx_checker_next_state = RX_ST_IDLE;
        endcase
    end

    // 3. Sequential Tracking Blocks
    always @(posedge rx_clk or negedge core_rst_n) 
    begin
        if (!core_rst_n) expected_rx <= 64'b0;
        else             expected_rx <= next_expected_rx;
    end

    always @(posedge rx_clk or negedge core_rst_n) 
    begin
        if (!core_rst_n)         err_cnt <= 32'b0;
        else if (rx_reset_pulse) err_cnt <= 32'b0;
        else                     err_cnt <= (err_cnt_inc) ? (err_cnt + 1) : (err_cnt);
    end

    always @(posedge rx_clk or negedge core_rst_n) 
    begin
        if (!core_rst_n)         wrd_cnt <= 32'b0;
        else if (rx_reset_pulse) wrd_cnt <= 32'b0;
        else                     wrd_cnt <= (wrd_cnt_inc) ? (wrd_cnt + 1) : (wrd_cnt);
    end

    // ------------------------------------------------------------
    // Diagnostic output assignments (rx_clk domain)
    // 2FF synchronization to axi_clk done in murosync_serdes_array_axi_ctrl
    // ------------------------------------------------------------
    assign diag_fsm_state      = rx_checker_curr_state[3:0];
    assign diag_rx_aligned     = rxbyteisaligned;
    assign diag_rx_comma_seen  = rx_aligned_seen;  // Sticky alignment status per channel
                                                    // (name kept for AXI register backwards compatibility)
    assign diag_rx_charisk     = rxcharisk;
    assign diag_checker_locked = checker_locked;
    assign diag_rx_data        = rx_data_corrected;
    assign diag_exp_data       = expected_rx;

    // TX Diagnostics
    assign diag_tx_data         = tx_data;
    assign diag_tx_counter_ch0  = counter_val_ch[0];
    assign diag_tx_counter_ch1  = counter_val_ch[1];
    assign diag_tx_counter_ch2  = counter_val_ch[2];
    assign diag_tx_counter_ch3  = counter_val_ch[3];
    assign diag_tx_comma_active = send_comma;
    assign diag_tx_comma_count  = comma_cnt;

    // Tier 1 sticky diagnostics
    assign diag_ever_locked    = ever_locked;
    assign diag_last_fsm_state = last_fsm_state;

endmodule
`default_nettype wire
