library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
-- This module is the top module for the displaying, we isolate this module so that we can isolate the VRAM block
-- therefore this module is independant from the rest of the project
-- if there is any changes in displaying, it should be processed before and then sent to the VRAM, this module only generates clocks for VGA screen and decode RGB signal
-- for screen displaying
entity Graphic_module is
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
        -- Inputs
        -- we take 2 clocks, the fpga base clock
        CLOCK_50 : in std_logic; --we take the FPGA clock
        rst      : in std_logic; -- active low
        -- Interface with VRAM from other modules (write clock is 50MHz)
        wr_clock : in std_logic; 
        wr_data    : in  std_logic_vector(7 downto 0); 
        wr_address: IN STD_LOGIC_VECTOR (18 DOWNTO 0);
        wren	 : IN STD_LOGIC  := '0';
        -- Outputs 
        VGA_R    : out std_logic_vector(7 downto 0);
        VGA_G    : out std_logic_vector(7 downto 0);
        VGA_B    : out std_logic_vector(7 downto 0);
        VGA_BLANK: out std_logic;
        VGA_CLK  : out std_logic; -- from the user manuel
        H_SYNC   : out std_logic;
        V_SYNC   : out std_logic;
		MODE     : in std_logic_vector(1 downto 0);
        CROSSHAIR_MODE : in std_logic
    );

end Graphic_module;

architecture BEH_Graphic_module of Graphic_module is 
    -- Components declaration of the GPU module --
    component CLOCK_DIV_HALF is
        -- means that this is a 25MHz clock 
        port(
		    inclk0		: IN STD_LOGIC  := '0';
		    c0		    : OUT STD_LOGIC
        );
        end component;

    component VRAM is
        port(
            data		: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
            rdaddress	: IN STD_LOGIC_VECTOR (18 DOWNTO 0);
            rdclock		: IN STD_LOGIC ;
            wraddress	: IN STD_LOGIC_VECTOR (18 DOWNTO 0);
            wrclock		: IN STD_LOGIC  := '1';
            wren		: IN STD_LOGIC  := '0';
            q			: OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
	    );
        end component;
    
    component VGA_display is
        port(
            CLOCK_25 : in std_logic;
            cur_X    : in integer range 0 to H_PIXELS;
            cur_Y    : in integer range 0 to V_PIXELS;
            
            -- VGA signals 
            VGA_R    : out std_logic_vector(7 downto 0);
            VGA_G    : out std_logic_vector(7 downto 0);
            VGA_B    : out std_logic_vector(7 downto 0);
            VGA_BLANK: out std_logic;

            rdaddress: out std_logic_vector(18 downto 0); --Read address from the VGA RAM
            rdclock  : out std_logic;
            q        : in std_logic_vector(7 downto 0); --RGB data of the pixel on VGA RAM
			MODE     : in std_logic_vector(1 downto 0);
            CROSSHAIR_MODE : in std_logic
        );
        end component;
    
    component VGA_sync is
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
        end component;

    --- Internal signals ---
    signal clock_25 : std_logic;
	 signal rd_clock_internal : std_logic;
    signal cur_X_int : integer range 0 to H_PIXELS;
    signal cur_Y_int : integer range 0 to V_PIXELS;

    signal vram_rdaddress : std_logic_vector(18 downto 0);
    signal vram_q         : std_logic_vector(7 downto 0);
    
    begin 
        -- Set immediately the VGA_CLOCK which is the 25MHz clock
        --------------------------------------------------------------------------
        ---- PLL part : to generate the 25MHz clock ------------------------------
        --------------------------------------------------------------------------
        PLL_inst : CLOCK_DIV_HALF
            port map(
                inclk0 => CLOCK_50,
                c0     => clock_25
            );
        VGA_CLK <= clock_25;
        --------------------------------------------------------------------------
        --VRAM_part : 
        -- external interface with other components with wrdata, wrclock (50MHz clock), and wraddress 
        -- internal interface : to be read from vga_display (read clock is 25MHz clock)
        --------------------------------------------------------------------------
		  
        VRAM_inst : VRAM
            port map(
                -- External interface
                data => wr_data,
                wraddress => wr_address,
                wrclock => wr_clock,
                wren => wren,
                -- Internal interface
                rdaddress => vram_rdaddress,
                q => vram_q,
                rdclock => rd_clock_internal
            );

        --------------------------------------------------------------------------
        -- VGA_sync : 
        -- generates H_SYNC and V_SYNC signals
        -- send cursor positions to displayer
        --------------------------------------------------------------------------
        VGA_sync_inst : VGA_sync
            generic map (
                WIDTH    => WIDTH,
                HEIGHT   => HEIGHT,
                H_FP     => H_FP,
                H_BP     => H_BP,
                V_FP     => V_FP,
                V_BP     => V_BP,
                H_ST     => H_ST,
                V_ST     => V_ST,
                H_PIXELS => H_PIXELS,
                V_PIXELS => V_PIXELS
            )
            port map(
                CLOCK_25 => clock_25,
                rst      => rst,
            
                H_SYNC   => H_SYNC,
                V_SYNC   => V_SYNC,

                -- X and Y coordinates to know where we are
                cur_X    => cur_X_int,
                cur_Y    => cur_Y_int
            );
        --------------------------------------------------------------------------
        -- VGA_display : 
        -- reads data from VRAM
        -- sends RGB signal to monitor
        --------------------------------------------------------------------------
        DISPLAY_inst : VGA_display
            port map (
                CLOCK_25  => clock_25,
                cur_X     => cur_X_int,
                cur_Y     => cur_Y_int,
                VGA_R     => VGA_R,
                VGA_G     => VGA_G,
                VGA_B     => VGA_B,
                VGA_BLANK => VGA_BLANK,
                rdaddress => vram_rdaddress,
                rdclock   => rd_clock_internal,
                q         => vram_q,
				MODE => MODE,
                CROSSHAIR_MODE => CROSSHAIR_MODE
            );
end BEH_Graphic_module;