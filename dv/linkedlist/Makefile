SIM=verilator # TODO Remove

VERILOG_SOURCES = $(PWD)/../../rtl/simmem_linkedlist_bank.sv $(PWD)/../../rtl/dependencies/prim_ram_1p.sv

TOPLEVEL=simmem_linkedlist_bank

COCOTB_SHARE_DIR = ~/miniconda3/lib/python3.7/site-packages/cocotb/share

MODULE=test_linkedlist

COCOTB_HDL_TIMEPRECISION = 1us # Set precision to 10^-6s
EXTRA_ARGS += --trace --trace-structs

include $(shell cocotb-config --makefiles)/Makefile.sim
