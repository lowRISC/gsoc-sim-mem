// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Simulated memory controller delay bank

// Supposed to not overflow

module simmem_delay_bank #(
  parameter int TotalCapacity   = 64,
  
  parameter int IDWidth         = 8,
  parameter int CounterWidth    = 8
)(
  input logic clk_i,
  input logic rst_ni,

  input logic in_valid_i,

  input logic delay_i,

  input logic data_out_valid_i,
  input logic data_out_ready_i,

  output logic [2**IDWidth-1:0] release_en_o
);

  // Linkedlist bank instance

  logic [CounterWidth-1:0] linkedlist_output;
  
  logic linkedlist_in_valid;
  logic linkedlist_in_ready;

  logic linkedlist_valid;

  simmem_linkedlist_bank #(
    .StructWidth(CounterWidth),
    .TotalCapacity,
    .IDWidth
  ) simmem_linkedlist_bank_i (
    .clk_i,
    .rst_ni,

    .release_en_i({2**IDWidth-1{1'b1}}),

    .data_i(delay_i),
    .data_o(linkedlist_output),

    .in_valid_i(linkedlist_in_valid),
    .in_ready_o(linkedlist_in_ready), // Should be always 1

    .out_ready_i(),
    .out_valid_o()
  );


  
endmodule
