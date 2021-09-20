/*
Authors: Ralf Kundel, Kadir Eryigit, 2020
*/

`timescale 1ns / 1ps
`default_nettype none
module configuration_registers #(
	parameter DEBUG_EN = 0
)(
   (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_i_n RST" *) (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
	input wire                             rst_i_n,

    (* X_INTERFACE_PARAMETER = "MASTER_TYPE BRAM_CTRL, MEM_ECC NONE, MEM_WIDTH 32, MEM_SIZE 4096, READ_WRITE_MODE READ_WRITE" *) //
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT ADDR" *)
	input wire[32-1:0]   addr_i, //addr is data width aligned
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT CLK" *) 
	input wire           clk_i,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT DOUT" *) 
	output reg[32-1:0]   data_o,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT DIN" *) 
	input wire[32-1:0]   data_i,
	(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT EN" *)  
	input wire           en_i,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT RST" *)
	input wire           rst_i,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT WE" *) 
	input wire[32/8-1:0] wea_i,



	output wire                        start_o,
	output wire                        init_o,
	output wire[63:0]                  nic_base_addr_reg_o,
	output wire[31:0]                  fpga_base_addr_reg_o

		);



reg[32-1:0] reg_0 = 0;
reg[32-1:0] reg_1;
reg[32-1:0] reg_2;

assign init_o = reg_0[0];
assign start_o = reg_0[1];
assign nic_base_addr_reg_o  = {32'b0, reg_1};
assign fpga_base_addr_reg_o = reg_2;

always @(posedge clk_i) begin
	if (~rst_i_n) begin
		// s_axi_awready     <= 1'b1;
		// s_axi_bvalid      <= 1'b0;
		// s_axi_wready      <= 1'b0;
		reg_0             <= 0;
		// w_state           <= IDLE;
	end
	else begin
		case(addr_i[3:2])
			2'b00 : begin
				if(en_i) begin
					if(wea_i[0]) reg_0[7:0]   <= data_i[7:0];
					if(wea_i[1]) reg_0[15:8]  <= data_i[15:8];
					if(wea_i[2]) reg_0[23:16] <= data_i[23:16];
					if(wea_i[3]) reg_0[31:24] <= data_i[31:24];
				end
			end
			2'b01 : begin
				if(en_i) begin
					if(wea_i[0]) reg_1[7:0]   <= data_i[7:0];
					if(wea_i[1]) reg_1[15:8]  <= data_i[15:8];
					if(wea_i[2]) reg_1[23:16] <= data_i[23:16];
					if(wea_i[3]) reg_1[31:24] <= data_i[31:24];
				end
			end
			2'b10 : begin
				if(en_i) begin
					if(wea_i[0]) reg_2[7:0]   <= data_i[7:0];
					if(wea_i[1]) reg_2[15:8]  <= data_i[15:8];
					if(wea_i[2]) reg_2[23:16] <= data_i[23:16];
					if(wea_i[3]) reg_2[31:24] <= data_i[31:24];
				end
			end
			default: begin
				
			end
		endcase

		if(reg_0[0])
			reg_0[0] <= 1'b0;
	end
end


always @(posedge clk_i) begin
	if(rst_i) begin
		data_o <= 0;
	end else begin		
		case(addr_i[3:2])
			2'b00 : begin
				if(en_i) data_o <= reg_0;
			end
			2'b01 : begin
				if(en_i) data_o <= reg_1;
			end
			2'b10 : begin
				if(en_i) data_o <= reg_2;
			end
			default : begin
				
			end
		endcase
		if(en_i) begin
			if(wea_i[0]) data_o[7:0]   <= data_i[7:0];
			if(wea_i[1]) data_o[15:8]  <= data_i[15:8];
			if(wea_i[2]) data_o[23:16] <= data_i[23:16];
			if(wea_i[3]) data_o[31:24] <= data_i[31:24];
		end
	end
end


generate
if(DEBUG_EN) begin

	// (* MARK_DEBUG="true" *) 
	(* MARK_DEBUG="true" *) reg[31:0]     reg_0_debug;
	(* MARK_DEBUG="true" *) reg[31:0]     reg_1_debug;
	(* MARK_DEBUG="true" *) reg[31:0]     reg_2_debug;
	(* MARK_DEBUG="true" *) reg[32-1:0]   addr_i_debug;
	(* MARK_DEBUG="true" *) reg[32-1:0]   data_o_debug;
	(* MARK_DEBUG="true" *) reg[32-1:0]   data_i_debug;
	(* MARK_DEBUG="true" *) reg           en_i_debug;
	(* MARK_DEBUG="true" *) reg           rst_i_debug;
	(* MARK_DEBUG="true" *) reg[32/8-1:0] wea_i_debug;


	always @(posedge clk_i) begin
		reg_0_debug  <= reg_0;
        reg_1_debug  <= reg_1;
        reg_2_debug  <= reg_2;
        addr_i_debug <= addr_i;
		data_o_debug <= data_o;
		data_i_debug <= data_i;
		en_i_debug   <= en_i;
		rst_i_debug  <= rst_i;
		wea_i_debug  <= wea_i;
	end
	
end
endgenerate

endmodule
`default_nettype wire
