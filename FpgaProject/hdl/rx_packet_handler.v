/*
Authors: Ralf Kundel, Kadir Eryigit, 2020

This module reads packets from bram and generates an axistream.
New packets are signaled by a simple handhshake input with address and length signals.
This axistream supports ready signalling. 
*/
`timescale 1ns / 1ps
`default_nettype none

module rx_packet_handler #(
	parameter DATA_WIDTH = 128,
	parameter DEBUG_EN = 0
	)(
	(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 axi_clk CLK" *) (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF m_axis_eth, ASSOCIATED_RESET axi_aresetn" *)
	   input wire                            	 axi_clk,
	(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 axi_aresetn RST" *) (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
	   input wire                            	 axi_aresetn,

	   output reg[64-1:0]       			  m_axis_eth_tdata,		
	   output reg[7:0]                        m_axis_eth_tuser,
	   output reg                             m_axis_eth_tlast,
	   output reg[64/8-1:0]     			  m_axis_eth_tkeep,
	   output reg                             m_axis_eth_tvalid,
	   input wire                             m_axis_eth_tready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:bram_rtl:1.0 MODE MASTER,NAME BRAM_PORT" *)
    (* X_INTERFACE_PARAMETER = "MASTER_TYPE BRAM_CTRL, MEM_ECC NONE, MEM_WIDTH 128, MEM_SIZE 131072, READ_LATENCY 1" *) //READ_WRITE_MODE READ_WRITE
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT ADDR" *)
	output reg[32-1:0]   addr_o, 
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
	output reg wren_o, //intel fpga signal

	   input wire[32-1:0]                     pkt_addr_i,
	   input wire[15:0]                       pkt_len_i, // in bytes
	   input wire                             pkt_addr_v_i,
	   output reg                             pkt_ack_o

  );

localparam  IDLE            = 1,
			PKT_ADDR        = 2,
			STREAM_SET      = 3, STREAM_SET_LO = 3,
			STREAM_VALID    = 4, STREAM_WAIT_HI = 4,
			STREAM_SAVE     = 5,
			STREAM_SAVE2    = 6, 
			STREAM_LAST     = 7;

localparam AXIS_TDATA_WIDTH = 64;



reg[3:0] eth_stream_state = IDLE;
reg[AXIS_TDATA_WIDTH/8-1:0] tkeep_last;
reg[AXIS_TDATA_WIDTH/8-1:0] tkeep_last_reg;
reg[31:0] pkt_counter = 0;

reg[1:0] read_shift; //cleanup only 2 bits needed
reg      read_valid;
reg[1:0] last_shift;
reg[7:0] addr_cnt;
reg[7:0] read_cnt;
wire read_last = read_cnt == 0;
reg read_last_64;

reg first_beat;
reg[63:0] next_eth_tdata;
reg next_last;
reg[15:0] last_keep_128;
reg last_hi;

reg[DATA_WIDTH-1:0] data_save;
reg data_last_save;

reg[DATA_WIDTH-1:0] data_save2;
reg data_last_save2;

assign clk_o = axi_clk;

generate
	if(DATA_WIDTH==64) begin



		always @(posedge axi_clk) begin
		if (~axi_aresetn) begin
			m_axis_eth_tvalid <= 1'b0;
			pkt_ack_o         <= 1'b0;
			rst_o             <= 1'b0;
			wea_o             <= 0;
			wren_o            <= 1'b0;
			en_o              <= 1'b0;
			read_valid        <= 1'b0;
			read_shift        <= 2'b00;
			last_shift        <= 2'b00;
			read_last_64      <= 1'b0;
			eth_stream_state  <= IDLE;
		end
		else begin
			en_o       <= 1'b1;
			rst_o      <= 1'b0;
			read_shift <= {read_shift[0],1'b0};
			if(read_shift[0])
				read_valid <= 1'b1;
			last_shift   <= {last_shift[0],1'b0};
			if(last_shift[0])
				read_last_64 <= 1'b1;
			case(eth_stream_state)
				IDLE : begin  //1
					m_axis_eth_tuser <= 0;
					m_axis_eth_tkeep <= 8'hFF;
					pkt_ack_o        <= 1'b0;
					if(pkt_addr_v_i & ~pkt_ack_o)begin
						addr_o           <= {pkt_addr_i[31:3], 3'b000};
						read_shift[0]    <= 1'b1;
						read_cnt         <= pkt_len_i/8 - 1 + (|pkt_len_i[2:0]);
						addr_cnt         <= pkt_len_i/8 - 1 + (|pkt_len_i[2:0]);
						last_shift[0]    <= pkt_len_i < 9;
						tkeep_last_reg   <= tkeep_last;
						eth_stream_state <= STREAM_SET;
					end
				end
				PKT_ADDR : begin  //2
						addr_o           <= addr_o + 8;
						addr_cnt         <= addr_cnt - 1;
						last_shift[1]    <= addr_cnt == 0;
						last_shift[0]    <= addr_cnt == 1;
						read_shift[0]    <= 1'b1;
						eth_stream_state <= STREAM_SET;
				end
				STREAM_SET : begin //3
					if(~|last_shift) begin
						addr_o           <= addr_o + 8;
						addr_cnt         <= addr_cnt - 1;
						last_shift[0]    <= addr_cnt == 1;
						read_shift[0]    <= 1'b1;
					end
					if(read_valid) begin
						m_axis_eth_tdata  <= data_i; 
						m_axis_eth_tvalid <= 1'b1; 
						m_axis_eth_tlast  <= read_last_64;
						// read_cnt          <= read_cnt - 1;
						read_valid        <= read_shift[0];
						eth_stream_state  <= STREAM_VALID;
						if(read_last_64) begin
							m_axis_eth_tkeep <= tkeep_last_reg;
							eth_stream_state <= STREAM_LAST;
						end
					end
					
				end
				STREAM_VALID : begin  //4
					if(~m_axis_eth_tready & read_valid & read_shift[0]) begin
						data_save        <= data_i;
						data_last_save   <= read_last_64;
						read_valid       <= read_shift[0];
						eth_stream_state <= STREAM_SAVE;
					end
					if(m_axis_eth_tready) begin
						if(~|last_shift) begin
							addr_o           <= addr_o + 8;
							addr_cnt         <= addr_cnt - 1;
							last_shift[0]    <= addr_cnt == 1;
							read_shift[0]     <= 1'b1;
						end
						m_axis_eth_tdata  <= data_i;
						read_cnt          <= read_cnt - 1;
						m_axis_eth_tlast  <= read_last_64;
						read_valid        <= read_shift[0];

						if(~read_valid) 
							eth_stream_state <= STREAM_SET;
						if(read_last_64) begin
							m_axis_eth_tkeep <= tkeep_last_reg;
							eth_stream_state <= STREAM_LAST;
						end
					end
				end
				STREAM_SAVE : begin  //5
					if(~m_axis_eth_tready & read_shift[0]) begin
						data_save2       <= data_i;
						data_last_save2  <= read_last_64;
						eth_stream_state <= STREAM_SAVE2;
					end

					if(m_axis_eth_tready) begin
						m_axis_eth_tdata  <= data_save;
						m_axis_eth_tlast  <= data_last_save;
						m_axis_eth_tvalid <= 1'b1;
						m_axis_eth_tkeep  <= 8'hFF;
						read_cnt          <= read_cnt - 1;
						if(~|last_shift) begin
							addr_o           <= addr_o + 8;
							addr_cnt         <= addr_cnt - 1;
							last_shift[0]    <= addr_cnt == 1;
							read_shift[0]     <= 1'b1;
						end
						if(~read_shift[0])
							eth_stream_state  <= STREAM_VALID;
						if(read_shift[0]) begin
							data_save      <= data_i;
							data_last_save <= read_last_64;
						end

						if(data_last_save) begin
							m_axis_eth_tkeep <= tkeep_last_reg;
							eth_stream_state <= STREAM_LAST;
						end
					end
				end
				STREAM_SAVE2 : begin
					if(m_axis_eth_tready) begin
						m_axis_eth_tdata  <= data_save;
						m_axis_eth_tlast  <= data_last_save;
						m_axis_eth_tkeep  <= 8'hFF;
						data_save         <= data_save2;
						data_last_save    <= data_last_save2;
						if(~|last_shift) begin
							addr_o           <= addr_o + 8;
							addr_cnt         <= addr_cnt - 1;
							last_shift[0]    <= addr_cnt == 1;
							read_shift[0]     <= 1'b1;
						end
						read_cnt          <= read_cnt - 1;
							eth_stream_state  <= STREAM_SAVE;
						if(data_last_save) begin
							m_axis_eth_tkeep <= tkeep_last_reg;
							eth_stream_state <= STREAM_LAST;
						end
					end
				end
				STREAM_LAST : begin  //6
					if(m_axis_eth_tready) begin
						read_shift        <= 2'b00;
						last_shift        <= 2'b00;
						read_last_64      <= 1'b0;
						pkt_ack_o         <= 1'b1;
						read_valid        <= 1'b0;
						m_axis_eth_tvalid <= 1'b0;
						m_axis_eth_tlast  <= 1'b0;
						eth_stream_state  <= IDLE;
					end
				end
				default : begin
					m_axis_eth_tvalid <= 1'b0;
					eth_stream_state  <= IDLE;
				end
			endcase

			end
		end



	end else if(DATA_WIDTH==128) begin



		always @(posedge axi_clk) begin
		if (~axi_aresetn) begin
			m_axis_eth_tvalid <= 1'b0;
			pkt_ack_o         <= 1'b0;
			rst_o             <= 1'b0;
			wea_o             <= 0;
			wren_o            <= 1'b0;
			en_o              <= 1'b0;
			read_valid        <= 1'b0;
			read_shift        <= 2'b000;
			first_beat        <= 1'b0;
			eth_stream_state  <= IDLE;
		end
		else begin
			en_o       <= 1'b1;
			rst_o      <= 1'b0;
			read_shift <= {read_shift[0],1'b0};
			if(read_shift[0])
				read_valid <= 1'b1;
			case(eth_stream_state)
				IDLE : begin  //1
					m_axis_eth_tuser <= 0;
					m_axis_eth_tkeep <= 8'hFF;
					pkt_ack_o        <= 1'b0;
					if(pkt_addr_v_i & ~pkt_ack_o)begin
						addr_o           <=  {pkt_addr_i[31:4],4'h0};
						read_shift[0]    <= 1'b1;
						first_beat       <= 1'b1;
						read_cnt         <= pkt_len_i/16 -1 + (|pkt_len_i[3:0]);
						last_hi          <= (pkt_len_i[3:0]==0) || (pkt_len_i[3:0]>8);
						tkeep_last_reg   <= tkeep_last;
						eth_stream_state <= STREAM_SET_LO;
					end
				end
				PKT_ADDR : begin  //2
					addr_o           <= addr_o + 16;
					read_shift[0]    <= 1'b1;
					eth_stream_state <= STREAM_SET_LO;
				end
				STREAM_SET_LO : begin //3
					if(~m_axis_eth_tready & ~first_beat & read_valid & read_shift[0]) begin  //save data if next cycle would overwrite it
						data_save        <= data_i;
						data_last_save   <= read_last;
						read_valid       <= read_shift[0];
						eth_stream_state <= STREAM_SAVE;
					end
					if( (m_axis_eth_tready | first_beat) & read_valid ) begin
						first_beat        <= 1'b0;
						m_axis_eth_tdata  <= data_i[63:0];
						next_eth_tdata    <= data_i[127:64];
						addr_o            <= addr_o + 16;
						read_shift[0]    <= 1'b1;
						m_axis_eth_tvalid <= 1'b1;
						m_axis_eth_tlast  <= ~last_hi & read_last;
						read_valid        <= read_shift[0];
						read_cnt          <= read_cnt - 1;
					 	next_last         <= last_hi & read_last;
						eth_stream_state  <= STREAM_WAIT_HI;
						if(~last_hi &  read_last) begin
							m_axis_eth_tkeep <= tkeep_last_reg;
							read_shift       <= 3'b000;
							read_valid       <= 1'b0;
							eth_stream_state <= STREAM_LAST;
					    end
					end
				end
				STREAM_WAIT_HI : begin //4

					if(m_axis_eth_tready) begin
						m_axis_eth_tdata <= next_eth_tdata;
						m_axis_eth_tlast <= next_last;
						// addr_o           <= addr_o + 16;
						// read_shift[0]    <= 1'b1;
						eth_stream_state <= STREAM_SET_LO;
						if(next_last) begin
							m_axis_eth_tkeep <= tkeep_last_reg;
							read_shift       <= 2'b00;
							read_valid       <= 1'b0;
							eth_stream_state <= STREAM_LAST;
						end
					end
				end
				STREAM_SAVE : begin //5
					if( m_axis_eth_tready) begin
						first_beat        <= 1'b0;
						m_axis_eth_tdata  <= data_save[63:0];
						next_eth_tdata    <= data_save[127:64];
						m_axis_eth_tvalid <= 1'b1;
						m_axis_eth_tlast  <= ~last_hi & data_last_save;
						read_cnt          <= read_cnt - 1;
					 	next_last         <= last_hi & data_last_save;
						eth_stream_state  <= STREAM_WAIT_HI;
						if(~last_hi &  data_last_save) begin
							m_axis_eth_tkeep <= tkeep_last_reg;
							read_shift       <= 2'b00;
							read_valid       <= 1'b0;
							eth_stream_state <= STREAM_LAST;
					    end
					end
				end
				STREAM_LAST : begin  //6
					if(m_axis_eth_tready) begin
						m_axis_eth_tvalid <= 1'b0;
						m_axis_eth_tlast  <= 1'b0;
						pkt_ack_o         <= 1'b1; //ack here because we need to read data safely
						eth_stream_state  <= IDLE;
					end
				end
				default : begin
					m_axis_eth_tvalid <= 1'b0;
					eth_stream_state  <= IDLE;
				end
			endcase

			end
		end
		
	end
	
endgenerate

always @(pkt_len_i) begin
	case(pkt_len_i[2:0])
		3'b000 : tkeep_last = 8'hFF;
		3'b001 : tkeep_last = 8'h01;
		3'b010 : tkeep_last = 8'h03;
		3'b011 : tkeep_last = 8'h07;
		3'b100 : tkeep_last = 8'h0F;
		3'b101 : tkeep_last = 8'h1F;
		3'b110 : tkeep_last = 8'h3F;
		3'b111 : tkeep_last = 8'h7F;
	endcase
end



generate
if(DEBUG_EN) begin
	(* MARK_DEBUG="true" *)	reg[32-1:0]                    pkt_addr_i_debug;
	(* MARK_DEBUG="true" *)	reg[15:0]                      pkt_len_i_debug;
	(* MARK_DEBUG="true" *)	reg                            pkt_addr_v_i_debug;
	(* MARK_DEBUG="true" *)	reg                            pkt_ack_o_debug;
	(* MARK_DEBUG="true" *)	reg[2:0]                       eth_stream_state_debug;
	(* MARK_DEBUG="true" *) reg[AXIS_TDATA_WIDTH-1:0]      m_axis_eth_tdata_debug;		
	(* MARK_DEBUG="true" *) reg                            m_axis_eth_tlast_debug;
	(* MARK_DEBUG="true" *) reg[AXIS_TDATA_WIDTH/8-1:0]    m_axis_eth_tkeep_debug;
	(* MARK_DEBUG="true" *) reg                            m_axis_eth_tvalid_debug;
	(* MARK_DEBUG="true" *) reg                            m_axis_eth_tready_debug;
	(* MARK_DEBUG="true" *) reg[AXIS_TDATA_WIDTH/8-1:0]    tkeep_last_debug;
    (* MARK_DEBUG="true" *) reg[AXIS_TDATA_WIDTH/8-1:0]    tkeep_last_reg_debug;
    (* MARK_DEBUG="true" *) reg[32-1:0]                    addr_o_debug;
    (* MARK_DEBUG="true" *) reg[DATA_WIDTH-1:0]            data_i_debug;
    (* MARK_DEBUG="true" *) reg[1:0]                       read_shift_debug;
    (* MARK_DEBUG="true" *) reg                            read_valid_debug;
    (* MARK_DEBUG="true" *) reg[1:0]                       last_shift_debug;
    (* MARK_DEBUG="true" *) reg[7:0]                       read_cnt_debug;
    (* MARK_DEBUG="true" *) reg                            read_last_debug;

	always @(posedge axi_clk) begin
		pkt_addr_i_debug        <= pkt_addr_i;
		pkt_len_i_debug         <= pkt_len_i;
		pkt_addr_v_i_debug      <= pkt_addr_v_i;
		pkt_ack_o_debug         <= pkt_ack_o;
		eth_stream_state_debug  <= eth_stream_state;
		m_axis_eth_tdata_debug  <= m_axis_eth_tdata;
		m_axis_eth_tlast_debug  <= m_axis_eth_tlast;
		m_axis_eth_tkeep_debug  <= m_axis_eth_tkeep;
		m_axis_eth_tvalid_debug <= m_axis_eth_tvalid;
		m_axis_eth_tready_debug <= m_axis_eth_tready;
		tkeep_last_debug        <= tkeep_last;
		tkeep_last_reg_debug    <= tkeep_last_reg;
		addr_o_debug            <= addr_o;
		data_i_debug            <= data_i;
		read_shift_debug        <= read_shift;
		read_valid_debug        <= read_valid;
		last_shift_debug        <= last_shift;
		read_cnt_debug          <= read_cnt;
		read_last_debug         <= read_last;
	end
		
end
endgenerate

endmodule
`default_nettype wire
