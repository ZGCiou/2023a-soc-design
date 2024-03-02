//############################################################################
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//  2023 SOCLAB Autumu Course
//  Final Project   : Caravel SOC Workload Optimization 
//  Author          : Zheng-Gang Ciou (nycu311511022.ee11@nycu.edu.tw)
//
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//  File Name       : FIFO.v
//  Module Name     : FIFO
//  Release version : V1.0 (Release Date: 2024.1.8)
//
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//############################################################################
module FIFO #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 2
) (
    input clk,
    input rst_n,
    // Write
    input we,
    input [DATA_WIDTH-1:0] wdata,
    output wfull,
    // Read
    input re,
    output rempty,
    output [DATA_WIDTH-1:0] rdata
);
//=====================================================================
//   LOGIC DECLARATION
//=====================================================================
integer i;
reg [DATA_WIDTH-1:0] fifomem[2**ADDR_WIDTH-1:0];
reg [ADDR_WIDTH:0] wptr, rptr;
wire [ADDR_WIDTH-1:0] waddr, raddr;

//=====================================================================
//   DATA PATH & CONTROL
//=====================================================================
assign waddr = wptr[ADDR_WIDTH-1:0];
assign raddr = rptr[ADDR_WIDTH-1:0];
assign rempty = (wptr == rptr);
assign wfull = (wptr[ADDR_WIDTH] != rptr[ADDR_WIDTH]) & (waddr == raddr);

// MDA (for waveform observe)
generate
  genvar idx;
  for(idx = 0; idx < 2**ADDR_WIDTH; idx = idx+1) begin: mem
    wire [DATA_WIDTH-1:0] data;
    assign data = fifomem[idx];
  end
endgenerate

// Write
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        wptr <= 'd0;
        for (i=0; i<2**ADDR_WIDTH; i=i+1) begin
            fifomem[i] <= 'd0;
        end
    end else begin
        if ((~wfull | re) & we) begin
            wptr <= wptr + 1'b1;
            fifomem[waddr] <= wdata;
        end
    end
end

// Read
assign rdata = fifomem[raddr];
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        rptr <= 'd0;
    end else begin
        if (~rempty & re) begin
            rptr <= rptr + 1'b1;
        end
    end
end

endmodule

