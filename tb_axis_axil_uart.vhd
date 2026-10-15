library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.crc16_pkg.all;

entity tb_axis_axil_uart is
end entity tb_axis_axil_uart;

architecture sim of tb_axis_axil_uart is

    constant C_CLK_FREQ : positive := 62_500_000;
    constant C_DEFAULT_BAUD : positive := 1_000_000;
    constant C_CLK_PERIOD : time := 16 ns;
    constant C_TOTAL_RANDOM_PKTS : positive := 4000;
    constant C_SB_DEPTH : positive := 1024;

    type t_pkt_scenario is (
        SCEN_IDLE,
        SCEN_VALID_PKT,
        SCEN_MIN_24B_PKT,
        SCEN_MAX_2024B_PKT,
        SCEN_BAD_CRC_INJECT,
        SCEN_SHORT_LEN_INJECT,
        SCEN_UART_GLITCH_INJECT
    );

    type t_sb_data_ram is array (0 to C_SB_DEPTH - 1) of std_logic_vector(31 downto 0);
    type t_sb_keep_ram is array (0 to C_SB_DEPTH - 1) of std_logic_vector(3 downto 0);
    type t_sb_last_ram is array (0 to C_SB_DEPTH - 1) of std_logic;
    type t_sb_id_ram is array (0 to C_SB_DEPTH - 1) of natural;

    function f_next_lfsr32(
        i_lfsr : std_logic_vector(31 downto 0)
    ) return std_logic_vector is
        variable v_bit : std_logic;
        variable v_res : std_logic_vector(31 downto 0);
    begin
        v_bit := i_lfsr(31) xor i_lfsr(21) xor i_lfsr(1) xor i_lfsr(0);
        v_res := i_lfsr(30 downto 0) & v_bit;
        return v_res;
    end function f_next_lfsr32;

    function f_mask_by_keep(
        i_data : std_logic_vector(31 downto 0);
        i_keep : std_logic_vector(3 downto 0)
    ) return std_logic_vector is
        variable v_out : std_logic_vector(31 downto 0);
    begin
        v_out := (others => '0');
        if i_keep(0) = '1' then
            v_out(7 downto 0) := i_data(7 downto 0);
        end if;
        if i_keep(1) = '1' then
            v_out(15 downto 8) := i_data(15 downto 8);
        end if;
        if i_keep(2) = '1' then
            v_out(23 downto 16) := i_data(23 downto 16);
        end if;
        if i_keep(3) = '1' then
            v_out(31 downto 24) := i_data(31 downto 24);
        end if;
        return v_out;
    end function f_mask_by_keep;

    signal i_clk : std_logic := '0';
    signal i_rst_n : std_logic := '0';

    signal s_axil_awaddr : std_logic_vector(7 downto 0) := (others => '0');
    signal s_axil_awprot : std_logic_vector(2 downto 0) := (others => '0');
    signal s_axil_awvalid : std_logic := '0';
    signal s_axil_awready : std_logic;
    signal s_axil_wdata : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axil_wstrb : std_logic_vector(3 downto 0) := (others => '1');
    signal s_axil_wvalid : std_logic := '0';
    signal s_axil_wready : std_logic;
    signal s_axil_bresp : std_logic_vector(1 downto 0);
    signal s_axil_bvalid : std_logic;
    signal s_axil_bready : std_logic := '0';
    signal s_axil_araddr : std_logic_vector(7 downto 0) := (others => '0');
    signal s_axil_arprot : std_logic_vector(2 downto 0) := (others => '0');
    signal s_axil_arvalid : std_logic := '0';
    signal s_axil_arready : std_logic;
    signal s_axil_rdata : std_logic_vector(31 downto 0);
    signal s_axil_rresp : std_logic_vector(1 downto 0);
    signal s_axil_rvalid : std_logic;
    signal s_axil_rready : std_logic := '0';

    signal s_axis_tx_tdata : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axis_tx_tkeep : std_logic_vector(3 downto 0) := (others => '0');
    signal s_axis_tx_tlast : std_logic := '0';
    signal s_axis_tx_tuser : std_logic_vector(3 downto 0) := (others => '0');
    signal s_axis_tx_tvalid : std_logic := '0';
    signal s_axis_tx_tready : std_logic;

    signal m_axis_rx_tdata : std_logic_vector(31 downto 0);
    signal m_axis_rx_tkeep : std_logic_vector(3 downto 0);
    signal m_axis_rx_tlast : std_logic;
    signal m_axis_rx_tuser : std_logic_vector(3 downto 0);
    signal m_axis_rx_tvalid : std_logic;
    signal m_axis_rx_tready : std_logic := '1';

    signal w_uart_txd_pin : std_logic;
    signal w_uart_rxd_pin : std_logic;

    -- Waveform uzerinde kolay hata ayiklama (Debug) sinyalleri
    signal dbg_scenario : t_pkt_scenario := SCEN_IDLE;
    signal dbg_pkt_id : natural := 0;
    signal dbg_pkt_byte_len : natural := 0;
    signal dbg_uart_glitch_en : std_logic := '0';
    signal dbg_exp_tx_pkts : natural := 0;
    signal dbg_exp_good_rx_pkts : natural := 0;
    signal dbg_exp_crc_errs : natural := 0;
    signal dbg_exp_frame_errs : natural := 0;

    -- Dairesel (Circular Ring Buffer) Scoreboard sinyalleri (Sinizsiz paket destegi)
    signal r_sb_data : t_sb_data_ram := (others => (others => '0'));
    signal r_sb_keep : t_sb_keep_ram := (others => (others => '0'));
    signal r_sb_last : t_sb_last_ram := (others => '0');
    signal r_sb_pkt_id : t_sb_id_ram := (others => 0);
    signal r_sb_wr_total : natural := 0;
    signal r_sb_rd_total : natural := 0;
    signal r_rx_pkt_done_cnt : natural := 0;
    signal r_rx_mismatch_cnt : natural := 0;

    signal r_lfsr_tready : std_logic_vector(31 downto 0) := x"CAFEBABE";
    signal r_axil_read_val : std_logic_vector(31 downto 0) := (others => '0');
    signal r_sim_done : boolean := false;

begin

    -- Fiziksel UART hatti: glitch enjeksiyonu aktifken RX hattini '0'a ceker
    w_uart_rxd_pin <= '0' when dbg_uart_glitch_en = '1' else w_uart_txd_pin;

    p_clk_gen : process
    begin
        while not r_sim_done loop
            i_clk <= '0';
            wait for C_CLK_PERIOD / 2;
            i_clk <= '1';
            wait for C_CLK_PERIOD / 2;
        end loop;
        wait;
    end process p_clk_gen;

    u_dut : entity work.axis_axil_uart_top
        generic map (
            G_CLK_FREQ => C_CLK_FREQ,
            G_DEFAULT_BAUD => C_DEFAULT_BAUD,
            G_DEFAULT_SOF => x"A55A"
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
            s_axis_tx_tdata => s_axis_tx_tdata,
            s_axis_tx_tkeep => s_axis_tx_tkeep,
            s_axis_tx_tlast => s_axis_tx_tlast,
            s_axis_tx_tuser => s_axis_tx_tuser,
            s_axis_tx_tvalid => s_axis_tx_tvalid,
            s_axis_tx_tready => s_axis_tx_tready,
            m_axis_rx_tdata => m_axis_rx_tdata,
            m_axis_rx_tkeep => m_axis_rx_tkeep,
            m_axis_rx_tlast => m_axis_rx_tlast,
            m_axis_rx_tuser => m_axis_rx_tuser,
            m_axis_rx_tvalid => m_axis_rx_tvalid,
            m_axis_rx_tready => m_axis_rx_tready,
            i_uart_rxd => w_uart_rxd_pin,
            o_uart_txd => w_uart_txd_pin
        );

    -- Rastgele AXI4-Stream RX TREADY Backpressure Ureticisi (%75 Ready, %25 Stall)
    p_random_tready : process(i_clk)
    begin
        if rising_edge(i_clk) then
            if i_rst_n = '0' then
                r_lfsr_tready <= x"CAFEBABE";
                m_axis_rx_tready <= '1';
            else
                r_lfsr_tready <= f_next_lfsr32(r_lfsr_tready);
                if r_lfsr_tready(1 downto 0) = "00" then
                    m_axis_rx_tready <= '0';
                else
                    m_axis_rx_tready <= '1';
                end if;
            end if;
        end if;
    end process p_random_tready;

    -- Otomatik Dairesel Scoreboard Dogrulayici (m_axis_rx cikisini kelime kelime kontrol eder)
    p_rx_scoreboard : process(i_clk)
        variable v_slot_idx : natural range 0 to C_SB_DEPTH - 1;
        variable v_exp_data : std_logic_vector(31 downto 0);
        variable v_act_data : std_logic_vector(31 downto 0);
        variable v_exp_keep : std_logic_vector(3 downto 0);
        variable v_exp_last : std_logic;
        variable v_pkt_num : natural;
    begin
        if rising_edge(i_clk) then
            if i_rst_n = '0' then
                r_sb_rd_total <= 0;
                r_rx_pkt_done_cnt <= 0;
                r_rx_mismatch_cnt <= 0;
            else
                if m_axis_rx_tvalid = '1' and m_axis_rx_tready = '1' then
                    assert r_sb_rd_total < r_sb_wr_total
                        report "SCOREBOARD HATASI: Beklenmeyen fazladan RX kelimesi geldi (Hatali paket sizmis olabilir)!"
                        severity failure;

                    v_slot_idx := r_sb_rd_total mod C_SB_DEPTH;
                    v_exp_keep := r_sb_keep(v_slot_idx);
                    v_exp_last := r_sb_last(v_slot_idx);
                    v_pkt_num := r_sb_pkt_id(v_slot_idx);
                    v_exp_data := f_mask_by_keep(r_sb_data(v_slot_idx), v_exp_keep);
                    v_act_data := f_mask_by_keep(m_axis_rx_tdata, m_axis_rx_tkeep);

                    if m_axis_rx_tkeep /= v_exp_keep then
                        r_rx_mismatch_cnt <= r_rx_mismatch_cnt + 1;
                        assert false
                            report "SCOREBOARD HATASI: TKEEP uyusmazligi! Paket ID=" & integer'image(v_pkt_num)
                            severity failure;
                    end if;

                    if v_act_data /= v_exp_data then
                        r_rx_mismatch_cnt <= r_rx_mismatch_cnt + 1;
                        assert false
                            report "SCOREBOARD HATASI: TDATA veri uyusmazligi! Paket ID=" & integer'image(v_pkt_num)
                            severity failure;
                    end if;

                    if m_axis_rx_tlast /= v_exp_last then
                        r_rx_mismatch_cnt <= r_rx_mismatch_cnt + 1;
                        assert false
                            report "SCOREBOARD HATASI: TLAST uyusmazligi! Paket ID=" & integer'image(v_pkt_num)
                            severity failure;
                    end if;

                    if m_axis_rx_tlast = '1' then
                        r_rx_pkt_done_cnt <= r_rx_pkt_done_cnt + 1;
                    end if;

                    r_sb_rd_total <= r_sb_rd_total + 1;
                end if;
            end if;
        end if;
    end process p_rx_scoreboard;

    -- Ana 4000 Paketlik Rastgele (RNG) Trafik ve Hata Enjeksiyon Sureci
    p_stim : process

        variable v_prng : std_logic_vector(31 downto 0) := x"13579BDF";
        variable v_mode_sel : natural range 0 to 31 := 0;
        variable v_rand_len : natural := 24;
        variable v_num_words : natural := 6;
        variable v_rem_bytes : natural := 0;
        variable v_word_data : std_logic_vector(31 downto 0);
        variable v_word_keep : std_logic_vector(3 downto 0);
        variable v_word_last : std_logic;
        variable v_word_user : std_logic_vector(3 downto 0);
        variable v_cur_div : natural := 4;
        variable v_wait_clks : natural := 0;
        variable v_sb_wr_var : natural := 0;
        variable v_sb_slot : natural range 0 to C_SB_DEPTH - 1 := 0;
        variable v_exp_tx_cnt : natural := 0;
        variable v_exp_good_cnt : natural := 0;
        variable v_exp_crc_cnt : natural := 0;
        variable v_exp_frm_cnt : natural := 0;

        procedure axil_write(
            constant c_addr : in std_logic_vector(7 downto 0);
            constant c_data : in std_logic_vector(31 downto 0)
        ) is
        begin
            wait until rising_edge(i_clk);
            s_axil_awaddr <= c_addr;
            s_axil_awvalid <= '1';
            s_axil_wdata <= c_data;
            s_axil_wstrb <= "1111";
            s_axil_wvalid <= '1';
            s_axil_bready <= '0';
            loop
                wait until rising_edge(i_clk);
                if s_axil_awready = '1' and s_axil_wready = '1' then
                    exit;
                end if;
            end loop;
            s_axil_awvalid <= '0';
            s_axil_wvalid <= '0';
            s_axil_bready <= '1';
            loop
                wait until rising_edge(i_clk);
                if s_axil_bvalid = '1' then
                    exit;
                end if;
            end loop;
            s_axil_bready <= '0';
            wait until rising_edge(i_clk);
        end procedure axil_write;

        procedure axil_read(
            constant c_addr : in std_logic_vector(7 downto 0)
        ) is
        begin
            wait until rising_edge(i_clk);
            s_axil_araddr <= c_addr;
            s_axil_arvalid <= '1';
            s_axil_rready <= '0';
            loop
                wait until rising_edge(i_clk);
                if s_axil_arready = '1' then
                    exit;
                end if;
            end loop;
            s_axil_arvalid <= '0';
            s_axil_rready <= '1';
            loop
                wait until rising_edge(i_clk);
                if s_axil_rvalid = '1' then
                    r_axil_read_val <= s_axil_rdata;
                    exit;
                end if;
            end loop;
            s_axil_rready <= '0';
            wait until rising_edge(i_clk);
        end procedure axil_read;

        procedure axis_send_word(
            constant c_data : in std_logic_vector(31 downto 0);
            constant c_keep : in std_logic_vector(3 downto 0);
            constant c_last : in std_logic;
            constant c_user : in std_logic_vector(3 downto 0)
        ) is
        begin
            s_axis_tx_tdata <= c_data;
            s_axis_tx_tkeep <= c_keep;
            s_axis_tx_tlast <= c_last;
            s_axis_tx_tuser <= c_user;
            s_axis_tx_tvalid <= '1';
            loop
                wait until rising_edge(i_clk);
                if s_axis_tx_tready = '1' then
                    exit;
                end if;
            end loop;
            s_axis_tx_tvalid <= '0';
            s_axis_tx_tlast <= '0';
            s_axis_tx_tuser <= "0000";
        end procedure axis_send_word;

    begin
        i_rst_n <= '0';
        dbg_scenario <= SCEN_IDLE;
        wait for C_CLK_PERIOD * 10;
        wait until rising_edge(i_clk);
        i_rst_n <= '1';
        wait for C_CLK_PERIOD * 5;

        -- Baslangic AXI4-Lite Yapilandirmasi: Baud Bolucu = 4, SOF = 0x55AA
        v_cur_div := 4;
        axil_write(x"04", x"00000004");
        axil_write(x"08", x"000055AA");
        axil_write(x"00", x"00000007");

        report "=== 4000 PAKETLIK RNG STRES VE HATA AYIKLAMA TESTI BASLIYOR ==="
            severity note;

        for pkt_idx in 1 to C_TOTAL_RANDOM_PKTS loop

            -- Her 1000 pakette bir calisma aninda (runtime) SOF degerini degistir
            if pkt_idx = 1001 then
                axil_write(x"08", x"00007E5A");
            elsif pkt_idx = 2001 then
                axil_write(x"08", x"0000A55A");
            elsif pkt_idx = 3001 then
                axil_write(x"08", x"00009669");
            end if;

            dbg_pkt_id <= pkt_idx;
            v_prng := f_next_lfsr32(v_prng);
            v_mode_sel := to_integer(unsigned(v_prng(12 downto 8)));

            -- Senaryo ve Boyut Secimi (Sinir degerleri + Rastgele + Hata Enjeksiyonu)
            if (pkt_idx mod 250) = 0 then
                -- Her 250 pakette bir maksimum sinir olan 2024 baytlik Jumbo Paket test et
                dbg_scenario <= SCEN_MAX_2024B_PKT;
                v_rand_len := 2024;
            elsif (pkt_idx mod 125) = 0 then
                -- Alt sinir olan tam 24 baytlik Paket test et
                dbg_scenario <= SCEN_MIN_24B_PKT;
                v_rand_len := 24;
            elsif v_mode_sel = 0 or v_mode_sel = 1 or v_mode_sel = 2 then
                -- ~%9.3 olasilikla Kasitli CRC Hatasi
                dbg_scenario <= SCEN_BAD_CRC_INJECT;
                v_rand_len := 24 + (to_integer(unsigned(v_prng(5 downto 0))) mod 40);
            elsif v_mode_sel = 3 then
                -- ~%3.1 olasilikla Kasitli Kisa Paket (<24 Bayt) Uzunluk Hatasi
                dbg_scenario <= SCEN_SHORT_LEN_INJECT;
                v_rand_len := 8 + (to_integer(unsigned(v_prng(3 downto 0))) mod 12);
            elsif v_mode_sel = 4 then
                -- ~%3.1 olasilikla Fiziksel UART Stop-Bit Glitch Hatasi
                dbg_scenario <= SCEN_UART_GLITCH_INJECT;
                v_rand_len := 24;
            else
                -- ~%84 olasilikla Rastgele Gecerli Paket (24..87 bayt arasi, tum TKEEP modlarini tarar)
                dbg_scenario <= SCEN_VALID_PKT;
                v_rand_len := 24 + to_integer(unsigned(v_prng(5 downto 0)));
            end if;

            dbg_pkt_byte_len <= v_rand_len;
            v_num_words := (v_rand_len + 3) / 4;
            v_rem_bytes := v_rand_len mod 4;
            wait until rising_edge(i_clk);

            if dbg_scenario = SCEN_UART_GLITCH_INJECT then
                -- Fiziksel UART RX hattinda dogrudan Stop-Bit Frame Error (Glitch/Break) olustur
                v_exp_frm_cnt := v_exp_frm_cnt + 1;
                dbg_exp_frame_errs <= v_exp_frm_cnt;
                wait until rising_edge(i_clk);
                dbg_uart_glitch_en <= '1';
                wait for C_CLK_PERIOD * (1 + ((19 * v_cur_div) / 2));
                dbg_uart_glitch_en <= '0';
                wait for C_CLK_PERIOD * (10 * v_cur_div);
            else
                for w_idx in 0 to v_num_words - 1 loop
                    v_prng := f_next_lfsr32(v_prng);
                    v_word_data := v_prng;

                    if w_idx = v_num_words - 1 then
                        v_word_last := '1';
                        if v_rem_bytes = 1 then
                            v_word_keep := "0001";
                        elsif v_rem_bytes = 2 then
                            v_word_keep := "0011";
                        elsif v_rem_bytes = 3 then
                            v_word_keep := "0111";
                        else
                            v_word_keep := "1111";
                        end if;
                    else
                        v_word_last := '0';
                        v_word_keep := "1111";
                    end if;

                    if dbg_scenario = SCEN_BAD_CRC_INJECT and v_word_last = '1' then
                        v_word_user := "0001";
                    else
                        v_word_user := "0000";
                    end if;

                    -- Paket gecerli bir paketse Dairesel Scoreboard kuyruguna ekle
                    if dbg_scenario = SCEN_VALID_PKT or dbg_scenario = SCEN_MIN_24B_PKT or dbg_scenario = SCEN_MAX_2024B_PKT then
                        v_sb_slot := v_sb_wr_var mod C_SB_DEPTH;
                        r_sb_data(v_sb_slot) <= v_word_data;
                        r_sb_keep(v_sb_slot) <= v_word_keep;
                        r_sb_last(v_sb_slot) <= v_word_last;
                        r_sb_pkt_id(v_sb_slot) <= pkt_idx;
                        v_sb_wr_var := v_sb_wr_var + 1;
                        r_sb_wr_total <= v_sb_wr_var;
                    end if;

                    axis_send_word(v_word_data, v_word_keep, v_word_last, v_word_user);
                end loop;

                -- Senaryoya gore beklenen sayaclari ve bekleme suresini yonet
                if dbg_scenario = SCEN_SHORT_LEN_INJECT then
                    v_exp_frm_cnt := v_exp_frm_cnt + 1;
                    dbg_exp_frame_errs <= v_exp_frm_cnt;
                    wait for C_CLK_PERIOD * 40;

                elsif dbg_scenario = SCEN_BAD_CRC_INJECT then
                    v_exp_tx_cnt := v_exp_tx_cnt + 1;
                    v_exp_crc_cnt := v_exp_crc_cnt + 1;
                    dbg_exp_tx_pkts <= v_exp_tx_cnt;
                    dbg_exp_crc_errs <= v_exp_crc_cnt;
                    v_wait_clks := (v_rand_len + 8) * 11 * v_cur_div;
                    wait for C_CLK_PERIOD * v_wait_clks;

                else
                    v_exp_tx_cnt := v_exp_tx_cnt + 1;
                    v_exp_good_cnt := v_exp_good_cnt + 1;
                    dbg_exp_tx_pkts <= v_exp_tx_cnt;
                    dbg_exp_good_rx_pkts <= v_exp_good_cnt;
                    loop
                        wait until rising_edge(i_clk);
                        if r_rx_pkt_done_cnt = v_exp_good_cnt then
                            exit;
                        end if;
                    end loop;
                    wait for C_CLK_PERIOD * (20 * v_cur_div);
                end if;
            end if;

            -- Her 100 pakette bir AXI4-Lite uzerinden donanim sayaclarini kontrol et ve ilerleme raporu bas
            if (pkt_idx mod 100) = 0 then
                axil_read(x"10");
                assert to_integer(unsigned(r_axil_read_val)) = v_exp_tx_cnt
                    report "ARA KONTROL HATASI: TX_PKT_CNT beklenen degerde degil! Paket=" & integer'image(pkt_idx)
                    severity failure;

                axil_read(x"14");
                assert to_integer(unsigned(r_axil_read_val)) = v_exp_good_cnt
                    report "ARA KONTROL HATASI: RX_GOOD_CNT beklenen degerde degil! Paket=" & integer'image(pkt_idx)
                    severity failure;

                axil_read(x"18");
                assert to_integer(unsigned(r_axil_read_val)) = v_exp_crc_cnt
                    report "ARA KONTROL HATASI: ERR_CRC_CNT beklenen degerde degil! Paket=" & integer'image(pkt_idx)
                    severity failure;

                axil_read(x"1C");
                assert to_integer(unsigned(r_axil_read_val)) = v_exp_frm_cnt
                    report "ARA KONTROL HATASI: ERR_FRAME_CNT beklenen degerde degil! Paket=" & integer'image(pkt_idx)
                    severity failure;

                report "[ILERLEME] " & integer'image(pkt_idx) & " / " & integer'image(C_TOTAL_RANDOM_PKTS)
                    & " paket tamamlandi | Saglam=" & integer'image(v_exp_good_cnt)
                    & " | CRC_Err=" & integer'image(v_exp_crc_cnt)
                    & " | Frame_Err=" & integer'image(v_exp_frm_cnt)
                    severity note;
            end if;

        end loop;

        dbg_scenario <= SCEN_IDLE;
        wait for C_CLK_PERIOD * 100;

        -- Son AXI4-Lite Register ve Scoreboard Kontrolleri
        assert r_sb_rd_total = r_sb_wr_total
            report "HATA: Scoreboard icindeki tum kelimeler okunmadi!"
            severity failure;

        assert r_rx_mismatch_cnt = 0
            report "HATA: Scoreboard veri/keep karsilastirmasinda hata bulundu!"
            severity failure;

        axil_read(x"10");
        assert r_axil_read_val = std_logic_vector(to_unsigned(v_exp_tx_cnt, 32))
            report "HATA: Son TX_PKT_CNT uyusmadi!"
            severity failure;

        axil_read(x"14");
        assert r_axil_read_val = std_logic_vector(to_unsigned(v_exp_good_cnt, 32))
            report "HATA: Son RX_GOOD_CNT uyusmadi!"
            severity failure;

        axil_read(x"18");
        assert r_axil_read_val = std_logic_vector(to_unsigned(v_exp_crc_cnt, 32))
            report "HATA: Son ERR_CRC_CNT uyusmadi!"
            severity failure;

        axil_read(x"1C");
        assert r_axil_read_val = std_logic_vector(to_unsigned(v_exp_frm_cnt, 32))
            report "HATA: Son ERR_FRAME_CNT uyusmadi!"
            severity failure;

        axil_read(x"20");
        axil_read(x"24");

        report "=================================================================="
            severity note;
        report "BASARILI: 4000 Paketlik RNG Stres Testi Hatasiz Tamamlandi!"
            severity note;
        report "  Toplam Dogrulanan 32-Bit Kelime Sayisi          : " & integer'image(r_sb_rd_total)
            severity note;
        report "  Gecerli RX Paket Sayisi (Scoreboard Dogrulandi) : " & integer'image(v_exp_good_cnt)
            severity note;
        report "  Yakalanip Dusurulen CRC Hatali Paket Sayisi     : " & integer'image(v_exp_crc_cnt)
            severity note;
        report "  Yakalanan Frame / Uzunluk Hatasi Sayisi         : " & integer'image(v_exp_frm_cnt)
            severity note;
        report "=================================================================="
            severity note;

        r_sim_done <= true;
        wait;
    end process p_stim;

end architecture sim;