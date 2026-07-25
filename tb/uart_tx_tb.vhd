library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity uart_tx_tb is
end uart_tx_tb;

architecture Behavioral of uart_tx_tb is

    constant c_WIDTH : natural := 8;
    constant c_DEPTH : natural := 4;
    constant c_CLK_FREQ : natural := 100_000_000;
    constant c_UART_BAUD : natural := 5_000_000;

    constant c_CLK_PERIOD : time := 10 ns;
    constant c_CLK_HALF_PERIOD : time := 5 ns;

    constant c_CLKS_PER_BIT : natural := c_CLK_FREQ / c_UART_BAUD;
    constant c_HALF_BIT_TICKS : positive := c_CLKS_PER_BIT / 2;

    constant c_START_TIMEOUT_TICKS : positive := 8 * c_CLKS_PER_BIT;
    constant c_IDLE_CHECK_TICKS : positive := 4 * c_CLKS_PER_BIT;

    signal r_CLK : std_logic := '0';
    signal r_RESET : std_logic := '0';
    signal r_WRITE_EN : std_logic := '0';
    signal r_TX_WRITE_DATA : std_logic_vector(c_WIDTH-1 downto 0) := (others => '0');

    signal r_BUFFER_FULL : std_logic := '0';
    signal r_TX_PORT : std_logic := '1';

begin

    p_CLK : process
    begin
        r_CLK <= '0';
        wait for c_CLK_HALF_PERIOD;
        r_CLK <= '1';
        wait for c_CLK_HALF_PERIOD;
    end process p_CLK;


    UUT : entity work.uart_tx
    generic map(
        c_WIDTH => c_WIDTH,
        c_DEPTH => c_DEPTH,
        c_UART_BAUD => c_UART_BAUD,
        c_CLK_FREQ => c_CLK_FREQ
    )
    port map(
        i_clk => r_CLK,
        i_rst => r_RESET,
        i_write_en => r_WRITE_EN,
        i_tx_write_data => r_TX_WRITE_DATA,

        o_buffer_full => r_BUFFER_FULL,
        o_tx_port => r_TX_PORT
    );


    p_TEST_BENCH : process is

        procedure p_tick_n(constant n : positive) is
        begin
            for i in 1 to n loop
                wait until rising_edge(r_CLK);
                wait for 1 ns;
            end loop;
        end procedure p_tick_n;


        procedure p_PREPARE_IDLE is
        begin
            r_WRITE_EN <= '0';
            r_TX_WRITE_DATA <= (others => '0');
            r_RESET <= '1';
            p_tick_n(3);
            r_RESET <= '0';
            p_tick_n(2);

            assert r_TX_PORT = '1'
                report "TX line should be high after reset."
                severity failure;

            assert r_BUFFER_FULL = '0'
                report "TX FIFO should not be full after reset."
                severity failure;
        end p_PREPARE_IDLE;


        procedure p_WRITE_BYTE(constant data_to_write : std_logic_vector(c_WIDTH-1 downto 0);
                               constant test_name : string) is
        begin
            assert r_RESET = '0'
                report test_name & ": attempted to write while reset was active."
                severity failure;

            r_TX_WRITE_DATA <= data_to_write;
            r_WRITE_EN <= '1';
            p_tick_n(1);
            r_WRITE_EN <= '0';
        end p_WRITE_BYTE;


        procedure p_WAIT_FOR_START_BIT(constant test_name : string) is
            variable v_found : boolean := false;
        begin
            for i in 1 to c_START_TIMEOUT_TICKS loop
                if r_TX_PORT = '0' then
                    v_found := true;
                    exit;
                end if;

                p_tick_n(1);
            end loop;

            assert v_found
                report test_name & ": TX never produced a start bit."
                severity failure;
        end p_WAIT_FOR_START_BIT;


        procedure p_RECEIVE_FRAME_AFTER_START_FOUND(constant expected_data : std_logic_vector(c_WIDTH-1 downto 0);
                                                    constant elapsed_start_ticks : natural;
                                                    constant test_name : string) is
        begin
            assert elapsed_start_ticks < c_HALF_BIT_TICKS
                report test_name & ": test bench missed the middle of the start bit."
                severity failure;

            if elapsed_start_ticks < c_HALF_BIT_TICKS then
                p_tick_n(c_HALF_BIT_TICKS - elapsed_start_ticks);
            end if;

            assert r_TX_PORT = '0'
                report test_name & ": start bit should be 0."
                severity failure;

            for bit_index in 0 to c_WIDTH-1 loop
                p_tick_n(c_CLKS_PER_BIT);
                assert r_TX_PORT = expected_data(bit_index)
                    report test_name & ": received data bit mismatch."
                    severity failure;
            end loop;

            p_tick_n(c_CLKS_PER_BIT);
            assert r_TX_PORT = '1'
                report test_name & ": stop bit should be 1."
                severity failure;
        end p_RECEIVE_FRAME_AFTER_START_FOUND;


        procedure p_RECEIVE_BYTE(constant expected_data : std_logic_vector(c_WIDTH-1 downto 0);
                                 constant test_name : string) is
        begin
            p_WAIT_FOR_START_BIT(test_name);
            p_RECEIVE_FRAME_AFTER_START_FOUND(expected_data, 0, test_name);
        end p_RECEIVE_BYTE;


        procedure p_WRITE_AND_EXPECT_FRAME(constant data_to_write : std_logic_vector(c_WIDTH-1 downto 0);
                                           constant test_name : string) is
        begin
            p_WRITE_BYTE(data_to_write, test_name);
            p_RECEIVE_BYTE(data_to_write, test_name);
        end p_WRITE_AND_EXPECT_FRAME;


        procedure p_FINISH_FRAME_AND_ASSERT_IDLE(constant test_name : string) is
        begin
            -- p_RECEIVE_BYTE returns around the middle of the stop bit. Let the
            -- stop bit finish and allow the writer to return to idle.
            p_tick_n(c_CLKS_PER_BIT + 3);

            assert r_TX_PORT = '1'
                report test_name & ": TX line should return to idle high after frame."
                severity failure;
        end p_FINISH_FRAME_AND_ASSERT_IDLE;


        procedure p_ASSERT_TX_IDLE_FOR(constant n : positive;
                                       constant test_name : string) is
        begin
            for i in 1 to n loop
                p_tick_n(1);

                assert r_TX_PORT = '1'
                    report test_name & ": TX line went low although no frame was expected."
                    severity failure;
            end loop;
        end p_ASSERT_TX_IDLE_FOR;


        procedure p_INIT is
        begin
            report "TEST: INITIALIZATION / IDLE";
            p_PREPARE_IDLE;
            p_ASSERT_TX_IDLE_FOR(c_IDLE_CHECK_TICKS, "Initialization idle check");
            report "SUCCESS";
        end p_INIT;


        procedure p_SINGLE_ZERO_BYTE is
        begin
            report "TEST: UART_TX TRANSMITS 0x00";
            p_PREPARE_IDLE;
            p_WRITE_AND_EXPECT_FRAME(x"00", "UART_TX transmit 0x00");
            p_FINISH_FRAME_AND_ASSERT_IDLE("UART_TX transmit 0x00");
            report "SUCCESS";
        end p_SINGLE_ZERO_BYTE;


        procedure p_SINGLE_ALL_ONES is
        begin
            report "TEST: UART_TX TRANSMITS 0xFF";
            p_PREPARE_IDLE;
            p_WRITE_AND_EXPECT_FRAME(x"FF", "UART_TX transmit 0xFF");
            p_FINISH_FRAME_AND_ASSERT_IDLE("UART_TX transmit 0xFF");
            report "SUCCESS";
        end p_SINGLE_ALL_ONES;


        procedure p_MIXED_PATTERN is
        begin
            report "TEST: UART_TX TRANSMITS MIXED PATTERN";
            p_PREPARE_IDLE;
            p_WRITE_AND_EXPECT_FRAME(x"A6", "UART_TX transmit 0xA6");
            p_FINISH_FRAME_AND_ASSERT_IDLE("UART_TX transmit 0xA6");
            report "SUCCESS";
        end p_MIXED_PATTERN;


        procedure p_LSB_FIRST_ORDER is
        begin
            report "TEST: UART_TX LSB-FIRST BIT ORDER";
            p_PREPARE_IDLE;

            -- 0x80 catches a transmitter that accidentally sends MSB-first.
            p_WRITE_AND_EXPECT_FRAME(x"80", "UART_TX LSB-first check");
            p_FINISH_FRAME_AND_ASSERT_IDLE("UART_TX LSB-first check");

            report "SUCCESS";
        end p_LSB_FIRST_ORDER;


        procedure p_FIFO_PRESERVES_WRITE_ORDER is
        begin
            report "TEST: UART_TX FIFO PRESERVES WRITE ORDER";
            p_PREPARE_IDLE;

            -- These writes happen much faster than one UART frame. The wrapper
            -- should buffer them and the frame writer should transmit them in
            -- the same order.
            p_WRITE_BYTE(x"12", "FIFO order write 0");
            p_WRITE_BYTE(x"34", "FIFO order write 1");
            p_WRITE_BYTE(x"56", "FIFO order write 2");

            p_RECEIVE_BYTE(x"12", "FIFO order first frame");
            p_RECEIVE_BYTE(x"34", "FIFO order second frame");
            p_RECEIVE_BYTE(x"56", "FIFO order third frame");
            p_FINISH_FRAME_AND_ASSERT_IDLE("FIFO order check");

            report "SUCCESS";
        end p_FIFO_PRESERVES_WRITE_ORDER;


        procedure p_NO_EXTRA_FRAME_AFTER_FIFO_EMPTY is
        begin
            report "TEST: UART_TX NO EXTRA FRAME AFTER FIFO BECOMES EMPTY";
            p_PREPARE_IDLE;

            p_WRITE_BYTE(x"7E", "No-extra-frame write");
            p_RECEIVE_BYTE(x"7E", "No-extra-frame received frame");
            p_FINISH_FRAME_AND_ASSERT_IDLE("No-extra-frame check");
            p_ASSERT_TX_IDLE_FOR(c_CLKS_PER_BIT * 4, "No-extra-frame idle check");

            report "SUCCESS";
        end p_NO_EXTRA_FRAME_AFTER_FIFO_EMPTY;


        procedure p_BUFFER_FULL_REJECTS_EXTRA_WRITE is
            constant c_ELAPSED_TICKS_AFTER_START : natural := c_DEPTH + 1;
        begin
            report "TEST: UART_TX BUFFER_FULL AND WRITE WHILE FULL";
            p_PREPARE_IDLE;

            -- First byte is moved from the FIFO into the frame writer. While it
            -- is being transmitted, fill the FIFO completely from the public TX
            -- write interface.
            p_WRITE_BYTE(x"10", "Full-buffer first byte");
            p_WAIT_FOR_START_BIT("Full-buffer first byte");

            p_WRITE_BYTE(x"20", "Full-buffer queued byte 0");
            p_WRITE_BYTE(x"21", "Full-buffer queued byte 1");
            p_WRITE_BYTE(x"22", "Full-buffer queued byte 2");
            p_WRITE_BYTE(x"23", "Full-buffer queued byte 3");

            assert r_BUFFER_FULL = '1'
                report "Full-buffer check: o_buffer_full should assert when the FIFO is full."
                severity failure;

            -- This byte is presented while full is already high. It should not
            -- appear later on the serial line.
            p_WRITE_BYTE(x"EE", "Full-buffer ignored byte");

            assert r_BUFFER_FULL = '1'
                report "Full-buffer check: FIFO should still be full after ignored write."
                severity failure;

            p_RECEIVE_FRAME_AFTER_START_FOUND(x"10", c_ELAPSED_TICKS_AFTER_START,
                                              "Full-buffer first transmitted frame");
            p_RECEIVE_BYTE(x"20", "Full-buffer queued frame 0");
            p_RECEIVE_BYTE(x"21", "Full-buffer queued frame 1");
            p_RECEIVE_BYTE(x"22", "Full-buffer queued frame 2");
            p_RECEIVE_BYTE(x"23", "Full-buffer queued frame 3");

            p_FINISH_FRAME_AND_ASSERT_IDLE("Full-buffer check");
            p_ASSERT_TX_IDLE_FOR(c_CLKS_PER_BIT * 12, "Full-buffer ignored-byte check");

            report "SUCCESS";
        end p_BUFFER_FULL_REJECTS_EXTRA_WRITE;


        procedure p_RESET_MID_TRANSMIT_CLEARS_FIFO_AND_RECOVERS is
        begin
            report "TEST: UART_TX RESET MID-TRANSMIT CLEARS OLD DATA AND RECOVERS";
            p_PREPARE_IDLE;

            p_WRITE_BYTE(x"A5", "Reset-mid-transmit old byte");
            p_WRITE_BYTE(x"5A", "Reset-mid-transmit queued old byte");

            p_WAIT_FOR_START_BIT("Reset-mid-transmit interrupted frame");
            p_tick_n(c_CLKS_PER_BIT + c_HALF_BIT_TICKS);

            r_RESET <= '1';
            p_tick_n(3);

            assert r_TX_PORT = '1'
                report "Reset-mid-transmit check: TX should return high during reset."
                severity failure;

            assert r_BUFFER_FULL = '0'
                report "Reset-mid-transmit check: FIFO should not be full during reset."
                severity failure;

            r_RESET <= '0';
            p_tick_n(3);

            p_ASSERT_TX_IDLE_FOR(c_CLKS_PER_BIT * 2,
                                 "Reset-mid-transmit old-data cleared check");

            p_WRITE_AND_EXPECT_FRAME(x"3C", "Recovery after reset mid-transmit");
            p_FINISH_FRAME_AND_ASSERT_IDLE("Recovery after reset mid-transmit");

            report "SUCCESS";
        end p_RESET_MID_TRANSMIT_CLEARS_FIFO_AND_RECOVERS;

    begin
        assert c_CLKS_PER_BIT >= 2
            report "c_CLKS_PER_BIT must be at least 2 for middle-of-bit sampling."
            severity failure;

        assert c_HALF_BIT_TICKS > c_DEPTH + 1
            report "c_HALF_BIT_TICKS must be greater than c_DEPTH + 1 for the full-buffer test."
            severity failure;

        p_INIT;
        p_SINGLE_ZERO_BYTE;
        p_SINGLE_ALL_ONES;
        p_MIXED_PATTERN;
        p_LSB_FIRST_ORDER;
        p_FIFO_PRESERVES_WRITE_ORDER;
        p_NO_EXTRA_FRAME_AFTER_FIFO_EMPTY;
        p_BUFFER_FULL_REJECTS_EXTRA_WRITE;
        p_RESET_MID_TRANSMIT_CLEARS_FIFO_AND_RECOVERS;

        assert false report "ALL TESTS PASSED" severity failure;
    end process p_TEST_BENCH;

end Behavioral;
