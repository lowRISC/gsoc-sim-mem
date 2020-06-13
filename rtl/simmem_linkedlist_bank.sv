// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//

// This modules assumes that no capacity overflow occurs.

module simmem_linkedlist_bank #(
  parameter int StructWidth   = 64, // Width of the message including identifier.
  parameter int TotalCapacity = 128,
  parameter int IDWidth       = 4,
  localparam int StructListElementWidth = StructWidth  - IDWidth
)(
  input logic clk_i,
  input logic rst_ni,

  input logic [2**IDWidth-1:0] release_en_i, // Input from the releaser

  input logic [StructWidth-1:0] data_i, // The identifier should be the first IDWidth bits
  output logic [StructWidth-1:0] data_o,

  input logic in_valid_i,
  output logic in_ready_o,

  input logic out_ready_i,
  output logic out_valid_o
);

  typedef enum logic {
    STRUCT_RAM     = 1'b0,
    NEXT_ELEM_RAM  = 1'b1
  } ram_bank_t;

  // Read the data ID
  logic [IDWidth-1:0] data_in_id_field;
  assign data_in_id_field = data_i[IDWidth-1:0];

  // Head, tail and non-empty signals
  logic [$clog2(TotalCapacity)-1:0] heads_d [2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] heads_q [2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] tails_d [2**IDWidth-1:0];
  logic [$clog2(TotalCapacity)-1:0] tails_q [2**IDWidth-1:0]; 
  logic [$clog2(TotalCapacity)-1:0] linkedlist_length_d [2**IDWidth-1:0]; 
  logic [$clog2(TotalCapacity)-1:0] linkedlist_length_q [2**IDWidth-1:0];
  logic [2**IDWidth-1:0] id_valid_ram; // Indicates, for each ID, whether the list is not empty. Keep packed for fast XORing

  for (genvar current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
    assign id_valid_ram[current_id] = linkedlist_length_q[current_id] == '0;
  end

  // Valid bits and pointer to next arrays. Masks update the valid bits
  logic ram_valid_d [TotalCapacity-1:0];
  logic [TotalCapacity-1:0] ram_valid_q; // Pack only the Q signal
  logic ram_valid_in_mask [TotalCapacity-1:0]; // TODO Generate statically (instead of currently dynamically) ?
  logic ram_valid_out_mask [TotalCapacity-1:0]; 
  logic ram_valid_apply_in_mask_id [2**IDWidth-1:0];
  logic ram_valid_apply_out_mask_id [2**IDWidth-1:0];

  logic [2**IDWidth-1:0] ram_valid_apply_in_mask_id_packed;
  logic [2**IDWidth-1:0] ram_valid_apply_out_mask_id_packed;

  for (genvar current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
    assign ram_valid_apply_in_mask_id_packed[current_id] = ram_valid_apply_in_mask_id[current_id]; // TODO Is this useless?
    assign ram_valid_apply_out_mask_id_packed[current_id] = ram_valid_apply_out_mask_id[current_id]; // TODO Is this useless?
  end

  for (genvar current_address = 0; current_address < TotalCapacity; current_address = current_address + 1) begin // FIXME here
    assign ram_valid_d[current_address] = ram_valid_q[current_address] ^ (ram_valid_in_mask[current_address] && |ram_valid_apply_in_mask_id_packed) ^ (ram_valid_out_mask[current_address] && |ram_valid_apply_out_mask_id_packed);
  end

  // This block is replaced by the assignment below
  // always_comb begin: ram_valid_apply_masks
  //   ram_valid_d = ram_valid_q;
  //   if (|ram_valid_apply_in_mask_id) begin
  //     ram_valid_d ^= ram_valid_in_mask;
  //   end
  //   if (|ram_valid_apply_out_mask_id) begin
  //     ram_valid_d ^= ram_valid_out_mask;
  //   end
  // end: ram_valid_apply_masks

  // TODO Uncomment for the unpacked way
  // assign ram_valid_d = ram_valid_q ^ (ram_valid_in_mask & {TotalCapacity{|ram_valid_apply_in_mask_id}}) ^ (ram_valid_out_mask & {TotalCapacity{|ram_valid_apply_out_mask_id}});

  // for (genvar current_address = 0; current_address < TotalCapacity; current_address = current_address + 1) begin // TODO Fix here
  //   assign ram_valid_d[current_address] = ram_valid_q[current_address] ^ (ram_valid_in_mask[current_address] & |ram_valid_apply_in_mask_id) ^ (ram_valid_out_mask[current_address] & |ram_valid_apply_out_mask_id);
  // end

  // Merge output data
  logic is_data_o_id [2**IDWidth-1:0];
  logic [IDWidth-1:0] data_o_id_mask [2**IDWidth-1:0];
  logic [2**IDWidth-1:0] data_o_id_mask_rot90 [IDWidth-1:0];
  for (genvar current_id = 0; current_id < 2**IDWidth; current_id = current_id + 1) begin
    assign data_o_id_mask[current_id] = current_id[IDWidth-1:0] & {IDWidth{is_data_o_id[current_id]}};
  end
  for (genvar i = 0; i < 2**IDWidth; i = i + 1) begin
    for (genvar j = 0; j < IDWidth; j = j + 1) begin
      assign data_o_id_mask_rot90[j][i] = data_o_id_mask[i][j];
    end
  end
  for (genvar current_id_bit = 0; current_id_bit < IDWidth; current_id_bit = current_id_bit + 1) begin
    assign data_o[current_id_bit] = |data_o_id_mask_rot90[current_id_bit]; // TODO Make sure the bit ordering is good
  end
  assign data_o[StructWidth-1:IDWidth] = data_out_struct_ram;

  // Find the next free address and transform next free address from one-hot to binary encoding
  logic next_free_ram_entry_onehot [TotalCapacity-1:0]; // Can be full zero if there is no free space in RAM
  logic [$clog2(TotalCapacity)-1:0] next_free_ram_entry_binary;
  logic [$clog2(TotalCapacity)-1:0] next_free_address_binary_masks [TotalCapacity-1:0];
  logic [TotalCapacity-1:0] next_free_address_binary_masks_rot90 [$clog2(TotalCapacity)-1:0];
  
  for (genvar current_address = 0; current_address < TotalCapacity; current_address=current_address+1) begin
    assign next_free_address_binary_masks[current_address] = next_free_ram_entry_onehot[current_address] ? current_address : '0;
  end
  for (genvar i = 0; i < TotalCapacity; i = i + 1) begin
    for (genvar j = 0; j < $clog2(TotalCapacity); j = j + 1) begin
      assign next_free_address_binary_masks_rot90[j][i] = next_free_address_binary_masks[i][j];
    end
  end
  for (genvar current_address_bit = 0; current_address_bit < $clog2(TotalCapacity); current_address_bit = current_address_bit + 1) begin
    assign next_free_ram_entry_binary[current_address_bit] = |next_free_address_binary_masks_rot90[current_address_bit];
  end

  // Find the next id to release (one-hot)
  logic [2**IDWidth-1:0] next_id_to_release;

  // RAM instances and management signals
  logic req_ram [1:0];
  logic write_ram [1:0];
  logic [2**IDWidth-1:0] req_ram_id [1:0];
  logic [2**IDWidth-1:0] write_ram_id [1:0];
  
  logic [StructListElementWidth-1:0] wmask_struct_ram;
  logic [$clog2(TotalCapacity)-1:0] wmask_next_elem_ram;
  
  logic [$clog2(TotalCapacity)-1:0] addr_ram [1:0];
  logic [$clog2(TotalCapacity)-1:0] addr_ram_id [1:0][2**IDWidth-1:0];
  logic [2**IDWidth-1:0] addr_ram_masks_rot90 [1:0][$clog2(TotalCapacity)-1:0];

  for (genvar ram_bank = 0; ram_bank < 2; ram_bank = ram_bank+1) begin
    // Aggregate the ram requests
    assign req_ram[ram_bank] = |req_ram_id[ram_bank];
    assign write_ram[ram_bank] = |write_ram_id[ram_bank];

    for (genvar i = 0; i < 2**IDWidth; i = i + 1) begin
      for (genvar j = 0; j < $clog2(TotalCapacity); j = j + 1) begin
        assign addr_ram_masks_rot90[ram_bank][j][i] = addr_ram_id[ram_bank][i][j];
      end
    end
    for (genvar current_address_bit = 0; current_address_bit < $clog2(TotalCapacity); current_address_bit = current_address_bit + 1) begin
      assign addr_ram[ram_bank][current_address_bit] = |addr_ram_masks_rot90[ram_bank][current_address_bit];
    end
  end

  logic [StructWidth-IDWidth-1:0] data_in_noid;
  logic [StructWidth-IDWidth-1:0] data_out_struct_ram;
  logic [$clog2(TotalCapacity)-1:0] data_out_next_elem_ram;

  assign data_in_noid = data_i[StructWidth-1:IDWidth];
  assign wmask_struct_ram = {StructListElementWidth{1'b1}};
  assign wmask_next_elem_ram = {$clog2(TotalCapacity){1'b1}};

  prim_ram_1p #(
    .Width(StructListElementWidth),
    .DataBitsPerMask(1), // TODO Configure correctly the masks, or use a non-masked RAM
    .Depth(TotalCapacity)
  ) struct_ram_i (
    .clk_i     (clk_i),
    .req_i     (req_ram[STRUCT_RAM]),
    .write_i   (write_ram[STRUCT_RAM]),
    .wmask_i   (wmask_struct_ram),
    .addr_i    (addr_ram[STRUCT_RAM]),
    .wdata_i   (data_in_noid),
    .rdata_o   (data_out_struct_ram)
  );

  prim_ram_1p #(
    .Width($clog2(TotalCapacity)),
    .DataBitsPerMask(1),
    .Depth(TotalCapacity)
  ) next_elem_ram_i (
    .clk_i     (clk_i),
    .req_i     (req_ram[NEXT_ELEM_RAM]),
    .write_i   (write_ram[NEXT_ELEM_RAM]),
    .wmask_i   (wmask_next_elem_ram),
    .addr_i    (addr_ram[NEXT_ELEM_RAM]),
    .wdata_i   (next_free_ram_entry_binary),
    .rdata_o   (data_out_next_elem_ram)
  );

  // // Next free addresses
  // assign next_free_ram_entry_onehot[0] = !|ram_valid_q;
  // assign next_free_ram_entry_onehot[1] = !ram_valid_q[0] && !(next_free_ram_entry_onehot[0]);
  // for (genvar current_address = 2; current_address < TotalCapacity; current_address = current_address + 1) begin
  //   assign next_free_ram_entry_onehot[current_address] = !(ram_valid_q[current_address-1]) && !(|(next_free_ram_entry_onehot[current_address-1:0]));
  // end

  // Next free addresses
  // logic next_free_ram_entry_onehot_or_reduction [TotalCapacity-2:0];
  // for (genvar current_address = 1; current_address < TotalCapacity; current_address = current_address + 1) begin
  //   always_comb begin // TODO Remove the always comb, but this gives combinatorial loop.
  //     for (int i = 0; i <= current_address; i++) begin
  //       next_free_ram_entry_onehot_or_reduction[current_address-1] = next_free_ram_entry_onehot_or_reduction[current_address-1] || 
  //     end 
  //   end
  // end

  assign next_free_ram_entry_onehot[0] = !ram_valid_q[0];
  for (genvar current_address = 1; current_address < TotalCapacity; current_address = current_address + 1) begin
    assign next_free_ram_entry_onehot[current_address] = !ram_valid_q[current_address] && &ram_valid_q[current_address-1:0];
  end

    // Next free addresses
  // logic next_free_ram_entry_onehot_still_not_one [TotalCapacity-2:0];
  
  // assign next_free_ram_entry_onehot[0] = !|ram_valid_q;
  // assign next_free_ram_entry_onehot_still_not_one[0] = !(next_free_ram_entry_onehot[0]);

  // assign next_free_ram_entry_onehot[1] = !ram_valid_q[0] && next_free_ram_entry_onehot_still_not_one[0];

  // for (genvar current_address = 2; current_address < TotalCapacity; current_address = current_address + 1) begin
  //   assign next_free_ram_entry_onehot_still_not_one[current_address-1] = next_free_ram_entry_onehot[current_address-1] && next_free_ram_entry_onehot_still_not_one[current_address-2];
  //   assign next_free_ram_entry_onehot[current_address] = !(ram_valid_q[current_address-1]) && next_free_ram_entry_onehot_still_not_one[current_address-1];
  // end

  // Next Id to release from RAM
  for (genvar current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
    if (current_id == 0) begin
      assign next_id_to_release[current_id] = id_valid_ram[current_id] && release_en_i[current_id];
    end else begin
      assign next_id_to_release[current_id] = id_valid_ram[current_id] && release_en_i[current_id] && ~|(id_valid_ram[current_id-1:0] & release_en_i[current_id-1:0]);
    end
  end


  // IdValid signals, ramValid masks

  // Idea: change ram_valid_out_mask somehow directly in sequential logic 
  for (genvar current_address = 0; current_address < TotalCapacity; current_address = current_address + 1) begin
    for (genvar current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
      always_comb begin
        if (heads_q[current_id] == current_address) begin
          assign ram_valid_out_mask[current_address] = current_id == next_id_to_release ? 1'b1 : 1'b0;
        end
      end
    end

    assign ram_valid_in_mask[current_address] = next_free_ram_entry_binary == current_address ? 1'b1 : 1'b0;
  end

  // Output is valid if a release-enabled RAM list is not empty
  assign out_valid_o = |next_id_to_release;

  // Input is ready if there is room and data is not flowing out
  assign in_ready_o = |(~ram_valid_q) && !(out_valid_o && out_ready_i);

  for (genvar current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin

    always_comb begin
      // Default assignments
      heads_d[current_id] = heads_q[current_id];
      tails_d[current_id] = tails_q[current_id];
      ram_valid_apply_in_mask_id[current_id] = 1'b0;
      ram_valid_apply_out_mask_id[current_id] = 1'b0;
      is_data_o_id[current_id] = 1'b0;

      // Default RAM signals
      for (int ram_bank = 0; ram_bank < 2; ram_bank = ram_bank + 1) begin
        req_ram_id[ram_bank][current_id] = 1'b0;
        write_ram_id[ram_bank][current_id] = 1'b0;
      end

      // Handshakes: start by output to avoid blocking output with simultaneous inputs
      if (out_ready_i && out_valid_o && next_id_to_release == current_id) begin
        req_ram_id[STRUCT_RAM][current_id] = 1'b1;
        write_ram_id[STRUCT_RAM][current_id] = 1'b0;
        addr_ram_id[STRUCT_RAM][current_id] = heads_q[current_id];

        // Assign the output data
        is_data_o_id[current_id] = 1'b1;

        // Free the head entry in the RAM using a XOR mask
        ram_valid_apply_out_mask_id[current_id] = 1'b1;

        linkedlist_length_d[current_id] = linkedlist_length_q[current_id] - 1;

        // Update the head position in the RAM
        req_ram_id[NEXT_ELEM_RAM][current_id] = 1'b1;
        write_ram_id[NEXT_ELEM_RAM][current_id] = 1'b1;
        addr_ram_id[NEXT_ELEM_RAM][current_id] = heads_q[current_id];
        heads_d[current_id] = data_out_next_elem_ram;

      end else if (in_valid_i && in_ready_o && current_id == data_in_id_field) begin

        // Mark address as taken
        ram_valid_apply_in_mask_id[current_id] = 1'b1;

        // Take the input data, considering cases where the RAM list is empty or not
        if (id_valid_ram[current_id]) begin
          tails_d[current_id] = next_free_ram_entry_binary;

          linkedlist_length_d[current_id] = linkedlist_length_q[current_id] + 1;

          // Store into next elem RAM
          req_ram_id[NEXT_ELEM_RAM][current_id] = 1'b1;
          write_ram_id[NEXT_ELEM_RAM][current_id] = 1'b1;
          addr_ram_id[NEXT_ELEM_RAM][current_id] = tails_d[current_id];

          // Store into struct RAM
          req_ram_id[STRUCT_RAM][current_id] = 1'b1;
          write_ram_id[STRUCT_RAM][current_id] = 1'b1;
          addr_ram_id[STRUCT_RAM][current_id] = next_free_ram_entry_binary;

        end else begin
          heads_d[current_id] = next_free_ram_entry_binary;
          tails_d[current_id] = next_free_ram_entry_binary;

          // Store into ram and mark address as taken
          req_ram_id[STRUCT_RAM][current_id] = 1'b1;
          write_ram_id[STRUCT_RAM][current_id] = 1'b1;
          addr_ram_id[STRUCT_RAM][current_id] = next_free_ram_entry_binary;

        end
      end
    end
  end


  for (genvar current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (~rst_ni) begin
        heads_q[current_id] <= '0; //current_id[$clog2(TotalCapacity)-1:0];
        tails_q[current_id] <= '0; //current_id[$clog2(TotalCapacity)-1:0];
        linkedlist_length_q[current_id] <= '0;
      end else begin
        heads_q[current_id] <= heads_d[current_id];
        tails_q[current_id] <= tails_d[current_id];
        linkedlist_length_q[current_id] <= linkedlist_length_d[current_id];
      end
    end
  end

  for (genvar current_address = 0; current_address < TotalCapacity; current_address = current_address + 1) begin
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (~rst_ni) begin
        ram_valid_q[current_address] <= 1'b0;
      end else begin
        ram_valid_q[current_address] <= ram_valid_d[current_address];
      end
    end
  end

endmodule