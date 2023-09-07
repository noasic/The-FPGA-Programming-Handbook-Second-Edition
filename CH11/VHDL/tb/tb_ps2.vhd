-- tb_ps2.sv
-- ------------------------------------
-- Testbench for the PS/2 module
-- ------------------------------------
-- Author : Frank Bruno, Guy Eschemann
-- Runs through a simple init sequence of the PS/2 as captured

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

use std.textio.all;

entity tb_ps2 is
end entity tb_ps2;

architecture tb of tb_ps2 is

  procedure log(str : string) is
    variable line : line;
  begin
    write(line, to_string(now) & ": " & str);
    writeline(output, line);
  end procedure;

  procedure wait_nclk(signal clk : std_ulogic; n : positive) is
  begin
    for i in 1 to n loop
      wait until rising_edge(clk);
    end loop;
  end procedure wait_nclk;

  procedure rx_key(
    signal   clk       : in std_logic;
    constant exp_data  : in std_logic_vector(7 downto 0);
    signal   ps2_clk   : in std_logic;
    signal   ps2_data  : in std_logic;
    signal   ps2_clk0  : out std_logic;
    signal   ps2_data0 : out std_logic) is
    variable edge_count : integer range 0 to 16 := 0;
    variable data_capt  : std_logic_vector(10 downto 0);
  begin
    -- Wait for ED
    edge_count := 0;
    -- Wait for first falling edge, then rising edge
    wait until falling_edge(ps2_clk);
    wait until rising_edge(ps2_clk);
    while edge_count < 10 loop
      wait_nclk(clk, 100);
      ps2_clk0              <= '1';
      wait_nclk(clk, 100);
      if edge_count = 10 then
        ps2_data0 <= '1';
      end if;
      data_capt(edge_count) := to_x01(ps2_data);
      edge_count            := edge_count + 1;
      ps2_clk0              <= '0';
    end loop;
    wait_nclk(clk, 100);
    ps2_data0  <= '1';
    wait_nclk(clk, 100);
    ps2_clk0   <= '1';
    wait_nclk(clk, 100);
    ps2_data0  <= '0';
    ps2_clk0   <= '0';
    wait_nclk(clk, 100);
    log("Captured data: " & to_hstring(data_capt(7 downto 0)));
    assert data_capt(7 downto 0) = exp_data
    report "Data miscompared! Expected " & to_hstring(exp_data) & " /= " & to_hstring(data_capt(8 downto 1)) severity error;
  end procedure;

  procedure send_key(
    signal   clk       : in std_logic;
    constant keycode   : in std_logic_vector(7 downto 0);
    constant error     : in std_logic;
    signal   ps2_clk0  : out std_logic;
    signal   ps2_data0 : out std_logic) is
  begin
    ps2_clk0  <= '0';
    ps2_data0 <= '0';
    wait_nclk(clk, 500);
    -- Drive data low
    ps2_data0 <= '1';
    wait_nclk(clk, 1000);
    -- first falling edge of the clock
    ps2_clk0  <= '1';
    wait_nclk(clk, 2000);
    for i in 0 to 7 loop
      if keycode(i) then
        ps2_data0 <= '0';
      else
        ps2_data0 <= '1';
      end if;
      wait_nclk(clk, 2000);
      ps2_clk0 <= '0';
      wait_nclk(clk, 4000);
      ps2_clk0 <= '1';
      wait_nclk(clk, 2000);
    end loop;
    -- parity
    if xor(keycode & error) then
      ps2_data0 <= '1';
    else
      ps2_data0 <= '0';
    end if;
    wait_nclk(clk, 2000);
    ps2_clk0  <= '0';
    wait_nclk(clk, 4000);
    ps2_clk0  <= '1';
    wait_nclk(clk, 2000);
    --s stop bit
    ps2_data0 <= '0';
    wait_nclk(clk, 2000);
    ps2_clk0  <= '0';
    wait_nclk(clk, 4000);
    ps2_clk0  <= '1';
    wait_nclk(clk, 4000);
    ps2_clk0  <= '0';
    wait_nclk(clk, 10000);
  end procedure;

  constant CYCLES  : integer := 16;
  constant CLK_PER : integer := 10;

  signal clk   : std_logic := '0';
  signal reset : std_logic := '0';

  signal ps2_clk   : std_logic;
  signal ps2_data  : std_logic;
  signal ps2_clk0  : std_logic := '0';
  signal ps2_data0 : std_logic := '0';

  -- Data from the device to the FPGA
  signal rx_data  : std_logic_vector(7 downto 0);
  signal rx_user  : std_logic;          -- Error indicator
  signal rx_valid : std_logic;
  signal rx_ready : std_logic;

begin

  clk <= not clk after (CLK_PER / 2) * 1 ns;

  reset <= '1', '0' after (CLK_PER * 10) * 1 ns;

  ps2_clk  <= '0' when ps2_clk0 else 'Z';
  ps2_data <= '0' when ps2_data0 else 'Z';
  ps2_clk  <= 'H';
  ps2_data <= 'H';

  rx_ready <= '1';

  u_ps2_host : entity work.ps2_host
    generic map(
      CLK_PER => CLK_PER,
      CYCLES  => CYCLES
    )
    port map(
      clk      => clk,
      reset    => reset,
      ps2_clk  => ps2_clk,
      ps2_data => ps2_data,
      tx_valid => '0',
      tx_data  => (others => '0'),
      tx_ready => open,
      rx_data  => rx_data,
      rx_user  => rx_user,              -- Error indicator
      rx_valid => rx_valid,
      rx_ready => rx_ready);

  stim : process
  begin
    log("0: send self test passed");
    wait_nclk(clk, 100);
    send_key(clk, x"AA", '0', ps2_clk0, ps2_data0);
    log("Wait for response");
    rx_key(clk, x"ED", ps2_clk, ps2_data, ps2_clk0, ps2_data0);

    log("1: send 00");
    wait_nclk(clk, 100);
    send_key(clk, x"FA", '0', ps2_clk0, ps2_data0);
    -- Wait for response
    rx_key(clk, x"00", ps2_clk, ps2_data, ps2_clk0, ps2_data0);

    log("2: send f2");
    wait_nclk(clk, 100);
    send_key(clk, x"FA", '0', ps2_clk0, ps2_data0);
    log("Wait for response");
    rx_key(clk, x"F2", ps2_clk, ps2_data, ps2_clk0, ps2_data0);

    log("3: send fA, AB");
    wait_nclk(clk, 100);
    send_key(clk, x"FA", '0', ps2_clk0, ps2_data0);
    send_key(clk, x"AB", '0', ps2_clk0, ps2_data0);
    log("Wait for response");
    rx_key(clk, x"ED", ps2_clk, ps2_data, ps2_clk0, ps2_data0);

    log("4: send fA");
    wait_nclk(clk, 100);
    send_key(clk, x"FA", '0', ps2_clk0, ps2_data0);
    log("Wait for response");
    rx_key(clk, x"02", ps2_clk, ps2_data, ps2_clk0, ps2_data0);

    log("5: send fA");
    wait_nclk(clk, 100);
    send_key(clk, x"FA", '0', ps2_clk0, ps2_data0);
    log("Wait for response");
    rx_key(clk, x"F3", ps2_clk, ps2_data, ps2_clk0, ps2_data0);

    log("6: send fA");
    wait_nclk(clk, 100);
    send_key(clk, x"FA", '0', ps2_clk0, ps2_data0);
    log("Wait for response");
    rx_key(clk, x"20", ps2_clk, ps2_data, ps2_clk0, ps2_data0);

    log("7: send fA");
    wait_nclk(clk, 100);
    send_key(clk, x"FA", '0', ps2_clk0, ps2_data0);
    log("Wait for response");
    rx_key(clk, x"F4", ps2_clk, ps2_data, ps2_clk0, ps2_data0);

    log("8: send fA");
    wait_nclk(clk, 100);
    send_key(clk, x"FA", '0', ps2_clk0, ps2_data0);
    log("Wait for response");
    rx_key(clk, x"F3", ps2_clk, ps2_data, ps2_clk0, ps2_data0);

    log("9: send fA");
    wait_nclk(clk, 100);
    send_key(clk, x"FA", '0', ps2_clk0, ps2_data0);
    log("Wait for response");
    rx_key(clk, x"00", ps2_clk, ps2_data, ps2_clk0, ps2_data0);

    wait_nclk(clk, 100);
    send_key(clk, x"55", '0', ps2_clk0, ps2_data0);
    wait_nclk(clk, 100);
    send_key(clk, x"AA", '0', ps2_clk0, ps2_data0);
    wait_nclk(clk, 100);
    send_key(clk, x"55", '1', ps2_clk0, ps2_data0);
    wait_nclk(clk, 100);
    send_key(clk, x"AA", '1', ps2_clk0, ps2_data0);
    wait_nclk(clk, 100);
    wait;
  end process;

  check : process
    variable exp_data    : std_logic_vector(7 downto 0);
    variable exp_user    : std_logic;
    variable valid_count : integer;
  begin
    valid_count := 0;
    while valid_count < 15 loop
      wait on clk until rising_edge(clk) and rx_valid = '1';
      if valid_count >= 11 and valid_count <= 14 then
        if valid_count = 11 then
          exp_data := x"55";
          exp_user := '0';
        elsif valid_count = 12 then
          exp_data := x"AA";
          exp_user := '0';
        elsif valid_count = 13 then
          exp_data := x"55";
          exp_user := '1';
        elsif valid_count = 14 then
          exp_data := x"AA";
          exp_user := '1';
        end if;
        assert exp_data = rx_data and exp_user = rx_user report "mismatch on output " & to_string(valid_count) severity failure;
        log("output matched " & to_string(valid_count));
      end if;
      valid_count := valid_count + 1;
    end loop;
    std.env.stop;
  end process;

end architecture;
