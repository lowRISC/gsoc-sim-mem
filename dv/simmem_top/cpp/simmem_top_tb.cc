// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// This testbench offers partial testing of the simumated memory controller:
//  * Delay assessment for write responses.
//  * Write response ordering.
//
// The testbench is divided into 3 parts:
//  * Definition of the SimmemTestbench class, which is the interface with the
//  design under test.
//  * Definition of a RealMem class, which emulates a simple and instantaneous
//  real memory
//    controller, which immediately responds to requests.
//  * Definition of a manual and a randomized testbench. The randomized
//  testbench randomly applies
//    inputs and observe output delays and contents.

#include "Vsimmem_top.h"
#include "simmem_axi_structures.h"
#include "verilated.h"
#include <cassert>
#include <iostream>
#include <memory>
#include <queue>
#include <stdlib.h>
#include <unordered_map>
#include <vector>
#include <verilated_fst_c.h>

// Choose whether to display all the transactions
const bool kTransactionVerbose = true;

// Length of the reset signal.
const int kResetLength = 5;  // Cycles
// Depth of the trace.
const int kTraceLevel = 6;

// Constant burst lengths supplied to the DUT
const int kWBurstLenField = 3;
const int kRBurstLenField = 2;

// Constant burst sizes supplied to the DUT
const int kWBurstSize = 2;
const int kRBurstSize = 2;

// Testbench choice.
typedef enum { MANUAL_TEST, RANDOMIZED_TEST } test_strategy_e;
const test_strategy_e kTestStrategy = RANDOMIZED_TEST;

// Determines the number of AXI identifiers involved in the randomized
// testbench.
const size_t NUM_IDENTIFIERS = 2;

// Determines seed for the randomized testbench.
const unsigned int SEED = 2;

// Determines the number of steps per randomized testbench.
const size_t NUM_RANDOM_TEST_STEPS = 1000;

typedef Vsimmem_top Module;

typedef std::map<uint64_t, std::queue<WriteResponse>> wrsp_queue_map_t;
typedef std::map<uint64_t, u_int64_t> wids_cnt_t;
typedef std::queue<std::pair<uint64_t, u_int64_t>>
    wids_cnt_queue_t;  // <id, burst_len>
typedef std::map<uint64_t, std::queue<ReadData>> rdata_queue_map_t;

// Maps mapping AXI identifiers to queues of pairs (timestamp, response)
typedef std::map<uint64_t, std::queue<std::pair<size_t, WriteAddress>>>
    waddr_time_queue_map_t;
typedef std::map<uint64_t, std::queue<std::pair<size_t, WriteData>>>
    wdata_time_queue_map_t;
typedef std::map<uint64_t, std::queue<std::pair<size_t, ReadAddress>>>
    raddr_time_queue_map_t;
typedef std::map<uint64_t, std::queue<std::pair<size_t, WriteResponse>>>
    wrsp_time_queue_map_t;
typedef std::map<uint64_t, std::queue<std::pair<size_t, ReadData>>>
    rdata_time_queue_map_t;

// This class implements elementary operations for the testbench
class SimmemTestbench {
 public:
  /**
   * @param record_trace set to false to skip trace recording
   */
  SimmemTestbench(bool record_trace = true,
                  const std::string &trace_filename = "sim.fst")
      : tick_count_(0l), record_trace_(record_trace), module_(new Module) {
    if (record_trace) {
      trace_ = new VerilatedFstC;
      module_->trace(trace_, kTraceLevel);
      trace_->open(trace_filename.c_str());
    }

    wrsp_mask_ =
        ~((1L << 63) >> (64 - WriteResponse::id_w - WriteResponse::rsp_w));
  }

  ~SimmemTestbench() { simmem_close_trace(); }

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
   * Applies a valid input address request as the requester.
   *
   * @param waddr_req the input address request
   */
  void simmem_requester_waddr_apply(WriteAddress waddr_req) {
    module_->waddr_i = waddr_req.to_packed();
    module_->waddr_in_valid_i = 1;
  }

  /**
   * Checks whether the input request has been accepted.
   */
  bool simmem_requester_waddr_check() {
    module_->eval();
    return (bool)(module_->waddr_in_ready_o);
  }

  /**
   * Stops applying a valid input write address request as the requester.
   */
  void simmem_requester_waddr_stop(void) { module_->waddr_in_valid_i = 0; }

  /**
   * Applies a valid input data request as the requester.
   *
   * @param wdata_req the input address request
   */
  void simmem_requester_wdata_apply(WriteData wdata_req) {
    module_->wdata_i = wdata_req.to_packed();
    module_->wdata_in_valid_i = 1;
  }

  /**
   * Checks whether the input request has been accepted.
   */
  bool simmem_requester_wdata_check() {
    module_->eval();

    return (bool)(module_->wdata_in_ready_o);
  }

  /**
   * Stops applying a valid input write address request as the requester.
   */
  void simmem_requester_wdata_stop(void) { module_->wdata_in_valid_i = 0; }

  /**
   * Applies a valid input address request as the requester.
   *
   * @param raddr_req the input address request
   */
  void simmem_requester_raddr_apply(ReadAddress raddr_req) {
    module_->raddr_i = raddr_req.to_packed();
    module_->raddr_in_valid_i = 1;
  }

  /**
   * Checks whether the input request has been accepted.
   */
  bool simmem_requester_raddr_check() {
    module_->eval();
    return (bool)(module_->raddr_in_ready_o);
  }

  /**
   * Stops applying a valid input read address request as the requester.
   */
  void simmem_requester_raddr_stop(void) { module_->raddr_in_valid_i = 0; }

  /**
   * Sets the ready signal to one on the DUT output side for the write response.
   */
  void simmem_requester_wrsp_request(void) { module_->wrsp_out_ready_i = 1; }

  /**
   * Fetches a write response as the requester. Requires the ready signal to be
   * one at the DUT output.
   *
   * @param out_data the output write response from the DUT
   *
   * @return true iff the data is valid
   */
  bool simmem_requester_wrsp_fetch(WriteResponse &out_data) {
    module_->eval();
    assert(module_->wrsp_out_ready_i);

    out_data.from_packed(module_->wrsp_o);
    return (bool)(module_->wrsp_out_valid_o);
  }

  /**
   * Sets the ready signal to zero on the DUT output side for the write
   * response.
   */
  void simmem_requester_wrsp_stop(void) { module_->wrsp_out_ready_i = 0; }

  /**
   * Sets the ready signal to one on the DUT output side for the read data.
   */
  void simmem_requester_rdata_request(void) { module_->rdata_out_ready_i = 1; }

  /**
   * Fetches a read data as the requester. Requires the ready signal to be one
   * at the DUT output.
   *
   * @param out_data the output read data from the DUT
   *
   * @return true iff the data is valid
   */
  bool simmem_requester_rdata_fetch(ReadData &out_data) {
    module_->eval();
    assert(module_->rdata_out_ready_i);

    out_data.from_packed(module_->rdata_o);
    return (bool)(module_->rdata_out_valid_o);
  }

  /**
   * Sets the ready signal to zero on the DUT output side for the write
   * response.
   */
  void simmem_requester_rdata_stop(void) { module_->rdata_out_ready_i = 0; }

  /**
   * Applies a valid write response the real memory controller.
   *
   * @param wrsp the input write response
   */
  void simmem_realmem_wrsp_apply(WriteResponse wrsp) {
    module_->wrsp_i = wrsp.to_packed();

    module_->wrsp_in_valid_i = 1;
  }

  /**
   * Checks whether the input request has been accepted.
   */
  bool simmem_realmem_wrsp_check() {
    module_->eval();
    return (bool)(module_->wrsp_in_ready_o);
  }

  /**
   * Stops applying a valid input write response as the real memory controller.
   */
  void simmem_realmem_wrsp_stop(void) { module_->wrsp_in_valid_i = 0; }

  /**
   * Applies a valid read data the real memory controller.
   *
   * @param rdata the input read data
   */
  void simmem_realmem_rdata_apply(ReadData rdata) {
    module_->rdata_i = rdata.to_packed();

    module_->rdata_in_valid_i = 1;
  }

  /**
   * Checks whether the input request has been accepted.
   */
  bool simmem_realmem_rdata_check() {
    module_->eval();
    return (bool)(module_->rdata_in_ready_o);
  }

  /**
   * Stops applying a valid input read data as the real memory controller.
   */
  void simmem_realmem_rdata_stop(void) { module_->rdata_in_valid_i = 0; }

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
  bool simmem_realmem_waddr_fetch(WriteAddress &out_data) {
    module_->eval();
    assert(module_->waddr_out_ready_i);

    out_data.from_packed(module_->waddr_o);
    return (bool)(module_->waddr_out_valid_o);
  }

  /**
   * Sets the ready signal to zero on the DUT output side for the write address.
   */
  void simmem_realmem_waddr_stop(void) { module_->waddr_out_ready_i = 0; }

  /**
   * Sets the ready signal to one on the DUT output side for the write data.
   */
  void simmem_realmem_wdata_request(void) { module_->wdata_out_ready_i = 1; }

  /**
   * Fetches a write data as the real memory controller. Requires the ready
   * signal to be one at the DUT output.
   *
   * @param out_data the output write data request from the DUT
   *
   * @return true iff the data is valid
   */
  bool simmem_realmem_wdata_fetch(WriteData &out_data) {
    module_->eval();
    assert(module_->wdata_out_ready_i);

    out_data.from_packed(module_->wdata_o);
    return (bool)(module_->wdata_out_valid_o);
  }

  /**
   * Sets the ready signal to zero on the DUT output side for the write data.
   */
  void simmem_realmem_wdata_stop(void) { module_->wdata_out_ready_i = 0; }

  /**
   * Sets the ready signal to one on the DUT output side for the read address.
   */
  void simmem_realmem_raddr_request(void) { module_->raddr_out_ready_i = 1; }

  /**
   * Fetches a read address as the real memory controller. Requires the ready
   * signal to be one at the DUT output.
   *
   * @param out_data the output read address request from the DUT
   *
   * @return true iff the data is valid
   */
  bool simmem_realmem_raddr_fetch(ReadAddress &out_data) {
    module_->eval();
    assert(module_->raddr_out_ready_i);

    out_data.from_packed(module_->raddr_o);
    return (bool)(module_->raddr_out_valid_o);
  }

  /**
   * Sets the ready signal to zero on the DUT output side for the read address.
   */
  void simmem_realmem_raddr_stop(void) { module_->raddr_out_ready_i = 0; }

  /**
   * Mask getter.
   */
  uint32_t simmem_get_wrsp_mask(void) { return wrsp_mask_; }

 private:
  vluint32_t tick_count_;
  bool record_trace_;
  std::unique_ptr<Module> module_;
  VerilatedFstC *trace_;

  // Mask that contains ones in the fields common between the write address
  // request and the response.
  uint64_t wrsp_mask_;
};

class RealMemoryController {
 public:
  RealMemoryController(std::vector<uint64_t> ids)
      : spare_wdata_cnt(0), wids_expecting_data() {
    for (size_t i = 0; i < ids.size(); i++) {
      wrsp_out_queues.insert(std::pair<uint64_t, std::queue<WriteResponse>>(
          ids[i], std::queue<WriteResponse>()));
      releasable_wrsp_cnts.insert(std::pair<uint64_t, uint64_t>(ids[i], 0));
      rdata_out_queues.insert(std::pair<uint64_t, std::queue<ReadData>>(
          ids[i], std::queue<ReadData>()));
    }
  }

  /**
   * Adds a new write address to the received queue map. When enough write data
   * are received, it can be released.
   */
  void accept_waddr(WriteAddress waddr) {
    WriteResponse newrsp;
    newrsp.id = waddr.id;
    // Copy the low order rsp of the incoming waddr in the corresponding wrsp
    newrsp.rsp = (waddr.to_packed() >> WriteAddress::id_w) &
                 ~((1L << (PackedW - 1)) >> (PackedW - WriteResponse::rsp_w));

    wrsp_out_queues[waddr.id].push(newrsp);

    if (spare_wdata_cnt >= waddr.burst_len) {
      releasable_wrsp_cnts[waddr.id]++;
      spare_wdata_cnt -= waddr.burst_len;
    } else {
      wids_expecting_data.push(
          std::pair<uint64_t, uint64_t>(waddr.id, waddr.burst_len));
    }
  }

  /**
   * Enables the release of read data.
   */
  void accept_raddr(ReadAddress raddr) {
    for (size_t i = 0; i < raddr.burst_len + 1; i++) {
      // raddr.burst_len+1 because the effective burst length is one entry more
      // than the burst length field.
      ReadData new_rdata;
      new_rdata.id = raddr.id;
      new_rdata.data = raddr.addr + i;
      new_rdata.rsp = 0;  // "OK" response
      new_rdata.last = i == raddr.burst_len - 1;
      rdata_out_queues[raddr.id].push(new_rdata);
    }
  }

  /**
   * Takes new write data into account. The content of the provided write data
   * is not considered.
   */
  void accept_wdata(WriteData wdata) {
    spare_wdata_cnt++;
    if (spare_wdata_cnt >= wids_expecting_data.front().second) {
      releasable_wrsp_cnts[wids_expecting_data.front().first]++;
      spare_wdata_cnt -= wids_expecting_data.front().second;
      wids_expecting_data.pop();
    }
  }

  /**
   * Simulates immediate operation of the real memory controller. The messages
   * are arbitrarily issued by lowest AXI identifier first.
   *
   * @return true iff the real controller holds a valid write response.
   */
  bool has_wrsp_to_input() {
    wrsp_queue_map_t::iterator it;
    for (it = wrsp_out_queues.begin(); it != wrsp_out_queues.end(); it++) {
      if (it->second.size()) {
        return true;
      }
    }
    return false;
  }

  /**
   * Simulates immediate operation of the real memory controller. The read data
   * are arbitrarily issued by lowest AXI identifier first.
   *
   * @return true iff the real controller holds a valid read data.
   */
  bool has_rdata_to_input() {
    rdata_queue_map_t::iterator it;
    for (it = rdata_out_queues.begin(); it != rdata_out_queues.end(); it++) {
      if (it->second.size()) {
        return true;
      }
    }
    return false;
  }

  /**
   * Gets the next write response. Assumes there is one ready. This function is
   * not destructive: the write response is not popped.
   *
   * @return the write response.
   */
  WriteResponse get_next_wrsp() {
    wrsp_queue_map_t::iterator it;
    for (it = wrsp_out_queues.begin(); it != wrsp_out_queues.end(); it++) {
      if (it->second.size()) {
        return it->second.front();
      }
    }
    assert(false);
  }

  /**
   * Gets the next read data. Assumes there is one ready. This function is not
   * destructive: the read data is not popped.
   *
   * @return the read data.
   */
  ReadData get_next_rdata() {
    rdata_queue_map_t::iterator it;
    for (it = rdata_out_queues.begin(); it != rdata_out_queues.end(); it++) {
      if (it->second.size()) {
        return it->second.front();
      }
    }
    assert(false);
  }

  /**
   * Pops the next write response. Assumes there is one ready.
   */
  void pop_next_wrsp() {
    wrsp_queue_map_t::iterator it;
    for (it = wrsp_out_queues.begin(); it != wrsp_out_queues.end(); it++) {
      if (it->second.size()) {
        it->second.pop();
        return;
      }
    }
    assert(false);
  }

  /**
   * Pops the next read data. Assumes there is one ready.
   */
  void pop_next_rdata() {
    rdata_queue_map_t::iterator it;
    for (it = rdata_out_queues.begin(); it != rdata_out_queues.end(); it++) {
      if (it->second.size()) {
        it->second.pop();
        return;
      }
    }
    assert(false);
  }

 private:
  size_t spare_wdata_cnt;  // Counts received wdata
  // Not releasable until enabled using releasable_wrsp_cnts
  wrsp_queue_map_t wrsp_out_queues;
  wids_cnt_t
      releasable_wrsp_cnts;  // Counts how many wrsp can be released to far
  wids_cnt_queue_t wids_expecting_data;
  rdata_queue_map_t rdata_out_queues;
};

/**
 * This function allows the user to manually play with the SimmemTestbench
 * object to interact with the simulated memory controller at a quite low and
 * controlled level.
 *
 * @param tb A pointer the the already contructed SimmemTestbench object.
 */
void manual_testbench(SimmemTestbench *tb) {
  // Example of a manual testbench

  tb->simmem_reset();

  tb->simmem_tick(5);

  WriteAddress waddr_req;
  waddr_req.id = 0;
  waddr_req.addr = 7;
  waddr_req.burst_len = 2;
  waddr_req.burst_size = 8;
  waddr_req.burst_type = 0;
  waddr_req.lock_type = 0;
  waddr_req.mem_type = 0;
  waddr_req.prot = 0;
  waddr_req.qos = 0;

  tb->simmem_requester_waddr_apply(waddr_req);

  tb->simmem_tick();

  waddr_req.id = 1;
  waddr_req.addr = 3;
  waddr_req.burst_len = 4;

  tb->simmem_realmem_waddr_request();
  tb->simmem_tick(4);

  WriteData w_data;
  w_data.from_packed(0UL);

  tb->simmem_requester_wdata_apply(w_data);
  tb->simmem_realmem_wdata_request();

  tb->simmem_requester_waddr_stop();

  tb->simmem_tick(600);
}

/**
 * This function implements a more complete, randomized and automatic testbench.
 *
 * @param tb A pointer the the already contructed SimmemTestbench object.
 * @param num_ids The number of AXI identifiers to involve. Must be at lest 1,
 * and lower than NumIds.
 * @param seed The seed for the randomized test.
 * @param num_cycles The number of simulated clock cycles.
 */
void randomized_testbench(SimmemTestbench *tb, size_t num_ids,
                          unsigned int seed, size_t num_cycles = 400) {
  srand(seed);

  // The AXI identifiers. During the testbench, we will always use the
  // [0,..,num_ids) ids.
  std::vector<uint64_t> ids;
  for (size_t i = 0; i < num_ids; i++) {
    ids.push_back(i);
  }

  // Instantiate a real memory controller emulator.
  RealMemoryController realmem(ids);

  // These structures will store the input and output data, for comparison and
  // delay measurement purposes.
  waddr_time_queue_map_t waddr_in_queues;
  waddr_time_queue_map_t waddr_out_queues;
  raddr_time_queue_map_t raddr_in_queues;
  raddr_time_queue_map_t raddr_out_queues;
  rdata_time_queue_map_t rdata_in_queues;
  rdata_time_queue_map_t rdata_out_queues;
  wrsp_time_queue_map_t wrsp_in_queues;
  wrsp_time_queue_map_t wrsp_out_queues;

  for (size_t i = 0; i < num_ids; i++) {
    waddr_in_queues.insert(
        std::pair<uint64_t, std::queue<std::pair<size_t, WriteAddress>>>(
            ids[i], std::queue<std::pair<size_t, WriteAddress>>()));
    waddr_out_queues.insert(
        std::pair<uint64_t, std::queue<std::pair<size_t, WriteAddress>>>(
            ids[i], std::queue<std::pair<size_t, WriteAddress>>()));
    raddr_in_queues.insert(
        std::pair<uint64_t, std::queue<std::pair<size_t, ReadAddress>>>(
            ids[i], std::queue<std::pair<size_t, ReadAddress>>()));
    raddr_out_queues.insert(
        std::pair<uint64_t, std::queue<std::pair<size_t, ReadAddress>>>(
            ids[i], std::queue<std::pair<size_t, ReadAddress>>()));
    rdata_in_queues.insert(
        std::pair<uint64_t, std::queue<std::pair<size_t, ReadData>>>(
            ids[i], std::queue<std::pair<size_t, ReadData>>()));
    rdata_out_queues.insert(
        std::pair<uint64_t, std::queue<std::pair<size_t, ReadData>>>(
            ids[i], std::queue<std::pair<size_t, ReadData>>()));
    wrsp_in_queues.insert(
        std::pair<uint64_t, std::queue<std::pair<size_t, WriteResponse>>>(
            ids[i], std::queue<std::pair<size_t, WriteResponse>>()));
    wrsp_out_queues.insert(
        std::pair<uint64_t, std::queue<std::pair<size_t, WriteResponse>>>(
            ids[i], std::queue<std::pair<size_t, WriteResponse>>()));
  }

  // Signal whether some input is applied to the simmem.
  bool requester_apply_waddr_input;
  bool requester_apply_wdata_input;
  bool requester_apply_raddr_input;
  bool realmem_apply_rdata_input;
  bool realmem_apply_wrsp_input;

  // Signal whether some output from the simmem is ready to be accepted.
  bool realmem_req_waddr_output;
  bool realmem_req_wdata_output;
  bool realmem_req_raddr_output;
  bool requester_req_rdata_output;
  bool requester_req_wrsp_output;

  bool iteration_announced;  // Variable only used for display purposes.

  ///////////////////////
  // Requester signals //
  ///////////////////////
  // Initialization of the next messages that will be supplied.

  // Input waddr from the requester
  WriteAddress requester_current_waddr;
  requester_current_waddr.from_packed(rand());
  requester_current_waddr.id = ids[rand() % num_ids];
  requester_current_waddr.burst_len = kWBurstLenField;
  requester_current_waddr.burst_type = BURST_INCR;
  requester_current_waddr.burst_size = kWBurstSize;

  // Input raddr from the requester
  ReadAddress requester_current_raddr;
  requester_current_raddr.from_packed(rand());
  requester_current_raddr.id = ids[rand() % num_ids];
  requester_current_raddr.burst_len = kRBurstLenField;
  requester_current_raddr.burst_type = BURST_INCR;
  requester_current_raddr.burst_size = kRBurstSize;

  // Input wdata from the requester
  WriteData requester_current_wdata;
  requester_current_wdata.from_packed(rand());

  // Outputs from the simmem to the requester
  WriteResponse requester_current_wrsp;  // Output wrsp to the requester
  ReadData requester_current_rdata;      // Output rdata to the requester

  /////////////////////
  // Realmem signals //
  /////////////////////

  WriteResponse realmem_current_wrsp;  // Input wrsp from the realmem
  ReadData realmem_current_rdata;      // Input rdata from the realmem

  WriteAddress realmem_current_waddr;  // Output to the realmem
  ReadAddress realmem_current_raddr;   // Output to the realmem
  WriteData realmem_current_wdata;     // Output to the realmem

  //////////////////////
  // Simulation start //
  //////////////////////

  tb->simmem_reset();

  for (size_t curr_itern = 0; curr_itern < num_cycles; curr_itern++) {
    iteration_announced = false;

    ///////////////////////////////////////////////////////////
    // Determine which signals to apply during the iteration //
    ///////////////////////////////////////////////////////////

    ///////////////////////
    // Requester signals //
    ///////////////////////

    // Randomize the boolean signals deciding which interactions will take place
    // in this cycle
    requester_apply_waddr_input = (bool)(rand() & 1);
    requester_apply_raddr_input = (bool)(rand() & 1);
    requester_apply_wdata_input = (bool)(rand() & 1);
    // The requester is supposedly always ready to get data, for more accurate
    // delay calculation
    requester_req_wrsp_output = true;
    requester_req_rdata_output = true;

    /////////////////////
    // Realmem signals //
    /////////////////////

    // The real memory controller is supposed to always output data when
    // possible. This translates the assumption that it operates much faster
    // than normal.
    realmem_apply_wrsp_input = realmem.has_wrsp_to_input();
    realmem_apply_rdata_input = realmem.has_rdata_to_input();
    // The real memory controller is supposedly always ready to get data, for
    // more accurate delay calculation
    realmem_req_waddr_output = true;
    realmem_req_raddr_output = true;
    realmem_req_wdata_output = true;

    ////////////////////////////////////////////////////
    // Signal application and readiness for requester //
    ////////////////////////////////////////////////////

    if (requester_apply_waddr_input) {
      // Apply a given input
      tb->simmem_requester_waddr_apply(requester_current_waddr);
    }
    if (requester_apply_raddr_input) {
      // Apply a given input
      tb->simmem_requester_raddr_apply(requester_current_raddr);
    }
    if (requester_apply_wdata_input) {
      // Apply a given input
      tb->simmem_requester_wdata_apply(requester_current_wdata);
    }

    if (requester_req_wrsp_output) {
      // Express readiness
      tb->simmem_requester_wrsp_request();
    }
    if (requester_req_rdata_output) {
      // Express readiness
      tb->simmem_requester_rdata_request();
    }

    //////////////////////////////////////////////////
    // Signal application and readiness for realmem //
    //////////////////////////////////////////////////

    if (realmem_apply_wrsp_input) {
      // Apply the next available wrsp from the real memory controller
      tb->simmem_realmem_wrsp_apply(realmem.get_next_wrsp());
    }
    if (realmem_apply_rdata_input) {
      // Apply the next available rdata from the real memory controller
      tb->simmem_realmem_rdata_apply(realmem.get_next_rdata());
    }
    if (realmem_req_waddr_output) {
      // Express readiness
      tb->simmem_realmem_waddr_request();
    }
    if (realmem_req_raddr_output) {
      // Express readiness
      tb->simmem_realmem_raddr_request();
    }
    if (realmem_req_wdata_output) {
      // Express readiness
      tb->simmem_realmem_wdata_request();
    }

    ////////////////////////////////////
    // Input handshakes to the simmem //
    ////////////////////////////////////

    // waddr handshake
    if (requester_apply_waddr_input && tb->simmem_requester_waddr_check()) {
      // If the input handshake between the requester and the simmem has been
      // successful for waddr, then accept the input.

      waddr_in_queues[requester_current_waddr.id].push(
          std::pair<size_t, WriteAddress>(curr_itern, requester_current_waddr));
      if (kTransactionVerbose) {
        if (!iteration_announced) {
          iteration_announced = true;
          std::cout << std::endl
                    << "Step " << std::dec << curr_itern << std::endl;
        }
        std::cout << "Requester inputted waddr " << std::hex
                  << requester_current_waddr.to_packed() << std::endl;
      }

      // Renew the input data if the input handshake has been successful
      requester_current_waddr.from_packed(rand());
      requester_current_waddr.id = ids[rand() % num_ids];
      requester_current_waddr.burst_len = kWBurstLenField;
      requester_current_waddr.burst_size = kWBurstSize;
      requester_current_waddr.burst_type = BURST_INCR;
    }
    // raddr handshake
    if (requester_apply_raddr_input && tb->simmem_requester_raddr_check()) {
      // If the input handshake between the requester and the simmem has been
      // successful for raddr, then accept the input.

      raddr_in_queues[requester_current_raddr.id].push(
          std::pair<size_t, ReadAddress>(curr_itern, requester_current_raddr));
      if (kTransactionVerbose) {
        if (!iteration_announced) {
          iteration_announced = true;
          std::cout << std::endl
                    << "Step " << std::dec << curr_itern << std::endl;
        }
        std::cout << "Requester inputted raddr " << std::hex
                  << requester_current_raddr.to_packed() << std::endl;
      }
      // Renew the input data if the input handshake has been successful
      requester_current_raddr.from_packed(rand());
      requester_current_raddr.id = ids[rand() % num_ids];
      requester_current_raddr.burst_len = kRBurstLenField;
      requester_current_raddr.burst_size = kRBurstSize;
      requester_current_raddr.burst_type = BURST_INCR;
    }
    // wdata handshake
    if (requester_apply_wdata_input && tb->simmem_requester_wdata_check()) {
      // If the input handshake between the requester and the simmem has been
      // successful for wdata, then accept the input.
      if (kTransactionVerbose) {
        if (!iteration_announced) {
          iteration_announced = true;
          std::cout << std::endl
                    << "Step " << std::dec << curr_itern << std::endl;
        }
        std::cout << "Requester inputted wdata " << std::hex
                  << requester_current_wdata.to_packed() << std::endl;
      }
      // Renew the input data if the input handshake has been successful
      requester_current_wdata.from_packed(rand());
    }
    // wrsp handshake
    if (realmem_apply_wrsp_input && tb->simmem_realmem_wrsp_check()) {
      // If the input handshake between the realmem and the simmem has been
      // successful, then accept the input.
      realmem_current_wrsp = realmem.get_next_wrsp();
      realmem.pop_next_wrsp();
      wrsp_in_queues[realmem_current_wrsp.id].push(
          std::pair<size_t, WriteResponse>(curr_itern, realmem_current_wrsp));
      if (kTransactionVerbose) {
        if (!iteration_announced) {
          iteration_announced = true;
          std::cout << std::endl
                    << "Step " << std::dec << curr_itern << std::endl;
        }
        std::cout << "Realmem inputted wrsp " << std::hex
                  << realmem_current_wrsp.to_packed() << std::endl;
      }
    }
    // rdata handshake
    if (realmem_apply_rdata_input && tb->simmem_realmem_rdata_check()) {
      // If the input handshake between the realmem and the simmem has been
      // successful, then accept the input.
      realmem_current_rdata = realmem.get_next_rdata();
      realmem.pop_next_rdata();
      rdata_in_queues[realmem_current_rdata.id].push(
          std::pair<size_t, ReadData>(curr_itern, realmem_current_rdata));
      if (kTransactionVerbose) {
        if (!iteration_announced) {
          iteration_announced = true;
          std::cout << std::endl
                    << "Step " << std::dec << curr_itern << std::endl;
        }
        std::cout << "Realmem inputted rdata " << std::hex
                  << realmem_current_rdata.to_packed() << std::endl;
      }
    }

    ///////////////////////////////////////
    // Output handshakes from the simmem //
    ///////////////////////////////////////

    // waddr handshake
    if (realmem_req_waddr_output &&
        tb->simmem_realmem_waddr_fetch(realmem_current_waddr)) {
      // If the output handshake between the realmem and the simmem has been
      // successful, then accept the output.
      waddr_out_queues[ids[realmem_current_waddr.id]].push(
          std::pair<size_t, WriteAddress>(curr_itern, realmem_current_waddr));
      // Let the realmem treat the freshly received waddr
      realmem.accept_waddr(realmem_current_waddr);
      if (kTransactionVerbose) {
        if (!iteration_announced) {
          iteration_announced = true;
          std::cout << std::endl
                    << "Step " << std::dec << curr_itern << std::endl;
        }
        std::cout << "Realmem received waddr " << std::hex
                  << realmem_current_waddr.to_packed() << std::endl;
      }
    }
    // raddr handshake
    if (realmem_req_raddr_output &&
        tb->simmem_realmem_raddr_fetch(realmem_current_raddr)) {
      // If the output handshake between the realmem and the simmem has been
      // successful, then accept the output.
      raddr_out_queues[ids[realmem_current_raddr.id]].push(
          std::pair<size_t, ReadAddress>(curr_itern, realmem_current_raddr));

      // Let the realmem treat the freshly received raddr
      realmem.accept_raddr(realmem_current_raddr);

      if (kTransactionVerbose) {
        if (!iteration_announced) {
          iteration_announced = true;
          std::cout << std::endl
                    << "Step " << std::dec << curr_itern << std::endl;
        }
        std::cout << "Realmem received raddr " << std::hex
                  << realmem_current_raddr.to_packed() << std::endl;
      }
    }
    // wdata handshake
    if (realmem_req_wdata_output &&
        tb->simmem_realmem_wdata_fetch(realmem_current_wdata)) {
      // If the output handshake between the realmem and the simmem has been
      // successful, then accept the output. Let the realmem treat the freshly
      // received wdata.
      realmem.accept_wdata(realmem_current_wdata);
      if (kTransactionVerbose) {
        if (!iteration_announced) {
          iteration_announced = true;
          std::cout << std::endl
                    << "Step " << std::dec << curr_itern << std::endl;
        }
        std::cout << "Realmem received wdata " << std::hex
                  << realmem_current_wdata.to_packed() << std::endl;
      }
    }
    // wrsp handshake
    if (requester_req_wrsp_output &&
        tb->simmem_requester_wrsp_fetch(requester_current_wrsp)) {
      // If the output handshake between the requester and the simmem has been
      // successful, then accept the output.
      wrsp_out_queues[ids[requester_current_wrsp.id]].push(
          std::pair<size_t, WriteResponse>(curr_itern, requester_current_wrsp));

      if (kTransactionVerbose) {
        if (!iteration_announced) {
          iteration_announced = true;
          std::cout << std::endl
                    << "Step " << std::dec << curr_itern << std::endl;
        }
        std::cout << "Requester received wrsp " << std::hex
                  << requester_current_wrsp.to_packed() << std::endl;
      }
    }
    // rdata handshake
    if (requester_req_rdata_output &&
        tb->simmem_requester_rdata_fetch(requester_current_rdata)) {
      // If the output handshake between the requester and the simmem has been
      // successful, then accept the output. One cycle is added to the delay, as
      // the data is available to the requester only after the handshake.
      rdata_out_queues[ids[requester_current_rdata.id]].push(
          std::pair<size_t, ReadData>(curr_itern + 1, requester_current_rdata));

      if (kTransactionVerbose) {
        if (!iteration_announced) {
          iteration_announced = true;
          std::cout << std::endl
                    << "Step " << std::dec << curr_itern << std::endl;
        }
        std::cout << "Requester received rdata " << std::hex
                  << requester_current_rdata.to_packed() << std::endl;
      }
    }

    //////////////////////////////
    // Tick and disable signals //
    //////////////////////////////

    // Reset all signals after tick. They may be set again before the next DUT
    // evaluation during the beginning of the next iteration.

    tb->simmem_tick();

    // Disable requester signals
    if (requester_apply_waddr_input) {
      tb->simmem_requester_waddr_stop();
    }
    if (requester_apply_raddr_input) {
      tb->simmem_requester_raddr_stop();
    }
    if (requester_apply_wdata_input) {
      tb->simmem_requester_wdata_stop();
    }
    if (requester_req_wrsp_output) {
      tb->simmem_requester_wrsp_stop();
    }
    if (requester_req_rdata_output) {
      tb->simmem_requester_rdata_stop();
    }
    // Disable realmem signals
    if (realmem_apply_wrsp_input) {
      tb->simmem_realmem_wrsp_stop();
    }
    if (realmem_apply_rdata_input) {
      tb->simmem_realmem_rdata_stop();
    }
    if (realmem_req_waddr_output) {
      tb->simmem_realmem_waddr_stop();
    }
    if (realmem_req_raddr_output) {
      tb->simmem_realmem_raddr_stop();
    }
    if (realmem_req_wdata_output) {
      tb->simmem_realmem_wdata_stop();
    }
  }

  //////////////////////
  // Delay assessment //
  //////////////////////

  // First, write response delays and ordering are checked.

  // Time of response entrance and output.
  size_t in_time, out_time;
  WriteAddress in_waddr;
  WriteResponse out_wrsp;
  ReadAddress in_raddr;
  ReadData out_rdata;

  // Counts the write response detected mismatches.
  size_t num_wrsp_mismatches = 0;
  std::cout << "\n#### Write responses ####" << std::endl;

  for (size_t curr_id = 0; curr_id < num_ids; curr_id++) {
    std::cout << "\n--- AXI ID " << std::dec << curr_id << " ---" << std::endl;

    while (!waddr_in_queues[curr_id].empty() &&
           !wrsp_out_queues[curr_id].empty()) {
      in_time = waddr_in_queues[curr_id].front().first;
      out_time = wrsp_out_queues[curr_id].front().first;

      in_waddr = waddr_in_queues[curr_id].front().second;
      out_wrsp = wrsp_out_queues[curr_id].front().second;

      waddr_in_queues[curr_id].pop();
      wrsp_out_queues[curr_id].pop();
      // Displays the delay for the sent and received message for each write
      // address request. The payload field helps identifying the message in the
      // waveforms.
      std::cout << "Delay: " << std::dec << out_time - in_time << std::hex
                << " (waddr: " << in_waddr.to_packed()
                << ", wrsp: " << out_wrsp.to_packed() << ")." << std::endl;

      if ((in_waddr.to_packed() & tb->simmem_get_wrsp_mask()) !=
          out_wrsp.to_packed()) {
        num_wrsp_mismatches++;
      }
    }
  }
  // Checks for response ordering.
  std::cout << "\nWrite response mismatches: " << std::dec
            << num_wrsp_mismatches << std::endl;

  // Second, read data delays are checked. Implementation is simplified by
  // assuming a fixed burst length.
  std::cout << "\n\n#### Read data ####" << std::endl;

  // rdata_id_in_burst stores the current position in a read burst, useful to
  // track the boundaries between (fixed-length) read bursts.
  size_t rdata_id_in_burst;

  for (size_t curr_id = 0; curr_id < num_ids; curr_id++) {
    rdata_id_in_burst = 0;

    std::cout << "\n--- AXI ID " << std::dec << curr_id << " ---" << std::endl;

    while (!raddr_in_queues[curr_id].empty() &&
           !rdata_out_queues[curr_id].empty()) {
      short curr_rdata_id = rdata_id_in_burst;

      in_time = raddr_in_queues[curr_id].front().first;
      out_time = rdata_out_queues[curr_id].front().first;

      in_raddr = raddr_in_queues[curr_id].front().second;
      out_rdata = rdata_out_queues[curr_id].front().second;

      if (++rdata_id_in_burst == kRBurstLenField + 1) {
        // kRBurstLenField+1 because the effective burst length is the burst
        // length field plus one.
        rdata_id_in_burst = 0;
        raddr_in_queues[curr_id].pop();
      }
      rdata_out_queues[curr_id].pop();

      // Displays the delay for the sent and received message for each read
      // address request.
      std::cout << "Delay: " << std::dec << out_time - in_time << std::hex
                << " (raddr: " << in_raddr.to_packed()
                << ", rdata id: " << curr_rdata_id << ")." << std::endl;
    }
  }
}

int main(int argc, char **argv, char **env) {
  Verilated::commandArgs(argc, argv);
  Verilated::traceEverOn(true);

  SimmemTestbench *tb = new SimmemTestbench(true, "top.fst");

  if (kTestStrategy == MANUAL_TEST) {
    manual_testbench(tb);
  } else if (kTestStrategy == RANDOMIZED_TEST) {
    randomized_testbench(tb, NUM_IDENTIFIERS, SEED, NUM_RANDOM_TEST_STEPS);
  }

  delete tb;

  std::cout << "Testbench complete!" << std::endl;

  exit(0);
}
