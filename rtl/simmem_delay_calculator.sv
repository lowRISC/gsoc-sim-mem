// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// The delay calculator is responsible for snooping the traffic from the requester and deducing the
// enable signals for the message banks. This module is a wrapper for the delay calculator core. It
// makes sure that write data requests are not seen by the delay calculator core before the
// corresponding write address. To ensure this property, and as the write data request content is
// irrelevant to delay estimation (in particular, it does not contain an AXI identifier in the
// targeted stadard AXI 4), this wrapper maintains a signed counter of snooped write data
// requests that do not have a write address yet. When the corresponding write address request comes
// in, it is immediately transmitted to the delay calculator core, along with the corresponding
// count of write data requests already (or concurrently) received.

module simmem_delay_calculator #(
    // Must be a power of two, used for address interleaving
    parameter int unsigned NumRanks = 1  // Must be one, as interleaving is not yet supported.
) (
    input logic clk_i,
    input logic rst_ni,

    // Write address request from the requester.
    input simmem_pkg::waddr_t     waddr_i,
    // Internal identifier corresponding to the write address request (issued by the write response
    // bank).
    input simmem_pkg::write_iid_t waddr_iid_i,

    // Write address request valid from the requester.
    input  logic waddr_valid_i,
    // Blocks the write address request if there is no write slot in the delay calculator to treat
    // it.
    output logic waddr_ready_o,

    // Write address request valid from the requester.
    input  logic wdata_valid_i,
    // Always ready to take write data (the corresponding counter 'wdata_cnt_d/wdata_cnt_q' is
    // supposed never to overflow).
    output logic wdata_ready_o,

    // Write address request from the requester.
    input simmem_pkg::raddr_t    raddr_i,
    // Internal identifier corresponding to the read address request (issued by the read response
    // bank).
    input simmem_pkg::read_iid_t raddr_iid_i,

    // Read address request valid from the requester.
    input  logic raddr_valid_i,
    // Blocks the read address request if there is no read slot in the delay calculator to treat it.
    output logic raddr_ready_o,

    // Release enable output signals and released address feedback.
    output logic [ simmem_pkg::WRspBankCapa-1:0] wrsp_release_en_mhot_o,
    output logic [simmem_pkg::RDataBankCapa-1:0] rdata_release_en_mhot_o,

    // Release confirmations sent by the message banks
    input logic [ simmem_pkg::WRspBankCapa-1:0] wrsp_released_iid_onehot_i,
    input logic [simmem_pkg::RDataBankCapa-1:0] rdata_released_iid_onehot_i,

    // Ready signals from the response banks
    input logic wrsp_bank_ready_i,
    input logic rrsp_bank_ready_i,

    // Ready signals for the response banks
    output logic wrsp_bank_ready_o,
    output logic rrsp_bank_ready_o
);

  import simmem_pkg::*;

  // MaxPendingWData is the maximum possible number of distinct values taken by the write data.
  localparam int unsigned MaxPendingWData = MaxBurstEffLen * WRspBankCapa;

  // Additional 32 bits are added to avoid overflow in tests.
  localparam int unsigned MaxPendingWDataW = $clog2(MaxPendingWData) + 32;

  // Counters for the write data without address yet. If negative, then it means, that the core is
  // still awaiting data write data.
  logic signed [MaxPendingWDataW:0] wdata_cnt_d;
  logic signed [MaxPendingWDataW:0] wdata_cnt_q;

  // Valid signal for the write data from the delay calculator core.
  logic core_wdata_valid_input;
  // Determines whether the core is ready to receive new data.
  logic core_wdata_ready;
  assign core_wdata_ready = wdata_cnt_q[MaxPendingWDataW];

  // Counts how many data requests have been received before or with the write address request.
  logic [MaxBurstLenField-1:0] wdata_immediate_cnt;

  always_comb begin
    wdata_cnt_d = wdata_cnt_q;
    core_wdata_valid_input = 1'b0;

    if (wdata_valid_i && wdata_ready_o) begin
      if (core_wdata_ready) begin
        // If the core has space for additional data, then transmit the data beat.
        core_wdata_valid_input = 1'b1;
      end
      // In all cases, when the data beat has been detected by the wrapper, increment the beat
      // counter.
      wdata_cnt_d = wdata_cnt_d + 1;
    end

    if (waddr_valid_i && waddr_ready_o) begin
      // Considering wdata_cnt_d, instead of wdata_cnt_q, allows the module to take into account the
      // data coming in during the same cycle as the address. Safety of this operation is granted by
      // the order in which wdata_cnt_d is updated in the combinatorial block.
      wdata_immediate_cnt = 0;
      if (!wdata_cnt_d[MaxPendingWDataW]) begin
        // If wdata_cnt_d is nonnegative, then consider sending immediate data
        if (AxLenWidth'(wdata_cnt_d) >= get_effective_burst_len(waddr_i.burst_len)) begin
          // If wdata_cnt_d is nonnegative and all the data associated with the address has arrived
          // not later than the address, then transmit all this data with the address request to the
          // delay calculator core.
          wdata_immediate_cnt = get_effective_burst_len(waddr_i.burst_len);
        end else begin
          // Else, transmit only the already and currently received write data.
          wdata_immediate_cnt = wdata_cnt_d[MaxBurstLenField - 1:0];
        end
      end

      // Update the write data count to take the new core demand into account.
      wdata_cnt_d = wdata_cnt_d - MaxPendingWDataW'(get_effective_burst_len(waddr_i.burst_len));
    end
  end

  // Outputs Write data are always accepted, as the only space they require is in the counter.
  assign wdata_ready_o = 1'b1;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wdata_cnt_q <= '0;
    end else begin
      wdata_cnt_q <= wdata_cnt_d;
    end
  end

  simmem_delay_calculator_core #(
      .NumRanks(NumRanks)
  ) i_simmem_delay_calculator_core (
      .clk_i                      (clk_i),
      .rst_ni                     (rst_ni),
      .waddr_iid_i                (waddr_iid_i),
      .waddr_i                    (waddr_i),
      .wdata_immediate_cnt_i      (wdata_immediate_cnt),
      .waddr_valid_i              (waddr_valid_i),
      .waddr_ready_o              (waddr_ready_o),
      .wdata_valid_i              (core_wdata_valid_input),
      .raddr_iid_i                (raddr_iid_i),
      .raddr_i                    (raddr_i),
      .raddr_valid_i              (raddr_valid_i),
      .raddr_ready_o              (raddr_ready_o),
      .wrsp_release_en_mhot_o     (wrsp_release_en_mhot_o),
      .rdata_release_en_mhot_o    (rdata_release_en_mhot_o),
      .wrsp_released_iid_onehot_i (wrsp_released_iid_onehot_i),
      .rdata_released_iid_onehot_i(rdata_released_iid_onehot_i),
      .wrsp_bank_ready_i          (wrsp_bank_ready_i),
      .rrsp_bank_ready_i          (rrsp_bank_ready_i),
      .wrsp_bank_ready_o          (wrsp_bank_ready_o),
      .rrsp_bank_ready_o          (rrsp_bank_ready_o)
  );

endmodule
