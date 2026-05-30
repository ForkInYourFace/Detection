library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
-- This module is used to connect the VGA module to the VGA screen inorder to display on it
-- New version : Calculate the filtered image and display the tracking centroids
-- New New version : Because the lightning is not consistent and I suffered from jiggling crosshairs because of pixel jiggling so I need to implement a temporal filter to take the 
-- average pixel overtime, in order to block this irritating movement.
-- So the motivation is to add more inertia into the crosshair, I need to make the weight of old crosshair bigger than that for the new crosshair to calculate the crosshair position.
-- I will take here the crosshair_pos = 0,75*old_crosshair_pos + 0,25*new_crosshair_pos

-- We will take a dead corridoor of 20 pixels (each size 2 times of the kernal size) so that it would help me to reduce the flickering effect of the crosshair when we have 2 persons, dead corridor = we neglect the values of the pixels
-- in this zone. Therefore the left and right segmentation would be more stable but we have a trade off of crosshair-biasing if 2 heads are close to each other.

-- SPECS --
-- Res : 640 x 480 
entity VGA_display is 
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
        V_PIXELS : integer := 525;

        -- Kernel size
        KERN_SIZE : integer := 7;
        WINDOW_SIZE : integer := 49;
		  
		  -- Verification threshold
		  seuil : integer range 0 to 49:= 30;
        
        -- Tracking Parameters
        COUNT_MIN   : integer := 1000; -- Threshold to validate detection
        CROSS_HALF  : integer := 10   -- Size of the tracking box/cross
    );
    port(
        -- input clock and pixel coordinates
        CLOCK_25 : in std_logic;
        cur_X    : in integer range 0 to H_PIXELS;
        cur_Y    : in integer range 0 to V_PIXELS;
        
        -- VGA signals 
        VGA_R    : out std_logic_vector(7 downto 0);
        VGA_G    : out std_logic_vector(7 downto 0);
        VGA_B    : out std_logic_vector(7 downto 0);
        VGA_BLANK: out std_logic;
        -- VRAM address
        rdaddress: out std_logic_vector(18 downto 0);
        rdclock  : out std_logic;
        q        : in std_logic_vector(7 downto 0);
        -- Display mode
        MODE     : in std_logic_vector(1 downto 0);
        CROSSHAIR_MODE : in std_logic
    );
end VGA_display;

architecture BEH_VGA_display of VGA_display is

    --Different MODE
    constant MODE_RAW_to_VGA    : std_logic_vector(1 downto 0) := "00";
    constant MODE_MASK_to_VGA   : std_logic_vector(1 downto 0) := "01";
    constant MODE_MASK_SRAM     : std_logic_vector(1 downto 0) := "11";
    
    -- RGB signals extracted from VRAM 
    signal r_sig_int : std_logic_vector(1 downto 0) :=  "00";
    signal g_sig_int : std_logic_vector(3 downto 0) :=  "0000";
    signal b_sig_int : std_logic_vector(1 downto 0) :=  "00";

    signal normal_vga_r : std_logic_vector(7 downto 0) := "00000000";
    signal normal_vga_g : std_logic_vector(7 downto 0) := "00000000";
    signal normal_vga_b : std_logic_vector(7 downto 0) := "00000000";
     
    signal mean_vga : std_logic_vector(7 downto 0) := "00000000";
     
    signal next_X    : integer range 0 to WIDTH;
    signal next_Y    : integer range 0 to HEIGHT;
     
    -- SPATIAL FILTER -- The filter of-skin-region in the documentation (Denoise and hole filling, read the documentation)
    type col_sum_array is array (0 to WIDTH - 1) of std_logic_vector(KERN_SIZE-1 downto 0);
    signal col_sums : col_sum_array := (others => (others => '0'));
	 -- ======================================================
	 -- ======================================================
	 -- ======================================================
	 -- ======================================================
	 -- ======================================================

	 -- ======================================================
	 -- ======================================================
	 -- ======================================================
	 -- ======================================================
	 -- ======================================================
    -- intermediate signals to stock pixel coordinates
    signal old_X : integer range 0 to H_PIXELS:=H_PIXELS;
    signal old_Y : integer range 0 to V_PIXELS:=V_PIXELS;
    
    -- ======================================================
    -- CENTROID & TEMPORAL FILTERING SIGNALS=================
    -- ======================================================
    -- The idea is to track humans' head but if there is 2 people, and if we suppose that the 2 people sit side by side,
    -- The centroide will be at the midlle (to be supposed that the 2 heads' areas are approximately the same)
    -- Global Centroid
    -- Inertial filter
    signal sumX : unsigned(29 downto 0) := (others => '0');
    signal sumY : unsigned(29 downto 0) := (others => '0');
    signal count : unsigned(19 downto 0) := (others => '0');
    signal avgX_inertied : integer range 0 to WIDTH := WIDTH/2;
    signal avgY_inertied : integer range 0 to HEIGHT := HEIGHT/2;
    signal valid_global : std_logic := '0';

    -- Left Centroid
    signal sumX_L : unsigned(29 downto 0) := (others => '0');
    signal sumY_L : unsigned(29 downto 0) := (others => '0');
    signal count_L : unsigned(19 downto 0) := (others => '0');
    signal avgX_L_inertied: integer range 0 to WIDTH := WIDTH/4;
    signal avgY_L_inertied : integer range 0 to HEIGHT := HEIGHT/2;
    signal valid_L : std_logic := '0';

    -- Right Centroid
    signal sumX_R : unsigned(29 downto 0) := (others => '0');
    signal sumY_R : unsigned(29 downto 0) := (others => '0');
    signal count_R: unsigned(19 downto 0) := (others => '0');
    signal avgX_R_inertied : integer range 0 to WIDTH := 3*WIDTH/4;
    signal avgY_R_inertied : integer range 0 to HEIGHT := HEIGHT/2;
    signal valid_R : std_logic := '0';
     
begin
    process(CLOCK_25)

        -- For the convolution
        variable old_x_index : integer range 0 to WIDTH;
        variable updated_sum : integer range 0 to 26 := 0;
        -- We calculates these parame
        -- Variables for end of frame division
        variable avgX_calc : integer range 0 to WIDTH;
        variable avgY_calc : integer range 0 to HEIGHT;
        variable avgX_L_calc : integer range 0 to WIDTH;
        variable avgY_L_calc : integer range 0 to HEIGHT;
        variable avgX_R_calc : integer range 0 to WIDTH;
        variable avgY_R_calc : integer range 0 to HEIGHT;

    begin
        if rising_edge(CLOCK_25) then
            -- Data extraction from VRAM as the old version of VGA display
            rdaddress <= std_logic_vector(to_unsigned(next_X + next_Y*WIDTH, 19));
            r_sig_int <= q(7 downto 6);
            g_sig_int <= q(5 downto 2);
            b_sig_int <= q(1 downto 0);
            -- CONVOLUTION (The of-skin-region in the documentation) --
            if (old_X /= cur_X or old_Y /= cur_Y) and cur_X < WIDTH and cur_Y < HEIGHT then
                if next_X > KERN_SIZE - 1 then
                    old_x_index := next_X - KERN_SIZE;
                else
                    old_x_index := WIDTH - KERN_SIZE + next_X;
                end if;
                -- using "vertical" shift registers to stock the window around the considered pixel (convolution windows) 
                -- Note : & is concatenation
                if q = "11111111" then
                    col_sums(next_X) <= col_sums(next_X)(3 downto 0) & "1";
                else
                    col_sums(next_X) <= col_sums(next_X)(3 downto 0) & "0";
                end if;

                -- Convolution 
                if next_X > KERN_SIZE - 1 and next_Y > KERN_SIZE - 1 then
                    updated_sum := 0;
                    for i in 0 to KERN_SIZE - 1 loop
                        for j in 0 to KERN_SIZE - 1 loop
                            if col_sums(next_X - i)(j) = '1' then
                                updated_sum := updated_sum + 1;
                            end if;
                        end loop;
                    end loop;

                    -- Taking the threshold and stacking the coordinates for centroids calculations
                    if updated_sum > seuil then
                        mean_vga <= (others => '1');
                        -- Accumulate Global Centroid
                        sumX <= sumX + to_unsigned(cur_X, 30);
                        sumY <= sumY + to_unsigned(cur_Y, 30);
                        count <= count + 1;
                        -- if this pixel is on the left side of the global cross hair then give it to the left block (global - corridor)
                        if cur_X < (avgX_inertied - 2*KERN_SIZE) then
                            sumX_L <= sumX_L + to_unsigned(cur_X, 30);
                            sumY_L <= sumY_L + to_unsigned(cur_Y, 30);
                            count_L <= count_L + 1;
                        -- same logic but to the right block
                        elsif cur_X > (avgX_inertied + 2*KERN_SIZE) then
                            sumX_R <= sumX_R + to_unsigned(cur_X, 30);
                            sumY_R <= sumY_R + to_unsigned(cur_Y, 30);
                            count_R <= count_R + 1;
                        end if;
                        -- corridor zone : have weights in global crosshair but no impact on neither left nor right
                    else
                        mean_vga <= (others => '0');
                    end if;
                end if;
            end if;

            -- end of frame, compute centroides and apply the low pass filter
            if old_Y < HEIGHT and cur_Y >= HEIGHT then
            --if cur_X = 0 and cur_Y = 480 then
                --- GLOBAL INERTIED CROSSHAIR --

                if count > to_unsigned(COUNT_MIN, 20) then
                    avgX_calc := to_integer(sumX / resize(count, 30));
                    avgY_calc := to_integer(sumY / resize(count, 30));

                    if avgX_calc > WIDTH-1 then avgX_calc := WIDTH-1; end if;
                    if avgY_calc > HEIGHT-1 then avgY_calc := HEIGHT-1; end if;
                    
                    avgX_inertied <= (avgX_inertied - (avgX_inertied / 4)) + (avgX_calc / 4); -- 3/4 old + 1/4 new
                    avgY_inertied <= (avgY_inertied - (avgY_inertied / 4)) + (avgY_calc / 4);
                    valid_global <= '1';
                else 
                        valid_global <= '0';
                    
                end if;

                --- LEFT BLOCK ---

                if count_L > to_unsigned(COUNT_MIN, 20) then
                    avgX_L_calc := to_integer(sumX_L / resize(count_L, 30));
                    avgY_L_calc := to_integer(sumY_L / resize(count_L, 30));

                    if avgX_L_calc > WIDTH-1 then avgX_L_calc := WIDTH-1; end if;
                    if avgY_L_calc > HEIGHT-1 then avgY_L_calc := HEIGHT-1; end if;

                    avgX_L_inertied <= (avgX_L_inertied - (avgX_L_inertied / 4)) + (avgX_L_calc / 4); -- 3/4 old + 1/4 new
                    avgY_L_inertied <= (avgY_L_inertied - (avgY_L_inertied / 4)) + (avgY_L_calc / 4);
                    valid_L <= '1';
                else 
                        valid_L <= '0';
                    
                end if;

                --- RIGHT BLOCK ---

                if count_R > to_unsigned(COUNT_MIN, 20) then
                    avgX_R_calc := to_integer(sumX_R / resize(count_R, 30));
                    avgY_R_calc := to_integer(sumY_R / resize(count_R, 30));

                    if avgX_R_calc > WIDTH-1 then avgX_R_calc := WIDTH-1; end if;
                    if avgY_R_calc > HEIGHT-1 then avgY_R_calc := HEIGHT-1; end if;

                    avgX_R_inertied <= (avgX_R_inertied - (avgX_R_inertied / 4)) + (avgX_R_calc / 4); -- 3/4 old + 1/4 new
                    avgY_R_inertied <= (avgY_R_inertied - (avgY_R_inertied / 4)) + (avgY_R_calc / 4);
                    valid_R <= '1';
                else 
                    valid_R <= '0';
                end if;

                -- reset all counters at end of frame
                sumX <= (others => '0'); sumY <= (others => '0'); count <= (others => '0');
                sumX_L <= (others => '0'); sumY_L <= (others => '0'); count_L <= (others => '0');
                sumX_R <= (others => '0'); sumY_R <= (others => '0'); count_R <= (others => '0');
                
            end if;
            old_X <= cur_X;
            old_Y <= cur_Y;
        end if;
    end process;

    -- Keep old VGA_display logic

    -- To keep in mind that the uncleaned mask is from the raw_to_rgb
    normal_vga_r <= r_sig_int & r_sig_int & r_sig_int & r_sig_int;
    normal_vga_g <= g_sig_int & g_sig_int;
    normal_vga_b <= b_sig_int & b_sig_int & b_sig_int & b_sig_int; 

    -- =========================================================================
    --                          DISPLAY LOGIC 
    -- =========================================================================
    -- need to use a process that takes into account all of the parameters listing below in order to display the wanted image
    process(cur_X, cur_Y, MODE, mean_vga, normal_vga_r, normal_vga_g, normal_vga_b,
            avgX_inertied, avgY_inertied, valid_global,
            avgX_L_inertied, avgY_L_inertied, valid_L,
            avgX_R_inertied, avgY_R_inertied, valid_R) 

            variable draw_global : boolean;
            variable draw_left   : boolean;
            variable draw_right  : boolean;
    begin
        -- Check which crosshair should be drawn
        -- checking logic is simple : should verify : 
        -- 1. is it a valid crosshair (to depass the head size)
        -- 2. is it a pixel in the crosshair region (if in, draw crosshair, if not draw the normal pixel)
        if CROSSHAIR_MODE = '0' then
            draw_global := (valid_global = '1') and not(valid_R = '1' or valid_L = '1') and
                        (cur_X > (avgX_inertied - CROSS_HALF) and cur_X < (avgX_inertied + CROSS_HALF) and
                        cur_Y > (avgY_inertied - CROSS_HALF) and cur_Y < (avgY_inertied + CROSS_HALF));
        else
            -- to show the global crosshair 
            draw_global := (valid_global = '1') and
                        (cur_X > (avgX_inertied - CROSS_HALF) and cur_X < (avgX_inertied + CROSS_HALF) and
                        cur_Y > (avgY_inertied - CROSS_HALF) and cur_Y < (avgY_inertied + CROSS_HALF));
        end if;

        draw_left   := (valid_L = '1') and 
                      (cur_X > (avgX_L_inertied - CROSS_HALF) and cur_X < (avgX_L_inertied + CROSS_HALF) and
                       cur_Y > (avgY_L_inertied - CROSS_HALF) and cur_Y < (avgY_L_inertied + CROSS_HALF));

        draw_right  := (valid_R = '1') and 
                      (cur_X > (avgX_R_inertied - CROSS_HALF) and cur_X < (avgX_R_inertied + CROSS_HALF) and
                       cur_Y > (avgY_R_inertied - CROSS_HALF) and cur_Y < (avgY_R_inertied + CROSS_HALF));

        -- draw logic priorities : global -> sides -> normal image; FIXED : depends on which mode we use
        if draw_global then
            -- global crosshair is red
            VGA_R <= (others => '1');
            VGA_G <= (others => '0');
            VGA_B <= (others => '0');
        -- elsif draw_left or draw_right then
        -- side cross hair is in blue
        elsif draw_left then
            VGA_R <= (others => '0');
            VGA_G <= (others => '0');
            VGA_B <= (others => '1');
        elsif draw_right then
            VGA_R <= (others => '0');
            VGA_G <= (others => '1');
            VGA_B <= (others => '0');
        elsif MODE = MODE_MASK_SRAM then 
            VGA_R <= mean_vga;
            VGA_G <= mean_vga;
            VGA_B <= mean_vga;
        else 
            VGA_R <= normal_vga_r;
            VGA_G <= normal_vga_g;
            VGA_B <= normal_vga_b;
        end if;
    end process;

    -- VGA_BLANK is active-low which means that if we are in the affiching zone it is '1'
    VGA_BLANK <= '1' when (0<= cur_X and cur_X < WIDTH and 0<= cur_Y and cur_Y < HEIGHT) else  '0';
    -- VGA clock
    rdclock <= CLOCK_25;

    next_X <= (cur_X + 1) when (cur_X < WIDTH - 1) else 0;
    --next_Y <= 0 when not (cur_Y < HEIGHT - 1) else cur_Y when (cur_X < WIDTH - 1) else (cur_Y + 1);
	 -- to remove glitches
	next_Y <= 0 when (cur_Y >= HEIGHT) else  -- end height
	 		  0 when (cur_X = WIDTH - 1 and cur_Y = HEIGHT - 1) else  -- end frame
              (cur_Y + 1) when (cur_X = WIDTH - 1) else  -- next line transition
              cur_Y; --mid line
end BEH_VGA_display;








