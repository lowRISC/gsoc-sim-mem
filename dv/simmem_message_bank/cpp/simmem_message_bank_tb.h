// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef SIMMEM_MEMORY_BANK_MODEL_H
#define SIMMEM_MEMORY_BANK_MODEL_H

#include "verilated_fst_c.h"

#define RESET_LENGTH 5
#define TRACE_LEVEL 8

template<class Module> class Testbench {
	
	long m_tick_count;
  bool m_record_trace;
  long m_max_clock_cycles;
	Module *m_module;
  VerilatedFstC* m_trace;

  // @param max_clock_cycles set to 0 to disable interruption after a given number of clock cycles
  // @param record_trace set to false to skip trace recording
	Testbench(long max_clock_cycles=0, bool record_trace = true, const string& trace_filename) {
		m_tick_count = 0l;
    m_record_trace = record_trace;
		m_module = new Module;

    if (record_trace) {
      m_trace = new VerilatedFstC;
      m_module->trace(m_trace, TRACE_LEVEL);
      m_trace->open(trace_filename.c_str());
    }
  }

	virtual ~Testbench(void) {
		delete m_module;
	}

	virtual void reset(void) {
		m_module->rst_i = 1;
    for (int i = 0; i < RESET_LENGTH; i++)
		  this->tick();
		m_module->rst_i = 0;
	}

  virtual void close_trace(void) {
		m_trace->close();
	}

	virtual void tick(void) {
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

	virtual bool is_done(void) {
		return (Verilated::gotFinish());
	}
}

#endif