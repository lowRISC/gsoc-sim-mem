# Vivado integration of the simulated memory controller

This document briefly shows how to integrate the simulated memory controller in a Xilinx Vivado design, using a Microblaze core as a CPU core example on a Digilent Nexys Video board.

## Project creation

Create a new RTL project and include the RTL files.

![](https://i.imgur.com/t6Kxp2i.png)

No constraints are required in this step.

![](https://i.imgur.com/RfOJVkH.png)

Choose your board.

![](https://i.imgur.com/89ldrKz.png)

## IP packaging

Create a new block design, called _simmem_module_.

![](https://i.imgur.com/toL8jK1.png)

Add the Verilog wrapper to the empty block design.

![](https://i.imgur.com/gjbnPWM.png)

Make all the pins external.

![](https://i.imgur.com/QZVPwjJ.png)

Package the new IP through _tools -> Create and package new IP_.

![](https://i.imgur.com/PJRZZoz.png)

![](https://i.imgur.com/18wVXCn.png)

## Main block design

### Microblaze placement

Create a new block design _simmem_ublaze_.

Import the clock wizard to output a clock frequency of 200MHz and take an active low signal.

![](https://i.imgur.com/grdKWB0.png)

![](https://i.imgur.com/a1ttVvO.png)

Import a DDR3 MIG and connect its clock input to the clock wizard's output. Then, run the connection automation.

![](https://i.imgur.com/cxbJql3.png)

Create a Microblaze IP and run block automation.

![](https://i.imgur.com/SACtEFS.png)
![](https://i.imgur.com/98brV9N.png)
![](https://i.imgur.com/I08IdeL.png)
![](https://i.imgur.com/FS8pFKA.png)
![](https://i.imgur.com/xWRtzOX.png)

Add an UART module and connect its interrupt output to the interrupt controller input.
Then, run connection automation, regenerate the layout and validate the design.

![](https://i.imgur.com/DyIFkMs.png)

### Simmem insertion

Delete the AXI link between the AXI interconnect and the DDR3 MIG.

![](https://i.imgur.com/crJilAG.png)

Insert a simulated memory controller IP. Connect the clock and reset inputs to the corresponding inputs of the AXI interconnect.

![](https://i.imgur.com/nDEmgOf.png)

Then, regenerate the layout and validate the design.

### Address mapping

Replace the mapping of the MIG by the simulated memory controller. Additionally, map the MIG in the memory controller's addresses.

![](https://i.imgur.com/oWzVkja.png)

### Integrated Logic Analyzer insertion (optional)

Insert two new ILA instances as shown in the figures below.
These will examine the AXI traffic around the simulated memory controller.

![](https://i.imgur.com/ssnY8ne.png)
![](https://i.imgur.com/4E2EGPD.png)

## Bitstream generation

### Top module selection

Create a HDL wrapper around _simmem_ublaze_.

![](https://i.imgur.com/kZ8nUSm.png)
![](https://i.imgur.com/fzQOFPj.png)

Then, set this wrapper as top.
The result should be as in the figure below.

![](https://i.imgur.com/99qpc1L.png)


### Bitstream

Now generate the bitstream.

First, run the synthesis.

![](https://i.imgur.com/oWzVkja.png)


## Execution

### Hardware exportation

Open the target and program the device.

![](https://i.imgur.com/9Bv8uLT.png)

Export the hardware under _File -> Export -> Export Hardware..._.

![](https://i.imgur.com/z3zirr1.png)

Open the SDK under _File -> Launch SDK_.

![](https://i.imgur.com/8oDC4tE.png)

### SDK: Memory testing application

#### Application setup

Verify the displayed address mappings in the SDK window.

![](https://i.imgur.com/B9vc6RG.png)

Create a new project under _File -> New -> Application Project_.

![](https://i.imgur.com/PiOO30P.png)
![](https://i.imgur.com/ny6JHU6.png)

Configure the memory test as in the figure below.

![](https://i.imgur.com/X1W9j09.png)
![](https://i.imgur.com/nnrD2Je.png)

#### UART terminal setup

Open the _SDK terminal_ tab.

![](https://i.imgur.com/WHuflL7.png)

Click the green + button. Select a baud rate of 9600 and click OK.

![](https://i.imgur.com/4pvyJkh.png)

#### Application run

Run the application under _Run -> Run configurations..._

![](https://i.imgur.com/0ofurRw.png)

Finally, run the application.
