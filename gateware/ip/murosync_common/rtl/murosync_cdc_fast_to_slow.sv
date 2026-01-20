/******************************************************************************
 * Project    : MuroSync
 * File       : murosync_cdc_fast_to_slow.sv
 * Created    : 2026-01-20
 * Author     : Mikhail Vasilev
 *
 * Description:
 *   Clock-domain crossing helper: fast-to-slow pulse transfer.
 *
 *   Transfers a single-cycle event from a fast clock domain (clk_a) into
 *   a slower clock domain (clk_b) using a toggle-based CDC scheme with
 *   multi-stage synchronization and edge detection.
 *
 *   Guarantees exactly one clk_b-cycle pulse per input event, independent
 *   of relative clock frequencies (assuming clk_b is slower than clk_a).
 *
 * Notes:
 *   - Uses toggle + synchronizer + XOR edge detect pattern.
 *   - SYNC_STAGES >= 2 required for safe CDC operation.
 *   - Suitable for interrupts, control pulses, and event notifications.
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

module murosync_cdc_fast_to_slow #(
    parameter int SYNC_STAGES = 5   // >=2 recommended
)(
    // Fast domain
    input  wire clk_a,
    input  wire rst_a_n,
    input  wire in_a,        // pulse in clk_a domain

    // Slow domain
    input  wire clk_b,
    input  wire rst_b_n,
    output wire out_b        // single-cycle pulse in clk_b domain
);

    // --------------------------------------------------------
    // Toggle in fast domain
    // --------------------------------------------------------
    logic tog_a;

    always @(posedge clk_a or negedge rst_a_n) 
    begin
        if (!rst_a_n)  tog_a <= 1'b0;
        else if (in_a) tog_a <= ~tog_a;
    end

    // --------------------------------------------------------
    // Synchronize toggle into slow domain
    // --------------------------------------------------------
    (* ASYNC_REG = "TRUE" *)
    logic [SYNC_STAGES-1:0] tog_sync;

    always @(posedge clk_b or negedge rst_b_n) 
    begin
        if (!rst_b_n) tog_sync <= '0;
        else          tog_sync <= {tog_sync[SYNC_STAGES-2:0], tog_a};
    end

    // --------------------------------------------------------
    // Edge detect (toggle change => pulse)
    // --------------------------------------------------------
    assign out_b = tog_sync[SYNC_STAGES-1] ^ tog_sync[SYNC_STAGES-2];

endmodule