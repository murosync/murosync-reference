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
    input  wire        enable,
    input  wire        reset_counters,
    input  wire [7:0]  cnfg,           // [7:4] Mask, [1:0] Mode
    input  wire [31:0] fixed_patt,

    // Data interfaces
    output logic [63:0] tx_data,
    input  wire  [63:0] rx_data,

    // Status to AXI (will be CDC'd by axi_ctrl)
    output logic [31:0] err_cnt,
    output logic [31:0] wrd_cnt
);

    // ============================================================
    // Control Signals 
    // ============================================================
    wire rx_reset_pulse = reset_counters;
    wire tx_reset_pulse = reset_counters;
    wire tx_enable      = enable;
    wire rx_enable      = enable;

    // Edge detectors for TX enable
    logic tx_enable_d;
    always @(posedge tx_clk or negedge core_rst_n) 
    begin
        if (!core_rst_n) tx_enable_d <= 1'b0;
        else             tx_enable_d <= tx_enable;
    end
    wire tx_enable_re = tx_enable && !tx_enable_d;

    // ------------------------------------------------------------
    // Shadow Registers (Fool-Proofing)
    // ------------------------------------------------------------
    logic [63:0] tx_fixed_64;
    logic [1:0]  tx_test_mode;
    
    logic [63:0] rx_fixed_64;
    logic [3:0]  rx_ch_mask;
    logic [1:0]  rx_test_mode;
    logic        capture_cfg; // Driven by RX Checker FSM

    localparam  TEST_MODE_FIXED   = 2'b00;
    localparam  TEST_MODE_TOGGLE  = 2'b01;
    localparam  TEST_MODE_COUNTER = 2'b10;

    always @(posedge tx_clk or negedge core_rst_n) 
    begin
        if (!core_rst_n) 
        begin
            tx_fixed_64  <= 64'h0;
            tx_test_mode <= TEST_MODE_FIXED;
        end 
        else if (tx_enable_re) 
        begin
            tx_fixed_64  <= {fixed_patt, fixed_patt};
            tx_test_mode <= cnfg[1:0];
        end
    end

    always @(posedge rx_clk or negedge core_rst_n) 
    begin
        if (!core_rst_n) 
        begin
            rx_fixed_64  <= 64'h0;
            rx_test_mode <= TEST_MODE_FIXED;
            rx_ch_mask   <= 4'h0;
        end 
        else if (capture_cfg) 
        begin
            rx_fixed_64  <= {fixed_patt, fixed_patt};
            rx_test_mode <= cnfg[1:0];
            rx_ch_mask   <= cnfg[7:4];
        end
    end

    // ============================================================
    // TX Pattern Generator
    // ============================================================
    logic [63:0] counter_val;
    logic        toggle_state;

    always @(posedge tx_clk or negedge core_rst_n) 
    begin
        if (!core_rst_n) 
        begin
            counter_val  <= 64'h0;
            toggle_state <= 1'b0;
        end
        else if (tx_enable && !IS_SLAVE) 
        begin
            counter_val  <= (tx_reset_pulse) ? 64'h0 : (counter_val + 1);
            toggle_state <= (tx_reset_pulse) ? 1'b0  : (~toggle_state);
        end            
    end

    // Simple fabric logical loopback register for Slave mode
    logic [63:0] rx_data_r;
    always @(posedge tx_clk or negedge core_rst_n) 
    begin
        if (!core_rst_n) rx_data_r <= 64'h0;
        else             rx_data_r <= rx_data;
    end

    always @(posedge tx_clk or negedge core_rst_n) 
    begin
        if (!core_rst_n) 
        begin
            tx_data <= 64'h0;
        end 
        else if (IS_SLAVE) // Slave acts as a reflector
        begin
            tx_data <= rx_data_r;
        end 
        else /* if (IS_MASTER) */
        begin
            if(tx_test_mode == TEST_MODE_FIXED)        tx_data <= tx_fixed_64;
            else if(tx_test_mode == TEST_MODE_TOGGLE)  tx_data <= toggle_state ? tx_fixed_64 : ~tx_fixed_64;
            else if(tx_test_mode == TEST_MODE_COUNTER) tx_data <= counter_val;
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
    localparam integer ST_IDLE        = 0;
    localparam integer ST_CAPTURE_CFG = 1;
    localparam integer ST_SEARCH      = 2;
    localparam integer ST_LOCKED      = 3;

    reg [3:0] rx_checker_next_state;
    (* keep = "true", mark_debug = "true" *) reg [3:0] rx_checker_curr_state;

    logic        checker_locked;
    logic [63:0] expected_rx;
    
    // Previous data register for robust COUNTER lock
    logic [63:0] rx_data_d;
    always @(posedge rx_clk or negedge core_rst_n) begin
        if (!core_rst_n) rx_data_d <= 64'h0;
        else             rx_data_d <= rx_data;
    end

    wire is_fixed_mode   = (rx_test_mode == TEST_MODE_FIXED);
    wire is_toggle_mode  = (rx_test_mode == TEST_MODE_TOGGLE);
    wire is_counter_mode = (rx_test_mode == TEST_MODE_COUNTER);

    wire match_fixed       = is_fixed_mode   && is_match_by_channel(rx_data, rx_fixed_64, rx_ch_mask);
    wire match_toggle_pos  = is_toggle_mode  && is_match_by_channel(rx_data, rx_fixed_64, rx_ch_mask);
    wire match_toggle_neg  = is_toggle_mode  && is_match_by_channel(rx_data, ~rx_fixed_64, rx_ch_mask);
    wire match_counter     = is_counter_mode && is_match_by_channel(rx_data, rx_data_d + 1, rx_ch_mask);
    wire match_expected    = is_match_by_channel(rx_data, expected_rx, rx_ch_mask);
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
        if (!core_rst_n) rx_checker_curr_state <= ST_IDLE;
        else             rx_checker_curr_state <= rx_checker_next_state;
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
            ST_IDLE: 
            begin
                if (rx_enable && !IS_SLAVE && !rx_reset_pulse) rx_checker_next_state = ST_CAPTURE_CFG;
            end

            ST_CAPTURE_CFG: 
            begin
                if (!rx_enable || rx_reset_pulse) rx_checker_next_state = ST_IDLE;
                else                              rx_checker_next_state = ST_SEARCH;

                capture_cfg = 1'b1;
            end

            ST_SEARCH: 
            begin
                // NOTE: match_any must be evaluated before lock_acquired is checked
                if (match_any) lock_acquired = 1'b1;

                if (!rx_enable || rx_reset_pulse) rx_checker_next_state = ST_IDLE;
                else if (lock_acquired)           rx_checker_next_state = ST_LOCKED;

                if (lock_acquired) begin
                    case (rx_test_mode)
                        TEST_MODE_FIXED:   next_expected_rx = rx_fixed_64;
                        TEST_MODE_TOGGLE:  next_expected_rx = match_toggle_pos ? ~rx_fixed_64 : rx_fixed_64;
                        TEST_MODE_COUNTER: next_expected_rx = rx_data + 1;

                        default:           next_expected_rx = rx_fixed_64;
                    endcase
                end
            end

            ST_LOCKED: 
            begin
                if (!rx_enable || rx_reset_pulse) rx_checker_next_state = ST_IDLE;

                checker_locked  = 1'b1;
                wrd_cnt_inc     = 1'b1;

                if (!match_expected) err_cnt_inc = 1'b1;

                case (rx_test_mode)
                    TEST_MODE_FIXED:   next_expected_rx = rx_fixed_64;
                    TEST_MODE_TOGGLE:  next_expected_rx = ~expected_rx;
                    TEST_MODE_COUNTER: next_expected_rx = err_cnt_inc ? (rx_data + 1) : (expected_rx + 1);
                    
                    default:           next_expected_rx = expected_rx;
                endcase
            end

            default: rx_checker_next_state = ST_IDLE;
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

endmodule
`default_nettype wire
