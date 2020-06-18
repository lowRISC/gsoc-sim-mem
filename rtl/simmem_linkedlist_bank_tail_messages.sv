// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Linkedlist bank for messages in the simulated memory controller 

module simmem_linkedlist_bank_tail_messages #(
    parameter int StructWidth = 64,  // Width of the message including identifier
    parameter int IDWidth = 4
) (
    input logic clk_i,
    input logic rst_ni,

    // Input from the releaser
    input logic [2**IDWidth-1:0] release_en_i,

    output logic [2**IDWidth-1:0] next_id_to_release_onehot_o,

    input logic [StructWidth-IDWidth-1:0] buf_data_i [2**IDWidth-1:0],
    input logic [2**IDWidth-1:0] buf_data_valid_i,

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

  // TODO Maybe this is not the best place to put the AND with the out_ready_i signal.
  // This OR is necessary at some point, to prevent updates in the linkedlist core.
  assign next_id_to_release_onehot_o = next_id_to_release_onehot & out_ready_i;


  // Merge output data from all the identifiers
  logic [StructWidth-1:0] data_o_id_mask[2**IDWidth-1:0];
  logic [2**IDWidth-1:0] data_o_id_mask_rot90[StructWidth-1:0];
  for (genvar current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
    assign data_o_id_mask[current_id] =
        buf_data_i[current_id] & {StructWidth{next_id_to_release_onehot[current_id]}};
  end
  for (genvar current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
    for (
        genvar current_struct_bit = 0;
        current_struct_bit < StructWidth;
        current_struct_bit = current_struct_bit + 1
    ) begin
      assign data_o_id_mask_rot90[current_struct_bit][current_id] =
          data_o_id_mask[current_id][current_struct_bit];
    end
  end
  for (
      genvar current_struct_bit = 0;
      current_struct_bit < StructWidth;
      current_struct_bit = current_struct_bit + 1
  ) begin
    assign data_o[current_struct_bit] = |data_o_id_mask_rot90[current_struct_bit];
  end

  // Next Id to release
  for (genvar current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
    if (current_id == 0) begin
      assign next_id_to_release_onehot[current_id] = buf_data_valid_i[current_id] && release_en_i[current_id];
    end else begin
      assign next_id_to_release_onehot[current_id] = buf_data_valid_i[current_id] && release_en_i[current_id] &&
          !|(buf_data_valid_i[current_id-1:0] & release_en_i[current_id-1:0]);
    end
  end

endmodule
