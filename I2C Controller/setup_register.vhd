    
    -- Table des registres (24 bits = 8 bits adresse reg + 16 bits data)
    --type rom_type is array (0 to 5) of std_logic_vector(23 downto 0);
    --constant INIT_ROM : rom_type := (
      --  x"20_0000", -- Reg 0x20: Context B, pas de skip/mirror
        --x"09_06A9", -- Reg 0x09: Exposition / Luminosité (Augmente 07D0 si trop sombre)
        --x"2B_001C", -- Reg 0x2B: Gain Vert 1 = 1.0x
        --x"2C_0020", -- Reg 0x2C: Gain Bleu = 2.5x 
        --x"2D_0020", -- Reg 0x2D: Gain Rouge = 2.0x 
        --x"2E_001C"  -- Reg 0x2E: Gain Vert 2 = 1.0x
		  
    --);
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity setup_register is
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
end setup_register;

architecture Behavioral of setup_register is

    ----- Declarations of internal signals ----------------
    signal red_gain_hex_int : std_logic_vector(15 downto 0) := x"0020";
    signal blue_gain_hex_int : std_logic_vector(15 downto 0) := x"0020";
    signal green1_gain_hex_int : std_logic_vector(15 downto 0) := x"0020";
    signal green2_gain_hex_int : std_logic_vector(15 downto 0) := x"0020";
    signal reg_exposure_int : std_logic_vector(15 downto 0) := x"07D0";

    signal incr_prev : std_logic := '1';
    signal decr_prev : std_logic := '1';
begin

    process(clk, rst_reg)
        variable curr_config_val : unsigned(15 downto 0);
        variable incr_pressed : boolean;
        variable decr_pressed : boolean;
    begin
        if rst_reg = '0' then
            red_gain_hex_int <= x"0020";
            blue_gain_hex_int <= x"0020";
            green1_gain_hex_int <= x"0020";
            green2_gain_hex_int <= x"0020";
            reg_exposure_int <= x"07D0";
            incr_prev <= '1';
            decr_prev <= '1';
        elsif rising_edge(clk) then
            incr_prev <= incr;
            decr_prev <= decr;
            incr_pressed := (incr_prev = '1' and incr = '0');
            decr_pressed := (decr_prev = '1' and decr = '0');
            if setup_en = '1' then
                if exp_sw = '1' then
                    curr_config_val := unsigned(reg_exposure_int);
                    if incr_pressed then
                        if curr_config_val > (65535 - 250) then
                            curr_config_val := to_unsigned(65535, 16);
                        else
                            curr_config_val := curr_config_val + 100;
                        end if;
                    elsif decr_pressed then
                        if curr_config_val < 250 then
                            curr_config_val := to_unsigned(0, 16);
                        else
                            curr_config_val := curr_config_val - 100;
                        end if;
                    end if;
                    reg_exposure_int <= std_logic_vector(curr_config_val);

                elsif g1_gain_sw = '1' or g2_gain_sw = '1' then
                    curr_config_val := unsigned(green1_gain_hex_int);
                    if incr_pressed then
                        if curr_config_val > (65535 - 15) then
                            curr_config_val := to_unsigned(65535, 16);
                        else
                            curr_config_val := curr_config_val + 15;
                        end if;
                    elsif decr_pressed then
                        if curr_config_val < 15 then
                            curr_config_val := to_unsigned(0, 16);
                        else
                            curr_config_val := curr_config_val - 15;
                        end if;
                    end if;
                    green1_gain_hex_int <= std_logic_vector(curr_config_val);
                    green2_gain_hex_int <= std_logic_vector(curr_config_val);

                elsif b_gain_sw = '1' then
                    curr_config_val := unsigned(blue_gain_hex_int);
                    if incr_pressed then
                        if curr_config_val > (65535 - 15) then
                            curr_config_val := to_unsigned(65535, 16);
                        else
                            curr_config_val := curr_config_val + 15;
                        end if;
                    elsif decr_pressed then
                        if curr_config_val < 15 then
                            curr_config_val := to_unsigned(0, 16);
                        else
                            curr_config_val := curr_config_val - 15;
                        end if;
                    end if;
                    blue_gain_hex_int <= std_logic_vector(curr_config_val);

                elsif r_gain_sw = '1' then
                    curr_config_val := unsigned(red_gain_hex_int);
                    if incr_pressed then
                        if curr_config_val > (65535 - 15) then
                            curr_config_val := to_unsigned(65535, 16);
                        else
                            curr_config_val := curr_config_val + 15;
                        end if;
                    elsif decr_pressed then
                        if curr_config_val < 15 then
                            curr_config_val := to_unsigned(0, 16);
                        else
                            curr_config_val := curr_config_val - 15;
                        end if;
                    end if;
                    red_gain_hex_int <= std_logic_vector(curr_config_val);
                end if;
            end if;
        end if;
    end process;
    red_gain_hex <= red_gain_hex_int;
    green1_gain_hex <= green1_gain_hex_int;
    green2_gain_hex <= green2_gain_hex_int;
    blue_gain_hex <= blue_gain_hex_int;
    exposure_hex <= reg_exposure_int;
end Behavioral;