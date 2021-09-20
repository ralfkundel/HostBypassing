/*
Authors: Ralf Kundel, Kadir Eryigit, 2020

This module handles the generation of tx-descriptors and the subsequent increment of the tx-tail-pointer on the network card.
Please also check the 82599-10-gbe-controller datasheet for further information.

This module is listening for new packet requests on a simple handshake interface with additional packet length information. 
On the event of a new request the tx-descriptor is written on a local FPGA bram.
The descriptor attributes are mostly static except the packet length.
The NIC is informed of the new tx-descriptor by an increase of its tx-tail pointer.
This module generates a simple pcie-request to increment the tail pointer on the NIC.
*/
`timescale 1ns / 1ps
`default_nettype none
module tx_desc_ctrl #(
	parameter NB_DESC = 64,
	parameter DEBUG_EN = 0
)(
(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk_i CLK" *) (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET rst_i_n" *)
	input wire                             clk_i,
(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_i_n RST" *) (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
	input wire                              rst_i_n,

    (* X_INTERFACE_INFO = "xilinx.com:interface:bram_rtl:1.0 MODE MASTER,NAME BRAM_PORT" *)
    (* X_INTERFACE_PARAMETER = "MASTER_TYPE BRAM_CTRL, MEM_ECC NONE, MEM_WIDTH 128, MEM_SIZE 256" *) //READ_WRITE_MODE READ_WRITE
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT ADDR" *)
	output reg[32-1:0]   addr_o, //addr is data width aligned
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT CLK" *) 
	output wire                  clk_o,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT DIN" *) 
	output reg[128-1:0]   data_o,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT DOUT" *) 
	input wire[128-1:0]   data_i,
	(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT EN" *)  
	output reg                   en_o,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT RST" *)
	output reg                   rst_o,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT WE" *) 
	output reg[128/8-1:0] wea_o,
    output reg wren_o,  //additional signal for intel fpgas

	input wire                            start_i,
	input wire                            init_i,


	input wire[31:0]                      nic_base_addr_i,
	input wire[31:0]                      fpga_base_addr_i,
	// input wire[31:0]                      desc_base_addr_i,

	input wire[31:0]                      pkt_addr_i,
	input wire[15:0]                      pkt_len_i,
	input wire   						  xmit_req_i,
	output reg                            xmit_ack_o,

	output reg[63:0]                      nic_phys_addr_o,
	output reg[31:0]                      nic_tx_tail_pointer_o,
	output reg                            pcie_rq_start_o,
	input wire 							  pcie_rq_ack_i
	);
	
// TODO enable writeback here
//`define REPORT_STATUS

localparam TDT_REG_OFFS = 64'h00000000_00006018; //see 8.2.3.9.9 in 82599-10-gbe-controller datasheet

assign clk_o = clk_i;


wire[31:0] pkt_base_addr = fpga_base_addr_i | (256*2048);

localparam 
           RESET              = 0,
           IDLE               = 1,
		   WRITE_DESC_BEAT1   = 2,
		   PCIE_WRITE_TDT_REG = 3,
		   PCIE_WAIT_TDT_REG  = 4;


localparam DESC_IX_SZ = $clog2(NB_DESC);
// 82599-10-gbe-controller datasheet 7.2.3.2.4 Advanced Transmit Data Descriptor
reg[63:0] pkt_addr;
reg[15:0] data_len;
wire[1:0] mac   = 0; //not mac address
wire[3:0] dtyp  = 4'b0011;
`ifdef REPORT_STATUS
    wire[7:0] dcmd  = 8'b0010_1011; //7:Transmit Segmentation Enable, 6: VLAN Packet Enable, 5: Descriptor Extension, 4: reserved, 3: Report Status (enabled by Ralf -2021-03-06), 2: reserved, 1: Insert FCS, 0:End of Packet
`else
    wire[7:0] dcmd  = 8'b0010_0011;
`endif
wire[3:0] sta   = 0;
wire[2:0] idx   = 0;
wire cc         = 0;
wire[5:0] popts = 0;
reg[17:0] paylen;

wire[127:0] tx_desc = {paylen,popts,cc,idx,sta,dcmd,dtyp,mac,2'b00,data_len,pkt_addr};

reg[2:0] tx_desc_state = RESET;
reg[DESC_IX_SZ-1:0] tail_pointer;

reg init;

reg[7:0] init_cnt = 0;

always @(posedge clk_i) begin
	if (~rst_i_n) begin
		init      <= 1'b1;
	end else begin
		init <= init_i;
	end
end


wire [3:0] descriptor_status_s;
`ifdef REPORT_STATUS
assign descriptor_status_s = data_i[35+64:32+64];
`else
assign descriptor_status_s = 4'b0001;
`endif
  
always @(posedge clk_i) begin
    if (init) begin
		xmit_ack_o      <= 1'b0;
		tail_pointer    <= 0;
		pcie_rq_start_o <= 1'b0;
		rst_o           <= 1'b1;
		en_o            <= 1'b0;
		wea_o	        <= 0;
		wren_o          <= 1'b0;
		tx_desc_state   <= RESET;

	end
	else begin
		rst_o           <= 1'b0;
		en_o            <= 1'b1;
		
		case(tx_desc_state)
		RESET: begin //initialize all tx descriptors
		    tx_desc_state <= RESET;
		    data_o <= {28'bx, 4'b0001, 32'bx, 64'bx};
		    addr_o <= {  {(32-DESC_IX_SZ-4){1'b0}}, tail_pointer,4'b0000 };
            wea_o  <= 16'hFFFF;
            wren_o <= 1'b1;
            tail_pointer  <= tail_pointer + 1;
            
            if(tail_pointer == NB_DESC-1) begin
    		    tx_desc_state <= IDLE;
            end            
		end
		
		IDLE : begin  //1
            wren_o <= 1'b0;
            wea_o  <= 16'h0000;
            nic_phys_addr_o <= nic_base_addr_i + TDT_REG_OFFS;
			addr_o     <= {  {(32-DESC_IX_SZ-4){1'b0}}, tail_pointer,4'b0000 }; //for reading the old status bit
			if(xmit_req_i & start_i) begin
				pkt_addr      <= {32'h0000_0000,pkt_addr_i | pkt_base_addr};
				data_len      <= pkt_len_i;
				paylen        <= {2'b00,pkt_len_i};
				xmit_ack_o    <= 1'b1;
				tx_desc_state <= WRITE_DESC_BEAT1;
			end
			
		end
		
		WRITE_DESC_BEAT1 : begin  //2
		
			xmit_ack_o <= 1'b0;
			tx_desc_state <= WRITE_DESC_BEAT1;
			
		    if (descriptor_status_s[0] == 1'b1) begin
                addr_o     <= {  {(32-DESC_IX_SZ-4){1'b0}}, tail_pointer,4'b0000 };
                data_o     <= tx_desc;
                wea_o      <= 16'hFFFF;
                wren_o     <= 1'b1;
    
                tail_pointer  <= tail_pointer + 1;
                tx_desc_state <= PCIE_WRITE_TDT_REG;
			end
			
		end
		
		PCIE_WRITE_TDT_REG : begin
			wea_o  <= 16'h0000;
			wren_o <= 1'b0;

			nic_tx_tail_pointer_o <= { {(32-DESC_IX_SZ){1'b0}},tail_pointer};
			pcie_rq_start_o <= 1'b1;
			tx_desc_state   <= PCIE_WAIT_TDT_REG;
		end
		
		PCIE_WAIT_TDT_REG : begin
			if(pcie_rq_ack_i) begin
				pcie_rq_start_o <= 1'b0;
				tx_desc_state   <= IDLE;
			end
		end
		
		default : begin
			xmit_ack_o      <= 1'b0;
			tail_pointer    <= 0;
			pcie_rq_start_o <= 1'b0;
			tx_desc_state <= IDLE;
		end
		endcase
	end
end
	






generate
if(DEBUG_EN) begin
	
	// (* MARK_DEBUG="true" *)
	(* MARK_DEBUG="true" *) reg                          pcie_rq_start_o_debug;
	(* MARK_DEBUG="true" *) reg                          pcie_rq_ack_i_debug;
	(* MARK_DEBUG="true" *) reg[2:0]                     tx_desc_state_debug;
	(* MARK_DEBUG="true" *) reg[31:0]                    pkt_addr_i_debug;
	(* MARK_DEBUG="true" *) reg[15:0]                    pkt_len_i_debug;
	(* MARK_DEBUG="true" *) reg                          xmit_req_i_debug;
	(* MARK_DEBUG="true" *) reg                          xmit_ack_o_debug;
	(* MARK_DEBUG="true" *) reg[DESC_IX_SZ-1:0]          tail_pointer_debug;
	(* MARK_DEBUG="true" *) reg                          init_debug;
	(* MARK_DEBUG="true" *) reg                          start_debug;
	(* MARK_DEBUG="true" *) reg[32-1:0]                  addr_o_debug;
	(* MARK_DEBUG="true" *) reg[128-1:0]                 data_o_debug;
	(* MARK_DEBUG="true" *) reg                          en_o_debug;
	(* MARK_DEBUG="true" *) reg[128/8-1:0]               wea_o_debug;


	always @(posedge clk_i) begin
		pcie_rq_start_o_debug       <= pcie_rq_start_o;
		pcie_rq_ack_i_debug         <= pcie_rq_ack_i;
		tx_desc_state_debug         <= tx_desc_state;
		pkt_addr_i_debug            <= pkt_addr_i;
		pkt_len_i_debug             <= pkt_len_i;
		xmit_req_i_debug            <= xmit_req_i;
		xmit_ack_o_debug            <= xmit_ack_o;
		tail_pointer_debug          <= tail_pointer;
		init_debug                  <= init;
		start_debug                 <= start_i;
		addr_o_debug                <= addr_o;
		data_o_debug                <= data_o;
		en_o_debug                  <= en_o;
		wea_o_debug                 <= wea_o;
	end
end

	
endgenerate


//
endmodule
`default_nettype wire
