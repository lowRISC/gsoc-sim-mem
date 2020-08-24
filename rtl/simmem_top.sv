// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Simulated memory controller top-level module

// This is the top-level module for the simulated memory controller. It has one AXI slave port to
// connect to the requester (typically the CPU) and one AXI master port to connect to the real
// memory controller.
//
// The top-level module wraps together the delay calculator and the response banks.
// It may itself be wrapped by a Verilog wrapper Xilinx Vivado® integration for instance.

module simmem_top (
    input logic clk_i,
    input logic rst_ni,

    // AXI slave interface

    input  logic               raddr_in_valid_i,
    output logic               raddr_in_ready_o,
    input  simmem_pkg::raddr_t raddr_i,

    input  logic               waddr_in_valid_i,
    output logic               waddr_in_ready_o,
    input  simmem_pkg::waddr_t waddr_i,

    input  logic               wdata_in_valid_i,
    output logic               wdata_in_ready_o,
    input  simmem_pkg::wdata_t wdata_i,

    input  logic               rdata_out_ready_i,
    output logic               rdata_out_valid_o,
    output simmem_pkg::rdata_t rdata_o,

    input  logic              wrsp_out_ready_i,
    output logic              wrsp_out_valid_o,
    output simmem_pkg::wrsp_t wrsp_o,

    // AXI master interface

    input  logic               waddr_out_ready_i,
    output logic               waddr_out_valid_o,
    output simmem_pkg::waddr_t waddr_o,

    input  logic               raddr_out_ready_i,
    output logic               raddr_out_valid_o,
    output simmem_pkg::raddr_t raddr_o,

    input  logic               wdata_out_ready_i,
    output logic               wdata_out_valid_o,
    output simmem_pkg::wdata_t wdata_o,

    input  logic               rdata_in_valid_i,
    output logic               rdata_in_ready_o,
    input  simmem_pkg::rdata_t rdata_i,

    input  logic              wrsp_in_valid_i,
    output logic              wrsp_in_ready_o,
    input  simmem_pkg::wrsp_t wrsp_i
);

  import simmem_pkg::*;

  // Reservation identifier
  logic [NumIds-1:0] wrsv_req_id_onehot;
  logic [NumIds-1:0] rrsv_req_id_onehot;

  for (genvar i_bit = 0; i_bit < NumIds; i_bit = i_bit + 1) begin : rsv_req_id_to_onehot
    assign wrsv_req_id_onehot[i_bit] = i_bit == waddr_i.id;
    assign rrsv_req_id_onehot[i_bit] = i_bit == raddr_i.id;
  end : rsv_req_id_to_onehot

  // Reserved IID (RAM address)
  logic [WRspBankAddrW-1:0] wrsv_iid;
  logic [RDataBankAddrW-1:0] rrsv_iid;

  // Reservation handshakes on the response banks
  logic wrsv_valid_in;
  logic rrsv_valid_in;
  logic wrsv_ready_out;
  logic rrsv_ready_out;

  assign wrsv_valid_in = waddr_out_ready_i & waddr_in_valid_i;
  assign rrsv_valid_in = raddr_out_ready_i & raddr_in_valid_i;

  // Valid and ready signals for addresses on the delay calculator
  logic waddr_valid_in_delay_calc;
  logic raddr_valid_in_delay_calc;
  logic waddr_ready_out_delay_calc;  // Must be equal to wrsv_ready_out
  logic raddr_ready_out_delay_calc;  // Must be equal to rrsv_ready_out

  assign waddr_valid_in_delay_calc = waddr_out_ready_i & waddr_in_valid_i;
  assign raddr_valid_in_delay_calc = raddr_out_ready_i & raddr_in_valid_i;

  // Valid and ready signals for write data on the delay calculator
  logic wdata_valid_in_delay_calc;
  logic wdata_ready_out_delay_calc;

  assign wdata_valid_in_delay_calc = wdata_out_ready_i & wdata_in_valid_i;

  // Release enable signals
  logic [WRspBankCapa-1:0] wrsp_release_en_mhot;
  logic [RDataBankCapa-1:0] rdata_release_en_mhot;

  // Released addresses feedback
  logic [WRspBankCapa-1:0] wrsp_released_onehot;
  logic [RDataBankCapa-1:0] rdata_released_onehot;

  // Mutual ready signals (directions are given in the point of view of the response banks
  logic w_delay_calc_ready_in;  // From the delay calculator
  logic r_delay_calc_ready_in;  // From the delay calculator
  logic w_delay_calc_ready_out;  // From the response banks
  logic r_delay_calc_ready_out;  // From the response banks

  // Output hanshake signals for upstream signals (from the requester to the real memory controller).
  assign waddr_in_ready_o = waddr_out_ready_i & wrsv_ready_out;
  assign raddr_in_ready_o = raddr_out_ready_i & rrsv_ready_out;
  assign waddr_out_valid_o = waddr_in_valid_i & wrsv_ready_out;
  assign raddr_out_valid_o = raddr_in_valid_i & rrsv_ready_out;
  assign wdata_in_ready_o = wdata_out_ready_i & wdata_ready_out_delay_calc;
  assign wdata_out_valid_o = wdata_in_valid_i & wdata_ready_out_delay_calc;

  // Output upstream signals
  assign wdata_o = wdata_i;
  assign raddr_o = raddr_i;
  assign waddr_o = waddr_i;

  // Response banks instance
  simmem_rsp_banks i_simmem_rsp_banks (
      .clk_i                   (clk_i),
      .rst_ni                  (rst_ni),
      .wrsv_req_id_onehot_i    (wrsv_req_id_onehot),
      .rrsv_req_id_onehot_i    (rrsv_req_id_onehot),
      .wrsv_iid_o              (wrsv_iid),
      .rrsv_iid_o              (rrsv_iid),
      .rrsv_burst_len_i        (MaxBurstLenFieldW'(raddr_i.burst_len)),
      .wrsv_valid_i            (wrsv_valid_in),
      .wrsv_ready_o            (wrsv_ready_out),
      .rrsv_valid_i            (rrsv_valid_in),
      .rrsv_ready_o            (rrsv_ready_out),
      .w_release_en_i          (wrsp_release_en_mhot),
      .r_release_en_i          (rdata_release_en_mhot),
      .w_released_addr_onehot_o(wrsp_released_onehot),
      .r_released_addr_onehot_o(rdata_released_onehot),
      .wrsp_i                  (wrsp_i),
      .wrsp_o                  (wrsp_o),
      .rdata_i                 (rdata_i),
      .rdata_o                 (rdata_o),
      .w_in_rsp_valid_i        (wrsp_in_valid_i),
      .w_in_rsp_ready_o        (wrsp_in_ready_o),
      .r_in_data_valid_i       (rdata_in_valid_i),
      .r_in_data_ready_o       (rdata_in_ready_o),
      .w_out_rsp_ready_i       (wrsp_out_ready_i),
      .w_out_rsp_valid_o       (wrsp_out_valid_o),
      .r_out_data_ready_i      (rdata_out_ready_i),
      .r_out_data_valid_o      (rdata_out_valid_o),
      .w_delay_calc_ready_i    (w_delay_calc_ready_in),
      .r_delay_calc_ready_i    (r_delay_calc_ready_in),
      .w_delay_calc_ready_o    (w_delay_calc_ready_out),
      .r_delay_calc_ready_o    (r_delay_calc_ready_out)
  );

  simmem_delay_calculator i_simmem_delay_calculator (
      .clk_i                      (clk_i),
      .rst_ni                     (rst_ni),
      .waddr_i                    (waddr_i),
      .waddr_iid_i                (wrsv_iid),
      .waddr_valid_i              (waddr_valid_in_delay_calc),
      .waddr_ready_o              (waddr_ready_out_delay_calc),
      .wdata_valid_i              (wdata_valid_in_delay_calc),
      .wdata_ready_o              (wdata_ready_out_delay_calc),
      .raddr_i                    (raddr_i),
      .raddr_iid_i                (rrsv_iid),
      .raddr_valid_i              (raddr_valid_in_delay_calc),
      .raddr_ready_o              (raddr_ready_out_delay_calc),
      .wrsp_release_en_mhot_o     (wrsp_release_en_mhot),
      .rdata_release_en_mhot_o    (rdata_release_en_mhot),
      .wrsp_released_iid_onehot_i (wrsp_released_onehot),
      .rdata_released_iid_onehot_i(rdata_released_onehot),
      .wrsp_bank_ready_o          (w_delay_calc_ready_in),
      .rrsp_bank_ready_o          (r_delay_calc_ready_in),
      .wrsp_bank_ready_i          (w_delay_calc_ready_out),
      .rrsp_bank_ready_i          (r_delay_calc_ready_out)
  );

endmodule
