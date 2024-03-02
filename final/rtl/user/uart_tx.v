module uart_transmission(
  input wire        rst_n,
  input wire        clk,
  input wire [31:0] clk_div,
  input wire        tx_start,
  input wire [7:0]  tx_data,
  output reg        tx,
  output reg        tx_finish,
//   output reg        clear_req,
  output wire        busy
);

parameter WAIT        = 4'b0000;
parameter START_BIT   = 4'b0001;
parameter SEND_DATA   = 4'b0010;
parameter STOP_BIT    = 4'b0011;
// parameter CLEAR_REQ   = 4'b0100;

//=====================================================================
//   LOGIC DECLARATION
//=====================================================================
reg [3:0] cur_state, next_state;
reg [31:0] clk_cnt;
reg [2:0] tx_index;
reg [1:0] detect_posedge_start;

//=====================================================================
//   FSM
//=====================================================================
// Current state
always @(posedge clk or negedge rst_n) begin
    if (~rst_n)
        cur_state <= WAIT;
    else
        cur_state <= next_state;
end
// Next state
always @(*) begin
    case (cur_state)
        WAIT: begin
            if (tx_start/*detect_posedge_start == 2'b01*/)
                next_state = START_BIT;
            else
                next_state = WAIT;
        end
        START_BIT: begin
            if(clk_cnt == (clk_div - 1))
                next_state = SEND_DATA;
            else
                next_state = START_BIT;
        end
        SEND_DATA: begin
            if(clk_cnt == (clk_div - 1) && tx_index == 3'b111)
                next_state = STOP_BIT;
            else
                next_state = SEND_DATA;
        end
        STOP_BIT: begin
            if(clk_cnt == (clk_div - 1))
                next_state = WAIT;
            else
                next_state = STOP_BIT;
        end
        default: next_state = WAIT;
    endcase
end

//=====================================================================
//   DATA PATH & CONTROL
//=====================================================================
// Seq
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        tx_index  <= 3'b000;
        clk_cnt   <= 32'h0000_0000;
        tx_finish <= 1'b0;
    end else begin
        case (cur_state)
            WAIT: tx_finish <= 1'b0;
            START_BIT: begin
                if(clk_cnt == (clk_div - 1)) begin
                    clk_cnt <= 32'h0000_0000;
                end else begin
                    clk_cnt <= clk_cnt + 32'h0000_0001;
                end
            end
            SEND_DATA: begin
                if(clk_cnt == (clk_div - 1)) begin
                    clk_cnt <= 32'h0000_0000;
                    tx_index <= tx_index + 3'b001;
                end else begin
                    clk_cnt <= clk_cnt + 32'h0000_0001;
                end
            end
            STOP_BIT: begin
                if(clk_cnt == (clk_div - 1)) begin
                    clk_cnt <= 32'h0000_0000;
                    tx_finish <= 1'b1;
                end else begin
                    clk_cnt <= clk_cnt + 32'h0000_0001;
                end
            end
            default: begin
                tx_index  <= 3'b000;
                clk_cnt   <= 32'h0000_0000;
                tx_finish <= 1'b0;
            end
        endcase
    end
end
// Comb
assign busy = (
    cur_state == START_BIT ||
    cur_state == SEND_DATA ||
    cur_state == STOP_BIT);
assign clear_req = (cur_state == CLEAR_REQ);
always @(*) begin
    case (cur_state)
        WAIT: tx = 1'b1; // Drive Line High for Idle
        START_BIT: tx = 1'b0; // start bit = 0
        SEND_DATA: tx = tx_data[tx_index];
        STOP_BIT: tx = 1'b1; // stop bit = 1
        default: tx = 1'b1;
    endcase
end

endmodule