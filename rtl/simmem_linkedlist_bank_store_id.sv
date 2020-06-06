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
  
  localparam int ListElementWidth = StructWidth  + $clog2(TotalCapacity) - IDWidth;

  // Demultiplex the data ID
  logic [IDWidth-1:0] data_in_id;

  // Head, tail and empty signals
  logic [IDWidth-1:0][$clog2(TotalCapacity)-1:0] heads_d, heads_q;
  logic [IDWidth-1:0][$clog2(TotalCapacity)-1:0] tails_d, tails_q;
  logic [IDWidth-1:0] id_empty;

  // Valid bit array
  logic [$clog2(TotalCapacity)-1:0] valid_bits_d, valid_bits_q;

  // Finds the next free address
  logic [$clog2(TotalCapacity)-1:0] next_free_address;
  
  // Finds the next id to release
  logic release_next_id;
  logic [2 ** IDWidth -1:0] next_id_to_release;

  // RAM instance and management signals
  logic req_ram;
  logic write_ram;
  logic [$clog2(TotalCapacity)-1:0] addr_ram;
  logic [StructWidth-IDWidth] data_out_ram;

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
    .wdata_i   (data_i),
    .rdata_o   (data_o)
  );

  always_comb begin: p_linkedlist_bank

    // Read the input identifier
    data_in_id = data_i[StructWidth-1:StructWidth-1-IDWidth];

    // Default assignments
    for (int i = 0; i < 2 ** IDWidth; i = i + 1) begin
      heads_d[i] = heads_q[i];
      tails_d[i] = tails_q[i];
    end

    valid_bits_d = valid_bits_q;

    req_ram   = '0;
    write_ram = '0;

    // Next Id to release
    // for (int current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
    //   if (current_id == 0) begin
    //     assign next_id_to_release[current_id] = valid_bits_q[heads_q[current_id]] && release_en[heads_q[current_id]];
    //   end else begin
    //     assign next_id_to_release[current_id] = valid_bits_q[heads_q[current_id]] && release_en[heads_q[current_id]] && ~|(valid_bits_q[heads_q[current_id]] && release_en[heads_q[current_id]]);
    //   end
    // end

    next_id_to_release = '0;
    for (int current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
      next_id_to_release = valid_bits_q[heads_q[current_id]] && release_en[heads_q[current_id]] && ~|(valid_bits_q[heads_q[current_id]] && release_en[heads_q[current_id]]) ? current_id : next_id_to_release;
    end

    // Next free addresses
    next_free_address = '0;
    for (int current_address = 1; current_address < TotalCapacity; current_address = current_address + 1) begin
      next_free_address = valid_bits_q[current_address] && !valid_bits_q[current_address-1:0] ? current_address : next_free_address;
    end

    // Empty singals
    for (int current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
      id_empty[current_id] = valid_bits_q[heads_q[current_id]];
    end

    // Handshakes 

    // TODO Watch out for latency

    // The interface is ready to accept when the corresponding linked list is not full.
    in_ready_o = |valid_bits_q;
    if (in_valid_i && in_ready_o) begin
      
      // Take the input data
      if (id_empty[data_in_id]) begin
        heads_d[data_in_id] = next_free_address;
        req_ram = 1'b1;
        write_ram = 1'b1;

        tails_d[data_in_id] = heads_d[data_in_id];
      end else begin

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
      valid_bits_q <= '0;
    end else begin
      for(int i = 0; i < 2 ** IDWidth; i = i + 1) begin
        heads_q[i] <= heads_d[i];
        tails_q[i] <= tails_d[i];
        // empty_q[i] <= empty_d[i];
      end
      valid_bits_q <= valid_bits_d;
    end
  end


  assign data_out_ram = {next_id_to_release}