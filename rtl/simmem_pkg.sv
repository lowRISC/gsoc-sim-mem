// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// simmem package

// The simmem_pkg module is structured as follows:
//  * Parameters for the AXI fields dimensions and several simulated memory controller parameters.
//  * AXI signals structure definitions
//  * Helper function definitions
//
// Only the first of the three parts should be modified for configuration.
//
// Parameters must match those in dv/simmem_top/simmem_axi_dimensions.h

package simmem_pkg;

  ///////////////////////
  // Simmem parameters //
  ///////////////////////

  // The capacity of the global memory
  parameter int unsigned GlobalMemCapaW = 19; // Width
  parameter int unsigned GlobalMemCapa = 1 << GlobalMemCapaW;  // Bytes.

  // The log2 of the bank row length.
  parameter int unsigned RowBufLenW = 10;
  // The number of MSBs that uniquely define a bank row in an address.
  parameter int unsigned RowIdWidth = GlobalMemCapaW - RowBufLenW;

  parameter int unsigned RowHitCost = 4;  // Cycles (must be at least 3)
  parameter int unsigned PrechargeCost = 2;  // Cycles
  parameter int unsigned ActivationCost = 1;  // Cycles

  // Log2 of the boundary that cannot be crossed by bursts.
  parameter int unsigned BurstAddrLSBs = 12;

  // Maximal value of any burst_size field, must be positive.
  parameter int unsigned MaxBurstSizeField = 2;

  // Effective max burst size (in number of elements)
  parameter int unsigned MaxBurstEffSizeBytes = 1 << MaxBurstSizeField;
  parameter int unsigned MaxBurstEffSizeBits = MaxBurstEffSizeBytes * 8;

  parameter int unsigned WStrbWidth = MaxBurstEffSizeBytes;

  // Maximal allowed burst length field value, must be positive.
  parameter int unsigned MaxBurstLenField = 3; // Must be of the form 2^n-1
  parameter int unsigned MaxBurstLenFieldW = $clog2(MaxBurstLenField); // Width

  // Effective max burst length (in number of elements)
  parameter int unsigned MaxBurstEffLen = 1 + MaxBurstLenField;
  parameter int unsigned MaxBurstEffLenW = $clog2(MaxBurstEffLen); // Width
  // XBurstEffLenW is the smallest width large enough to contain the representation of the
  //  maximal effective number of elements per burst (as opposed to the maximal burst length field
  //  value, which is one element smaller). It is useful in counters implementation.
  localparam int unsigned XBurstEffLenW = $clog2(MaxBurstEffLen + 1);

  // Capacities in extended cells (number of outstanding bursts).
  parameter int unsigned WRspBankCapa = 3;
  parameter int unsigned RDataBankCapa = 2;

  parameter int unsigned WRspBankAddrW = $clog2(WRspBankCapa);
  parameter int unsigned RDataBankAddrW = $clog2(RDataBankCapa);

  // Internal identifier types.
  typedef logic [WRspBankAddrW-1:0] write_iid_t;
  typedef logic [RDataBankAddrW-1:0] read_iid_t;

  // Delay calculator slot constants definition.
  parameter int unsigned NumWSlots = WRspBankCapa;
  parameter int unsigned NumRSlots = RDataBankCapa;

  // Maximal bit width on which to encode a delay.(measured in clock cycles).
  parameter int unsigned DelayW = $clog2(RowHitCost + PrechargeCost + ActivationCost);  // bits

  /////////////////
  // AXI signals //
  /////////////////

  parameter int unsigned IDWidth = 2;
  parameter int unsigned NumIds = 1 << IDWidth;

  // Address field widths
  parameter int unsigned AxAddrWidth = GlobalMemCapaW;
  parameter int unsigned AxLenWidth = 8;
  parameter int unsigned AxSizeWidth = 3;
  parameter int unsigned AxBurstWidth = 2;
  parameter int unsigned AxLockWidth = 1;
  parameter int unsigned AxCacheWidth = 4;
  parameter int unsigned AxProtWidth = 3;
  parameter int unsigned AxQoSWidth = 4;
  parameter int unsigned AxRegionWidth = 4;
  parameter int unsigned AwUserWidth = 0;
  parameter int unsigned ArUserWidth = 0;

  // Data & response field widths
  parameter int unsigned XLastWidth = 1;
  // XRespWidth should be increased to 10 when testing, to have wider patterns to compare.
  parameter int unsigned XRespWidth = 2;
  parameter int unsigned WUserWidth = 0;
  parameter int unsigned RUserWidth = 0;
  parameter int unsigned BUserWidth = 0;

  ///////////////////////////////////
  // End of the parameters section //
  ///////////////////////////////////

  typedef enum logic {
    WRSP_BANK = 0,
    RDATA_BANK = 1
  } rsp_bank_type_e;

  typedef enum logic [AxBurstWidth-1:0] {
    BURST_FIXED = 0,
    BURST_INCR = 1,
    BURST_WRAP = 2,
    BURST_RESERVED = 3
  } burst_type_e;

  ////////////////////////
  // Packet definitions //
  ////////////////////////

  typedef struct packed {
    // logic [AwUserWidth-1:0] user_signal;
    logic [AxQoSWidth-1:0] qos;
    logic [AxRegionWidth-1:0] region;
    logic [AxProtWidth-1:0] protection_type;
    logic [AxCacheWidth-1:0] memory_type;
    logic [AxLockWidth-1:0] lock_type;
    burst_type_e burst_type;
    logic [AxSizeWidth-1:0] burst_size;
    logic [AxLenWidth-1:0] burst_len;
    logic [AxAddrWidth-1:0] addr;
    logic [IDWidth-1:0] id;
  } waddr_t;

  typedef struct packed {
    // logic [ArUserWidth-1:0] user_signal;
    logic [AxQoSWidth-1:0] qos;
    logic [AxRegionWidth-1:0] region;
    logic [AxProtWidth-1:0] protection_type;
    logic [AxCacheWidth-1:0] memory_type;
    logic [AxLockWidth-1:0] lock_type;
    burst_type_e burst_type;
    logic [AxSizeWidth-1:0] burst_size;
    logic [AxLenWidth-1:0] burst_len;
    logic [AxAddrWidth-1:0] addr;
    logic [IDWidth-1:0] id;
  } raddr_t;

  typedef struct packed {
    // logic [WUserWidth-1:0] user_signal;
    logic [XLastWidth-1:0] last;
    logic [WStrbWidth-1:0] strobes;
    logic [MaxBurstEffSizeBits-1:0] data;
  // logic [IDWidth-1:0] id; AXI4 does not allocate identifiers in write data messages
  } wdata_t;

  typedef struct packed {
    // logic [RUserWidth-1:0] user_signal;
    logic [XLastWidth-1:0] last;
    logic [XRespWidth-1:0] response;
    logic [MaxBurstEffSizeBits-1:0] data;
    logic [IDWidth-1:0] id;
  } rdata_all_fields_t;

  typedef struct packed {
    logic [$bits(rdata_all_fields_t)-IDWidth-1:0] payload;
    logic [IDWidth-1:0] id;
  } rdata_merged_payload_t;

  typedef union packed {
    rdata_all_fields_t all_fields;
    rdata_merged_payload_t merged_payload;
  } rdata_t;

  typedef struct packed {
    // logic [BUserWidth-1:0] user_signal;
    logic [XRespWidth-1:0] payload;
    logic [IDWidth-1:0] id;
  } wrsp_merged_payload_t;

  // For the write response, the union is only a wrapper helping generic response bank implementation
  typedef union packed {wrsp_merged_payload_t merged_payload;} wrsp_t;

  //////////////////////
  // Helper functions //
  //////////////////////

  /**
    * Determines the effective burst length from the burst length field.
    *
    * @param burst_len_field the burst_length field of the AXI signal
    * @return the number of elements in the burst
    */
  function automatic logic [XBurstEffLenW-1:0] get_effective_burst_len(
      logic [AxLenWidth-1:0] burst_len_field);
    return XBurstEffLenW'(burst_len_field) + XBurstEffLenW'(1);
  endfunction : get_effective_burst_len

  /**
    * Determines the effective burst size from the burst size field.
    *
    * @param burst_len_field the burst_size field of the AXI signal
    * @return the size of the elements in the burst
    */
  function automatic logic [MaxBurstSizeField-1:0] get_effective_burst_size(
      logic [AxSizeWidth-1:0] burst_size_field);
    return 1 << burst_size_field;
  endfunction : get_effective_burst_size

endpackage
