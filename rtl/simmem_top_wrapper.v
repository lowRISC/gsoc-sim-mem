// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Simulated memory controller top-level Verilog wrapper

// This is a Verilog wrapper to integrate the module as a block in Xilinx Vivado.

module simmem_top_wrapper #(
    // Width of the main memory capacity, i.e., of an address in main memory.
    parameter GlobalMemCapaW = 19,
    // Main memory capacity, in bytes.
    parameter GlobalMemCapa = 1 << GlobalMemCapaW,

    /////////////////
    // AXI signals //
    /////////////////

    parameter IDWidth = 2,
    parameter NumIds = 1 << IDWidth,
    // No ID tag in the write data
    parameter WIDWidth = 0,

    // Address field widths
    parameter AxAddrWidth = GlobalMemCapaW,
    parameter AxLenWidth = 8,
    parameter AxSizeWidth = 3,
    parameter AxBurstWidth = 2,
    parameter AxLockWidth = 2,
    parameter AxCacheWidth = 4,
    parameter AxProtWidth = 4,
    parameter AxQoSWidth = 4,
    parameter AxRegionWidth = 4,
    parameter AwUserWidth = 0,
    parameter ArUserWidth = 0,

    // Data & response field widths
    parameter MaxBurstSizeBytes = 4,
    parameter MaxBurstSizeBits = MaxBurstSizeBytes * 8,
    parameter XLastWidth = 1,
    parameter XRespWidth = 3,
    parameter WUserWidth = 0,
    parameter RUserWidth = 0,
    parameter BUserWidth = 0,

    parameter WStrbWidth = MaxBurstSizeBytes
  ) (
    input clk_i,
    input rst_ni,

    // Normally AXI is automatically inferred.  However, if the names of
    // your ports do not match, you can force the
    // the creation of an interface and map the physical ports to the
    // logical ports by using the X_INTERFACE_INFO
    // attribute before each physical port
    // Typical parameters the user might specify: PROTOCOL {AXI4, AXI4LITE,
    // AXI3}, SUPPORTS_NARROW_BURST {0, 1}, NUM_READ_OUTSTANDING,
    // NUM_WRITE_OUTSTANDING, MAX_BURST_LENGTH
    // The PROTOCOL can typically be inferred from the set of signals.
    // aximm - AMBA AXI Interface (slave directions)
    //
    // Allowed parameters:
    //  CLK_DOMAIN                - Clk Domain                (string default: <blank>)
    //  PHASE                     - Phase                     (float)
    //  MAX_BURST_LENGTH          - Max Burst Length          (long default: 256) [1, 256]
    //  NUM_WRITE_OUTSTANDING     - Num Write Outstanding     (long default: 1) [0, 32]
    //  NUM_READ_OUTSTANDING      - Num Read Outstanding      (long default: 1) [0, 32]
    //  SUPPORTS_NARROW_BURST     - Supports Narrow Burst     (long default: 1) [0, 1]
    //  READ_WRITE_MODE           - Read Write Mode           (string default: READ_WRITE) {READ_WRITE,READ_ONLY,WRITE_ONLY}
    //  BUSER_WIDTH               - Buser Width               (long)
    //  RUSER_WIDTH               - Ruser Width               (long)
    //  WUSER_WIDTH               - Wuser Width               (long)
    //  ARUSER_WIDTH              - Aruser Width              (long)
    //  AWUSER_WIDTH              - Awuser Width              (long)
    //  ADDR_WIDTH                - Addr Width                (long default: 32) [1, 64]
    //  ID_WIDTH                  - Id Width                  (long)
    //  FREQ_HZ                   - Frequency                 (float default: 100000000)
    //  PROTOCOL                  - Protocol                  (string default: AXI4) {AXI4,AXI4LITE,AXI3}
    //  DATA_WIDTH                - Data Width                (long default: 32) {32,64,128,256,512,1024}
    //  HAS_BURST                 - Has BURST                 (long default: 1) {0,1}
    //  HAS_CACHE                 - Has CACHE                 (long default: 1) {0,1}
    //  HAS_LOCK                  - Has LOCK                  (long default: 1) {0,1}
    //  HAS_PROT                  - Has PROT                  (long default: 1) {0,1}
    //  HAS_QOS                   - Has QOS                   (long default: 1) {0,1}
    //  HAS_REGION                - Has REGION                (long default: 1) {0,1}
    //  HAS_WSTRB                 - Has WSTRB                 (long default: 1) {0,1}
    //  HAS_BRESP                 - Has BRESP                 (long default: 1) {0,1}
    //  HAS_RRESP                 - Has RRESP                 (long default: 1) {0,1}
  // Uncomment the following to set interface specific parameter on the bus interface.
  //  (* X_INTERFACE_PARAMETER = "CLK_DOMAIN <value>,PHASE
  // <value>,MAX_BURST_LENGTH <value>,NUM_WRITE_OUTSTANDING
  // <value>,NUM_READ_OUTSTANDING <value>,SUPPORTS_NARROW_BURST
  // <value>,READ_WRITE_MODE <value>,BUSER_WIDTH <value>,RUSER_WIDTH
  // <value>,WUSER_WIDTH <value>,ARUSER_WIDTH <value>,AWUSER_WIDTH
  // <value>,ADDR_WIDTH <value>,ID_WIDTH <value>,FREQ_HZ <value>,PROTOCOL
  // <value>,DATA_WIDTH <value>,HAS_BURST <value>,HAS_CACHE <value>,HAS_LOCK
  // <value>,HAS_PROT <value>,HAS_QOS <value>,HAS_REGION <value>,HAS_WSTRB
  // <value>,HAS_BRESP <value>,HAS_RRESP <value>" *)

  // From the requester
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s AWID" *)
  input [IDWidth-1:0] s_awid, // Write address ID
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s AWADDR" *)
  input [AxAddrWidth-1:0] s_awaddr, // Write address
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s AWLEN" *)
  input [AxLenWidth-1:0] s_awlen, // Burst length
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s AWSIZE" *)
  input [2:0] s_awsize, // Burst size
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s AWBURST" *)
  input [1:0] s_awburst, // Burst type
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s AWLOCK" *)
  input [AxLockWidth-1:0] s_awlock, // Lock type
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s AWCACHE" *)
  input [3:0] s_awcache, // Cache type
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s AWPROT" *)
  input [2:0] s_awprot, // Protection type
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s AWREGION" *)
  input [3:0] s_awregion, // Write address slave region
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s AWQOS" *)
  input [3:0] s_awqos, // Transaction Quality of Service token
  // (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s AWUSER" *)
  // input [AwUserWidth-1:0] s_awuser, // Write address user sideband (optional)
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s AWVALID" *)
  input s_awvalid, // Write address valid
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s AWREADY" *)
  output s_awready, // Write address ready
  // (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s WID" *)
  // input [WIDWidth-1:0] s_wid, // Write ID tag (optional)
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s WDATA" *)
  input [AxSizeWidth-1:0] s_wdata, // Write data
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s WSTRB" *)
  input [WStrbWidth-1:0] s_wstrb, // Write strobes
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s WLAST" *)
  input s_wlast, // Write last beat
  // (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s WUSER" *)
  // input [WUserWidth-1:0] s_wuser, // Write data user sideband (optional)
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s WVALID" *)
  input s_wvalid, // Write valid
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s WREADY" *)
  output s_wready, // Write ready
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s BID" *)
  output [IDWidth-1:0] s_bid, // Response ID
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s BRESP" *)
  output [1:0] s_bresp, // Write response
  // (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s BUSER" *)
  // output [BUserWidth-1:0] s_buser, // Write response user sideband (optional)
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s BVALID" *)
  output s_bvalid, // Write response valid
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s BREADY" *)
  input s_bready, // Write response ready
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s ARID" *)
  input [IDWidth-1:0] s_arid, // Read address ID
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s ARADDR" *)
  input [AxAddrWidth-1:0] s_araddr, // Read address
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s ARLEN" *)
  input [AxLenWidth-1:0] s_arlen, // Burst length
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s ARSIZE" *)
  input [2:0] s_arsize, // Burst size
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s ARBURST" *)
  input [1:0] s_arburst, // Burst type
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s ARLOCK" *)
  input [AxLockWidth-1:0] s_arlock, // Lock type
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s ARCACHE" *)
  input [3:0] s_arcache, // Cache type
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s ARPROT" *)
  input [2:0] s_arprot, // Protection type
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s ARREGION" *)
  input [3:0] s_arregion, // Read address slave region
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s ARQOS" *)
  input [3:0] s_arqos, // Quality of service token
  // (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s ARUSER" *)
  // input [RUserWidth-1:0] s_aruser, // Read address user sideband (optional)
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s ARVALID" *)
  input s_arvalid, // Read address valid
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s ARREADY" *)
  output s_arready, // Read address ready
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s RID" *)
  output [IDWidth-1:0] s_rid, // Read ID tag
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s RDATA" *)
  output [MaxBurstSizeBits-1:0] s_rdata, // Read data
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s RRESP" *)
  output [1:0] s_rresp, // Read response
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s RLAST" *)
  output s_rlast, // Read last beat
  // (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s RUSER" *)
  // output [RUserWidth-1:0] s_ruser, // Read user sideband (optional)
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s RVALID" *)
  output s_rvalid, // Read valid
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s RREADY" *)
  input s_rready, // Read ready

  // To the real memory controller
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m AWID" *)
  output [IDWidth-1:0] m_awid, // Write address ID
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m AWADDR" *)
  output [AxAddrWidth-1:0] m_awaddr, // Write address
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m AWLEN" *)
  output [AxLenWidth-1:0] m_awlen, // Burst length
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m AWSIZE" *)
  output [2:0] m_awsize, // Burst size
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m AWBURST" *)
  output [1:0] m_awburst, // Burst type
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m AWLOCK" *)
  output [AxLockWidth-1:0] m_awlock, // Lock type
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m AWCACHE" *)
  output [3:0] m_awcache, // Cache type
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m AWPROT" *)
  output [2:0] m_awprot, // Protection type
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m AWREGION" *)
  output [3:0] m_awregion, // Write address slave region
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m AWQOS" *)
  output [3:0] m_awqos, // Transaction Quality of Service token
  // (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m AWUSER" *)
  // output [AwUserWidth-1:0] m_awuser, // Write address user sideband (optional)
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m AWVALID" *)
  output m_awvalid, // Write address valid
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m AWREADY" *)
  input m_awready, // Write address ready
  // (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m WID" *)
  // output [WIDWidth-1:0] m_wid, // Write ID tag (optional)
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m WDATA" *)
  output [AxSizeWidth-1:0] m_wdata, // Write data
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m WSTRB" *)
  output [WStrbWidth-1:0] m_wstrb, // Write strobes
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m WLAST" *)
  output m_wlast, // Write last beat
  // (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m WUSER" *)
  // output [WUserWidth-1:0] m_wuser, // Write data user sideband (optional)
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m WVALID" *)
  output m_wvalid, // Write valid
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m WREADY" *)
  input m_wready, // Write ready
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m BID" *)
  input [IDWidth-1:0] m_bid, // Response ID
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m BRESP" *)
  input [1:0] m_bresp, // Write response
  // (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m BUSER" *)
  // input [BUserWidth-1:0] m_buser, // Write response user sideband (optional)
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m BVALID" *)
  input m_bvalid, // Write response valid
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m BREADY" *)
  output m_bready, // Write response ready
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m ARID" *)
  output [IDWidth-1:0] m_arid, // Read address ID
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m ARADDR" *)
  output [AxAddrWidth-1:0] m_araddr, // Read address
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m ARLEN" *)
  output [AxLenWidth-1:0] m_arlen, // Burst length
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m ARSIZE" *)
  output [2:0] m_arsize, // Burst size
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m ARBURST" *)
  output [1:0] m_arburst, // Burst type
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m ARLOCK" *)
  output [AxLockWidth-1:0] m_arlock, // Lock type
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m ARCACHE" *)
  output [3:0] m_arcache, // Cache type
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m ARPROT" *)
  output [2:0] m_arprot, // Protection type
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m ARREGION" *)
  output [3:0] m_arregion, // Read address slave region
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m ARQOS" *)
  output [3:0] m_arqos, // Quality of service token
  // (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m ARUSER" *)
  // output [RUserWidth-1:0] m_aruser, // Read address user sideband (optional)
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m ARVALID" *)
  output m_arvalid, // Read address valid
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m ARREADY" *)
  input m_arready, // Read address ready
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m RID" *)
  input [IDWidth-1:0] m_rid, // Read ID tag
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m RDATA" *)
  input [MaxBurstSizeBits-1:0] m_rdata, // Read data
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m RRESP" *)
  input [1:0] m_rresp, // Read response
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m RLAST" *)
  input m_rlast, // Read last beat
  // (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m RUSER" *)
  // input [RUserWidth-1:0] m_ruser, // Read user sideband (optional)
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m RVALID" *)
  input m_rvalid, // Read valid
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m RREADY" *)
  output m_rready // Read ready
);

  import simmem_top::waddr_t;
  import simmem_top::raddr_t;
  import simmem_top::wdata_t;
  import simmem_top::rdata_all_fields_t;
  import simmem_top::wrsp_merged_payload_t;

  waddr_t s_waddr;
  waddr_t m_waddr;
  raddr_t s_raddr;
  raddr_t m_raddr;
  wdata_t s_wdata;
  wdata_t m_wdata;
  rdata_all_fields_t s_rdata;
  rdata_all_fields_t m_rdata;
  wrsp_merged_payload_t s_wrsp;
  wrsp_merged_payload_t m_wrsp;

  assign s_waddr.id = s_awid;
  assign m_waddr.id = m_awid;
  assign s_waddr.addr = s_awaddr;
  assign m_waddr.addr = m_awaddr;
  assign s_waddr.burst_len = s_awlen;
  assign m_waddr.burst_len = m_awlen;
  assign s_waddr.burst_size = s_awsize;
  assign m_waddr.burst_size = m_awsize;
  assign s_waddr.burst_type = s_awburst;
  assign m_waddr.burst_type = m_awburst;
  assign s_waddr.lock_type = s_awlock;
  assign m_waddr.lock_type = m_awlock;
  assign s_waddr.memory_type = s_awcache;
  assign m_waddr.memory_type = m_awcache;
  assign s_waddr.protection_type = s_awprot;
  assign m_waddr.protection_type = m_awprot;
  assign s_waddr.region = s_awregion;
  assign m_waddr.region = m_awregion;
  assign s_waddr.qos = s_awqos;
  assign m_waddr.qos = m_awqos;

  assign s_raddr.id = s_arid;
  assign m_raddr.id = m_arid;
  assign s_raddr.addr = s_araddr;
  assign m_raddr.addr = m_araddr;
  assign s_raddr.burst_len = s_arlen;
  assign m_raddr.burst_len = m_arlen;
  assign s_raddr.burst_size = s_arsize;
  assign m_raddr.burst_size = m_arsize;
  assign s_raddr.burst_type = s_arburst;
  assign m_raddr.burst_type = m_arburst;
  assign s_raddr.lock_type = s_arlock;
  assign m_raddr.lock_type = m_arlock;
  assign s_raddr.memory_type = s_arcache;
  assign m_raddr.memory_type = m_arcache;
  assign s_raddr.protection_type = s_arprot;
  assign m_raddr.protection_type = m_arprot;
  assign s_raddr.region = s_arregion;
  assign m_raddr.region = m_arregion;
  assign s_raddr.qos = s_arqos;
  assign m_raddr.qos = m_arqos;

  assign s_wdata.data = s_wdata;
  assign m_wdata.data = m_wdata;
  assign s_wdata.strobes = s_wstrb;
  assign m_wdata.strobes = m_wstrb;
  assign s_wdata.last = s_wlast;
  assign m_wdata.last = m_wlast;

  assign s_rdata.id = s_rid;
  assign m_rdata.id = m_rid;
  assign s_rdata.data = s_rdata;
  assign m_rdata.data = m_rdata;
  assign s_rdata.response = s_rresp;
  assign m_rdata.response = m_rresp;
  assign s_rdata.last = s_rlast;
  assign m_rdata.last = m_rlast;

  assign s_wrsp.id = s_bid;
  assign m_wrsp.id = m_bid;
  assign s_wrsp.payload = s_bresp;
  assign m_wrsp.payload = m_bresp;

  simmem_top i_simmem_top (
      .clk_i            (clk_i),
      .rst_ni           (rst_ni),
      .raddr_in_valid_i (s_arvalid),
      .raddr_out_ready_i(m_arready),
      .raddr_in_ready_o (s_arready),
      .raddr_out_valid_o(m_arvalid),
      .waddr_in_valid_i (s_awvalid),
      .waddr_out_ready_i(m_awready),
      .waddr_in_ready_o (s_awready),
      .waddr_out_valid_o(m_awvalid),
      .wdata_in_valid_i (s_wvalid),
      .wdata_out_ready_i(m_wready),
      .wdata_in_ready_o (s_wready),
      .wdata_out_valid_o(m_wvalid),
      .rdata_in_valid_i (m_rvalid),
      .rdata_out_ready_i(s_rready),
      .rdata_in_ready_o (m_rready),
      .rdata_out_valid_o(s_rvalid),
      .wrsp_in_valid_i  (m_bvalid),
      .wrsp_out_ready_i (s_bready),
      .wrsp_in_ready_o  (m_bready),
      .wrsp_out_valid_o (s_bvalid),
      .raddr_i          (s_raddr),
      .waddr_i          (s_waddr),
      .wdata_i          (s_wdata),
      .rdata_i          (m_rdata),
      .wrsp_i           (m_wrsp),
      .raddr_o          (m_raddr),
      .waddr_o          (m_waddr),
      .wdata_o          (m_wdata),
      .rdata_o          (s_rdata),
      .wrsp_o           (s_wrsp)
  );

endmodule
