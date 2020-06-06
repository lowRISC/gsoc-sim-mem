// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// simmem top-level

module simmem_fifo #(
  parameter int DataWidth = 64,
  parameter int Capacity  = 128
)(
  input logic clk_i,
  input logic rst_ni,

  input logic [DataWidth-1:0] data_i,
  output logic [DataWidth-1:0] data_o,

  input logic data_in_valid_i,
  output logic data_in_ready_o,

  output logic data_out_valid_o,
  input logic data_out_ready_i
);

  // Bank of entries
  typdef logic [DataWidth-1:0] fifo_entry_t;
  logic [DataWidth-1:0][Capacity-1:0] entries;

  // Internal signal declaration
  logic [$clog2(Capacity)-1:0] first_entry_index_d, first_entry_index_q;
  logic [$clog2(Capacity)-1:0] next_entry_index_d, next_entry_index_q;

  logic empty_d, empty_q;
  logic is_full;
  logic entry_we;

  // Plus one to the indices
  logic [$clog2(Capacity)-1:0] first_entry_index_plus_one, next_entry_index_plus_one;

  assign first_entry_index_plus_one = first_entry_index_q + 1;
  assign next_entry_index_plus_one = next_entry_index_q + 1;

  // Full signal assignment
  assign is_full = !empty_q && (first_entry_index_q == next_entry_index_plus_one);

  // Output selection
  assign data_o = entries_q[first_entry_index_q];

  // TODO Handshake signal assignment 

  // TODO Assign entry_we inside always_comb
  always_comb begin
    entry_we = 1'b0;
    first_entry_index_d = first_entry_index_q;
    next_entry_index_d = next_entry_index_q;

    data_out_valid_o = '0;
    data_in_ready_o = '0;

    // Input handshake
    if (!is_full) begin
      data_in_ready_o = 1'b1;

      // Entry is added if input handshake is successful and [is currently not full or output handshake is successful]
      if (data_in_valid_i && (!is_full || data_out_ready_i) begin
        entry_we = 1'b1;
        first_entry_index_d = first_entry_index_plus_one;
      end
    end

    // Output handshake
    data_out_valid_o = !empty_q 

    if (data_out_ready_i) begin
      if (!empty_q) begin
        // TODO
      end
    end

    if (!empty_q || data_in_valid_i) begin
      data_out_valid_o = 1'b1;

      // Entry is flushed if 
      if (data_in_valid_i && (!is_full || data_out_ready_i) begin
        entry_we = 1'b1;
        first_entry_index_d = first_entry_index_plus_one;
      end
    end


    // TODO Check if the jump is performed correctly

  end

  // TODO Determine the value of the *_d signals
  // TODO Handshakes
  
  // Sequential assignments
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      first_entry_index_q <= '0;
      next_entry_index_q  <= '0;
      empty_q             <= '0;
    end else begin

      // TODO Maybe add a write enable signal

      first_entry_index_q <= first_entry_index_d;
      next_entry_index_q  <= next_entry_index_d;
      empty_q             <= empty_d;

      entries[next_entry_index_q] <= 
    end
  end






















  entry_t entries_q[Capacity];
  logic [DataWidth-1:0] data_mem [Capacity];

  logic [Capacity-1:0] entry_valid;
  logic [Capacity-1:0] entry_finished;
  logic [Capacity-1:0] next_free_entry;
  logic [Capacity-1:0] next_finished_entry;

  logic                          data_mem_en;
  logic [$clog2(Capacity-1:0)] data_in_addr;
  logic [$clog2(Capacity-1:0)] data_out_addr;

  for (genvar int i = 0;i < Capacity; i = i + 1) begin
    // Pull valid bits out into seperate packed logic bits for easy use in
    // expression below
    assign entry_valid[i] = entries_q[i].entry_valid;
    if (i == 0) begin
      assign next_free_entry[i] = entry_valid[i];
    end else begin
      // entry i is next to be used if it's not valid and all lower entries are
      // valid
      assign next_free_entry[i] = entry_valid[i] && ~&entry_valid[i-1:0];
    end

    // entry is finished when it has data and its counter reaches zero
    assign entry_finished[i] = entries_q[i].entry_valid && entries_q[i].data_valid && (entries_q[i].counter == 0);

    // choose entry to give out on resp_out from the finished entries. When
    // there's multiple finished entries choose the one with the lowest index.
    assign next_finished_entry[i] = i[i] = entry_finished[i] && ~|entry_finished[i-1:0];
  end

  always_comb begin
    for(int i = 0;i < Capacity; i = i + 1) begin
      if (next_free_entry[i]) begin
        data_in_addr = i;
      end

      if (next_finished_entry[i]) begin
        data_out_addr = i;
      end
    end
  end

  for (genvar int i = 0;i < Capacity; i = i + 1) begin
    always_comb begin
      // Keep old contents by default
      entry_d[i] = entry_q[i];

      // Allocate new entry
      if (req_valid_i && next_free_entry[i]) begin
        entry_d[i].entry_valid = 1'b1;
        entry_d[i].id          = req_id_i;
        entry_d[i].data_valid  = 1'b0;
        entry_d[i].counter     = 0;
      end

      // Store response data
      if (resp_valid_i && entry_q[i].entry_valid && (entry_q[i].id == req_id_i)) begin
        entry_d[i].data_valid = 1'b1;
        // determine_initial_counter intentionally left un-implemented, this
        // will eventually turn into something quite sophisticated so probably
        // won't come from a function but rather some IO with another module.
        entry_d[i].counter    = determine_initial_counter(req_id_i);
      end

      // Decrement counter if it's non-zero with valid data
      if (entry_q[i].entry_valid && entry_q[i].data_valid && (entry_q[i].counter != 0)) begin
        entry_d[i].counter = entry_q[i].counter - 1'b1;
      end

      // Remove entry when it's accepted on resp_out interface
      if (resp_out_ready_i & next_finished_entry[i]) begin
        entry_d[i].entry_valid = 1'b0;
      end
    end
  end

  // Write to data memory when we get a response in
  assign data_mem_en = resp_in_valid_i;

  always_ff @(posedge clk_i) begin
    if (data_mem_en) begin
      data_mem[data_in_addr] <= resp_in_data_i;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      entry_q <= '0;
    end else begin
      entry_q <= entry_d;
    end
  end

  // Can accept a new request if there's an invalid entry to accept it
  assign req_ready_o = |(~entry_valid);

  // Valid resp_out if there's a finished entry to give out
  assign resp_out_valid_o = |next_finished_entry;

  // Mux out the finished entry data, note this isn't the best way to do this,
  // but it's clear and straight-forward.
  // The issue here is next_finished_entry[i] is one-hot encoded (so one bit
  // or no bits, guaranteed we don't have 2 bits set) but the for with the if
  // encodes a priority structure (so here it will only set
  // resp_out_id_o/resp_out_data_o for an entry i if there are no bits higher
  // than i set in next_finished_entry but we're guaranteed this isn't the
  // case). A better way to do this is an AND-OR reduction, AND
  // next_finished_entry[i] replicated DataWidth and CounterWidth times with the
  // id/data fields then OR the whole lot together. As next_finished_entry[i] is
  // only set for one entry the AND will only grab the bits from one entry so
  // that will be the only bit that makes it through the OR giving you the mux.
  always_comb begin
    for(int i = 0;i < Capacity; i = i + 1) begin
      if (next_finished_entry[i]) begin
        resp_out_id_o = entry[i].id;
      end
    end
  end

  // Note that this reads directly from memory with a combinational signal, in reality you may need
  // to flop the addres or flop the data coming out of memory, which will complicate the logic (you
  // need to determine which entry you're sending out one cycle, it becomes available the next so
  // you end up with two next_finished_entry style signals, one for the entry that will have its
  // data sent out next cycle, one for the entry that will be deallocated this cycle).
  assign resp_out_data = data_mem[data_out_addr];
endmodule

