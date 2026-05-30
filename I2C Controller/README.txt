This module is written by BUI Duc
------------------------------------------------------------------------------------------------------
The I2C master level - is the bit-by-bit level of the I2C controller, 
it is inspired by the state machine proposed by Aslak's 
A big thanks to him (https://www.aslak.net/index.php/2021/05/05/an-i2c-controller-implemented-in-vhdl/)
I modified just the state machine to adapt it to the READ-ONLY mode 
-------------------------------------------------------------------------------------------------------
The camera_init_manager is to manage the byte-by-byte chain 
It has a ROM and a dynamic register to dynamically modify the gains value on the camera
