`timescale 1ns/1ps
module diff_tb;
  reg clk=0, reset=0, wr=0, rd=0;
  reg [21:0] addr=0;
  reg [31:0] wd=0;
  wire [31:0] q;
  wire stall, hs, vs, active, irq;
  wire [3:0] r,g,b;
  top_gpu dut (.clk(clk), .reset(reset), .avs_address(addr), .avs_write(wr),
    .avs_writedata(wd), .avs_read(rd), .avs_readdata(q), .avs_waitrequest(stall),
    .hsync(hs), .vsync(vs), .video_on(active), .red(r), .green(g), .blue(b), .irq(irq));
  integer vec, trace, n, count, cycle=0;
  reg pre_wait;
  reg [48:0] sample, prev;
  initial begin
    vec=$fopen("vectors.txt","r"); trace=$fopen("verilog.trace","w");
    if (!vec || !trace) $fatal(1,"could not open vector/trace file");
    count=$fscanf(vec,"%d %d %d %d %d %h",n,reset,wr,rd,addr,wd);
    while (count==6) begin
      repeat(n) begin
        #5; pre_wait=stall; clk=1; #1;
        sample={pre_wait,irq,hs,vs,active,r,g,b,(rd && !pre_wait ? q : 32'b0)};
        if (!cycle || sample !== prev) $fdisplay(trace,"%0d %b",cycle,sample);
        prev=sample; cycle=cycle+1; #4; clk=0;
      end
      count=$fscanf(vec,"%d %d %d %d %d %h",n,reset,wr,rd,addr,wd);
    end
    if (!$feof(vec)) $fatal(1,"malformed vectors");
    $fdisplay(trace,"%0d END",cycle); $fclose(trace); $finish;
  end
endmodule
