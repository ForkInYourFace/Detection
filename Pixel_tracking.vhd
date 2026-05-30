library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
-- This module has a direct interface with the Camera to take the PIXCLK, FRAME_VALID, LINE_VALID, to track the position of the reading pixel
-- IMPORTANT NOTE : THIS IS THE CAMERA PIXEL, WHICH IS 1 RGB COMPONENT, NOT THE COLOURED COMPONENT PIXEL
entity Pixel_tracking is 
    port(
        -- Direct interface which the CMOS camera
        -- Receive :
        PIXCLK          : in std_logic; -- continuous clock from the camera to synchronize the read out data
        FRAME_VALID     : in std_logic; -- active-high signal, to indicate that a valide FRAME is being transmitted
        LINE_VALID      : in std_logic; -- active-high signal, to indicate that a valide row (line) is being transmitted

        -- camera-pixel tracking 
        cur_X           : out integer range 0 to 2047;
        cur_Y           : out integer range 0 to 2047;
        isInValidRegion   : out std_logic
    );
    end Pixel_tracking;
architecture BEH_Pixel_tracking of Pixel_tracking is 
    --- Declarative parts
    signal cur_X_int   : integer range 0 to 2047 := 0;
    signal cur_Y_int   : integer range 0 to 2047 := 0;
    signal isLastLineValid : boolean := false;
begin
    process(PIXCLK)
    begin
        -- page 9 in the documentation of the camera, it is better if we take the data at the falling edge of the PIXCLK
        if rising_edge(PIXCLK) then 
            -- in the same frame
            if FRAME_VALID = '1' then
                if LINE_VALID = '1' then
                    -- at each falling edge, if line_valid is still active, we take a pixel in the same line so update the X coor
                    cur_X_int <= cur_X_int + 1;
                    isLastLineValid <= true;
                else -- if line_valid go low
                    cur_X_int <= 0;
                    if isLastLineValid then
                        isLastLineValid <= false; -- line read finished
                        -- update Y coord
                        cur_Y_int <= cur_Y_int + 1;
                    end if;
                end if;
            else 
                -- next frame, reset X and Y
                cur_X_int <= 0;
                cur_Y_int <= 0;
            end if;
            isInValidRegion <= FRAME_VALID and LINE_VALID; -- a pixel in the displaying region only when it is in valid frames and lines
        end if;
    end process;
    cur_X <= cur_X_int;
    cur_Y <= cur_Y_int;
end BEH_Pixel_tracking;

