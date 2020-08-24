// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Wrapper for the write response and read data response banks

// This module wraps the two response banks, which act independently. No logic is integrated in this
// wrapper.

module simmem_rsp_banks (
    input logic clk_i,
    input logic rst_ni,

    // Reservation interface AXI identifier for which the reseration request is being done.
    input  logic [           simmem_pkg::NumIds-1:0] wrsv_req_id_onehot_i,
    input  logic [           simmem_pkg::NumIds-1:0] rrsv_req_id_onehot_i,
    // Information about currently reserved address. Will be stored by other modules as an internal
    // identifier to uniquely identify the response (or response burst in case of read data).
    output logic [    simmem_pkg::WRspBankAddrW-1:0] wrsv_iid_o,
    output logic [   simmem_pkg::RDataBankAddrW-1:0] rrsv_iid_o,
    // The number of data elements to reserve in the RAM cell.
    input  logic [simmem_pkg::MaxBurstLenFieldW-1:0] rrsv_burst_len_i,

    // Reservation handshake signals
    input  logic wrsv_valid_i,
    output logic wrsv_ready_o,
    input  logic rrsv_valid_i,
    output logic rrsv_ready_o,

    // Interface with the releaser Multi-hot signal that enables the release for given internal
    // addresses (i.e., RAM addresses).
    input  logic [ simmem_pkg::WRspBankCapa-1:0] w_release_en_i,
    input  logic [simmem_pkg::RDataBankCapa-1:0] r_release_en_i,
    // Signals which address has been released, if any. One-hot signal. Is set to one for each
    // released response in a burst.
    output logic [ simmem_pkg::WRspBankCapa-1:0] w_released_addr_onehot_o,
    output logic [simmem_pkg::RDataBankCapa-1:0] r_released_addr_onehot_o,

    // Interface with the real memory controller AXI response excluding handshake
    input  simmem_pkg::wrsp_t  wrsp_i,
    output simmem_pkg::wrsp_t  wrsp_o,
    input  simmem_pkg::rdata_t rdata_i,
    output simmem_pkg::rdata_t rdata_o,

    // Response acquisition handshake signal
    input  logic w_in_rsp_valid_i,
    output logic w_in_rsp_ready_o,
    input  logic r_in_data_valid_i,
    output logic r_in_data_ready_o,

    // Interface with the requester
    input  logic w_out_rsp_ready_i,
    output logic w_out_rsp_valid_o,
    input  logic r_out_data_ready_i,
    output logic r_out_data_valid_o,

    // Ready signals from the delay calculator
    input logic w_delay_calc_ready_i,
    input logic r_delay_calc_ready_i,

    // Ready signals for the delay calculator
    output logic w_delay_calc_ready_o,
    output logic r_delay_calc_ready_o

);

  import simmem_pkg::*;

  simmem_rsp_bank #(
      .RspBankType(WRSP_BANK),
      .DataType(wrsp_t)
  ) i_simmem_wrsp_bank (
      .clk_i                 (clk_i),
      .rst_ni                (rst_ni),
      .rsv_req_id_onehot_i   (wrsv_req_id_onehot_i),
      .rsv_iid_o             (wrsv_iid_o),
      .rsv_burst_len_i       (0),  // Only 1 wrsp per burst
      .rsv_valid_i           (wrsv_valid_i),
      .rsv_ready_o           (wrsv_ready_o),
      .release_en_i          (w_release_en_i),
      .released_addr_onehot_o(w_released_addr_onehot_o),
      .rsp_i                 (wrsp_i),
      .rsp_o                 (wrsp_o),
      .in_rsp_valid_i        (w_in_rsp_valid_i),
      .in_rsp_ready_o        (w_in_rsp_ready_o),
      .out_rsp_ready_i       (w_out_rsp_ready_i),
      .out_rsp_valid_o       (w_out_rsp_valid_o),
      .delay_calc_ready_i    (w_delay_calc_ready_i),
      .delay_calc_ready_o    (w_delay_calc_ready_o)

  );

  simmem_rsp_bank #(
      .RspBankType(RDATA_BANK),
      .DataType(rdata_t)
  ) i_simmem_rdata_bank (
      .clk_i                 (clk_i),
      .rst_ni                (rst_ni),
      .rsv_req_id_onehot_i   (rrsv_req_id_onehot_i),
      .rsv_iid_o             (rrsv_iid_o),
      .rsv_burst_len_i       (rrsv_burst_len_i),
      .rsv_valid_i           (rrsv_valid_i),
      .rsv_ready_o           (rrsv_ready_o),
      .release_en_i          (r_release_en_i),
      .released_addr_onehot_o(r_released_addr_onehot_o),
      .rsp_i                 (rdata_i),
      .rsp_o                 (rdata_o),
      .in_rsp_valid_i        (r_in_data_valid_i),
      .in_rsp_ready_o        (r_in_data_ready_o),
      .out_rsp_ready_i       (r_out_data_ready_i),
      .out_rsp_valid_o       (r_out_data_valid_o),
      .delay_calc_ready_i    (r_delay_calc_ready_i),
      .delay_calc_ready_o    (r_delay_calc_ready_o)
  );

endmodule
