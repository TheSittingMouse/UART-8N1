
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- clock is standard
-- I feel like I need to use some sort of a buffer and a first-in-first-out
-- queue. That would probably be a nice approach.
-- I would need to check if the fifo queue is full first before trying to write
-- in it. 

entity uart_rx is
    Generic (
        constant c_WIDTH : natural := 8;
        constant c_DEPTH : natural := 8;
        constant c_UART_BAUD : natural := 9600;
        constant c_CLK_FREQ : natural := 100_000_000
    );
    Port (
        i_clk : in std_logic;
        i_rst : in std_logic;
        i_read_en : in std_logic;
        i_rx_port : in std_logic;
        
        o_buffer_empty : out std_logic;
        o_rx_data : out std_logic_vector (c_WIDTH-1 downto 0)
    );
end uart_rx;

architecture Behavioral of uart_rx is
    signal w_WRITE_EN : std_logic := '0';
    signal w_BUFFER_FULL : std_logic := '0';
    signal w_RX_BYTE : std_logic_vector (c_WIDTH-1 downto 0) := (others => '0');
begin


    e_RX_FRAME_READER : entity work.rx_frame_reader
    generic map(
        c_WIDTH => c_WIDTH,
        c_UART_BAUD => c_UART_BAUD,
        c_CLK_FREQ => c_CLK_FREQ
    )
    port map (
        i_clk => i_clk,
        i_reset => i_rst,
        i_buffer_full => w_BUFFER_FULL,
        i_rx_port => i_rx_port,
        
        o_write_en => w_WRITE_EN,
        o_read_byte => w_RX_BYTE
    );


    e_FIFO : entity work.fifo_queue
    generic map(
        c_WIDTH => c_WIDTH,
        c_DEPTH => c_DEPTH
    )
    port map (
        i_clk => i_clk,
        i_read_en => i_read_en,
        i_write_en => w_WRITE_EN,
        i_write_data => w_RX_BYTE,
        i_reset => i_rst,
        
        o_read_data => o_rx_data,
        o_queue_full => w_BUFFER_FULL,
        o_queue_empty => o_buffer_empty
    );


end Behavioral;
