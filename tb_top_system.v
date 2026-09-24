`timescale 1ns / 1ps
module tb_top_system;
reg clk,rst_n,btnc,sw0,sw1;
wire led_normal,led_tachy,led_brady,led_irregular,buzzer;
top_pt_system uut (.clk(clk),.rst_n(rst_n),.btnc(btnc),.sw0(sw0),.sw1(sw1),.led_normal(led_normal),.led_tachy(led_tachy),.led_brady(led_brady),.led_irregular(led_irregular),.buzzer(buzzer));
initial begin
    clk = 1'b0;
    rst_n = 1'b1;
    btnc = 1'b0;
end
always #5 clk = ~clk;
initial begin
    $dumpfile("waveform.vcd");
    $dumpvars(0, tb_top_system);
    $monitor("Time = %0t ns | SW[1:0] = %b%b | Flags [Tachy=%b, Brady=%b, Irreg=%b, Normal=%b] | Buzzer = %b", $time, sw1, sw0, led_tachy, led_brady, led_irregular, led_normal, buzzer);
    rst_n = 1'b0 ; sw1   = 0 ; sw0   = 1 ; #100 ;
    rst_n = 1'b1 ;#801000 ; 
    $display(">>> [EVENT]: Pressing BTNC Center Button to Latch Flags...");
    btnc = 1'b1 ; #200 ; 
    btnc = 1'b0 ; #5000 ;
    $finish;
end
endmodule