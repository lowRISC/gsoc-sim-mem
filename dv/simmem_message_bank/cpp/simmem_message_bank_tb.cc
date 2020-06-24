// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "simmem_message_bank_tb.h"

#include "Vsimmem_message_bank.h"
#include "verilated.h"

int main(int argc, char **argv, char **env)
{
	Verilated::commandArgs(argc, argv);
  Verilated::traceEverOn(true);

	Testbench<Vsimmem_message_bank>* tb = new Testbench<Vsimmem_message_bank>(0, true, "message_bank.fst");

	while (!tb->done())
	{
		printf("Running iteration %d.\n", counter);
		
    tb->tick();
	}

	tb->close_trace();

	printf("Complete!\n");

	delete tb;
	exit(0);
}
