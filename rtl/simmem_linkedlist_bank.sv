// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//

// This modules assumes that no capacity overflow occurs.

module simmem_linkedlist_bank #(
  parameter int StructWidth   = 64, // Width of the message including identifier
  parameter int TotalCapacity = 512,
  parameter int IDWidth       = 8
)(
  input logic clk_i,
  input logic rst_ni,

  input logic [2**IDWidth-1:0] release_en, // Input from the releaser

  input logic [StructWidth-1:0] data_i,
  output logic [StructWidth-1:0] data_o,

  input logic in_valid_i,
  output logic in_ready_o,

  input logic out_ready_i,
  output logic out_valid_o
);
  
  typedef enum logic { 
    STRUCT_RAM      = 1'b0,
    NEXT_ELEM_RAM  = 1'b1
  } ram_bank_t;

  localparam int StructListElementWidth = StructWidth  - IDWidth;

  // Demultiplex the data ID
  logic [IDWidth-1:0] data_in_id;

  // Head, tail and empty signals
  logic [IDWidth-1:0][$clog2(TotalCapacity)-1:0] heads_d, heads_q;
  logic [IDWidth-1:0][$clog2(TotalCapacity)-1:0] tails_d, tails_q;
  logic [IDWidth-1:0] id_valid_ram;

  // Valid bit and pointer to next arrays
  logic [TotalCapacity-1:0] ram_valid_d, ram_valid_q, ram_valid_in_mask, ram_valid_out_mask;
  logic [IDWidth-1:0] ram_valid_apply_in_mask_id, ram_valid_apply_out_mask_id;
  logic [TotalCapacity-1:0][$clog2(TotalCapacity)-1:0] next_in_list_d, next_in_list_q;

  always_comb begin: ram_valid_apply_masks
    ram_valid_d = ram_valid_q;
    if (|ram_valid_apply_in_mask_id) begin
      ram_valid_d ^= ram_valid_in_mask;
    end
    if (|ram_valid_apply_out_mask_id) begin
      ram_valid_d ^= ram_valid_out_mask;
    end
  end: ram_valid_apply_masks

  // Finds the next free address
  logic [TotalCapacity-1:0] next_free_ram_entry_onehot;
  logic [$clog2(TotalCapacity)-1:0] next_free_ram_entry_binary;
  
  simmem_onehot_to_bin # (
    .OneHotWidth(TotalCapacity)
  ) simmem_onehot_to_bin_next_free_ram_entry_i (
    .data_i(next_free_ram_entry_onehot),
    .data_o(next_free_ram_entry_binary)
  );

  // Finds the next id to release
  logic [2**IDWidth-1:0] next_id_to_release;

  // RAM instance and management signals
  logic [1:0]               req_ram, write_ram;
  logic [1:0][$clog2(TotalCapacity)-1:0] addr_ram;
  logic [1:0][IDWidth-1:0]  req_ram_id, write_ram_id;
  logic [1:0][IDWidth-1:0][$clog2(TotalCapacity)-1:0] addr_ram_id;

  logic [StructListElementWidth-1:0] wmask_ram;

  for (genvar int ram_bank = 0; ram_bank < 2; ram_bank = ram_bank+1) begin // SIMPLIFY Is the for loop useful?
    // Aggregate the ram requests
    assign req_ram[ram_bank] = |req_ram_id[ram_bank];
    assign write_ram[ram_bank] = |write_ram_id[ram_bank];
    assign addr_ram[ram_bank] = |addr_ram_id[ram_bank];
  end

  logic [StructWidth-IDWidth-1:0] data_in_noid, data_in_next_elem_ram;
  logic [1:0][StructWidth-IDWidth-1:0] data_out_ram;

  assign data_in_noid = data_i[StructWidth-1-IDWidth:0];
  assign wmask_ram = {StructListElementWidth{1'b1}};

  prim_ram_1p #(
    .Width(StructListElementWidth),
    .DataBitsPerMask(8),
    .Depth(TotalCapacity)
  ) struct_ram_i (
    .clk_i     (clk_i),
    .req_i     (req_ram[STRUCT_RAM]),
    .write_i   (write_ram[STRUCT_RAM]),
    .wmask_i   (wmask_ram),
    .addr_i    (addr_ram[STRUCT_RAM]),
    .wdata_i   (data_in_noid),
    .rdata_o   (data_out_ram[STRUCT_RAM])
  );

  prim_ram_1p #(
    .Width($clog2(TotalCapacity)),
    .DataBitsPerMask(8),
    .Depth(TotalCapacity)
  ) next_elem_ram_i (
    .clk_i     (clk_i),
    .req_i     (req_ram[NEXT_ELEM_RAM]),
    .write_i   (write_ram[NEXT_ELEM_RAM]),
    .wmask_i   (wmask_ram),
    .addr_i    (addr_ram[NEXT_ELEM_RAM]),
    .wdata_i   (next_free_ram_entry_binary),
    .rdata_o   (data_out_ram[NEXT_ELEM_RAM])
  );

  // Next free addresses
  for (genvar int current_address = 0; current_address < TotalCapacity; current_address = current_address + 1) begin
    if (current_address == 0) begin
      assign next_free_ram_entry_onehot[current_address] = ram_valid_q[current_address];
    end else begin
      assign next_free_ram_entry_onehot[current_address] = ram_valid_q[current_address] && ~&ram_valid_q[current_address-1:0];
    end
  end

  // Next Id to release from output buffer
  for (genvar int current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
    next_id_to_release[current_id] = id_valid_ram[current_id] && release_en[current_id] && ~|(id_valid_ram[current_id-1:0] & release_en[current_id-1:0]);
  end

  // IdValid signals
  // for (genvar logic [IDWidth-1:0] current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
  //   id_valid_ram[current_id] = ram_valid_q[heads_q[current_id]];
  // end

  always_comb begin: p_linkedlist_bank // TODO Put all in assigns

    // Read the input identifier
    data_in_id = data_i[StructWidth-1:StructWidth-IDWidth];
    
    // IdValid signals, ramValid masks
    for (logic [$clog2(TotalCapacity)-1:0] current_address = 0; current_address < TotalCapacity; current_address = current_address + 1) begin
      for (logic [IDWidth-1:0] current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
        if (heads_q[current_id] == current_address) begin
          id_valid_ram[current_id] = ram_valid_q[current_address];

          ram_valid_out_mask[current_address] = current_id == next_id_to_release ? 1'b1 : 1'b0;
        end

      end
      
      ram_valid_in_mask[current_address] = next_free_ram_entry_binary == current_address ? 1'b1 : 1'b0;
    end

    // Output is valid if a release-enabled output buffer is full
    out_valid_o = |next_id_to_release;

    // Input is ready if there is room and data is not flowing out
    in_ready_o = |ram_valid_q && !(out_valid_o && out_ready_i);

  end: p_linkedlist_bank

  for (genvar logic [IDWidth-1:0] current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin

    always_comb begin
      // Default assignments
      heads_d[current_id] = heads_q[current_id];
      tails_d[current_id] = tails_q[current_id];
      output_buffers_d[current_id] = output_buffers_q[current_id];
      output_buffers_valid_d[current_id] = output_buffers_valid_q[current_id];
      ram_valid_apply_in_mask_id[current_id] = 1'b0;
      ram_valid_apply_out_mask_id[current_id] = 1'b0;

      // Default RAM signals
      for (int ram_bank = 0; ram_bank < 2; ram_bank = ram_bank + 1) begin // SIMPLIFY Is the for loop useful?
        req_ram_id[ram_bank][current_id] = 1'b0;
        write_ram_id[ram_bank][current_id] = 1'b0;
        addr_ram_id[ram_bank][current_id] = '0;
      end

      // Handshakes: start by output to avoid blocking output with inputs
      if (out_ready_i && out_valid_o && next_id_to_release == current_id) begin
        req_ram_id[STRUCT_RAM][current_id] = 1'b1;
        write_ram_id[STRUCT_RAM][current_id] = 1'b0;
        addr_ram_id[STRUCT_RAM][current_id] = heads_q[current_id];

        // Assign the output data and plug the identifier again
        data_o = {current_id, data_out_ram[STRUCT_RAM]};

        // Free the head entry in the RAM
        ram_valid_apply_out_mask_id[current_id] = 1'b1;

        // Update the head position in the RAM
        req_ram_id[NEXT_ELEM_RAM][current_id] = 1'b1;
        write_ram_id[NEXT_ELEM_RAM][current_id] = 1'b1;
        addr_ram_id[NEXT_ELEM_RAM][current_id] = heads_q[current_id];
        heads_d[current_id] = data_out_next_elem_ram;
      end

      end else if (in_valid_i && in_ready_o && current_id == data_in_id) begin

        // Mark address as taken
        ram_valid_apply_in_mask_id[current_id] = 1'b1;

        // Take the input data, considering cases where the RAM list is empty or not
        if (id_valid_ram[current_id]) begin
          tails_d[current_id] = next_free_ram_entry_binary;

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

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      for(int i = 0; i < 2 ** IDWidth; i = i + 1) begin
        heads_q[i] <= i;
        tails_q[i] <= i;
      end
      ram_valid_q <= '0;
      output_buffers_q <= '0;
      output_buffers_valid_q <= '0;
    end else begin
      for(int i = 0; i < 2 ** IDWidth; i = i + 1) begin
        heads_q[i] <= heads_d[i];
        tails_q[i] <= tails_d[i];
      end
      ram_valid_q <= ram_valid_d;
      next_in_list_q <= next_in_list_d;
      output_buffers_q <= output_buffers_d;
      output_buffers_valid_q <= output_buffers_valid_d;
    end
  end

endmodule