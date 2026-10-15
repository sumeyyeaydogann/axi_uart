library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
    generic (
        G_CLK_FREQ : positive := 62_500_000;
        G_DEFAULT_BAUD : positive := 115_200
    );
    port (
        i_clk : in std_logic;
        i_rst_n : in std_logic;
        i_tx_en : in std_logic;
        i_clk_div : in std_logic_vector(15 downto 0);
        i_tx_data : in std_logic_vector(7 downto 0);
        i_tx_valid : in std_logic;
        o_tx_ready : out std_logic;
        o_tx_busy : out std_logic;
        o_uart_txd : out std_logic
    );
end entity uart_tx;

architecture rtl of uart_tx is

    constant C_DEFAULT_DIV : natural := G_CLK_FREQ / G_DEFAULT_BAUD;

    type t_tx_state is (
        ST_IDLE,
        ST_START_BIT,
        ST_DATA_BITS,
        ST_STOP_BIT
    );

    signal r_state : t_tx_state := ST_IDLE;
    signal r_clk_cnt : unsigned(15 downto 0) := (others => '0');
    signal r_bit_max : unsigned(15 downto 0) := (others => '0');
    signal r_bit_idx : natural range 0 to 7 := 0;
    signal r_shreg : std_logic_vector(7 downto 0) := (others => '0');
    signal r_txd : std_logic := '1';
    signal r_tx_ready : std_logic := '0';
    signal r_tx_busy : std_logic := '0';

begin

    o_uart_txd <= r_txd;
    o_tx_ready <= r_tx_ready;
    o_tx_busy <= r_tx_busy;

    p_uart_tx : process(i_clk)
        variable v_div_val : unsigned(15 downto 0);
    begin
        if rising_edge(i_clk) then
            if i_rst_n = '0' then
                r_state <= ST_IDLE;
                r_clk_cnt <= (others => '0');
                r_bit_max <= to_unsigned(C_DEFAULT_DIV - 1, 16);
                r_bit_idx <= 0;
                r_shreg <= (others => '0');
                r_txd <= '1';
                r_tx_ready <= '0';
                r_tx_busy <= '0';
            else
                case r_state is

                    when ST_IDLE =>
                        r_txd <= '1';
                        r_clk_cnt <= (others => '0');
                        r_bit_idx <= 0;
                        if unsigned(i_clk_div) >= 4 then
                            v_div_val := unsigned(i_clk_div) - 1;
                        else
                            v_div_val := to_unsigned(C_DEFAULT_DIV - 1, 16);
                        end if;
                        r_bit_max <= v_div_val;
                        if i_tx_en = '1' then
                            r_tx_ready <= '1';
                        else
                            r_tx_ready <= '0';
                        end if;
                        if i_tx_en = '1' and i_tx_valid = '1' and r_tx_ready = '1' then
                            r_shreg <= i_tx_data;
                            r_tx_ready <= '0';
                            r_tx_busy <= '1';
                            r_txd <= '0';
                            r_state <= ST_START_BIT;
                        else
                            r_tx_busy <= '0';
                        end if;

                    when ST_START_BIT =>
                        r_txd <= '0';
                        r_tx_ready <= '0';
                        r_tx_busy <= '1';
                        if r_clk_cnt = r_bit_max then
                            r_clk_cnt <= (others => '0');
                            r_txd <= r_shreg(0);
                            r_bit_idx <= 0;
                            r_state <= ST_DATA_BITS;
                        else
                            r_clk_cnt <= r_clk_cnt + 1;
                        end if;

                    when ST_DATA_BITS =>
                        r_txd <= r_shreg(r_bit_idx);
                        r_tx_ready <= '0';
                        r_tx_busy <= '1';
                        if r_clk_cnt = r_bit_max then
                            r_clk_cnt <= (others => '0');
                            if r_bit_idx = 7 then
                                r_txd <= '1';
                                r_state <= ST_STOP_BIT;
                            else
                                r_bit_idx <= r_bit_idx + 1;
                            end if;
                        else
                            r_clk_cnt <= r_clk_cnt + 1;
                        end if;

                    when ST_STOP_BIT =>
                        r_txd <= '1';
                        r_tx_ready <= '0';
                        r_tx_busy <= '1';
                        if r_clk_cnt = r_bit_max then
                            r_clk_cnt <= (others => '0');
                            r_tx_busy <= '0';
                            r_state <= ST_IDLE;
                        else
                            r_clk_cnt <= r_clk_cnt + 1;
                        end if;

                    when others =>
                        r_state <= ST_IDLE;

                end case;
            end if;
        end if;
    end process p_uart_tx;

end architecture rtl;