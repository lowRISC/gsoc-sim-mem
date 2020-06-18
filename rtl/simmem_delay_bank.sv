// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Simulated memory controller delay bank

// Supposed to not overflow

module simmem_delay_bank #(
  parameter int TotalCapacity   = 64,
  
  parameter int IDWidth         = 8,
  parameter int CounterWidth    = 64
)(
  input logic clk_i,
  input logic rst_ni,

  input logic in_valid_i,

  input logic [IDWidth-1:0] delay_id_i,
  input logic [CounterWidth-1:0] delay_i,

  input logic data_out_valid_i,
  input logic data_out_ready_i,

  output logic [2**IDWidth-1:0] release_en_o
);

  // Linkedlist bank instance

  logic [CounterWidth-1:0] linkedlist_output;
  
  logic linkedlist_out_valid;
  logic linkedlist_out_ready;

  logic linkedlist_in_valid;

  simmem_linkedlist_bank #(
    .StructWidth(CounterWidth),
    .TotalCapacity,
    .IDWidth
  ) simmem_linkedlist_bank_i (
    .clk_i,
    .rst_ni,

    .in_valid_i(linkedlist_in_valid),

    .data_id_i(delay_id_i),
    .data_i(delay_i),

    .data_id_o(delay_o),
    .data_o(linkedlist_output),

    .out_ready_i(linkedlist_out_ready),
    .out_valid_o(linkedlist_out_valid)
  );

  // Linkedlist 
  
endmodule
