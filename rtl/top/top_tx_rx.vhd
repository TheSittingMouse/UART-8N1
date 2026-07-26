
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;


entity top_rx_tx is
    Generic (
        constant c_DEBOUNCE_CYCLES : natural := 1048575;
        constant c_WIDTH : natural := 8;
        constant c_DEPTH : natural := 8;
        constant c_UART_BAUD : natural := 9600;
        constant c_CLK_FREQ : natural := 100_000_000
    );
    Port (
        i_clk : in std_logic;
        i_btn_rst : in std_logic;
        i_btn_send : in std_logic;
        i_btn_recv : in std_logic;
        i_switch_data : in std_logic_vector(c_WIDTH-1 downto 0);
        i_rx_port : in std_logic;
        
        o_led_tx_data : out std_logic_vector(c_WIDTH-1 downto 0);
        o_led_rx_data : out std_logic_vector(c_WIDTH-1 downto 0);
        o_tx_port : out std_logic
    );
end top_rx_tx;


architecture Behavioral of top_rx_tx is
    
    subtype t_std_byte is std_logic_vector(c_WIDTH-1 downto 0);
    
    signal w_RST_PULSE : std_logic;
    signal w_WRITE_EN_PULSE : std_logic;
    signal w_READ_EN_PULSE : std_logic;
    
    signal r_SWITCH_DATA_SYNC_2 : t_std_byte := (others => '0');
    signal r_SWITCH_DATA_SYNC_1 : t_std_byte := (others => '0');
    
    signal r_RX_SYNC_2 : std_logic := '0';
    signal r_RX_SYNC_1 : std_logic := '0';
begin

    e_UART_TX : entity work.uart_tx
    generic map (
        c_WIDTH => c_WIDTH,
        c_DEPTH => c_DEPTH,
        c_UART_BAUD => c_UART_BAUD,
        c_CLK_FREQ => c_CLK_FREQ
    )
    port map (
        i_clk => i_clk,
        i_rst => w_RST_PULSE,
        i_write_en => w_WRITE_EN_PULSE,
        i_tx_write_data => r_SWITCH_DATA_SYNC_2,
        
        o_buffer_full => open,
        o_tx_port => o_tx_port
    );
    
    
    e_UART_RX : entity work.uart_rx
    generic map (
        c_WIDTH => c_WIDTH,
        c_DEPTH => c_DEPTH,
        c_UART_BAUD => c_UART_BAUD,
        c_CLK_FREQ => c_CLK_FREQ
    )
    port map (
        i_clk => i_clk,
        i_rst => w_RST_PULSE,
        i_read_en => w_READ_EN_PULSE,
        i_rx_port => r_RX_SYNC_2,
        o_buffer_empty => open,
        o_rx_data => o_led_rx_data
    );
    
    
    e_BTN_RST : entity work.button_debouncer
    generic map (
        c_DEBOUNCE_CYCLES => c_DEBOUNCE_CYCLES
    )
    Port map (
        i_clk => i_clk,
        i_rst => '0',
        i_btn_raw => i_btn_rst,
        
        o_debounced => open,
        o_single_clk_pulse => w_RST_PULSE
    );
    
    
    e_BTN_RECV : entity work.button_debouncer
    generic map (
        c_DEBOUNCE_CYCLES => c_DEBOUNCE_CYCLES
    )
    Port map (
        i_clk => i_clk,
        i_rst => '0',
        i_btn_raw => i_btn_recv,
        
        o_debounced => open,
        o_single_clk_pulse => w_READ_EN_PULSE
    );
    
    
    e_BTN_SEND : entity work.button_debouncer
    generic map (
        c_DEBOUNCE_CYCLES => c_DEBOUNCE_CYCLES
    )
    Port map (
        i_clk => i_clk,
        i_rst => '0',
        i_btn_raw => i_btn_send,
        
        o_debounced => open,
        o_single_clk_pulse => w_WRITE_EN_PULSE
    );
    
    
    
    o_led_tx_data <= r_SWITCH_DATA_SYNC_2;
    
    p_SWITCH_SYNC : process(i_clk) is
    begin
        if rising_edge(i_clk) then
            r_SWITCH_DATA_SYNC_1 <= i_switch_data;
            r_SWITCH_DATA_SYNC_2 <= r_SWITCH_DATA_SYNC_1;
        end if;
    end process p_SWITCH_SYNC;
    
    p_RX_SYNC : process(i_clk) is
    begin
        if rising_edge(i_clk) then
            r_RX_SYNC_2 <= r_RX_SYNC_1;
            r_RX_SYNC_1 <= i_rx_port;
        end if;
    end process p_RX_SYNC;


end Behavioral;
