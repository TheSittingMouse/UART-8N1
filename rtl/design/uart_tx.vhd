
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- clock is standard
-- I feel like I need to use some sort of a buffer and a first-in-first-out
-- queue. That would probably be a nice approach.
-- I would need to check if the fifo queue is full first before trying to write
-- in it. 

entity uart_tx is
    Generic (
        constant c_WIDTH : natural := 8;
        constant c_DEPTH : natural := 8;
        constant c_UART_BAUD : natural := 9600;
        constant c_CLK_FREQ : natural := 100_000_000
    );
    Port (
        i_clk : in std_logic;
        i_rst : in std_logic;
        i_write_en : in std_logic;
        i_tx_write_data : in std_logic_vector (7 downto 0);
        
        o_buffer_full : out std_logic;
        o_tx_port : out std_logic
    );
end uart_tx;

architecture Behavioral of uart_tx is
    signal w_READ_EN : std_logic := '0';
    signal w_BUFFER_EMPTY : std_logic := '0';
    signal w_READ_DATA : std_logic_vector (c_WIDTH-1 downto 0) := (others => '0');
begin


    e_TX_FRAME_WRITER : entity work.tx_frame_writer
    generic map(
        c_WIDTH => c_WIDTH,
        c_UART_BAUD => c_UART_BAUD,
        c_CLK_FREQ => c_CLK_FREQ
    )
    port map (
        i_clk => i_clk,
        i_reset => i_rst,
        i_buffer_empty => w_BUFFER_EMPTY,
        i_data => w_READ_DATA,
        
        o_read_en => w_READ_EN,
        o_tx_port => o_tx_port
    );


    e_FIFO : entity work.fifo_queue
    generic map(
        c_WIDTH => c_WIDTH,
        c_DEPTH => c_DEPTH
    )
    port map (
        i_clk => i_clk,
        i_read_en => w_READ_EN,
        i_write_en => i_write_en,
        i_write_data => i_tx_write_data,
        i_reset => i_rst,
        
        o_read_data => w_READ_DATA,
        o_queue_full => o_buffer_full,
        o_queue_empty => w_BUFFER_EMPTY
    );


end Behavioral;
