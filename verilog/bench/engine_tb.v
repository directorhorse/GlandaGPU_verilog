`timescale 1ns/1ps
// Black-box engine check: sample registered outputs after each rising edge.
module engine_tb;
    reg clk=0, reset=1, start=0;
    reg [3:0] cmd=0;
    reg [9:0] x=0, y=0, w=0, h=0;
    reg [11:0] color=12'hc71;
    wire busy, we;
    wire [18:0] addr;
    wire [11:0] data;
    gpu_engine dut(.clk(clk), .reset(reset), .reg_start(start), .reg_cmd(cmd),
        .reg_x(x), .reg_y(y), .reg_w(w), .reg_h(h), .reg_color(color),
        .busy(busy), .vram_we(we), .vram_addr(addr), .vram_din(data));
    always #5 clk=~clk;
    task tick; begin @(posedge clk); #1; end endtask
    task fail; begin $display("FAIL cmd=%d addr=%d busy=%b we=%b",cmd,addr,busy,we); $finish; end endtask
    task launch; input [3:0] op; begin
        cmd=op; start=1; tick; start=0;
        if ({busy,we} !== 2'b10) fail;
        tick; if ({busy,we} !== 2'b10) fail;
    end endtask
    task pixel; input integer expected; begin
        tick;
        if ({busy,we} !== 2'b11 || addr !== expected[18:0] || data !== color) fail;
    end endtask
    task idle; begin tick; if ({busy,we} !== 2'b00) fail; end endtask
    integer i;
    initial begin
        tick; reset=0;
        launch(1); for (i=0;i<307200;i=i+1) pixel(i); idle;
        // Cross both clipping boundaries; only the first of six pixels is visible.
        x=639; y=479; w=3; h=2; launch(2); pixel(307199);
        repeat(5) begin tick; if ({busy,we} !== 2'b10) fail; end
        idle;
        // Negative steps with an exact error tie on the second pixel.
        x=7; y=4; w=3; h=2; launch(3); repeat(2) tick;
        pixel(4*640+7); pixel(3*640+6); pixel(3*640+5); pixel(2*640+4); pixel(2*640+3); idle;
        launch(15); idle;
        $display("PASS engine"); $finish;
    end
endmodule
