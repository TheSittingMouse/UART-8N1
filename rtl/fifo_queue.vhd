
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;


entity fifo_queue is
    Generic (
        -- each entry is 8 bits - one byte
        constant c_WIDTH : natural := 8;
        -- how many entries to store
        constant c_DEPTH : natural := 4
    );
    Port (
        i_clk : in std_logic;
        i_read_en : in std_logic;
        i_write_en : in std_logic;
        i_write_data : in std_logic_vector (c_WIDTH-1 downto 0);
        i_reset : in std_logic;
        
        o_read_data : out std_logic_vector (c_WIDTH-1 downto 0);
        o_queue_full : out std_logic;
        o_queue_empty : out std_logic 
    );
end fifo_queue;

architecture Behavioral of fifo_queue is

    -- short function for code clarity.
    function get_next_idx (current_idx : in natural) return natural is
        variable next_idx : natural;
    begin
        if current_idx = c_DEPTH-1 then
            next_idx := 0;
        else
            next_idx := current_idx + 1;
        end if;
    return next_idx;
    end function get_next_idx;
    
    type t_memory is array (natural range <>) of std_logic_vector (c_WIDTH-1 downto 0);
    signal r_QUEUE : t_memory(0 to c_DEPTH-1);
    
    signal r_READ_IDX : natural range 0 to c_DEPTH-1 := 0;
    signal r_WRITE_IDX : natural range 0 to c_DEPTH-1:= 0;
    signal r_IS_FULL : std_logic;
    signal r_IS_EMPTY : std_logic; 
    
    -- To keep track of if the queue is full or empty.
    signal r_NUM_ITEMS : integer range 0 to c_DEPTH := 0;  
begin

    -- combinational flag assignments.
    r_IS_EMPTY <= '1' when (r_NUM_ITEMS = 0) else '0';
    r_IS_FULL <= '1' when (r_NUM_ITEMS = c_DEPTH) else '0';
    
    p_READ_WRITE : process (i_clk) is
    begin
        if rising_edge (i_clk) then    
            if (i_reset = '1') then
                r_READ_IDX <= 0;
                r_WRITE_IDX <= 0;
                r_NUM_ITEMS <= 0;
                o_read_data <= (others => '0');
            else  
                -- Read logic
                if (i_read_en = '1' and i_write_en = '0' and r_IS_EMPTY = '0') then
                    o_read_data <= r_queue(r_READ_IDX);
                    
                    r_READ_IDX <= get_next_idx(r_READ_IDX);
                    r_NUM_ITEMS <= r_NUM_ITEMS - 1;
                                    
                -- Write logic
                elsif (i_write_en = '1' and i_read_en = '0' and r_IS_FULL = '0') then
                    r_queue(r_WRITE_IDX) <= i_write_data;
                    
                    r_WRITE_IDX <= get_next_idx(r_WRITE_IDX);
                    r_NUM_ITEMS <= r_NUM_ITEMS + 1;
                    
                -- Simultaneous read/write logic
                elsif (i_write_en = '1' and i_read_en = '1' and (r_IS_FULL = '0' and r_IS_EMPTY = '0')) then
                    o_read_data <= r_queue(r_READ_IDX);
                    r_queue(r_WRITE_IDX) <= i_write_data;
                    
                    r_READ_IDX <= get_next_idx(r_READ_IDX);
                    r_WRITE_IDX <= get_next_idx(r_WRITE_IDX);
                    
                elsif (i_write_en = '1' and i_read_en = '1' and r_IS_EMPTY = '1') then
                    -- Since both read and write indexes are the same, a different case is needed.
                    -- No need to change the index counters.
                    o_read_data <= i_write_data;
                    
                elsif (i_write_en = '1' and i_read_en = '1' and r_IS_FULL = '1') then
                    -- We dont expect to see write_en when the buffer is full.
                    -- A comprimize is made and the last data is droped.
                    -- Would need an output register to make this work.
                    o_read_data <= r_queue(r_READ_IDX);
                    
                    r_READ_IDX <= get_next_idx(r_READ_IDX);
                    r_NUM_ITEMS <= r_NUM_ITEMS - 1;
                
                end if;
            end if;   
        end if;
    end process p_READ_WRITE;
    
    o_queue_full <= r_IS_FULL;
    o_queue_empty <= r_IS_EMPTY;

end Behavioral;
