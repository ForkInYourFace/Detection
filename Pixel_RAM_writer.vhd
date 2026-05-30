library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
-- TO STOCK ALL THE CAMERA 1-RGB-COMPONENT (R or G or B) into the PIXEL_RAM to be demosaic
-- IMPORTANT NOTE : THIS IS THE CAMERA PIXEL, WHICH IS 1 RGB COMPONENT, NOT THE COLOURED COMPONENT PIXEL
-- Calculations : 640x480 --> 1280x960 size mosaiced matrix, where 4 camera-pixels encode 1 eye-seeing pixel
-- From the documentation 
-------------------------------------------------------- 8xblack rows
--                                                    --
--                                                    --
--                                                      
--
--              DISPLAYING AREA                      ... 26 x black columms
-- 1 x black col |
--
--                                                    --
--                                                    --
-------------------------------------------------------- 7xblack rows
-- PIXEL_RAM is rather a 4-lines circular buffer
entity Pixel_RAM_writer is
    port(
        -- Inputs : to track the camera-pixel
        PIXCLK          : in std_logic;
        cur_X           : in integer range 0 to 2047;
        cur_Y           : in integer range 0 to 2047;
        isInValidRegion : in boolean;
        -- Direct input from the camera : 10 bits wide information on 1-RGB-component (R or G or B, only 1)
        DATA            : in std_logic_vector(9 downto 0);
        
        -- Interface with the Pixel RAM
        DATA_OUT        : out std_logic_vector(7 downto 0); -- we will truncate the 10 bits RGB info to 8 bits RGB info
        wraddress       : out std_logic_vector(12 downto 0);
        wrclock         : out std_logic := '1';
        wren            : out std_logic := '0'
    );
    end Pixel_RAM_writer;

architecture BEH_Pixel_RAM_writer of Pixel_RAM_writer is 
    --- Declare internal signals
    signal isInDisplayingRegion_X : boolean := false;
    signal isInDisplayingRegion_Y : boolean := false;

begin 
    process(PIXCLK)
    begin
        if rising_edge(PIXCLK) then
            -- transfer directly the camera data to the RAM
            DATA_OUT <= DATA(9 downto 2); -- 10 bits -> 8 bits data (we take only the 8MSBs)
            if isInDisplayingRegion_Y then
                -- if the reading pixel is not in the displaying region (the first 8 rows), we will 
                -- continue to write them in the first line, then when comes to displaying region
                -- we will write onto that and continue upto 4 lines
                wraddress(12 downto 11) <= std_logic_vector(to_unsigned(cur_Y - 8, 11)(1 downto 0));
            else 
                wraddress(12 downto 11) <= "00";
            end if;

            if isInDisplayingRegion_X then
                wraddress(10 downto 0) <= std_logic_vector(to_unsigned(cur_X - 26, 11)); 
            else 
                wraddress(10 downto 0) <= "11111111111";
            end if;

            if isInDisplayingRegion_X and isInDisplayingRegion_Y and isInValidRegion then
                wren <= '1';
            else 
                wren <= '0';
            end if;
        end if;
    end process;

    isInDisplayingRegion_X <= (cur_X >= 26 and cur_X < 1306); -- 640x2 + 26
    isInDisplayingRegion_Y <= (cur_Y >= 8 and cur_Y < 968); -- 480x2 + 8
    wrclock <= PIXCLK;
end BEH_Pixel_RAM_writer;



