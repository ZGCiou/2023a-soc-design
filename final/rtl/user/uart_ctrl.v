module ctrl(
    input wire        rst_n,
    input wire        clk,
    input wire        i_wb_valid,
    input wire [31:0] i_wb_adr,
    input wire        i_wb_we,
    input wire [31:0] i_wb_dat,
    input wire [3:0]  i_wb_sel,
    output reg        o_wb_ack,
    output reg [31:0] o_wb_dat,
    input wire [7:0]  i_rx,
    input wire        i_rx_valid,
    input wire        i_rx_finish,
    output reg        o_irq,
    input wire        i_rx_busy,
    input wire        i_frame_err,
    output wire       o_rx_fifofull,
    output reg [7:0]  o_tx,
    input wire        i_tx_finish,
    input wire        i_tx_busy,
    output wire       o_tx_start
);

// Declare the UART memory mapped registers address
localparam RX_DATA  = 32'h3000_0000;
localparam TX_DATA	= 32'h3000_0004;
localparam STAT_REG = 32'h3000_0008;

//+------+-------+-------+-------+-------+-------+-------+-------+-------+-------+-------+
//|RX_DATA |     RX_Data_3     |     RX_Data_2     |     RX_Data_1    |     RX_Data_0    |
//|        |       31-24       |       23-16       |       15-8       |        7-0       |
//+------+-------+-------+-------+-------+-------+-------+-------+-------+-------+-------+
//|TX_DATA |     TX_Data_3     |     TX_Data_2     |     TX_Data_1    |     TX_Data_0    |
//|        |       31-24       |       23-16       |       15-8       |        7-0       |
//+------+-------+-------+-------+-------+-------+-------+-------+-------+-------+-------+-------+-------+-
//|STAT_REG| RESERVERD | Tx_fifo_full | Frame Err | Overrun Err | Tx_full | Tx_empty | Rx_full | Rx_empty |
//|        |    31-7   |      6       |     5     |      4      |    3    |     2    |    1    |     0    |
//+------+-------+-------+-------+-------+-------+-------+-------+-------+-------+-------+-------+-------+-

//=====================================================================
//   LOGIC DECLARATION
//=====================================================================
wire [31:0] rx_buffer;
reg [7:0] tx_buffer;
reg [31:0] stat_reg;
reg tx_start_local;
wire tx_run;
wire [3:0] rx_fifo_wfull, rx_fifo_re, rx_fifo_rempty;
reg [3:0] rx_fifo_we;
wire [7:0] rx_fifo_rdata[3:0];
wire [3:0] tx_fifo_wfull, tx_fifo_re, tx_fifo_rempty;
reg [3:0] tx_fifo_we;
wire [7:0] tx_fifo_wdata[3:0], tx_fifo_rdata[3:0];
reg [1:0] rx_index, tx_index;

`define rx_empty stat_reg[0]
`define rx_full stat_reg[1]
`define tx_empty stat_reg[2]
`define tx_full stat_reg[3]
`define overrun_err stat_reg[4]
`define frame_err stat_reg[5]

//=====================================================================
//   DATA PATH & CONTROL
//=====================================================================
// Stage register
always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        stat_reg <= 32'h0000_0005;
    end else begin
        if(i_wb_valid && !i_wb_we)begin
            if(i_wb_adr==STAT_REG)
                stat_reg[5:4] <= 2'b00;
        end

        if(i_tx_busy)
            stat_reg[3:2] <= 2'b10;
        else
            stat_reg[3:2] <= 2'b01;

        if (&tx_fifo_wfull)
            stat_reg[6] <= 1'b1;
        else
            stat_reg[6] <= 1'b0;
            
        if(i_frame_err && i_rx_busy)
            stat_reg[5] <= 1'b1;
        else if(i_rx_finish && !stat_reg[1] && !i_frame_err)
            stat_reg[1:0] <= 2'b10;
        else if(i_rx_busy && stat_reg[1:0]==2'b10)
            stat_reg[4] <= 1'b1;
        else if((i_wb_valid && i_wb_adr==RX_DATA && !i_wb_we && stat_reg[1:0]==2'b10) || i_frame_err)
            stat_reg[1:0] <= 2'b01;
    end
end

// Rx
// rx_fifo
generate
    genvar i;
    for (i=0; i<4; i=i+1) begin : RX
        FIFO #(
            .DATA_WIDTH(8),
            .ADDR_WIDTH(4)
        ) rx_fifo (
            .clk    (clk),
            .rst_n  (rst_n),
            .we     (rx_fifo_we[i]),
            .wdata  (i_rx),
            .wfull  (rx_fifo_wfull[i]),
            .re     (rx_fifo_re[i]),
            .rempty (rx_fifo_rempty[i]),
            .rdata  (rx_fifo_rdata[i])
        );
    end
endgenerate

// Write rx_fifo
assign o_rx_fifofull = rx_fifo_wfull[rx_index];
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        rx_index <= 'd0;
    end else begin
        if (i_rx_valid & ~rx_fifo_wfull[rx_index])
            rx_index <= rx_index + 1'b1;
    end
end
always @(*) begin
    if (i_rx_valid & ~rx_fifo_wfull[rx_index]) begin
        case (rx_index)
            2'b01: rx_fifo_we = 4'b0010; // write fifo_1
            2'b10: rx_fifo_we = 4'b0100; // write fifo_2
            2'b11: rx_fifo_we = 4'b1000; // write fifo_3
            default: rx_fifo_we = 4'b0001; // write fifo_0
        endcase
    end else begin
        rx_fifo_we = 4'b0000;
    end
end

// IRQ
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        o_irq <= 1'b0;
    end else begin
        if (rx_index == 2'b11 & i_rx_valid & ~rx_fifo_wfull[3]) o_irq <= 1'b1;
        else o_irq <= 1'b0; 
    end
end

// ISR: uart read
assign rx_fifo_re = {4{i_wb_valid && !i_wb_we && i_wb_adr==RX_DATA}};
assign rx_buffer = {rx_fifo_rdata[3], rx_fifo_rdata[2], rx_fifo_rdata[1], rx_fifo_rdata[0]};
always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        o_wb_dat <= 32'h00000000;
    end else begin
        if(i_wb_valid && !i_wb_we)begin
            case(i_wb_adr)
                RX_DATA:begin
                    o_wb_dat <= rx_buffer;
                end
                STAT_REG:begin
                    o_wb_dat <= stat_reg;
                end
                default:begin 
                    o_wb_dat <= 32'h00000000;
                end
            endcase
        end
    end
end

// Tx
// tx_fifo
generate
    genvar j;
    for (j=0; j<4; j=j+1) begin : TX
        FIFO #(
            .DATA_WIDTH(8),
            .ADDR_WIDTH(2)
        ) tx_fifo (
            .clk    (clk),
            .rst_n  (rst_n),
            .we     (tx_fifo_we[j]),
            .wdata  (tx_fifo_wdata[j]),
            .wfull  (tx_fifo_wfull[j]),
            .re     (tx_fifo_re[j]),
            .rempty (tx_fifo_rempty[j]),
            .rdata  (tx_fifo_rdata[j])
        );
    end
endgenerate

// ISR: uart write
assign tx_fifo_wdata[3] = i_wb_dat[31:24];
assign tx_fifo_wdata[2] = i_wb_dat[23:16];
assign tx_fifo_wdata[1] = i_wb_dat[15:8];
assign tx_fifo_wdata[0] = i_wb_dat[7:0];

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        tx_fifo_we <= 4'b0000;
    end else begin
        if ((i_wb_valid) & (i_wb_we) & (i_wb_adr==TX_DATA) & (~|tx_fifo_we))
            tx_fifo_we <= 4'b1111;
        else
            tx_fifo_we <= 4'b0000;
    end
end
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        tx_index <= 'd0;
    end else begin
        if (|tx_fifo_re) tx_index <= tx_index + 1'b1;
    end
end

// Read tx_fifo & start uart_tx
assign o_tx_start = ~&tx_fifo_rempty;
assign tx_fifo_re[3] = tx_index==2'b11 & o_tx_start & ~i_tx_busy;
assign tx_fifo_re[2] = tx_index==2'b10 & o_tx_start & ~i_tx_busy;
assign tx_fifo_re[1] = tx_index==2'b01 & o_tx_start & ~i_tx_busy;
assign tx_fifo_re[0] = tx_index==2'b00 & o_tx_start & ~i_tx_busy;

always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        tx_buffer <= 8'b0;
    end else begin
        if (|tx_fifo_re) tx_buffer <= tx_fifo_rdata[tx_index];
    end
end
always @(*) begin
    o_tx = tx_buffer;
end

// Wishbone
always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        o_wb_ack <= 1'b0;
    end else begin
        if(i_wb_valid)  
            o_wb_ack <= 1'b1;
        else            
            o_wb_ack <= 1'b0;
    end
end

endmodule
