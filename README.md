# VERGrab
Grab contents of VER packet from a TI device using a TI-83 Plus and TI Link Protocol


## Usage
Set Ans to a real integer between 0 and 255, this will be used as the Machine ID sent by the calculator to the other device. When the program is run, it will return the Machine ID the other device used, or a negative integer error number. The VER packet received from the other device is stored in L1, and L1 is not updated if the packet is not successfully received.  

This probably won't corrupt your VAT anymore. 

## Assembling
Use Brass to assemble VERGrab. "ti83plus.inc" can be found online readily, but make sure it has `_SendAByteIO`. 
