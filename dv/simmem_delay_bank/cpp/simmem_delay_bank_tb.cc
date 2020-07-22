// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "Vsimmem_delay_bank.h"
#include "verilated.h"
#include <cassert>
#include <iostream>
#include <memory>
#include <stdlib.h>
#include <unordered_map>
#include <vector>
#include <verilated_fst_c.h>

const bool kIterationVerbose = false;
const bool kPairsVerbose = false;
const bool kTransactionVerbose = false;

const int kResetLength = 5;
const int kTraceLevel = 6;
const int kIdWidth = 4;

const size_t kMinDelay = 3;
const size_t kMaxDelay = 10;
const size_t kNbLocalIdentifiers = 32;
const size_t kAdjustmentDelay = 1;  // Cycles to subtract to the actual delayh

typedef Vsimmem_delay_bank Module;

// This class implements elementary operations for the testbench
class DelayBankTestbench {
 public:
  /**
   * @param record_trace set to false to skip trace recording
   */
  DelayBankTestbench(bool record_trace = true,
                     const std::string &trace_filename = "sim.fst")
      : tick_count_(0l), record_trace_(record_trace), module_(new Module) {
    if (record_trace) {
      trace_ = new VerilatedFstC;
      module_->trace(trace_, kTraceLevel);
      trace_->open(trace_filename.c_str());
    }
  }

  ~DelayBankTestbench(void) { simmem_close_trace(); }

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
  void simmem_tick(int nbTicks = 1) {
    for (size_t i = 0; i < nbTicks; i++) {
      if (kIterationVerbose) {
        std::cout << "Running iteration " << tick_count_ << std::endl;
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
   * Applies valid input data.
   *
   * @param local_identifier the identifier of the incoming data
   * @param delay the delay applied as input to the module
   */
  void simmem_input_data_apply(uint32_t local_identifier, uint32_t delay) {
    module_->local_identifier_i = local_identifier;
    module_->delay_i = delay;
    module_->in_valid_i = 1;
  }

  /**
   * Stops feeding data to the DUT instance.
   */
  void simmem_input_data_stop(void) { module_->in_valid_i = 0; }

  /**
   * Signals that the corresponding local identifier has actually been released
   * by the memory bank.
   *
   * @param local_identifier the released local identifier
   */
  void simmem_output_data_apply(uint32_t local_identifier) {
    module_->address_released_onehot_i = 1 << local_identifier;
  }

  /**
   * Sets the released local identifier one-hot signal as full-zero.
   */
  void simmem_output_data_stop(void) { module_->address_released_onehot_i = 0; }

  /**
   * Checks the module's releasable signals against the testbench's.
   *
   * @param completed_identifiers an bool array of length kNbLocalIdentifiers,
   * whose cells are true iff the identifier should be released, according to
   * the golden model
   * @return true iff the check is successful
   */
  bool simmem_out_signals_check(bool *completed_identifiers) {
    if (kPairsVerbose) {
      for (size_t local_id = 0; local_id < kNbLocalIdentifiers; local_id++) {
        if (completed_identifiers[local_id]) {
          std::cout << local_id << " - "
                    << (bool)(module_->release_en_o & (1 << (local_id)))
                    << std::endl;
        }
      }
    }

    if (kTransactionVerbose) {
      std::cout << "Release signal: " << std::hex
                << (uint32_t)(module_->release_en_o) << std::dec << std::endl;
    }
    for (size_t local_id = 0; local_id < kNbLocalIdentifiers; local_id++) {
      if (completed_identifiers[local_id] !=
          (bool)(module_->release_en_o & (1 << (local_id)))) {
        return false;
      }
    }
    return true;
  }

 private:
  vluint32_t tick_count_;
  bool record_trace_;
  std::unique_ptr<Module> module_;
  VerilatedFstC *trace_;
};

/**
 * Performs a complete and randomized test.
 *
 * @param tb a pointer to a fresh testbench instance
 * @param seed the seed used for the random request generation
 *
 * @return the number of uncovered errors
 */
size_t randomized_test(DelayBankTestbench *tb, unsigned int seed) {
  srand(seed);
  tb->simmem_reset();

  size_t nb_iterations = 100;
  size_t nb_errors = 0;

  bool apply_input, apply_output;

  // Useful to forbid any input or output
  size_t nb_pending_expiration_times = 0;
  size_t nb_releasable_ids = 0;

  // Stores the next local identifier that will be releasable, along with its
  // expiration time
  std::pair<uint32_t, size_t> next_id_and_expiration =
      std::pair<uint32_t, size_t>(0, ~0);

  // The local identifiers that wait for releasability after input
  std::unordered_map<uint32_t, size_t> pending_expiration_times;

  // Currently releasable identifiers
  bool completed_identifiers[kNbLocalIdentifiers];
  for (size_t local_id = 0; local_id < kNbLocalIdentifiers; local_id++) {
    completed_identifiers[local_id] = false;
  }

  for (size_t current_time = 0; current_time < nb_iterations; current_time++) {
    if (kIterationVerbose) {
      std::cout << "Running iteration " << current_time << std::endl;
    }

    // Check if some delays expired. The loop treats the case
    // where multiple local identifiers are simultaneously newly releasable
    while (next_id_and_expiration.second == current_time) {
      if (kTransactionVerbose) {
        std::cout << "Delay expired for id " << next_id_and_expiration.first
                  << " with expiration " << next_id_and_expiration.second
                  << std::endl;
      }

      // Update the data structures
      completed_identifiers[next_id_and_expiration.first] = true;
      pending_expiration_times.erase(next_id_and_expiration.first);
      nb_releasable_ids++;

      // Update the next delay and corresponding identifier
      next_id_and_expiration.second = ~0;
      for (std::pair<uint32_t, size_t> pending_id_and_delay :
           pending_expiration_times) {
        if (pending_id_and_delay.second < next_id_and_expiration.second) {
          next_id_and_expiration = pending_id_and_delay;
        }
      }
    }

    // Take potential mismatches into account
    nb_errors += (size_t)!tb->simmem_out_signals_check(completed_identifiers);

    // Decide the random input and output actions
    apply_input = (nb_pending_expiration_times < kNbLocalIdentifiers) &&
                  (bool)(rand() & 1);
    apply_output = nb_releasable_ids && (bool)(rand() & 1);

    if (apply_input) {
      std::unordered_map<uint32_t, size_t>::const_iterator found_it;
      size_t tmp_input_expiration;
      uint32_t tmp_local_identifier;

      // Find the next local identifier to input
      do {
        tmp_local_identifier = rand() % kNbLocalIdentifiers;

        found_it = pending_expiration_times.find(tmp_local_identifier);
      } while (found_it != pending_expiration_times.end() ||
               completed_identifiers[tmp_local_identifier]);

      // Determine the corresponding input expiration time
      tmp_input_expiration = current_time +
                             (kMinDelay + rand() % (kMaxDelay - kMinDelay)) -
                             kAdjustmentDelay;

      // Update the storage of the next local identifier that expires
      if (tmp_input_expiration < next_id_and_expiration.second) {
        next_id_and_expiration = std::pair<uint32_t, size_t>(
            tmp_local_identifier, tmp_input_expiration);
      }
      if (kTransactionVerbose) {
        std::cout << "Inputting id " << tmp_local_identifier << " with exp "
                  << tmp_input_expiration << ", delay "
                  << tmp_input_expiration - current_time + kAdjustmentDelay
                  << std::endl;
      }

      // Update the pending expiration times data structure
      pending_expiration_times.insert(std::pair<uint32_t, size_t>(
          tmp_local_identifier, tmp_input_expiration));

      // Apply the inputs to the module
      tb->simmem_input_data_apply(
          tmp_local_identifier,
          tmp_input_expiration - current_time + kAdjustmentDelay);

      nb_pending_expiration_times++;
    }

    if (apply_output) {
      uint32_t tmp_output_identifier;
      // Determine the next identifier whose actual release will be signaled to
      // the DUT instance
      do {
        tmp_output_identifier = rand() % kNbLocalIdentifiers;
      } while (!completed_identifiers[tmp_output_identifier]);

      // Update the data structure of the currently releasable identifiers
      completed_identifiers[tmp_output_identifier] = false;

      // Apply the signal to the DUT instance
      tb->simmem_output_data_apply(tmp_output_identifier);
      nb_releasable_ids--;
    }

    tb->simmem_tick(1);

    // Reset all signals after tick (they may be set again before the next DUT
    // evaluation during the beginning of the next iteration)

    tb->simmem_input_data_stop();
    tb->simmem_output_data_stop();
  }

  return nb_errors;
}

int main(int argc, char **argv, char **env) {
  Verilated::commandArgs(argc, argv);
  Verilated::traceEverOn(true);

  size_t nb_errors;

  DelayBankTestbench *tb = new DelayBankTestbench(true, "delay_bank.fst");

  // Perform the actual randomized testing
  nb_errors = randomized_test(tb, 0);
  delete tb;

  std::cout << nb_errors << " errors uncovered." << std::endl;
  std::cout << "Testbench complete!" << std::endl;

  exit(0);
}
