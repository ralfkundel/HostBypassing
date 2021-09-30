close_project -quiet
set outputDir [pwd]/vivado_project_U200
create_project DpdkHostBypassing $outputDir -part xcu200-fsgd2104-2-e -force
set_property board_part xilinx.com:au200:part0:1.3 [current_project]

# read verilog files
read_verilog [pwd]/hdl/configuration_registers.v
read_verilog [pwd]/hdl/rx_desc_ctrl.v
read_verilog [pwd]/hdl/rx_packet_handler.v
read_verilog [pwd]/hdl/tailpointer_delay.v
read_verilog [pwd]/hdl/tx_desc_ctrl.v
read_verilog [pwd]/hdl/tx_packet_handler.v
read_verilog [pwd]/hdl/pcie_core_init.v
read_verilog [pwd]/hdl/pcie_req_arbiter.v
read_verilog [pwd]/hdl/pcie_axi_requester.v


# create block design for combining the components
create_bd_design "hostBypassingReferenceArchitecture"

## create xilinx PCIe IP-core and pcie ref clock, pcie init module
create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.1 util_ds_buf_0
set_property -dict [list CONFIG.C_BUF_TYPE {IBUFDSGTE} CONFIG.DIFF_CLK_IN_BOARD_INTERFACE {pcie_refclk}] [get_bd_cells util_ds_buf_0]
make_bd_intf_pins_external  [get_bd_intf_pins util_ds_buf_0/CLK_IN_D]

create_bd_cell -type ip -vlnv xilinx.com:ip:xdma:4.1 xdma_0
set_property -dict [list CONFIG.functional_mode {AXI_Bridge} CONFIG.mode_selection {Advanced} CONFIG.pl_link_cap_max_link_width {X8} CONFIG.pl_link_cap_max_link_speed {8.0_GT/s} CONFIG.axi_addr_width {32} CONFIG.axi_data_width {256_bit} CONFIG.axisten_freq {250} CONFIG.pf0_device_id {9038} CONFIG.xdma_axilite_slave {true} CONFIG.SYS_RST_N_BOARD_INTERFACE {pcie_perstn} CONFIG.PCIE_BOARD_INTERFACE {pci_express_x8} CONFIG.en_gt_selection {true} CONFIG.coreclk_freq {500} CONFIG.plltype {QPLL1} CONFIG.c_m_axi_num_write {16} CONFIG.pf0_bar0_size {2} CONFIG.pf0_bar0_scale {Megabytes} CONFIG.PF0_DEVICE_ID_mqdma {9038} CONFIG.PF2_DEVICE_ID_mqdma {9038} CONFIG.PF3_DEVICE_ID_mqdma {9038} CONFIG.c_s_axi_supports_narrow_burst {true}] [get_bd_cells xdma_0]
make_bd_intf_pins_external  [get_bd_intf_pins xdma_0/pcie_mgt]
make_bd_pins_external  [get_bd_pins xdma_0/sys_rst_n]

connect_bd_net [get_bd_pins util_ds_buf_0/IBUF_DS_ODIV2] [get_bd_pins xdma_0/sys_clk]
connect_bd_net [get_bd_pins util_ds_buf_0/IBUF_OUT] [get_bd_pins xdma_0/sys_clk_gt]

create_bd_cell -type module -reference pcie_core_init pcie_core_init
connect_bd_intf_net [get_bd_intf_pins pcie_core_init/m_axil] [get_bd_intf_pins xdma_0/S_AXI_LITE]
connect_bd_net [get_bd_pins pcie_core_init/clk_i] [get_bd_pins xdma_0/axi_aclk]
connect_bd_net [get_bd_pins pcie_core_init/rst_i_n] [get_bd_pins xdma_0/axi_aresetn]



## create ring buffer brams, bram controllers, crossbar


### create rx ring
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_bram_ctrl_rx_ring
set_property -dict [list CONFIG.DATA_WIDTH {256} CONFIG.SINGLE_PORT_BRAM {1} CONFIG.ECC_TYPE {0}] [get_bd_cells axi_bram_ctrl_rx_ring]

create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 bram_rx_ring
set_property -dict [list CONFIG.Memory_Type {True_Dual_Port_RAM} CONFIG.Assume_Synchronous_Clk {true} CONFIG.Enable_B {Use_ENB_Pin} CONFIG.Use_RSTB_Pin {true} CONFIG.Port_B_Clock {100} CONFIG.Port_B_Write_Rate {50} CONFIG.Port_B_Enable_Rate {100} CONFIG.EN_SAFETY_CKT {false}] [get_bd_cells bram_rx_ring]

connect_bd_intf_net [get_bd_intf_pins bram_rx_ring/BRAM_PORTA] [get_bd_intf_pins axi_bram_ctrl_rx_ring/BRAM_PORTA]

### create tx ring
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_bram_ctrl_tx_ring
set_property -dict [list CONFIG.DATA_WIDTH {256} CONFIG.SINGLE_PORT_BRAM {1} CONFIG.ECC_TYPE {0}] [get_bd_cells axi_bram_ctrl_tx_ring]

create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 bram_tx_ring
set_property -dict [list CONFIG.Memory_Type {True_Dual_Port_RAM} CONFIG.Assume_Synchronous_Clk {true} CONFIG.Enable_B {Use_ENB_Pin} CONFIG.Use_RSTB_Pin {true} CONFIG.Port_B_Clock {100} CONFIG.Port_B_Write_Rate {50} CONFIG.Port_B_Enable_Rate {100} CONFIG.EN_SAFETY_CKT {false}] [get_bd_cells bram_tx_ring]

connect_bd_intf_net [get_bd_intf_pins bram_tx_ring/BRAM_PORTA] [get_bd_intf_pins axi_bram_ctrl_tx_ring/BRAM_PORTA]


### create rx packet buffer
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_bram_ctrl_rx_buffer
set_property -dict [list CONFIG.DATA_WIDTH {256} CONFIG.SINGLE_PORT_BRAM {1} CONFIG.ECC_TYPE {0}] [get_bd_cells axi_bram_ctrl_rx_buffer]

create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 bram_rx_buffer
set_property -dict [list CONFIG.Memory_Type {True_Dual_Port_RAM} CONFIG.Assume_Synchronous_Clk {true} CONFIG.Enable_B {Use_ENB_Pin} CONFIG.Use_RSTB_Pin {true} CONFIG.Port_B_Clock {100} CONFIG.Port_B_Write_Rate {50} CONFIG.Port_B_Enable_Rate {100} CONFIG.EN_SAFETY_CKT {false}] [get_bd_cells bram_rx_buffer]

connect_bd_intf_net [get_bd_intf_pins bram_rx_buffer/BRAM_PORTA] [get_bd_intf_pins axi_bram_ctrl_rx_buffer/BRAM_PORTA]


### create tx packet buffer
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_bram_ctrl_tx_buffer
set_property -dict [list CONFIG.DATA_WIDTH {256} CONFIG.SINGLE_PORT_BRAM {1} CONFIG.ECC_TYPE {0}] [get_bd_cells axi_bram_ctrl_tx_buffer]

create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 bram_tx_buffer
set_property -dict [list CONFIG.Memory_Type {True_Dual_Port_RAM} CONFIG.Assume_Synchronous_Clk {true} CONFIG.Enable_B {Use_ENB_Pin} CONFIG.Use_RSTB_Pin {true} CONFIG.Port_B_Clock {100} CONFIG.Port_B_Write_Rate {50} CONFIG.Port_B_Enable_Rate {100} CONFIG.EN_SAFETY_CKT {false}] [get_bd_cells bram_tx_buffer]

connect_bd_intf_net [get_bd_intf_pins bram_tx_buffer/BRAM_PORTA] [get_bd_intf_pins axi_bram_ctrl_tx_buffer/BRAM_PORTA]


### create configuration registers
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_bram_ctrl_configuration_registers
set_property -dict [list CONFIG.DATA_WIDTH {32} CONFIG.SINGLE_PORT_BRAM {1} CONFIG.ECC_TYPE {0}] [get_bd_cells axi_bram_ctrl_configuration_registers]

create_bd_cell -type module -reference configuration_registers configuration_registers

connect_bd_intf_net [get_bd_intf_pins configuration_registers/BRAM_PORT] [get_bd_intf_pins axi_bram_ctrl_configuration_registers/BRAM_PORTA]
connect_bd_net [get_bd_pins configuration_registers/init_o] [get_bd_pins pcie_core_init/init_i]
connect_bd_net [get_bd_pins pcie_core_init/ram_base_addr_i] [get_bd_pins configuration_registers/nic_base_addr_reg_o]
connect_bd_net [get_bd_pins xdma_0/axi_aresetn] [get_bd_pins configuration_registers/rst_i_n]


### create axi interconnect
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0
set_property -dict [list CONFIG.NUM_MI {5}] [get_bd_cells axi_interconnect_0]

connect_bd_intf_net [get_bd_intf_pins xdma_0/M_AXI_B] -boundary_type upper [get_bd_intf_pins axi_interconnect_0/S00_AXI]
connect_bd_net [get_bd_pins xdma_0/axi_aclk] [get_bd_pins axi_interconnect_0/ACLK]
connect_bd_net [get_bd_pins xdma_0/axi_aclk] [get_bd_pins axi_interconnect_0/S00_ACLK]
connect_bd_net [get_bd_pins xdma_0/axi_aclk] [get_bd_pins axi_interconnect_0/M00_ACLK]
connect_bd_net [get_bd_pins xdma_0/axi_aclk] [get_bd_pins axi_interconnect_0/M01_ACLK]
connect_bd_net [get_bd_pins xdma_0/axi_aclk] [get_bd_pins axi_interconnect_0/M02_ACLK]
connect_bd_net [get_bd_pins xdma_0/axi_aclk] [get_bd_pins axi_interconnect_0/M03_ACLK]
connect_bd_net [get_bd_pins xdma_0/axi_aclk] [get_bd_pins axi_interconnect_0/M04_ACLK]
connect_bd_net [get_bd_pins xdma_0/axi_aresetn] [get_bd_pins axi_interconnect_0/ARESETN]
connect_bd_net [get_bd_pins xdma_0/axi_aresetn] [get_bd_pins axi_interconnect_0/S00_ARESETN]
connect_bd_net [get_bd_pins xdma_0/axi_aresetn] [get_bd_pins axi_interconnect_0/M00_ARESETN]
connect_bd_net [get_bd_pins xdma_0/axi_aresetn] [get_bd_pins axi_interconnect_0/M01_ARESETN]
connect_bd_net [get_bd_pins xdma_0/axi_aresetn] [get_bd_pins axi_interconnect_0/M02_ARESETN]
connect_bd_net [get_bd_pins xdma_0/axi_aresetn] [get_bd_pins axi_interconnect_0/M03_ARESETN]
connect_bd_net [get_bd_pins xdma_0/axi_aresetn] [get_bd_pins axi_interconnect_0/M04_ARESETN]

connect_bd_intf_net -boundary_type upper [get_bd_intf_pins axi_interconnect_0/M00_AXI] [get_bd_intf_pins axi_bram_ctrl_rx_buffer/S_AXI]
connect_bd_intf_net -boundary_type upper [get_bd_intf_pins axi_interconnect_0/M01_AXI] [get_bd_intf_pins axi_bram_ctrl_tx_buffer/S_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_bram_ctrl_rx_ring/S_AXI] -boundary_type upper [get_bd_intf_pins axi_interconnect_0/M02_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_bram_ctrl_tx_ring/S_AXI] -boundary_type upper [get_bd_intf_pins axi_interconnect_0/M03_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_bram_ctrl_configuration_registers/S_AXI] -boundary_type upper [get_bd_intf_pins axi_interconnect_0/M04_AXI]

connect_bd_net [get_bd_pins axi_bram_ctrl_rx_ring/s_axi_aclk] [get_bd_pins xdma_0/axi_aclk]
connect_bd_net [get_bd_pins axi_bram_ctrl_rx_ring/s_axi_aresetn] [get_bd_pins xdma_0/axi_aresetn]
connect_bd_net [get_bd_pins axi_bram_ctrl_tx_ring/s_axi_aclk] [get_bd_pins xdma_0/axi_aclk]
connect_bd_net [get_bd_pins axi_bram_ctrl_tx_ring/s_axi_aresetn] [get_bd_pins xdma_0/axi_aresetn]
connect_bd_net [get_bd_pins axi_bram_ctrl_rx_buffer/s_axi_aclk] [get_bd_pins xdma_0/axi_aclk]
connect_bd_net [get_bd_pins axi_bram_ctrl_rx_buffer/s_axi_aresetn] [get_bd_pins xdma_0/axi_aresetn]
connect_bd_net [get_bd_pins axi_bram_ctrl_tx_buffer/s_axi_aclk] [get_bd_pins xdma_0/axi_aclk]
connect_bd_net [get_bd_pins axi_bram_ctrl_tx_buffer/s_axi_aresetn] [get_bd_pins xdma_0/axi_aresetn]
connect_bd_net [get_bd_pins axi_bram_ctrl_configuration_registers/s_axi_aclk] [get_bd_pins xdma_0/axi_aclk]
connect_bd_net [get_bd_pins axi_bram_ctrl_configuration_registers/s_axi_aresetn] [get_bd_pins xdma_0/axi_aresetn]


## create writeback logic
create_bd_cell -type module -reference pcie_req_arbiter pcie_req_arbiter
create_bd_cell -type module -reference pcie_axi_requester pcie_axi_requester
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dwidth_converter:2.1 axi_dwidth_converter_0

set_property -dict [list CONFIG.PROTOCOL.VALUE_SRC USER CONFIG.READ_WRITE_MODE.VALUE_SRC USER CONFIG.ADDR_WIDTH.VALUE_SRC USER CONFIG.SI_DATA_WIDTH.VALUE_SRC USER CONFIG.MI_DATA_WIDTH.VALUE_SRC USER CONFIG.SI_ID_WIDTH.VALUE_SRC USER] [get_bd_cells axi_dwidth_converter_0]
set_property -dict [list CONFIG.MI_DATA_WIDTH {256} CONFIG.SI_ID_WIDTH {3}] [get_bd_cells axi_dwidth_converter_0]

connect_bd_net [get_bd_pins pcie_req_arbiter/clk_i] [get_bd_pins xdma_0/axi_aclk]
connect_bd_net [get_bd_pins pcie_axi_requester/clk_i] [get_bd_pins xdma_0/axi_aclk]
connect_bd_net [get_bd_pins pcie_axi_requester/rstn_i] [get_bd_pins xdma_0/axi_aresetn]
connect_bd_net [get_bd_pins pcie_req_arbiter/rst_i_n] [get_bd_pins xdma_0/axi_aresetn]
connect_bd_net [get_bd_pins pcie_req_arbiter/pcie_addr_o] [get_bd_pins pcie_axi_requester/dma_phys_addr_i]
connect_bd_net [get_bd_pins pcie_req_arbiter/pcie_data_o] [get_bd_pins pcie_axi_requester/dma_payload_i]
connect_bd_net [get_bd_pins pcie_req_arbiter/pcie_valid_o] [get_bd_pins pcie_axi_requester/req_start_i]
connect_bd_net [get_bd_pins axi_dwidth_converter_0/s_axi_aclk] [get_bd_pins xdma_0/axi_aclk]
connect_bd_net [get_bd_pins axi_dwidth_converter_0/s_axi_aresetn] [get_bd_pins xdma_0/axi_aresetn]
connect_bd_net [get_bd_pins pcie_axi_requester/req_ack_o] [get_bd_pins pcie_req_arbiter/pcie_ack_i]

connect_bd_intf_net [get_bd_intf_pins pcie_axi_requester/m_axi] [get_bd_intf_pins axi_dwidth_converter_0/S_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dwidth_converter_0/M_AXI] [get_bd_intf_pins xdma_0/S_AXI_B]

## create rx logic

create_bd_cell -type module -reference rx_packet_handler rx_packet_handler_0
create_bd_cell -type module -reference rx_desc_ctrl rx_desc_ctrl_0

connect_bd_net [get_bd_pins rx_packet_handler_0/pkt_ack_o] [get_bd_pins rx_desc_ctrl_0/pkt_ack_i]
connect_bd_net [get_bd_pins rx_packet_handler_0/pkt_addr_i] [get_bd_pins rx_desc_ctrl_0/pkt_addr_o]
connect_bd_net [get_bd_pins rx_packet_handler_0/pkt_len_i] [get_bd_pins rx_desc_ctrl_0/pkt_len_o]
connect_bd_net [get_bd_pins rx_desc_ctrl_0/pkt_addr_v_o] [get_bd_pins rx_packet_handler_0/pkt_addr_v_i]
connect_bd_net [get_bd_pins rx_desc_ctrl_0/clk_i] [get_bd_pins xdma_0/axi_aclk]
connect_bd_net [get_bd_pins rx_packet_handler_0/axi_clk] [get_bd_pins xdma_0/axi_aclk]
connect_bd_net [get_bd_pins rx_packet_handler_0/axi_aresetn] [get_bd_pins xdma_0/axi_aresetn]
connect_bd_net [get_bd_pins rx_desc_ctrl_0/rst_i_n] [get_bd_pins xdma_0/axi_aresetn]

connect_bd_intf_net [get_bd_intf_pins rx_desc_ctrl_0/BRAM_PORT] [get_bd_intf_pins bram_rx_ring/BRAM_PORTB]
connect_bd_intf_net [get_bd_intf_pins rx_packet_handler_0/BRAM_PORT] [get_bd_intf_pins bram_rx_buffer/BRAM_PORTB]

create_bd_cell -type module -reference tailpointer_delay tailpointer_delay_rx
connect_bd_net [get_bd_pins tailpointer_delay_rx/clk_i] [get_bd_pins xdma_0/axi_aclk]
connect_bd_net [get_bd_pins tailpointer_delay_rx/rstn_i] [get_bd_pins xdma_0/axi_aresetn]
connect_bd_net [get_bd_pins rx_desc_ctrl_0/nic_phys_addr_o] [get_bd_pins tailpointer_delay_rx/s_phys_addr_i]
connect_bd_net [get_bd_pins rx_desc_ctrl_0/nic_rx_tail_pointer_o] [get_bd_pins tailpointer_delay_rx/s_tail_pointer_i]
connect_bd_net [get_bd_pins rx_desc_ctrl_0/pcie_rq_start_o] [get_bd_pins tailpointer_delay_rx/s_pcie_write_i]
connect_bd_net [get_bd_pins tailpointer_delay_rx/s_pcie_write_ack_o] [get_bd_pins rx_desc_ctrl_0/pcie_rq_ack_i]

connect_bd_net [get_bd_pins tailpointer_delay_rx/m_phys_addr_o] [get_bd_pins pcie_req_arbiter/pcie_addr0_i]
connect_bd_net [get_bd_pins tailpointer_delay_rx/m_tail_pointer_o] [get_bd_pins pcie_req_arbiter/pcie_data0_i]
connect_bd_net [get_bd_pins tailpointer_delay_rx/m_pcie_write_o] [get_bd_pins pcie_req_arbiter/pcie_valid0_i]
connect_bd_net [get_bd_pins pcie_req_arbiter/fifo_ready0_o] [get_bd_pins tailpointer_delay_rx/m_pcie_write_ack_i]

connect_bd_net [get_bd_pins rx_desc_ctrl_0/nic_base_addr_i] [get_bd_pins configuration_registers/nic_base_addr_reg_o]
connect_bd_net [get_bd_pins rx_desc_ctrl_0/fpga_base_addr_i] [get_bd_pins configuration_registers/fpga_base_addr_reg_o]
connect_bd_net [get_bd_pins rx_desc_ctrl_0/start_i] [get_bd_pins configuration_registers/start_o]
connect_bd_net [get_bd_pins pcie_core_init/init_o] [get_bd_pins rx_desc_ctrl_0/init_i]



## create tx logic
create_bd_cell -type module -reference tx_desc_ctrl tx_desc_ctrl_0
create_bd_cell -type module -reference tx_packet_handler tx_packet_handler_0

connect_bd_net [get_bd_pins tx_desc_ctrl_0/clk_i] [get_bd_pins xdma_0/axi_aclk]
connect_bd_net [get_bd_pins tx_desc_ctrl_0/rst_i_n] [get_bd_pins xdma_0/axi_aresetn]
connect_bd_net [get_bd_pins tx_packet_handler_0/axi_clk] [get_bd_pins xdma_0/axi_aclk]
connect_bd_net [get_bd_pins tx_packet_handler_0/axi_aresetn] [get_bd_pins xdma_0/axi_aresetn]
connect_bd_net [get_bd_pins tx_packet_handler_0/pkt_addr_o] [get_bd_pins tx_desc_ctrl_0/pkt_addr_i]
connect_bd_net [get_bd_pins tx_desc_ctrl_0/pkt_len_i] [get_bd_pins tx_packet_handler_0/pkt_len_o]
connect_bd_net [get_bd_pins tx_packet_handler_0/xmit_req_o] [get_bd_pins tx_desc_ctrl_0/xmit_req_i]
connect_bd_net [get_bd_pins tx_packet_handler_0/xmit_ack_i] [get_bd_pins tx_desc_ctrl_0/xmit_ack_o]


connect_bd_intf_net [get_bd_intf_pins tx_packet_handler_0/BRAM_PORT] [get_bd_intf_pins bram_tx_buffer/BRAM_PORTB]
connect_bd_intf_net [get_bd_intf_pins tx_desc_ctrl_0/BRAM_PORT] [get_bd_intf_pins bram_tx_ring/BRAM_PORTB]

connect_bd_net [get_bd_pins tx_desc_ctrl_0/nic_base_addr_i] [get_bd_pins configuration_registers/nic_base_addr_reg_o]
connect_bd_net [get_bd_pins tx_desc_ctrl_0/fpga_base_addr_i] [get_bd_pins configuration_registers/fpga_base_addr_reg_o]
connect_bd_net [get_bd_pins configuration_registers/start_o] [get_bd_pins tx_packet_handler_0/start_i]
connect_bd_net [get_bd_pins configuration_registers/start_o] [get_bd_pins tx_desc_ctrl_0/start_i]
connect_bd_net [get_bd_pins tx_desc_ctrl_0/init_i] [get_bd_pins pcie_core_init/init_o]
connect_bd_net [get_bd_pins tx_packet_handler_0/init_i] [get_bd_pins pcie_core_init/init_o]

create_bd_cell -type module -reference tailpointer_delay tailpointer_delay_tx
connect_bd_net [get_bd_pins tailpointer_delay_tx/clk_i] [get_bd_pins xdma_0/axi_aclk]
connect_bd_net [get_bd_pins tailpointer_delay_tx/rstn_i] [get_bd_pins xdma_0/axi_aresetn]
connect_bd_net [get_bd_pins tx_desc_ctrl_0/nic_phys_addr_o] [get_bd_pins tailpointer_delay_tx/s_phys_addr_i]
connect_bd_net [get_bd_pins tx_desc_ctrl_0/nic_tx_tail_pointer_o] [get_bd_pins tailpointer_delay_tx/s_tail_pointer_i]
connect_bd_net [get_bd_pins tx_desc_ctrl_0/pcie_rq_start_o] [get_bd_pins tailpointer_delay_tx/s_pcie_write_i]
connect_bd_net [get_bd_pins tx_desc_ctrl_0/pcie_rq_ack_i] [get_bd_pins tailpointer_delay_tx/s_pcie_write_ack_o]

connect_bd_net [get_bd_pins pcie_req_arbiter/pcie_addr1_i] [get_bd_pins tailpointer_delay_tx/m_phys_addr_o]
connect_bd_net [get_bd_pins tailpointer_delay_tx/m_tail_pointer_o] [get_bd_pins pcie_req_arbiter/pcie_data1_i]
connect_bd_net [get_bd_pins tailpointer_delay_tx/m_pcie_write_o] [get_bd_pins pcie_req_arbiter/pcie_valid1_i]
connect_bd_net [get_bd_pins pcie_req_arbiter/fifo_ready1_o] [get_bd_pins tailpointer_delay_tx/m_pcie_write_ack_i]


## sample network function

create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 sample_network_function
connect_bd_intf_net [get_bd_intf_pins rx_packet_handler_0/m_axis_eth] [get_bd_intf_pins sample_network_function/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins sample_network_function/M_AXIS] [get_bd_intf_pins tx_packet_handler_0/s_axis_eth]
connect_bd_net [get_bd_pins sample_network_function/s_axis_aresetn] [get_bd_pins xdma_0/axi_aresetn]
connect_bd_net [get_bd_pins sample_network_function/s_axis_aclk] [get_bd_pins xdma_0/axi_aclk]

### asign addresses
assign_bd_address [get_bd_addr_segs {xdma_0/S_AXI_B/BAR0 }]
set_property offset 0x00000000 [get_bd_addr_segs {pcie_axi_requester/m_axi/SEG_xdma_0_BAR0}]
set_property range 64K [get_bd_addr_segs {pcie_axi_requester/m_axi/SEG_xdma_0_BAR0}]

assign_bd_address [get_bd_addr_segs {xdma_0/S_AXI_LITE/CTL0 }]

assign_bd_address [get_bd_addr_segs {axi_bram_ctrl_configuration_registers/S_AXI/Mem0 }]
set_property range 4K [get_bd_addr_segs {xdma_0/M_AXI_B/SEG_axi_bram_ctrl_configuration_registers_Mem0}]
set_property offset 0x00102000 [get_bd_addr_segs {xdma_0/M_AXI_B/SEG_axi_bram_ctrl_configuration_registers_Mem0}]

assign_bd_address [get_bd_addr_segs {axi_bram_ctrl_rx_buffer/S_AXI/Mem0 }]
set_property range 512K [get_bd_addr_segs {xdma_0/M_AXI_B/SEG_axi_bram_ctrl_rx_buffer_Mem0}]
set_property offset 0x00000000 [get_bd_addr_segs {xdma_0/M_AXI_B/SEG_axi_bram_ctrl_rx_buffer_Mem0}]

assign_bd_address [get_bd_addr_segs {axi_bram_ctrl_rx_ring/S_AXI/Mem0 }]
set_property range 4K [get_bd_addr_segs {xdma_0/M_AXI_B/SEG_axi_bram_ctrl_rx_ring_Mem0}]
set_property offset 0x00100000 [get_bd_addr_segs {xdma_0/M_AXI_B/SEG_axi_bram_ctrl_rx_ring_Mem0}]

assign_bd_address [get_bd_addr_segs {axi_bram_ctrl_tx_buffer/S_AXI/Mem0 }]
set_property offset 0x00080000 [get_bd_addr_segs {xdma_0/M_AXI_B/SEG_axi_bram_ctrl_tx_buffer_Mem0}]
set_property range 512K [get_bd_addr_segs {xdma_0/M_AXI_B/SEG_axi_bram_ctrl_tx_buffer_Mem0}]

assign_bd_address [get_bd_addr_segs {axi_bram_ctrl_tx_ring/S_AXI/Mem0 }]
set_property range 4K [get_bd_addr_segs {xdma_0/M_AXI_B/SEG_axi_bram_ctrl_tx_ring_Mem0}]
set_property offset 0x00101000 [get_bd_addr_segs {xdma_0/M_AXI_B/SEG_axi_bram_ctrl_tx_ring_Mem0}]

save_bd_design
validate_bd_design
regenerate_bd_layout
save_bd_design

close_bd_design [get_bd_designs hostBypassingReferenceArchitecture]

make_wrapper -files [get_files [pwd]/vivado_project_U200/DpdkHostBypassing.srcs/sources_1/bd/hostBypassingReferenceArchitecture/hostBypassingReferenceArchitecture.bd] -top
add_files -norecurse [pwd]/vivado_project_U200/DpdkHostBypassing.srcs/sources_1/bd/hostBypassingReferenceArchitecture/hdl/hostBypassingReferenceArchitecture_wrapper.v
set_property top hostBypassingReferenceArchitecture_wrapper [current_fileset]


