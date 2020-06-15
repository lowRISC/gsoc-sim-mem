// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Verification testbench for the simulated memory controller

module simmem_linkedlist_bank_tb #(
) (
  input  logic clk_i,
  input  logic rst_ni,

  output logic test_done_o,
  output logic test_passed_o
);

  localparam int StructWidth    = 32; // Width of the message including identifier.
  localparam int TotalCapacity  = 32;
  localparam int IDWidth        = 2;

  localparam int NbInputsToSend = 26;

  logic [2**IDWidth-1:0] release_en;
  logic [StructWidth-1:0] in_data; // The identifier should be the first IDWidth bits
  logic [StructWidth-1:0] out_data;
  logic in_valid;
  logic in_ready;
  logic out_ready;
  logic out_valid;

  // Instantiate DUT
  simmem_linkedlist_bank #(
    .StructWidth(StructWidth), // Width of the message including identifier.
    .TotalCapacity(TotalCapacity),
    .IDWidth(IDWidth)
  ) simmem_linkedlist_bank_i (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .release_en_i(release_en),
    .data_i(in_data),
    .data_o(out_data),
    .in_valid_i(in_valid),
    .in_ready_o(in_ready),
    .out_ready_i(out_ready),
    .out_valid_o(out_valid)
  );

  // Introduce one single element
  assign release_en = {2**IDWidth{1'b1}};

  // Example of stimuli application
  // For now we just use a counter
  logic [StructWidth-1:0] count_stimuli_d, count_stimuli_q;
  logic [31:0] count_clock_d, count_clock_q;

  // Flip-flop for stimuli counter
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      count_stimuli_q <= '0;
    end else begin
      count_stimuli_q <= count_stimuli_d;
    end
  end

  // Increment the stimuli count
  assign count_stimuli_d = (in_valid && in_ready) ? count_stimuli_q+1 : count_stimuli_q;

  // Input valid
  always_comb begin: in_valid_p
    in_valid = 0;
    if (rst_ni) begin
      in_valid = count_stimuli_q < NbInputsToSend ? 1'b1 : '0;
    end
  end: in_valid_p

  always_comb begin: out_ready_p
    out_ready = 0;
    if (rst_ni) begin
      out_ready = count_stimuli_q >= NbInputsToSend ? 1'b1 : '0;
    end
  end: out_ready_p

  assign in_data = count_stimuli_q;

  // Cycle counter
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      count_clock_q <= '0;
    end else begin
      count_clock_q <= count_clock_d;
    end
  end

  assign count_clock_d = count_clock_q + 1;
  assign test_done_o = count_clock_q >= 1000;
  assign test_passed_o = 1'b1;

endmodule