// Pixel drawing engine. All command sequencing and VRAM outputs are clocked.
module gpu_engine (
    input  wire        clk,
    input  wire        reset,
    input  wire [3:0]  reg_cmd,
    input  wire [9:0]  reg_x, reg_y, reg_w, reg_h,
    input  wire [11:0] reg_color,
    input  wire        reg_start,
    output reg         busy,
    output reg         vram_we,
    output reg  [18:0] vram_addr,
    output reg  [11:0] vram_din
);
    localparam [2:0] IDLE = 3'd0, FETCH_CMD = 3'd1, STATE_CLEAR = 3'd2,
                     STATE_RECT = 3'd3, STATE_LINE_INIT = 3'd4,
                     STATE_LINE_PREP = 3'd5, STATE_LINE_DRAW = 3'd6;
    reg [2:0] state = IDLE;
    reg [18:0] clear_addr;
    reg [9:0] curr_x, curr_y;
    reg signed [11:0] x0 = 0, y0 = 0, x1 = 0, y1 = 0;
    reg signed [11:0] dx = 0, dy = 0, err = 0, sx = 0, sy = 0;

    // The original clips using 10-bit sums, but computes the address using
    // unwrapped coordinates. Its 10-bit size-minus-one wraps for zero size.
    wire [10:0] rect_x = {1'b0, reg_x} + {1'b0, curr_x};
    wire [10:0] rect_y = {1'b0, reg_y} + {1'b0, curr_y};
    wire [9:0] last_x = reg_w - 10'd1;
    wire [9:0] last_y = reg_h - 10'd1;

    // Both decisions use the original doubled error, truncated to 12 bits.
    wire signed [11:0] e2 = err + err;
    wire step_x = e2 >= dy;
    wire step_y = e2 <= dx;
    wire signed [11:0] err_after_x = step_x ? err + dy : err;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            busy <= 1'b0;
            vram_we <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    busy <= 1'b0;
                    vram_we <= 1'b0;
                    if (reg_start) begin
                        busy <= 1'b1;
                        state <= FETCH_CMD;
                    end
                end
                FETCH_CMD: begin
                    case (reg_cmd)
                        4'h1: begin
                            clear_addr <= 19'd0;
                            state <= STATE_CLEAR;
                        end
                        4'h2: begin
                            curr_x <= 10'd0;
                            curr_y <= 10'd0;
                            state <= STATE_RECT;
                        end
                        4'h3: begin
                            x0 <= {2'b00, reg_x};
                            y0 <= {2'b00, reg_y};
                            x1 <= {2'b00, reg_w};
                            y1 <= {2'b00, reg_h};
                            state <= STATE_LINE_INIT;
                        end
                        default: state <= IDLE;
                    endcase
                end
                STATE_CLEAR: begin
                    vram_we <= 1'b1;
                    vram_addr <= clear_addr;
                    vram_din <= reg_color;
                    if (clear_addr < 19'd307199)
                        clear_addr <= clear_addr + 19'd1;
                    else state <= IDLE;
                end
                STATE_RECT: begin
                    if (rect_y[9:0] < 10'd480 && rect_x[9:0] < 10'd640) begin
                        vram_we <= 1'b1;
                        vram_addr <= rect_y * 19'd640 + rect_x;
                        vram_din <= reg_color;
                    end else vram_we <= 1'b0;

                    if (curr_x < last_x) curr_x <= curr_x + 10'd1;
                    else begin
                        curr_x <= 10'd0;
                        if (curr_y < last_y) curr_y <= curr_y + 10'd1;
                        else state <= IDLE;
                    end
                end
                STATE_LINE_INIT: begin
                    dx <= (x0 < x1) ? x1 - x0 : x0 - x1;
                    dy <= (y0 < y1) ? y0 - y1 : y1 - y0;
                    sx <= (x0 < x1) ? 12'sd1 : -12'sd1;
                    sy <= (y0 < y1) ? 12'sd1 : -12'sd1;
                    state <= STATE_LINE_PREP;
                end
                STATE_LINE_PREP: begin
                    err <= dx + dy;
                    state <= STATE_LINE_DRAW;
                end
                STATE_LINE_DRAW: begin
                    if (x0 >= 12'sd0 && x0 < 12'sd640 &&
                        y0 >= 12'sd0 && y0 < 12'sd480) begin
                        vram_we <= 1'b1;
                        vram_addr <= y0 * 19'sd640 + x0;
                        vram_din <= reg_color;
                    end else vram_we <= 1'b0;

                    if (x0 == x1 && y0 == y1) state <= IDLE;
                    else begin
                        if (step_x) x0 <= x0 + sx;
                        if (step_y) y0 <= y0 + sy;
                        err <= step_y ? err_after_x + dx : err_after_x;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
