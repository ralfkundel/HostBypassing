/*
Authors: Ralf Kundel, Kadir Eryigit, 2021

This module delays tail pointer increases and batches them
*/
`timescale 1ns / 1ps
`default_nettype none
module tailpointer_delay #(
    parameter MAX_TIME_CNT = 1000,//3 micro seconds
    parameter MAX_PACKET_CNT = 8
)(

	input wire                            clk_i,
    input wire                            rstn_i,

    //rx/tx_desc_ctrl side
	input wire[63:0]                        s_phys_addr_i,
	input wire[31:0]                        s_tail_pointer_i,
	input wire                              s_pcie_write_i,
    output reg                              s_pcie_write_ack_o,

    //pcie side
	output wire[63:0]                       m_phys_addr_o,
	output wire[31:0]                       m_tail_pointer_o,
	output reg                              m_pcie_write_o,
    input wire                              m_pcie_write_ack_i
	);

reg [31:0] last_tail_pointer_s;
reg [63:0] addr_s;

assign m_tail_pointer_o = last_tail_pointer_s;
assign m_phys_addr_o = addr_s;

reg [31:0] time_cnt, next_time_cnt;
reg [31:0] packet_cnt, next_packet_cnt;
reg state, next_state;
reg take_pointer_s;
reg next_s_pcie_write_ack_o;

localparam  STATE_IDLE               = 0, 
            STATE_WRITE              = 1;


always @(posedge clk_i) begin
    if(!rstn_i) begin
        state <= STATE_IDLE;
        time_cnt <= 0;
        packet_cnt <= 0;
    end else begin
        state <= next_state;
        time_cnt <= next_time_cnt;
        packet_cnt <= next_packet_cnt;
    end
    addr_s <= s_phys_addr_i;
    if (take_pointer_s) begin
        last_tail_pointer_s <= s_tail_pointer_i;    
    end else begin
    end
    s_pcie_write_ack_o <= next_s_pcie_write_ack_o;
end

always @(*) begin
    next_time_cnt = time_cnt;
    next_packet_cnt = packet_cnt;
    next_state = STATE_IDLE;
    take_pointer_s = 1'b0;
    m_pcie_write_o = 1'b0;
    next_s_pcie_write_ack_o = 1'b0;

    case (state)
    STATE_IDLE: begin
        take_pointer_s = s_pcie_write_i;        
        next_s_pcie_write_ack_o = 1'b1;
        if(time_cnt != MAX_TIME_CNT) begin
            next_time_cnt = time_cnt+1;
        end
        if(s_pcie_write_i) begin
            next_packet_cnt = packet_cnt+1;
        end
        if((time_cnt == MAX_TIME_CNT && next_packet_cnt!=0) || next_packet_cnt == MAX_PACKET_CNT) begin
            next_state = STATE_WRITE;
            m_pcie_write_o = 1'b1;   
            next_s_pcie_write_ack_o = 1'b0;
        end
    end

    STATE_WRITE:  begin
        next_state = STATE_WRITE;
        next_packet_cnt = 0;
        next_time_cnt = 0;
        m_pcie_write_o = 1'b1;
        if(m_pcie_write_ack_i) begin
            next_state = STATE_IDLE;
            m_pcie_write_o = 1'b0;
        end
    end
    endcase
end

endmodule
`default_nettype wire
