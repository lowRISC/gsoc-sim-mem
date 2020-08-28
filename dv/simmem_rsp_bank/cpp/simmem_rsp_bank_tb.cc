// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// This testbench offers partial testing of the simumated memory controller response banks:
//  * Response integrity.
//  * Response ordering per AXI identifier.
//
// The testbench is divided into 2 parts:
//  * Definition of the WriteRspBankTestbench class, which is the interface with the design under
//    test.
//  * Definition of a manual and a randomized testbench. The randomized testbench randomly applies
//    inputs and observe output delays and contents.

// As the reservation and response actions are decorellated, deadlock situations may appear,
// especially for low ratios NumIds over bank capacity. Those are due to the fact that one input
// response has an AXI ID which has not been reserved yet, but all cells are already reserved for
// other IDs. This issue does not appear at the toplevel, where reservations are made realistically.

#include "Vsimmem_rsp_bank.h"
#include "verilated.h"
#include <cassert>
#include <iostream>
#include <map>
#include <memory>
#include <queue>
#include <stdlib.h>
#include <vector>
#include <verilated_fst_c.h>

// Choose whether to display all the transactions
const bool kTransactionsVerbose = false;
// Choose whether to display all (input,output) pairs in the end of each execution.
const bool kPairsVerbose = true;

// Length of the reset signal.
const int kResetLength = 5; // Cycles
// Depth of the trace.
const int kTraceLevel = 6;

const int kIdWidth = 2; // AXI identifier width
const int kRspWidth = 4+kIdWidth;  // Whole response width

// Testbench choice.
typedef enum { MANUAL_TEST, RANDOMIZED_TEST } test_strategy_e;
const test_strategy_e kTestStrategy = RANDOMIZED_TEST;

// Determines the number of independent testbenches are performed in the randomized testbench. Set to 1 to
// proceed with wave analysis.
const size_t NUM_RANDOM_TEST_ROUNDS = 100;

// Determines the number of steps per randomized testbench round.
const size_t NUM_RANDOM_TEST_STEPS = 1000;

// Determines the number of AXI identifiers involved in the randomized testbench.
const size_t NUM_IDENTIFIERS = 2;

typedef Vsimmem_rsp_bank Module;
typedef std::map<uint32_t, std::queue<uint32_t>> queue_map_t;

// This class implements elementary operations for the testbench
class WriteRspBankTestbench {
 public:
  /**
   * @param record_trace set to false to skip trace recording
   */
  WriteRspBankTestbench(bool record_trace = true,
                         const std::string &trace_filename = "sim.fst")
      : tick_count_(0l),
        record_trace_(record_trace),
        module_(new Module) {
    if (record_trace) {
      trace_ = new VerilatedFstC;
      module_->trace(trace_, kTraceLevel);
      trace_->open(trace_filename.c_str());
    }

    // Puts ones at the fields' places
    id_mask_ = ~((1 << 31) >> (31 - kIdWidth));
    content_mask_ = ~((1 << 31) >> (31 - kRspWidth + kIdWidth)) & ~id_mask_;

    // The delay bank is supposedly always ready to receive address requests.
    module_->delay_calc_ready_i = 1;
  }

  ~WriteRspBankTestbench(void) { simmem_close_trace(); }

  void simmem_reset(void) {
    module_->rst_ni = 0;
    this->simmem_tick(kResetLength);
    module_->rst_ni = 1;
  }

  void simmem_close_trace(void) { trace_->close(); }

  /**
   * Performs one or multiple clock cycles.
   *
   * @param num_ticks the number of ticks to perform at once
   */
  void simmem_tick(int num_ticks = 1) {
    for (size_t i = 0; i < num_ticks; i++) {
      tick_count_++;

      module_->clk_i = 0;
      module_->eval();

      if (record_trace_) {
        trace_->dump(5 * tick_count_ - 1);
      }
      module_->clk_i = 1;
      module_->eval();

      if (record_trace_) {
        trace_->dump(5 * tick_count_);
      }
      module_->clk_i = 0;
      module_->eval();

      if (record_trace_) {
        trace_->dump(5 * tick_count_ + 2);
        trace_->flush();
      }
    }
  }

  /**
   * Sets the reservation request signal to one and the reservation request identifier to the right
   * value.
   *
   * @param axi_id the AXI identifier to reserve
   */
  void simmem_reservation_start(uint32_t axi_id) {
    module_->rsv_valid_i = 1;
    module_->rsv_req_id_onehot_i = 1 << axi_id;

    // Must be not larger than MaxBurstLenField
    module_->rsv_burst_len_i = 2;
  }

  /**
   * Sets the reservation request signal to zero.
   */
  void simmem_reservation_stop(void) { module_->rsv_valid_i = 0; }

  /**
   * Applies valid input data.
   *
   * @param identifier the AXI identifier of the incoming data
   * @param rsp the rest (rsp) of the incoming data
   *
   * @return the data as seen by the design under test instance
   */
  uint32_t simmem_input_rsp_apply(uint32_t identifier, uint32_t rsp) {
    // Checks if the given values are not too big
    assert(!(rsp >> (kRspWidth - kIdWidth)));
    assert(!(identifier >> kIdWidth));

    uint32_t in_rsp = rsp << kIdWidth | identifier;
    module_->rsp_i = in_rsp;
    module_->in_rsp_valid_i = 1;
    return in_rsp;
  }

  /**
   * Gets the newly reserved address as offered by the DUT.
   */
  uint32_t simmem_reservation_get_address(void) { return module_->rsv_iid_o; }

  /**
   * Checks whether the input data has been accepted by checking the ready output signal.
   */
  bool simmem_input_rsp_check(void) {
    module_->eval();
    return (bool)(module_->in_rsp_ready_o);
  }

  /**
   * Checks whether the reservation request has been accepted.
   */
  bool simmem_reservation_check(void) {
    module_->eval();
    return (bool)(module_->rsv_ready_o);
  }

  /**
   * Stops applying data to the DUT instance.
   */
  void simmem_input_rsp_stop(void) { module_->in_rsp_valid_i = 0; }

  /**
   * Allows all the data output from a releaser module standpoint.
   */
  void simmem_output_rsp_allow(void) { module_->release_en_i = -1; }

  /**
   * Forbids all the data output from a releaser module standpoint.
   */
  void simmem_output_rsp_forbid(void) { module_->release_en_i = 0; }

  /**
   * Sets the ready signal to one on the output side.
   */
  void simmem_output_rsp_request(void) { module_->out_rsp_ready_i = 1; }

  /**
   * Tries to fetch output data. Requires the ready signal to be one at the DUT output.
   *
   * @param out_rsp the output data from the DUT
   *
   * @return true iff the data is valid
   */
  bool simmem_output_rsp_fetch(uint32_t &out_rsp) {
    module_->eval();
    assert(module_->out_rsp_ready_i);

    out_rsp = (uint32_t)module_->rsp_o;
    return (bool)(module_->out_rsp_valid_o);
  }

  /**
   * Sets the ready signal to zero on the output side.
   */
  void simmem_output_rsp_stop(void) { module_->out_rsp_ready_i = 0; }

  /**
   * Getters.
   */
  uint32_t simmem_get_content_mask(void) { return content_mask_; }
  uint32_t simmem_get_identifier_mask(void) { return id_mask_; }

 private:
  vluint32_t tick_count_;
  bool record_trace_;
  std::unique_ptr<Module> module_;
  VerilatedFstC *trace_;

  // Masks that contain ones in the corresponding fields.
  uint32_t id_mask_;
  uint32_t content_mask_;
};

/**
 * Performs a basic test as a temporally disjoint sequence of reservation, data input and data
 * output.
 *
 * @param tb a pointer to a fresh testbench instance
 */
void manual_test(WriteRspBankTestbench *tb) {
  tb->simmem_reset();

  // Apply reservation requests for 4 ticks
  tb->simmem_reservation_start(
      3);  // Start issuing reservation requests for AXI ID 3
  tb->simmem_tick(4);
  tb->simmem_reservation_stop();  // Stop issuing reservation requests

  tb->simmem_tick(4);

  // Apply inputs for 6 ticks
  tb->simmem_input_rsp_apply(3, 2);
  tb->simmem_tick(7);
  tb->simmem_input_rsp_stop();

  tb->simmem_tick(4);

  // Enable data toutput
  tb->simmem_output_rsp_allow();
  tb->simmem_tick(5);

  tb->simmem_output_rsp_request();
  tb->simmem_tick(10);
  tb->simmem_output_rsp_stop();

  tb->simmem_tick(100);
}

/**
 * This function implements a more complete, randomized and automatic testbench.
 *
 * @param tb A pointer the the already contructed SimmemTestbench object.
 * @param num_ids The number of AXI identifiers to involve. Must be at
 * lest 1, and lower than NumIds.
 * @param seed The seed for the randomized test.
 * @param num_cycles The number of simulated clock cycles.
 */
size_t randomized_testbench(WriteRspBankTestbench *tb, size_t num_ids,
                         unsigned int seed, size_t num_cycles = 1000) {
  srand(seed);

  // The AXI identifiers. During the testbench, we will always use the [0,..,num_ids) ids.
  std::vector<uint32_t> ids;
  for (size_t i = 0; i < num_ids; i++) {
    ids.push_back(i);
  }

  // These structures will store the input and output data, for comparison purposes.
  queue_map_t input_queues;
  queue_map_t output_queues;

  for (size_t i = 0; i < num_ids; i++) {
    input_queues.insert(std::pair<uint32_t, std::queue<uint32_t>>(
        ids[i], std::queue<uint32_t>()));
    output_queues.insert(std::pair<uint32_t, std::queue<uint32_t>>(
        ids[i], std::queue<uint32_t>()));
  }

  // Signal whether some input is applied to the simmem.
  bool reserve;
  bool apply_input;
  bool request_output_rsp;

  bool iteration_announced;  // Variable only used for display purposes.

  // Initialization of the next messages that will be supplied.
  uint32_t current_input_id = ids[rand() % num_ids];
  uint32_t current_content =
      (uint32_t)((rand() & tb->simmem_get_content_mask()) >> kIdWidth);
  uint32_t current_reservation_id = ids[rand() % num_ids];
  uint32_t current_input;
  uint32_t current_output;

  //////////////////////
  // Simulation start //
  //////////////////////

  tb->simmem_reset();

  // The ready signal is always 1 for the simmem output.
  tb->simmem_output_rsp_allow();

  for (size_t i = 0; i < num_cycles; i++) {
    iteration_announced = false;

    // Randomize the boolean signals deciding which interactions will happen in this cycle.
    reserve = (bool)(rand() & 1);
    apply_input = (bool)(rand() & 1);
    request_output_rsp = (bool)(rand() & 1);

    if (reserve) {
      // Apply the reservation request.
      tb->simmem_reservation_start(current_reservation_id);
    }
    if (apply_input) {
      // Apply the input response.
      current_input =
          tb->simmem_input_rsp_apply(current_input_id, current_content);
    }
    if (request_output_rsp) {
      // Fetch an output if the handshake is successful.
      tb->simmem_output_rsp_request();
    }

    // Only perform the evaluation once all the inputs have been applied
    if (reserve && tb->simmem_reservation_check()) {
      if (kTransactionsVerbose) {
        if (!iteration_announced) {
          iteration_announced = true;
          std::cout << std::endl << "Step " << std::dec << i << std::endl;
        }
        std::cout << current_reservation_id << " reserves "
                  << tb->simmem_reservation_get_address() << std::endl;
      }

      // Renew the reservation identifier if the reservation is successful.
      current_reservation_id = ids[rand() % num_ids];
    }
    if (tb->simmem_input_rsp_check()) {
      // If the input handshake is successful, then add the input into the corresponding queue.
      input_queues[current_input_id].push(current_input);
      if (kTransactionsVerbose) {
        if (!iteration_announced) {
          iteration_announced = true;
          std::cout << std::endl << "Step " << std::dec << i << std::endl;
        }
        std::cout << std::dec << current_input_id << " inputs " << std::hex
                  << current_input << std::endl;
      }

      // Renew the input data if the input handshake is successful
      current_input_id = ids[rand() % num_ids];
      current_content =
          (uint32_t)((rand() & tb->simmem_get_content_mask()) >> kIdWidth);
    }
    if (request_output_rsp) {
      // If the output handshake is successful, then add the output to the corresponding queue
      if (tb->simmem_output_rsp_fetch(current_output)) {
        output_queues[ids[(current_output &
                                   tb->simmem_get_identifier_mask())]]
            .push(current_output);

        if (kTransactionsVerbose) {
          if (!iteration_announced) {
            iteration_announced = true;
            std::cout << std::endl << "Step " << std::dec << i << std::endl;
          }
          std::cout << std::dec
                    << (uint32_t)(current_output &
                                  tb->simmem_get_identifier_mask())
                    << " outputs " << std::hex << current_output << std::endl;
        }
      }
    }

    tb->simmem_tick();

    // Reset all signals after tick (they may be set again before the next DUT evaluation during the
    // beginning of the next iteration)
    if (reserve) {
      tb->simmem_reservation_stop();
    }
    if (apply_input) {
      tb->simmem_input_rsp_stop();
    }
    if (request_output_rsp) {
      tb->simmem_output_rsp_stop();
    }
  }

  tb->simmem_tick(100);

  // Check the input and output queues for mismatches.
  size_t num_mismatches = 0;
  for (size_t i = 0; i < num_ids; i++) {
    if (kPairsVerbose) {
      std::cout << std::dec << "--- ID: " << i << " ---" << std::endl;
    }
    while (!input_queues[i].empty() && !output_queues[i].empty()) {
      current_input = input_queues[i].front();
      current_output = output_queues[i].front();

      input_queues[i].pop();
      output_queues[i].pop();
      if (kPairsVerbose) {
        std::cout << std::hex << current_input << " - " << current_output
                  << std::endl;
      }
      num_mismatches += (size_t)(current_input != current_output);
    }
  }
  return num_mismatches;
}

int main(int argc, char **argv, char **env) {
  Verilated::commandArgs(argc, argv);
  Verilated::traceEverOn(true);

  // Counts the number of mismatches during the whole test
  size_t total_num_mismatches = 0;

  for (unsigned int seed = 0; seed < NUM_RANDOM_TEST_ROUNDS; seed++) {
    // Counts the number of mismatches during the loop iteration
    size_t local_num_mismatches;

    // Instantiate the DUT instance
    WriteRspBankTestbench *tb =
        new WriteRspBankTestbench(true, "rsp_bank.fst");

    // Perform one test for the given seed
    if (kTestStrategy == MANUAL_TEST) {
      manual_test(tb);
      break;
    } else if (kTestStrategy == RANDOMIZED_TEST) {
      local_num_mismatches = randomized_testbench(tb, NUM_IDENTIFIERS, seed);
    }

    total_num_mismatches += local_num_mismatches;
    std::cout << "Mismatches for seed " << std::dec << seed << ": "
              << local_num_mismatches << std::hex << std::endl;
    delete tb;
  }

  std::cout << "Testbench complete!" << std::endl;

  exit(0);
}
