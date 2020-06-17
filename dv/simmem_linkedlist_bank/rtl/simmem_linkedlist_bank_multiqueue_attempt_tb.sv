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

  localparam unsigned Timeout   = 1000;

  localparam int StructWidth    = 10; // Width of the message including identifier.
  localparam int TotalCapacity  = 16;
  localparam int IDWidth        = 2;

  localparam int NbInputsToSend = 10;

  logic [2**IDWidth-1:0] release_en;
  logic [StructWidth-1:0] in_data; // The identifier should be the first IDWidth bits
  logic [StructWidth-1:0] out_data;
  logic in_valid;
  logic in_ready;
  logic out_ready;
  logic out_valid;

  logic [StructWidth-1:0] queue_inputs[$]; // Holds all the inputs before being multiplexed into different ID queues
  logic [2**IDWidth-1:0][StructWidth-1:0] queue_inputs_ids[$];
  logic [2**IDWidth-1:0][StructWidth-1:0] queue_outputs[$];
  
  // Implements a peek function for queues
  logic first_input_valid;
  logic [StructWidth-1:0] first_input; // Holds all the inputs before being multiplexed into different ID queues
  
  logic all_stims_applied;
  int nb_stims;
  int nb_checks;

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

  initial begin: application_block
    int ret_code;

    nb_stims = 0;
    in_valid = 1'b0;
    all_stims_applied = 1'b0;
    first_input_valid = 1'b0;
    
    while (nb_stims < NbInputsToSend) begin
      @(posedge clk);
      #(APPL_DELAY);
      ret_code = randomize(in_valid);
      #(ACQ_DELAY-APPL_DELAY);
      if (in_valid) begin
        ret_code = randomize(in_data);
        queue_inputs.push_back(in_data);
        nb_stims = nb_stims + 1;
        #(ACQ_DELAY-APPL_DELAY);
        wait (in_ready);
      end
    end
    @(posedge clk);
    #(APPL_DELAY);

    in_valid = 1'b0;
    all_stims_applied = 1'b1;
  end

  // for (genvar current_id = 0; current_id < 2 ** IDWidth; current_id = current_id + 1) begin
  //   initial begin: input_demux_block
  //     while (!test_done_o) begin
  //       wait(queue_inputs.size() > 0)
  //     end
  //     @(posedge clk);
  //     #(APPL_DELAY);

  //     in_valid = 1'b0;
  //     all_stims_applied = 1'b1;
  //   end
  // end

  initial begin: acquisition_block
    integer ret_code;
    out_ready = 1'b0;
    wait (rst_n);
    while (1) begin
      @(posedge clk);
      #(APPL_DELAY);
      ret_code = randomize(out_ready);
      #(ACQ_DELAY-APPL_DELAY);
      if (out_valid && out_ready) begin
          queue_outputs.push_back(out_data);
      end
    end
  end

  initial begin: checker_block
    nb_checks = 0;
    n_errs   = 0;
    nb_clock_cycles_timeout = 0;
    wait (rst_n);
    while (!all_stims_applied || nb_checks < nb_stims) begin
      wait(queue_inputs.size() > 0 && queue_outputs.size() > 0);

      expected_resp = queue_inputs.pop_front();
      acquired_resp = queue_outputs.pop_front();

      nb_checks += 1;
      $display("Expected %x, processed %x.", expected_resp, acquired_resp);
      if (acquired_resp != expected_resp) begin

          n_errs += 1;
          $display("Mismatch occurred at %d", $time);
      end
    end
    if (n_errs > 0) begin
      $display("Test ***FAILED*** with ", n_errs, " mismatches out of ", nb_checks, " checks after ", nb_stims, " stimuli!");
    end else begin
      $display("Test ***PASSED*** with ", n_errs, " mismatches out of ", nb_checks, " checks after ", nb_stims, " stimuli.");
    end
    $stop();
  end

  initial begin: timeout_block
    while (nb_clock_cycles_timeout < Timeout) begin
      @(posedge clk);
      #(ACQ_DELAY);
      if(gift_output_valid && gift_output_ready) begin
          nb_clock_cycles_timeout = 0;
      end else begin
          nb_clock_cycles_timeout = nb_clock_cycles_timeout + 1;
      end
    end
    $display("Test ***TIMED OUT*** with ", n_errs, " mismatches out of ", nb_checks, " checks after ", nb_stims, " stimuli!");
    $stop;
  end


endmodule









endmodule