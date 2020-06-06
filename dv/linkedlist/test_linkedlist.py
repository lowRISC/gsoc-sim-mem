import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge

@cocotb.test()
async def test_linkedlist(dut):

    clock = Clock(dut.clk, 10, units="us")
    cocotb.fork(clock.start())

    for i in range(1000):
        await FallingEdge(dut.clk)
        print(i)
        # assert dut.q == val, "output q was incorrect on the {}th cycle".format(i)
