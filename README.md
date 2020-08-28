# gsoc-sim-mem

A simulated memory controller for use in FPGA designs that want to model real system performance.

This project has been developed in the Google Summer of Code 2020 for [LowRisc CIC](https://www.lowrisc.org/), supervised by [Greg Chadwick](https://github.com/GregAC), [Pirmin Vogel](https://github.com/vogelpi) and [Alex Bradbury](https://github.com/asb).

![Overview](https://i.imgur.com/BwElPLe.png)

## How to contribute

Have a look at [CONTRIBUTING](./CONTRIBUTING.md) for guidelines on how to contribute code to this repository.

## Licensing

Unless otherwise noted, everything in this repository is covered by the Apache License, Version 2.0 (see [LICENSE](./LICENSE) for full text).

## How to use

The simulated memory controller has two AXI ports (one slave and one master) dedicated to its integration between the requester (typically the CPU core) and the real memory controller.

Two testbenches are integrated in the repository:

- A testbench for the whole simulated memory controller, which is discussed here.
- A testbench for the response banks, as it is a relatively complex design block.

See the [documentation](https://github.com/lowrisc/gsoc-sim-mem/documentation.md) for more information about the testbenches.

The required tools are [Verilator](https://www.veripool.org/wiki/verilator) and [FuseSoC](https://github.com/olofk/fusesoc).
Additionally, [GTKWave](http://gtkwave.sourceforge.net/) is used for analyzing waveforms.

### Initial setup

To run the complete testbench,

**Step 1:** Clone the repository and move to the repository root:

```bash
git clone https://github.com/lowRISC/gsoc-sim-mem.git simmem
cd simmem
```

**Step 2:** Initialize FuseSoC and add the simmem core:

```bash
fusesoc init
fusesoc library add simmem .
```

### Testbench execution

The main testbench checks the functionality and performance of the simulated memory controller by:

- Checking the write response ordering according to the corresponding requests.
- Displaying the actual delays.

**Step 1:** To compile the design and testbench, execute:

```bash
fusesoc run --target=sim_simmem_top simmem
```

**Step 2:** To generate the waveforms, execute:

```bash
./build/simmem_0.1/sim_simmem_top-verilator/Vsimmem_top --trace
```

This runs the testbench again, but this time it generates the `top.fst` wave file.
The testbench standard output is described in the [documentation](https://github.com/lowrisc/gsoc-sim-mem/documentation.md).

**Step 3:** To view the waveforms, execute:

```bash
gtkwave top.fst
```

This opens the waveform GUI for a deeper analysis.
