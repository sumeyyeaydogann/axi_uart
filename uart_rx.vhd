library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_rx is
    generic (
        G_CLK_FREQ : positive := 62_500_000;
        G_DEFAULT_BAUD : positive := 115_200
    );
    port (
        i_clk : in std_logic;
        i_rst_n : in std_logic;
        i_rx_en : in std_logic;
        i_clk_div : in std_logic_vector(15 downto 0);
        i_uart_rxd : in std_logic;
        o_rx_data : out std_logic_vector(7 downto 0);
        o_rx_valid : out std_logic;
        o_rx_busy : out std_logic;
        o_frame_err : out std_logic
    );
end entity uart_rx;

architecture rtl of uart_rx is

    constant C_DEFAULT_DIV : natural := G_CLK_FREQ / G_DEFAULT_BAUD;

    type t_rx_state is (
        ST_IDLE,
        ST_START_BIT,
        ST_DATA_BITS,
        ST_STOP_BIT
    );

    signal r_state : t_rx_state := ST_IDLE;
    signal r_rx_meta : std_logic := '1';
    signal r_rx_sync : std_logic := '1';
    signal r_clk_cnt : unsigned(15 downto 0) := (others => '0');
    signal r_bit_max : unsigned(15 downto 0) := (others => '0');
    signal r_half_bit : unsigned(15 downto 0) := (others => '0');
    signal r_bit_idx : natural range 0 to 7 := 0;
    signal r_shreg : std_logic_vector(7 downto 0) := (others => '0');
    signal r_rx_data : std_logic_vector(7 downto 0) := (others => '0');
    signal r_rx_valid : std_logic := '0';
    signal r_rx_busy : std_logic := '0';
    signal r_frame_err : std_logic := '0';

begin

    o_rx_data <= r_rx_data;
    o_rx_valid <= r_rx_valid;
    o_rx_busy <= r_rx_busy;
    o_frame_err <= r_frame_err;

    p_sync : process(i_clk)
    begin
        if rising_edge(i_clk) then
            if i_rst_n = '0' then
                r_rx_meta <= '1';
                r_rx_sync <= '1';
            else
                r_rx_meta <= i_uart_rxd;
                r_rx_sync <= r_rx_meta;
            end if;
        end if;
    end process p_sync;

    p_uart_rx : process(i_clk)
        variable v_div_val : unsigned(15 downto 0);
    begin
        if rising_edge(i_clk) then
            if i_rst_n = '0' then
                r_state <= ST_IDLE;
                r_clk_cnt <= (others => '0');
                r_bit_max <= to_unsigned(C_DEFAULT_DIV - 1, 16);
                r_half_bit <= to_unsigned((C_DEFAULT_DIV / 2) - 1, 16);
                r_bit_idx <= 0;
                r_shreg <= (others => '0');
                r_rx_data <= (others => '0');
                r_rx_valid <= '0';
                r_rx_busy <= '0';
                r_frame_err <= '0';
            else
                r_rx_valid <= '0';
                r_frame_err <= '0';

                case r_state is

                    when ST_IDLE =>
                        r_clk_cnt <= (others => '0');
                        r_bit_idx <= 0;
                        r_rx_busy <= '0';
                        if unsigned(i_clk_div) >= 4 then
                            v_div_val := unsigned(i_clk_div);
                        else
                            v_div_val := to_unsigned(C_DEFAULT_DIV, 16);
                        end if;
                        r_bit_max <= v_div_val - 1;
                        r_half_bit <= shift_right(v_div_val, 1) - 1;
                        if i_rx_en = '1' and r_rx_sync = '0' then
                            r_rx_busy <= '1';
                            r_state <= ST_START_BIT;
                        end if;

                    when ST_START_BIT =>
                        r_rx_busy <= '1';
                        if r_clk_cnt = r_half_bit then
                            r_clk_cnt <= (others => '0');
                            if r_rx_sync = '0' then
                                r_bit_idx <= 0;
                                r_state <= ST_DATA_BITS;
                            else
                                r_rx_busy <= '0';
                                r_state <= ST_IDLE;
                            end if;
                        else
                            r_clk_cnt <= r_clk_cnt + 1;
                        end if;

                    when ST_DATA_BITS =>
                        r_rx_busy <= '1';
                        if r_clk_cnt = r_bit_max then
                            r_clk_cnt <= (others => '0');
                            r_shreg(r_bit_idx) <= r_rx_sync;
                            if r_bit_idx = 7 then
                                r_state <= ST_STOP_BIT;
                            else
                                r_bit_idx <= r_bit_idx + 1;
                            end if;
                        else
                            r_clk_cnt <= r_clk_cnt + 1;
                        end if;

                    when ST_STOP_BIT =>
                        r_rx_busy <= '1';
                        if r_clk_cnt = r_bit_max then
                            r_clk_cnt <= (others => '0');
                            r_rx_busy <= '0';
                            if r_rx_sync = '1' then
                                r_rx_data <= r_shreg;
                                r_rx_valid <= '1';
                            else
                                r_frame_err <= '1';
                            end if;
                            r_state <= ST_IDLE;
                        else
                            r_clk_cnt <= r_clk_cnt + 1;
                        end if;

                    when others =>
                        r_state <= ST_IDLE;

                end case;
            end if;
        end if;
    end process p_uart_rx;

end architecture rtl;