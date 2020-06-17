// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Simulated memory controller releaser

module simmem_releaser #(
    // Width of the messages, including identifier
    parameter int ReadAddressStructWidth  = 64,
    parameter int WriteAddressStructWidth = 64,
    parameter int WriteDataStructWidth    = 64,

    parameter int ReadDataBanksCapacity   = 64,
    parameter int WriteRespBanksCapacity  = 64,
    parameter int ReadDataDelayBanksCapacity   = 64,
    parameter int WriteRespDelayBanksCapacity  = 64,

    parameter int IDWidth                 = 8,
    parameter int CounterWidth            = 8
  )(
    input logic clk_i,
    input logic rst_ni,

    input logic read_addr_in_valid_i,
    input logic read_addr_out_ready_i,

    input logic write_addr_in_valid_i,
    input logic write_addr_out_ready_i,

    input logic write_data_in_valid_i,
    input logic write_data_out_ready_i,

    input logic read_data_out_ready_i,
    input logic read_data_out_valid_i,
  
    input logic write_resp_out_ready_i,
    input logic write_resp_out_valid_i,  

    input logic [ReadAddressStructWidth-1:0]  read_addr_i,
    input logic [WriteAddressStructWidth-1:0] write_addr_i,
    input logic [WriteDataStructWidth-1:0]    write_data_i,

    output logic [1:0][2**IDWidth-1:0] release_en_o
    // output logic read_data_ready_o,
    // output logic write_resp_ready_o
  );
  
  
  endmodule
  
  