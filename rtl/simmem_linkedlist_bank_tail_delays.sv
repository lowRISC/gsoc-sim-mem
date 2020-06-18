// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Linkedlist bank for messages in the simulated memory controller 

module simmem_linkedlist_bank_reduction_messages #(
    parameter int StructWidth = 64,  // Width of the message including identifier
    parameter int CounterWidth = 64,
    parameter int IDWidth = 4
) (
    input logic clk_i,
    input logic rst_ni,

    output logic [2**IDWidth-1:0] next_id_to_release_onehot_o,

    input logic [StructWidth-IDWidth-1:0] buf_data_i [2**IDWidth-1:0],
    input logic [2**IDWidth-1:0] buf_data_valid_i,

    // Snoop handshake signals from the message banks output
    input logic snoop_message_out_ready_i [2**IDWidth-1:0],
    input logic snoop_message_out_valid_i [2**IDWidth-1:0],

    input  logic out_ready_i,
    output logic out_valid_o
);

  // Choose which identifier to release first
  logic next_id_to_release_onehot[2**IDWidth-1:0];
  logic [2**IDWidth-1:0] next_id_to_release_onehot_packed;

  for (genvar current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
    assign next_id_to_release_onehot_packed[current_id] = next_id_to_release_onehot[current_id];
  end

  // Output signals
  assign out_valid_o = |next_id_to_release_onehot_packed;
  assign next_id_to_release_onehot_o = next_id_to_release_onehot & out_ready_i;


  // Counters

  logic [CounterWidth-1:0] counters_d[2**IDWidth-1:0];
  logic [CounterWidth-1:0] counters_q[2**IDWidth-1:0];

  logic [2**IDWidth-1:0] expect_new_delay_packed;

  for (genvar current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
    // Request a new delay in the case the previous delay is passed and the handshake is happening between the message bank and the requester
    expect_new_delay_packed[current_id] = buf_data_valid_i[current_id] && (counters_q[current_id] >= buf_data_i[current_id]) && snoop_message_out_ready_i && snoop_message_out_valid_i;
  end

  // Next Id to release TODO Adapt this
  for (genvar current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
    if (current_id == 0) begin
      assign next_id_to_release_onehot[current_id] = expect_new_delay_packed[current_id];
    end else begin
      assign next_id_to_release_onehot[current_id] = expect_new_delay_packed[current_id] && !|expect_new_delay_packed[current_id-1:0];
    end

    assign counters_d[current_id] = next_id_to_release_onehot[current_id] ? (counters_q[current_id] - buf_data_i[current_id] + 1) : (counters_q[current_id] + 1);
  end


  for (genvar current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (~rst_ni) begin
        counters_q[current_id] <= '0;
      end else begin
        counters_q[current_id] <= counters_q[current_id];
      end
    end
  end  

endmodule
