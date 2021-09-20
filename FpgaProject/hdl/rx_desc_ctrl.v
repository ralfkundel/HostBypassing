/*
Authors: Ralf Kundel, Kadir Eryigit, 2020

This module is handling all rx-side descriptor handling for the network interface card.
The statemachine is running in two phases, initialization and polling.
For further information regarding rx-handling please check 82599-10-gbe-controller datasheet. 

1) Initialization:
	All Rx-descriptors are initialized on a local FPGA BRAM with physical memory pointers to another local FPGA Bram.
	Note that the first initial rx-tail pointer is set by software and not here.
	The initialization phase can be started anytime when the init_i signal is pulled high.
	After initialization the rx-descriptor must not be written to until the NIC has finished writing back to the descriptors.

2) Polling:
	The polling phase is responsible for detecting new packets, resetting the rx-descriptor, notifying a new packet to other modules and incrementing the tail pointer on the NIC.
	The rx descriptors are write locked by protocol to make sure only the NIC can write to the descriptors until it advances to the next descriptors.
	These are the steps in the polling phase:
		1. Poll dd-bit of current rx-descriptor (starting at 0)
		2. Read packet length from rx-descriptor.
		3. Signal new packet and packet length to output
		4. Reset descriptor.
		5. Wait until new packet has been handled by outside module.
		5. Generate simple PCIe write transmission to advance rx tail pointer on NIC.
		6. Go back to 1.

	Note that the tail pointer must never be equal to the head pointer.
	This would result in a dead lock.
	To prevent this the tail pointer is always at least two units smaller than the head pointer.

*/
`timescale 1ns / 1ps
`default_nettype none
module rx_desc_ctrl #(
	parameter NB_DESC = 64,
	parameter DATA_WIDTH = 128,
	// parameter M_AXI_ID_WIDTH = 3,
	// parameter M_AXI_ADDR_WIDTH = 32,
	// parameter M_AXI_TDATA_WIDTH = 64,
	parameter DEBUG_EN = 0
)(
(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk_i CLK" *) (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET rst_i_n" *)
	input wire                             clk_i,
(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_i_n RST" *) (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
	input wire                              rst_i_n,


	(* X_INTERFACE_INFO = "xilinx.com:interface:bram_rtl:1.0 MODE MASTER,NAME BRAM_PORT" *)
    (* X_INTERFACE_PARAMETER = "MASTER_TYPE BRAM_CTRL, MEM_ECC NONE, MEM_WIDTH 128, MEM_SIZE 1024, READ_LATENCY 1" *) //READ_WRITE_MODE READ_WRITE
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT ADDR" *)
    output reg[32-1:0]   addr_o, //addr is data width aligned
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT CLK" *) 
    output wire                  clk_o,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT DIN" *) 
    output reg[DATA_WIDTH-1:0]   data_o,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT DOUT" *) 
    input wire[DATA_WIDTH-1:0]   data_i,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT EN" *)  
    output reg                   en_o,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT RST" *)
    output reg                  rst_o,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT WE" *) 
    output reg[DATA_WIDTH/8-1:0] wea_o,
    output reg wren_o,  //additional signal for intel fpgas

	input wire                            start_i,
	input wire                            init_i,

	input wire[31:0]                      nic_base_addr_i,
	input wire[31:0]                      fpga_base_addr_i,
	
	//TODO: this is ugly
	output reg[63:0]                      nic_phys_addr_o,
	output reg[31:0]                      nic_rx_tail_pointer_o,

	output reg                            pcie_rq_start_o,
	input wire                            pcie_rq_ack_i,

	output reg[32-1:0]                    pkt_addr_o,
	output reg[15:0]                      pkt_len_o,
	output reg                            pkt_addr_v_o,
	input wire                            pkt_ack_i
	);


localparam RDT_REG_OFFS = 64'h00000000_00001018;

assign clk_o = clk_i;

localparam IDLE               = 1, 
		   ADDR_INIT          = 2, 
		   DESC_PKT_INIT      = 3, DESC_INIT = 3,
		   DESC_HDR_INIT      = 4, 
		   DESC_POLL          = 5, 
		   DESC_WAIT          = 6, 
		   POLL               = 7,
		   READ_DESC          = 8, 
		   RST_DESC_LO        = 9, RST_DESC = 9,
		   RST_DESC_HI        = 10, 
		   PCIE_WRITE_RDT_REG = 11; 
		   

reg init;
reg init_done;

localparam DESC_IX_WIDTH = $clog2(NB_DESC);

localparam RX_ADDR_AREA = 2048; //so we are always aligned inside 4k AXI boundary
localparam RX_OFFS_WIDTH = $clog2(RX_ADDR_AREA*NB_DESC);

reg[DESC_IX_WIDTH-1:0] poll_ix;
reg[DESC_IX_WIDTH-1:0] tail_ix;

reg[3:0] poll_state = IDLE;
reg[RX_OFFS_WIDTH-1:0] rx_pkt_addr;
reg[7:0] burst_cnt;

reg[127:0] rx_desc;

// 82599-10-gbe-controller datasheet 7.1.6.2 Advanced Receive Descriptors - Write-Back Format
wire[3:0] rss_type                                         = rx_desc[3:0];
wire[12:0] pkt_type                                        = rx_desc[16:4];
wire[3:0] rsc_cnt                                          = rx_desc[20:17];
wire[9:0] hdr_len                                          = rx_desc[30:21];
wire sph                                                   = rx_desc[31];
wire[31:0] rss_hash_frag_chksm_rtt_fcoe_param_fd_filter_id = rx_desc[63:32];
wire[19:0] extd_stat_nextp                                 = rx_desc[83:64];
wire[11:0] extd_error                                      = rx_desc[95:84];
wire[15:0] pkt_len                                         = rx_desc[111:96];
wire[15:0] vlan_tag                                        = rx_desc[127:112];

wire dd_bit                                                = data_i[DATA_WIDTH-64]; //only works with 64 and 128 bit data widths

reg[31:0] pkt_in_counter = 0;
reg[31:0] pkt_out_counter = 0;

always @(posedge clk_i) begin
	if (~rst_i_n) begin
		init      <= 1'b0;
	end else begin
		if(init_done)
			init <= 1'b0;
		if(init_i)
			init <= 1'b1;
	end
end

generate
if(DATA_WIDTH==64) begin
	//Init 
always @(posedge clk_i) begin
	if (~rst_i_n) begin
		poll_state          <= IDLE;
		pkt_addr_v_o        <= 1'b0;
		pcie_rq_start_o     <= 1'b0;
		init_done           <= 1'b0;
		en_o                <= 1'b0;
		rst_o               <= 1'b0;
		wea_o               <= 0;
		wren_o              <= 1'b0;
	end
	else begin
		init_done           <= 1'b0;
		en_o                <= 1'b1;
		rst_o               <= 1'b0;
		wea_o               <= 8'h00;
		wren_o              <= 1'b0;
		case(poll_state)
		IDLE : begin  //1
			addr_o            <= 0;
			burst_cnt         <= NB_DESC*2-1;
			nic_phys_addr_o   <= nic_base_addr_i + RDT_REG_OFFS;
			rx_pkt_addr       <= 0;
			poll_ix           <= 0;
			tail_ix           <= NB_DESC-1; //this is set in ixgbe_dev_rx_queue_start() in ixgbe_rxtc.c (DPDK)
			if(init) begin
				pkt_in_counter  <= 0;
				pkt_out_counter <= 0;
				poll_state      <= ADDR_INIT;
			end
		end
		ADDR_INIT : begin  //2
			data_o      <= fpga_base_addr_i + rx_pkt_addr;
			wea_o       <= 8'hFF;
			wren_o      <= 1'b1;
			rx_pkt_addr <= rx_pkt_addr + RX_ADDR_AREA;
			poll_state  <= DESC_PKT_INIT;
		end
		DESC_PKT_INIT : begin  //3
			addr_o     <= addr_o + 8;
			data_o     <= 64'h0;
			wea_o      <= 8'hFF;
			wren_o      <= 1'b1;
			burst_cnt  <= burst_cnt - 1;
			poll_state <= DESC_HDR_INIT;
			if(burst_cnt == 1) begin
				init_done  <= 1'b1;
				poll_state <= DESC_POLL;
			end
		end
		DESC_HDR_INIT : begin  //4
			addr_o        <= addr_o + 8;
			data_o        <= fpga_base_addr_i + rx_pkt_addr;
			wea_o         <= 8'hFF;
			wren_o      <= 1'b1;
			rx_pkt_addr   <= rx_pkt_addr + RX_ADDR_AREA;
			burst_cnt     <= burst_cnt - 1;
			poll_state    <= DESC_PKT_INIT;
		end
		DESC_POLL : begin
			addr_o     <= { {(32-DESC_IX_WIDTH-4){1'b0}}, poll_ix,4'h8}; // + 8 because dd bit is in that address
			poll_state <= DESC_WAIT;
		end
		DESC_WAIT : begin
			poll_state <= POLL;
		end
		POLL : begin
			if(start_i & dd_bit)
				poll_state <= READ_DESC;
		end
		READ_DESC : begin  //5
			if(start_i & dd_bit) begin
				pkt_in_counter        <= pkt_in_counter + 1;
				data_o                <= 64'h0;
				wea_o                 <= 8'hFF;
				wren_o      <= 1'b1;
				poll_ix               <= poll_ix + 1;
				tail_ix               <= tail_ix + 1;
				pkt_addr_o            <= { {(32-DESC_IX_WIDTH-11){1'b0}}, poll_ix,11'b0000000000};
				pkt_len_o             <= data_i[47:32];
				nic_rx_tail_pointer_o <= {{(32-DESC_IX_WIDTH){1'b0}},tail_ix};
				poll_state            <= RST_DESC_LO;
			end
			if(init & ~init_done) begin
				poll_state    <= IDLE;
			end
		end
		RST_DESC_LO : begin //6
			data_o       <= fpga_base_addr_i + {poll_ix,11'b0000000000}; //*2048 //todo: parameter RX_ADDR_AREA
			addr_o       <= addr_o - 8;
			wea_o        <= 8'hFF;
			wren_o      <= 1'b1;
			pkt_addr_v_o <= 1'b1;
			poll_state   <= RST_DESC_HI;
		end
		RST_DESC_HI : begin  //7
			addr_o                <= { {(32-DESC_IX_WIDTH-4){1'b0}}, poll_ix,4'h8};
			if(pkt_ack_i) begin
				pkt_out_counter <= pkt_out_counter + 1;
				pkt_addr_v_o    <= 1'b0;
				pcie_rq_start_o <= 1'b1; 
				poll_state      <= PCIE_WRITE_RDT_REG;
			end
			if(init) begin
				pkt_addr_v_o    <= 1'b0;
				pcie_rq_start_o <= 1'b0;
				poll_state      <= IDLE;
			end
			
			
		end
		PCIE_WRITE_RDT_REG : begin  //8
			if(pcie_rq_ack_i) begin
				pcie_rq_start_o   <= 1'b0;
				poll_state        <= POLL;
				if(init)
					poll_state <= IDLE;
			end
		end
		default : begin
			poll_state          <= IDLE;
			init_done           <= 1'b0;
		end
		endcase
	end
end




end else if(DATA_WIDTH==128) begin



	//Init 
always @(posedge clk_i) begin
	if (~rst_i_n) begin
		poll_state          <= IDLE;
		init_done           <= 1'b0;
		pkt_addr_v_o        <= 1'b0;
		pcie_rq_start_o     <= 1'b0;
		en_o                <= 1'b0;
		rst_o               <= 1'b0;
		wea_o               <= 0;
		wren_o              <= 1'b0;
	end
	else begin
		init_done           <= 1'b0;
		en_o                <= 1'b1;
		rst_o               <= 1'b0;
		wea_o               <= 16'h0000;
		wren_o              <= 1'b0;
		case(poll_state)
		IDLE : begin  //1
			addr_o            <= 0;
			burst_cnt         <= NB_DESC-1;
			nic_phys_addr_o   <= nic_base_addr_i + RDT_REG_OFFS;
			rx_pkt_addr       <= 0;
			poll_ix           <= 0;
			tail_ix           <= NB_DESC-1; //this is set in ixgbe_dev_rx_queue_start() in ixgbe_rxtc.c (DPDK)
			if(init) begin
				pkt_in_counter      <= 0;
				pkt_out_counter     <= 0;
				poll_state          <= ADDR_INIT;
			end
		end
		ADDR_INIT : begin  //2
			data_o            <= {64'h0,fpga_base_addr_i + rx_pkt_addr};
			wea_o             <= 16'hFFFF;
			wren_o            <= 1'b1;
			rx_pkt_addr       <= rx_pkt_addr + RX_ADDR_AREA;
			poll_state        <= DESC_INIT;
		end
		DESC_INIT : begin  //3
			data_o      <= {64'h0,fpga_base_addr_i + rx_pkt_addr};
			wea_o       <= 16'hFFFF;
			wren_o            <= 1'b1;
			rx_pkt_addr <= rx_pkt_addr + RX_ADDR_AREA;
			addr_o      <= addr_o + 16;
			burst_cnt   <= burst_cnt - 1;
			if(burst_cnt == 1) begin
				init_done  <= 1'b1;
				poll_state <= DESC_POLL;
			end
		end
		DESC_POLL: begin //5
			addr_o     <= { {(32-DESC_IX_WIDTH-4){1'b0}}, poll_ix,4'h0};
			poll_state <= DESC_WAIT;
		end
		DESC_WAIT: begin  //6
			poll_state <= POLL;
			if(init & ~init_done)
				poll_state    <= IDLE;
		end
		POLL : begin // 7 
			if(start_i & dd_bit)
				poll_state <= READ_DESC;  //We read dd bit in two cycles to prevent read anomalies that can happen during simultaneous write and read into bram
			
			if(init & ~init_done)
				poll_state    <= IDLE;
		end
		READ_DESC : begin  //8 
			if(start_i & dd_bit) begin
				pkt_in_counter        <= pkt_in_counter + 1;
				
				poll_ix               <= poll_ix + 1;
				tail_ix               <= tail_ix + 1;
				
				rx_desc               <= data_i;
				
				pkt_addr_o            <= { {(32-DESC_IX_WIDTH-11){1'b0}}, poll_ix,11'b0000000000};
				pkt_len_o             <= data_i[111:96];
				pkt_addr_v_o          <= 1'b1;
				
				data_o                <= {64'h0,fpga_base_addr_i + {poll_ix,11'b0000000000} }; //*2048 //todo: parameter RX_ADDR_AREA
				wea_o                 <= 16'hFFFF;
				wren_o                <= 1'b1;

				nic_rx_tail_pointer_o <= {{(32-DESC_IX_WIDTH){1'b0}},tail_ix};
				poll_state            <= RST_DESC;
			end
			if(init & ~init_done) begin
				poll_state    <= IDLE;
			end
		end
		RST_DESC : begin  //9
			addr_o <= { {(32-DESC_IX_WIDTH-4){1'b0}}, poll_ix,4'h0};
			if(pkt_ack_i) begin
				pkt_out_counter     <= pkt_out_counter + 1;
				pkt_addr_v_o        <= 1'b0;
				pcie_rq_start_o     <= 1'b1; 
				poll_state          <= PCIE_WRITE_RDT_REG;
			end
			if(init) begin
				pkt_addr_v_o    <= 1'b0;
				pcie_rq_start_o <= 1'b0;
				poll_state      <= IDLE;
			end

		end
		PCIE_WRITE_RDT_REG : begin  //10
			if(pcie_rq_ack_i) begin
				pcie_rq_start_o   <= 1'b0;
				poll_state        <= POLL;
				if(init)
					poll_state <= IDLE;
			end
		end
		default : begin
			poll_state          <= IDLE;
		end
		endcase
	end
end
end
endgenerate





generate
if(DEBUG_EN) begin
	
	(* MARK_DEBUG="true" *) reg                            init_debug;
	(* MARK_DEBUG="true" *) reg                            pcie_rq_start_o_debug;
	(* MARK_DEBUG="true" *) reg                            pcie_rq_ack_i_debug;
	(* MARK_DEBUG="true" *) reg[3:0]                       poll_state_debug;
	(* MARK_DEBUG="true" *) reg[7:0]                       burst_cnt_debug;
	(* MARK_DEBUG="true" *) reg[DESC_IX_WIDTH-1:0]         poll_ix_debug;
	(* MARK_DEBUG="true" *) reg[DESC_IX_WIDTH-1:0]         tail_ix_debug;
	(* MARK_DEBUG="true" *) reg [32-1:0]                   pkt_addr_o_debug;
	(* MARK_DEBUG="true" *) reg [15:0]                     pkt_len_o_debug;
	(* MARK_DEBUG="true" *) reg                            pkt_addr_v_o_debug;
	(* MARK_DEBUG="true" *) reg                            pkt_ack_i_debug;

	(* MARK_DEBUG="true" *) reg[3:0]                       rss_type_debug;
	(* MARK_DEBUG="true" *) reg[12:0]                      pkt_type_debug;
	(* MARK_DEBUG="true" *) reg[3:0]                       rsc_cnt_debug;
	(* MARK_DEBUG="true" *) reg[9:0]                       hdr_len_debug;
	(* MARK_DEBUG="true" *) reg                            sph_debug;
	(* MARK_DEBUG="true" *) reg[31:0]                      rss_hash_frag_chksm_rtt_fcoe_param_fd_filter_id_debug;
	(* MARK_DEBUG="true" *) reg[19:0]                      extd_stat_nextp_debug;
	(* MARK_DEBUG="true" *) reg[11:0]                      extd_error_debug;
	(* MARK_DEBUG="true" *) reg[15:0]                      vlan_tag_debug;
	(* MARK_DEBUG="true" *) reg[31:0]                      pkt_in_counter_debug;
	(* MARK_DEBUG="true" *) reg[31:0]                      pkt_out_counter_debug;
    (* MARK_DEBUG="true" *) reg[32-1:0]                    addr_o_debug; //addr is data width aligned
    (* MARK_DEBUG="true" *) reg[DATA_WIDTH-1:0]            data_o_debug;
    (* MARK_DEBUG="true" *) reg[DATA_WIDTH-1:0]            data_i_debug;
    (* MARK_DEBUG="true" *) reg[DATA_WIDTH/8-1:0]          wea_o_debug;
	(* MARK_DEBUG="true" *) reg 				           dd_bit_debug;

	always @(posedge clk_i) begin
		init_debug                                           <= init;
		pcie_rq_start_o_debug                                <= pcie_rq_start_o;
		pcie_rq_ack_i_debug                                  <= pcie_rq_ack_i;
		poll_state_debug                                     <= poll_state;
		burst_cnt_debug                                      <= burst_cnt;
		poll_ix_debug                                        <= poll_ix;
		tail_ix_debug                                        <= tail_ix;
		pkt_addr_o_debug                                     <= pkt_addr_o;
		pkt_len_o_debug                                      <= pkt_len_o;
		pkt_addr_v_o_debug                                   <= pkt_addr_v_o;
		pkt_ack_i_debug                                      <= pkt_ack_i;
		rss_type_debug                                       <= rss_type;
		pkt_type_debug                                       <= pkt_type;
		rsc_cnt_debug                                        <= rsc_cnt;
		hdr_len_debug                                        <= hdr_len;
		sph_debug                                            <= sph;
		rss_hash_frag_chksm_rtt_fcoe_param_fd_filter_id_debug <= rss_hash_frag_chksm_rtt_fcoe_param_fd_filter_id;
		extd_stat_nextp_debug                                <= extd_stat_nextp;
		extd_error_debug                                     <= extd_error;
		vlan_tag_debug                                       <= vlan_tag;
		pkt_in_counter_debug                                 <= pkt_in_counter;
		pkt_out_counter_debug                                <= pkt_out_counter;
		addr_o_debug                                         <= addr_o;
		data_o_debug                                         <= data_o;
		data_i_debug                                         <= data_i;
		wea_o_debug                                          <= wea_o;
		dd_bit_debug                                         <= dd_bit;
	end
end

	
endgenerate

endmodule
`default_nettype wire
