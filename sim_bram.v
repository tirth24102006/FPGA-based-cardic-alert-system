module sim_bram (clk,addr,dout);
input clk;
input [11:0] addr;
output reg [15:0] dout;
reg [15:0] ram [0:2743]; 
initial begin
    $readmemh("mit_data_101.mem", ram);
end
always @(posedge clk) begin
    dout <= ram[addr];
end
endmodule
