# Basys 3 UART TX/RX Demo

`top_tx_rx.vhd` contains the `top_rx_tx` entity, a simple Basys 3 demonstration top level for the UART transmitter and receiver in this repository. It connects the reusable `uart_tx` and `uart_rx` cores to board switches, push buttons, LEDs, and the USB-RS232 serial pins.

The top level is intended as a manual hardware demo. A byte is selected with switches, sent with a button press, received serial data is buffered by the RX core, and another button press reads the next received byte onto LEDs.

## Files

- `rtl/top/top_tx_rx.vhd`: top-level VHDL entity.
- `constrs/basys3_master_top_tx_rx.xdc`: Basys 3 pin and clock constraints for this top level.
- `rtl/design/uart_tx.vhd`: transmit wrapper instantiated by the top level.
- `rtl/design/uart_rx.vhd`: receive wrapper instantiated by the top level.
- `rtl/extern/button_debouncer.vhd`: button debouncer used for reset, send, and receive/read buttons.

## Basic Use

Make sure that the files that were described are added inside the same work environment. Program the design with `top_rx_tx` as the top entity and include `constrs/basys3_master_top_tx_rx.xdc` in the Vivado project. The supplied constraints map `i_clk` to the Basys 3 100 MHz clock and map `i_rx_port`/`o_tx_port` to the USB-RS232 interface. To see the bytes sent by the board and send bytes to the board, open any valid serial terminal and connect to the corresponding port of the Basys 3 board with correct BAUD. 

To send a byte:

1. Set `i_switch_data[7:0]` with the Basys 3 switches.
2. Press the send button connected to `i_btn_send`.
3. The debouncer creates a one-clock `w_WRITE_EN_PULSE`.
4. `uart_tx` writes the synchronized switch byte into its FIFO and transmits it on `o_tx_port` as an idle-high UART frame with start bit `0`, 8 data bits LSB-first, and stop bit `1`.

To read a received byte:

1. Drive a compatible UART serial signal into `i_rx_port`.
2. `uart_rx` receives valid frames and stores decoded bytes in its RX FIFO.
3. Press the receive/read button connected to `i_btn_recv`.
4. The debouncer creates a one-clock `w_READ_EN_PULSE`.
5. `uart_rx` reads one queued byte and presents it on `o_led_rx_data`.

To reset the UART cores:

1. Press the reset button connected to `i_btn_rst`.
2. The debouncer creates a one-clock active-high `w_RST_PULSE`.
3. The pulse resets `uart_tx` and `uart_rx`.

The reset button does not reset the three `button_debouncer` instances because their `i_rst` ports are tied to `'0'` in this top level.

## Board Controls

| Board Function | Top-Level Signal | Use |
| -------------- | ---------------- | --- |
| 100 MHz clock | `i_clk` | Main clock for the whole design. |
| Switches `SW0`-`SW7` | `i_switch_data[7:0]` | Byte selected for transmission. |
| Reset button | `i_btn_rst` | Generates a single-clock reset pulse for the UART cores. |
| Send button | `i_btn_send` | Generates a single-clock TX FIFO write request. |
| Receive/read button | `i_btn_recv` | Generates a single-clock RX FIFO read request. |
| TX LEDs | `o_led_tx_data[7:0]` | Shows the synchronized switch byte. |
| RX LEDs | `o_led_rx_data[7:0]` | Shows the last byte read from the RX FIFO. |
| USB-RS232 RX | `i_rx_port` | Serial input to the receiver. |
| USB-RS232 TX | `o_tx_port` | Serial output from the transmitter. |

## Generics

| Generic | Default | Description |
| ------- | ------- | ----------- |
| `c_DEBOUNCE_CYCLES` | `1048575` | Debounce interval in `i_clk` cycles for each push button. |
| `c_WIDTH` | `8` | Width of the switch and LED data buses. The included UART wrapper ports are fixed at 8 bits, so this top level should be used as an 8-bit design unless the lower-level interfaces are updated. |
| `c_DEPTH` | `8` | Number of entries in the TX and RX FIFOs. |
| `c_UART_BAUD` | `9600` | UART baud rate used by the TX and RX cores. |
| `c_CLK_FREQ` | `100_000_000` | Input clock frequency in hertz. |

## Ports

| Port | Direction | Description |
| ---- | --------- | ----------- |
| `i_clk` | in | Main synchronous clock. The XDC constrains this as a 10 ns, 100 MHz clock. |
| `i_btn_rst` | in | Raw active-high reset button input. Debounced into `w_RST_PULSE`. |
| `i_btn_send` | in | Raw active-high send button input. Debounced into `w_WRITE_EN_PULSE`. |
| `i_btn_recv` | in | Raw active-high receive/read button input. Debounced into `w_READ_EN_PULSE`. |
| `i_switch_data` | in | `c_WIDTH`-bit switch byte. It is sampled through two registers before being used. |
| `i_rx_port` | in | UART serial receive input. It is synchronized through two registers before reaching `uart_rx`. |
| `o_led_tx_data` | out | Synchronized copy of `i_switch_data`, shown on LEDs. |
| `o_led_rx_data` | out | Byte read from the RX FIFO, shown on LEDs. |
| `o_tx_port` | out | UART serial transmit output from `uart_tx`; idle level is high. |

## Internal Connections

`top_rx_tx` instantiates one transmitter, one receiver, and three button debouncers:

- `e_UART_TX` maps the synchronized switch byte to `uart_tx.i_tx_write_data`. Its `o_buffer_full` flag is left open, so the board demo does not display TX FIFO full status.
- `e_UART_RX` maps the synchronized serial input to `uart_rx.i_rx_port`. Its `o_buffer_empty` flag is left open, so the board demo does not display RX FIFO empty status.
- `e_BTN_RST`, `e_BTN_SEND`, and `e_BTN_RECV` convert raw button inputs into one-clock pulses.

Two small synchronizer processes handle external board inputs:

- `p_SWITCH_SYNC` samples `i_switch_data` through `r_SWITCH_DATA_SYNC_1` and `r_SWITCH_DATA_SYNC_2`.
- `p_RX_SYNC` samples `i_rx_port` through `r_RX_SYNC_1` and `r_RX_SYNC_2`.

## Usage Notes

- The UART line is expected to idle high.
- The top level gives manual control over FIFO writes and reads; pressing send writes the current switch byte, and pressing receive/read consumes one queued RX byte.
- There is no visible full or empty indicator in this top-level demo because the UART wrapper status outputs are left unconnected.
- Button actions occur after debounce, so a button must remain stable for `c_DEBOUNCE_CYCLES` clock cycles before the pulse is generated, not an issue but be warned.
- `o_led_rx_data` updates only when a read from the RX FIFO is accepted; otherwise it retains the previous read value.
- If the RX FIFO fills before the user presses the receive/read button enough times, additional received frames may be dropped by the lower-level RX path.
