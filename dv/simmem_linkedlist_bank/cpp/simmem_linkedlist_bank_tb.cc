// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "Vsimmem_linkedlist_bank_tb.h"
#include "verilated_toplevel.h"
#include "verilator_sim_ctrl.h"

#include <signal.h>
#include <functional>
#include <iostream>

#include "sim_ctrl_extension.h"

class SimmemLinkedlistBankTB : public SimCtrlExtension {
  using SimCtrlExtension::SimCtrlExtension;

 public:
  SimmemLinkedlistBankTB(simmem_linkedlist_bank_tb *top);

  void OnClock(unsigned long sim_time);

 private:
  simmem_linkedlist_bank_tb *top_;
};

// Constructor:
// - Set up top_ ptr
SimmemLinkedlistBankTB::SimmemLinkedlistBankTB(simmem_linkedlist_bank_tb *top)
    : SimCtrlExtension{}, top_(top) {}

// Function called once every clock cycle from SimCtrl
void SimmemLinkedlistBankTB::OnClock(unsigned long sim_time) {
  if (top_->test_done_o) {
    VerilatorSimCtrl::GetInstance().RequestStop(top_->test_passed_o);
  }
}

int main(int argc, char **argv) {
  int ret_code;

  // Init verilog instance
  simmem_linkedlist_bank_tb top;

  // Init sim
  VerilatorSimCtrl &simctrl = VerilatorSimCtrl::GetInstance();
  simctrl.SetTop(&top, &top.clk_i, &top.rst_ni,
                 VerilatorSimCtrlFlags::ResetPolarityNegative);

  // Create and register VerilatorSimCtrl extension
  SimmemLinkedlistBankTB simmemLinkedlistBankTB(&top);
  simctrl.RegisterExtension(&simmemLinkedlistBankTB);

  std::cout << "Simulation of linkedlist bank for the simulated memory controller" << std::endl
            << "=================================================================" << std::endl
            << std::endl;

  // Get pass / fail from Verilator
  ret_code = simctrl.Exec(argc, argv);

  return ret_code;
}
