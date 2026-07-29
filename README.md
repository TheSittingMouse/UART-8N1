# UART 8N1 VHDL Transmitter and Receiver

This repository contains a VHDL implementation of a UART-style 8N1 serial transmitter and receiver with small FIFO queues on both sides. The design is written as synthesizable VHDL RTL, with a Basys 3-oriented top-level example and Xilinx XDC constraints for the board clock, switches, LEDs, buttons, and USB-RS232 pins.

The core can serve as a lightweight educational UART block for FPGA projects that need byte-oriented serial transmit and receive paths. The repository keeps the frame writer, frame reader, FIFO queue, and board demonstration top level separated so each part can be simulated and reviewed independently.

## Overview

The transmit path accepts an 8-bit byte through `i_tx_write_data` when `i_write_en` is asserted on `i_clk`. The byte is stored in a FIFO if space is available. When the transmit frame writer sees that the FIFO is not empty, it requests one byte, builds a serial frame, and drives `o_tx_port` idle-high, then a low start bit, then data bits LSB-first, then one high stop bit.

The receive path watches the serial `i_rx_port` line. It waits for an idle-high line, qualifies a low start bit for half of a bit period, samples `c_WIDTH` data bits at the configured bit cadence, checks for a high stop bit, and writes the decoded byte into a FIFO when the FIFO is not full. The public receive wrapper presents queued bytes on `o_rx_data` when `i_read_en` reads the FIFO, and reports FIFO emptiness through `o_buffer_empty`.

The top-level entity `top_rx_tx` is displayed as a small example of usage. It connects the TX and RX cores to board controls for a nice demonstration. Push buttons are debounced into single-clock pulses for reset, send, and receive actions. Switches provide the byte to transmit, TX switch data is mirrored to LEDs, received data is shown on another LED bank, and `i_rx_port`/`o_tx_port` connect to the board serial pins.

## Interface

The main public top-level entity is `top_rx_tx` in `rtl/top/top_tx_rx.vhd`.

### Generics

| Generic / Parameter | Default | Description |
| ------------------- | ------- | ----------- |
| `c_DEBOUNCE_CYCLES` | `1048575` | Number of `i_clk` cycles that a button input must remain changed before the debouncer updates its state and emits a pulse. Default value corresponds to `10 ms` for a `100MHz` clock. |
| `c_WIDTH` | `8` | Data width used by the top-level switch and LED vectors and passed into the UART/FIFO submodules. The integrated wrapper ports in `uart_tx` and `uart_rx` are fixed at 8 bits, so the supplied top level is practically an 8-bit design as written. |
| `c_DEPTH` | `8` | FIFO depth, in entries, passed to both the transmit and receive FIFOs. |
| `c_UART_BAUD` | `9600` | UART baud rate used to derive the number of clock cycles per serial bit. |
| `c_CLK_FREQ` | `100_000_000` | Input clock frequency in hertz. With the supplied constraint, `i_clk` is a 100 MHz clock. |

### Ports

| Port | Direction | Description |
| ---- | --------- | ----------- |
| `i_clk` | in | Main synchronous clock for the top level, UART cores, FIFOs, synchronizers, and button debouncers. The supplied XDC constrains this clock to 10.00 ns. |
| `i_btn_rst` | in | Raw active-high reset button input. `top_rx_tx` debounces it and converts it into the one-clock active-high `w_RST_PULSE` used as the synchronous reset for `uart_tx` and `uart_rx`. |
| `i_btn_send` | in | Raw active-high send button input. After debounce, a single-clock `w_WRITE_EN_PULSE` requests that the synchronized switch byte be written into the TX FIFO. |
| `i_btn_recv` | in | Raw active-high receive/read button input. After debounce, a single-clock `w_READ_EN_PULSE` requests one read from the RX FIFO. |
| `i_switch_data` | in | `c_WIDTH`-bit switch input. The top level passes this through two clocked synchronization registers before using it as TX write data and displaying it on `o_led_tx_data`. |
| `i_rx_port` | in | Asynchronous serial receive input. The top level passes it through a two-register synchronizer before feeding the UART receiver. The UART line is expected to idle high. |
| `o_led_tx_data` | out | Registered copy of the synchronized switch data. It reflects the byte currently presented to the TX write path, not the current serial bit. |
| `o_led_rx_data` | out | RX FIFO read-data output from `uart_rx`. It updates when the receive FIFO accepts a valid read and otherwise retains its previous value. |
| `o_tx_port` | out | Serial transmit output from `uart_tx`. It idles high and sends frames as start bit `0`, data bits LSB-first, and stop bit `1`. |

The reusable core wrappers are `uart_tx` and `uart_rx` in `rtl/design/`. `uart_tx` exposes `i_write_en`, `i_tx_write_data`, `o_buffer_full`, and `o_tx_port`; `uart_rx` exposes `i_read_en`, `i_rx_port`, `o_buffer_empty`, and `o_rx_data`.

## Implementation Details

`top_rx_tx` instantiates `uart_tx`, `uart_rx`, and three `button_debouncer` instances. `p_SWITCH_SYNC` registers `i_switch_data` through `r_SWITCH_DATA_SYNC_1` and `r_SWITCH_DATA_SYNC_2`. `p_RX_SYNC` similarly registers `i_rx_port` through `r_RX_SYNC_1` and `r_RX_SYNC_2`. The debounced send and receive buttons become one-clock write/read requests, and the debounced reset button becomes a one-clock synchronous reset pulse for the UART cores.

`uart_tx` combines `tx_frame_writer` with `fifo_queue`. External writes enter the FIFO through `i_write_en` when the queue is not full. The frame writer monitors `i_buffer_empty`; when data is available, it asserts `o_read_en` for one clock, waits one state for FIFO output timing, captures the byte into `r_TX_FRAME`, and transmits the frame from bit 0 upward. `c_CLKS_PER_BIT` is calculated as integer division `c_CLK_FREQ / c_UART_BAUD`, so UART timing is quantized to whole input-clock cycles.

The `tx_frame_writer` state machine uses four encoded states: `c_IDLE`, `c_REQUEST_READ`, `c_CAPTURE_DATA`, and `c_TRANSMIT`. In `c_IDLE`, `o_tx_port` is held high. When `i_buffer_empty = '0'`, `c_REQUEST_READ` creates a one-clock FIFO read pulse. `c_CAPTURE_DATA` loads `r_TX_FRAME <= "1" & w_DATA & '0'`, placing the start bit at the shift-register LSB and the stop bit at the MSB. `c_TRANSMIT` drives the next serial bit whenever `r_CLK_COUNTER = 0`, shifts the frame register, and uses `r_BIT_COUNTER` to return to `c_IDLE` after the stop bit has been held for one bit period.

`uart_rx` combines `rx_frame_reader` with another `fifo_queue`. The frame reader decodes serial frames and asserts `o_write_en` for one clock after a valid stop bit if `i_buffer_full = '0'`. The FIFO stores received bytes until the public `i_read_en` port reads them. Since `uart_rx` only exposes `o_buffer_empty`, receive overflow is observable only by missing bytes, not by a public full flag.

The `rx_frame_reader` state machine uses `c_WAIT`, `c_SYNC`, `c_RECEIVE`, and `c_END`. Reset puts the reader into `c_WAIT`, where it waits for `i_rx_port = '1'` before returning to synchronization. In `c_SYNC`, the reader requires the line to remain low until `r_SYNC_COUNTER = c_CLKS_SYNC`, where `c_CLKS_SYNC = c_CLKS_PER_BIT / 2`; shorter low pulses are rejected. In `c_RECEIVE`, each sampled bit is shifted into `r_RX_DATA` so an LSB-first UART frame reconstructs the byte in normal vector order. In `c_END`, a high stop bit copies `r_RX_DATA` to `w_READ_BYTE` and optionally pulses `w_WRITE_EN`; a low or unknown stop bit moves the machine to `c_WAIT` without writing the byte.

`fifo_queue` is a synchronous circular queue with `r_READ_IDX`, `r_WRITE_IDX`, and `r_NUM_ITEMS`. `o_queue_empty` and `o_queue_full` are derived from `r_NUM_ITEMS`. A read-only cycle removes the oldest entry and updates `o_read_data`; a write-only cycle stores `i_write_data` if the queue is not full. Simultaneous read/write has three special cases: normal non-empty/non-full operation reads the oldest entry and writes the new entry without changing the item count; when empty, the write data passes directly to `o_read_data` without being stored; when full, the oldest entry is read, the new write is dropped, and the queue becomes non-full.

`button_debouncer` uses a clocked process with active-high synchronous reset. It has two synchronization registers, a debounced state register, a counter from `0` to `c_DEBOUNCE_CYCLES`, and a one-cycle pulse output. When the observed button level differs from the debounced state for the configured count, `r_DEBOUNCED` updates and `r_PULSE` is assigned the new raw button level. In the supplied top level, the debouncer reset inputs are tied low, so the board reset button resets the UART cores but not the debouncer instances themselves.

## Implementation Results

Implementation results depend on the selected FPGA part, tool version, constraints, and generic values. The implementation results that were reported were obtained from the implementation of the top level demonstration file that combines both the transmitter and receiver units. Using the units individually or in a different context may result with different timing and utilization reports.

### Setup

| Item | Value |
| ---- | ----- |
| Constraint File | `constrs/basys3_master_top_tx_rx.xdc` |
| Board/Pinout Context | Basys 3-style switches, LEDs, buttons, and USB-RS232 pins |
| Clock Constraint | `create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports i_clk]` |
| Important Configuration | `c_WIDTH = 8`, `c_DEPTH = 8`, `c_UART_BAUD = 9600`, `c_CLK_FREQ = 100_000_000` in `top_rx_tx` defaults |
| Report Type | No synthesis or implementation reports are present |

### Timing

| Metric | Value |
| ------ | ----- |
| Worst Negative Slack (WNS) | Not available; no timing report is present |
| Total Negative Slack (TNS) | Not available; no timing report is present |
| Worst Hold Slack (WHS) | Not available; no timing report is present |
| Total Hold Slack (THS) | Not available; no timing report is present |

### Utilization

| Resource | Used |
| -------- | ---- |
| LUT | Not available; no utilization report is present |
| LUTRAM | Not available; no utilization report is present |
| FF | Not available; no utilization report is present |
| BRAM | Not available; no utilization report is present |
| DSP | Not available; no utilization report is present |
| IO | Not available; no utilization report is present |

## Verification

The repository contains self-checking VHDL testbenches in `tb/`. They use `assert ... severity failure` checks and `report` messages. Each bench ends with `assert false report "ALL TESTS PASSED" severity failure`, so a successful run is indicated by all earlier checks passing and the final intentional termination message appearing.

Testbench files:

- `tb/fifo_queue_tb.vhd`
- `tb/tx_frame_writer_tb.vhd`
- `tb/rx_frame_reader_tb.vhd`
- `tb/uart_tx_tb.vhd`
- `tb/uart_rx_tb.vhd`

Covered test cases:

### `tb/tx_frame_writer_tb.vhd` :
- Idle behavior checks that `o_tx_port` stays high and `o_read_en` stays low while the buffer is empty.
- Read request behavior checks that `o_read_en` asserts after `i_buffer_empty` goes low and that the pulse is one clock.
- Frame generation checks transmission of `x"00"`, `x"FF"`, `x"A6"`, and `x"80"` as start bit, LSB-first data bits, and stop bit.
- Data capture checks that changing `i_data` after the capture point does not alter the frame already being transmitted.
- Back-to-back frame behavior checks that a still-non-empty buffer causes another read request after the previous frame completes.
- Empty-after-frame behavior checks that no extra frame is generated once the buffer becomes empty.

### `tb/rx_frame_reader_tb.vhd` :
- Idle behavior checks that no write pulse occurs while the RX line is idle high.
- receive behavior checks decoding of `x"00"`, `x"FF"`, `x"A6"`, and `x"80"` from LSB-first serial frames.
- Write request behavior checks that `o_write_en` is a one-clock pulse and `o_read_byte` matches and remains stable after a valid frame.
- back-to-back serial frames check that two adjacent valid frames produce two decoded bytes.
- Buffer-full behavior checks that no write pulse is generated while `i_buffer_full = '1'`, that clearing full does not create a late write for the rejected byte, and that a later valid frame is accepted.
- Invalid stop bit, short start glitch, unknown RX value, and reset-mid-receive cases check that bad or interrupted frames do not write data and that the reader recovers after the line returns idle high.

### `tb/uart_tx_tb.vhd` :
- Wrapper-level TX tests check reset/idle behavior, single-byte frames, LSB-first order, FIFO-preserved transmit order, no extra frames after FIFO empty, full FIFO rejection of an extra write, and recovery after reset during transmission.

### `tb/uart_rx_tb.vhd` :
- Wrapper-level RX tests check reset/idle behavior, read-when-empty recovery, single-byte receive cases, LSB-first order, FIFO-preserved receive order, dropped extra frame while the RX FIFO is full, invalid stop rejection, short start glitch rejection, reset during receive, reset clearing queued FIFO data, and recovery after each exceptional case.



## Waveforms

On-board demonstrations and oscilloscope images are coming.


## Notes / Limitations

- The implemented UART framing is 8N1-style: one low start bit, `c_WIDTH` data bits sent and received LSB-first, and one high stop bit. Parity, multiple stop bits, break detection, and configurable protocol modes are not implemented.
- Reset inputs inside the RTL are active-high and synchronous to `i_clk`.
- Baud timing uses integer division in `c_CLKS_PER_BIT := c_CLK_FREQ / c_UART_BAUD`; fractional baud-rate error is not compensated.
- The design uses a single clock domain internally. External switch, button, and RX inputs are board-level asynchronous signals; the top level includes two-register synchronizers for switches and RX, and debouncers for buttons.
- `uart_rx` exposes `o_buffer_empty`, but not RX FIFO full status. A valid received byte is not written when the internal FIFO is full, so overflow is a drop condition with no public error flag.
- `rx_frame_reader` rejects a low stop bit and waits for the RX line to return high before looking for the next start bit.
- The top-level reset button is debounced into a single-clock reset pulse for the UART cores. It is not a level reset held for the full duration of the physical button press.