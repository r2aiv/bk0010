// ====================================================================
//                         VECTOR-06C FPGA REPLICA
//
//              Copyright (C) 2007,2008 Viacheslav Slavinsky
//
// This core is distributed under modified BSD license. 
// For complete licensing information see LICENSE.TXT.
// -------------------------------------------------------------------- 
//
// An open implementation of Vector-06C home computer
//
// Author: Viacheslav Slavinsky, http://sensi.org/~svo
// 
// Design File: soundcodec.v
//
// Audio interface between raw audio pulses from 8253, tape i/o and
// sound codec. Includes simple moving average filter for all but
// tape signals.
//
// --------------------------------------------------------------------

`default_nettype none

`define NOADAPTIVE_TAPE_LEVEL

module soundcodec(clk18, pulses, pcm, tapein, reset_n, oAUD_XCK, oAUD_BCK, oAUD_DATA, oAUD_LRCK, iAUD_ADCDAT, oAUD_ADCLRCK);
input   clk18;
input   [3:0] pulses;
input   [7:0] pcm;
output  tapein;
input   reset_n;
output  oAUD_XCK = clk18;
output  oAUD_BCK;
output  oAUD_DATA;
output  oAUD_LRCK;
input   iAUD_ADCDAT;
output  oAUD_ADCLRCK;

reg [7:0] decimator;
always @(posedge clk18) decimator <= decimator + 1'd1;

wire ma_ce = decimator == 0;


wire [15:0] linein;         // comes from codec
reg [15:0] ma_pulse;        // goes to codec

reg [7:0] pulses_sample[0:3];

// sample * 16
wire [5:0] m04 = {pulses[0], 4'b0};
wire [5:0] m14 = {pulses[1], 4'b0};
wire [5:0] m24 = {pulses[2], 4'b0};
wire [5:0] m34 = {pulses[3], 4'b0};

reg [7:0] sum;

always @(posedge clk18) begin
    if (ma_ce) begin
        pulses_sample[3] <= pulses_sample[2];
        pulses_sample[2] <= pulses_sample[1];
        pulses_sample[1] <= pulses_sample[0];
        pulses_sample[0] <= m04 + m14 + m24/* + m34*/;
        sum <= pulses_sample[0] + pulses_sample[1] + pulses_sample[2] + pulses_sample[3];
    end

    ma_pulse <= {sum[7:2], 7'b0} + {m34,10'b0} + {pcm,5'b0};
    
end

audio_io audioio(oAUD_BCK, oAUD_DATA, oAUD_LRCK, iAUD_ADCDAT, oAUD_ADCLRCK, clk18, reset_n, ma_pulse, linein);      

reg [15:0] level_avg;
reg [7:0] lowest;
reg [7:0] highest;
reg [7:0] abs_low;
reg [7:0] abs_high;

wire [7:0] line8in = linein[15:8];

// a really slow counter to adjust min/max envelopes
reg [15:0] slowcount;
always @(posedge oAUD_LRCK) begin
    slowcount <= slowcount + 1'd1;
end

wire [15:0] acc_plus = level_avg + line8in;

wire [7:0] h_l_diff = abs_high - abs_low;

reg [7:0] the_middle;

`ifdef ADAPTIVE_TAPE_LEVEL  
always @(negedge oAUD_LRCK or negedge reset_n) begin
    if (!reset_n) begin
        abs_low <= 127;
        abs_high <= 128;
        level_avg <= 127;
    end else begin
        if (line8in < abs_low)  abs_low <= line8in;
        if (line8in > abs_high) abs_high <= line8in;
        
        if (slowcount == 0 && abs_low < level_avg) abs_low <= abs_low + 1'd1;
        if (slowcount == 0 && abs_high > level_avg) abs_high <= abs_high - 1'd1;
        
        level_avg <= acc_plus[15:1];
        
        the_middle <= abs_low + h_l_diff[7:1];
    end
end
`else
always @(negedge reset_n) begin
    the_middle <= 128;
end
`endif


assign tapein = line8in > the_middle;

endmodule

// $Id: soundcodec.v 207 2008-01-17 18:15:02Z svofski $