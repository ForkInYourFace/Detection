library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;


-- Camera_flux_decoder
-- ----------------------------------------------------------------------------
-- Top-level wrapper for the camera capture and demosaic chain.
-- Contains:
--   Pixel_tracking    : turns FRAME_VALID/LINE_VALID into (X, Y) coords
--   Pixel_RAM_writer  : writes raw camera pixels into the 4-line buffer
--   Pixel_RAM         : 4-line circular buffer (dual-clock BRAM)
--   Demosaic_and_Filter : reads the buffer, demosaics, classifies skin,
--                         and drives one of three output paths based on MODE
-- 00 RAW_to_VGA, 01 MASK_to_VGA, 10 MASK_to_SRAM
--
-- Outputs to the rest of the design:
--   VRAM write port (RGB, wraddress, wrclock, wren)
--   SRAM FIFO write port (data_fifo, wren_fifo)
--   start_seg pulse (one per frame, for the segmentation core)

entity Camera_flux_decoder is
    Port (
        -- System
        CLOCK_50    : in  std_logic;
 
        -- Direct interface with the CMOS camera
        PIXCLK      : in  std_logic;
        FRAME_VALID : in  std_logic;
        LINE_VALID  : in  std_logic;
        DATA        : in  std_logic_vector(9 downto 0);   -- 10-bit Bayer
 
        -- Mode select (from switches on the top level)
        MODE        : in  std_logic_vector(1 downto 0);
 
        -- VRAM write port (to GPU_module / VRAM)
        RGB         : out std_logic_vector(7 downto 0);
        wraddress   : out std_logic_vector(18 downto 0);
        wrclock     : out std_logic;
        wren        : out std_logic;
 
        -- SRAM FIFO write port (to segmentation pipeline)
        wren_fifo   : out std_logic;
        data_fifo   : out std_logic_vector(30 downto 0);
        start_seg   : out std_logic
    );
end Camera_flux_decoder;
 
 
architecture BEH_Camera_flux_decoder of Camera_flux_decoder is
 
    -- ----------------------------------------------------------------------
    -- Component declarations
    -- ----------------------------------------------------------------------
    component Pixel_tracking is
        port(
            PIXCLK          : in  std_logic;
            FRAME_VALID     : in  std_logic;
            LINE_VALID      : in  std_logic;
            cur_X           : out integer range 0 to 2047;
            cur_Y           : out integer range 0 to 2047;
            isInValidRegion : out std_logic
        );
    end component;
 
    component Pixel_RAM_writer is
        port(
            PIXCLK          : in  std_logic;
            cur_X           : in  integer range 0 to 2047;
            cur_Y           : in  integer range 0 to 2047;
            isInValidRegion : in  std_logic;
            DATA            : in  std_logic_vector(9 downto 0);
            DATA_OUT        : out std_logic_vector(7 downto 0);
            wraddress       : out std_logic_vector(12 downto 0);
            wrclock         : out std_logic;
            wren            : out std_logic
        );
    end component;
 
    component Pixel_RAM is
        port(
            data      : in  std_logic_vector(7 downto 0);
            rdaddress : in  std_logic_vector(12 downto 0);
            rdclock   : in  std_logic;
            wraddress : in  std_logic_vector(12 downto 0);
            wrclock   : in  std_logic := '1';
            wren      : in  std_logic := '0';
            q         : out std_logic_vector(7 downto 0)
        );
    end component;
 
 component raw_to_rgb_converter is
	Port (CLOCK_50 : in std_logic;
			PIXCLK : in std_logic;
			FRAME_VALID : in std_logic;
			Y : in integer range 0 to 2047;
			
			rdaddress : out STD_LOGIC_VECTOR (12 DOWNTO 0);
			rdclock : out STD_LOGIC ;
			q : in STD_LOGIC_VECTOR (7 DOWNTO 0);

			--VGA
			RGB: out STD_LOGIC_VECTOR (7 downto 0) := "00000000"; --2 bit R, 4 bit G, 2 bit B
			wraddress		: out STD_LOGIC_VECTOR (18 DOWNTO 0) :="0000000000000000000";
			wrclock		: out STD_LOGIC  := '1';
			wren		: out STD_LOGIC  := '0';
			--FIFO Sram
			wren_fifo : out std_logic;
			data_fifo : out std_LOGIC_VECTOR (30 downto 0);
			start_seg : out std_logic;
			
			MODE : in std_logic_vector (1 downto 0)

		);
end component;
 
--    component Demosaic_and_Filter is
--        port(
--            CLOCK_50    : in  std_logic;
--            PIXCLK      : in  std_logic;
--            FRAME_VALID : in  std_logic;
--            cur_Y       : in  integer range 0 to 2047;
--            rdaddress   : out std_logic_vector(12 downto 0);
--          rdclock     : out std_logic;
--          q           : in  std_logic_vector(7 downto 0);
--          RGB         : out std_logic_vector(7 downto 0);
--            wraddress   : out std_logic_vector(18 downto 0);
--            wrclock     : out std_logic;
--            wren        : out std_logic;
--            wren_fifo   : out std_logic;
--            data_fifo   : out std_logic_vector(30 downto 0);
--            start_seg   : out std_logic;
--            MODE        : in  std_logic_vector(1 downto 0)
--        );
--    end component;
 
    -- ----------------------------------------------------------------------
    -- Internal signals
    -- ----------------------------------------------------------------------
    -- Pixel tracker outputs
    signal s_cur_X             : integer range 0 to 2047;
    signal s_cur_Y             : integer range 0 to 2047;
    signal s_isInValidRegion   : std_logic;
 
    -- Pixel_RAM_writer -> Pixel_RAM
    signal s_ram_data_in       : std_logic_vector(7 downto 0);
    signal s_ram_wraddress     : std_logic_vector(12 downto 0);
    signal s_ram_wrclock       : std_logic;
    signal s_ram_wren          : std_logic;
 
    -- Demosaic -> Pixel_RAM (read side)
    signal s_ram_rdaddress     : std_logic_vector(12 downto 0);
    signal s_ram_rdclock       : std_logic;
    signal s_ram_q             : std_logic_vector(7 downto 0);
 
begin
 
    -- ----------------------------------------------------------------------
    -- Pixel coordinate tracker
    -- ----------------------------------------------------------------------
    Pixel_tracking_inst : Pixel_tracking
        port map (
            PIXCLK          => PIXCLK,
            FRAME_VALID     => FRAME_VALID,
            LINE_VALID      => LINE_VALID,
            cur_X           => s_cur_X,
            cur_Y           => s_cur_Y,
            isInValidRegion => s_isInValidRegion
        );
 
    -- ----------------------------------------------------------------------
    -- Writer into the 4-line circular buffer (the PIXEL RAM)
    -- ----------------------------------------------------------------------
    Pixel_RAM_writer_inst : Pixel_RAM_writer
        port map (
            PIXCLK          => PIXCLK,
            cur_X           => s_cur_X,
            cur_Y           => s_cur_Y,
            isInValidRegion => s_isInValidRegion,
            DATA            => DATA,
            DATA_OUT        => s_ram_data_in,
            wraddress       => s_ram_wraddress,
            wrclock         => s_ram_wrclock,
            wren            => s_ram_wren
        );
 
    -- ----------------------------------------------------------------------
    -- 4-line circular pixel buffer (BRAM) - PIXEL RAM
    -- ----------------------------------------------------------------------
    Pixel_RAM_inst : Pixel_RAM
        port map (
            data      => s_ram_data_in,
            wraddress => s_ram_wraddress,
            wrclock   => s_ram_wrclock,
            wren      => s_ram_wren,
            rdaddress => s_ram_rdaddress,
            rdclock   => s_ram_rdclock,
            q         => s_ram_q
        );
 
    -- ----------------------------------------------------------------------
    -- Demosaic + skin filter
    -- ----------------------------------------------------------------------
    Demosaic_inst : raw_to_rgb_converter
        port map (
            CLOCK_50    => CLOCK_50,
            PIXCLK      => PIXCLK,
            FRAME_VALID => FRAME_VALID,
            Y       => s_cur_Y,
            rdaddress   => s_ram_rdaddress,
            rdclock     => s_ram_rdclock,
            q           => s_ram_q,
            RGB         => RGB,
            wraddress   => wraddress,
            wrclock     => wrclock,
            wren        => wren,
            wren_fifo   => wren_fifo,
            data_fifo   => data_fifo,
            start_seg   => start_seg,
            MODE        => MODE
        );
 
 
end BEH_Camera_flux_decoder;