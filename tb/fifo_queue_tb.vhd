
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity fifo_queue_tb is
end fifo_queue_tb;

architecture Behavioral of fifo_queue_tb is

    constant c_DEPTH : natural := 4;
    constant c_WIDTH : natural := 8;

    signal r_CLK : std_logic := '0';
    signal r_READ_EN : std_logic := '0';
    signal r_WRITE_EN : std_logic := '0';
    signal r_RST : std_logic := '0';
    signal r_WRITE_DATA : std_logic_vector (c_WIDTH-1 downto 0) := (others => '0');
    
    signal r_READ_DATA : std_logic_vector (c_WIDTH-1 downto 0) := (others => '0');
    signal r_IS_FULL : std_logic := '0';
    signal r_IS_EMPTY : std_logic := '0';  
begin
 
    p_CLK : process 
    begin
        r_CLK <= '0';
        wait for 5 ns;
        r_CLK <= '1';
        wait for 5 ns;
    end process p_CLK;

    UUT : entity work.fifo_queue
    generic map (
        c_WIDTH => c_WIDTH,
        c_DEPTH => c_DEPTH
    )
    port map (
        i_clk => r_CLK,
        i_read_en => r_READ_EN,
        i_write_en => r_WRITE_EN,
        i_write_data => r_WRITE_DATA,
        i_reset => r_RST,
        
        o_read_data => r_READ_DATA,
        o_queue_full => r_IS_FULL,
        o_queue_empty => r_IS_EMPTY
    );
    
    
    p_TEST_BENCH : process is
        procedure p_tick_n(constant n : positive) is
        begin
            for i in 1 to n loop
                wait until rising_edge(r_CLK);
                wait for 1 ns;
            end loop;
        end procedure p_tick_n;
    
        procedure p_RESET is
        begin
            p_tick_n(1);
            r_READ_EN <= '0';
            r_WRITE_EN <= '0';
            r_WRITE_DATA <= (others => '0');
            r_RST <= '1';
            p_tick_n(3);
            r_RST <= '0';
            
            assert (r_IS_FULL = '0' and r_IS_EMPTY = '1' and r_READ_DATA = x"00")
                report "Reset behavior is wrong."
                severity failure;
            p_tick_n(1);
        end p_RESET;
        
        
        procedure p_INIT is
        begin
            report "TEST: INITIALIZATION";
            -- initialization behaviour
            p_tick_n(1);
            r_READ_EN <= '0';
            r_WRITE_EN <= '0';
            r_WRITE_DATA <= (others => '0');
            r_RST <= '0';
            
            --wait until rising_edge (r_CLK);
            p_tick_n(1);
            assert r_IS_FULL = '0' and r_IS_EMPTY = '1'
                report "Initial full/empty flags do not work."
                severity failure;
        end p_INIT;
        
        
        procedure p_WRITE_EN is
        begin
            report "TEST: WRITE WITH/WITHOUT WRITE_EN";
            p_RESET;            
            
            r_WRITE_DATA <= x"44";
    
            p_tick_n(1);
            assert r_IS_FULL = '0' and r_IS_EMPTY = '1'
                report "Writing without write enable signal"
                severity failure;
                
            r_WRITE_EN <= '1';
            
            -- Now, with write enable signal
            p_tick_n(1);    
            assert r_IS_FULL = '0' and r_IS_EMPTY = '0'
                report "Not writing with the enable signal"
                severity failure;        
            report "SUCCESS";        
        end p_WRITE_EN;
        
        
        procedure p_READ_EN is
        begin
            report "TEST: READ WITH/WITHOUT READ_EN";
            p_RESET;
            
            r_WRITE_EN <= '1';
            r_WRITE_DATA <= x"f8";
            
            p_tick_n(1);
            r_WRITE_EN <= '0';
            
            p_tick_n(1);
            assert r_READ_DATA = x"00"
                report "There shouldn't be read data without read_en"
                severity failure;
               
            r_READ_EN <= '1';
            
            p_tick_n(1);
            r_READ_EN <= '0';
            
            assert r_READ_DATA = x"f8"
                report "Not reading with read_en"
                severity failure;
            report "SUCCESS";
        end p_READ_EN;
            
        
        procedure p_SIMPLE_READ_WRITE is
        begin
            report "TEST: SIMPLE READ/WRITE";
            p_RESET;
                        
            r_WRITE_EN <= '1';
            r_WRITE_DATA <= x"3a";
            
            p_tick_n(1);
            r_WRITE_EN <= '0';
            r_READ_EN <= '1';
            
            p_tick_n(1);
            r_READ_EN <= '0';
            
            assert r_READ_DATA = x"3a"
                report "Simple read/write doesn't work."
                severity failure;   
            report "SUCCESS";             
        end p_SIMPLE_READ_WRITE;
    
    
        procedure p_READ_FROM_EMPTY_WRITE_TO_FULL is
        begin
            report "TEST: READ WHEN EMPTY / WRITE WHEN FULL";
            p_RESET;
            -- first fill the queue to make useful observations.
            r_WRITE_EN <= '1';
            for i in 1 to c_DEPTH loop
                r_WRITE_DATA <= std_logic_vector(to_unsigned(i, 8));
                p_tick_n(1);
            end loop;
            
            r_WRITE_EN <= '0';
            assert r_IS_FULL = '1'
                report "Queue should have been full"
                severity failure;
                
            p_tick_n(1);
            r_WRITE_EN <= '1';
            r_WRITE_DATA <= x"4d"; --this shouldnt write
            
            p_Tick_n(1);
            
            r_WRITE_EN <= '0';
            r_READ_EN <= '1';    
            p_tick_n(1);
            for i in 1 to c_DEPTH loop
                assert r_READ_DATA = std_logic_vector(to_unsigned(i, 8))
                    report "Unexpected data has been read"
                    severity failure;
                p_tick_n(1);
            end loop;
            
            -- trying to read again. The buffer should be empty            
            assert r_IS_EMPTY = '1'
                report "Buffer should have been empty"
                severity failure;
                
            -- Read_en is still on. But the value shouldnt update and stay the same as last.
            assert r_READ_DATA = std_logic_vector(to_unsigned(c_DEPTH, 8))
                report "Last value should have retained"
                severity failure;
            report "SUCCESS";
        end p_READ_FROM_EMPTY_WRITE_TO_FULL;
    
    
        procedure p_BOTH_READ_WRITE_NO_FLAGS is
        begin
            report "TEST: BOTH READ AND WRITE IS ON / NOT EMPTY OR FULL";
            p_RESET;
            
            -- adding something so that it is neither full nor empty
            r_WRITE_DATA <= x"9c";
            r_WRITE_EN <= '1';
            
            p_tick_n(1);
            assert r_IS_EMPTY = '0' and r_IS_FULL = '0'
                report "Expecting the queue to not be empty"
                severity failure;
                
            r_READ_EN <= '1';
            -- changing the next value for clarity.
            r_WRITE_DATA <= x"97";

            p_tick_n(1);
            -- Now both read/write are on. Expecting to see the last element
            assert r_READ_DATA = x"9c"
                report "Couldnt read the first element written"
                severity failure;
            
            p_tick_n(1);
            assert r_READ_DATA = x"97"
                report "Couldnt read the second element written"
                severity failure;
            report "SUCCESS";
        end p_BOTH_READ_WRITE_NO_FLAGS;
        
        
        procedure p_BOTH_READ_WRITE_EMPTY is
        begin
            report "TEST: READ WHEN EMPTY / WRITE WHEN EMPTY";
            p_RESET;
        
            r_WRITE_DATA <= x"d2";
            r_READ_EN <= '1';
            r_WRITE_EN <= '1';
            
            p_tick_n(1);
            -- expecting to see the data just be sent through;
            assert r_READ_DATA = x"d2"
                report "Both RW doesnt work when empty"
                severity failure;
                
            assert r_IS_EMPTY = '1'
                report "Shouldnt have changed the storage"
                severity failure;   
            report "SUCCESS";             
        end p_BOTH_READ_WRITE_EMPTY;
        
        
        procedure p_BOTH_READ_WRITE_FULL is
        begin
            report "TEST: BOTH READ / WRITE WHEN FULL";
            p_RESET;
            -- first fill the queue to make useful observations.
            r_WRITE_EN <= '1';
            for i in 1 to c_DEPTH loop
                r_WRITE_DATA <= std_logic_vector(to_unsigned(i, 8));
                p_tick_n(1);
            end loop;
            r_WRITE_EN <= '0';
            
            assert r_IS_FULL = '1'
                report "Expecting queue to be full"
                severity failure;
                
            p_tick_n(1);
            
            r_WRITE_EN <= '1';
            r_READ_EN <= '1';
            
            p_tick_n(1);
            assert r_READ_DATA = std_logic_vector(to_unsigned(1, 8))
                report "Couldnt read the first element"
                severity failure;
            
            assert r_IS_EMPTY = '0' and r_IS_FULL = '0'
                report "Expected non-full"
                severity failure;
            report "SUCCESS";
        end p_BOTH_READ_WRITE_FULL;
    
    begin
    
        p_INIT;
        p_WRITE_EN;
        p_READ_EN;
        p_SIMPLE_READ_WRITE;
        p_READ_FROM_EMPTY_WRITE_TO_FULL;
        p_BOTH_READ_WRITE_NO_FLAGS;
        p_BOTH_READ_WRITE_EMPTY;
        p_BOTH_READ_WRITE_FULL;
        p_RESET;
        
        assert false report "ALL TESTS PASSED" severity failure;
        
--    -- lets fill the queue
--    p_tick(r_CLK);
--    r_WRITE_DATA <= "00000001";
--    r_WRITE_EN <= '1';
--    p_tick(r_CLK);
--    r_WRITE_DATA <= "00000011";
--    p_tick(r_CLK);
--    r_WRITE_DATA <= "00000111";
--    p_tick(r_CLK);
--    r_WRITE_DATA <= "00001111";
--    p_tick(r_CLK); -- now we expect the queue to be full
--    r_WRITE_DATA <= "11110000"; -- this should not write.
    
--    p_tick(r_CLK);
--    assert (r_IS_FULL = '1' and r_IS_EMPTY = '0')
--        report "It should have been full by now"
--        severity failure;
    
--    r_WRITE_EN <= '0';
--    r_READ_EN <= '1';
    
--    -- lets see what is written inside now.
--    p_tick(r_CLK); -- r_READ_EN = 1 is registered, the data will be read.
--    assert r_READ_DATA = "00000001"
--        report "Reading the first data failed"
--        severity failure;

--    p_tick(r_CLK);
--    assert r_READ_DATA = "00000011"
--        report "Reading the second data failed"
--        severity failure;

--    p_tick(r_CLK);
--    -- turn the read enable off
--    assert r_READ_DATA = "00000111"
--        report "Reading the third data failed"
--        severity failure;
--    --wait until rising_edge (r_CLK);
--    p_tick(r_CLK);
--    assert r_READ_DATA = "00001111"
--        report "Reading the fourth data failed"
--        severity failure;
        
--    r_READ_EN <= '0';
    
--    p_tick(r_CLK);
--    -- write something arbitrary
--    r_WRITE_DATA <= "10101010";
--    r_WRITE_EN <= '1';
    
--    p_tick(r_CLK); -- r_WRITE_EN = 1, write will happen next cycle.
--    r_WRITE_DATA <= "01100110"; -- writing something arbitrary.
--    r_READ_EN <= '1';
    
--    p_tick(r_CLK);
--    assert r_READ_DATA = "10101010"
--        report "Expected to read 10101010."
--        severity failure;
        
--    assert (r_IS_FULL = '0' and r_IS_EMPTY = '0')
--        report "Simultaneous read-write doesnt work"
--        severity failure;
        
--    r_WRITE_EN <= '0';
    
--    p_tick(r_CLK);
--    assert r_READ_DATA = "01100110"
--        report "Expected to read 01100110."
--        severity failure;
        
--    r_READ_EN <= '0';
        
--    p_tick(r_CLK);
--    -- reset and confirm functionality
--    r_RST <= '1';
    
--    p_tick(r_CLK); --r_RST = 1 now.
--    assert (r_IS_FULL = '0' and r_IS_EMPTY = '1')
--        report "Final reset failed."
--        severity failure;
    
--    r_RST <= '0';
    
--    p_tick(r_CLK);
--    report "SUCCESS";
--    wait;
    
    end process p_TEST_BENCH;
end Behavioral;
