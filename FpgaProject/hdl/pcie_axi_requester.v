/*

Authors: Ralf Kundel, Kadir Eryigit, 2020
*/
module pcie_axi_requester#(

	parameter M_AXI_ID_WIDTH = 3,
	parameter M_AXI_ADDR_WIDTH = 32,
	parameter M_AXI_TDATA_WIDTH = 32,
    parameter DEBUG_EN = 0

	)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk_i CLK" *) (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF m_axi, ASSOCIATED_RESET rstn_i" *)
	input wire                               clk_i,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rstn_i RST" *) (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
	input wire                               rstn_i,
	
    output wire[M_AXI_ID_WIDTH-1:0]          m_axi_awid,
    output reg[M_AXI_ADDR_WIDTH-1 : 0]       m_axi_awaddr,
    output wire[7:0]                         m_axi_awlen,
    output wire[2:0]                         m_axi_awsize,
    output wire[1:0]                         m_axi_awburst,
    output reg                               m_axi_awvalid,
    input wire                               m_axi_awready,
 
    output reg[M_AXI_TDATA_WIDTH-1 : 0]      m_axi_wdata,
    output wire[M_AXI_TDATA_WIDTH/8-1 : 0]   m_axi_wstrb,
    output wire                              m_axi_wlast,
    output reg                               m_axi_wvalid,
    input wire                               m_axi_wready,
 
 
    input wire[M_AXI_ID_WIDTH-1:0]           m_axi_bid,
    input wire[1 : 0]                        m_axi_bresp,
    input wire                               m_axi_bvalid,
    output wire                              m_axi_bready,
 
    output wire[M_AXI_ID_WIDTH-1:0]          m_axi_arid,
    output reg[M_AXI_ADDR_WIDTH-1 : 0]       m_axi_araddr,
    output reg[7:0]                          m_axi_arlen,
    output wire[2:0]                         m_axi_arsize,
    output wire[1:0]                         m_axi_arburst,
    output reg                               m_axi_arvalid,
    input wire                               m_axi_arready,
 
    input wire[M_AXI_ID_WIDTH-1:0]           m_axi_rid,
    input wire[M_AXI_TDATA_WIDTH-1 : 0]      m_axi_rdata,
    input wire[1 : 0]                        m_axi_rresp,
    input wire                               m_axi_rlast,
    input wire                               m_axi_rvalid,
    output reg                               m_axi_rready,

    input wire                               r_req_v_i,
    input wire[31:0]                         r_addr_i,
    input wire[7:0]                          r_len_i,
    output reg                               r_ack_o,

    input wire[63:0]                         dma_phys_addr_i,
    input wire[31:0]                         dma_payload_i,

    input wire                               req_start_i,
    output reg                               req_ack_o

	);

localparam ARSIZE = $clog2(M_AXI_TDATA_WIDTH/8);
localparam AWSIZE = $clog2(M_AXI_TDATA_WIDTH/8);

assign m_axi_awlen   = 0;
assign m_axi_awid    = 0;
assign m_axi_awsize  = AWSIZE;
assign m_axi_awburst = 2'b01;   //INCR burst type
assign m_axi_bready  = 1'b1; 
assign m_axi_wlast   = 1'b1;

assign m_axi_arid    = 0;
assign m_axi_arsize  = ARSIZE;
assign m_axi_arburst = 2'b01;
assign m_axi_wstrb   = 4'hF;
wire[M_AXI_TDATA_WIDTH-1:0] wdata = dma_payload_i;
wire[M_AXI_ADDR_WIDTH-1:0] waddr = { 16'h0000, dma_phys_addr_i[15:0]};


localparam IDLE = 0,
           ADDR = 1,
           READY = 2, WRITE = 2;


reg[3:0] axi_r_state = IDLE;
reg[3:0] axi_w_state = IDLE;

always @(posedge clk_i) begin
	if (~rstn_i) begin
        axi_r_state   <= IDLE;
        r_ack_o       <= 1'b0;
        m_axi_arvalid <= 1'b0;
        m_axi_rready  <= 1'b0;
	end
	else begin
        m_axi_rready  <= 1'b1;
		case(axi_r_state) 
		IDLE: begin
			if(r_req_v_i) begin
                m_axi_araddr  <= r_addr_i;
                m_axi_arlen   <= r_len_i;
                m_axi_arvalid <= 1'b1;       
                r_ack_o       <= 1'b1;
                axi_r_state   <= ADDR;
            end
		end
		ADDR: begin
            r_ack_o <= 1'b0;
			if(m_axi_arready) begin
                m_axi_arvalid <= 1'b0;
                axi_r_state   <= IDLE;
            end
		end
		READY: begin
			
		end
		endcase
	end
end


always @(posedge clk_i) begin
    if (~rstn_i) begin
        m_axi_wvalid  <= 1'b0;
        m_axi_awvalid <= 1'b0;
        req_ack_o     <= 1'b0;
    end
    else begin
        req_ack_o <= 1'b0;
        case(axi_w_state)
        IDLE: begin
            if(req_start_i) begin
                req_ack_o     <= 1'b1;
                m_axi_awaddr  <= waddr;
                m_axi_wdata   <= wdata;
                m_axi_awvalid <= 1'b1;
                m_axi_wvalid  <= 1'b1;
                axi_w_state   <= ADDR;
            end
        end
        ADDR: begin
            if(m_axi_awready)
                m_axi_awvalid <= 1'b0;
            if(m_axi_wready)
                m_axi_wvalid <= 1'b0;
            if(~m_axi_awvalid & ~m_axi_wvalid)
                axi_w_state <= IDLE;
        end
        WRITE: begin
            
        end
        endcase
    end
end

generate
    if(DEBUG_EN) begin
        (* MARK_DEBUG = "true" *) reg[M_AXI_ADDR_WIDTH-1 : 0]       m_axi_awaddr_debug;
        (* MARK_DEBUG = "true" *) reg                               m_axi_awvalid_debug;
        (* MARK_DEBUG = "true" *) reg                               m_axi_awready_debug;
        (* MARK_DEBUG = "true" *) reg[M_AXI_TDATA_WIDTH-1 : 0]      m_axi_wdata_debug;
        (* MARK_DEBUG = "true" *) reg[M_AXI_TDATA_WIDTH/8-1 : 0]   m_axi_wstrb_debug;
        (* MARK_DEBUG = "true" *) reg                              m_axi_wlast_debug;
        (* MARK_DEBUG = "true" *) reg                               m_axi_wvalid_debug;
        (* MARK_DEBUG = "true" *) reg                               m_axi_wready_debug;
        (* MARK_DEBUG = "true" *) reg                               req_start_i_debug;
        (* MARK_DEBUG = "true" *) reg                               req_ack_o_debug;

        (* MARK_DEBUG = "true" *) reg[M_AXI_ID_WIDTH-1:0]           m_axi_bid_debug;
        (* MARK_DEBUG = "true" *) reg[1 : 0]                        m_axi_bresp_debug;
        (* MARK_DEBUG = "true" *) reg                               m_axi_bvalid_debug;
        (* MARK_DEBUG = "true" *) reg                              m_axi_bready_debug;



        always @(posedge clk_i) begin
            m_axi_awaddr_debug  <= m_axi_awaddr;
            m_axi_awvalid_debug <= m_axi_awvalid;
            m_axi_awready_debug <= m_axi_awready;
            m_axi_wdata_debug   <= m_axi_wdata;
            m_axi_wstrb_debug   <= m_axi_wstrb;
            m_axi_wlast_debug   <= m_axi_wlast;
            m_axi_wvalid_debug  <= m_axi_wvalid;
            m_axi_wready_debug  <= m_axi_wready;
            m_axi_bid_debug     <= m_axi_bid;
            m_axi_bresp_debug   <= m_axi_bresp;
            m_axi_bvalid_debug  <= m_axi_bvalid;
            m_axi_bready_debug  <= m_axi_bready;
            req_start_i_debug   <= req_start_i;
            req_ack_o_debug     <= req_ack_o;
        end
        
    end
endgenerate



endmodule
