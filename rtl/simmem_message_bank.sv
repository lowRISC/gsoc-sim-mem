// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// simmem

module simmem_message_bank #(
    // Width of the messages, including identifier
    parameter int StructWidth   = 64, 

    parameter int TotalCapacity = 64, 
    parameter int IDWidth       = 8
  )(
    input logic clk_i,
    input logic rst_ni,
  
    input logic [2**IDWidth-1:0] release_en_i, // Input from the releaser
  
    input logic [StructWidth-1:0] data_i,
    output logic [StructWidth-1:0] data_o,
  
    input logic   in_valid_i,
    output logic  in_ready_o,
    
    input logic   out_ready_i,
    output logic  out_valid_o,
  );

  // Core and tail instances

  logic [2**IDWidth-1:0] next_id_to_release_onehot;
  logic [IDWidth-1:0] data_id_in;
  logic [StructWidth-IDWidth-1:0] data_noid_in;

  logic [StructWidth-IDWidth-1:0] buf_data[2**IDWidth-1:0];
  logic [2**IDWidth-1:0] buf_data_valid;

  assign data_id_in = data_i[IDWidth-1:0];
  assign data_noid_in = data_i[StructWidth-IDWidth-1:0];

  simmem_linkedlist_bank_core #(
    .StructWidth, 
    .TotalCapacity,
    .IDWidth
  ) (
    .clk_i,
    .rst_ni,

    .next_id_to_release_onehot_i(next_id_to_release_onehot),

    .data_id_i(data_id_in),
    .data_noid_i(data_noid_in),

    .buf_data_o(buf_data),
    .buf_data_valid_o(buf_data_valid),
    
    .in_valid_i(in_valid_i),
    .in_ready_o(in_ready_o)
  );

  simmem_linkedlist_bank_tail_messages #(
    .StructWidth, 
    .IDWidth
  ) (
    .clk_i,
    .rst_ni,

    .release_en_i(release_en_i),

    .next_id_to_release_onehot_o(next_id_to_release_onehot),

    .buf_data_i(buf_data),
    .buf_data_valid_i(buf_data_valid),
    
    .out_valid_i(out_valid_i),
    .out_ready_o(out_ready_o)
  );
  
  endmodule
  