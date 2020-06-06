// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// simmem top-level

// This modules assumes that no capacity overflow occurs.

module simmem_linkedlist_bank #(
  parameter int StructWidth   = 64, // Width of the message including identifier
  parameter int TotalCapacity = 512,
  parameter int IDWidth       = 8
)(
  input logic clk_i,
  input logic rst_ni,

  input logic [2**IDWidth-1:0] release_en; // Input from the releaser

  input logic [StructWidth-1:0] data_i,
  output logic [StructWidth-1:0] data_o,

  input logic in_valid_i,
  output logic in_ready_o,

  input logic out_ready_i,
  output logic out_valid_o
);
  
  localparam int ListElementWidth = StructWidth  - IDWidth;

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
  logic [$clog2(TotalCapacity)-1:0] ram_valid_d, ram_valid_q;
  logic [$clog2(TotalCapacity)-1:0][$clog2(TotalCapacity)-1:0] next_in_list_d, next_in_list_q;

  // Finds the next free address
  logic [$clog2(TotalCapacity)-1:0] next_free_address;
  
  // Finds the next id to release
  logic tmp_release_next_id_outbuf, release_next_id_outbuf;
  logic [2 ** IDWidth -1:0] next_id_to_release_outbuf;

  // RAM instance and management signals
  logic req_ram;
  logic write_ram;
  logic [$clog2(TotalCapacity)-1:0] addr_ram;
  logic [StructWidth-IDWidth:0] data_in_noid;
  logic [StructWidth-IDWidth:0] data_out_ram;

  assign data_in_noid = data_i[StructWidth-1-IDWidth:0];

  prim_ram_1p #(
    .Width(ListElementWidth),
    .DataBitsPerMask(8),
    .Depth(TotalCapacity)
  ) prim_ram_i (
    .clk_i     (clk_i),
    .req_i     (req_ram),
    .write_i   (write_ram),
    .wmask_i   (8'hFF),
    .addr_i    (addr_ram),
    .wdata_i   (data_in_noid),
    .rdata_o   (data_out_ram)
  );

  always_comb begin: p_linkedlist_bank

    // Read the input identifier
    data_in_id = data_i[StructWidth-1:StructWidth-1-IDWidth];

    // Default assignments
    heads_d = heads_q;
    tails_d = tails_q;

    ram_valid_d = ram_valid_q;
    output_buffers_valid_d = output_buffers_valid_q;

    req_ram   = '0;
    write_ram = '0;

    // Next Id to release from output buffer
    next_id_to_release_outbuf = '0;
    release_next_id_outbuf = '0;
    for (int current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
      tmp_release_next_id_outbuf = output_buffers_valid_q[heads_q[current_id]] && release_en[heads_q[current_id]] && ~|(output_buffers_valid_q[heads_q[current_id]] & release_en[heads_q[current_id]]);
      next_id_to_release_outbuf = tmp_release_next_id_outbuf ? current_id : next_id_to_release_outbuf;
      release_next_id_outbuf = release_next_id_outbuf || tmp_release_next_id_outbuf;
    end

    // Next free addresses
    next_free_address = '0;
    for (int current_address = 1; current_address < TotalCapacity; current_address = current_address + 1) begin
      next_free_address = ram_valid_q[current_address] && !ram_valid_q[current_address-1:0] ? current_address : next_free_address;
    end

    // Empty signals
    for (int current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
      id_empty_ram[current_id] = ram_valid_q[heads_q[current_id]];
    end

    // Handshake signals
    in_ready_o = |ram_valid_q;
    // Output is valid if a release-enabled output buffer is full or the corresponding input is flowing simultaneously
    out_valid_o = release_next_id_outbuf || (next_id_to_release_outbuf == data_in_id && release_en[data_in_id] && id_empty_ram[data_in_id]);

    // Handshakes: start by input to allow direct flowing
    if (in_valid_i && in_ready_o) begin

      // Take the input data, considering cases where the RAM list is empty or not
      if (id_empty_ram[data_in_id]) begin
        
        // If there is nothing in the output buffer or the output buffer is being pulled from and the RAM is empty, then bypass the RAM (the actual bypassing is performed in the output handshake block)
        if (output_buffers_valid_q[data_in_id] && !(next_id_to_release_outbuf == data_in_id && release_en[data_in_id] && id_empty_ram[data_in_id])) begin
          heads_d[data_in_id] = next_free_address;
          tails_d[data_in_id] = next_free_address;

          // Store into ram and mark address as taken
          req_ram = 1'b1;
          write_ram = 1'b1;
          addr_ram = next_free_address;
          ram_valid_d[next_free_address] = 1'b1;
        end

      end else begin
        next_in_list_d[tails_d[data_in_id]] = next_free_address;
        tails_d[data_in_id] = next_free_address;

        // Store into ram and mark address as taken
        req_ram = 1'b1;
        write_ram = 1'b1;
        addr_ram = next_free_address;
        ram_valid_d[next_free_address] = 1'b1;
      end

    end else if (out_ready_i && out_valid_o) begin

      if (release_next_id_outbuf) begin
        
        // Assign the output data and plug the identifier again
        data_o = {next_id_to_release_outbuf, output_buffers_valid_q[next_id_to_release_outbuf]};

        // Then refill the output buffer if the corresponding RAM queue is not empty
        if (!id_empty_ram[next_id_to_release_outbuf]) begin
          req_ram = 1'b1;
          write_ram = 1'b0;
          addr_ram = heads_q[next_id_to_release_outbuf];
          ram_valid_d[heads_q[next_id_to_release_outbuf]] = 1'b0;

          // Update the head position in the RAM
          if (heads_q[next_id_to_release_outbuf] != tails_q[next_id_to_release_outbuf]) begin
            heads_d[next_id_to_release_outbuf] = next_in_list_q[heads_d[next_id_to_release_outbuf]];
          end

        // Or refill it with simultaneously incoming data if possible
        end else if (in_valid_i && in_ready_o && next_id_to_release_outbuf == data_in_id) begin
          output_buffers_d[next_id_to_release_outbuf] = data_in_noid;
        end else begin
          output_buffers_valid_d[next_id_to_release_outbuf] = 1'b0;
        end

      // The following case captures the situation where the input can directly flow to the output
      end else begin
        data_o = data_i;
      end
    end

  end: p_linkedlist_bank

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      for(int i = 0; i < 2 ** IDWidth; i = i + 1) begin
        heads_q[i] <= i;
        tails_q[i] <= i;
        // empty_q[i] <= 1'b1;
      end
      ram_valid_q <= '0;
      output_buffers_valid_q <= '0;
    end else begin
      for(int i = 0; i < 2 ** IDWidth; i = i + 1) begin
        heads_q[i] <= heads_d[i];
        tails_q[i] <= tails_d[i];
        // empty_q[i] <= empty_d[i];
      end
      ram_valid_q <= ram_valid_d;
      next_in_list_q <= next_in_list_d;
      output_buffers_valid_q <= output_buffers_valid_d;
    end
  end