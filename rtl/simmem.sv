// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Simulated memory controller top-level

module simmem #(
  // Width of the messages, including identifier
  parameter int ReadAddressStructWidth  = 64,
  parameter int WriteAddressStructWidth = 64,
  parameter int WriteDataStructWidth    = 64,
  parameter int ReadDataStructWidth     = 64,
  parameter int WriteRespStructWidth    = 64,

  parameter int ReadDataBanksCapacity   = 64,
  parameter int WriteRespBanksCapacity  = 64,
  parameter int ReadDataDelayBanksCapacity   = 64,
  parameter int WriteRespDelayBanksCapacity  = 64,

  parameter int IDWidth                 = 8,
  parameter int CounterWidth            = 8
)(
  input logic   clk_i,
  input logic   rst_ni,

  input logic   read_addr_in_valid_i,
  input logic   read_addr_out_ready_i,
  output logic  read_addr_in_ready_o,
  output logic  read_addr_out_valid_o,

  input logic   write_addr_in_valid_i,
  input logic   write_addr_out_ready_i,
  output logic  write_addr_in_ready_o,
  output logic  write_addr_out_valid_o,

  input logic   write_data_in_valid_i,
  input logic   write_data_out_ready_i,
  output logic  write_data_in_ready_o,
  output logic  write_data_out_valid_o,

  input logic   read_data_in_valid_i,
  input logic   read_data_out_ready_i,
  output logic  read_data_in_ready_o,
  output logic  read_data_out_valid_o,

  input logic   write_resp_in_valid_i,
  input logic   write_resp_out_ready_i,
  output logic  write_resp_in_ready_o,
  output logic  write_resp_out_valid_o,

  input logic [ReadAddressStructWidth-1:0]  read_addr_i,
  input logic [WriteAddressStructWidth-1:0] write_addr_i,
  input logic [WriteDataStructWidth-1:0]    write_data_i,
  input logic [ReadDataStructWidth-1:0]     read_data_i,
  input logic [WriteRespStructWidth-1:0]    write_resp_i,

  output logic [ReadAddressStructWidth-1:0]  read_addr_o,
  output logic [WriteAddressStructWidth-1:0] write_addr_o,
  output logic [WriteDataStructWidth-1:0]    write_data_o,
  output logic [ReadDataStructWidth-1:0]     read_data_o,
  output logic [WriteRespStructWidth-1:0]    write_resp_o
);

  // Releaser instance

  logic [1:0][2**IDWidth-1] release_en;

  // Blocks the transactions if the releaser is not ready
  // logic releaser_read_data_ready;
  // logic releaser_write_resp_ready;

  simmem_releaser #(
    .ReadAddressStructWidth,
    .WriteAddressStructWidth,
    .WriteDataStructWidth,
    .ReadDataBanksCapacity,
    .WriteRespBanksCapacity,
    .IDWidth,
    .CounterWidth
  ) simmem_releaser_i (
    .clk_i,
    .rst_ni,

    .read_addr_in_valid_i,
    .read_addr_out_ready_i,

    .write_addr_in_valid_i,
    .write_addr_out_ready_i,

    .write_data_in_valid_i,
    .write_data_out_ready_i,

    .read_data_in_valid_i,
    .read_data_out_ready_i,
    .read_data_in_ready_i(read_data_in_ready_o),
    .read_data_out_valid_i(read_data_out_valid_o),
  
    .write_resp_in_valid_i,
    .write_resp_out_ready_i,
    .write_resp_in_ready_i(write_resp_in_ready_o),
    .write_resp_out_valid_i(write_resp_out_valid_o),

    .read_addr_i,
    .write_addr_i,
    .write_data_i,

    .release_en_o(release_en)
    // .read_data_ready_o(releaser_read_data_ready)
    // .releaser_write_resp_ready_o(releaser_write_resp_ready)
  );


  // Linkedlist banks instance

  simmem_message_banks #(
    .ReadDataStructWidth,
    .WriteRespStructWidth,
    .ReadDataBanksCapacity,
    .WriteRespBanksCapacity,
    .IDWidth
  ) simmem_message_banks_i (
    .clk_i,
    .rst_ni,
  
    .release_en_i(release_en),
  
    .read_data_i,
    .write_resp_i,
  
    .read_data_o,
    .write_resp_o,
  
    .read_data_in_valid_i,
    .read_data_out_ready_i,
    .read_data_in_ready_o,
    .read_data_out_valid_o,
  
    .write_resp_in_valid_i,
    .write_resp_out_ready_i,
    .write_resp_in_ready_o,
    .write_resp_out_valid_o
  );


  // I/O signals

  assign read_data_in_ready_o = read_data_out_ready_i;
  assign read_addr_in_ready_o = read_addr_out_ready_i;
  assign write_addr_in_ready_o = write_addr_out_ready_i;

endmodule
