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
  logic [IDWidth-1:0] id_empty_ram;

  // Output buffers
  logic [2 ** IDWidth-1:0][StructWidth-IDWidth:0] output_buffers_d, output_buffers_q;
  logic [2 ** IDWidth-1:0] output_buffers_valid_d, output_buffers_valid_q;

  // Valid bit and pointer to next arrays
  logic [TotalCapacity-1:0] ram_valid_d, ram_valid_q;
  logic [TotalCapacity-1:0][$clog2(TotalCapacity)-1:0] next_in_list_d, next_in_list_q;

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
  logic [2**IDWidth-1:0] next_id_to_release_outbuf;
  logic release_outbuf;

  assign release_outbuf = |next_id_to_release_outbuf;

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
  logic [StructWidth-IDWidth-1:0] data_out_struct_ram, data_out_next_elem_ram; // TODO data_out_struct_ram not used

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
    .rdata_o   (data_out_struct_ram)
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
    .rdata_o   (data_out_next_elem_ram)
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
    next_id_to_release_outbuf[current_id] = output_buffers_valid_q[current_id] && release_en[current_id] && ~|(output_buffers_valid_q[current_id-1:0] & release_en[current_id-1]);
  end

  // Empty signals
  // for (genvar logic [IDWidth-1:0] current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
  //   id_empty_ram[current_id] = !ram_valid_q[heads_q[current_id]];
  // end

  always_comb begin: p_linkedlist_bank

    // Read the input identifier
    data_in_id = data_i[StructWidth-1:StructWidth-IDWidth];

    ram_valid_d = ram_valid_q; // TODO Distribute among IDs
    
    // Empty signals
    for (logic [$clog2(TotalCapacity)-1:0] current_address = 0; current_address < TotalCapacity; current_address = current_address + 1) begin
      for (logic [IDWidth-1:0] current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
        if (heads_q[current_id] == current_address) begin
          id_empty_ram[current_id] = !ram_valid_q[current_address];
        end
      end
    end

    // Handshake signals
    in_ready_o = |ram_valid_q;
    // Output is valid if a release-enabled output buffer is full
    out_valid_o = release_outbuf;

  end: p_linkedlist_bank

  for (genvar logic [IDWidth-1:0] current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin

    always_comb begin
      // Default assignments
      heads_d[current_id] = heads_q[current_id];
      tails_d[current_id] = tails_q[current_id];
      output_buffers_d[current_id] = output_buffers_q[current_id];
      output_buffers_valid_d[current_id] = output_buffers_valid_q[current_id];

      // Initialize the RAM signals
      for (int ram_bank = 0; ram_bank < 2; ram_bank = ram_bank + 1) begin // SIMPLIFY Is the for loop useful?
        req_ram_id[ram_bank][current_id] = '0;
        write_ram_id[ram_bank][current_id] = '0;
        addr_ram_id[ram_bank][current_id] = '0;
      end

      // Handshakes: start by output to avoid blocking output with inputs
      if (out_ready_i && out_valid_o) begin

        if (next_id_to_release_outbuf == current_id) begin
          
          // Assign the output data and plug the identifier again
          data_o = {current_id, output_buffers_valid_q[current_id]};

          // Then refill the output buffer if the corresponding RAM queue is not empty
          if (!id_empty_ram[current_id]) begin
            req_ram_id[STRUCT_RAM][current_id] = 1'b1;
            write_ram_id[STRUCT_RAM][current_id] = 1'b0;
            addr_ram_id[STRUCT_RAM][current_id] = heads_q[current_id];
            
            output_buffers_d[current_id] = data_out_struct_ram;

            // Free the head entry in the RAM
            ram_valid_d[heads_q[current_id]] = 1'b0;

            // Update the head position in the RAM
            if (heads_q[current_id] != tails_q[current_id]) begin
              req_ram_id[NEXT_ELEM_RAM][current_id] = 1'b1;
              write_ram_id[NEXT_ELEM_RAM][current_id] = 1'b0;
              addr_ram_id[NEXT_ELEM_RAM][current_id] = heads_q[current_id];
  
              heads_d[current_id] = data_out_next_elem_ram;
            end

          // Or refill it with simultaneously incoming data if possible
          end else if (in_valid_i && in_ready_o && current_id == data_in_id) begin
            output_buffers_d[current_id] = data_in_noid;
          end else begin
            output_buffers_valid_d[current_id] = 1'b0;
          end

        // The following case captures the situation where the input can directly flow to the output
        end else begin
          data_o = data_i;
        end
      end else if (in_valid_i && in_ready_o && current_id == data_in_id) begin

        // Take the input data, considering cases where the RAM list is empty or not
        if (id_empty_ram[current_id]) begin
          
          heads_d[current_id] = next_free_ram_entry_binary;
          tails_d[current_id] = next_free_ram_entry_binary;

          // Store into ram and mark address as taken
          req_ram_id[STRUCT_RAM][current_id] = 1'b1;
          write_ram_id[STRUCT_RAM][current_id] = 1'b1;
          addr_ram_id[STRUCT_RAM][current_id] = next_free_ram_entry_binary;
        end else begin

          tails_d[current_id] = next_free_ram_entry_binary;

          // Store into next elem RAM
          req_ram_id[NEXT_ELEM_RAM][current_id] = 1'b1;
          write_ram_id[NEXT_ELEM_RAM][current_id] = 1'b1;
          addr_ram_id[NEXT_ELEM_RAM][current_id] = tails_d[current_id];

          // Store into struct RAM
          req_ram_id[STRUCT_RAM][current_id] = 1'b1;
          write_ram_id[STRUCT_RAM][current_id] = 1'b1;
          addr_ram_id[STRUCT_RAM][current_id] = next_free_ram_entry_binary;
        end
        // Mark address as taken
        ram_valid_d = ram_valid_d | next_free_ram_entry_onehot;
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