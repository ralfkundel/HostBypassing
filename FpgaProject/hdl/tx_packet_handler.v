/*
Authors: Ralf Kundel, Kadir Eryigit, 2020

This module reads an axistream and writes the contents to a bram.
Additionally packet length information is generated for each axistream and output with a simple handshake protocol.
Each packet is also accompanied by a 2048byte aligned address.
The axi-stream supports ready signalling.
Each packet must be ackknowledged by the new packet output before a new axistream can be handled.
*/
`timescale 1ns / 1ps
`default_nettype none
module tx_packet_handler #(
    // parameter M_AXI_ID_WIDTH = 3,
    // parameter M_AXI_ADDR_WIDTH = 32,
    // parameter M_AXI_TDATA_WIDTH = 64,
    parameter NB_TX_DESC = 64,
    parameter DATA_WIDTH = 128,
    parameter DEBUG_EN = 0
    )(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 axi_clk CLK" *) (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axis_eth, ASSOCIATED_RESET axi_aresetn" *)
       input wire                                axi_clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 axi_aresetn RST" *) (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
       input wire                                axi_aresetn,

       input wire[64-1:0]                    s_axis_eth_tdata,      
       input wire[7:0]                       s_axis_eth_tuser,
       input wire                            s_axis_eth_tlast,
       input wire[64/8-1:0]                  s_axis_eth_tkeep,
       input wire                            s_axis_eth_tvalid,
       output reg                            s_axis_eth_tready,

      (* X_INTERFACE_INFO = "xilinx.com:interface:bram_rtl:1.0 MODE MASTER,NAME BRAM_PORT" *)
      (* X_INTERFACE_PARAMETER = "MASTER_TYPE BRAM_CTRL, MEM_ECC NONE, MEM_WIDTH 128, MEM_SIZE 131072, READ_LATENCY 1" *) //READ_WRITE_MODE READ_WRITE
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

       input wire                            init_i,
       input wire                            start_i,

       
       // input wire[31:0]                      pkt_base_addr_i,

       output reg[32-1:0]                    pkt_addr_o,
       output reg[15:0]                      pkt_len_o, // in bytes
       output reg                            xmit_req_o,
       input wire                            xmit_ack_i

  );

localparam IDLE          = 1,                                       
           NEW_PKT       = 2,                                      
           DATA          = 3, DATA_HI       = 3,
                              DATA_LO       = 4,
           PKT_REQ       = 5;

     
localparam AXIS_TDATA_WIDTH = 64;

reg[3:0]                    axi_state = IDLE;

localparam PKT_OFFS_WIDTH = $clog2(NB_TX_DESC);

reg[PKT_OFFS_WIDTH-1:0] pkt_offset = 0;
reg[15:0]  byte_count = 0;
reg[3:0]  add_bytes;

reg init;
reg init_done = 0;

assign clk_o = axi_clk;

always @(posedge axi_clk) begin
  if (~axi_aresetn) begin
    init      <= 1'b0;
  end else begin
    if(init_done)
      init <= 1'b0;
    if(init_i)
      init <= 1'b1;
  end
end




generate
  if(DATA_WIDTH == 64) begin


    always @(posedge axi_clk) begin
    if(~axi_aresetn) begin
        axi_state         <= IDLE;
        byte_count        <= 0;
        xmit_req_o        <= 1'b0;
        s_axis_eth_tready <= 1'b1;
        rst_o             <= 1'b0;
        wea_o             <= 0;
        wren_o            <= 1'b0;
        en_o              <= 1'b0;
        init_done         <= 1'b0;
    end else begin
        en_o  <= 1'b1;
        rst_o <= 1'b0;
        wea_o <= 16'h0000;
        wren_o            <= 1'b0;

        case(axi_state) 
            IDLE : begin //1
              s_axis_eth_tready <= 1'b1; //just drop all packets before start_i
              pkt_offset        <= 0;
              init_done         <= 1'b1;
              if( (start_i & ~init) & (s_axis_eth_tvalid & s_axis_eth_tlast | ~s_axis_eth_tvalid)) begin
                axi_state <= NEW_PKT;
              end
            end
            NEW_PKT : begin //2
              if(s_axis_eth_tvalid) begin //wait for incoming packet
                data_o            <= s_axis_eth_tdata;
                wea_o             <= s_axis_eth_tkeep;
                wren_o            <= |s_axis_eth_tkeep;
                byte_count        <= add_bytes;
                axi_state         <= DATA;
                addr_o            <= { {(32- PKT_OFFS_WIDTH-11){1'b0}}  ,pkt_offset,11'b00000000000};
                pkt_addr_o        <= { {(32- PKT_OFFS_WIDTH-11){1'b0}}  ,pkt_offset,11'b00000000000}; //add 2048 offset for each paket, so burst always stay inside 4k boundary(max packet length smaller than 2k);
                pkt_offset        <= pkt_offset + 1;
                if(s_axis_eth_tlast) begin
                  pkt_len_o         <= add_bytes;
                  xmit_req_o        <= 1'b1;
                  s_axis_eth_tready <= 1'b0;
                  axi_state         <= PKT_REQ;
                end
              end
              if(init)begin
                wea_o             <= 8'h00;
                wren_o            <= 1'b0;
                s_axis_eth_tready <= 1'b1;
                axi_state         <= IDLE;
              end
            end
            DATA : begin //3
             if(s_axis_eth_tvalid) begin //receive data
                data_o            <= s_axis_eth_tdata;
                wea_o             <= s_axis_eth_tkeep;
                wren_o            <= |s_axis_eth_tkeep;
                byte_count        <= add_bytes + byte_count;
                addr_o            <= addr_o + 8;
                if(s_axis_eth_tlast) begin
                  pkt_len_o         <= add_bytes + byte_count;
                  xmit_req_o        <= 1'b1;
                  s_axis_eth_tready <= 1'b0;
                  axi_state         <= PKT_REQ;
                end
              end
              if(init)begin
                wea_o             <= 8'h00;
                wren_o            <= 1'b0;
                s_axis_eth_tready <= 1'b1;
                axi_state         <= IDLE;
              end
            end
            PKT_REQ : begin //5
              if(xmit_ack_i) begin
                xmit_req_o        <= 1'b0;
                s_axis_eth_tready <= 1'b1;
                axi_state         <= NEW_PKT;
                if(init) begin
                  axi_state         <= IDLE;
                end
              end
            end
            default : begin
              s_axis_eth_tready <= 1'b1;
              xmit_req_o        <= 1'b0;
              axi_state         <= IDLE;
            end
        endcase
    end
end



  end else if(DATA_WIDTH == 128) begin
      

      always @(posedge axi_clk) begin
        if(~axi_aresetn) begin
            axi_state         <= IDLE;
            byte_count        <= 0;
            xmit_req_o        <= 1'b0;
            s_axis_eth_tready <= 1'b1;
            rst_o             <= 1'b0;
            wea_o             <= 0;
            wren_o            <= 1'b0;
            en_o              <= 1'b0;
            init_done         <= 1'b0;
        end else begin
            en_o   <= 1'b1;
            rst_o  <= 1'b0;
            wea_o  <= 16'h0000;
            wren_o <= 1'b0;

            case(axi_state)
                IDLE : begin //1
                  s_axis_eth_tready <= 1'b1; //just drop all packets before start_i
                  pkt_offset        <= 0;
                  init_done         <= 1'b1;
                  if( (~init & start_i) & (s_axis_eth_tvalid & s_axis_eth_tlast | ~s_axis_eth_tvalid) ) begin
                    axi_state <= NEW_PKT;
                  end
                end
                NEW_PKT : begin //2
                  if(s_axis_eth_tvalid) begin
                    data_o[63:0]      <= s_axis_eth_tdata;
                    wea_o             <= {8'h00,s_axis_eth_tkeep};
                    wren_o            <= |s_axis_eth_tkeep;
                    byte_count        <= add_bytes;
                    axi_state         <= DATA_HI;
                    addr_o            <= { {(32- PKT_OFFS_WIDTH-11){1'b0}}  ,pkt_offset,11'b00000000000};
                    pkt_addr_o        <= { {(32- PKT_OFFS_WIDTH-11){1'b0}}  ,pkt_offset,11'b00000000000}; //add 2048 offset for each paket, so burst always stay inside 4k boundary(max packet length smaller than 2k);
                    pkt_offset        <= pkt_offset + 1;
                    if(s_axis_eth_tlast) begin
                      pkt_len_o         <= add_bytes;
                      xmit_req_o        <= 1'b1;
                      s_axis_eth_tready <= 1'b0;
                      axi_state         <= PKT_REQ;
                    end
                  end
                  if(init)begin
                    wea_o             <= 16'h0000;
                    wren_o            <= 1'b0;
                    s_axis_eth_tready <= 1'b1;
                    axi_state         <= IDLE;
                  end
                end
                DATA_HI : begin  //3
                  if(s_axis_eth_tvalid) begin
                    data_o[127:64]      <= s_axis_eth_tdata;
                    wea_o               <= {s_axis_eth_tkeep,8'h00};
                    wren_o              <= |s_axis_eth_tkeep;
                    byte_count          <= byte_count + add_bytes;
                    axi_state           <= DATA_LO;
                    if(s_axis_eth_tlast) begin
                      pkt_len_o         <= byte_count + add_bytes;
                      xmit_req_o        <= 1'b1;
                      s_axis_eth_tready <= 1'b0;
                      axi_state         <= PKT_REQ;
                    end
                  end
                  if(init)begin
                    wea_o             <= 16'h0000;
                    wren_o            <= 1'b0;
                    s_axis_eth_tready <= 1'b1;
                    axi_state         <= IDLE;
                  end
                end
                DATA_LO : begin  //4
                  if(s_axis_eth_tvalid) begin
                    data_o[63:0] <= s_axis_eth_tdata;
                    addr_o       <= addr_o + 16;
                    wea_o        <= {8'h00,s_axis_eth_tkeep};
                    wren_o       <= |s_axis_eth_tkeep;
                    byte_count   <= byte_count + add_bytes;
                    axi_state    <= DATA_HI;
                    if(s_axis_eth_tlast) begin
                      pkt_len_o         <= byte_count + add_bytes;
                      xmit_req_o        <= 1'b1;
                      s_axis_eth_tready <= 1'b0;
                      axi_state         <= PKT_REQ;
                    end
                  end
                  if(init)begin
                    wea_o             <= 16'h0000;
                    wren_o            <= 1'b0;
                    s_axis_eth_tready <= 1'b1;
                    axi_state         <= IDLE;
                  end
                end
                PKT_REQ : begin //5
                  if(xmit_ack_i) begin
                    xmit_req_o        <= 1'b0;
                    s_axis_eth_tready <= 1'b1;
                    axi_state         <= NEW_PKT;
                  end
                  if(init) begin
                    xmit_req_o        <= 1'b0;
                    s_axis_eth_tready <= 1'b1;
                    axi_state         <= IDLE;
                  end
                  
                end
                default : begin
                  axi_state         <= IDLE;
                  xmit_req_o        <= 1'b0;
                  s_axis_eth_tready <= 1'b1;
                end
            endcase
        end
    end
  



  end
  
endgenerate


always @(*) begin
    casex(s_axis_eth_tkeep)
        8'b1xxxxxxx: add_bytes = 8;
        8'b01xxxxxx: add_bytes = 7;
        8'b001xxxxx: add_bytes = 6;
        8'b0001xxxx: add_bytes = 5;
        8'b00001xxx: add_bytes = 4;
        8'b000001xx: add_bytes = 3;
        8'b0000001x: add_bytes = 2;
        8'b00000001: add_bytes = 1;
        default    : add_bytes = 0;
    endcase
end




generate
  if(DEBUG_EN) begin
      // (* MARK_DEBUG="true" *) reg[AXIS_TDATA_WIDTH-1:0]      s_axis_eth_tdata_debug;      
      // (* MARK_DEBUG="true" *) reg[7:0]                       s_axis_eth_tuser_debug;
      // (* MARK_DEBUG="true" *) reg                            s_axis_eth_tlast_debug;
      // (* MARK_DEBUG="true" *) reg[AXIS_TDATA_WIDTH/8-1:0]    s_axis_eth_tkeep_debug;
      // (* MARK_DEBUG="true" *) reg                            s_axis_eth_tvalid_debug;
      // (* MARK_DEBUG="true" *) reg                            s_axis_eth_tready_debug;
      (* MARK_DEBUG="true" *) reg[32-1:0]                    pkt_addr_o_debug;
      (* MARK_DEBUG="true" *) reg[15:0]                      pkt_len_o_debug;
      (* MARK_DEBUG="true" *) reg                            xmit_req_o_debug;
      (* MARK_DEBUG="true" *) reg                            xmit_ack_i_debug;
      (* MARK_DEBUG="true" *) reg[PKT_OFFS_WIDTH-1:0]        pkt_offset_debug;
      (* MARK_DEBUG="true" *) reg[15:0]                      byte_count_debug;
      (* MARK_DEBUG="true" *) reg[3:0]                       add_bytes_debug;
      (* MARK_DEBUG="true" *) reg[2:0]                       axi_state_debug;
      (* MARK_DEBUG="true" *) reg                            init_done_debug;
      (* MARK_DEBUG="true" *) reg[DATA_WIDTH-1:0]            data_o_debug;
      (* MARK_DEBUG="true" *) reg                            en_o_debug;
      (* MARK_DEBUG="true" *) reg[DATA_WIDTH/8-1:0]          wea_o_debug;
      (* MARK_DEBUG="true" *) reg[32-1:0]                    addr_o_debug;

      always @(posedge axi_clk) begin
          // s_axis_eth_tdata_debug  <= s_axis_eth_tdata;
          // s_axis_eth_tuser_debug  <= s_axis_eth_tuser;
          // s_axis_eth_tlast_debug  <= s_axis_eth_tlast;
          // s_axis_eth_tkeep_debug  <= s_axis_eth_tkeep;
          // s_axis_eth_tvalid_debug <= s_axis_eth_tvalid;
          // s_axis_eth_tready_debug <= s_axis_eth_tready;
          pkt_addr_o_debug        <= pkt_addr_o;
          pkt_len_o_debug         <= pkt_len_o;
          xmit_req_o_debug        <= xmit_req_o;
          xmit_ack_i_debug        <= xmit_ack_i;
          pkt_offset_debug        <= pkt_offset;
          byte_count_debug        <= byte_count;
          add_bytes_debug         <= add_bytes;
          axi_state_debug         <= axi_state;
          init_done_debug         <= init_done;
          data_o_debug            <= data_o;
          en_o_debug              <= en_o;
          wea_o_debug             <= wea_o;
          addr_o_debug            <= addr_o;
      end
       
  end
endgenerate

endmodule
`default_nettype wire
