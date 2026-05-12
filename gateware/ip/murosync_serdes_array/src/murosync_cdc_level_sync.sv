/******************************************************************************
 * Project    : MuroSync
 * File       : murosync_cdc_level_sync.sv
 * Created    : 2026-05-12
 * Author     : Mikhail Vasilev
 *
 * Description:
 *   Clock-domain crossing helper: multi-stage level synchronizer.
 *
 *   Synchronizes a level (not pulse) signal bus from one clock domain into
 *   another using a chain of flip-flops. Output follows input with a
 *   latency of SYNC_STAGES clock cycles in the destination domain.
 *
 *   Suitable for: status bits, FSM state bits, flag signals, and any
 *   slowly-changing level bus that must cross a clock domain boundary.
 *
 * Notes:
 *   - Output is a synchronized level, NOT a pulse (no edge detection).
 *   - SYNC_STAGES >= 2 required for safe CDC operation.
 *   - WIDTH >= 1. For multi-bit buses: bits are NOT coherent with each
 *     other — use only for grey-coded or single-bit signals if coherence
 *     is required.
 *   - Suitable for both fast-to-slow and slow-to-fast level crossing.
 *
 * Copyright (c) 2026 Mikhail Vasilev / MuroSync
 *
 * License:
 *   Restricted research license.
 *   Commercial use requires an explicit license agreement.
 *
 * Contact:
 *   info@murosync.com
 *
 *****************************************************************************/

module murosync_cdc_level_sync #(
    parameter int WIDTH       = 1,  // bus width (bits not coherent for WIDTH>1)
    parameter int SYNC_STAGES = 2   // >=2 required
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire [WIDTH-1:0]  in,    // level signal(s) from source domain
    output wire [WIDTH-1:0]  out    // synchronized level(s) in destination domain
);

    (* ASYNC_REG = "TRUE" *)
    logic [SYNC_STAGES-1:0] sync_reg [WIDTH-1:0];

    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : g_sync
            always @(posedge clk or negedge rst_n)
            begin
                if (!rst_n) sync_reg[i] <= '0;
                else        sync_reg[i] <= {sync_reg[i][SYNC_STAGES-2:0], in[i]};
            end
            assign out[i] = sync_reg[i][SYNC_STAGES-1];
        end
    endgenerate

endmodule