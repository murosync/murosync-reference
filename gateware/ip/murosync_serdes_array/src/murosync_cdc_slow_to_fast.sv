/******************************************************************************
 * Project    : MuroSync
 * File       : murosync_cdc_slow_to_fast.sv
 * Created    : 2026-01-20
 * Author     : Mikhail Vasilev
 *
 * Description:
 *   Clock-domain crossing helper: slow-to-fast pulse generator.
 *
 *   Synchronizes a level signal from a slow or asynchronous domain into the
 *   target clock domain and generates a single-cycle pulse on the rising edge
 *   of the input level. Intended for control and W1P-style signals.
 *
 *   Uses a multi-stage synchronizer for metastability reduction, followed by
 *   edge detection in the destination clock domain.
 *
 * Notes:
 *   - SYNC_STAGES >= 2 is required; >= 3 is recommended.
 *   - Reset is active-low and synchronous to the destination clock.
 *   - Output pulse is one clk cycle wide.
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

module murosync_cdc_slow_to_fast #(
    parameter int SYNC_STAGES = 3   // >=2 recommended
)(
    input  wire clk,
    input  wire rst_n,

    input  wire in,        // level in slow domain
    output wire out        // pulse in clk domain
);

    (* ASYNC_REG = "TRUE" *)
    logic [SYNC_STAGES-1:0] sync_reg;

    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) sync_reg <= '0;
        else        sync_reg <= {sync_reg[SYNC_STAGES-2:0], in};
    end

    // Rising-edge detect after synchronization
    assign out = sync_reg[SYNC_STAGES-1] & ~sync_reg[SYNC_STAGES-2];

endmodule
