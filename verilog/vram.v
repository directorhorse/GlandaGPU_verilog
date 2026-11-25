module vram #(
    parameter integer ADDR_WIDTH = 19,
    parameter integer DATA_WIDTH = 12
) (
    input  wire                  clk,
    input  wire                  we_a,
    input  wire [ADDR_WIDTH-1:0] addr_a,
    input  wire [DATA_WIDTH-1:0] din_a,
    output reg  [DATA_WIDTH-1:0] dout_a,
    input  wire [ADDR_WIDTH-1:0] addr_b,
    output reg  [DATA_WIDTH-1:0] dout_b
);
    localparam integer RAM_DEPTH = 307200;  // 640 x 480
    (* ramstyle = "M10K, no_rw_check" *) reg [DATA_WIDTH-1:0] ram [0:RAM_DEPTH-1];

    // Addresses outside the framebuffer alias word zero on both ports.
    wire [ADDR_WIDTH-1:0] index_a = (addr_a >= RAM_DEPTH) ? {ADDR_WIDTH{1'b0}} : addr_a;
    wire [ADDR_WIDTH-1:0] index_b = (addr_b >= RAM_DEPTH) ? {ADDR_WIDTH{1'b0}} : addr_b;

    // Both registered outputs sample the pre-write contents on this edge.
    always @(posedge clk) begin
        if (we_a)
            ram[index_a] <= din_a;
        dout_a <= ram[index_a];
        dout_b <= ram[index_b];
    end
endmodule
