
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;


entity button_debouncer is
    generic (
        -- for 10 ms
        constant c_DEBOUNCE_CYCLES : natural := 1048575
    );
    Port (
        i_clk : in std_logic;
        i_rst : in std_logic;
        i_btn_raw : in std_logic;
        
        o_debounced : out std_logic;
        o_single_clk_pulse : out std_logic
    );
end button_debouncer;

architecture rtl of button_debouncer is
    -- apperantly, we need syncronization registers to stabilize asyncronous signals like
    -- external world button presses. Typically, 2 are used. Causes 2 cycles of delay of the observed signal.
    signal r_BTN_SYNC_1 : std_logic := '0';
    signal r_BTN_SYNC_2 : std_logic := '0';

    signal r_DEBOUNCED : std_logic:= '0';
    signal r_PULSE : std_logic := '0';
    signal r_COUNTER : natural range 0 to c_DEBOUNCE_CYCLES := 0;
begin

    process (i_clk) is
    begin
        if rising_edge (i_clk) then
            if (i_rst = '1') then
                --r_STABLE <= '1';
                r_BTN_SYNC_1 <= '0';
                r_BTN_SYNC_2 <= '0'; 
                r_DEBOUNCED <= '0';
                r_PULSE <= '0';
                r_COUNTER <= 0;
            else
                
                -- syncronize the button
                r_BTN_SYNC_1 <= i_btn_raw;
                r_BTN_SYNC_2 <= r_BTN_SYNC_1;
                
                -- reset the pulse
                r_PULSE <= '0';
                
                if (r_DEBOUNCED = i_btn_raw) then
                    -- do nothing
                    r_COUNTER <= 0;
                else
                    if (r_COUNTER = c_DEBOUNCE_CYCLES) then
                        r_DEBOUNCED <= i_btn_raw;
                        r_PULSE <= i_btn_raw;
                        r_COUNTER <= 0;
                    else
                        r_COUNTER <= r_COUNTER + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    o_debounced <= r_DEBOUNCED;
    o_single_clk_pulse <= r_PULSE;

end rtl;
