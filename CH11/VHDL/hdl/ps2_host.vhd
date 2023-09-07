-- ps2_host.vhd
-- ------------------------------------
-- PS/2 host controller interface
-- ------------------------------------
-- Author : Frank Bruno, Guy Eschemann
-- Takes a PS/2 interface and generate data back into the FPGA.
-- Also allows the FPGA to communicate wit hthe PS/2 device.
-- Currently only keyboards are supported

LIBRARY IEEE, XPM;
USE IEEE.std_logic_1164.all;
USE ieee.numeric_std.all;
use IEEE.math_real.all;
use XPM.vcomponents.all;

entity ps2_host is
  generic(
    CLK_PER : integer := 5;
    CYCLES  : integer := 32);
  port(
    clk      : in    std_logic;         -- 200 MHz
    reset    : in    std_logic;
    ps2_clk  : inout std_logic;
    ps2_data : inout std_logic;
    -- Transmit data to the keyboard from the FPGA
    tx_valid : in    std_logic;
    tx_data  : in    std_logic_vector(7 downto 0);
    tx_ready : out   std_logic := '1';
    -- Data from the device to the FPGA
    rx_data  : out   std_logic_vector(7 downto 0);
    rx_user  : out   std_logic;
    rx_valid : out   std_logic;
    rx_ready : in    std_logic
  );
end entity ps2_host;

architecture rtl of ps2_host is

  type state_t is (
    IDLE, CLK_FALL0, CLK_FALL1,
    CLK_HIGH, XMIT0, XMIT1, XMIT2,
    XMIT3, XMIT4, XMIT5, XMIT6);

  type start_state_t is (
    START_IDLE, SEND_CMD, START0,
    START1, START2);

  type array8_t is array (natural range <>) of std_logic_vector(7 downto 0);

  type out_state_t is (OUT_IDLE, OUT_WAIT);

  constant COUNT_100us : integer := integer(100000 / CLK_PER);
  constant COUNT_20us  : integer := integer(20000 / CLK_PER);

  -- Host-to-keyboard initialization commands
  constant INIT_DATA : array8_t(0 to 9) := (
    x"ED", x"00", x"F2", x"ED", x"02", x"F3", x"20", x"F4", x"F3", x"00"
  );

  -- Expected receive keyboard-to-host commands
  constant RX_EXPECT : array8_t(0 to 10) := (
    x"AA",                              -- Self test
    x"FA",                              -- Ack
    x"FA",                              -- Ack
    x"AB",                              -- Ack + keyboard code
    x"FA",                              -- Ack
    x"FA",                              -- Ack
    x"FA",                              -- Ack
    x"FA",                              -- Ack
    x"FA",                              -- Ack
    x"FA",                              -- Ack
    x"FA");                             -- Ack

  -- Registered signals with initial values
  signal counter_100us      : integer range 0 to COUNT_100us := 0;
  signal ps2_clk_clean_last : std_logic                      := '0';
  signal ps2_clk_en         : std_logic                      := '0';
  signal ps2_data_en        : std_logic                      := '0';
  signal data_capture       : std_logic_vector(10 downto 0)  := (others => '0');
  signal data_counter       : integer range 0 to 15          := 0;
  signal done               : std_logic                      := '0';
  signal err                : std_logic                      := '0';
  signal tx_xmit            : std_logic                      := '0';
  signal tx_data_capt       : std_logic_vector(7 downto 0); -- REVIEW
  signal state              : state_t                        := IDLE;
  signal start_state        : start_state_t                  := START_IDLE;
  signal send_set           : std_logic                      := '0';
  signal clr_set            : std_logic                      := '0';
  signal send_data          : std_logic_vector(7 downto 0)   := (others => '0');
  signal start_count        : integer range 0 to 10          := 0;
  signal tx_data_out        : std_logic_vector(10 downto 0)  := (others => '0');
  signal xmit_ready         : std_logic                      := '0';
  signal out_state          : out_state_t                    := OUT_IDLE;

  -- Unregistered signals
  signal ps2_clk_clean  : std_logic;
  signal ps2_data_clean : std_logic;

begin

  -- Enable drives a 0 out on the clock or data lines
  ps2_clk  <= '0' when ps2_clk_en else 'Z';
  ps2_data <= '0' when ps2_data_en else 'Z';

  --------------------------------------------------------------------------------------------------
  -- Debounce the PS/2 clock and data signals
  --------------------------------------------------------------------------------------------------

  u_debounce0 : entity work.debounce
    generic map(
      CYCLES => CYCLES
    )
    port map(
      clk     => clk,
      reset   => reset,
      sig_in  => to_x01(ps2_clk),
      sig_out => ps2_clk_clean);

  u_debounce1 : entity work.debounce
    generic map(
      CYCLES => CYCLES
    )
    port map(
      clk     => clk,
      reset   => reset,
      sig_in  => to_x01(ps2_data),
      sig_out => ps2_data_clean);

  --------------------------------------------------------------------------------------------------
  -- REVIEW: what does this do?
  --------------------------------------------------------------------------------------------------

  process(clk)
  begin
    if rising_edge(clk) then
      if reset then
        tx_data_capt <= (others => '0');
        tx_ready     <= '0';
      else
        if tx_valid and tx_ready then
          tx_data_capt <= tx_data;
          tx_ready     <= '0';
        elsif tx_xmit then
          tx_ready <= '1';
        end if;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------------------------------------
  -- Keyboard initialization sequence FSM: sends host-to-keyboard commands from the INIT_DATA
  -- sequence in response to keyboard-to-host commands.
  --------------------------------------------------------------------------------------------------

  init_fsm : process(clk)
  begin
    if rising_edge(clk) then
      if reset then
        start_state <= START_IDLE;
        send_data   <= (others => '0');
        send_set    <= '0';
        start_count <= 0;
      else
        case start_state is

          when START_IDLE =>
            if rx_valid = '1' and rx_ready = '1' and rx_data = RX_EXPECT(start_count) then
              start_state <= SEND_CMD;
            end if;

          when SEND_CMD =>
            send_set    <= '1';
            send_data   <= INIT_DATA(start_count);
            start_count <= start_count + 1;
            start_state <= START0;

          when START0 =>
            if clr_set then
              send_set    <= '0';
              start_state <= START1;
            end if;

          when START1 =>
            if rx_valid = '1' and rx_ready = '1' and rx_data = RX_EXPECT(start_count) then
              if start_count = 10 then
                start_state <= START2;
              else
                start_state <= SEND_CMD;
              end if;
            end if;

          when START2 =>                -- @suppress "Dead state 'START2': state does not have outgoing transitions"
            null;

        end case;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------------------------------------
  -- PS/2 receive and transmit FSM
  --------------------------------------------------------------------------------------------------

  process(clk)
  begin
    if rising_edge(clk) then
      if reset then
        ps2_clk_en         <= '0';
        ps2_data_en        <= '0';
        done               <= '0';
        err                <= '0';
        tx_xmit            <= '0';
        clr_set            <= '0';
        ps2_clk_clean_last <= '0';
        counter_100us      <= 0;
        data_capture       <= (others => '0');
        data_counter       <= 0;
        tx_data_out        <= (others => '0');
        xmit_ready         <= '0';
        state              <= IDLE;
      else
        -- Defaults:
        ps2_clk_en         <= '0';
        ps2_data_en        <= '0';
        done               <= '0';
        err                <= '0';
        tx_xmit            <= '0';
        clr_set            <= '0';
        ps2_clk_clean_last <= ps2_clk_clean;

        case state is
          when IDLE =>
            -- Wait for a falling edge of the clock or we received
            -- a xmit request
            if counter_100us /= COUNT_100us then
              counter_100us <= counter_100us + 1;
              xmit_ready    <= '0';
            else
              xmit_ready <= '1';
            end if;
            data_counter <= 0;
            if not ps2_clk_clean and ps2_clk_clean_last then -- falling edge of ps2_clk
              -- Start receiving keyboard-to-host code
              counter_100us <= 0;
              state         <= CLK_FALL0;
--            elsif not tx_ready and xmit_ready then -- transmit request
--              counter_100us <= 0;
--              tx_data_out   <= '1' & xnor(tx_data) & tx_data & '0';
--              state         <= XMIT0;
            elsif send_set and xmit_ready then -- send initialization data
              clr_set       <= '1';
              counter_100us <= 0;
              tx_data_out   <= '1' & xnor(send_data) & send_data & '0';
              state         <= XMIT0;
            end if;

          when CLK_FALL0 =>
            -- Capture data
            data_capture <= ps2_data_clean & data_capture(10 downto 1);
            data_counter <= data_counter + 1;
            state        <= CLK_FALL1;

          when CLK_FALL1 =>
            -- Clock has gone low, wait for it to go high
            if ps2_clk_clean then
              state <= CLK_HIGH;
            end if;

          when CLK_HIGH =>
            if data_counter = 11 then
              counter_100us <= 0;
              done          <= '1';
              err           <= xnor(data_capture(9 downto 1));
              state         <= IDLE;
            elsif not ps2_clk_clean then
              state <= CLK_FALL0;
            end if;

          when XMIT0 =>
            --REVIEW            clr_set       <= '1';
            ps2_clk_en <= '1';          -- ps2_clk = 0
            if counter_100us = COUNT_100us then
              counter_100us <= 0;
              state         <= XMIT1;
            else
              counter_100us <= counter_100us + 1;
            end if;

          when XMIT1 =>
            ps2_data_en <= not tx_data_out(data_counter);
            ps2_clk_en  <= '1';         -- ps2_clk = 0
            if counter_100us = COUNT_20us then
              counter_100us <= 0;
              state         <= XMIT2;
            else
              counter_100us <= counter_100us + 1;
            end if;

          when XMIT2 =>
            ps2_clk_en  <= '0';         -- ps2_clk = 1
            ps2_data_en <= not (tx_data_out(data_counter));
            if not ps2_clk_clean and ps2_clk_clean_last then -- ps2_clk falling edge
              data_counter <= data_counter + 1;
              if data_counter = 9 then
                state <= XMIT3;
              end if;
            end if;

          when XMIT3 =>
            if not ps2_clk_clean and ps2_clk_clean_last then -- ps2_clk falling edge
              state <= XMIT4;
            end if;

          when XMIT4 =>
            if not ps2_data_clean then
              state <= XMIT5;
            end if;

          when XMIT5 =>
            if not ps2_clk_clean then
              state <= XMIT6;
            end if;

          when XMIT6 =>
            if ps2_data_clean and ps2_clk_clean then
              state <= IDLE;
            end if;

        end case;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------------------------------------
  -- RX data interface handshake
  --------------------------------------------------------------------------------------------------

  process(clk)
  begin
    if rising_edge(clk) then
      if reset then
        rx_data   <= (others => '0');
        rx_user   <= '0';
        rx_valid  <= '0';
        out_state <= OUT_IDLE;
      else
        case out_state is
          when OUT_IDLE =>
            if done then
              rx_data   <= data_capture(8 downto 1);
              rx_user   <= err;         -- error indicator
              rx_valid  <= '1';
              out_state <= OUT_WAIT;
            end if;
          when OUT_WAIT =>
            if rx_ready then
              rx_valid  <= '0';
              out_state <= OUT_IDLE;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture rtl;
