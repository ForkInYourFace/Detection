library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity camera_init_manager is
    Port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;
        -- Camera config values coming from the I2C registers
        red_gain_hex    : in  std_logic_vector(15 downto 0);
        green1_gain_hex : in  std_logic_vector(15 downto 0);
        green2_gain_hex : in  std_logic_vector(15 downto 0);
        blue_gain_hex   : in  std_logic_vector(15 downto 0);
        exposure_hex    : in  std_logic_vector(15 downto 0);
        -- Update button to charge the camera values with changed values coming from the registers
        update          : in  std_logic := '1';
        -- Interface with le I2C_master (the I2C_master is an I2C controller but at byte level)
        i2c_busy        : in  std_logic;
        i2c_trigger     : out std_logic;
        i2c_address     : out std_logic_vector(6 downto 0);
        i2c_rw          : out std_logic;
        i2c_data        : out std_logic_vector(7 downto 0);
        i2c_last        : out std_logic;
        -- Signalisation
        reg_filled      : out std_logic;
        led_isDone      : out std_logic;
        led_update_pending : out std_logic
    );
end camera_init_manager;

architecture Behavioral of camera_init_manager is

    -- Register data structure 8 bits adresse + 16 bits data
    type reg_struct is array (0 to 5) of std_logic_vector(23 downto 0);
    constant INIT_ROM : reg_struct := (
        x"20_0000", -- Reg 0x20: Context B, pas de skip/mirror
        x"09_07D0", -- Reg 0x09: Exposition / Luminosite
        x"2B_0020", -- Reg 0x2B: Gain Vert 1
        x"2C_0030", -- Reg 0x2C: Gain Bleu
        x"2D_0035", -- Reg 0x2D: Gain Rouge
        x"2E_0015"  -- Reg 0x2E: Gain Vert 2
    );

    signal rom_index            : integer range 0 to 5 := 0;
    signal register_update_data : reg_struct := INIT_ROM;
    signal startup_done         : std_logic := '0';

    -- To check update button state
    signal update_prev : std_logic := '1';   -- update active high
    signal update_edge : std_logic := '0';   

    type state_type is (
        S_IDLE,
        S_SEND_ADDR,  S_WAIT_ADDR_BUSY,  S_WAIT_ADDR_DONE,
        S_SEND_REG,   S_WAIT_REG_BUSY,   S_WAIT_REG_DONE,
        S_SEND_MSB,   S_WAIT_MSB_BUSY,   S_WAIT_MSB_DONE,
        S_SEND_LSB,   S_WAIT_LSB_BUSY,   S_WAIT_LSB_DONE,
        S_DONE
    );
    signal state : state_type := S_IDLE;

begin

    i2c_address <= "1011101";
    i2c_rw      <= '0';

    -- ------------------------------------------------------------------
    -- We capture continuously the changing values in the registers
    -- 
    -- We change only the 16-bits data
    -- ------------------------------------------------------------------
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            register_update_data <= INIT_ROM;   -- au reset : valeurs usine
            reg_filled <= '0';
        elsif rising_edge(clk) then
            register_update_data(1)(15 downto 0) <= exposure_hex;
            register_update_data(2)(15 downto 0) <= green1_gain_hex;
            register_update_data(3)(15 downto 0) <= blue_gain_hex;
            register_update_data(4)(15 downto 0) <= red_gain_hex;
            register_update_data(5)(15 downto 0) <= green2_gain_hex;
            reg_filled <= '1';
        end if;
    end process;

    -- ------------------------------------------------------------------
    -- If update is pressed
    -- ------------------------------------------------------------------
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            update_prev <= '1';
            update_edge <= '0';
        elsif rising_edge(clk) then
            update_prev <= update;
            if (update_prev = '1' and update = '0') then
                update_edge <= '1';
            else
                update_edge <= '0';
            end if;
        end if;
    end process;

    -- ------------------------------------------------------------------
    -- FSM : if reset set all value to ROM
    -- update when the update button is pressed
    -- ------------------------------------------------------------------
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            state        <= S_IDLE;
            led_isDone   <= '0';
            led_update_pending <= '0';
            rom_index    <= 0;
            i2c_trigger  <= '0';
            i2c_last     <= '0';
            i2c_data     <= (others => '0');
            startup_done <= '0';          -- start up with ROM
        elsif rising_edge(clk) then
            case state is

                when S_IDLE =>
                    led_isDone <= '0';
                    led_update_pending <= '1'; -- Signal that initialization/update is starting
                    if i2c_busy = '0' then
                        state <= S_SEND_ADDR;
                    end if;

                -- ---- Slave Adresse + bit R/W ----
                when S_SEND_ADDR =>
                    i2c_trigger <= '1';
                    i2c_last    <= '0';
                    state       <= S_WAIT_ADDR_BUSY;

                when S_WAIT_ADDR_BUSY =>
                    i2c_trigger <= '0';
                    if i2c_busy = '1' then state <= S_WAIT_ADDR_DONE; end if;

                when S_WAIT_ADDR_DONE =>
                    if i2c_busy = '0' then state <= S_SEND_REG; end if;

                -- ---- Send register address(8 bits) ----
                -- ADDRESSES IS FROM ROM 
                when S_SEND_REG =>
                    i2c_data    <= INIT_ROM(rom_index)(23 downto 16);
                    i2c_trigger <= '1';
                    i2c_last    <= '0';
                    state       <= S_WAIT_REG_BUSY;

                when S_WAIT_REG_BUSY =>
                    i2c_trigger <= '0';
                    if i2c_busy = '1' then state <= S_WAIT_REG_DONE; end if;

                when S_WAIT_REG_DONE =>
                    if i2c_busy = '0' then state <= S_SEND_MSB; end if;

                -- The first 8 bit in the 16 bit sequence ----
                when S_SEND_MSB =>
                    if startup_done = '0' then
                        i2c_data <= INIT_ROM(rom_index)(15 downto 8);
                    else
                        i2c_data <= register_update_data(rom_index)(15 downto 8);
                    end if;
                    i2c_trigger <= '1';
                    i2c_last    <= '0';
                    state       <= S_WAIT_MSB_BUSY;

                when S_WAIT_MSB_BUSY =>
                    i2c_trigger <= '0';
                    if i2c_busy = '1' then state <= S_WAIT_MSB_DONE; end if;

                when S_WAIT_MSB_DONE =>
                    if i2c_busy = '0' then state <= S_SEND_LSB; end if;

                -- ---- Last 8 bits in the 16 bits sequence and STOP ----
                when S_SEND_LSB =>
                    if startup_done = '0' then
                        i2c_data <= INIT_ROM(rom_index)(7 downto 0);
                    else
                        i2c_data <= register_update_data(rom_index)(7 downto 0);
                    end if;
                    i2c_trigger <= '1';
                    i2c_last    <= '1';
                    state       <= S_WAIT_LSB_BUSY;

                when S_WAIT_LSB_BUSY =>
                    i2c_trigger <= '0';
                    if i2c_busy = '1' then state <= S_WAIT_LSB_DONE; end if;

                when S_WAIT_LSB_DONE =>
                    if i2c_busy = '0' then
                        if rom_index = 5 then
                            state <= S_DONE;
                        else
                            rom_index <= rom_index + 1;
                            state     <= S_SEND_ADDR;
                        end if;
                    end if;

                -- ---- we wait if there is an update ----
                when S_DONE =>
                    i2c_trigger <= '0';
                    led_isDone  <= '1';        
                    led_update_pending <= '0'; -- Update has finished
                    rom_index   <= 0;
                    if update_edge = '1' then
                        -- if update is pressed one more time then resend address (to rebegin to update)
                        startup_done <= '1';
                        led_isDone   <= '0';
                        led_update_pending <= '1'; 
                        state        <= S_SEND_ADDR;
                    else
                        state <= S_DONE;
                    end if;

            end case;
        end if;
    end process;

end Behavioral;