/*
Authors: Ralf Kundel, Kadir Eryigit, 2020


Also see documentation PG194.
Initializes AXI to PCIe Address Translation Registers in Xilinx PCIe IP.
The PCIeIP requires a translation value to convert AXI-adresses on its AXI-Slave interface to PCIe physical addresses on the host system.
This value can be set inside the IP configurator in a static way or can be achieved dynamically during runtime through the AXI ctl interface of the IP.
The final pcie address will be comprised of this adress value and the AXI adresses used in the slave interface.
The upper part of the address is defined here. The lower part is defined in the AXI-adress of each AXI transaction.
The range of the lower part is defined through the Address Editor in Vivado in a static way.

For example: We define an address range of 64K for the Axi-Slave interface.
This means the lower 16 bits of the PCIe-transaction adress will be comprised of the lower 16-bit of the AXI-address.
The upper 16 bit will be defined by the value that is set through this module.

Address Editor: 64k range
AXI-address: CAFE_0123
AXI2PCIe-Translation address: BABE_0000
resulting PCIE-adress: BABE_0123

*/
`default_nettype none
module pcie_core_init #(
	parameter DEBUG_EN = 0
)(

(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk_i CLK" *) (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF m_axil, ASSOCIATED_RESET rst_i_n" *)
	input wire                            clk_i,
(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_i_n RST" *) (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
	input wire                            rst_i_n,

	output reg[12-1: 0]      m_axil_awaddr,
	output reg             m_axil_awvalid,
	input wire             m_axil_awready,

	output reg[32-1 : 0]   m_axil_wdata,
	output reg[32/8-1 : 0] m_axil_wstrb,
	output reg             m_axil_wvalid,
	input wire             m_axil_wready,

	input wire[1 : 0]      m_axil_bresp,
	input wire             m_axil_bvalid,
	output wire            m_axil_bready,

	output wire[12-1 : 0]   m_axil_araddr,
	output reg             m_axil_arvalid,
	input wire             m_axil_arready,

	input wire[32-1 : 0]   m_axil_rdata,
	input wire[1:0]        m_axil_rresp,
	input wire             m_axil_rvalid,
	output reg             m_axil_rready,

	input wire             init_i,
	input wire[63:0]       ram_base_addr_i,

	output reg             init_o

	);

// see PG194 doc - AXI Base Address Translation Configuration Registers
localparam AXIBAR2PCIEBAR_0U_OFFS = 12'h208;
localparam AXIBAR2PCIEBAR_0L_OFFS = 12'h20C;

assign m_axil_bready = 1'b1;

assign m_axil_araddr = 0;

localparam IDLE            = 1,
		   WRITE_AT_HI_REG = 2,
		   WRITE_AT_LO_REG = 3;


reg[1:0] axil_state = IDLE;


always @(posedge clk_i) begin
	if (~rst_i_n) begin
		axil_state     <= IDLE;     
		init_o         <= 1'b0;
		m_axil_wvalid  <= 1'b0;
		m_axil_awvalid <= 1'b0;
		m_axil_arvalid <= 1'b0;
		m_axil_rready  <= 1'b1;
	end
	else begin
		init_o <= 1'b0;
		if(m_axil_awvalid & m_axil_awready)
			m_axil_awvalid <= 1'b0;
		if(m_axil_wvalid & m_axil_wready)
			m_axil_wvalid <= 1'b0;
		case(axil_state)
		IDLE : begin
			m_axil_awaddr <= AXIBAR2PCIEBAR_0U_OFFS;
			m_axil_wdata  <= ram_base_addr_i[63:32];
			m_axil_wstrb  <= 4'hF;
			if(init_i) begin
				m_axil_wvalid  <= 1'b1;
				m_axil_awvalid <= 1'b1;
				axil_state     <= WRITE_AT_HI_REG;
			end
		end
		WRITE_AT_HI_REG : begin
			if(m_axil_awvalid & m_axil_awready) 
				m_axil_awaddr  <= AXIBAR2PCIEBAR_0L_OFFS;
			if(m_axil_wvalid & m_axil_wready) 
				m_axil_wdata  <= ram_base_addr_i[31:0];
			if(~m_axil_awvalid & ~m_axil_wvalid) begin
				m_axil_wvalid  <= 1'b1;
				m_axil_awvalid <= 1'b1;
				axil_state     <= WRITE_AT_LO_REG;
			end
		end
		WRITE_AT_LO_REG : begin
			if(~m_axil_awvalid & ~m_axil_wvalid) begin
				init_o     <= 1'b1;
				axil_state <= IDLE;
			end
		end
		endcase
	end
end

generate
	if(DEBUG_EN) begin

		(* MARK_DEBUG = "true" *) reg[12-1: 0]    m_axil_awaddr_debug;
		(* MARK_DEBUG = "true" *) reg             m_axil_awvalid_debug;
		(* MARK_DEBUG = "true" *) reg             m_axil_awready_debug;
		(* MARK_DEBUG = "true" *) reg[32-1 : 0]   m_axil_wdata_debug;
		(* MARK_DEBUG = "true" *) reg[32/8-1 : 0] m_axil_wstrb_debug;
		(* MARK_DEBUG = "true" *) reg             m_axil_wvalid_debug;
		(* MARK_DEBUG = "true" *) reg             m_axil_wready_debug;
		(* MARK_DEBUG = "true" *) reg[1 : 0]      m_axil_bresp_debug;
		(* MARK_DEBUG = "true" *) reg             m_axil_bvalid_debug;
		(* MARK_DEBUG = "true" *) reg             m_axil_bready_debug;
		(* MARK_DEBUG = "true" *) reg[12-1: 0]    m_axil_araddr_debug;
		(* MARK_DEBUG = "true" *) reg             m_axil_arvalid_debug;
		(* MARK_DEBUG = "true" *) reg             m_axil_arready_debug;
		(* MARK_DEBUG = "true" *) reg[32-1 : 0]   m_axil_rdata_debug;
		(* MARK_DEBUG = "true" *) reg[1:0]        m_axil_rresp_debug;
		(* MARK_DEBUG = "true" *) reg             m_axil_rvalid_debug;
		(* MARK_DEBUG = "true" *) reg             m_axil_rready_debug;
		(* MARK_DEBUG = "true" *) reg             init_i_debug;
		(* MARK_DEBUG = "true" *) reg[63:0]       ram_base_addr_i_debug;
		(* MARK_DEBUG = "true" *) reg             init_o_debug;

		always @(posedge clk_i) begin
			m_axil_awaddr_debug   <= m_axil_awaddr;
			m_axil_awvalid_debug  <= m_axil_awvalid;
			m_axil_awready_debug  <= m_axil_awready;
			m_axil_wdata_debug    <= m_axil_wdata;
			m_axil_wstrb_debug    <= m_axil_wstrb;
			m_axil_wvalid_debug   <= m_axil_wvalid;
			m_axil_wready_debug   <= m_axil_wready;
			m_axil_bresp_debug    <= m_axil_bresp;
			m_axil_bvalid_debug   <= m_axil_bvalid;
			m_axil_bready_debug   <= m_axil_bready;
			m_axil_araddr_debug   <= m_axil_araddr;
			m_axil_arvalid_debug  <= m_axil_arvalid;
			m_axil_arready_debug  <= m_axil_arready;
			m_axil_rdata_debug    <= m_axil_rdata;
			m_axil_rresp_debug    <= m_axil_rresp;
			m_axil_rvalid_debug   <= m_axil_rvalid;
			m_axil_rready_debug   <= m_axil_rready;
			init_i_debug          <= init_i;
			ram_base_addr_i_debug <= ram_base_addr_i;
			init_o_debug          <= init_o;
		end

	end
	
endgenerate
endmodule
