library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.crc16_pkg.all;

entity axis_axil_uart_top is
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
        s_axis_tx_tdata : in std_logic_vector(31 downto 0);
        s_axis_tx_tkeep : in std_logic_vector(3 downto 0);
        s_axis_tx_tlast : in std_logic;
        s_axis_tx_tuser : in std_logic_vector(3 downto 0);
        s_axis_tx_tvalid : in std_logic;
        s_axis_tx_tready : out std_logic;
        m_axis_rx_tdata : out std_logic_vector(31 downto 0);
        m_axis_rx_tkeep : out std_logic_vector(3 downto 0);
        m_axis_rx_tlast : out std_logic;
        m_axis_rx_tuser : out std_logic_vector(3 downto 0);
        m_axis_rx_tvalid : out std_logic;
        m_axis_rx_tready : in std_logic;
        i_uart_rxd : in std_logic;
        o_uart_txd : out std_logic
    );
end entity axis_axil_uart_top;

architecture rtl of axis_axil_uart_top is

    signal w_rst_n_int : std_logic;
    signal w_core_en : std_logic;
    signal w_tx_en : std_logic;
    signal w_rx_en : std_logic;
    signal w_loopback_en : std_logic;
    signal w_soft_rst : std_logic;
    signal w_clk_div : std_logic_vector(15 downto 0);
    signal w_sof_val : std_logic_vector(15 downto 0);

    signal w_uart_tx_data : std_logic_vector(7 downto 0);
    signal w_uart_tx_valid : std_logic;
    signal w_uart_tx_ready : std_logic;
    signal w_uart_tx_busy : std_logic;
    signal w_pkt_tx_busy : std_logic;
    signal w_tx_busy_all : std_logic;

    signal w_uart_rx_data : std_logic_vector(7 downto 0);
    signal w_uart_rx_valid : std_logic;
    signal w_uart_rx_busy : std_logic;
    signal w_uart_frame_err : std_logic;
    signal w_pkt_rx_busy : std_logic;
    signal w_rx_busy_all : std_logic;

    signal w_tx_axis_ready : std_logic;
    signal w_rx_axis_valid : std_logic;
    signal w_tx_pkt_done : std_logic;
    signal w_tx_len_err : std_logic;
    signal w_rx_good_pkt : std_logic;
    signal w_rx_crc_err : std_logic;
    signal w_rx_len_err : std_logic;
    signal w_rx_frame_err : std_logic;

    signal w_last_tx_len : std_logic_vector(15 downto 0);
    signal w_last_rx_blen : std_logic_vector(15 downto 0);
    signal w_last_rx_crc : std_logic_vector(15 downto 0);
    signal w_last_calc_crc : std_logic_vector(15 downto 0);

    signal w_uart_txd_int : std_logic;
    signal w_uart_rxd_mux : std_logic;

begin

    w_rst_n_int <= i_rst_n and (not w_soft_rst);
    w_tx_busy_all <= w_pkt_tx_busy or w_uart_tx_busy;
    w_rx_busy_all <= w_pkt_rx_busy or w_uart_rx_busy;
    w_uart_rxd_mux <= w_uart_txd_int when w_loopback_en = '1' else i_uart_rxd;

    o_uart_txd <= w_uart_txd_int;
    s_axis_tx_tready <= w_tx_axis_ready;
    m_axis_rx_tvalid <= w_rx_axis_valid;

    u_axil_regs : entity work.axil_uart_regs
        generic map (
            G_CLK_FREQ => G_CLK_FREQ,
            G_DEFAULT_BAUD => G_DEFAULT_BAUD,
            G_DEFAULT_SOF => G_DEFAULT_SOF
        )
        port map (
            i_clk => i_clk,
            i_rst_n => i_rst_n,
            s_axil_awaddr => s_axil_awaddr,
            s_axil_awprot => s_axil_awprot,
            s_axil_awvalid => s_axil_awvalid,
            s_axil_awready => s_axil_awready,
            s_axil_wdata => s_axil_wdata,
            s_axil_wstrb => s_axil_wstrb,
            s_axil_wvalid => s_axil_wvalid,
            s_axil_wready => s_axil_wready,
            s_axil_bresp => s_axil_bresp,
            s_axil_bvalid => s_axil_bvalid,
            s_axil_bready => s_axil_bready,
            s_axil_araddr => s_axil_araddr,
            s_axil_arprot => s_axil_arprot,
            s_axil_arvalid => s_axil_arvalid,
            s_axil_arready => s_axil_arready,
            s_axil_rdata => s_axil_rdata,
            s_axil_rresp => s_axil_rresp,
            s_axil_rvalid => s_axil_rvalid,
            s_axil_rready => s_axil_rready,
            o_core_en => w_core_en,
            o_tx_en => w_tx_en,
            o_rx_en => w_rx_en,
            o_loopback_en => w_loopback_en,
            o_soft_rst => w_soft_rst,
            o_clk_div => w_clk_div,
            o_sof_val => w_sof_val,
            i_tx_busy => w_tx_busy_all,
            i_rx_busy => w_rx_busy_all,
            i_tx_axis_ready => w_tx_axis_ready,
            i_rx_axis_valid => w_rx_axis_valid,
            i_tx_pkt_done => w_tx_pkt_done,
            i_tx_len_err => w_tx_len_err,
            i_rx_good_pkt => w_rx_good_pkt,
            i_rx_crc_err => w_rx_crc_err,
            i_rx_len_err => w_rx_len_err,
            i_rx_frame_err => w_rx_frame_err,
            i_last_tx_len => w_last_tx_len,
            i_last_rx_blen => w_last_rx_blen,
            i_last_rx_crc => w_last_rx_crc,
            i_last_calc_crc => w_last_calc_crc
        );

    u_tx_pkt : entity work.axis_uart_tx_pkt
        port map (
            i_clk => i_clk,
            i_rst_n => w_rst_n_int,
            i_tx_en => w_tx_en,
            i_sof_val => w_sof_val,
            s_axis_tdata => s_axis_tx_tdata,
            s_axis_tkeep => s_axis_tx_tkeep,
            s_axis_tlast => s_axis_tx_tlast,
            s_axis_tuser => s_axis_tx_tuser,
            s_axis_tvalid => s_axis_tx_tvalid,
            s_axis_tready => w_tx_axis_ready,
            o_uart_tx_data => w_uart_tx_data,
            o_uart_tx_valid => w_uart_tx_valid,
            i_uart_tx_ready => w_uart_tx_ready,
            o_tx_busy => w_pkt_tx_busy,
            o_tx_pkt_done => w_tx_pkt_done,
            o_tx_len_err => w_tx_len_err,
            o_last_tx_len => w_last_tx_len
        );

    u_uart_tx : entity work.uart_tx
        generic map (
            G_CLK_FREQ => G_CLK_FREQ,
            G_DEFAULT_BAUD => G_DEFAULT_BAUD
        )
        port map (
            i_clk => i_clk,
            i_rst_n => w_rst_n_int,
            i_tx_en => w_tx_en,
            i_clk_div => w_clk_div,
            i_tx_data => w_uart_tx_data, 
            i_tx_valid => w_uart_tx_valid,
            o_tx_ready => w_uart_tx_ready,
            o_tx_busy => w_uart_tx_busy,
            o_uart_txd => w_uart_txd_int
        );

    u_uart_rx : entity work.uart_rx
        generic map (
            G_CLK_FREQ => G_CLK_FREQ,
            G_DEFAULT_BAUD => G_DEFAULT_BAUD
        )
        port map (
            i_clk => i_clk,
            i_rst_n => w_rst_n_int,
            i_rx_en => w_rx_en,
            i_clk_div => w_clk_div,
            i_uart_rxd => w_uart_rxd_mux,
            o_rx_data => w_uart_rx_data,
            o_rx_valid => w_uart_rx_valid,
            o_rx_busy => w_uart_rx_busy,
            o_frame_err => w_uart_frame_err
        );

    u_rx_pkt : entity work.axis_uart_rx_pkt
        port map (
            i_clk => i_clk,
            i_rst_n => w_rst_n_int,
            i_rx_en => w_rx_en,
            i_sof_val => w_sof_val,
            i_uart_rx_data => w_uart_rx_data,
            i_uart_rx_valid => w_uart_rx_valid,
            i_uart_frame_err => w_uart_frame_err,
            m_axis_tdata => m_axis_rx_tdata,
            m_axis_tkeep => m_axis_rx_tkeep,
            m_axis_tlast => m_axis_rx_tlast,
            m_axis_tuser => m_axis_rx_tuser,
            m_axis_tvalid => w_rx_axis_valid,
            m_axis_tready => m_axis_rx_tready,
            o_rx_busy => w_pkt_rx_busy,
            o_rx_good_pkt => w_rx_good_pkt,
            o_rx_crc_err => w_rx_crc_err,
            o_rx_len_err => w_rx_len_err,
            o_rx_frame_err => w_rx_frame_err,
            o_last_rx_blen => w_last_rx_blen,
            o_last_rx_crc => w_last_rx_crc,
            o_last_calc_crc => w_last_calc_crc
        );

end architecture rtl;