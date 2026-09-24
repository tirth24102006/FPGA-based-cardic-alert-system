module adaptive_threshold (clk,rst_n,mwi_in,valid_in,r_peak_pulse);
input clk,rst_n,valid_in;
input signed [31:0] mwi_in;
output reg r_peak_pulse;
reg [31:0] spki,npki,threshold_i1;
reg [7:0] refractory_cnt;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        spki         <= 32'h00004000; 
        npki         <= 32'h00000400;
        threshold_i1 <= 32'h00001000;
        refractory_cnt <= 0;
        r_peak_pulse   <= 0;
    end else if (valid_in) begin
        r_peak_pulse <= 0;
        if (refractory_cnt > 0) begin
            refractory_cnt <= refractory_cnt - 1;
        end
        if (mwi_in > threshold_i1 && refractory_cnt == 0) begin
            r_peak_pulse <= 1;
            refractory_cnt <= 72; 
            spki <= (spki - (spki >>> 3)) + (mwi_in >>> 3); 
        end else if (mwi_in < threshold_i1) begin
            npki <= (npki - (npki >>> 3)) + (mwi_in >>> 3);
        end
        threshold_i1 <= npki + ((spki - npki) >>> 2);
    end
end
endmodule