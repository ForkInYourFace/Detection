library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- ============================================================================
-- Skin_segmentation_top
-- ----------------------------------------------------------------------------
-- DE2-115 top level. Wires the camera capture pipeline, the I2C camera
-- configuration manager, and the VGA display module to the on-board UI.
--
-- The SRAM-based segmentation pipeline is NOT included here yet. MODE = "11"
-- (MASK_TO_SRAM) is exposed but its outputs (data_fifo, wren_fifo, start_seg)
-- are left open. Use MODE = "01" (RAW_TO_VGA) or "10" (MASK_TO_VGA) for now.
--
-- UI mapping:
--   KEY(0)  : rst         (active low)
--   KEY(1)  : incr button (active low on DE2-115; treated as active low here)
--   KEY(2)  : decr button
--   SW(0)   : MODE(0)
--   SW(1)   : MODE(1)
--   SW(13)  : b_gain_sw
--   SW(14)  : g_gain_sw
--   SW(15)  : r_gain_sw
--   SW(16)  : exp_sw
--   SW(17)  : setup_en
--   LEDR(17): update_pending indicator
-- ============================================================================

entity Skin_segmentation_top is
    Port (
            CLOCK_50    : in std_logic;
            KEY         : in std_logic_vector(3 downto 0); 
            LEDR        : out std_logic_vector(17 downto 0);
            -- Green LED for I2C trains debug
            LEDG        : out std_logic_vector(7 downto 0);
          
            CMOS_SDAT    : inout std_logic;
            CMOS_SCLK    : inout std_logic;
            
            CMOS_PIXCLK : in std_logic;
            CMOS_MCLK   : out std_logic;
            CMOS_FVAL   : in std_logic;
            CMOS_LVAL   : in std_logic;
            CMOS_DATA   : in std_logic_vector (9 downto 0);
            
            VGA_HS      : out std_logic;
            VGA_VS      : out std_logic;
            VGA_R       : out std_logic_vector (7 downto 0);
            VGA_G       : out std_logic_vector (7 downto 0);
            VGA_B       : out std_logic_vector (7 downto 0);
            VGA_BLANK_N : out std_logic;
            VGA_SYNC_N  : out std_logic;
            VGA_CLK     : out std_logic;
            
            SW          : in std_logic_vector (17 downto 0)
    );
end Skin_segmentation_top;


architecture BEH_top of Skin_segmentation_top is

    -- ----------------------------------------------------------------------
    -- Component declarations
    -- ----------------------------------------------------------------------
	 --------------------------------------------------------------------------
    ---- PLL part : to generate the 25MHz clock ------------------------------
    --------------------------------------------------------------------------
	 component CLOCK_DIV_HALF is
        -- means that this is a 25MHz clock 
        port(
		    inclk0		: IN STD_LOGIC  := '0';
		    c0		    : OUT STD_LOGIC
        );
        end component;

        
    component Camera_flux_decoder is
        port(
            CLOCK_50    : in  std_logic;
            PIXCLK      : in  std_logic;
            FRAME_VALID : in  std_logic;
            LINE_VALID  : in  std_logic;
            DATA        : in  std_logic_vector(9 downto 0);
            MODE        : in  std_logic_vector(1 downto 0);
            RGB         : out std_logic_vector(7 downto 0);
            wraddress   : out std_logic_vector(18 downto 0);
            wrclock     : out std_logic;
            wren        : out std_logic;
            wren_fifo   : out std_logic;
            data_fifo   : out std_logic_vector(30 downto 0);
            start_seg   : out std_logic
        );
    end component;

    component Graphic_module is
        generic(
            WIDTH    : integer := 640;
            HEIGHT   : integer := 480;
            H_FP     : integer := 16;
            H_BP     : integer := 48;
            V_FP     : integer := 10;
            V_BP     : integer := 33;
            H_ST     : integer := 96;
            V_ST     : integer := 2;
            H_PIXELS : integer := 800;
            V_PIXELS : integer := 525
        );
        port(
            CLOCK_50   : in  std_logic;
            rst        : in  std_logic;
            wr_data    : in  std_logic_vector(7 downto 0);
            wr_address : in  std_logic_vector(18 downto 0);
            wren       : in  std_logic;
				wr_clock   : in std_logic;
            VGA_R      : out std_logic_vector(7 downto 0);
            VGA_G      : out std_logic_vector(7 downto 0);
            VGA_B      : out std_logic_vector(7 downto 0);
            VGA_BLANK  : out std_logic;
            VGA_CLK    : out std_logic;
            H_SYNC     : out std_logic;
            V_SYNC     : out std_logic;
			MODE     : in std_logic_vector(1 downto 0);
            CROSSHAIR_MODE : in std_logic
        );
    end component;

    component I2C_manager_block is 
        port(
            clk         : in  std_logic;
            rst_n       : in  std_logic;
            rst_reg     :  in std_logic;
            -- User interfaces
            setup_en      : in std_logic;
            exp_sw        : in std_logic;
            b_gain_sw     : in std_logic;
            r_gain_sw     : in std_logic;
            g1_gain_sw    : in std_logic;
            g2_gain_sw    : in std_logic;
            incr          : in std_logic;
            decr          : in std_logic;
				update 		  : in std_logic;
            -- Interface with the I2C master
            i2c_busy    : in  std_logic;
            i2c_trigger : out std_logic;
            i2c_address : out std_logic_vector(6 downto 0);
            i2c_rw      : out std_logic;
            i2c_data    : out std_logic_vector(7 downto 0);
            i2c_last    : out std_logic;
            -- Debugging LED
            is_Filled_LED   : out std_logic;
            is_Done_LED     : out std_logic;
            led_update_pending : out std_logic
        );
        
    end component;

    component I2C_master is
        port(
            clock       : in  std_logic;
            rst         : in  std_logic;
            trigger     : in  std_logic;
            restart     : in  std_logic;
            address     : in  std_logic_vector(6 downto 0);
            is_last_bit : in  std_logic;
            read_write  : in  std_logic;
            write_data  : in  std_logic_vector(7 downto 0);
            ack_error   : out std_logic;
            busy        : out std_logic;
            scl         : inout std_logic;
            sda         : inout std_logic
        );
    end component;

    -- ----------------------------------------------------------------------
    -- Internal signals
    -- ----------------------------------------------------------------------
    signal rst          : std_logic;
    signal mode_sel     : std_logic_vector(1 downto 0);
	signal clock_25		: std_logic;

    -- Camera_flux_decoder -> Graphic_module
    signal cam_rgb      : std_logic_vector(7 downto 0);
    signal cam_wraddr   : std_logic_vector(18 downto 0);
    signal cam_wren     : std_logic;
	signal cam_wrclock  : std_logic;
    -- Camera_flux_decoder SRAM outputs (parked, not used yet)
    signal cam_wren_fifo : std_logic;
    signal cam_data_fifo : std_logic_vector(30 downto 0);
    signal cam_start_seg : std_logic;

    -- I2C
    signal i2c_busy        : std_logic;
    signal i2c_trigger     : std_logic;
    signal i2c_address     : std_logic_vector(6 downto 0);
    signal i2c_rw          : std_logic;
    signal i2c_data        : std_logic_vector(7 downto 0);
    signal i2c_last        : std_logic;
    signal i2c_ack_error   : std_logic;
    signal update_pending_s : std_logic;



begin
     --------------------------------------------------------------------------
     ---- PLL part : to generate the 25MHz clock ------------------------------
     --------------------------------------------------------------------------
     PLL_inst : CLOCK_DIV_HALF
         port map(
                inclk0 => CLOCK_50,
                c0     => clock_25
        );

    -- ----------------------------------------------------------------------
    -- UI mapping
    -- ----------------------------------------------------------------------
    rst       <= KEY(0);                       -- active low, matches downstream convention
    mode_sel  <= SW(1) & SW(0);                -- SW(1)=MSB, SW(0)=LSB

    -- VGA static outputs
    VGA_SYNC_N <= '0';                         -- composite sync disabled
    
    -- Camera Master Clock (documentation 25Mhz)
    CMOS_MCLK <= clock_25;                     -- reput to 25Mhz

    -- Indicator LEDs
	 --LEDR(9 downto 0)			 <= CMOS_DATA;
    LEDR(17) <= update_pending_s;
	LEDR(16) <= i2c_ack_error;
    
    LEDR(15 downto 0) <= (others => '0');
    LEDG(5 downto 0)  <= (others => '0');
    -- ----------------------------------------------------------------------
    -- Camera flux decoder (capture + demosaic + classify)
    -- ----------------------------------------------------------------------
    cam_inst : Camera_flux_decoder
        port map (
            CLOCK_50    => CLOCK_50,
            PIXCLK      => CMOS_PIXCLK,
            FRAME_VALID => CMOS_FVAL,
            LINE_VALID  => CMOS_LVAL,
            DATA        => CMOS_DATA,
            MODE        => mode_sel,
            RGB         => cam_rgb,
            wraddress   => cam_wraddr,
            wrclock     => cam_wrclock,        -- Graphic_module uses CLOCK_50 internally
            wren        => cam_wren,
            wren_fifo   => cam_wren_fifo,      -- parked for now
            data_fifo   => cam_data_fifo,
            start_seg   => cam_start_seg
        );

    -- ----------------------------------------------------------------------
    -- Display (VRAM + VGA timing + DAC output)
    -- ----------------------------------------------------------------------
    gpu_inst : Graphic_module
        port map (
            CLOCK_50   => CLOCK_50,
            rst        => rst,
            wr_data    => cam_rgb,
            wr_address => cam_wraddr,
            wren       => cam_wren,
				wr_clock   => cam_wrclock,
            VGA_R      => VGA_R,
            VGA_G      => VGA_G,
            VGA_B      => VGA_B,
            VGA_BLANK  => VGA_BLANK_N,
            VGA_CLK    => VGA_CLK,
            H_SYNC     => VGA_HS,
            V_SYNC     => VGA_VS,
			MODE => mode_sel,
            CROSSHAIR_MODE => SW(2)
        );

    -- ----------------------------------------------------------------------
    -- Camera I2C configuration manager
    -- ----------------------------------------------------------------------
    init_inst : I2C_manager_block
        port map (
            -- clk            => CLOCK_50,
            -- rst            => rst,
            -- i2c_busy       => i2c_busy,
            -- i2c_trigger    => i2c_trigger,
            -- i2c_address    => i2c_address,
            -- i2c_rw         => i2c_rw,
            -- i2c_data       => i2c_data,
            -- i2c_last       => i2c_last,
            -- setup_en       => SW(17),
            -- exp_sw         => SW(16),
            -- r_gain_sw      => SW(15),
            -- g_gain_sw      => SW(14),
            -- b_gain_sw      => SW(13),
            -- incr           => KEY(1),
            -- decr           => KEY(2),
            -- commit         => KEY(3),
            -- update_pending => update_pending_s

            clk         => CLOCK_50,
            rst_n       => rst,
            rst_reg     => rst,
            -- User interfaces
            setup_en      => SW(17),
            exp_sw        => SW(16),
            b_gain_sw     => SW(13),
            r_gain_sw     => SW(15),
            g1_gain_sw    => SW(14),
            g2_gain_sw    => '0',
            incr          => KEY(1),
            decr          => KEY(2),
				update 	     => KEY(3),
            -- Interface with the I2C master
            i2c_busy       => i2c_busy,
            i2c_trigger    => i2c_trigger,
            i2c_address    => i2c_address,
            i2c_rw         => i2c_rw,
            i2c_data       => i2c_data,
            i2c_last       => i2c_last,
            -- Debugging LED
            is_Filled_LED   => LEDG(7),
            is_Done_LED     => LEDG(6), 
            led_update_pending => update_pending_s
        );
    -- ----------------------------------------------------------------------
    -- I2C bit-banging master (talks to the camera over CMOS_SCLK / CMOS_SDAT)
    -- ----------------------------------------------------------------------
    i2c_inst : I2C_master
        port map (
            clock       => CLOCK_50,
            rst         => rst,
            trigger     => i2c_trigger,
            restart     => '0',                -- not used in this flow
            address     => i2c_address,
            is_last_bit => i2c_last,
            read_write  => i2c_rw,
            write_data  => i2c_data,
            ack_error   => i2c_ack_error,
            busy        => i2c_busy,
            scl         => CMOS_SCLK,
            sda         => CMOS_SDAT
        );

end BEH_top;