// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Linkedlist bank for messages in the simulated memory controller 

// Does not support direct replacement (simultaneous write and read in the RAM)
// Assumes that a message is received by the message bank before it should be released

module simmem_message_bank #(
    parameter int MessageWidth = 64,  // Width of the message including identifier
    parameter int TotalCapacity = 128
) (
    input logic clk_i,
    input logic rst_ni,

    // Reservation signals
    input logic [IDWidth-1:0] reservation_request_id_i,
    output logic [$clog2(TotalCapacity)-1:0] new_reserved_address_o,

    input logic reservation_request_ready_i,
    output logic reservation_request_valid_o,

    // Bank I/O signals
    input  logic [MessageWidth-1:0] data_i,
    output logic [MessageWidth-1:0] data_o,

    input logic [TotalCapacity-1:0] release_en_i, // multi-hot signal

    input  logic in_valid_i,
    output logic in_ready_o,
  
    input  logic out_ready_i,
    output logic out_valid_o
  );

  import simmem_pkg::ram_bank_e;
  import simmem_pkg::ram_port_e;

  // Read the data ID
  logic [IDWidth-1:0] data_in_id_field;
  assign data_in_id_field = data_i[IDWidth - 1:0];

  // Head, tail and length signals
  logic [$clog2(TotalCapacity)-1:0] heads_d[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] heads_q[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] tails_d[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] tails_q[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] reservation_tails_d[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] reservation_tails_q[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] actual_length_d[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] actual_length_q[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] reservation_length_d[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] reservation_length_q[2**IDWidth-1:0];

  // Output valid and address
  logic [$clog2(TotalCapacity)-1:0] current_output_valid_d[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] current_output_valid_q[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] current_output_address_d[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] current_output_address_q[2**IDWidth-1:0];

  // Valid bits and pointer to next arrays. Masks update the valid bits
  logic ram_valid_d[TotalCapacity-1:0];
  logic ram_valid_q[TotalCapacity-1:0];
  logic [TotalCapacity-1:0] ram_valid_q_packed;
  logic ram_valid_reservation_mask[TotalCapacity-1:0];
  logic ram_valid_out_mask[TotalCapacity-1:0];

  // Prepare the next RAM valid bit array
  for (genvar current_addr = 0; current_addr < TotalCapacity; current_addr = current_addr + 1) begin
    assign ram_valid_d[current_addr] = ram_valid_q[current_addr] ^
        (ram_valid_reservation_mask[current_addr]) ^ (ram_valid_out_mask[current_addr]);
  end

  // Find the next free address and transform next free address from one-hot to binary encoding
  logic next_free_ram_entry_onehot[TotalCapacity-1:0];  // Can be full zero
  logic [$clog2(TotalCapacity)-1:0] next_free_address_binary_masks[TotalCapacity-1:0];
  logic [TotalCapacity-1:0] next_free_address_binary_masks_rot90[$clog2(TotalCapacity)-1:0];
  logic [$clog2(TotalCapacity)-1:0] next_free_ram_entry_binary;

  assign new_reserved_address_o = next_free_ram_entry_binary;

  for (genvar current_addr = 0; current_addr < TotalCapacity; current_addr = current_addr + 1) begin
    assign next_free_address_binary_masks[current_addr] =
        next_free_ram_entry_onehot[current_addr] ? current_addr : '0;
  end
  for (genvar current_id = 0; current_id < TotalCapacity; current_id = current_id + 1) begin
    for (
        genvar current_addr_bit = 0;
        current_addr_bit < $clog2(TotalCapacity);
        current_addr_bit = current_addr_bit + 1
    ) begin
      assign next_free_address_binary_masks_rot90[current_addr_bit][current_id] =
          next_free_address_binary_masks[current_id][current_addr_bit];
    end
  end
  for (
      genvar current_addr_bit = 0;
      current_addr_bit < $clog2(TotalCapacity);
      current_addr_bit = current_addr_bit + 1
  ) begin
    assign next_free_ram_entry_binary[current_addr_bit] =
        |next_free_address_binary_masks_rot90[current_addr_bit];
  end

  // RAM instances and management signals
  logic req_ram[1:0];
  logic write_ram[1:0];

  logic [MessageWidth-1:0] wmask_ram;

  logic [$clog2(TotalCapacity)-1:0] addr_ram[1:0];
  logic [$clog2(TotalCapacity)-1:0] data_out_ram;

  assign wmask_ram = {$clog2(TotalCapacity) {1'b1}};

  prim_generic_ram_2p #(
    .Width(MessageWidth),
    .DataBitsPerMask(1),
    .Depth(TotalCapacity)
  ) message_ram_i (
    .clk_a_i     (clk_i),
    .clk_b_i     (clk_i),
    
    .a_req_i     (req_ram[RAM_IN]),
    .a_write_i   (write_ram[RAM_IN]),
    .a_wmask_i   (wmask_ram),
    .a_addr_i    (addr_ram[RAM_IN]),
    .a_wdata_i   (data_i),
    .a_rdata_o   (),
    
    .b_req_i     (req_ram[RAM_OUT]),
    .b_write_i   (write_ram[RAM_OUT]),
    .b_wmask_i   (wmask_ram),
    .b_addr_i    (addr_ram[RAM_OUT]),
    .b_wdata_i   (),
    .b_rdata_o   (data_out_ram)
  );

  for (genvar current_addr = 0; current_addr < TotalCapacity; current_addr = current_addr + 1) begin
    assign ram_valid_q_packed[current_addr] = ram_valid_q[current_addr];
  end

  assign next_free_ram_entry_onehot[0] = !ram_valid_q[0];
  for (genvar current_addr = 1; current_addr < TotalCapacity; current_addr = current_addr + 1) begin
    assign next_free_ram_entry_onehot[current_addr] =
        !ram_valid_q[current_addr] && &ram_valid_q_packed[current_addr - 1:0];
  end

  // Next AXI identifier to release

  logic next_id_to_release_onehot[2**IDWidth-1:0];
  logic [TotalCapacity-1:0] next_address_to_release_onehot_id[2**IDWidth-1:0];
  logic [2**IDWidth-1:0] next_id_to_release_onehot_packed;
  logic [TotalCapacity-1:0] next_id_to_release_multihot [2**IDWidth-2:0];
  logic [TotalCapacity-1:0][2**IDWidth-2:0] next_id_to_release_multihot_rot90;

  for (genvar current_id = 0; current_id < 2 ** IDWidth - 1; current_id = current_id + 1) begin
    assign next_id_to_release_onehot_packed[current_id] = next_id_to_release_onehot[current_id];

    for (genvar current_addr = 0; current_addr < TotalCapacity; current_addr = current_addr + 1) begin
      assign next_id_to_release_multihot[current_id][current_addr] = |(actual_length_q[current_id]) && heads_q[current_id] == current_addr;
      assign next_id_to_release_multihot_rot90[current_addr][current_id] = next_id_to_release_multihot[current_id][current_addr];
    end
  end

  // Next Id to release from RAM
  for (genvar current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
    for (
      genvar current_addr = 0; current_addr < TotalCapacity; current_addr = current_addr + 1
    ) begin

      if (current_addr == 0) begin
        assign next_address_to_release_onehot_id[current_id][current_addr] = next_id_to_release_multihot[current_id][current_addr];
      end else begin
        assign next_address_to_release_onehot_id[current_id][current_addr] = next_id_to_release_multihot[current_id][current_addr] && !(next_id_to_release_multihot_rot90[current_id-1:0]);
      end
      
    if (current_id == 0) begin
      assign next_id_to_release_onehot[current_id] =
          (heads_q[current_id] && release_en_i[current_id];
    end else begin
      assign next_id_to_release_onehot[current_id] =
          (out_buf_id_valid_q[current_id] || in_valid_i && in_ready_o && current_id ==
          data_in_id_field) && release_en_i[current_id] &&
          !|((out_buf_id_valid_q_packed[current_id-1:0] |
          ({current_id{in_valid_i && in_ready_o}} &
          next_id_to_release_multihot[current_id-1:0])) & release_en_i[current_id-1:0]);
      end
    end
  end



  // RamValid masks

  for (
      genvar current_addr = 0; current_addr < TotalCapacity; current_addr = current_addr + 1
  ) begin : ram_valid_masks_generation
    assign ram_valid_reservation_mask[current_addr] = next_free_ram_entry_binary == current_addr && reservation_request_valid_o && reservation_request_ready_i;
    assign ram_valid_out_mask[current_addr] = next_address_to_release_valid_i && next_address_to_release_i == current_addr && out_valid_o && out_ready_o;
  end

  // Input is ready if there is room and data is not flowing out
  assign in_ready_o = |(~ram_valid_q_packed);
  assign out_valid_o = next_address_to_release_i;

  for (
      genvar current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1
  ) begin : id_isolated_comb

    always_comb begin
      // Default assignments
      heads_d[current_id] = heads_q[current_id];
      tails_d[current_id] = tails_q[current_id];
      actual_length_d[current_id] = actual_length_q[current_id];
      buf_data_valid[current_id] = 1'b0;
      update_heads_from_ram_d[current_id] = 1'b0;
      ram_valid_apply_in_mask_id[current_id] = 1'b0;
      ram_valid_apply_out_mask_id[current_id] = 1'b0;
      out_buf_id_d[current_id] = out_buf_id_actual_content[current_id];
      out_buf_id_valid_d[current_id] = out_buf_id_valid_q[current_id];
      update_out_buf_from_ram_d[current_id] = 1'b0;

      // Default RAM signals
      for (int ram_bank = 0; ram_bank < 2; ram_bank = ram_bank + 1) begin
        for (int ram_port = 0; ram_port < 2; ram_port = ram_port + 1) begin
          req_ram_id[ram_bank][ram_port][current_id] = 1'b0;
          write_ram_id[ram_bank][ram_port][current_id] = 1'b0;
          addr_ram_id[ram_bank][ram_port][current_id] = '0;
        end
      end

      // Expose output buffer data
      if (out_buf_id_valid_q[current_id]) begin : out_buf_valid
        buf_data_o[current_id] = out_buf_id_actual_content[current_id];
        buf_data_valid[current_id] = 1'b1;
      end else if (in_valid_i && in_ready_o && current_id == data_id_i) begin : out_buf_direct
        buf_data_o[current_id] = data_noid_i};
        buf_data_valid[current_id] = 1'b1;
      end

      // Handshakes: start by output to avoid blocking output with simultaneous inputs
      if (next_id_to_release_onehot_i[current_id] && out_buf_id_valid_q[current_id]) begin : out_handshake

        // If the RAM is not empty
        if (id_valid_ram[current_id]) begin : out_handshake_ram_valid
          update_heads_from_ram_d[current_id] = 1'b1;
          update_out_buf_from_ram_d[current_id] = 1'b1;

          req_ram_id[STRUCT_RAM][RAM_OUT][current_id] = 1'b1;
          write_ram_id[STRUCT_RAM][RAM_OUT][current_id] = 1'b0;
          addr_ram_id[STRUCT_RAM][RAM_OUT][current_id] = heads_actual[current_id];

          // Free the head entry in the RAM using a XOR mask
          ram_valid_apply_out_mask_id[current_id] = 1'b1;

          actual_length_d[current_id] -= 1;

          // Update the head position in the RAM
          req_ram_id[NEXT_ELEM_RAM][RAM_OUT][current_id] = 1'b1;
          write_ram_id[NEXT_ELEM_RAM][RAM_OUT][current_id] = 1'b0;
          addr_ram_id[NEXT_ELEM_RAM][RAM_OUT][current_id] = heads_actual[current_id];

        end else if (in_valid_i && in_ready_o && current_id == data_id_i
            ) begin : out_handshake_refill_buf_from_input
          out_buf_id_d[current_id] = data_noid_i;
        end else begin : out_handshake_id_now_empty
          out_buf_id_valid_d[current_id] = 1'b0;
        end

      end

      if (in_valid_i && in_ready_o && current_id == data_id_i) begin : in_handshake

        if (!out_buf_id_valid_q[current_id]) begin : in_handshake_buf_empty
          // Direct flow from input to output is already implemented in the output handshake block 
          if (!(next_id_to_release_onehot_i[current_id])
              ) begin : in_handshake_fill_buf
            out_buf_id_valid_d[current_id] = 1'b1;
            out_buf_id_d[current_id] = data_noid_i;
          end
        end else begin : in_handshake_buf_valid

          // Mark address as taken
          ram_valid_apply_in_mask_id[current_id] = 1'b1;

          actual_length_d[current_id] = actual_length_q[current_id] + 1;

          // Take the input data, considering cases where the RAM list is empty or not
          if (actual_length_q[current_id] >= 2 || actual_length_q[current_id] == 1 &&
              !(next_id_to_release_onehot_i[current_id])
              ) begin : in_handshake_ram_will_stay_valid
            tails_d[current_id] = next_free_ram_entry_binary;

            // Store into next elem RAM
            req_ram_id[NEXT_ELEM_RAM][RAM_IN][current_id] = 1'b1;
            write_ram_id[NEXT_ELEM_RAM][RAM_IN][current_id] = 1'b1;
            addr_ram_id[NEXT_ELEM_RAM][RAM_IN][current_id] = tails_q[current_id];

            // Store into struct RAM
            req_ram_id[STRUCT_RAM][RAM_IN][current_id] = 1'b1;
            write_ram_id[STRUCT_RAM][RAM_IN][current_id] = 1'b1;
            addr_ram_id[STRUCT_RAM][RAM_IN][current_id] = next_free_ram_entry_binary;

          end else begin : in_handshake_initiate_ram_linkedlist
            heads_d[current_id] = next_free_ram_entry_binary;
            tails_d[current_id] = next_free_ram_entry_binary;

            // Store into struct RAM and mark address as taken
            req_ram_id[STRUCT_RAM][RAM_IN][current_id] = 1'b1;
            write_ram_id[STRUCT_RAM][RAM_IN][current_id] = 1'b1;
            addr_ram_id[STRUCT_RAM][RAM_IN][current_id] = next_free_ram_entry_binary;

          end
        end
      end
    end
  end


  for (genvar current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (~rst_ni) begin
        heads_q[current_id] <= '0;
        tails_q[current_id] <= '0;
        actual_length_q[current_id] <= '0;
        update_heads_from_ram_q[current_id] <= '0;

        out_buf_id_valid_q[current_id] <= '0;
        out_buf_id_q[current_id] <= '0;
        update_out_buf_from_ram_q[current_id] <= '0;
      end else begin
        heads_q[current_id] <= heads_d[current_id];
        tails_q[current_id] <= tails_d[current_id];
        actual_length_q[current_id] <= actual_length_d[current_id];
        update_heads_from_ram_q[current_id] <= update_heads_from_ram_d[current_id];

        out_buf_id_q[current_id] <= out_buf_id_d[current_id];
        out_buf_id_valid_q[current_id] <= out_buf_id_valid_d[current_id];
        update_out_buf_from_ram_q[current_id] <= update_out_buf_from_ram_d[current_id];
      end
    end
  end

  for (genvar current_addr = 0; current_addr < TotalCapacity; current_addr = current_addr + 1) begin
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (~rst_ni) begin
        ram_valid_q[current_addr] <= 1'b0;
      end else begin
        ram_valid_q[current_addr] <= ram_valid_d[current_addr];
      end
    end
  end

endmodule
