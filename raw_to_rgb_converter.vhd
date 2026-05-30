library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- Si besoin on peut remplacer PIXCLK par CLOCK_50 pour faire le travail plus vite, mais il faut alors faire un composant en plus qui nous dit quand lire

entity raw_to_rgb_converter is
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
end raw_to_rgb_converter;

architecture raw_to_rgb_converter_arch of raw_to_rgb_converter is

--Different MODE
constant MODE_RAW_to_VGA    : std_logic_vector(1 downto 0) := "00";
constant MODE_MASK_to_VGA   : std_logic_vector(1 downto 0) := "01";
constant MODE_MASK_SRAM     : std_logic_vector(1 downto 0) := "11";

--Syncrhonisation signal to synchronize with the camera
signal Y_SYNC : integer range 0 to 2047;
signal FRAME_VALID_SYNC : std_logic;
signal Y_REEL : integer range 0 to 2047;

--Internal counters
signal x : integer range 0 to 1280 :=0;
signal y_vga : integer range 0 to 640 :=0;
signal y_parity : integer range 0 to 1 :=0;


signal state : integer range 0 to 8 :=0; -- 0 rien, 1 au prÃ©cÃ©dent on a lu g1, 2 au prÃ©cÃ©dent on a lu r, 3 au prÃ©cÃ©dent on a lu b, 4 au prÃ©cÃ©dent on a lu g2

--Stores pixels in different format
signal g_one_sig : unsigned (2 DOWNTO 0):="000";
--signal r_sig : unsigned (1 DOWNTO 0):="00";
signal b_sig : unsigned (1 DOWNTO 0):="00";
signal g_two_sig : unsigned (2 DOWNTO 0):="000";

signal g_one_sig_skin : unsigned (6 DOWNTO 0):="0000000";
signal g_skin : unsigned (7 DOWNTO 0):="00000000";
signal b_skin : unsigned (7 DOWNTO 0):="00000000";
signal start_seq_sig : std_LOGIC := '0';
--signal b : unsigned (7 DOWNTO 0):="00000000";

signal sram_word : std_LOGIC_VECTOR (15 downto 0);

--signal test_sig : std_logic_vector (7 downto 0);

--signal r_cond : boolean;
--signal b_cond : boolean;
--signal g_cond : boolean;
--signal max : integer range 0 to 256;
--signal min : integer range 0 to 256;
--signal max_min_cond : boolean;
--signal rg_ecart : boolean;
--signal r_gt_g : boolean;
--signal r_gt_b : boolean;

begin

process(PIXCLK)
begin
Y_SYNC<=Y;
FRAME_VALID_SYNC <= FRAME_VALID;
end process;

process(CLOCK_50)
variable g : unsigned (3 downto 0);

--To apply the skin detection function
variable r_skin : unsigned (7 downto 0);
variable r_skin_int : integer range 0 to 256;
variable g_skin_int : integer range 0 to 256;
variable b_skin_int : integer range 0 to 256;
variable r_cond : boolean;
variable b_cond : boolean;
variable g_cond : boolean;
variable max : integer range 0 to 256;
variable min : integer range 0 to 256;
variable max_min_cond : boolean;
variable rg_ecart : boolean;
variable r_gt_g : boolean;
variable r_gt_b : boolean;

begin


if rising_edge(CLOCK_50) then
	--IDLE
	if state=0 then
		wren<='0';
		wren_fifo <= '0';
		if y_vga >=480 or FRAME_VALID_SYNC='0' then
			y_vga<=0;
			start_seq_sig <= '1';
		elsif ((Y_REEL>((y_vga*2) +1)) or (Y_REEL < y_vga*2)) and Y_REEL/=2000 then
			state <= 1;
		end if;
		
	--GET_FIRST_PIXEL (G1)
	elsif state=1 then
		wren<='0';
		wren_fifo<='0';
		b_sig <= unsigned(q(7 downto 6));
		b_skin <= unsigned(q);
		--vert
		state <= state+1;
		x<=x+1;
		
	--WAIT_RESPONSE
	elsif state = 2 then
		state <= state+1;
		
	--GET_SECOND_PIXEL (G2)
	elsif state=3 then
		g_one_sig <=unsigned(q(7 downto 5));
		g_one_sig_skin <= unsigned(q(7 downto 1));
		state <= state+1;
		y_parity<=1;
		x<=x-1;
		
	--WAIT_RESPONSE
	elsif state = 4 then
		state <= state+1;

	--GET_THIS_PIXEL (R)
	elsif state=5 then
		--g <=unsigned(q(7 downto 0));
		--r_sig <=unsigned(q(7 downto 6));
		g_two_sig <= unsigned(q(7 downto 5));
		g_skin <='0' & unsigned(q(7 downto 1)) + g_one_sig_skin;

		
		--test_sig <= q;
		--RGB <= std_LOGIC_VECTOR(q);
		x<=x+1;
		state <= state+1;
		--test:
		--y_parity<=y_parity+1;

	--WAIT_RESPONSE
	elsif state = 6 then
		state <= state+1;
		
	--GET_FOURTH_PIXEL (B) and PROCESS
	elsif state=7 then

		
		if MODE=MODE_MASK_to_VGA or MODE = MODE_MASK_SRAM then 
			--SKIN_COLOR_DETECTION
			r_skin := unsigned(q);
		
			r_skin_int := to_integer(r_skin);
			b_skin_int := to_integer(b_skin);
			g_skin_int := to_integer(g_skin);
		
			r_cond := r_skin_int> 95;
			b_cond := b_skin_int> 20;
			g_cond := g_skin_int> 40;
		
			if r_skin_int>b_skin_int and r_skin_int>g_skin_int then
				max := r_skin_int;
			elsif g_skin_int>b_skin_int then
				max := g_skin_int;
			else
				max :=b_skin_int;
			end if;
		
			if r_skin_int<b_skin_int and r_skin_int<g_skin_int then
				min := r_skin_int;
			elsif g_skin_int<b_skin_int then
				min := g_skin_int;
			else
				min :=b_skin_int;
			end if;

			max_min_cond := max-min>15;
			rg_ecart := r_skin_int-g_skin_int<15 and g_skin_int-r_skin_int<15;
			r_gt_g := r_skin>g_skin;
			r_gt_b := r_skin>b_skin;
			
			--WRITE_RESULT 
			if r_cond and b_cond and g_cond and max_min_cond and r_gt_g and r_gt_b and rg_ecart then
				sram_word(x mod 16)<='1';
			else
				sram_word(x mod 16)<='0';
			end if;
			
			--SEND_RESULT to the correct output
			--if MODE=MODE_MASK_SRAM then
			--	if (x mod 16) = 15 then
			--		wren_fifo <= '1';
			--		data_fifo(15 downto 0) <= sram_word;
			--		data_fifo(30 downto 16) <= std_logic_vector(to_unsigned(y_vga*40 + x/16, 15));
			--	end if;
			--else
				RGB <= (others => sram_word(x mod 16));
				wraddress <= std_logic_vector(shift_right(to_unsigned(x,19),1)+to_unsigned(y_vga*640,19));
				wren <= '1';
			--end if;
		else
			RGB(1 downto 0) <= std_logic_vector(b_sig);
			g := ('0' & g_one_sig) + unsigned(g_two_sig);
			RGB(5 downto 2) <= std_logic_vector(g);
			RGB(7 downto 6) <= std_logic_vector(q(7 downto 6));
			wraddress <= std_logic_vector(shift_right(to_unsigned(x,19),1)+to_unsigned(y_vga*640,19));
			wren <= '1';
		end if;
		
		
		y_parity <= 0;
		
		state <= state+1;
		x<=x+1;
		if x=1279 then
			y_vga <=y_vga+1;
			x<=0;
			state <=0;
		end if;
	elsif state = 8 then
		--wren_fifo <= '0';
		--wren <= '0';
		state <= 1;
	end if; 
end if;
end process;

--r_cond <= to_integer(r)> 95;
--b_cond <= to_integer(b)> 20;
--g_cond <= to_integer(g)> 40;

--max <= to_integer(r) when to_integer(r)>b and to_integer(r)>to_integer(g) else to_integer(g) when to_integer(g)>to_integer(b) else to_integer(b);
--min <= to_integer(r) when to_integer(r)<to_integer(b) and to_integer(r)<to_integer(g) else to_integer(g) when to_integer(g)<to_integer(b) else to_integer(b);

--max_min_cond <= max-min>15;
--rg_ecart <= to_integer(r)-to_integer(g)<15 and to_integer(g)-to_integer(r)<15;
--r_gt_g <= r>g;
--r_gt_b <= r>b;

rdclock <= PIXCLK;
wrclock <= PIXCLK;
rdaddress(12 downto 11) <= "00" when (y_parity=0 and y_vga mod 2 =0) else
									"01" when (y_parity=1 and y_vga mod 2 =0) else
									"10" when (y_parity=0 and y_vga mod 2 =1) else
									"11";
rdaddress(10 downto 0) <= std_logic_vector(to_unsigned(x,11));
start_seg <= start_seq_sig;
Y_REEL <= Y_SYNC-8 when (Y_SYNC>=8) and (Y_SYNC<968) else 2000; --968=2*480+8

end raw_to_rgb_converter_arch;
