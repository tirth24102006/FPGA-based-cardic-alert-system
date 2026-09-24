module pan_tompkins_processor (clk,rst_n,ecg_in,valid_in,mwi_out,valid_out);
input clk,rst_n,valid_in;
input signed [15:0] ecg_in;
output reg signed [31:0] mwi_out;
output reg valid_out;
// Stage 1: Low-Pass Filter
reg signed [15:0] x_d [0:12];
reg signed [15:0] y_lp;
integer i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i=0; i<=12; i=i+1) x_d[i] <= 0;
        y_lp <= 0;
    end else if (valid_in) begin
        for (i=12; i>0; i=i-1) x_d[i] <= x_d[i-1];
        x_d[0] <= ecg_in; // FIXED: Added index [0] instead of whole array assignmentx           
        // FIXED: Added precise indexes for x_d registers
        y_lp <= ecg_in + x_d[0] - (x_d[6] <<< 1) + (y_lp <<< 1) - y_lp; 
    end
end
// Stage 2: Differentiator
reg signed [15:0] lp_d [0:4];
reg signed [18:0] diff_out;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i=0; i<=4; i=i+1) lp_d[i] <= 0;
        diff_out <= 0;
    end else if (valid_in) begin
        for (i=4; i>0; i=i-1) lp_d[i] <= lp_d[i-1];
        lp_d[0] <= y_lp; // FIXED: Added index [0] instead of whole array assignment           
        // FIXED: Added precise indexes for lp_d registers
        diff_out <= ((y_lp <<< 1) + lp_d[1] - lp_d[3] - (lp_d[4] <<< 1)) >>> 3;
    end
end
// Stage 3: Nonlinear Squaring
reg signed [37:0] squared_out;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) squared_out <= 0;
    else if (valid_in) squared_out <= diff_out * diff_out;
end
// Stage 4: Moving Window Integrator
reg signed [31:0] delay_line [0:29];
reg signed [31:0] accumulator;
integer j;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        accumulator <= 0;
        for (j=0; j<30; j=j+1) delay_line[j] <= 0;
        mwi_out <= 0;
        valid_out <= 0;
    end else if (valid_in) begin
        // FIXED: Subtracted the oldest element from the end of the line (delay_line[29])
        accumulator <= accumulator + squared_out[31:0] - delay_line[29];           
        for (j=29; j>0; j=j-1) delay_line[j] <= delay_line[j-1];
        delay_line[0] <= squared_out[31:0]; // FIXED: Added index [0] instead of whole array assignment 
        mwi_out <= accumulator / 30;
        valid_out <= 1;
    end else begin
        valid_out <= 0;
    end
end
endmodule