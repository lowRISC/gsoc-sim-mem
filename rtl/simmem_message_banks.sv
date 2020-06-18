// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// simmem

// This modules assumes that no capacity overflow occurs.

module simmem_message_banks #(
  // Width of the messages, including identifier
  parameter int ReadDataStructWidth     = 64, 
  parameter int WriteRespStructWidth    = 64,

  parameter int ReadDataBanksCapacity   = 64,
  parameter int WriteRespBanksCapacity  = 64,
  
  parameter int IDWidth                 = 8
)(
  input logic clk_i,
  input logic rst_ni,

  input logic [1:0][2**IDWidth-1:0] release_en_i, // Input from the releaser

  input logic [ReadDataStructWidth-1:0] read_data_i,
  input logic [WriteRespStructWidth-1:0] write_resp_i,

  output logic [ReadDataStructWidth-1:0] read_data_o,
  output logic [WriteRespStructWidth-1:0] write_resp_o,

  input logic   read_data_in_valid_i,
  input logic   read_data_out_ready_i,
  output logic  read_data_in_ready_o,
  output logic  read_data_out_valid_o,

  input logic   write_resp_in_valid_i,
  input logic   write_resp_out_ready_i,
  output logic  write_resp_in_ready_o,
  output logic  write_resp_out_valid_o
);

  import simmem_pkg::ram_bank_e;

  simmem_linkedlist_message_bank #(
    .StructWidth(ReadDataStructWidth),
    .TotalCapacity(ReadDataBanksCapacity),
    .IDWidth(IDWidth)
  ) simmem_linkedlist_message_bank_read_data_i (
    .clk_i,
    .rst_ni,

    .release_en_i(release_en_i[READ_DATA]),

    .data_i(read_data_i),
    .data_o(read_data_o),

    .in_valid_i(read_data_in_valid_i),
    .in_ready_o(read_data_in_ready_o),

    .out_ready_i(read_data_out_ready_i),
    .out_valid_o(read_data_out_valid_o)
  );

  simmem_linkedlist_message_bank #(
    .StructWidth(ReadDataStructWidth),
    .TotalCapacity(ReadDataBanksCapacity),
    .IDWidth(IDWidth)
  ) simmem_message_bank_write_resp_i (
    .clk_i,
    .rst_ni,

    .release_en_i(release_en_i[WRITE_RESP]),

    .data_i(write_resp_i),
    .data_o(write_resp_o),

    .in_valid_i(write_resp_in_valid_i),
    .in_ready_o(write_resp_in_ready_o),

    .out_ready_i(write_resp_out_ready_i),
    .out_valid_o(write_resp_out_valid_o)
  );

endmodule
