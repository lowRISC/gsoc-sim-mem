// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Linkedlist bank for messages in the simulated memory controller 

// Does not support direct replacement (simultaneous write and read in the RAM)
// Assumes that a message is received by the message bank before it should be released

// TODO Manage the arrival of bursts

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
  logic [$clog2(TotalCapacity)-1:0] actual_heads_d[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] pre_update_actual_heads_q[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] actual_heads_q[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] reservation_heads_d[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] pre_update_reservation_heads_q[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] reservation_heads_q[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] tails_d[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] pre_update_tails_q[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] tails_q[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] actual_length_d[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] actual_length_q[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] reservation_length_d[2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] reservation_length_q[2**IDWidth-1:0];

  logic update_actual_heads_id_d[2**IDWidth-1:0];
  logic update_actual_heads_id_q[2**IDWidth-1:0];
  logic update_reservation_heads_from_ram_id_d[2**IDWidth-1:0];
  logic update_reservation_heads_from_ram_id_q[2**IDWidth-1:0];

  for (genvar current_id = 0; current_id < TotalCapacity; current_id = current_id + 1) begin
    assign actual_heads_q[current_id] = update_actual_heads_id_q[current_id] ? next_free_ram_entry_binary : pre_update_actual_heads_q[current_id]; 
    assign reservation_heads_q[current_id] = update_reservation_heads_from_ram_id_q[current_id] ? next_free_ram_entry_binary : pre_update_reservation_heads_q[current_id]; 
    assign tails_q[current_id] = current_output_valid_q && out_ready_i && current_output_id_q ? data_out_ram[NEXT_ELEM_RAM] : pre_update_tails_q[current_id];
  end

  // Output valid and address
  logic current_output_valid_d;
  logic current_output_valid_q;
  logic [IDWidth-1:0] current_output_identifier_id[2**IDWidth-1:0]; // Useful to update the tail and to not store IDs
  logic [IDWidth-1:0] current_output_identifier_id[2**IDWidth-1:0];
  logic [IDWidth-1:0] current_output_identifier_id_d;
  logic [IDWidth-1:0] current_output_identifier_id_q;
  // logic [TotalCapacity-1:0] current_output_address_onehot_id[2**IDWidth-1:0];
  // logic [TotalCapacity-1:0] current_output_address_onehot_id[2**IDWidth-1:0];
  logic [TotalCapacity-1:0] current_output_address_onehot_d;
  logic [TotalCapacity-1:0] current_output_address_onehot_q;

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

  logic [$clog2(TotalCapacity)-1:0] data_out_ram[1:0];

  logic req_ram_id[1:0][1:0][2**IDWidth-1:0];
  logic [2**IDWidth-1:0] req_ram_id_packed[1:0][1:0];
  logic [2**IDWidth-1:0] write_ram_id[1:0][1:0];

  logic [$clog2(TotalCapacity)-1:0] addr_ram[1:0][1:0];
  logic [$clog2(TotalCapacity)-1:0] addr_ram_id[1:0][1:0][2**IDWidth-1:0];
  logic [2**IDWidth-1:0] addr_ram_masks_rot90[1:0][1:0][$clog2(TotalCapacity)-1:0];

  for (genvar ram_bank = 0; ram_bank < 2; ram_bank = ram_bank + 1) begin
    for (genvar ram_port = 0; ram_port < 2; ram_port = ram_port + 1) begin
      // Aggregate the RAM requests
      assign req_ram[ram_bank][ram_port] = |req_ram_id_packed[ram_bank][ram_port];
      assign write_ram[ram_bank][ram_port] = |write_ram_id[ram_bank][ram_port];

      for (genvar current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
        assign req_ram_id_packed[ram_bank][ram_port][current_id] =
            req_ram_id[ram_bank][ram_port][current_id];

        for (
            genvar current_addr_bit = 0;
            current_addr_bit < $clog2(TotalCapacity);
            current_addr_bit = current_addr_bit + 1
        ) begin
          assign addr_ram_masks_rot90[ram_bank][ram_port][current_addr_bit][current_id] =
              addr_ram_id[ram_bank][ram_port][current_id][current_addr_bit];
        end
      end
      for (
          genvar current_addr_bit = 0;
          current_addr_bit < $clog2(TotalCapacity);
          current_addr_bit = current_addr_bit + 1
      ) begin
        assign addr_ram[ram_bank][ram_port][current_addr_bit] =
            |addr_ram_masks_rot90[ram_bank][ram_port][current_addr_bit];
      end
    end
  end

  assign wmask_ram = {$clog2(TotalCapacity) {1'b1}};

  prim_generic_ram_2p #(
    .Width(MessageWidth),
    .DataBitsPerMask(1),
    .Depth(TotalCapacity)
  ) i_message_ram (
    .clk_a_i     (clk_i),
    .clk_b_i     (clk_i),
    
    .a_req_i     (req_ram[STRUCT_RAM][RAM_IN]),
    .a_write_i   (write_ram[STRUCT_RAM][RAM_IN]),
    .a_wmask_i   (wmask_ram),
    .a_addr_i    (addr_ram[STRUCT_RAM][RAM_IN]),
    .a_wdata_i   (data_i),
    .a_rdata_o   (),
    
    .b_req_i     (req_ram[STRUCT_RAM][RAM_OUT]),
    .b_write_i   (write_ram[STRUCT_RAM][RAM_OUT]),
    .b_wmask_i   (wmask_ram),
    .b_addr_i    (addr_ram[STRUCT_RAM][RAM_OUT]),
    .b_wdata_i   (),
    .b_rdata_o   (data_out_ram[STRUCT_RAM])
  );

  prim_generic_ram_2p #(
    .Width($clog2(TotalCapacity)),
    .DataBitsPerMask(1),
    .Depth(TotalCapacity)
  ) i_next_element_ram (
    .clk_a_i     (clk_i),
    .clk_b_i     (clk_i),
    
    .a_req_i     (req_ram[NEXT_ELEM_RAM][RAM_IN]),
    .a_write_i   (write_ram[NEXT_ELEM_RAM][RAM_IN]),
    .a_wmask_i   (wmask_ram),
    .a_addr_i    (addr_ram[NEXT_ELEM_RAM][RAM_IN]),
    .a_wdata_i   (next_free_ram_entry_binary),
    .a_rdata_o   (),
    
    .b_req_i     (req_ram[NEXT_ELEM_RAM][RAM_OUT]),
    .b_write_i   (write_ram[NEXT_ELEM_RAM][RAM_OUT]),
    .b_wmask_i   (wmask_ram),
    .b_addr_i    (addr_ram[NEXT_ELEM_RAM][RAM_OUT]),
    .b_wdata_i   (),
    .b_rdata_o   (data_out_ram[NEXT_ELEM_RAM])
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

  // All the cells at 1'b1 represent the candidate AXI ids candidate to release
  logic [2**IDWidth-1:0] next_id_to_release_multihot;
  // The unique cell at 1'b1 represents the lowest-order AXI id candidate to release if any
  logic [2**IDWidth-1:0] next_id_to_release_onehot;
  // All the cells at 1'b1 represent (address, AXI id) ready for release
  logic [2**IDWidth-2:0][TotalCapacity-1:0] next_address_to_release_multihot_id;
  // For each AXI id, the unique cell at 1'b1 represents the address ready for release if any
  logic [TotalCapacity-1:0] next_address_to_release_onehot_id[2**IDWidth-1:0];
  logic [TotalCapacity-1:0][2**IDWidth-1:0] next_address_to_release_onehot_rot90_filtered;

  // Next id and address to release from RAM
  for (genvar current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin

    assign next_id_to_release_multihot[current_id] = |next_address_to_release_onehot_id[current_id];
    
    if (current_id == 0) begin
      assign next_id_to_release_onehot[current_id] = next_id_to_release_multihot[current_id];
    end else begin
      assign next_id_to_release_onehot[current_id] = next_id_to_release_multihot[current_id] && !|(next_id_to_release_multihot[current_id]);
    end

    for (genvar current_addr = 0; current_addr < TotalCapacity; current_addr = current_addr + 1) begin
      assign next_address_to_release_multihot_id[current_id][current_addr] = |(actual_length_q[current_id]) && heads_q[current_id] == current_addr && release_en_i[current_id];
      if (current_addr == 0) begin
        assign next_address_to_release_onehot_id[current_id][current_addr] = next_address_to_release_multihot_id[current_id][current_addr];
      end else begin
        assign next_address_to_release_onehot_id[current_id][current_addr] = next_address_to_release_multihot_id[current_id][current_addr] && !(next_address_to_release_multihot_id[current_id][current_addr-1:0]);
      end
      assign next_address_to_release_onehot_rot90_filtered[current_addr][current_id] = next_address_to_release_onehot_id[current_id][current_addr] && next_id_to_release_onehot[current_id];
    end
  end

  for (genvar current_addr = 0; current_addr < TotalCapacity; current_addr = current_addr + 1) begin
    assign current_output_address_onehot_d[current_addr] = |next_address_to_release_onehot_rot90_filtered[current_addr];
  end

  // RAM valid masks
  for (
      genvar current_addr = 0; current_addr < TotalCapacity; current_addr = current_addr + 1
  ) begin : ram_valid_masks_generation
    assign ram_valid_reservation_mask[current_addr] = next_free_ram_entry_binary == current_addr && reservation_request_valid_o && reservation_request_ready_i; // TODO And no input handshake going on
    assign ram_valid_out_mask[current_addr] = current_output_address_onehot_q[current_addr] && out_valid_o && out_ready_i;
    // assign ram_valid_out_mask[current_addr] = current_output_valid_q && current_output_address_onehot_q[current_addr] && out_ready_i;
  end

  // Signals for input ready calculation
  logic [2**IDWidth] is_id_reserved_filtered;
  for (genvar current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
    assign is_id_reserved_filtered[current_id] = data_in_id_field == current_id && |(reservation_length_q[current_id]);
  end

  // Input is ready if there is room and data is not flowing out
  assign in_ready_o = in_valid_i && |is_id_reserved_filtered; // AXI 4 allows ready to depend on the valid signal
  assign out_valid_o = current_output_valid_q;
  assign reservation_request_valid_o = !(in_ready_o && in_valid_i) && |(~ram_valid_q_packed);

  for (
      genvar current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1
  ) begin : id_isolated_comb

    always_comb begin
      // Default assignments
      actual_heads_d[current_id] = actual_heads_q[current_id];
      reservation_heads_d[current_id] = reservation_heads_q[current_id];
      tails_d[current_id] = tails_q[current_id];
      actual_length_d[current_id] = actual_length_q[current_id];
      reservation_length_d[current_id] = reservation_length_q[current_id];

      update_actual_heads_id_d[current_id] = 1'b0;
      update_reservation_heads_from_ram_id_d[current_id] = 1'b0;

      // current_output_valid_id[current_id] = '0;
      current_output_identifier_id[current_id] = '0;

      // Default RAM signals
      for (int ram_bank = 0; ram_bank < 2; ram_bank = ram_bank + 1) begin
        for (int ram_port = 0; ram_port < 2; ram_port = ram_port + 1) begin
          req_ram_id[ram_bank][ram_port][current_id] = 1'b0;
          write_ram_id[ram_bank][ram_port][current_id] = 1'b0;
          addr_ram_id[ram_bank][ram_port][current_id] = '0;
        end
      end

      // Input handshake
      if (in_ready_o && in_valid_i && data_in_id_field == current_id) begin : in_handshake

        update_actual_heads_id_d[current_id] = 1'b1;

        actual_length_d[current_id] = actual_length_d[current_id] + 1;
        reservation_length_d[current_id] = reservation_length_d[current_id] - 1;

        // Store the data
        req_ram_id[STRUCT_RAM][RAM_IN][current_id] = 1'b1;
        write_ram_id[STRUCT_RAM][RAM_IN][current_id] = 1'b1;
        addr_ram_id[STRUCT_RAM][RAM_IN][current_id] = actual_heads_q[current_id];

        // Update the actual head position
        req_ram_id[NEXT_ELEM_RAM][RAM_OUT][current_id] = 1'b1;
        write_ram_id[NEXT_ELEM_RAM][RAM_OUT][current_id] = 1'b0;
        addr_ram_id[NEXT_ELEM_RAM][RAM_OUT][current_id] = actual_heads_q[current_id];

      end else if (reservation_request_ready_i && reservation_request_valid_o && reservation_request_id_i == current_id) begin : reservation

        update_reservation_heads_from_ram_id_d[current_id] = 1'b1;

        reservation_length_d[current_id] = reservation_length_d[current_id] + 1;

        // Update the reserved head position
        req_ram_id[NEXT_ELEM_RAM][RAM_IN][current_id] = 1'b1;
        write_ram_id[NEXT_ELEM_RAM][RAM_IN][current_id] = 1'b1;
        addr_ram_id[NEXT_ELEM_RAM][RAM_IN][current_id] = reservation_heads_q[current_id];
      end

      if (next_id_to_release_onehot[current_id]) begin : out_preparation_handshake

        req_ram_id[STRUCT_RAM][RAM_OUT][current_id] = 1'b1;
        write_ram_id[STRUCT_RAM][RAM_OUT][current_id] = 1'b0;
        addr_ram_id[STRUCT_RAM][RAM_OUT][current_id] = tails_q[current_id];

        // Update the actual head position
        req_ram_id[NEXT_ELEM_RAM][RAM_OUT][current_id] = 1'b1;
        write_ram_id[NEXT_ELEM_RAM][RAM_OUT][current_id] = 1'b0;
        addr_ram_id[NEXT_ELEM_RAM][RAM_OUT][current_id] = tails_q[current_id];
      end
    
      if (current_output_valid_q && out_ready_i && current_output_id_q == current_output_id_q) begin
        actual_length_d[current_id] = actual_length_d[current_id] - 1;
        reservation_length_d[current_id] = reservation_length_d[current_id] - 1;
      end
    end
  end

  // Outputs
  assign current_output_valid_d = |next_id_to_release_onehot || (current_output_valid_q && !out_ready_i);

  for (genvar current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (~rst_ni) begin
        pre_update_actual_heads_q[current_id] <= '0;
        pre_update_reservation_heads_q[current_id] <= '0;
        pre_update_tails_q[current_id] <= '0;
        actual_length_q[current_id] <= '0;
        reservation_length_q[current_id] <= '0;

        update_actual_heads_id_q[current_id] <= '0;
        update_reservation_heads_from_ram_id_q[current_id] <= '0;

        current_output_valid_q <= '0;
        current_output_identifier_q <= '0;
        current_output_address_onehot_q <= '0;
      end else begin
        pre_update_actual_heads_q[current_id] <= actual_heads_d[current_id];
        pre_update_reservation_heads_q[current_id] <= reservation_heads_d[current_id];
        pre_update_tails_q[current_id] <= tails_d[current_id];
        actual_length_q[current_id] <= actual_length_d[current_id];
        reservation_length_q[current_id] <= reservation_length_d[current_id];

        update_actual_heads_id_q[current_id] <= update_actual_heads_id_d[current_id];
        update_reservation_heads_from_ram_id_q[current_id] <= update_reservation_heads_from_ram_id_d[current_id];

        current_output_valid_q <= current_output_valid_d;
        current_output_identifier_q <= current_output_identifier_d;
        current_output_address_onehot_q <= current_output_address_onehot_d;
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
