library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- this module is to set the HSYNC and VSYNC signals for the VGA screen
-----------------------------------------------------------------------
-- SPECS --
-- Res : 640 x 480 
-- Horizontal : 800 pixels in total, where 640 active, 16 fp, 96 sync width and 48 bp
-- Vertical : 525 pixels in total, where 480 active, 10 fp, 2 sync width and 33 bp
-- timing : active -> front porch -> sync width (to put the faisceau back to the top of bp) -> bp and again

-- refresh rate of screen : 60hz --> 1/(60 frames x 800 x 525) = 39,7 ns/pixel 
-- need a clock of 1/39,7 = 25,2MHz

entity VGA_sync is
    generic(
        -- Screen res
        WIDTH    : integer := 640;
        HEIGHT   : integer := 480;
        -- Porches
        H_FP     : integer := 16;
        H_BP     : integer := 48;
        V_FP     : integer := 10;
        V_BP     : integer := 33;
        -- Sync times
        H_ST     : integer := 96;
        V_ST     : integer := 2;
        -- Total pixels
        H_PIXELS : integer := 800;
        V_PIXELS : integer := 525
    );
    port(
        CLOCK_25 : in std_logic;
        rst      : in std_logic;
        
        H_SYNC   : out std_logic;
        V_SYNC   : out std_logic;

        -- X and Y coordinates to know where we are
        cur_X    : out integer range 0 to H_PIXELS;
        cur_Y    : out integer range 0 to V_PIXELS
    );
    end VGA_sync;

architecture BEH_VGA_sync of VGA_sync is 
    -- Declarative part
    -- To make internal signals
    signal cur_X_int_sig : integer range 0 to H_PIXELS;
    signal cur_Y_int_sig : integer range 0 to V_PIXELS;

begin
    process(CLOCK_25, rst)
    begin
        if rst = '0' then
            cur_X_int_sig <= 0;
            cur_Y_int_sig <= 0;
        elsif rising_edge(CLOCK_25) then
            if cur_X_int_sig = H_PIXELS - 1 then -- at the end of the line we return to 0
                cur_X_int_sig <= 0;
                if cur_Y_int_sig = V_PIXELS - 1 then
                    cur_Y_int_sig <= 0;
                else 
                    cur_Y_int_sig <= cur_Y_int_sig + 1;
                end if;
            else 
                cur_X_int_sig <= cur_X_int_sig + 1;
            end if;
        end if;
    end process;
        -- Connect to outputs
        cur_X <= cur_X_int_sig;
        cur_Y <= cur_Y_int_sig;

        H_SYNC <= '0' when (cur_X_int_sig >= (H_PIXELS - H_BP - H_ST) and cur_X_int_sig < (H_PIXELS - H_BP)) else '1';
        V_SYNC <= '0' when (cur_Y_int_sig >= (V_PIXELS - V_BP - V_ST) and cur_Y_int_sig < (V_PIXELS - V_BP)) else '1';

end BEH_VGA_sync;
