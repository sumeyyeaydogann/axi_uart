library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.crc16_pkg.all;

entity axis_uart_rx_pkt is
    port (
        i_clk : in std_logic;
        i_rst_n : in std_logic;
        i_rx_en : in std_logic;
        i_sof_val : in std_logic_vector(15 downto 0);
        i_uart_rx_data : in std_logic_vector(7 downto 0);
        i_uart_rx_valid : in std_logic;
        i_uart_frame_err : in std_logic;
        m_axis_tdata : out std_logic_vector(31 downto 0);
        m_axis_tkeep : out std_logic_vector(3 downto 0);
        m_axis_tlast : out std_logic;
        m_axis_tuser : out std_logic_vector(3 downto 0);
        m_axis_tvalid : out std_logic;
        m_axis_tready : in std_logic;
        o_rx_busy : out std_logic;
        o_rx_good_pkt : out std_logic;
        o_rx_crc_err : out std_logic;
        o_rx_len_err : out std_logic;
        o_rx_frame_err : out std_logic;
        o_last_rx_blen : out std_logic_vector(15 downto 0);
        o_last_rx_crc : out std_logic_vector(15 downto 0);
        o_last_calc_crc : out std_logic_vector(15 downto 0)
    );
end entity axis_uart_rx_pkt;

architecture rtl of axis_uart_rx_pkt is

    type t_word_ram is array (0 to 511) of std_logic_vector(35 downto 0);

    type t_rx_pkt_state is (
        ST_WAIT_SOF1,
        ST_WAIT_SOF2,
        ST_BLEN_H,
        ST_BLEN_L,
        ST_PAYLOAD,
        ST_CRC_H,
        ST_CRC_L,
        ST_AXIS_PREP,
        ST_AXIS_SEND
    );

    signal r_rx_ram : t_word_ram := (others => (others => '0'));
    signal r_state : t_rx_pkt_state := ST_WAIT_SOF1;
    signal r_blen : std_logic_vector(15 downto 0) := (others => '0');
    signal r_payload_len : natural range 0 to 2047 := 0;
    signal r_byte_idx : natural range 0 to 2047 := 0;
    signal r_wr_ptr : natural range 0 to 511 := 0;
    signal r_rd_ptr : natural range 0 to 511 := 0;
    signal r_total_words : natural range 0 to 512 := 0;
    signal r_cur_word : std_logic_vector(31 downto 0) := (others => '0');
    signal r_cur_keep : std_logic_vector(3 downto 0) := (others => '0');
    signal r_crc : std_logic_vector(15 downto 0) := C_CRC16_INIT;
    signal r_rx_crc : std_logic_vector(15 downto 0) := (others => '0');
    signal r_m_tdata : std_logic_vector(31 downto 0) := (others => '0');
    signal r_m_tkeep : std_logic_vector(3 downto 0) := (others => '0');
    signal r_m_tlast : std_logic := '0';
    signal r_m_tuser : std_logic_vector(3 downto 0) := (others => '0');
    signal r_m_tvalid : std_logic := '0';
    signal r_rx_busy : std_logic := '0';
    signal r_good_pkt : std_logic := '0';
    signal r_crc_err : std_logic := '0';
    signal r_len_err : std_logic := '0';
    signal r_frame_err : std_logic := '0';
    signal r_last_blen : std_logic_vector(15 downto 0) := (others => '0');
    signal r_last_rx_crc : std_logic_vector(15 downto 0) := (others => '0');
    signal r_last_calc_crc : std_logic_vector(15 downto 0) := (others => '0');

begin

    m_axis_tdata <= r_m_tdata;
    m_axis_tkeep <= r_m_tkeep;
    m_axis_tlast <= r_m_tlast;
    m_axis_tuser <= r_m_tuser;
    m_axis_tvalid <= r_m_tvalid;
    o_rx_busy <= r_rx_busy;
    o_rx_good_pkt <= r_good_pkt;
    o_rx_crc_err <= r_crc_err;
    o_rx_len_err <= r_len_err;
    o_rx_frame_err <= r_frame_err;
    o_last_rx_blen <= r_last_blen;
    o_last_rx_crc <= r_last_rx_crc;
    o_last_calc_crc <= r_last_calc_crc;

    p_rx_pkt : process(i_clk)
        variable v_blen_slv : std_logic_vector(15 downto 0);
        variable v_blen_int : natural range 0 to 65535;
        variable v_lane : natural range 0 to 3;
        variable v_word : std_logic_vector(31 downto 0);
        variable v_keep : std_logic_vector(3 downto 0);
        variable v_rx_crc_full : std_logic_vector(15 downto 0);
        variable v_ram_entry : std_logic_vector(35 downto 0);
    begin
        if rising_edge(i_clk) then
            if i_rst_n = '0' then
                r_state <= ST_WAIT_SOF1;
                r_blen <= (others => '0');
                r_payload_len <= 0;
                r_byte_idx <= 0;
                r_wr_ptr <= 0;
                r_rd_ptr <= 0;
                r_total_words <= 0;
                r_cur_word <= (others => '0');
                r_cur_keep <= (others => '0');
                r_crc <= C_CRC16_INIT;
                r_rx_crc <= (others => '0');
                r_m_tdata <= (others => '0');
                r_m_tkeep <= (others => '0');
                r_m_tlast <= '0';
                r_m_tuser <= (others => '0');
                r_m_tvalid <= '0';
                r_rx_busy <= '0';
                r_good_pkt <= '0';
                r_crc_err <= '0';
                r_len_err <= '0';
                r_frame_err <= '0';
                r_last_blen <= (others => '0');
                r_last_rx_crc <= (others => '0');
                r_last_calc_crc <= (others => '0');
            else
                r_good_pkt <= '0';
                r_crc_err <= '0';
                r_len_err <= '0';
                r_frame_err <= '0';

                if i_uart_frame_err = '1' then
                    r_frame_err <= '1';
                    r_rx_busy <= '0';
                    r_state <= ST_WAIT_SOF1;
                else
                    case r_state is

                        when ST_WAIT_SOF1 =>
                            r_m_tvalid <= '0';
                            r_m_tlast <= '0';
                            r_rx_busy <= '0';
                            if i_rx_en = '1' and i_uart_rx_valid = '1' then
                                if i_uart_rx_data = i_sof_val(15 downto 8) then
                                    r_rx_busy <= '1';
                                    r_state <= ST_WAIT_SOF2;
                                end if;
                            end if;

                        when ST_WAIT_SOF2 =>
                            r_rx_busy <= '1';
                            if i_uart_rx_valid = '1' then
                                if i_uart_rx_data = i_sof_val(7 downto 0) then
                                    r_state <= ST_BLEN_H;
                                elsif i_uart_rx_data = i_sof_val(15 downto 8) then
                                    r_state <= ST_WAIT_SOF2;
                                else
                                    r_rx_busy <= '0';
                                    r_state <= ST_WAIT_SOF1;
                                end if;
                            end if;

                        when ST_BLEN_H =>
                            r_rx_busy <= '1';
                            if i_uart_rx_valid = '1' then
                                r_blen(15 downto 8) <= i_uart_rx_data;
                                r_crc <= f_crc16_ccitt_byte(C_CRC16_INIT, i_uart_rx_data);
                                r_state <= ST_BLEN_L;
                            end if;

                        when ST_BLEN_L =>
                            r_rx_busy <= '1';
                            if i_uart_rx_valid = '1' then
                                v_blen_slv := r_blen(15 downto 8) & i_uart_rx_data;
                                r_blen <= v_blen_slv;
                                r_last_blen <= v_blen_slv;
                                v_blen_int := to_integer(unsigned(v_blen_slv));
                                if v_blen_int < C_MIN_BLEN_BYTES or v_blen_int > C_MAX_BLEN_BYTES then
                                    r_len_err <= '1';
                                    r_rx_busy <= '0';
                                    r_state <= ST_WAIT_SOF1;
                                else
                                    r_payload_len <= v_blen_int - C_CRC_BYTES;
                                    r_crc <= f_crc16_ccitt_byte(r_crc, i_uart_rx_data);
                                    r_byte_idx <= 0;
                                    r_wr_ptr <= 0;
                                    r_total_words <= 0;
                                    r_cur_word <= (others => '0');
                                    r_cur_keep <= (others => '0');
                                    r_state <= ST_PAYLOAD;
                                end if;
                            end if;

                        when ST_PAYLOAD =>
                            r_rx_busy <= '1';
                            if i_uart_rx_valid = '1' then
                                r_crc <= f_crc16_ccitt_byte(r_crc, i_uart_rx_data);
                                v_lane := r_byte_idx mod 4;
                                v_word := r_cur_word;
                                v_keep := r_cur_keep;
                                case v_lane is
                                    when 0 =>
                                        v_word(7 downto 0) := i_uart_rx_data;
                                    when 1 =>
                                        v_word(15 downto 8) := i_uart_rx_data;
                                    when 2 =>
                                        v_word(23 downto 16) := i_uart_rx_data;
                                    when others =>
                                        v_word(31 downto 24) := i_uart_rx_data;
                                end case;
                                v_keep(v_lane) := '1';
                                if v_lane = 3 or r_byte_idx = r_payload_len - 1 then
                                    r_rx_ram(r_wr_ptr) <= v_keep & v_word;
                                    if r_wr_ptr < 511 then
                                        r_wr_ptr <= r_wr_ptr + 1;
                                    end if;
                                    r_total_words <= r_total_words + 1;
                                    r_cur_word <= (others => '0');
                                    r_cur_keep <= (others => '0');
                                else
                                    r_cur_word <= v_word;
                                    r_cur_keep <= v_keep;
                                end if;
                                if r_byte_idx = r_payload_len - 1 then
                                    r_state <= ST_CRC_H;
                                else
                                    r_byte_idx <= r_byte_idx + 1;
                                end if;
                            end if;

                        when ST_CRC_H =>
                            r_rx_busy <= '1';
                            if i_uart_rx_valid = '1' then
                                r_rx_crc(15 downto 8) <= i_uart_rx_data;
                                r_state <= ST_CRC_L;
                            end if;

                        when ST_CRC_L =>
                            r_rx_busy <= '1';
                            if i_uart_rx_valid = '1' then
                                v_rx_crc_full := r_rx_crc(15 downto 8) & i_uart_rx_data;
                                r_rx_crc <= v_rx_crc_full;
                                r_last_rx_crc <= v_rx_crc_full;
                                r_last_calc_crc <= r_crc;
                                if v_rx_crc_full = r_crc then
                                    r_good_pkt <= '1';
                                    r_rd_ptr <= 0;
                                    r_state <= ST_AXIS_PREP;
                                else
                                    r_crc_err <= '1';
                                    r_rx_busy <= '0';
                                    r_state <= ST_WAIT_SOF1;
                                end if;
                            end if;

                        when ST_AXIS_PREP =>
                            r_rx_busy <= '1';
                            v_ram_entry := r_rx_ram(r_rd_ptr);
                            r_m_tdata <= v_ram_entry(31 downto 0);
                            r_m_tkeep <= v_ram_entry(35 downto 32);
                            if r_rd_ptr + 1 = r_total_words then
                                r_m_tlast <= '1';
                            else
                                r_m_tlast <= '0';
                            end if;
                            r_m_tuser <= "0000";
                            r_m_tvalid <= '1';
                            r_state <= ST_AXIS_SEND;

                        when ST_AXIS_SEND =>
                            r_rx_busy <= '1';
                            if r_m_tvalid = '1' and m_axis_tready = '1' then
                                r_m_tvalid <= '0';
                                r_m_tlast <= '0';
                                if r_rd_ptr + 1 = r_total_words then
                                    r_rx_busy <= '0';
                                    r_state <= ST_WAIT_SOF1;
                                else
                                    r_rd_ptr <= r_rd_ptr + 1;
                                    r_state <= ST_AXIS_PREP;
                                end if;
                            end if;

                        when others =>
                            r_state <= ST_WAIT_SOF1;

                    end case;
                end if;
            end if;
        end if;
    end process p_rx_pkt;

end architecture rtl;