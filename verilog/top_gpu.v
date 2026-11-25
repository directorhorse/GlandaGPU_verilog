module top_gpu (
    input  wire        clk,
    input  wire        reset,
    input  wire [21:0] avs_address,
    input  wire        avs_write,
    input  wire [31:0] avs_writedata,
    input  wire        avs_read,
    output wire [31:0] avs_readdata,
    output wire        avs_waitrequest,
    output wire        hsync,
    output wire        vsync,
    output wire        video_on,
    output wire [3:0]  red,
    output wire [3:0]  green,
    output wire [3:0]  blue,
    output wire        irq
);
    wire [18:0] vram_addr_vga, gpu_addr;
    wire [11:0] vram_data_vga, gpu_din, vram_dout_cpu;
    wire gpu_we, gpu_busy;

    wire [31:0] reg_dout;
    wire [3:0] reg_cmd;
    wire [9:0] reg_x, reg_y, reg_w, reg_h;
    wire [11:0] reg_color;
    wire reg_start;

    // Avalon uses word addresses. Bit 19 selects registers (byte offset 0x200000).
    wire reg_cs = avs_address[19];
    wire bus_we_reg = reg_cs && avs_write;
    wire cpu_we_vram = !reg_cs && !gpu_busy && avs_write;
    wire [18:0] cpu_addr_vram = avs_address[18:0];
    wire [11:0] cpu_din_vram = avs_writedata[11:0];
    assign avs_waitrequest = !reg_cs && gpu_busy && (avs_read || avs_write);
    assign avs_readdata = reg_cs ? reg_dout : {20'b0, vram_dout_cpu};

    // While busy the engine owns port A; VGA always reads independently on B.
    wire mux_we_a = gpu_busy ? gpu_we : cpu_we_vram;
    wire [18:0] mux_addr_a = gpu_busy ? gpu_addr : cpu_addr_vram;
    wire [11:0] mux_din_a = gpu_busy ? gpu_din : cpu_din_vram;
    wire vsync_internal, hsync_internal, video_on_internal;

    vram vram_inst (
        .clk(clk), .we_a(mux_we_a), .addr_a(mux_addr_a), .din_a(mux_din_a),
        .dout_a(vram_dout_cpu), .addr_b(vram_addr_vga), .dout_b(vram_data_vga)
    );

    gpu_regs gpu_regs_inst (
        .clk(clk), .reset(reset), .bus_addr(avs_address[3:0]), .bus_we(bus_we_reg),
        .bus_din(avs_writedata), .bus_dout(reg_dout),
        .gpu_x0(reg_x), .gpu_y0(reg_y), .gpu_x1(reg_w), .gpu_y1(reg_h),
        .gpu_color(reg_color), .gpu_cmd(reg_cmd), .gpu_start(reg_start),
        .gpu_busy(gpu_busy), .vga_vsync(vsync_internal), .irq(irq)
    );

    gpu_engine engine_inst (
        .clk(clk), .reset(reset), .reg_cmd(reg_cmd), .reg_x(reg_x), .reg_y(reg_y),
        .reg_w(reg_w), .reg_h(reg_h), .reg_color(reg_color), .reg_start(reg_start),
        .busy(gpu_busy), .vram_we(gpu_we), .vram_addr(gpu_addr), .vram_din(gpu_din)
    );

    vga_controller vga_inst (
        .clk(clk), .reset(reset), .pixel_data(vram_data_vga), .pixel_addr(vram_addr_vga),
        .hsync(hsync_internal), .vsync(vsync_internal), .video_on(video_on_internal),
        .red(red), .green(green), .blue(blue)
    );

    assign hsync = hsync_internal;
    assign vsync = vsync_internal;
    assign video_on = video_on_internal;
endmodule
