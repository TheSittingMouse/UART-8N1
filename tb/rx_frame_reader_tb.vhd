library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity rx_frame_reader_tb is
end rx_frame_reader_tb;

architecture Behavioral of rx_frame_reader_tb is

    constant c_WIDTH : natural := 8;
    constant c_CLK_FREQ : natural := 100_000_000;
    constant c_UART_BAUD : natural := 10_000_000;

    constant c_CLK_PERIOD : time := 10 ns;
    constant c_CLK_HALF_PERIOD : time := 5 ns;

    constant c_CLKS_PER_BIT : natural := c_CLK_FREQ / c_UART_BAUD;
    constant c_HALF_BIT_TICKS : positive := c_CLKS_PER_BIT / 2;

    constant c_STOP_SAMPLE_TICKS : positive := c_HALF_BIT_TICKS + 1;
    constant c_WRITE_TIMEOUT_TICKS : positive := 4 * c_CLKS_PER_BIT;
    constant c_IDLE_CHECK_TICKS : positive := 4 * c_CLKS_PER_BIT;

    signal r_CLK : std_logic := '0';
    signal r_RESET : std_logic := '0';
    signal r_BUFFER_FULL : std_logic := '0';
    signal r_RX_PORT : std_logic := '1';

    signal r_WRITE_EN : std_logic := '0';
    signal r_READ_BYTE : std_logic_vector(c_WIDTH-1 downto 0) := (others => '0');

begin

    p_CLK : process
    begin
        r_CLK <= '0';
        wait for c_CLK_HALF_PERIOD;
        r_CLK <= '1';
        wait for c_CLK_HALF_PERIOD;
    end process p_CLK;


    UUT : entity work.rx_frame_reader
    generic map(
        c_WIDTH => c_WIDTH,
        c_UART_BAUD => c_UART_BAUD,
        c_CLK_FREQ => c_CLK_FREQ
    )
    port map(
        i_clk => r_CLK,
        i_reset => r_RESET,
        i_buffer_full => r_BUFFER_FULL,
        i_rx_port => r_RX_PORT,

        o_write_en => r_WRITE_EN,
        o_read_byte => r_READ_BYTE
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
            r_BUFFER_FULL <= '0';
            r_RESET <= '1';
            p_tick_n(3);
            r_RESET <= '0';

            -- The reader reset state is WAIT. Give it a high RX line so it can
            -- return to SYNC/idle and be ready to see the next falling edge.
            p_tick_n(2);

            assert r_WRITE_EN = '0'
                report "WRITE_EN should be low after reset."
                severity failure;

            assert r_READ_BYTE = x"00"
                report "READ_BYTE should reset to 0."
                severity failure;
        end p_PREPARE_IDLE;


        procedure p_ASSERT_NO_WRITE_FOR(constant n : positive;
                                        constant test_name : string) is
        begin
            for i in 1 to n loop
                p_tick_n(1);

                assert r_WRITE_EN = '0'
                    report test_name & ": WRITE_EN went high although no write was expected."
                    severity failure;
            end loop;
        end p_ASSERT_NO_WRITE_FOR;


        procedure p_WAIT_FOR_WRITE_PULSE(constant expected_data : std_logic_vector(c_WIDTH-1 downto 0);
                                         constant test_name : string) is
            variable v_found : boolean := false;
        begin
            -- o_write_en is expected to be a one-clock request pulse to the FIFO.
            -- The pulse may already be high when this procedure is called because
            -- the virtual transmitter returns at the end of the stop-bit window.
            for i in 1 to c_WRITE_TIMEOUT_TICKS loop
                if r_WRITE_EN = '1' then
                    v_found := true;

                    assert r_READ_BYTE = expected_data
                        report test_name & ": READ_BYTE does not match the received frame."
                        severity failure;
                    exit;
                end if;

                p_tick_n(1);
            end loop;

            assert v_found
                report test_name & ": WRITE_EN was not asserted after a valid frame."
                severity failure;

            p_tick_n(1);

            assert r_WRITE_EN = '0'
                report test_name & ": WRITE_EN should be a single-clock pulse."
                severity failure;

            assert r_READ_BYTE = expected_data
                report test_name & ": READ_BYTE should remain stable after the write pulse."
                severity failure;
        end p_WAIT_FOR_WRITE_PULSE;


        procedure p_ASSERT_WRITE_PULSE_NOW(constant expected_data : std_logic_vector(c_WIDTH-1 downto 0);
                                           constant test_name : string) is
        begin
            assert r_WRITE_EN = '1'
                report test_name & ": expected WRITE_EN to be high now."
                severity failure;

            assert r_READ_BYTE = expected_data
                report test_name & ": READ_BYTE does not match while WRITE_EN is high."
                severity failure;
        end p_ASSERT_WRITE_PULSE_NOW;


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


        procedure p_DRIVE_STOP_BIT(constant stop_bit : std_logic) is
        begin
            -- Stop as soon as the reader reaches its stop-bit sampling point.
            -- For a valid frame, WRITE_EN should be visible when this returns.
            r_RX_PORT <= stop_bit;
            p_tick_n(c_STOP_SAMPLE_TICKS);
        end p_DRIVE_STOP_BIT;


        procedure p_DRIVE_UART_FRAME(constant data_to_send : std_logic_vector(c_WIDTH-1 downto 0);
                                     constant stop_bit : std_logic) is
        begin
            p_DRIVE_START_BIT;
            p_DRIVE_DATA_BITS(data_to_send);
            p_DRIVE_STOP_BIT(stop_bit);
        end p_DRIVE_UART_FRAME;


        procedure p_SEND_FRAME_AND_EXPECT_BYTE(constant data_to_send : std_logic_vector(c_WIDTH-1 downto 0);
                                               constant test_name : string) is
        begin
            p_DRIVE_UART_FRAME(data_to_send, '1');
            p_WAIT_FOR_WRITE_PULSE(data_to_send, test_name);

            -- Leave the serial line in idle for a few clocks before the next test.
            r_RX_PORT <= '1';
            p_ASSERT_NO_WRITE_FOR(2, test_name & " post-frame idle check");
        end p_SEND_FRAME_AND_EXPECT_BYTE;


        procedure p_INIT is
        begin
            report "TEST: INITIALIZATION / IDLE";
            p_PREPARE_IDLE;
            p_ASSERT_NO_WRITE_FOR(c_IDLE_CHECK_TICKS, "Initialization idle check");
            report "SUCCESS";
        end p_INIT;


        procedure p_NO_WRITE_WHILE_IDLE is
        begin
            report "TEST: NO WRITE WHILE RX LINE IS IDLE";
            p_PREPARE_IDLE;

            r_RX_PORT <= '1';
            r_BUFFER_FULL <= '0';
            p_ASSERT_NO_WRITE_FOR(c_IDLE_CHECK_TICKS, "Idle-line check");

            report "SUCCESS";
        end p_NO_WRITE_WHILE_IDLE;


        procedure p_RECEIVE_ZERO_BYTE is
        begin
            report "TEST: RECEIVE 0x00";
            p_PREPARE_IDLE;
            p_SEND_FRAME_AND_EXPECT_BYTE(x"00", "Receive 0x00");
            report "SUCCESS";
        end p_RECEIVE_ZERO_BYTE;


        procedure p_RECEIVE_ALL_ONES is
        begin
            report "TEST: RECEIVE 0xFF";
            p_PREPARE_IDLE;
            p_SEND_FRAME_AND_EXPECT_BYTE(x"FF", "Receive 0xFF");
            report "SUCCESS";
        end p_RECEIVE_ALL_ONES;


        procedure p_RECEIVE_MIXED_PATTERN is
        begin
            report "TEST: RECEIVE MIXED PATTERN";
            p_PREPARE_IDLE;
            p_SEND_FRAME_AND_EXPECT_BYTE(x"A6", "Receive 0xA6");
            report "SUCCESS";
        end p_RECEIVE_MIXED_PATTERN;


        procedure p_LSB_FIRST_ORDER is
        begin
            report "TEST: LSB-FIRST BIT ORDER";
            p_PREPARE_IDLE;

            -- 0x80 is useful because a wrong MSB-first reader would decode this
            -- as 0x01 instead of 0x80.
            p_SEND_FRAME_AND_EXPECT_BYTE(x"80", "LSB-first receive check");

            report "SUCCESS";
        end p_LSB_FIRST_ORDER;


        procedure p_WRITE_EN_SINGLE_CYCLE is
        begin
            report "TEST: WRITE_EN SINGLE-CLOCK PULSE";
            p_PREPARE_IDLE;
            p_SEND_FRAME_AND_EXPECT_BYTE(x"55", "WRITE_EN pulse check");
            report "SUCCESS";
        end p_WRITE_EN_SINGLE_CYCLE;


        procedure p_BACK_TO_BACK_FRAMES is
        begin
            report "TEST: BACK-TO-BACK FRAMES";
            p_PREPARE_IDLE;

            -- First frame. At return from the stop bit sample, WRITE_EN should be high.
            p_DRIVE_UART_FRAME(x"12", '1');
            p_ASSERT_WRITE_PULSE_NOW(x"12", "Back-to-back first frame");

            -- Consume the write pulse and finish the rest of the stop bit before
            -- starting the next frame. This is the actual UART back-to-back case:
            -- one stop bit, then immediately another start bit.
            p_tick_n(1);

            assert r_WRITE_EN = '0'
                report "Back-to-back frames: first WRITE_EN pulse was longer than one clock."
                severity failure;

            if c_CLKS_PER_BIT > c_STOP_SAMPLE_TICKS + 1 then
                p_tick_n(c_CLKS_PER_BIT - c_STOP_SAMPLE_TICKS - 1);
            end if;

            p_DRIVE_START_BIT;
            p_DRIVE_DATA_BITS(x"34");
            p_DRIVE_STOP_BIT('1');
            p_WAIT_FOR_WRITE_PULSE(x"34", "Back-to-back second frame");

            report "SUCCESS";
        end p_BACK_TO_BACK_FRAMES;


        procedure p_NO_WRITE_WHEN_BUFFER_FULL is
        begin
            report "TEST: NO FIFO WRITE WHEN BUFFER IS FULL";
            p_PREPARE_IDLE;

            r_BUFFER_FULL <= '1';
            p_DRIVE_UART_FRAME(x"4D", '1');

            assert r_WRITE_EN = '0'
                report "Buffer-full check: WRITE_EN should not assert when FIFO is full."
                severity failure;

            -- The decoded byte may update internally, but no FIFO write request
            -- should be made while full is high.
            p_ASSERT_NO_WRITE_FOR(c_CLKS_PER_BIT * 2, "Buffer-full check");

            -- Dropping full after the frame must not create a late write for the
            -- already missed frame.
            r_BUFFER_FULL <= '0';
            p_ASSERT_NO_WRITE_FOR(c_CLKS_PER_BIT * 2, "Buffer-full late-write check");

            -- Make sure the reader can still accept the next frame after full clears.
            p_SEND_FRAME_AND_EXPECT_BYTE(x"4E", "Receive after buffer-full clears");

            report "SUCCESS";
        end p_NO_WRITE_WHEN_BUFFER_FULL;


        procedure p_INVALID_STOP_BIT_NO_WRITE is
        begin
            report "TEST: INVALID STOP BIT DOES NOT WRITE";
            p_PREPARE_IDLE;

            -- Stop bit must be 1 for 8N1. A low stop bit should reject the frame
            -- and put the reader into WAIT until the line returns high.
            p_DRIVE_UART_FRAME(x"C3", '0');

            assert r_WRITE_EN = '0'
                report "Invalid-stop check: WRITE_EN should stay low."
                severity failure;

            p_ASSERT_NO_WRITE_FOR(c_CLKS_PER_BIT * 2, "Invalid-stop check while line is low");

            r_RX_PORT <= '1';
            p_tick_n(3);

            p_SEND_FRAME_AND_EXPECT_BYTE(x"3C", "Recovery after invalid stop bit");

            report "SUCCESS";
        end p_INVALID_STOP_BIT_NO_WRITE;


        procedure p_SHORT_START_GLITCH_NO_WRITE is
        begin
            report "TEST: SHORT START-BIT GLITCH DOES NOT WRITE";
            p_PREPARE_IDLE;

            -- A low pulse shorter than the start-bit qualification window should
            -- not be treated as a real frame.
            r_RX_PORT <= '0';
            p_tick_n(c_HALF_BIT_TICKS - 1);
            r_RX_PORT <= '1';

            p_ASSERT_NO_WRITE_FOR(c_CLKS_PER_BIT * 3, "Short-start-glitch check");

            p_SEND_FRAME_AND_EXPECT_BYTE(x"5A", "Recovery after short start glitch");

            report "SUCCESS";
        end p_SHORT_START_GLITCH_NO_WRITE;


        procedure p_UNKNOWN_RX_VALUE_GOES_TO_WAIT is
        begin
            report "TEST: UNKNOWN RX VALUE DOES NOT WRITE AND RECOVERS";
            p_PREPARE_IDLE;

            r_RX_PORT <= 'X';
            p_ASSERT_NO_WRITE_FOR(c_CLKS_PER_BIT, "Unknown-RX check");

            r_RX_PORT <= '1';
            p_tick_n(3);

            p_SEND_FRAME_AND_EXPECT_BYTE(x"96", "Recovery after unknown RX value");

            report "SUCCESS";
        end p_UNKNOWN_RX_VALUE_GOES_TO_WAIT;


        procedure p_RESET_MID_RECEIVE is
        begin
            report "TEST: RESET MID-RECEIVE";
            p_PREPARE_IDLE;

            -- Begin a frame, then reset before the frame can complete.
            p_DRIVE_START_BIT;

            r_RX_PORT <= '1'; -- data bit 0 of the interrupted frame
            p_tick_n(c_CLKS_PER_BIT);

            r_RX_PORT <= '0'; -- start driving data bit 1, then interrupt
            p_tick_n(c_HALF_BIT_TICKS);

            r_RESET <= '1';
            p_tick_n(3);

            assert r_WRITE_EN = '0'
                report "Reset-mid-receive check: WRITE_EN should be low during reset."
                severity failure;

            assert r_READ_BYTE = x"00"
                report "Reset-mid-receive check: READ_BYTE should reset to 0."
                severity failure;

            r_RESET <= '0';

            -- Keep the line low after reset release. Since reset puts the reader in
            -- WAIT, it should not treat this low level as a continuation of the old frame.
            p_ASSERT_NO_WRITE_FOR(c_CLKS_PER_BIT * 2, "Reset-mid-receive low-line wait check");

            -- Return the line to idle and make sure the reader recovers.
            r_RX_PORT <= '1';
            p_tick_n(3);

            p_SEND_FRAME_AND_EXPECT_BYTE(x"69", "Recovery after reset mid-receive");

            report "SUCCESS";
        end p_RESET_MID_RECEIVE;

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
        p_NO_WRITE_WHILE_IDLE;
        p_RECEIVE_ZERO_BYTE;
        p_RECEIVE_ALL_ONES;
        p_RECEIVE_MIXED_PATTERN;
        p_LSB_FIRST_ORDER;
        p_WRITE_EN_SINGLE_CYCLE;
        p_BACK_TO_BACK_FRAMES;
        p_NO_WRITE_WHEN_BUFFER_FULL;
        p_INVALID_STOP_BIT_NO_WRITE;
        p_SHORT_START_GLITCH_NO_WRITE;
        p_UNKNOWN_RX_VALUE_GOES_TO_WAIT;
        p_RESET_MID_RECEIVE;

        assert false report "ALL TESTS PASSED" severity failure;
    end process p_TEST_BENCH;

end Behavioral;
