library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity I2C_master is 
    -- start/address(7 bits)-R/W bit-ACK1 - 8 bits data - ACK2 - stop
    port(
        clock : in std_logic; -- master clock
        rst   : in std_logic; -- reset
        trigger : in std_logic; -- to start the control process
        restart : in std_logic; -- generate a new start (the start point of the cycle)

        address : in std_logic_vector(6 downto 0); -- 7 bits address
        is_last_bit : in std_logic; 
        read_write : in std_logic; -- the R/W bit, to be set to 0 to be the write only mode
        write_data : in std_logic_vector(7 downto 0);
        ack_error : out std_logic; -- 0 = ACK, 1 = NACK
        busy : out std_logic;

        -- I2C buses
        scl : inout std_logic;
        sda : inout std_logic
    );
    end entity;

architecture RTL_design of I2C_master is
    --declarative part
    type state_machine is
        (
            START1, 
            START2, 
            WRITING_DATA, WRITING_ACK,
            WRITE_WAITING,
            STOP1, STOP2, STOP3,
            RESTART_S
        );
        signal running : std_logic := '0'; -- not idle, trigger received
        signal pause_running : std_logic := '0'; -- used to wait for the next trigger
        signal i2c_clock : std_logic; -- I2C clock - 100KHz
        signal previous_running_clock : std_logic; --to store the edge
        signal state : state_machine := START1;
        signal scl_local : std_logic := '1';
        signal sda_local : std_logic := '1';
begin
    -- to make a 100KHz i2c 'clock' which is in fact a pulse generator
    -- 50 000 000 / 100000 = 500, log2 500 = ~ 9, so 9 bits wide and take the 2-nd msb
    process (rst, clock)
        variable i2c_clock_counter : unsigned(8 downto 0);
        -- declarative part
    begin
        if (rst = '0') then 
            i2c_clock_counter := (others => '0');
            running <= '0';
        elsif rising_edge(clock) then 
            if (trigger = '1') then
                -- trigger is on, we move to the controlling process and we reset the counter
                running <= '1';
                i2c_clock_counter := (others => '0');
            end if;
            if (running = '1') then 
                i2c_clock_counter := i2c_clock_counter + 1;
                previous_running_clock <= i2c_clock;
                i2c_clock <= i2c_clock_counter(7);
            end if; 
            if (pause_running  = '1') then
                running <= '0';
            end if;
        end if;
    end process ;
    
    process (clock, rst)
        variable clock_flip : std_logic := '0';
        variable bit_counter : integer range 0 to 8 := 0;
        variable data_to_write : std_logic_vector(7 downto 0); -- maybe the slave address or actual data
    begin 
        if (rst = '0') then 
            scl_local <= '1';
            sda_local <= '1';
            state <= START1;
				ack_error <= '0';
        elsif rising_edge(clock) then
            pause_running <= '0';

            if (restart = '1') then
                state <= RESTART_S;
            end if;

            if (running = '1' and i2c_clock = '1' and previous_running_clock = '0') then 
                case state is 
                    when START1 =>
                        scl_local <= '1';
                        sda_local <= '1';
                        state <= START2;
                    
                    when START2 => 
                        sda_local <= '0';
                        clock_flip := '0';
                        bit_counter := 8;
                        data_to_write := address & read_write; -- concatenate
                        state <= WRITING_DATA;
                    
                    when WRITING_DATA =>
                        scl_local <= clock_flip;
                        sda_local <= data_to_write( bit_counter - 1);
                        if (clock_flip = '1') then 
                            bit_counter := bit_counter - 1;
                            if (bit_counter = 0) then 
                                state <= WRITING_ACK;
                            end if;
                        end if;
                        clock_flip := not clock_flip;
                    
                    when WRITING_ACK =>
                        scl_local <= clock_flip;
                        sda_local <= '1';

                        if (clock_flip = '1') then 
                            ack_error <= sda;
                            if (is_last_bit = '1') then
                                state <= STOP1;
                            else 
                                pause_running <= '1';
                                state <= WRITE_WAITING;
                            end if;
                        end if;
                        clock_flip := not clock_flip;

                    when WRITE_WAITING =>
                        data_to_write := write_data;
                        bit_counter := 8;
                        state <= WRITING_DATA;
                    
                    when STOP1 =>
                        sda_local <= '0';
                        scl_local <= '0';
                        state <= STOP2;
                    
                    when STOP2 => 
                        scl_local <= '1';
                        state <= STOP3;
                    
                    when STOP3 =>
                        sda_local <= '1';
                        pause_running <= '1';
                        state <= START1;
                    
                    when RESTART_S =>
                        scl_local <= '0';
                        sda_local <= '0';
                        state <= START1;
                    
                end case;
            end if;
        end if;
    end process;

    busy <= running;
    scl <= 'Z' when (scl_local = '1') else '0';
    sda <= 'Z' when (sda_local = '1') else '0';
        
end architecture;