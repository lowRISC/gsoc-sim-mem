// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "Vsimmem_resp_bank.h"
#include "verilated.h"
#include <cassert>
#include <iostream>
#include <map>
#include <memory>
#include <queue>
#include <stdlib.h>
#include <vector>
#include <verilated_fst_c.h>

const bool kIterationVerbose = false;
const bool kTransactionsVerbose = false;
const bool kPairsVerbose = false;

const int kResetLength = 5;
const int kTraceLevel = 6;
const int kRspWidth = 10;  // Whole response width
const int kIdWidth = 4;

typedef enum {
  SEQUENTIAL_TEST,
  SINGLE_ID_TEST,
  MULTIPLE_ID_TEST
} test_strategy_e;

typedef Vsimmem_resp_bank Module;
typedef std::map<uint32_t, std::queue<uint32_t>> queue_map_t;

const int kTestStrategy = MULTIPLE_ID_TEST;

// This class implements elementary operations for the testbench
class WriteRespBankTestbench {
 public:
  /**
   * @param trailing_clock_cycles number of ticks to perform after all the
   * requests have been performed
   * @param record_trace set to false to skip trace recording
   */
  WriteRespBankTestbench(vluint32_t trailing_clock_cycles = 0,
                         bool record_trace = true,
                         const std::string &trace_filename = "sim.fst")
      : tick_count_(0l),
        trailing_clock_cycles_(trailing_clock_cycles),
        record_trace_(record_trace),
        module_(new Module) {
    if (record_trace) {
      trace_ = new VerilatedFstC;
      module_->trace(trace_, kTraceLevel);
      trace_->open(trace_filename.c_str());
    }

    // Puts ones at the fields' places
    id_mask_ = ~((1 << 31) >> (31 - kIdWidth));
    content_mask_ = ~((1 << 31) >> (31 - kRspWidth - kIdWidth)) & ~id_mask_;
  }

  ~WriteRespBankTestbench(void) { simmem_close_trace(); }

  void simmem_reset(void) {
    module_->rst_ni = 0;
    this->simmem_tick(kResetLength);
    module_->rst_ni = 1;
  }

  void simmem_close_trace(void) { trace_->close(); }

  /**
   * Performs one or multiple clock cycles.
   *
   * @param nb_ticks the number of ticks to perform at once
   */
  void simmem_tick(int nb_ticls = 1) {
    for (size_t i = 0; i < nb_ticls; i++) {
      if (kIterationVerbose) {
        std::cout << "Running iteration" << tick_count_ << std::endl;
      }

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
   * Sets the reservation request signal to one and the reservation request
   * identifier to the right value.
   *
   * @param axi_id the AXI identifier to reserve
   */
  void simmem_reservation_start(uint32_t axi_id) {
    module_->rsv_valid_i = 1;
    module_->rsv_req_id_onehot_i = 1 << axi_id;
    module_->rsv_burst_len_i = 4;
  }

  /**
   * Sets the reservation request signal to zero.
   */
  void simmem_reservation_stop(void) { module_->rsv_valid_i = 0; }

  /**
   * Applies valid input data.
   *
   * @param identifier the AXI identifier of the incoming data
   * @param rsp the rest (rsp) of the incoming
   * data
   *
   * @return the data as seen by the design under test instance
   */
  uint32_t simmem_input_data_apply(uint32_t identifier, uint32_t rsp) {
    // Checks if the given values are not too big
    assert(!(rsp >> kRspWidth));
    assert(!(identifier >> kIdWidth));

    uint32_t in_data = rsp << kIdWidth | identifier;
    module_->rsp_i = in_data;
    module_->in_rsp_valid_i = 1;
    return in_data;
  }

  /**
   * Gets the newly reserved address as offered by the DUT.
   */
  uint32_t simmem_reservation_get_address(void) { return module_->rsv_addr_o; }

  /**
   * Checks whether the input data has been accepted by checking the ready
   * output signal.
   */
  bool simmem_input_data_check(void) {
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
  void simmem_input_data_stop(void) { module_->in_rsp_valid_i = 0; }

  /**
   * Allows all the data output from a releaser module standpoint.
   */
  void simmem_output_data_allow(void) { module_->release_en_i = -1; }

  /**
   * Forbids all the data output from a releaser module standpoint.
   */
  void simmem_output_data_forbid(void) { module_->release_en_i = 0; }

  /**
   * Sets the ready signal to one on the output side.
   */
  void simmem_output_data_request(void) { module_->out_rsp_ready_i = 1; }

  /**
   * Tries to fetch output data. Requires the ready signal to be one at the DUT
   * output.
   *
   * @param out_data the output data from the DUT
   *
   * @return true iff the data is valid
   */
  bool simmem_output_data_fetch(uint32_t &out_data) {
    module_->eval();
    assert(module_->out_rsp_ready_i);

    out_data = (uint32_t)module_->rsp_o;
    return (bool)(module_->out_rsp_valid_o);
  }

  /**
   * Sets the ready signal to zero on the output side.
   */
  void simmem_output_data_stop(void) { module_->out_rsp_ready_i = 0; }

  /**
   * Informs the testbench that all the requests have been performed and
   * therefore that the trailing cycles phase should start.
   */
  void simmem_requests_complete(void) { tick_count_ = 0; }

  /**
   * Checks whether the testbench completed the trailing cycles phase.
   */
  bool simmem_is_done(void) {
    return (
        Verilated::gotFinish() ||
        (trailing_clock_cycles_ && (tick_count_ >= trailing_clock_cycles_)));
  }

  /**
   * Getters.
   */
  uint32_t simmem_get_content_mask(void) { return content_mask_; }
  uint32_t simmem_get_identifier_mask(void) { return id_mask_; }

 private:
  vluint32_t tick_count_;
  vluint32_t trailing_clock_cycles_;
  bool record_trace_;
  std::unique_ptr<Module> module_;

  // Masks that contain ones in the corresponding fields
  uint32_t id_mask_;
  uint32_t content_mask_;
  VerilatedFstC *trace_;
};

/**
 * Performs a basic test as a temporally disjoint sequence of reservation, data
 * input and data output.
 *
 * @param tb a pointer to a fresh testbench instance
 */
void sequential_test(WriteRespBankTestbench *tb) {
  tb->simmem_reset();

  // Apply reservation requests for 4 ticks
  tb->simmem_reservation_start(
      4);  // Start issuing reservation requests for AXI ID 4
  tb->simmem_tick(4);
  tb->simmem_reservation_stop();  // Stop issuing reservation requests

  tb->simmem_tick(4);

  // Apply inputs for 6 ticks
  tb->simmem_input_data_apply(4, 3);
  tb->simmem_tick(6);
  tb->simmem_input_data_stop();

  tb->simmem_tick(4);

  // Enable data toutput
  tb->simmem_output_data_allow();
  tb->simmem_tick(4);

  // Express readiness for output data
  tb->simmem_output_data_request();
  tb->simmem_tick(10);
  tb->simmem_output_data_stop();

  tb->simmem_requests_complete();
  while (!tb->simmem_is_done()) {
    tb->simmem_tick();
  }
}

/**
 * Performs a complete test for a single AXI identifier. Reservation, input and
 * output requests, as well as the data rsp (except for the AXI
 * identifier) are randomized.
 *
 * @param tb a pointer to a fresh testbench instance
 * @param seed the seed used for the random request generation
 *
 * @return the number of mismatches between the expected and acquired outputs
 */
size_t single_id_test(WriteRespBankTestbench *tb, unsigned int seed) {
  srand(seed);

  uint32_t current_input_id = 4;
  size_t nb_iterations = 1000;

  // Generate inputs
  std::queue<uint32_t> input_queue;
  std::queue<uint32_t> output_queue;

  bool reserve;
  bool apply_input;
  bool request_output_data;

  uint32_t current_content =
      (uint32_t)((rand() & tb->simmem_get_content_mask()) >> kIdWidth);
  uint32_t current_input;
  uint32_t current_output;

  tb->simmem_reset();
  // Sets the input signal from releaser such that the releaser allows all
  // output signals
  tb->simmem_output_data_allow();

  for (size_t i = 0; i < nb_iterations; i++) {
    // Randomize the boolean signals deciding which interactions will take place
    // in this cycle
    reserve = (bool)(rand() & 1);
    apply_input = (bool)(rand() & 1);
    request_output_data = (bool)(rand() & 1);

    if (reserve) {
      // Signal a reservation request
      tb->simmem_reservation_start(current_input_id);
    }
    if (apply_input) {
      current_input =
          tb->simmem_input_data_apply(current_input_id, current_content);
    }
    if (request_output_data) {
      tb->simmem_output_data_request();
    }

    // Only perform the evaluation once all the inputs have been applied
    if (tb->simmem_input_data_check()) {
      input_queue.push(current_input);
      current_content =
          (uint32_t)((rand() & tb->simmem_get_content_mask()) >> kIdWidth);
    }
    if (request_output_data) {
      if (tb->simmem_output_data_fetch(current_output)) {
        output_queue.push(current_output);
      }
    }

    tb->simmem_tick();

    // Reset all signals after tick (they may be set again before the next DUT
    // evaluation during the beginning of the next iteration)

    if (reserve) {
      tb->simmem_reservation_stop();
    }
    if (apply_input) {
      tb->simmem_input_data_stop();
    }
    if (request_output_data) {
      tb->simmem_output_data_stop();
    }
  }

  tb->simmem_requests_complete();
  while (!tb->simmem_is_done()) {
    tb->simmem_tick();
  }

  // Check the input and output queues for mismatches
  size_t nb_mismatches = 0;
  while (!input_queue.empty() && !output_queue.empty()) {
    current_input = input_queue.front();
    current_output = output_queue.front();

    input_queue.pop();
    output_queue.pop();

    if (kPairsVerbose) {
      std::cout << std::hex << current_input << " - " << current_output
                << std::endl;
    }
    nb_mismatches += (size_t)(current_input != current_output);
  }
  if (kPairsVerbose) {
    std::cout << std::endl
              << "Mismatches: " << std::dec << nb_mismatches << std::endl
              << std::endl;
  }

  return nb_mismatches;
}

/**
 * Performs a complete test for multiple AXI identifiers. Reservation, input and
 * output requests, as well as the data rsp (except for the AXI
 * identifier) are randomized.
 *
 * @param tb a pointer to a fresh testbench instance
 * @param num_identifiers the number of AXI identifiers to use in the test, must
 * be included between 1 and 2**kIdWidth
 * @param seed the seed used for the random request generation
 *
 * @return the number of mismatches between the expected and acquired outputs
 */

size_t multiple_ids_test(WriteRespBankTestbench *tb, size_t num_identifiers,
                         unsigned int seed) {
  srand(seed);

  size_t nb_iterations = 1000;

  std::vector<uint32_t> identifiers;

  for (size_t i = 0; i < num_identifiers; i++) {
    identifiers.push_back(i);
  }

  queue_map_t input_queues;
  queue_map_t output_queues;

  for (size_t i = 0; i < num_identifiers; i++) {
    input_queues.insert(std::pair<uint32_t, std::queue<uint32_t>>(
        identifiers[i], std::queue<uint32_t>()));
    output_queues.insert(std::pair<uint32_t, std::queue<uint32_t>>(
        identifiers[i], std::queue<uint32_t>()));
  }

  bool reserve;
  bool apply_input;
  bool request_output_data;
  bool iteration_announced;  // Variable only used for display

  uint32_t current_input_id = identifiers[rand() % num_identifiers];
  uint32_t current_content =
      (uint32_t)((rand() & tb->simmem_get_content_mask()) >> kIdWidth);
  uint32_t current_reservation_id = identifiers[rand() % num_identifiers];
  uint32_t current_input;
  uint32_t current_output;

  tb->simmem_reset();
  // Sets the input signal from releaser such that the releaser allows all
  // output signals
  tb->simmem_output_data_allow();

  for (size_t i = 0; i < nb_iterations; i++) {
    iteration_announced = false;

    // Randomize the boolean signals deciding which interactions will take place
    // in this cycle
    reserve = (bool)(rand() & 1);
    apply_input = (bool)(rand() & 1);
    request_output_data = (bool)(rand() & 1);

    if (reserve) {
      // Signal a reservation request
      tb->simmem_reservation_start(current_reservation_id);
    }
    if (apply_input) {
      // Apply a given input
      current_input =
          tb->simmem_input_data_apply(current_input_id, current_content);
    }
    if (request_output_data) {
      // Try to fetch an output if the handshake is successful
      tb->simmem_output_data_request();
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

      // Renew the reservation identifier if the reservation has been successful
      current_reservation_id = identifiers[rand() % num_identifiers];
    }
    if (tb->simmem_input_data_check()) {
      // If the input handshake has been successful, then add the input into the
      // corresponding queue

      input_queues[current_input_id].push(current_input);
      if (kTransactionsVerbose) {
        if (!iteration_announced) {
          iteration_announced = true;
          std::cout << std::endl << "Step " << std::dec << i << std::endl;
        }
        std::cout << std::dec << current_input_id << " inputs " << std::hex
                  << current_input << std::endl;
      }

      // Renew the input data if the input handshake has been successful
      current_input_id = identifiers[rand() % num_identifiers];
      current_content =
          (uint32_t)((rand() & tb->simmem_get_content_mask()) >> kIdWidth);
    }
    if (request_output_data) {
      // If the output handshake has been successful, then add the output to the
      // corresponding queue
      if (tb->simmem_output_data_fetch(current_output)) {
        output_queues[identifiers[(current_output &
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

    // Reset all signals after tick (they may be set again before the next DUT
    // evaluation during the beginning of the next iteration)

    if (reserve) {
      tb->simmem_reservation_stop();
    }
    if (apply_input) {
      tb->simmem_input_data_stop();
    }
    if (request_output_data) {
      tb->simmem_output_data_stop();
    }
  }

  tb->simmem_requests_complete();
  while (!tb->simmem_is_done()) {
    tb->simmem_tick();
  }

  // Check the input and output queues for mismatches
  size_t nb_mismatches = 0;
  for (size_t i = 0; i < num_identifiers; i++) {
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
      nb_mismatches += (size_t)(current_input != current_output);
    }
  }

  return nb_mismatches;
}

int main(int argc, char **argv, char **env) {
  Verilated::commandArgs(argc, argv);
  Verilated::traceEverOn(true);

  // Counts the number of mismatches during the whole test
  size_t total_nb_mismatches = 0;

  for (unsigned int seed = 0; seed < 100; seed++) {
    // Counts the number of mismatches during the loop iteration
    size_t local_nb_mismatches;

    // Instantiate the DUT instance
    WriteRespBankTestbench *tb =
        new WriteRespBankTestbench(100, true, "resp_bank.fst");

    // Perform one test for the given seed
    if (kTestStrategy == SINGLE_ID_TEST) {
      sequential_test(tb);
      break;
    } else if (kTestStrategy == SINGLE_ID_TEST) {
      local_nb_mismatches = single_id_test(tb, seed);
    } else {
      local_nb_mismatches = multiple_ids_test(tb, 4, seed);
    }

    total_nb_mismatches += local_nb_mismatches;
    std::cout << "Mismatches for seed " << std::dec << seed << ": "
              << local_nb_mismatches << std::hex << std::endl;
    delete tb;
  }

  std::cout << "Testbench complete!" << std::endl;

  exit(0);
}
