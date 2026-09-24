module arrhythmia_classifier (clk,rst_n,sample_en,r_peak_pulse,led_normal,led_tachy,led_brady,led_irregular,buzzer);
input clk,rst_n,sample_en,r_peak_pulse;
output reg led_normal,led_tachy,led_brady,led_irregular;
output buzzer;
reg [15:0] sample_counter,current_rr,previous_rr;
reg [1:0] beat_count; 
wire signed [16:0] rr_diff;
// Clean Edge Detection to capture exactly ONE pulse cycle per heartbeat
reg r_peak_pulse_d1;
wire r_peak_edge = r_peak_pulse && !r_peak_pulse_d1;
assign rr_diff = current_rr - previous_rr;
// Sync Edge Buffer Delay
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_peak_pulse_d1 <= 0;
    end else begin
        r_peak_pulse_d1 <= r_peak_pulse;
    end
end
// Accurate Accumulator stopwatch pipeline
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sample_counter <= 0;
        current_rr     <= 0;
        previous_rr    <= 0;
        beat_count     <= 0;
    end else begin
        if (r_peak_edge) begin 
            if (beat_count < 2'd2) begin
                beat_count  <= beat_count + 1;
                current_rr  <= sample_counter;
                previous_rr <= sample_counter;
            end else begin
                previous_rr <= current_rr;
                current_rr  <= sample_counter;
            end
            sample_counter <= 0; 
        end else if (sample_en) begin
            if (sample_counter < 16'hFFFF) begin
                sample_counter <= sample_counter + 1;
            end
        end
    end
end
// Balanced Priority Decision Gates
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        led_normal    <= 0;
        led_tachy     <= 0;
        led_brady     <= 0;
        led_irregular <= 0;
    end else if (r_peak_edge && beat_count == 2'd2) begin 
        led_normal    <= 0;
        led_tachy     <= 0;
        led_brady     <= 0;
        led_irregular <= 0;
        if (sample_counter < 216) begin
            led_tachy <= 1;
        end 
        else if (sample_counter > 360) begin
            led_brady <= 1;
        end 
        else if ((rr_diff > $signed(previous_rr >>> 3)) || (rr_diff < -$signed(previous_rr >>> 3))) begin 
            led_irregular <= 1;
        end 
        else begin
            led_normal <= 1;
        end
    end
end
assign buzzer = led_tachy || led_brady || led_irregular;
endmodule