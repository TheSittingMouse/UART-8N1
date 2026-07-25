
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Takes the N-bit data to be sent, makes it into a formal UART
-- package and sends the bits to the tx port.
entity tx_frame_writer is
    Generic (
        constant c_WIDTH : natural := 8;
        constant c_UART_BAUD : natural := 9600;
        constant c_CLK_FREQ : natural := 100_000_000
    );
    Port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_buffer_empty : in std_logic;
        i_data : in std_logic_vector (c_WIDTH-1 downto 0);
        
        o_read_en : out std_logic;
        o_tx_port : out std_logic
    );
end tx_frame_writer;

architecture Behavioral of tx_frame_writer is

    function reverse_vector (vec : in std_logic_vector) return std_logic_vector is
        variable result : std_logic_vector (vec'RANGE);
        alias vec_r : std_logic_vector (vec'REVERSE_RANGE) is vec;
    begin
        for i in vec_r'RANGE loop
            result(i) := vec_r(i);
        end loop;
        return result;
    end function;

    -- 1 (for start) + c_WIDTH + 1 (parity) + 2 (stop)
    constant c_FRAME_END : natural := c_WIDTH + 1; -- c_WIDTH + 1 + 1 - 1
    constant c_CLKS_PER_BIT : natural := c_CLK_FREQ / c_UART_BAUD;

    signal r_TX_FRAME : std_logic_vector (c_FRAME_END downto 0) := (others => '0');
    signal r_BIT_COUNTER : natural range 0 to c_FRAME_END := 0;
    signal r_CLK_COUNTER : natural range 0 to c_CLKS_PER_BIT := 0;
    signal r_STATE : std_logic_vector (1 downto 0) := "00";
    
    signal w_BUFFER_EMPTY : std_logic := '1';
    signal w_DATA : std_logic_vector (c_WIDTH-1 downto 0);
    signal w_READ_NEXT : std_logic := '0';
    signal w_TX_PORT : std_logic := '1';
    
    -- State name aliases
    constant c_IDLE : std_logic_vector(1 downto 0) := "00";
    constant c_REQUEST_READ : std_logic_vector(1 downto 0) := "01";
    constant c_CAPTURE_DATA : std_logic_vector(1 downto 0) := "10";
    constant c_TRANSMIT : std_logic_vector(1 downto 0) := "11";
begin

    -- port-to-register mappings 
    w_BUFFER_EMPTY <= i_buffer_empty;
    w_DATA <= i_data;
    o_read_en <= w_READ_NEXT;
    o_tx_port <= w_TX_PORT;

    p_WRITE_FRAME : process (i_clk) is
    begin
        if rising_edge (i_clk) then
            if i_reset = '1' then
                r_TX_FRAME <= (others => '0');
                r_BIT_COUNTER <= 0;
                r_CLK_COUNTER <= 0;
                r_STATE <= c_IDLE;
                w_READ_NEXT <= '0';
                w_TX_PORT <= '1';
            else
                case r_STATE is
                    when c_TRANSMIT => -- transmitting
                        if r_CLK_COUNTER = 0 then
                            -- lets try writing this one with shift registers as well
                            
                            w_TX_PORT <= r_TX_FRAME(0);
                            r_TX_FRAME(c_FRAME_END-1 downto 0) <= r_TX_FRAME(c_FRAME_END downto 1);
                            r_CLK_COUNTER <= r_CLK_COUNTER + 1;
                            
                            if r_BIT_COUNTER < c_FRAME_END then
                                r_BIT_COUNTER <= r_BIT_COUNTER + 1;
                            else
                                r_BIT_COUNTER <= 0;
                            end if;
                            
    --                        if r_POS_COUNTER = c_FRAME_END then
    --                            r_POS_COUNTER <= 0;  
    --                        else
    --                            r_POS_COUNTER <= r_POS_COUNTER + 1;
    --                        end if;
                            
    --                        w_TX_PORT <= r_TX_FRAME(r_POS_COUNTER);
    --                        r_CLK_COUNTER <= r_CLK_COUNTER + 1;
    
                        elsif r_CLK_COUNTER = c_CLKS_PER_BIT-1 then
                            if r_BIT_COUNTER = 0 then
                                r_STATE <= c_IDLE;
                            end if;
                            
                            r_CLK_COUNTER <= 0;
                            
                        else
                            r_CLK_COUNTER <= r_CLK_COUNTER + 1;
                        end if;
                        
                    when c_IDLE => -- idle
                        w_TX_PORT <= '1';
                            if w_BUFFER_EMPTY = '0' then
                                w_READ_NEXT <= '1';
                                r_STATE <= c_REQUEST_READ; --go to loading state
                            end if;
                            
                    -- needed to add this state due to the timings of buffer_empty and read_en
                    when c_REQUEST_READ =>
                        w_READ_NEXT <= '0';
                        r_BIT_COUNTER <= 0;
                        r_STATE <= c_CAPTURE_DATA;
                        
                    when c_CAPTURE_DATA => -- loading next data
                        r_TX_FRAME <= "1" & w_DATA & '0';
                        r_STATE <= c_TRANSMIT;
                    
                    when others => -- goes to idle
                        r_STATE <= c_IDLE;
                       
                end case; 
            
            end if;
        end if;
    end process p_WRITE_FRAME;
    
end Behavioral;
