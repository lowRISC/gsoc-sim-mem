// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// simmem package

package simmem_pkg;

  /////////////////
  // AXI signals //
  /////////////////

  localparam IDWidth = 4;
  localparam NumIds = 2 ** IDWidth;

  // Address field widths
  localparam AxAddrWidth = 8;
  localparam AxLenWidth = 8;
  localparam AxSizeWidth = 3;
  localparam AxBurstWidth = 2;
  localparam AxLockWidth = 2;
  localparam AxCacheWidth = 4;
  localparam AxProtWidth = 4;
  localparam AxQoSWidth = 4;
  localparam AxRegionWidth = 4;
  localparam AwUserWidth = 0;
  localparam ArUserWidth = 0;

  // Data & response field widths
  localparam XDataWidth = 14;
  localparam XLastWidth = 1;
  // TODO: Set XRespWidth to 3 when all tests are passed
  localparam XRespWidth = 10;
  localparam WUserWidth = 0;
  localparam RUserWidth = 0;
  localparam BUserWidth = 0;

  localparam WStrbWidth = XDataWidth / 8;

  typedef struct packed {
    // logic [AwUserWidth-1:0] user_signal;
    logic [AxQoSWidth-1:0] qos;
    logic [AxProtWidth-1:0] protection_type;
    logic [AxCacheWidth-1:0] memory_type;
    logic [AxLockWidth-1:0] lock_type;
    logic [AxBurstWidth-1:0] burst_type;
    logic [AxSizeWidth-1:0] burst_size;
    logic [AxLenWidth-1:0] burst_length;
    logic [AxAddrWidth-1:0] addr;
    logic [IDWidth-1:0] id;
  } waddr_req_t;

  typedef struct packed {
    // logic [ArUserWidth-1:0] user_signal;
    logic [AxQoSWidth-1:0] qos;
    logic [AxProtWidth-1:0] protection_type;
    logic [AxCacheWidth-1:0] memory_type;
    logic [AxLockWidth-1:0] lock_type;
    logic [AxBurstWidth-1:0] burst_type;
    logic [AxSizeWidth-1:0] burst_size;
    logic [AxLenWidth-1:0] burst_length;
    logic [AxAddrWidth-1:0] addr;
    logic [IDWidth-1:0] id;
  } raddr_req_t;

  typedef struct packed {
    // logic [WUserWidth-1:0] user_signal;
    logic [XLastWidth-1:0] last;
    logic [WStrbWidth-1:0] strobes;
    logic [XDataWidth-1:0] data;
  // logic [IDWidth-1:0] id; AXI4 does not allocate identifiers in write data messages
  } wdata_req_t;

  typedef struct packed {
    // logic [RUserWidth-1:0] user_signal;
    logic [XLastWidth-1:0] last;
    logic [WStrbWidth-1:0] response;
    logic [XDataWidth-1:0] data;
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
  } wresp_merged_payload_t;

  // For the write response, the union is only a wrapper helping generic message bank implementation
  typedef union packed {wresp_merged_payload_t merged_payload;} wresp_t;


  ////////////////////////////
  // Dimensions for modules //
  ////////////////////////////

  localparam WriteRespBankTotalCapacity = 32;

  localparam WriteRespBankAddrWidth = $clog2(WriteRespBankTotalCapacity);

endpackage
