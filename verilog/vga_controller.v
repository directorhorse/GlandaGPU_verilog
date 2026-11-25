module vga_controller (
    input  wire        clk,
    input  wire        reset,
    input  wire [11:0] pixel_data,
    output wire [18:0] pixel_addr,
    output wire        hsync,
    output wire        vsync,
    output wire        video_on,
    output reg  [3:0]  red,
    output reg  [3:0]  green,
    output reg  [3:0]  blue
);
    localparam H_ACTIVE = 640, H_FP = 16, H_SYNC = 96, H_BP = 48;
    localparam V_ACTIVE = 480, V_FP = 10, V_SYNC = 2, V_BP = 33;
    localparam H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;
    localparam V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;

    reg [9:0] h_cnt = 0, v_cnt = 0;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            h_cnt <= 0;
            v_cnt <= 0;
        end else if (h_cnt == H_TOTAL - 1) begin
            h_cnt <= 0;
            if (v_cnt == V_TOTAL - 1)
                v_cnt <= 0;
            else
                v_cnt <= v_cnt + 1'b1;
        end else begin
            h_cnt <= h_cnt + 1'b1;
        end
    end

    wire hsync_i = !(h_cnt >= H_ACTIVE + H_FP && h_cnt < H_ACTIVE + H_FP + H_SYNC);
    wire vsync_i = !(v_cnt >= V_ACTIVE + V_FP && v_cnt < V_ACTIVE + V_FP + V_SYNC);
    wire video_on_i = h_cnt < H_ACTIVE && v_cnt < V_ACTIVE;
    assign pixel_addr = video_on_i ? v_cnt * 19'd640 + h_cnt : 19'd0;

    // Sync and blanking follow the synchronous VRAM read, then the RGB register.
    // Reset affects the counters only; the pipeline continues to clock during reset.
    reg hsync_v1 = 1'b1, hsync_v2 = 1'b1;
    reg vsync_v1 = 1'b1, vsync_v2 = 1'b1;
    reg video_on_v1 = 1'b0, video_on_v2 = 1'b0;
    always @(posedge clk) begin
        hsync_v1 <= hsync_i;
        vsync_v1 <= vsync_i;
        video_on_v1 <= video_on_i;
        hsync_v2 <= hsync_v1;
        vsync_v2 <= vsync_v1;
        video_on_v2 <= video_on_v1;

        if (video_on_v1)
            {red, green, blue} <= pixel_data;
        else
            {red, green, blue} <= 12'h000;
    end

    assign hsync = hsync_v2;
    assign vsync = vsync_v2;
    assign video_on = video_on_v2;
endmodule
