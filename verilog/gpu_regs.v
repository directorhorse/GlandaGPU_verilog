module gpu_regs (
    input  wire        clk,
    input  wire        reset,
    input  wire [3:0]  bus_addr,
    input  wire        bus_we,
    input  wire [31:0] bus_din,
    output reg  [31:0] bus_dout,
    output wire [9:0]  gpu_x0,
    output wire [9:0]  gpu_y0,
    output wire [9:0]  gpu_x1,
    output wire [9:0]  gpu_y1,
    output wire [11:0] gpu_color,
    output wire [3:0]  gpu_cmd,
    output wire        gpu_start,
    input  wire        gpu_busy,
    input  wire        vga_vsync,
    output wire        irq
);
    reg [31:0] reg_coord0 = 32'b0, reg_coord1 = 32'b0;
    reg [31:0] reg_color = 32'b0, reg_ctrl = 32'b0;
    reg start_pulse = 1'b0;
    reg [31:0] reg_ie = 32'b0, reg_ip = 32'b0;
    reg busy_old = 1'b0, vsync_old = 1'b0;

    always @(posedge clk) begin
        start_pulse <= 1'b0;
        if (reset) begin
            reg_coord0 <= 32'b0;
            reg_coord1 <= 32'b0;
            reg_color  <= 32'b0;
            reg_ctrl   <= 32'b0;
        end else if (bus_we) begin
            case (bus_addr)
                4'h1: begin
                    reg_ctrl <= bus_din;
                    start_pulse <= bus_din[4];
                end
                4'h2: reg_coord0 <= bus_din;
                4'h3: reg_coord1 <= bus_din;
                4'h4: reg_color  <= bus_din;
                default: ;
            endcase
        end
    end

    // Model the synthesized read mux. The VHDL sensitivity list omits
    // start_pulse, reg_ip and reg_ie, so its simulation can show stale data.
    always @* begin
        case (bus_addr)
            4'h0: bus_dout = {30'b0, vga_vsync, (gpu_busy | start_pulse)};
            4'h1: bus_dout = reg_ctrl;
            4'h2: bus_dout = reg_coord0;
            4'h3: bus_dout = reg_coord1;
            4'h4: bus_dout = reg_color;
            4'h5: bus_dout = reg_ip;
            4'h6: bus_dout = reg_ie;
            default: bus_dout = 32'b0;
        endcase
    end

    assign gpu_x0 = reg_coord0[9:0];
    assign gpu_y0 = reg_coord0[25:16];
    assign gpu_x1 = reg_coord1[9:0];
    assign gpu_y1 = reg_coord1[25:16];
    assign gpu_color = reg_color[11:0];
    assign gpu_cmd = reg_ctrl[3:0];
    assign gpu_start = start_pulse;

    always @(posedge clk) begin : interrupt_update
        reg [31:0] ip_next;
        busy_old  <= gpu_busy;
        vsync_old <= vga_vsync;
        if (reset) begin
            reg_ip <= 32'b0;
            reg_ie <= 32'b0;
        end else begin
            ip_next = reg_ip;
            if (bus_we && bus_addr == 4'h5)
                ip_next = ip_next & ~bus_din;
            if (bus_we && bus_addr == 4'h6)
                reg_ie <= bus_din;

            // A new falling-edge event wins over a simultaneous W1C.
            if (busy_old && !gpu_busy)
                ip_next[0] = 1'b1;
            if (vsync_old && !vga_vsync)
                ip_next[1] = 1'b1;
            reg_ip <= ip_next;
        end
    end

    assign irq = |(reg_ip & reg_ie);
endmodule
