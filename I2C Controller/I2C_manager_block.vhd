library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- This block is an I2C manager, with its internal ROM and register

entity I2C_manager_block is 
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
        update        : in std_logic;
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
    
end I2C_manager_block;

architecture Behavioral of I2C_manager_block is

--- Components ---------------------------------
component setup_register is
    port(

        ---------------- INPUTS ------------------------------
        clk        : in std_logic;
        rst_reg    : in std_logic;
        -- switches and buttons used
        setup_en      : in std_logic;
        exp_sw        : in std_logic;
        b_gain_sw     : in std_logic;
        r_gain_sw     : in std_logic;
        g1_gain_sw    : in std_logic;
        g2_gain_sw    : in std_logic;
        incr          : in std_logic;
        decr          : in std_logic;

        ---------------- OUTPUTS--------------------------------
        red_gain_hex  : out std_logic_vector(15 downto 0);
        green1_gain_hex : out std_logic_vector(15 downto 0);
        green2_gain_hex : out std_logic_vector(15 downto 0);
        blue_gain_hex : out std_logic_vector(15 downto 0);
        exposure_hex : out std_logic_vector(15 downto 0)
    );
    end component;

component camera_init_manager
    Port (
        clk         : in  std_logic;
        rst_n       : in  std_logic;
        -- Incoming values to update the registers of this module
        red_gain_hex  : in std_logic_vector(15 downto 0);
        green1_gain_hex : in std_logic_vector(15 downto 0);
        green2_gain_hex : in std_logic_vector(15 downto 0);
        blue_gain_hex : in std_logic_vector(15 downto 0);
        exposure_hex : in std_logic_vector(15 downto 0);
	update      : in std_logic;
        -- Interface avec le NOUVEAU I2C_master
        i2c_busy    : in  std_logic;
        i2c_trigger : out std_logic;
        i2c_address : out std_logic_vector(6 downto 0);
        i2c_rw      : out std_logic;
        i2c_data    : out std_logic_vector(7 downto 0);
        i2c_last    : out std_logic;
        -- Reception signal
        reg_filled  : out std_logic;
        led_isDone  : out std_logic;
        led_update_pending : out std_logic  
    );
end component;
---------------------- Internal signals --------------------------------
signal red_gain_hex_int : std_logic_vector(15 downto 0) := x"0020";
signal blue_gain_hex_int : std_logic_vector(15 downto 0) := x"0020";    
signal green1_gain_hex_int : std_logic_vector(15 downto 0) := x"0020";
signal green2_gain_hex_int : std_logic_vector(15 downto 0) := x"0020";
signal reg_exposure_int : std_logic_vector(15 downto 0) := x"07D0";
signal received : std_logic; -- debug signal to indicate that the internal register has been updated
signal is_Done_sig : std_logic;

begin
    is_Filled_LED <= received;
    is_Done_LED <= is_Done_sig;
    inst_setup_register : setup_register
        port map (
            clk             => clk,
            rst_reg         => rst_n,
            setup_en        => setup_en,
            exp_sw          => exp_sw,
            b_gain_sw       => b_gain_sw,
            r_gain_sw       => r_gain_sw,
            g1_gain_sw      => g1_gain_sw,
            g2_gain_sw      => g2_gain_sw,
            incr            => incr,
            decr            => decr,
            -- outputs
            red_gain_hex    => red_gain_hex_int,
            green1_gain_hex => green1_gain_hex_int,
            green2_gain_hex => green2_gain_hex_int,
            blue_gain_hex   => blue_gain_hex_int,
            exposure_hex    => reg_exposure_int
        );

    inst_camera_init_manager : camera_init_manager
        port map (
            clk             => clk,
            rst_n           => rst_n,
            red_gain_hex    => red_gain_hex_int,
            green1_gain_hex => green1_gain_hex_int,
            green2_gain_hex => green2_gain_hex_int,
            blue_gain_hex   => blue_gain_hex_int,
            exposure_hex    => reg_exposure_int,
            update          => update,
            i2c_busy        => i2c_busy,
            i2c_trigger     => i2c_trigger,
            i2c_address     => i2c_address,
            i2c_rw          => i2c_rw,
            i2c_data        => i2c_data,
            i2c_last        => i2c_last,
            reg_filled      => received,
            led_isDone      => is_Done_sig,
            led_update_pending => led_update_pending
        );

end Behavioral;