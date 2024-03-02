module uart_receive (
  input wire        rst_n,
  input wire        clk,
  input wire [31:0] clk_div,
  input wire        rx,
  output reg        rx_finish,
  output reg        rx_valid,
  output reg [7:0]  rx_data,
  input wire        rx_fifofull,
  output wire        frame_err,
  output wire        busy
);

parameter WAIT        = 4'b0000;
parameter START_BIT   = 4'b0001;
parameter GET_DATA    = 4'b0010;
parameter STOP_BIT    = 4'b0011;
parameter WAIT_READ   = 4'b0100;
parameter FRAME_ERR   = 4'b0101;
// parameter FINISH      = 4'b0110;

//=====================================================================
//   LOGIC DECLARATION
//=====================================================================
reg [3:0] cur_state, next_state;
reg [31:0] clk_cnt;
reg [2:0] rx_index, tx_index;

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
            if (rx == 1'b0) // Start bit detected
                next_state = START_BIT;
            else
                next_state = WAIT;
        end
        START_BIT: begin
            // Check middle of start bit to make sure it's still low
            if (clk_cnt == ((clk_div >> 1) - 1) && rx == 1'b0)
                next_state = GET_DATA;
            else
                next_state = START_BIT;
        end
        GET_DATA: begin
            // Wait CLKS_PER_BIT-1 clock cycles to sample serial data
            if (clk_cnt == (clk_div - 1) && rx_index == 3'b111)
                next_state = STOP_BIT;
            else
                next_state = GET_DATA;
        end
        STOP_BIT: begin
            // Receive Stop bit.  Stop bit = 1
            if (clk_cnt == (clk_div - 1)) begin
                if (rx == 1'b1) begin
                    next_state = WAIT_READ;
                end else begin
                    next_state = FRAME_ERR;
                end
            end else begin
                next_state = STOP_BIT;
            end
        end
        // FINISH: next_state = WAIT_READ;
        WAIT_READ: begin
            if (rx_fifofull) next_state = WAIT_READ;
            else next_state = WAIT;
        end
        FRAME_ERR: next_state = WAIT;
        default: next_state = WAIT;
    endcase
end

//=====================================================================
//   DATA PATH & CONTROL
//=====================================================================
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        clk_cnt   <= 32'h0000_0000;
        rx_index  <= 3'b000;
        rx_finish <= 1'b0;
        rx_data   <= 8'h0;
        rx_valid <= 1'b0;
    end else begin
        case (cur_state)
            WAIT: begin
                rx_finish <= 1'b0;
                rx_data <= 8'b0;
            end 
            START_BIT: begin
                if (clk_cnt == ((clk_div >> 1) - 1))
                    clk_cnt <= 32'h0000_0000;
                else
                    clk_cnt <= clk_cnt + 32'h0000_0001;    
            end
            GET_DATA: begin
                if (clk_cnt == (clk_div - 1)) begin
                    clk_cnt <= 32'h0000_0000;
                    rx_index <= rx_index + 3'b001;
                    rx_data[rx_index] <= rx;
                    //$display("rx data bit index:%d %b", rx_index, rx_data[rx_index]);
                end else begin
                    clk_cnt <= clk_cnt + 32'h0000_0001;
                end
            end
            STOP_BIT: begin
                if(clk_cnt == (clk_div - 1)) begin
                    clk_cnt <= 32'h0000_0000;
                    if (rx == 1'b1) begin
                        rx_finish <= 1'b1;
                        rx_valid <= 1'b1;
                    end else begin
                        rx_finish <= 1'b0;  
                    end 
                end else begin
                    clk_cnt <= clk_cnt + 32'h0000_0001;
                end
            end
            WAIT_READ: begin
                rx_finish <= 1'b0;
                if(~rx_fifofull) rx_valid <= 1'b0;
            end
            FRAME_ERR: begin
                rx_finish <= 0;
            end
            default: begin
                clk_cnt   <= 32'h0000_0000;
                rx_index  <= 3'b000;
                rx_finish <= 1'b0;
                rx_data   <= 8'h0;
                rx_valid <= 1'b0;
            end
        endcase
    end
end
assign busy = (
    cur_state == START_BIT ||
    cur_state == GET_DATA ||
    cur_state == STOP_BIT);
assign frame_err = (cur_state == FRAME_ERR);

endmodule