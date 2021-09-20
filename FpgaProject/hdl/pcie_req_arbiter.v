/*
Authors: Ralf Kundel, Kadir Eryigit, 2020

This module arbitrates two pcie request interfaces.
It is held very simple to allow for 32bit writes with 64 bit adresses.
A simple valid-ack handshake protocol is used for both sides of the requests.
The arbitration happens in a round-robin fashion.
*/
`timescale 1ns / 1ps
`default_nettype none
module pcie_req_arbiter #(
	parameter ADDR_WIDTH = 64,
	parameter DEBUG_EN   = 0
)(

	(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk_i CLK" *) (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET axi_aresetn" *)
	input wire                 clk_i,
	(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_i_n RST" *) (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
	input wire                 rst_i_n,


	input wire[ADDR_WIDTH-1:0] pcie_addr0_i,
	input wire[31:0]           pcie_data0_i,
	input wire                 pcie_valid0_i,
	output reg                 fifo_ready0_o,

	input wire[ADDR_WIDTH-1:0] pcie_addr1_i,
	input wire[31:0]           pcie_data1_i,
	input wire                 pcie_valid1_i,
	output reg                 fifo_ready1_o,

	input wire                 pcie_ack_i,

	output reg[ADDR_WIDTH-1:0] pcie_addr_o,
	output reg[31:0]           pcie_data_o,
	output reg                 pcie_valid_o

);

localparam DATA_WIDTH = ADDR_WIDTH + 32;

localparam IN = 1,
			READY = 2;

reg[1:0] mux_state = IN;


reg round;

always @(posedge clk_i) begin
	if (~rst_i_n) begin
		mux_state     <= IN;
		fifo_ready0_o <= 1'b0;
		fifo_ready1_o <= 1'b0;
		pcie_valid_o  <= 1'b0;
		round         <= 1'b0;
	end
	else begin
		case(mux_state)
			IN : begin
				pcie_valid_o <= pcie_valid0_i | pcie_valid1_i;
				if(pcie_valid0_i & ~pcie_valid1_i) begin
					pcie_addr_o   <= pcie_addr0_i;
					pcie_data_o   <= pcie_data0_i;
					fifo_ready0_o <= 1'b1;
					round         <= 1'b1;
					mux_state     <= READY;
				end
				if(~pcie_valid0_i & pcie_valid1_i) begin
					pcie_addr_o   <= pcie_addr1_i;
					pcie_data_o   <= pcie_data1_i;
					fifo_ready1_o <= 1'b1;
					round         <= 1'b0;
					mux_state     <= READY;
				end
				if(pcie_valid0_i & pcie_valid1_i)begin
					if(round) begin
						pcie_addr_o   <= pcie_addr1_i;
						pcie_data_o   <= pcie_data1_i;
						fifo_ready1_o <= 1'b1;
					end else begin
						pcie_addr_o   <= pcie_addr0_i;
						pcie_data_o   <= pcie_data0_i;
						fifo_ready0_o <= 1'b1;
					end

					mux_state <= READY;
					round     <= ~round;
				end

			end
			READY : begin
				fifo_ready0_o <= 1'b0;
				fifo_ready1_o <= 1'b0;
				if(pcie_ack_i) begin
					pcie_valid_o <= 1'b0;
					mux_state    <= IN;
				end
			end
			default : begin
				fifo_ready0_o <= 1'b0;
				fifo_ready1_o <= 1'b0;
				round         <= 1'b0;
				mux_state     <= IN;
			end
		endcase
	end
end



generate
if(DEBUG_EN) begin
	// (* MARK_DEBUG="true" *)
	(* MARK_DEBUG="true" *) reg[ADDR_WIDTH-1:0]  pcie_addr0_i_debug;
	(* MARK_DEBUG="true" *) reg[31:0]            pcie_data0_i_debug;
	(* MARK_DEBUG="true" *) reg                  pcie_valid0_i_debug;
	(* MARK_DEBUG="true" *) reg                  fifo_ready0_o_debug;
	(* MARK_DEBUG="true" *) reg[ADDR_WIDTH-1:0]  pcie_addr1_i_debug;
	(* MARK_DEBUG="true" *) reg[31:0]            pcie_data1_i_debug;
	(* MARK_DEBUG="true" *) reg                  pcie_valid1_i_debug;
	(* MARK_DEBUG="true" *) reg                  fifo_ready1_o_debug;
	(* MARK_DEBUG="true" *) reg                  pop_req_i_debug;
	(* MARK_DEBUG="true" *) reg[ADDR_WIDTH-1:0] pcie_addr_o_debug;
	(* MARK_DEBUG="true" *) reg[31:0]           pcie_data_o_debug;
	(* MARK_DEBUG="true" *) reg                 pcie_valid_o_debug;

	always @(posedge clk_i) begin
		pcie_addr0_i_debug  <= pcie_addr0_i;
		pcie_data0_i_debug  <= pcie_data0_i;
		pcie_valid0_i_debug <= pcie_valid0_i;
		fifo_ready0_o_debug <= fifo_ready0_o;
		pcie_addr1_i_debug  <= pcie_addr1_i;
		pcie_data1_i_debug  <= pcie_data1_i;
		pcie_valid1_i_debug <= pcie_valid1_i;
		fifo_ready1_o_debug <= fifo_ready1_o;
		pop_req_i_debug     <= pcie_ack_i;
		pcie_addr_o_debug   <= pcie_addr_o;
		pcie_data_o_debug   <= pcie_data_o;
		pcie_valid_o_debug  <= pcie_valid_o;
	end
	
end	
endgenerate

endmodule
`default_nettype wire
