
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;


entity rx_frame_reader is
    Generic (
        constant c_WIDTH : natural := 8;
        constant c_UART_BAUD : natural := 9600;
        constant c_CLK_FREQ : natural := 100_000_000
    );
    Port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_buffer_full : in std_logic;
        i_rx_port : in std_logic;
        
        o_write_en : out std_logic;
        o_read_byte : out std_logic_vector (c_WIDTH-1 downto 0)
    );
end rx_frame_reader;

architecture Behavioral of rx_frame_reader is
    -- states: sync, complete, receive, wait
    -- receiver should expect to se in order -> 0 , <8-bit-data> , 1
    -- (need to work on other formats and termination options later on...)
    -- if not, it should go back to sync. If all is well, it sould be idle.
    
    constant c_FRAME_END : natural := c_WIDTH + 1; -- 0 & data & 1
    constant c_CLKS_PER_BIT : natural := c_CLK_FREQ / c_UART_BAUD;
    constant c_CLKS_SYNC : natural := c_CLKS_PER_BIT / 2;
    
    signal r_STATE : std_logic_vector (1 downto 0) := "00"; -- initially sync
    signal r_RX_DATA : std_logic_vector (c_WIDTH-1 downto 0) := (others => '0');
    signal r_BIT_COUNTER : natural range 0 to c_WIDTH-1 := 0;
    signal r_CLK_COUNTER : natural range 0 to c_CLKS_PER_BIT := 0;
    signal r_SYNC_COUNTER : natural range 0 to c_CLKS_SYNC := 0;
    
    signal w_BUFFER_FULL : std_logic;
    signal w_RX_PORT : std_logic;
    signal w_READ_BYTE : std_logic_vector (c_WIDTH-1 downto 0);
    signal w_WRITE_EN : std_logic;
    
    constant c_SYNC : std_logic_vector(1 downto 0) := "00";
    constant c_END : std_logic_vector(1 downto 0) := "01";
    constant c_RECEIVE : std_logic_vector(1 downto 0) := "10";
    constant c_WAIT : std_logic_vector(1 downto 0) := "11";
begin

    w_RX_PORT <= i_rx_port;
    w_BUFFER_FULL <= i_buffer_full;
    o_read_byte <= w_READ_BYTE;
    o_write_en <= w_WRITE_EN;

    p_MAIN : process (i_clk) is
    begin    
        if rising_edge (i_clk) then
            if i_reset = '1' then 
                w_READ_BYTE <= (others => '0');
                w_WRITE_EN <= '0';
                r_STATE <= c_WAIT;
                r_RX_DATA <= (others => '0');
                r_BIT_COUNTER <= 0;
                r_SYNC_COUNTER <= 0;
                r_CLK_COUNTER <= 0;
            else
            
                case r_STATE is
                    when c_SYNC => -- sync state
                        w_WRITE_EN <= '0';
                    
                        case w_RX_PORT is
                            when '1' =>
                                r_SYNC_COUNTER <= 0;
                            when '0' =>
                                if r_SYNC_COUNTER = c_CLKS_SYNC then
                                    r_SYNC_COUNTER <= 0;
                                    r_STATE <= c_RECEIVE;
                                else
                                    r_SYNC_COUNTER <= r_SYNC_COUNTER + 1;
                                end if;
                            when others =>
                                r_SYNC_COUNTER <= 0;
                                r_STATE <= c_WAIT; 
                        end case;
                                       
                    when c_END => -- end state
                        if r_CLK_COUNTER = c_CLKS_PER_BIT-1 then
                            case w_RX_PORT is
                                when '1' => -- initial syncronization was correct, continue
                                    w_READ_BYTE <= r_RX_DATA;
                                    r_STATE <= c_SYNC;
                                    
                                    if w_BUFFER_FULL = '0' then
                                        w_WRITE_EN <= '1'; -- I may improve upon this logic later on.
                                    end if;
                                    
                                when '0' => -- initial syncronization was wrong. Do not pass the data.
                                    r_STATE <= c_WAIT; -- "wait for 1" state (?)
                                    
                                when others =>
                                    r_STATE <= c_WAIT; -- go to wait state until '1'.
                            end case;
                            
                            r_CLK_COUNTER <= 0;
                        else
                            r_CLK_COUNTER <= r_CLK_COUNTER + 1;
                        end if; 
                    
                    when c_RECEIVE => -- receive state
                        if r_CLK_COUNTER = c_CLKS_PER_BIT-1 then 
                            r_RX_DATA(c_WIDTH-1) <= w_RX_PORT;
                            r_RX_DATA(c_WIDTH-2 downto 0) <= r_RX_DATA(c_WIDTH-1 downto 1); -- shift registers
                            
                            if r_BIT_COUNTER < c_WIDTH-1 then
                                r_BIT_COUNTER <= r_BIT_COUNTER + 1;
                            else
                                r_BIT_COUNTER <= 0;
                                r_STATE <= c_END;
                            end if;
                            
                            r_CLK_COUNTER <= 0;
                        else    
                            r_CLK_COUNTER <= r_CLK_COUNTER + 1;
                        end if;
                        
                    when c_WAIT => -- wait state
                        if w_RX_PORT = '1' then
                            r_STATE <= c_SYNC;
                        end if;
                        
                    when others =>
                        r_STATE <= c_WAIT; -- other logic states go to wait state
                        
                end case;
            end if;
        end if;
    end process p_MAIN;


end Behavioral;
