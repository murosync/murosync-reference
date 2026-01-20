// ------------------------------------------------------------
// murosync_cdc_slow_to_fast.sv
//
// Level-to-pulse CDC from slow domain into fast domain.
// Produces a single-cycle pulse in clk domain on rising edge
// of 'in'.
// ------------------------------------------------------------

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
