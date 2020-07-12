// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "Vsimmem_write_only_nocontent.h"
#include "simmem_axi_structures.h"
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
const size_t kAdjustmentDelay = 1;  // Cycles to subtract to the actual delay

typedef Vsimmem_write_only_nocontent Module;

// This class implements elementary operations for the testbench
class SimmemWriteOnlyNoBurstTestbench {
 public:
  /**
   * @param record_trace set to false to skip trace recording
   */
  SimmemWriteOnlyNoBurstTestbench(vluint32_t trailing_clock_cycles = 0,
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
  }

  ~SimmemWriteOnlyNoBurstTestbench() { simmem_close_trace(); }

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
   * Applies a valid input address request as the requester.
   *
   * @param waddr_req the input address request
   */
  void simmem_requester_waddr_apply(WriteAddressRequest waddr_req) {
    module_->waddr_data_i = waddr_req.get_packed();
    module_->waddr_in_valid_i = 1;
  }

  /**
   * Stops feeding a valid input write address request as the requester.
   */
  void simmem_requester_waddr_stop(void) { module_->waddr_in_valid_i = 0; }

  /**
   * Sets the ready signal to one on the DUT output side for the write response.
   */
  void simmem_requester_wresp_request(void) { module_->wresp_out_ready_i = 1; }

  /**
   * Fetches a write response as the requester. Requires the ready signal to be
   * one at the DUT output.
   *
   * @param out_data the output write response from the DUT
   *
   * @return true iff the data is valid
   */
  bool simmem_requester_wresp_fetch(WriteResponse &out_data) {
    module_->eval();
    assert(module_->wresp_out_ready_i);

    out_data.set_packed(module_->wresp_data_o);
    return (bool)(module_->wresp_out_valid_o);
  }

  /**
   * Sets the ready signal to zero on the DUT output side for the write
   * response.
   */
  void simmem_requester_wresp_stop(void) { module_->wresp_out_ready_i = 0; }

  /**
   * Applies a valid write response the real memory controller.
   *
   * @param wresp the input write response
   */
  void simmem_realmem_wresp_apply(WriteResponse wresp) {
    module_->wresp_data_i = wresp.get_packed();
    module_->wresp_in_valid_i = 1;
  }

  /**
   * Stops feeding a valid input write response as the real memory controller.
   */
  void simmem_realmem_wresp_stop(void) { module_->wresp_in_valid_i = 0; }

  /**
   * Sets the ready signal to one on the DUT output side for the write address.
   */
  void simmem_realmem_waddr_request(void) { module_->waddr_out_ready_i = 1; }

  /**
   * Fetches a write address as the real memory controller. Requires the ready
   * signal to be one at the DUT output.
   *
   * @param out_data the output write address request from the DUT
   *
   * @return true iff the data is valid
   */
  bool simmem_realmem_waddr_fetch(WriteAddressRequest &out_data) {
    module_->eval();
    assert(module_->waddr_out_ready_i);

    out_data.set_packed(module_->waddr_data_o);
    return (bool)(module_->waddr_out_valid_o);
  }

  /**
   * Sets the ready signal to zero on the DUT output side for the write
   * address.
   */
  void simmem_realmem_waddr_stop(void) { module_->waddr_out_ready_i = 0; }

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

 private:
  vluint32_t tick_count_;
  vluint32_t trailing_clock_cycles_;
  bool record_trace_;
  std::unique_ptr<Module> module_;
  VerilatedFstC *trace_;
};

void simple_testbench(SimmemWriteOnlyNoBurstTestbench *tb) {
  tb->simmem_reset();

  tb->simmem_tick(5);

  while (!tb->simmem_is_done()) {
    tb->simmem_tick();
  }
}

int main(int argc, char **argv, char **env) {
  Verilated::commandArgs(argc, argv);
  Verilated::traceEverOn(true);

  SimmemWriteOnlyNoBurstTestbench *tb = new SimmemWriteOnlyNoBurstTestbench(
      100, true, "write_only_nocontent.fst");

  // Choose testbench type
  simple_testbench(tb);
  delete tb;

  // std::cout << nb_errors << " errors uncovered." << std::endl;
  std::cout << "Testbench complete!" << std::endl;

  exit(0);
}
