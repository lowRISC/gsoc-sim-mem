// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Linkedlist bank for delays in the simulated memory controller

// The delay bank takes delays as inputs and outputs a multihot signal corresponding to which
// response can be released by the message bank.
// It contains one counter per response identifier (corresponding to RAM addresses).

module simmem_delay_bank (
  input logic clk_i,
  input logic rst_ni,
  
  input logic [simmem_pkg::WriteRespBankAddrWidth-1:0] local_identifier_i,
  input logic [simmem_pkg::DelayWidth-1:0] delay_i,
  input logic in_valid_i,
  
  // Signals at output
  input  logic [simmem_pkg::WriteRespBankTotalCapacity-1:0] address_released_onehot_i,
  output logic [simmem_pkg::WriteRespBankTotalCapacity-1:0] release_en_o
);

  import simmem_pkg::*;

  /////////////////////////////////////////////////////
  // Local identifiers to add to the releasable list //
  /////////////////////////////////////////////////////

  logic [WriteRespBankTotalCapacity-1:0] new_addresses_to_release_multihot;


  ///////////////////
  // Entry signals //
  ///////////////////

  logic [DelayWidth-1:0] counters_d[WriteRespBankTotalCapacity];
  logic [DelayWidth-1:0] counters_q[WriteRespBankTotalCapacity];

  // Entry signal management
  for (
      genvar curr_entry = 0; curr_entry < WriteRespBankTotalCapacity; curr_entry = curr_entry + 1
  ) begin : counter_update
    always_comb begin : counter_update_comb
      new_addresses_to_release_multihot[curr_entry] = 1'b0;

      // Update the counter value if it is not zero
      if (|counters_q[curr_entry]) begin
        counters_d[curr_entry] = counters_q[curr_entry] - 1;
      end else begin
        counters_d[curr_entry] = counters_q[curr_entry];
      end

      // The input cannot be simultaneous with the release due to a counter hitting zero
      if (counters_q[curr_entry] == 1 && counters_d[curr_entry] == 0) begin
        new_addresses_to_release_multihot[curr_entry] = 1'b1;
      end else if (in_valid_i && local_identifier_i == curr_entry) begin
        if (delay_i == 2 || delay_i == 1 || delay_i == 0) begin
          new_addresses_to_release_multihot[curr_entry] = 1'b1;
        end else begin
          // Minus 2 because the input handshake of this module takes 1 cycle and the output
          // latency of the memory bank is at least 1 cycle.
          counters_d[curr_entry] = delay_i - 2;
        end
      end else begin
      end
    end : counter_update_comb
  end : counter_update


  /////////////////////////////////////
  // Update the release_en_i signals //
  /////////////////////////////////////

  logic [WriteRespBankTotalCapacity-1:0] release_en_d;

  always_comb begin : update_release_en_signals
    release_en_d = release_en_o;

    // Clear the released values
    release_en_d &= ~address_released_onehot_i;
    release_en_d |= new_addresses_to_release_multihot;
  end : update_release_en_signals


  //////////////////////////////////
  // Sequential signal management //
  //////////////////////////////////

  for (
      genvar curr_entry = 0; curr_entry < WriteRespBankTotalCapacity; curr_entry = curr_entry + 1
  ) begin : sequential_signal_update
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        counters_q[curr_entry] <= '0;
        release_en_o <= '0;
      end else begin
        counters_q[curr_entry] <= counters_d[curr_entry];
        release_en_o <= release_en_d;
      end
    end
  end : sequential_signal_update

endmodule
