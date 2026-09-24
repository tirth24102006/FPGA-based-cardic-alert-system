module top_pt_system (clk,rst_n,btnc,sw0,sw1,led_normal,led_tachy,led_brady,led_irregular,buzzer);
input clk,rst_n,btnc,sw0,sw1;
output reg led_normal,led_tachy,led_brady,led_irregular; 
output buzzer;
reg sample_en;
`ifdef SIMULATION
    reg [1:0] sim_clk_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sim_clk_cnt <= 0;
            sample_en   <= 0;
        end else if (sim_clk_cnt == 2'd3) begin
            sim_clk_cnt <= 0;
            sample_en   <= 1'b1;
        end else begin
            sim_clk_cnt <= sim_clk_cnt + 1;
            sample_en   <= 1'b0;
        end
    end
`else
    reg [18:0] clk_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_cnt   <= 0;
            sample_en <= 0;
        end else if (clk_cnt == 277777) begin
            clk_cnt   <= 0;
            sample_en <= 1'b1;
        end else begin
            clk_cnt   <= clk_cnt + 1;
            sample_en <= 1'b0;
        end
    end
`endif
wire [1:0] current_mode = {sw1, sw0};
reg [11:0] base_address; 
always @(*) begin
    case(current_mode)
        2'b00: base_address = 12'd0;    // Quad 0: Tachy
        2'b01: base_address = 12'd686;  // Quad 1: Brady
        2'b10: base_address = 12'd1372; // Quad 2: Irregular
        2'b11: base_address = 12'd2058; // Quad 3: Normal
        default: base_address = 12'd0;
    endcase
end
reg [9:0] inner_counter;
wire [11:0] rom_addr = base_address + inner_counter;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        inner_counter <= 0;
    end else if (sample_en) begin
        if (inner_counter == 685)  
            inner_counter <= 0;
        else 
            inner_counter <= inner_counter + 1;
    end
end
wire [15:0] ecg_from_rom;
wire [31:0] mwi_to_threshold;
wire valid_mwi,r_peak_detected,w_normal, w_tachy, w_brady, w_irregular;
reg sample_en_d1;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) sample_en_d1 <= 0;
    else        sample_en_d1 <= sample_en;
end
sim_bram design_rom (.clk(clk),.addr(rom_addr),.dout(ecg_from_rom));
pan_tompkins_processor processor_core (.clk(clk),.rst_n(rst_n),.ecg_in(ecg_from_rom),.valid_in(sample_en_d1),.mwi_out(mwi_to_threshold),.valid_out(valid_mwi));
adaptive_threshold peak_detector (.clk(clk),.rst_n(rst_n),.mwi_in(mwi_to_threshold),.valid_in(valid_mwi),.r_peak_pulse(r_peak_detected));
arrhythmia_classifier classifier_core (.clk(clk),.rst_n(rst_n),.sample_en(sample_en),.r_peak_pulse(r_peak_detected),.led_normal(w_normal),.led_tachy(w_tachy),.led_brady(w_brady),.led_irregular(w_irregular),.buzzer(buzzer));
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        led_normal    <= 0;
        led_tachy     <= 0;
        led_brady     <= 0;
        led_irregular <= 0;
    end else if (btnc) begin
        led_normal    <= w_normal;
        led_tachy     <= w_tachy;
        led_brady     <= w_brady;
        led_irregular <= w_irregular;
    end
end
endmodule