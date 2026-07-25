library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity uart_rx_tb is
end uart_rx_tb;

architecture Behavioral of uart_rx_tb is

    constant c_WIDTH : natural := 8;
    constant c_DEPTH : natural := 4;
    constant c_CLK_FREQ : natural := 100_000_000;
    constant c_UART_BAUD : natural := 5_000_000;

    constant c_CLK_PERIOD : time := 10 ns;
    constant c_CLK_HALF_PERIOD : time := 5 ns;

    constant c_CLKS_PER_BIT : natural := c_CLK_FREQ / c_UART_BAUD;
    constant c_HALF_BIT_TICKS : positive := c_CLKS_PER_BIT / 2;

    constant c_STOP_SAMPLE_TICKS : positive := c_HALF_BIT_TICKS + 1;
    constant c_DATA_TIMEOUT_TICKS : positive := 4 * c_CLKS_PER_BIT;
    constant c_IDLE_CHECK_TICKS : positive := 4 * c_CLKS_PER_BIT;

    signal r_CLK : std_logic := '0';
    signal r_RESET : std_logic := '0';
    signal r_READ_EN : std_logic := '0';
    signal r_RX_PORT : std_logic := '1';

    signal r_BUFFER_EMPTY : std_logic := '1';
    signal r_RX_DATA : std_logic_vector(c_WIDTH-1 downto 0) := (others => '0');

begin

    p_CLK : process
    begin
        r_CLK <= '0';
        wait for c_CLK_HALF_PERIOD;
        r_CLK <= '1';
        wait for c_CLK_HALF_PERIOD;
    end process p_CLK;


    UUT : entity work.uart_rx
    generic map(
        c_WIDTH => c_WIDTH,
        c_DEPTH => c_DEPTH,
        c_UART_BAUD => c_UART_BAUD,
        c_CLK_FREQ => c_CLK_FREQ
    )
    port map(
        i_clk => r_CLK,
        i_rst => r_RESET,
        i_read_en => r_READ_EN,
        i_rx_port => r_RX_PORT,

        o_buffer_empty => r_BUFFER_EMPTY,
        o_rx_data => r_RX_DATA
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
            r_RX_PORT <= '1';
            r_READ_EN <= '0';
            r_RESET <= '1';
            p_tick_n(3);
            r_RESET <= '0';

            -- The frame reader reset path needs a high RX line for a couple of
            -- clocks so that it can return to its synchronized idle state.
            p_tick_n(2);

            assert r_BUFFER_EMPTY = '1'
                report "RX FIFO should be empty after reset."
                severity failure;

            assert r_RX_DATA = x"00"
                report "RX output data should reset to 0."
                severity failure;
        end p_PREPARE_IDLE;


        procedure p_ASSERT_EMPTY_FOR(constant n : positive;
                                     constant test_name : string) is
        begin
            for i in 1 to n loop
                p_tick_n(1);

                assert r_BUFFER_EMPTY = '1'
                    report test_name & ": RX buffer became non-empty although no byte was expected."
                    severity failure;
            end loop;
        end p_ASSERT_EMPTY_FOR;


        procedure p_WAIT_FOR_BUFFER_NOT_EMPTY(constant test_name : string) is
            variable v_found : boolean := false;
        begin
            for i in 1 to c_DATA_TIMEOUT_TICKS loop
                if r_BUFFER_EMPTY = '0' then
                    v_found := true;
                    exit;
                end if;

                p_tick_n(1);
            end loop;

            assert v_found
                report test_name & ": RX FIFO did not become non-empty after receiving a valid frame."
                severity failure;
        end p_WAIT_FOR_BUFFER_NOT_EMPTY;


        procedure p_READ_BYTE(constant expected_data : std_logic_vector(c_WIDTH-1 downto 0);
                              constant test_name : string) is
        begin
            p_WAIT_FOR_BUFFER_NOT_EMPTY(test_name);

            r_READ_EN <= '1';
            p_tick_n(1);

            assert r_RX_DATA = expected_data
                report test_name & ": read byte does not match expected data."
                severity failure;

            r_READ_EN <= '0';
            p_tick_n(1);
        end p_READ_BYTE;


        procedure p_ASSERT_EMPTY_NOW(constant test_name : string) is
        begin
            assert r_BUFFER_EMPTY = '1'
                report test_name & ": RX FIFO should be empty now."
                severity failure;
        end p_ASSERT_EMPTY_NOW;


        procedure p_DRIVE_START_BIT is
        begin
            r_RX_PORT <= '0';
            p_tick_n(c_CLKS_PER_BIT);
        end p_DRIVE_START_BIT;


        procedure p_DRIVE_DATA_BITS(constant data_to_send : std_logic_vector(c_WIDTH-1 downto 0)) is
        begin
            -- UART 8N1 sends data LSB-first.
            for bit_index in 0 to c_WIDTH-1 loop
                r_RX_PORT <= data_to_send(bit_index);
                p_tick_n(c_CLKS_PER_BIT);
            end loop;
        end p_DRIVE_DATA_BITS;


        procedure p_DRIVE_STOP_BIT_TO_SAMPLE_POINT(constant stop_bit : std_logic) is
        begin
            -- Stop when the reader reaches its stop-bit sample point. The top
            -- level FIFO may store the byte one clock after the frame reader
            -- produces its internal write pulse.
            r_RX_PORT <= stop_bit;
            p_tick_n(c_STOP_SAMPLE_TICKS);
        end p_DRIVE_STOP_BIT_TO_SAMPLE_POINT;


        procedure p_FINISH_STOP_BIT is
        begin
            r_RX_PORT <= '1';

            if c_CLKS_PER_BIT > c_STOP_SAMPLE_TICKS then
                p_tick_n(c_CLKS_PER_BIT - c_STOP_SAMPLE_TICKS);
            end if;
        end p_FINISH_STOP_BIT;


        procedure p_DRIVE_UART_FRAME(constant data_to_send : std_logic_vector(c_WIDTH-1 downto 0);
                                     constant stop_bit : std_logic) is
        begin
            p_DRIVE_START_BIT;
            p_DRIVE_DATA_BITS(data_to_send);
            p_DRIVE_STOP_BIT_TO_SAMPLE_POINT(stop_bit);
        end p_DRIVE_UART_FRAME;


        procedure p_SEND_VALID_FRAME_TO_FIFO(constant data_to_send : std_logic_vector(c_WIDTH-1 downto 0)) is
        begin
            p_DRIVE_UART_FRAME(data_to_send, '1');
            p_FINISH_STOP_BIT;
        end p_SEND_VALID_FRAME_TO_FIFO;


        procedure p_SEND_FRAME_AND_READ(constant data_to_send : std_logic_vector(c_WIDTH-1 downto 0);
                                        constant test_name : string) is
        begin
            p_SEND_VALID_FRAME_TO_FIFO(data_to_send);
            p_READ_BYTE(data_to_send, test_name);
            p_ASSERT_EMPTY_NOW(test_name & " post-read empty check");
        end p_SEND_FRAME_AND_READ;


        procedure p_INIT is
        begin
            report "TEST: INITIALIZATION / IDLE";
            p_PREPARE_IDLE;
            p_ASSERT_EMPTY_FOR(c_IDLE_CHECK_TICKS, "Initialization idle check");
            report "SUCCESS";
        end p_INIT;


        procedure p_READ_WHEN_EMPTY_DOES_NOT_BREAK is
        begin
            report "TEST: UART_RX READ WHEN FIFO IS EMPTY";
            p_PREPARE_IDLE;

            r_READ_EN <= '1';
            p_tick_n(1);
            r_READ_EN <= '0';
            p_tick_n(1);

            p_ASSERT_EMPTY_NOW("Read-when-empty check");
            p_SEND_FRAME_AND_READ(x"5A", "Recovery after read when empty");

            report "SUCCESS";
        end p_READ_WHEN_EMPTY_DOES_NOT_BREAK;


        procedure p_RECEIVE_ZERO_BYTE is
        begin
            report "TEST: UART_RX RECEIVES 0x00";
            p_PREPARE_IDLE;
            p_SEND_FRAME_AND_READ(x"00", "UART_RX receive 0x00");
            report "SUCCESS";
        end p_RECEIVE_ZERO_BYTE;


        procedure p_RECEIVE_ALL_ONES is
        begin
            report "TEST: UART_RX RECEIVES 0xFF";
            p_PREPARE_IDLE;
            p_SEND_FRAME_AND_READ(x"FF", "UART_RX receive 0xFF");
            report "SUCCESS";
        end p_RECEIVE_ALL_ONES;


        procedure p_RECEIVE_MIXED_PATTERN is
        begin
            report "TEST: UART_RX RECEIVES MIXED PATTERN";
            p_PREPARE_IDLE;
            p_SEND_FRAME_AND_READ(x"A6", "UART_RX receive 0xA6");
            report "SUCCESS";
        end p_RECEIVE_MIXED_PATTERN;


        procedure p_LSB_FIRST_ORDER is
        begin
            report "TEST: UART_RX LSB-FIRST BIT ORDER";
            p_PREPARE_IDLE;

            -- 0x80 catches a reader that accidentally decodes MSB-first.
            p_SEND_FRAME_AND_READ(x"80", "UART_RX LSB-first check");

            report "SUCCESS";
        end p_LSB_FIRST_ORDER;


        procedure p_FIFO_PRESERVES_RECEIVE_ORDER is
        begin
            report "TEST: UART_RX FIFO PRESERVES RECEIVE ORDER";
            p_PREPARE_IDLE;

            -- Store multiple received bytes without reading between frames.
            p_SEND_VALID_FRAME_TO_FIFO(x"12");
            p_SEND_VALID_FRAME_TO_FIFO(x"34");
            p_SEND_VALID_FRAME_TO_FIFO(x"56");

            assert r_BUFFER_EMPTY = '0'
                report "Receive-order check: RX FIFO should contain queued bytes."
                severity failure;

            p_READ_BYTE(x"12", "Receive-order first byte");
            p_READ_BYTE(x"34", "Receive-order second byte");
            p_READ_BYTE(x"56", "Receive-order third byte");
            p_ASSERT_EMPTY_NOW("Receive-order final empty check");

            report "SUCCESS";
        end p_FIFO_PRESERVES_RECEIVE_ORDER;


        procedure p_FIFO_FULL_DROPS_EXTRA_FRAME_AND_RECOVERS is
        begin
            report "TEST: UART_RX INTERNAL FIFO FULL DROPS EXTRA FRAME AND RECOVERS";
            p_PREPARE_IDLE;

            -- Fill the RX FIFO completely from the serial input.
            p_SEND_VALID_FRAME_TO_FIFO(x"20");
            p_SEND_VALID_FRAME_TO_FIFO(x"21");
            p_SEND_VALID_FRAME_TO_FIFO(x"22");
            p_SEND_VALID_FRAME_TO_FIFO(x"23");

            assert r_BUFFER_EMPTY = '0'
                report "RX full check: FIFO should contain data after filling."
                severity failure;

            -- This frame arrives while the internal FIFO should be full. Since
            -- uart_rx has no public full flag, the observable behavior is that
            -- this byte must not appear after the four queued bytes are read.
            p_SEND_VALID_FRAME_TO_FIFO(x"EE");

            p_READ_BYTE(x"20", "RX full check queued byte 0");
            p_READ_BYTE(x"21", "RX full check queued byte 1");
            p_READ_BYTE(x"22", "RX full check queued byte 2");
            p_READ_BYTE(x"23", "RX full check queued byte 3");
            p_ASSERT_EMPTY_NOW("RX full check ignored-byte check");

            -- After freeing FIFO space, the receiver should accept new frames.
            p_SEND_FRAME_AND_READ(x"55", "Recovery after RX FIFO full");

            report "SUCCESS";
        end p_FIFO_FULL_DROPS_EXTRA_FRAME_AND_RECOVERS;


        procedure p_INVALID_STOP_BIT_NO_STORE is
        begin
            report "TEST: UART_RX INVALID STOP BIT DOES NOT STORE BYTE";
            p_PREPARE_IDLE;

            p_DRIVE_UART_FRAME(x"C3", '0');

            assert r_BUFFER_EMPTY = '1'
                report "Invalid-stop check: RX FIFO should remain empty."
                severity failure;

            p_ASSERT_EMPTY_FOR(c_CLKS_PER_BIT * 2, "Invalid-stop low-line check");

            r_RX_PORT <= '1';
            p_tick_n(3);

            p_SEND_FRAME_AND_READ(x"3C", "Recovery after invalid stop bit");

            report "SUCCESS";
        end p_INVALID_STOP_BIT_NO_STORE;


        procedure p_SHORT_START_GLITCH_NO_STORE is
        begin
            report "TEST: UART_RX SHORT START-BIT GLITCH DOES NOT STORE BYTE";
            p_PREPARE_IDLE;

            r_RX_PORT <= '0';
            p_tick_n(c_HALF_BIT_TICKS - 1);
            r_RX_PORT <= '1';

            p_ASSERT_EMPTY_FOR(c_CLKS_PER_BIT * 3, "Short-start-glitch check");
            p_SEND_FRAME_AND_READ(x"69", "Recovery after short start glitch");

            report "SUCCESS";
        end p_SHORT_START_GLITCH_NO_STORE;


        procedure p_RESET_MID_RECEIVE_RECOVERS is
        begin
            report "TEST: UART_RX RESET MID-RECEIVE";
            p_PREPARE_IDLE;

            p_DRIVE_START_BIT;

            r_RX_PORT <= '1'; -- data bit 0 of the interrupted frame
            p_tick_n(c_CLKS_PER_BIT);

            r_RX_PORT <= '0'; -- begin data bit 1, then interrupt
            p_tick_n(c_HALF_BIT_TICKS);

            r_RESET <= '1';
            p_tick_n(3);

            assert r_BUFFER_EMPTY = '1'
                report "Reset-mid-receive check: RX FIFO should remain empty during reset."
                severity failure;

            assert r_RX_DATA = x"00"
                report "Reset-mid-receive check: RX data should reset to 0."
                severity failure;

            r_RESET <= '0';

            -- Keep the line low after reset release. The reader should wait for
            -- a clean idle-high level instead of continuing the old frame.
            p_ASSERT_EMPTY_FOR(c_CLKS_PER_BIT * 2, "Reset-mid-receive low-line wait check");

            r_RX_PORT <= '1';
            p_tick_n(3);

            p_SEND_FRAME_AND_READ(x"96", "Recovery after reset mid-receive");

            report "SUCCESS";
        end p_RESET_MID_RECEIVE_RECOVERS;


        procedure p_RESET_CLEARS_QUEUED_DATA is
        begin
            report "TEST: UART_RX RESET CLEARS QUEUED FIFO DATA";
            p_PREPARE_IDLE;

            p_SEND_VALID_FRAME_TO_FIFO(x"AA");
            p_SEND_VALID_FRAME_TO_FIFO(x"BB");

            assert r_BUFFER_EMPTY = '0'
                report "Reset-clears-queue check: RX FIFO should contain data before reset."
                severity failure;

            r_RESET <= '1';
            p_tick_n(3);
            r_RESET <= '0';
            p_tick_n(2);

            p_ASSERT_EMPTY_NOW("Reset-clears-queue check");

            r_READ_EN <= '1';
            p_tick_n(1);
            r_READ_EN <= '0';
            p_tick_n(1);
            p_ASSERT_EMPTY_NOW("Reset-clears-queue read-old-data check");

            p_SEND_FRAME_AND_READ(x"CC", "Recovery after reset clears queued data");

            report "SUCCESS";
        end p_RESET_CLEARS_QUEUED_DATA;

    begin
        assert c_CLKS_PER_BIT >= 2
            report "c_CLKS_PER_BIT must be at least 2 for UART bit timing."
            severity failure;

        assert c_HALF_BIT_TICKS > 1
            report "c_HALF_BIT_TICKS must be greater than 1 for the short-glitch test."
            severity failure;

        assert c_STOP_SAMPLE_TICKS < c_CLKS_PER_BIT
            report "c_STOP_SAMPLE_TICKS should leave some stop-bit time after the sample point."
            severity failure;

        p_INIT;
        p_READ_WHEN_EMPTY_DOES_NOT_BREAK;
        p_RECEIVE_ZERO_BYTE;
        p_RECEIVE_ALL_ONES;
        p_RECEIVE_MIXED_PATTERN;
        p_LSB_FIRST_ORDER;
        p_FIFO_PRESERVES_RECEIVE_ORDER;
        p_FIFO_FULL_DROPS_EXTRA_FRAME_AND_RECOVERS;
        p_INVALID_STOP_BIT_NO_STORE;
        p_SHORT_START_GLITCH_NO_STORE;
        p_RESET_MID_RECEIVE_RECOVERS;
        p_RESET_CLEARS_QUEUED_DATA;

        assert false report "ALL TESTS PASSED" severity failure;
    end process p_TEST_BENCH;

end Behavioral;
