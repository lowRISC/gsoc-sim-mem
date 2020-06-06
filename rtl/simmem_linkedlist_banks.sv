// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// simmem top-level

// This modules assumes that no capacity overflow occurs.

module simmem_linkedlist_banks #(
  parameter int StructWidth   = 64, // Width of the net data to store (without the linkedlist overhead)
  parameter int TotalCapacity         = 512,
  parameter int IDWidth               = 8
)(
  input logic clk_i,
  input logic rst_ni,

  input logic [1:0][2**IDWidth-1:0] release_en; // Input from the releaser

  input logic [ReadDataStructWidth-1:0] read_data_i,
  input logic [WriteRespStructWidth-1:0] write_resp_i,
  output logic [ReadDataStructWidth-1:0] read_data_o,
  output logic [WriteRespStructWidth-1:0] write_resp_o,

  input logic [1:0] in_valid_i,
  output logic [1:0] in_ready_o,

  input logic [1:0] out_ready_i,
  output logic [1:0] out_valid_o

  // input logic in_read_data_valid_i,
  // input logic in_write_response_valid_i,
  // output logic in_read_data_ready_o,
  // output logic in_write_response_ready_o,

  // input logic out_read_data_ready_i,
  // input logic out_write_response_ready_i,
  // output logic out_read_data_valid_o,
  // output logic out_write_response_valid_o
);
  
  // This type segregates the two linked lists
  typedef enum logic { 
    READ_DATA   = 1'b0,
    WRITE_RESP  = 1'b1
  } linkedlist_entry_t;

  localparam int [1:0] ListElementWidth = {
    ReadDataStructWidth  + $clog2(TotalCapacity),
    WriteRespStructWidth + $clog2(TotalCapacity)
  }

  // Demultiplex the data ID
  logic [1:0][IDWidth-1:0] data_in_id;

  // Head, tail and empty signals
  logic [1:0][IDWidth-1:0][$clog2(TotalCapacity)-1:0] heads_d, heads_q;
  logic [1:0][IDWidth-1:0][$clog2(TotalCapacity)-1:0] tails_d, tails_q;
  // logic [1:0][IDWidth-1:0] empty_d, empty_q; // TODO Is empty signal useful?
  logic [1:0][IDWidth-1:0] id_empty;

  // Valid bit array
  logic [1:0][$clog2(TotalCapacity)-1:0] valid_bits_d, valid_bits_q;

  // Finds the next free address
  logic [1:0][$clog2(TotalCapacity)-1:0] next_free_address;
  
  // Finds the next id to release
  logic release_next_id;
  logic [1:0][2 ** IDWidth -1:0] next_id_to_release;

  // RAM instance and management signals
  logic [1:0] req_ram;
  logic [1:0] write_ram;
  logic [1:0][$clog2(TotalCapacity)-1:0] addr_ram;

  prim_ram_1p #(
    .Width(ListElementWidth[READ_DATA]),
    .DataBitsPerMask(8),
    .Depth(TotalCapacity)
  ) read_data_ram_i (
    .clk_i     (clk_i),
    .req_i     (req_ram[READ_DATA]),
    .write_i   (write_ram[READ_DATA]),
    .wmask_i   (8'hFF),
    .addr_i    (addr_ram[READ_DATA]),
    .wdata_i   (read_data_i),
    .rdata_o   (read_data_o)
  );

  prim_ram_1p #(
    .Width(ListElementWidth[WRITE_RESP]),
    .DataBitsPerMask(8),
    .Depth(TotalCapacity)
  ) write_resp_data_ram_i (
    .clk_i     (clk_i),
    .req_i     (req_ram[WRITE_RESP]),
    .write_i   (write_ram[WRITE_RESP]),
    .wmask_i   (8'hFF),
    .addr_i    (addr_ram[WRITE_RESP]),
    .wdata_i   (write_resp_i),
    .rdata_o   (write_resp_o)
  );


  always_comb begin: p_linkedlist_bank

    // Read the input identifiers
    for (int entry_type = 0; entry_type < 2; entry_type = entry_type + 1) begin
      data_in_id[entry_type] = 
    end

    // Default assignments
    for (int i = 0; i < 2 ** IDWidth; i = i + 1) begin
      heads_d[i] = heads_q[i];
      tails_d[i] = tails_q[i];
      empty_d[i] = empty_q[i];
    end

    valid_bits_d = valid_bits_q;

    req_ram   = '0;
    write_ram = '0;

    // Next Id to release
    for (int entry_type = 0; entry_type < 2; entry_type = entry_type + 1) begin
      for (int current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
        if (current_id == 0) begin
          assign next_id_to_release[entry_type][current_id] = valid_bits_q[entry_type][heads_q[current_id]] && release_en[entry_type][heads_q[current_id]];
        end else begin
          assign next_id_to_release[entry_type][current_id] = valid_bits_q[entry_type][heads_q[current_id]] && release_en[entry_type][heads_q[current_id]] && ~|(valid_bits_q[entry_type][heads_q[current_id]] && release_en[entry_type][heads_q[current_id]]);
        end
      end
    end

    // // Next free addresses
    // for (int entry_type = 0; entry_type < 2; entry_type = entry_type + 1) begin
    //   for (int i = 0; i < TotalCapacity; i = i + 1) begin
    //     if (i == 0) begin
    //       assign next_free_address[entry_type][i] = valid_bits_q[entry_type][i];
    //     end else begin
    //       assign next_free_address[entry_type][i] = valid_bits_q[entry_type][i] && !valid_bits_q[entry_type][i-1:0];
    //     end
    //   end
    // end

    // Next free addresses
    for (int entry_type = 0; entry_type < 2; entry_type = entry_type + 1) begin
      next_free_address[entry_type] = '0;
      for (int current_address = 1; current_address < TotalCapacity; current_address = current_address + 1) begin
        assign next_free_address[entry_type][current_address] = valid_bits_q[entry_type][current_address] && !valid_bits_q[entry_type][current_address-1:0] ? current_address : next_free_address[entry_type];
      end
    end

    // Empty singals
    for (int entry_type = 0; entry_type < 2; entry_type = entry_type + 1) begin
      for (int current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
        id_empty[entry_type][current_id] = valid_bits_q[entry_type][heads_q[current_id]];
      end
    end

    // Concurrent handshakes for both interfaces

    for (int entry_type = 0; entry_type < 2; entry_type = entry_type + 1) begin

      // TODO Watch out for latency

      // The interface is ready to accept when the corresponding linked list is not full.
      in_ready_o[entry_type] = |valid_bits_q[entry_type];
      if (in_valid_i[entry_type] && in_ready_o[entry_type]) begin
        
        // If the corresponding linkedlist is empty
        if (id_empty[entry_type]) begin
          heads_d[entry_type] = 
          tails_d[entry_type]
        end
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



  // TODO Add assertion in case the linkedlist is full