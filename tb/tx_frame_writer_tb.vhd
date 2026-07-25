
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity tx_frame_writer_tb is
end tx_frame_writer_tb;

architecture Behavioral of tx_frame_writer_tb is

    constant c_WIDTH : natural := 8;
    constant c_CLK_FREQ : natural := 100_000_000;
    constant c_UART_BAUD : natural := 10_000_000;
    
    constant c_CLK_PERIOD : time := 10 ns;
    constant c_CLK_HALF_PERIOD : time := 5 ns;
    
    constant c_CLKS_PER_BIT : natural := c_CLK_FREQ / c_UART_BAUD;
    constant c_HALF_BIT_TICKS : positive := c_CLKS_PER_BIT / 2;

    constant c_READ_TIMEOUT_TICKS : positive := 4 * c_CLKS_PER_BIT;
    constant c_START_TIMEOUT_TICKS : positive := 8 * c_CLKS_PER_BIT;

    signal r_CLK : std_logic := '0';
    signal r_RESET : std_logic := '0';
    signal r_BUFFER_EMPTY : std_logic := '1';
    signal r_DATA : std_logic_vector(c_WIDTH-1 downto 0) := (others => '0');

    signal r_READ_EN : std_logic := '0';
    signal r_TX_PORT : std_logic := '1';

begin

    p_CLK : process
    begin
        r_CLK <= '0';
        wait for c_CLK_HALF_PERIOD;
        r_CLK <= '1';
        wait for c_CLK_HALF_PERIOD;
    end process p_CLK;

    UUT : entity work.tx_frame_writer
    generic map(
        c_WIDTH => c_WIDTH,
        c_UART_BAUD => c_UART_BAUD,
        c_CLK_FREQ => c_CLK_FREQ
    )
    port map(
        i_clk => r_CLK,
        i_reset => r_RESET,
        i_buffer_empty => r_BUFFER_EMPTY,
        i_data => r_DATA,
        o_read_en => r_READ_EN,
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
            r_BUFFER_EMPTY <= '1';
            r_DATA <= (others => '0');
            r_RESET <= '1';
            p_tick_n(3);
            r_RESET <= '0';

            assert r_TX_PORT = '1'
                report "TX line should be high while idle."
                severity failure;

            assert r_READ_EN = '0'
                report "READ_EN should be low while idle."
                severity failure;
        end p_PREPARE_IDLE;


        procedure p_ASSERT_IDLE_FOR(constant n : positive;
                                    constant test_name : string) is
        begin
            for i in 1 to n loop
                p_tick_n(1);

                assert r_TX_PORT = '1'
                    report test_name & ": TX line went low although no frame was expected."
                    severity failure;

                assert r_READ_EN = '0'
                    report test_name & ": READ_EN went high although buffer was empty."
                    severity failure;
            end loop;
        end p_ASSERT_IDLE_FOR;


        procedure p_WAIT_FOR_READ_PULSE(constant test_name : string) is
            variable v_found : boolean := false;
        begin
            -- o_read_en is expected to be a one-clock request pulse.
            for i in 1 to c_READ_TIMEOUT_TICKS loop
                if r_READ_EN = '1' then
                    v_found := true;
                    exit;
                end if;

                p_tick_n(1);
            end loop;

            assert v_found
                report test_name & ": READ_EN was not asserted after buffer became non-empty."
                severity failure;

            p_tick_n(1);

            assert r_READ_EN = '0'
                report test_name & ": READ_EN should be a single-clock pulse."
                severity failure;
        end p_WAIT_FOR_READ_PULSE;


        procedure p_WAIT_FOR_START_BIT(constant test_name : string) is
            variable v_found : boolean := false;
        begin
            -- This avoids a hanging test bench if the transmitter never starts.
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


        procedure p_RECEIVE_BYTE(constant expected_data : std_logic_vector(c_WIDTH-1 downto 0);
                                 constant test_name : string) is
        begin
            -- Virtual serial receiver:
            -- 1. Wait for the falling edge / low start bit.
            -- 2. Sample the middle of the start bit.
            -- 3. Sample each data bit one bit-period apart.
            -- 4. The DUT sends data LSB-first.
            -- 5. Check the final stop bit.
            p_WAIT_FOR_START_BIT(test_name);

            p_tick_n(c_HALF_BIT_TICKS);
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
        end p_RECEIVE_BYTE;


        procedure p_REQUEST_ONE_FRAME(constant data_to_send : std_logic_vector(c_WIDTH-1 downto 0);
                                      constant test_name : string) is
        begin
            r_DATA <= data_to_send;
            r_BUFFER_EMPTY <= '0';

            p_WAIT_FOR_READ_PULSE(test_name);

            -- No more data after this byte.
            r_BUFFER_EMPTY <= '1';

            -- The DUT loads i_data in its LOAD_2 state, one clock after
            -- READ_EN has already gone low. Keep r_DATA stable until here.
            p_tick_n(1);
        end p_REQUEST_ONE_FRAME;


        procedure p_FINISH_FRAME_AND_ASSERT_IDLE(constant test_name : string) is
        begin
            r_BUFFER_EMPTY <= '1';

            -- p_RECEIVE_BYTE returns around the middle of the stop bit.
            -- Let the stop bit finish and let the DUT return to IDLE.
            p_tick_n(c_CLKS_PER_BIT + 3);

            assert r_TX_PORT = '1'
                report test_name & ": TX line should return to idle high after frame."
                severity failure;

            assert r_READ_EN = '0'
                report test_name & ": READ_EN should be low after frame when buffer is empty."
                severity failure;
        end p_FINISH_FRAME_AND_ASSERT_IDLE;


        procedure p_INIT is
        begin
            report "TEST: INITIALIZATION / IDLE";
            p_PREPARE_IDLE;
            p_ASSERT_IDLE_FOR(c_CLKS_PER_BIT * 3, "Initialization idle check");
            report "SUCCESS";
        end p_INIT;


        procedure p_NO_READ_WHEN_EMPTY is
        begin
            report "TEST: NO READ REQUEST WHEN BUFFER IS EMPTY";
            p_PREPARE_IDLE;

            r_BUFFER_EMPTY <= '1';
            r_DATA <= x"A5";

            p_ASSERT_IDLE_FOR(c_CLKS_PER_BIT * 4, "Empty-buffer check");
            report "SUCCESS";
        end p_NO_READ_WHEN_EMPTY;


        procedure p_READ_EN_SINGLE_CYCLE is
        begin
            report "TEST: READ_EN SINGLE-CLOCK PULSE";
            p_PREPARE_IDLE;

            p_REQUEST_ONE_FRAME(x"55", "READ_EN pulse check");
            p_RECEIVE_BYTE(x"55", "READ_EN pulse check");
            p_FINISH_FRAME_AND_ASSERT_IDLE("READ_EN pulse check");

            report "SUCCESS";
        end p_READ_EN_SINGLE_CYCLE;


        procedure p_SEND_ZERO_BYTE is
        begin
            report "TEST: TRANSMIT 0x00";
            p_PREPARE_IDLE;

            p_REQUEST_ONE_FRAME(x"00", "Transmit 0x00");
            p_RECEIVE_BYTE(x"00", "Transmit 0x00");
            p_FINISH_FRAME_AND_ASSERT_IDLE("Transmit 0x00");

            report "SUCCESS";
        end p_SEND_ZERO_BYTE;


        procedure p_SEND_ALL_ONES is
        begin
            report "TEST: TRANSMIT 0xFF";
            p_PREPARE_IDLE;

            p_REQUEST_ONE_FRAME(x"FF", "Transmit 0xFF");
            p_RECEIVE_BYTE(x"FF", "Transmit 0xFF");
            p_FINISH_FRAME_AND_ASSERT_IDLE("Transmit 0xFF");

            report "SUCCESS";
        end p_SEND_ALL_ONES;


        procedure p_SEND_MIXED_PATTERN is
        begin
            report "TEST: TRANSMIT MIXED PATTERN";
            p_PREPARE_IDLE;

            p_REQUEST_ONE_FRAME(x"A6", "Transmit 0xA6");
            p_RECEIVE_BYTE(x"A6", "Transmit 0xA6");
            p_FINISH_FRAME_AND_ASSERT_IDLE("Transmit 0xA6");

            report "SUCCESS";
        end p_SEND_MIXED_PATTERN;


        procedure p_LSB_FIRST_ORDER is
        begin
            report "TEST: LSB-FIRST BIT ORDER";
            p_PREPARE_IDLE;

            -- 0x80 is useful because a wrong MSB-first transmitter would
            -- send the only '1' as the first data bit instead of the last one.
            p_REQUEST_ONE_FRAME(x"80", "LSB-first check");
            p_RECEIVE_BYTE(x"80", "LSB-first check");
            p_FINISH_FRAME_AND_ASSERT_IDLE("LSB-first check");

            report "SUCCESS";
        end p_LSB_FIRST_ORDER;


        procedure p_DATA_LATCHED_BEFORE_TRANSMIT is
        begin
            report "TEST: DATA IS LATCHED BEFORE TRANSMIT";
            p_PREPARE_IDLE;

            p_REQUEST_ONE_FRAME(x"3C", "Data latch check");

            -- Change the input after LOAD_2 should have captured the frame.
            -- A correct frame writer should still transmit 0x3C.
            r_DATA <= x"C3";

            p_RECEIVE_BYTE(x"3C", "Data latch check");
            p_FINISH_FRAME_AND_ASSERT_IDLE("Data latch check");

            report "SUCCESS";
        end p_DATA_LATCHED_BEFORE_TRANSMIT;


        procedure p_BACK_TO_BACK_FRAMES is
        begin
            report "TEST: BACK-TO-BACK FRAMES WHILE BUFFER STAYS NON-EMPTY";
            p_PREPARE_IDLE;

            -- First byte is available.
            r_DATA <= x"12";
            r_BUFFER_EMPTY <= '0';
            p_WAIT_FOR_READ_PULSE("Back-to-back first read");

            -- Keep first byte stable until the DUT reaches LOAD_2.
            p_tick_n(1);

            -- Simulate the FIFO now presenting the next byte while still non-empty.
            r_DATA <= x"34";
            r_BUFFER_EMPTY <= '0';

            p_RECEIVE_BYTE(x"12", "Back-to-back first frame");

            -- After the first stop bit, the DUT should return to IDLE and
            -- immediately request the next byte because buffer_empty is still 0.
            p_WAIT_FOR_READ_PULSE("Back-to-back second read");

            -- No more data after the second byte. Again, hold r_DATA stable
            -- for the DUT's LOAD_2 state.
            r_BUFFER_EMPTY <= '1';
            p_tick_n(1);

            p_RECEIVE_BYTE(x"34", "Back-to-back second frame");
            p_FINISH_FRAME_AND_ASSERT_IDLE("Back-to-back frames");

            report "SUCCESS";
        end p_BACK_TO_BACK_FRAMES;


        procedure p_NO_EXTRA_FRAME_AFTER_EMPTY is
        begin
            report "TEST: NO EXTRA FRAME AFTER BUFFER BECOMES EMPTY";
            p_PREPARE_IDLE;

            p_REQUEST_ONE_FRAME(x"7E", "No-extra-frame check");
            p_RECEIVE_BYTE(x"7E", "No-extra-frame check");
            p_FINISH_FRAME_AND_ASSERT_IDLE("No-extra-frame check");

            p_ASSERT_IDLE_FOR(c_CLKS_PER_BIT * 4, "No-extra-frame check");
            report "SUCCESS";
        end p_NO_EXTRA_FRAME_AFTER_EMPTY;

    begin
        assert c_CLKS_PER_BIT >= 2
            report "c_CLKS_PER_BIT must be at least 2 for middle-of-bit sampling."
            severity failure;

        p_INIT;
        p_NO_READ_WHEN_EMPTY;
        p_READ_EN_SINGLE_CYCLE;
        p_SEND_ZERO_BYTE;
        p_SEND_ALL_ONES;
        p_SEND_MIXED_PATTERN;
        p_LSB_FIRST_ORDER;
        p_DATA_LATCHED_BEFORE_TRANSMIT;
        p_BACK_TO_BACK_FRAMES;
        p_NO_EXTRA_FRAME_AFTER_EMPTY;

        assert false report "ALL TESTS PASSED" severity failure;
    end process p_TEST_BENCH;

end Behavioral;
