// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include <verilated_fst_c.h>

#include "Vsimmem_write_resp_bank.h"
#include "verilated.h"

#define RESET_LENGTH 5
#define TRACE_LEVEL 8

#define ID_WIDTH 4

typedef Vsimmem_write_resp_bank Module;

struct WriteRespBankTestbench {
	
	vluint32_t m_tick_count;
  vluint32_t m_max_clock_cycles;
  bool m_record_trace;
	Module *m_module;
  VerilatedFstC* m_trace;

  // @param max_clock_cycles set to 0 to disable interruption after a given number of clock cycles
  // @param record_trace set to false to skip trace recording
	WriteRespBankTestbench(vluint32_t max_clock_cycles = 0, bool record_trace = true, const std::string& trace_filename = "sim.fst") {
		m_tick_count = 0l;
    m_max_clock_cycles = max_clock_cycles;
    m_record_trace = record_trace;
		m_module = new Module;

    if (record_trace) {
      m_trace = new VerilatedFstC;
      m_module->trace(m_trace, TRACE_LEVEL);
      m_trace->open(trace_filename.c_str());
    }
  }

	void destruct(void) {
		delete m_module;
	}

	void reset(void) {
		m_module->rst_ni = 0;
    for (int i = 0; i < RESET_LENGTH; i++)
		  this->tick();
		m_module->rst_ni = 1;
	}

  void close_trace(void) {
		m_trace->close();
	}

	void tick(void) {

    printf("Running iteration %d.\n", m_tick_count);

		m_tick_count++;

		m_module->clk_i = 0;
		m_module->eval();

    if(m_record_trace)
      m_trace->dump(5*m_tick_count-1);

		m_module->clk_i = 1;
		m_module->eval();

    if(m_record_trace)
      m_trace->dump(5*m_tick_count);

		m_module->clk_i = 0;
		m_module->eval();

    if(m_record_trace) {
      m_trace->dump(5*m_tick_count+2);
      m_trace->flush();
    }
	}

	bool is_done(void) {
    printf("cnt: %u, max: %u\n", m_tick_count, m_max_clock_cycles);
		return (Verilated::gotFinish() || (m_max_clock_cycles && (m_tick_count >= m_max_clock_cycles)));
	}

  void reserve(int axi_id) {
    m_module->reservation_request_ready_i = 1;
    m_module->reservation_request_id_i = axi_id;
  }

  void apply_input_data(int data_i) {
    m_module->data_i = data_i;
    m_module->in_valid_i = 1;
  }
};




int main(int argc, char **argv, char **env)
{
	Verilated::commandArgs(argc, argv);
  Verilated::traceEverOn(true);

	WriteRespBankTestbench* tb = new WriteRespBankTestbench(100, true, "write_resp_bank.fst");

  tb->reset();
  tb->reserve(4);
  tb->apply_input_data(4);

	while (!tb->is_done())
	{		
    tb->tick();
	}

	tb->close_trace();

	printf("Complete!\n");

	delete tb;
	exit(0);
}
