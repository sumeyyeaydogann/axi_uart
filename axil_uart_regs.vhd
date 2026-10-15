library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.crc16_pkg.all;

entity axil_uart_regs is
    generic (
        G_CLK_FREQ : positive := 62_500_000;
        G_DEFAULT_BAUD : positive := 115_200;
        G_DEFAULT_SOF : std_logic_vector(15 downto 0) := x"A55A"
    );
    port (
        i_clk : in std_logic;
        i_rst_n : in std_logic;
        s_axil_awaddr : in std_logic_vector(7 downto 0);
        s_axil_awprot : in std_logic_vector(2 downto 0);
        s_axil_awvalid : in std_logic;
        s_axil_awready : out std_logic;
        s_axil_wdata : in std_logic_vector(31 downto 0);
        s_axil_wstrb : in std_logic_vector(3 downto 0);
        s_axil_wvalid : in std_logic;
        s_axil_wready : out std_logic;
        s_axil_bresp : out std_logic_vector(1 downto 0);
        s_axil_bvalid : out std_logic;
        s_axil_bready : in std_logic;
        s_axil_araddr : in std_logic_vector(7 downto 0);
        s_axil_arprot : in std_logic_vector(2 downto 0);
        s_axil_arvalid : in std_logic;
        s_axil_arready : out std_logic;
        s_axil_rdata : out std_logic_vector(31 downto 0);
        s_axil_rresp : out std_logic_vector(1 downto 0);
        s_axil_rvalid : out std_logic;
        s_axil_rready : in std_logic;
        o_core_en : out std_logic;
        o_tx_en : out std_logic;
        o_rx_en : out std_logic;
        o_loopback_en : out std_logic;
        o_soft_rst : out std_logic;
        o_clk_div : out std_logic_vector(15 downto 0);
        o_sof_val : out std_logic_vector(15 downto 0);
        i_tx_busy : in std_logic;
        i_rx_busy : in std_logic;
        i_tx_axis_ready : in std_logic;
        i_rx_axis_valid : in std_logic;
        i_tx_pkt_done : in std_logic;
        i_tx_len_err : in std_logic;
        i_rx_good_pkt : in std_logic;
        i_rx_crc_err : in std_logic;
        i_rx_len_err : in std_logic;
        i_rx_frame_err : in std_logic;
        i_last_tx_len : in std_logic_vector(15 downto 0);
        i_last_rx_blen : in std_logic_vector(15 downto 0);
        i_last_rx_crc : in std_logic_vector(15 downto 0);
        i_last_calc_crc : in std_logic_vector(15 downto 0)
    );
end entity axil_uart_regs;

architecture rtl of axil_uart_regs is

    constant C_INIT_DIV : natural := G_CLK_FREQ / G_DEFAULT_BAUD;

    signal r_awready : std_logic := '0';
    signal r_wready : std_logic := '0';
    signal r_bvalid : std_logic := '0';
    signal r_arready : std_logic := '0';
    signal r_rvalid : std_logic := '0';
    signal r_rdata : std_logic_vector(31 downto 0) := (others => '0');

    signal r_ctrl_reg : std_logic_vector(31 downto 0) := x"00000007";
    signal r_baud_div : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(C_INIT_DIV, 16));
    signal r_sof_val : std_logic_vector(15 downto 0) := G_DEFAULT_SOF;
    signal r_soft_rst : std_logic := '0';
    signal r_clr_cnt : std_logic := '0';

    signal r_tx_pkt_cnt : unsigned(31 downto 0) := (others => '0');
    signal r_rx_good_cnt : unsigned(31 downto 0) := (others => '0');
    signal r_err_crc_cnt : unsigned(31 downto 0) := (others => '0');
    signal r_err_frame_cnt : unsigned(31 downto 0) := (others => '0');
    signal r_last_err_code : std_logic_vector(3 downto 0) := "0000";

begin

    s_axil_awready <= r_awready;
    s_axil_wready <= r_wready;
    s_axil_bresp <= "00";
    s_axil_bvalid <= r_bvalid;
    s_axil_arready <= r_arready;
    s_axil_rdata <= r_rdata;
    s_axil_rresp <= "00";
    s_axil_rvalid <= r_rvalid;

    o_core_en <= r_ctrl_reg(0);
    o_tx_en <= r_ctrl_reg(0) and r_ctrl_reg(1);
    o_rx_en <= r_ctrl_reg(0) and r_ctrl_reg(2);
    o_loopback_en <= r_ctrl_reg(3);
    o_soft_rst <= r_soft_rst;
    o_clk_div <= r_baud_div;
    o_sof_val <= r_sof_val;

    p_axil_write : process(i_clk)
        variable v_addr : std_logic_vector(5 downto 0);
    begin
        if rising_edge(i_clk) then
            if i_rst_n = '0' then
                r_awready <= '0';
                r_wready <= '0';
                r_bvalid <= '0';
                r_ctrl_reg <= x"00000007";
                r_baud_div <= std_logic_vector(to_unsigned(C_INIT_DIV, 16));
                r_sof_val <= G_DEFAULT_SOF;
                r_soft_rst <= '0';
                r_clr_cnt <= '0';
            else
                r_soft_rst <= '0';
                r_clr_cnt <= '0';

                if r_awready = '0' and s_axil_awvalid = '1' and s_axil_wvalid = '1' and (r_bvalid = '0' or s_axil_bready = '1') then
                    r_awready <= '1';
                    r_wready <= '1';
                    v_addr := s_axil_awaddr(7 downto 2);
                    case v_addr is
                        when "000000" =>
                            if s_axil_wstrb(0) = '1' then
                                r_ctrl_reg(7 downto 0) <= s_axil_wdata(7 downto 0);
                                r_soft_rst <= s_axil_wdata(4);
                                r_clr_cnt <= s_axil_wdata(5);
                            end if;
                        when "000001" =>
                            if s_axil_wstrb(0) = '1' then
                                r_baud_div(7 downto 0) <= s_axil_wdata(7 downto 0);
                            end if;
                            if s_axil_wstrb(1) = '1' then
                                r_baud_div(15 downto 8) <= s_axil_wdata(15 downto 8);
                            end if;
                        when "000010" =>
                            if s_axil_wstrb(0) = '1' then
                                r_sof_val(7 downto 0) <= s_axil_wdata(7 downto 0);
                            end if;
                            if s_axil_wstrb(1) = '1' then
                                r_sof_val(15 downto 8) <= s_axil_wdata(15 downto 8);
                            end if;
                        when others =>
                            null;
                    end case;
                    r_bvalid <= '1';
                else
                    r_awready <= '0';
                    r_wready <= '0';
                    if r_bvalid = '1' and s_axil_bready = '1' then
                        r_bvalid <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process p_axil_write;

    p_counters : process(i_clk)
    begin
        if rising_edge(i_clk) then
            if i_rst_n = '0' or r_soft_rst = '1' or r_clr_cnt = '1' then
                r_tx_pkt_cnt <= (others => '0');
                r_rx_good_cnt <= (others => '0');
                r_err_crc_cnt <= (others => '0');
                r_err_frame_cnt <= (others => '0');
                r_last_err_code <= "0000";
            else
                if i_tx_pkt_done = '1' then
                    r_tx_pkt_cnt <= r_tx_pkt_cnt + 1;
                end if;
                if i_rx_good_pkt = '1' then
                    r_rx_good_cnt <= r_rx_good_cnt + 1;
                end if;
                if i_rx_crc_err = '1' then
                    r_err_crc_cnt <= r_err_crc_cnt + 1;
                    r_last_err_code <= "0001";
                end if;
                if i_rx_len_err = '1' or i_rx_frame_err = '1' or i_tx_len_err = '1' then
                    r_err_frame_cnt <= r_err_frame_cnt + 1;
                    if i_rx_len_err = '1' then
                        r_last_err_code <= "0010";
                    elsif i_rx_frame_err = '1' then
                        r_last_err_code <= "0100";
                    else
                        r_last_err_code <= "1000";
                    end if;
                end if;
            end if;
        end if;
    end process p_counters;

    p_axil_read : process(i_clk)
        variable v_raddr : std_logic_vector(5 downto 0);
        variable v_status : std_logic_vector(31 downto 0);
    begin
        if rising_edge(i_clk) then
            if i_rst_n = '0' then
                r_arready <= '0';
                r_rvalid <= '0';
                r_rdata <= (others => '0');
            else
                if r_arready = '0' and s_axil_arvalid = '1' and (r_rvalid = '0' or s_axil_rready = '1') then
                    r_arready <= '1';
                    r_rvalid <= '1';
                    v_raddr := s_axil_araddr(7 downto 2);
                    v_status := (others => '0');
                    v_status(0) := i_tx_busy;
                    v_status(1) := i_rx_busy;
                    v_status(2) := i_tx_axis_ready;
                    v_status(3) := i_rx_axis_valid;
                    v_status(11 downto 8) := r_last_err_code;

                    case v_raddr is
                        when "000000" =>
                            r_rdata <= r_ctrl_reg;
                        when "000001" =>
                            r_rdata <= x"0000" & r_baud_div;
                        when "000010" =>
                            r_rdata <= x"0000" & r_sof_val;
                        when "000011" =>
                            r_rdata <= v_status;
                        when "000100" =>
                            r_rdata <= std_logic_vector(r_tx_pkt_cnt);
                        when "000101" =>
                            r_rdata <= std_logic_vector(r_rx_good_cnt);
                        when "000110" =>
                            r_rdata <= std_logic_vector(r_err_crc_cnt);
                        when "000111" =>
                            r_rdata <= std_logic_vector(r_err_frame_cnt);
                        when "001000" =>
                            r_rdata <= i_last_rx_crc & i_last_rx_blen;
                        when "001001" =>
                            r_rdata <= i_last_calc_crc & i_last_tx_len;
                        when others =>
                            r_rdata <= x"DEADBEEF";
                    end case;
                else
                    r_arready <= '0';
                    if r_rvalid = '1' and s_axil_rready = '1' then
                        r_rvalid <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process p_axil_read;

end architecture rtl;