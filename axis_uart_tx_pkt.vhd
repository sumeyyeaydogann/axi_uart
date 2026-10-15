library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.crc16_pkg.all;

entity axis_uart_tx_pkt is
    port (
        i_clk : in std_logic;
        i_rst_n : in std_logic;
        i_tx_en : in std_logic;
        i_sof_val : in std_logic_vector(15 downto 0);
        s_axis_tdata : in std_logic_vector(31 downto 0);
        s_axis_tkeep : in std_logic_vector(3 downto 0);
        s_axis_tlast : in std_logic;
        s_axis_tuser : in std_logic_vector(3 downto 0);
        s_axis_tvalid : in std_logic;
        s_axis_tready : out std_logic;
        o_uart_tx_data : out std_logic_vector(7 downto 0);
        o_uart_tx_valid : out std_logic;
        i_uart_tx_ready : in std_logic;
        o_tx_busy : out std_logic;
        o_tx_pkt_done : out std_logic;
        o_tx_len_err : out std_logic;
        o_last_tx_len : out std_logic_vector(15 downto 0)
    );
end entity axis_uart_tx_pkt;

architecture rtl of axis_uart_tx_pkt is

    type t_word_ram is array (0 to 511) of std_logic_vector(35 downto 0);

    type t_tx_pkt_state is (
        ST_COLLECT_AXIS,
        ST_CHECK_LEN,
        ST_SEND_SOF_H,
        ST_SEND_SOF_L,
        ST_SEND_BLEN_H,
        ST_SEND_BLEN_L,
        ST_LOAD_WORD,
        ST_SEND_PAYLOAD_BYTE,
        ST_SEND_CRC_H,
        ST_SEND_CRC_L,
        ST_PKT_DONE
    );

    signal r_tx_ram : t_word_ram := (others => (others => '0'));
    signal r_state : t_tx_pkt_state := ST_COLLECT_AXIS;
    signal r_wr_ptr : natural range 0 to 511 := 0;
    signal r_rd_ptr : natural range 0 to 511 := 0;
    signal r_word_cnt : natural range 0 to 512 := 0;
    signal r_byte_cnt : natural range 0 to 4095 := 0;
    signal r_blen : std_logic_vector(15 downto 0) := (others => '0');
    signal r_crc : std_logic_vector(15 downto 0) := C_CRC16_INIT;
    signal r_cur_word : std_logic_vector(31 downto 0) := (others => '0');
    signal r_cur_keep : std_logic_vector(3 downto 0) := (others => '0');
    signal r_lane_idx : natural range 0 to 3 := 0;
    signal r_corrupt_crc : std_logic := '0';
    signal r_s_ready : std_logic := '0';
    signal r_uart_data : std_logic_vector(7 downto 0) := (others => '0');
    signal r_uart_valid : std_logic := '0';
    signal r_tx_busy : std_logic := '0';
    signal r_pkt_done : std_logic := '0';
    signal r_len_err : std_logic := '0';
    signal r_last_tx_len : std_logic_vector(15 downto 0) := (others => '0');

begin

    s_axis_tready <= r_s_ready;
    o_uart_tx_data <= r_uart_data;
    o_uart_tx_valid <= r_uart_valid;
    o_tx_busy <= r_tx_busy;
    o_tx_pkt_done <= r_pkt_done;
    o_tx_len_err <= r_len_err;
    o_last_tx_len <= r_last_tx_len;

    p_tx_pkt : process(i_clk)
        variable v_add_bytes : natural range 0 to 4;
        variable v_total_bytes : natural range 0 to 4095;
        variable v_byte_sel : std_logic_vector(7 downto 0);
    begin
        if rising_edge(i_clk) then
            if i_rst_n = '0' then
                r_state <= ST_COLLECT_AXIS;
                r_wr_ptr <= 0;
                r_rd_ptr <= 0;
                r_word_cnt <= 0;
                r_byte_cnt <= 0;
                r_blen <= (others => '0');
                r_crc <= C_CRC16_INIT;
                r_cur_word <= (others => '0');
                r_cur_keep <= (others => '0');
                r_lane_idx <= 0;
                r_corrupt_crc <= '0';
                r_s_ready <= '0';
                r_uart_data <= (others => '0');
                r_uart_valid <= '0';
                r_tx_busy <= '0';
                r_pkt_done <= '0';
                r_len_err <= '0';
                r_last_tx_len <= (others => '0');
            else
                r_pkt_done <= '0';
                r_len_err <= '0';

                case r_state is

                    when ST_COLLECT_AXIS =>
                        r_uart_valid <= '0';
                        if i_tx_en = '1' then
                            r_s_ready <= '1';
                        else
                            r_s_ready <= '0';
                        end if;
                        if r_word_cnt > 0 then
                            r_tx_busy <= '1';
                        else
                            r_tx_busy <= '0';
                        end if;
                        if i_tx_en = '1' and s_axis_tvalid = '1' and r_s_ready = '1' then
                            v_add_bytes := f_count_keep_bytes(s_axis_tkeep);
                            v_total_bytes := r_byte_cnt + v_add_bytes;
                            if r_word_cnt < 512 then
                                r_tx_ram(r_wr_ptr) <= s_axis_tkeep & s_axis_tdata;
                            end if;
                            r_byte_cnt <= v_total_bytes;
                            r_word_cnt <= r_word_cnt + 1;
                            if s_axis_tlast = '1' then
                                r_s_ready <= '0';
                                r_tx_busy <= '1';
                                r_corrupt_crc <= s_axis_tuser(0);
                                r_state <= ST_CHECK_LEN;
                            else
                                if r_wr_ptr < 511 then
                                    r_wr_ptr <= r_wr_ptr + 1;
                                end if;
                            end if;
                        end if;

                    when ST_CHECK_LEN =>
                        r_s_ready <= '0';
                        r_tx_busy <= '1';
                        r_last_tx_len <= std_logic_vector(to_unsigned(r_byte_cnt, 16));
                        if r_byte_cnt < C_MIN_PAYLOAD_BYTES or r_byte_cnt > C_MAX_PAYLOAD_BYTES then
                            r_len_err <= '1';
                            r_wr_ptr <= 0;
                            r_rd_ptr <= 0;
                            r_word_cnt <= 0;
                            r_byte_cnt <= 0;
                            r_tx_busy <= '0';
                            r_state <= ST_COLLECT_AXIS;
                        else
                            r_blen <= std_logic_vector(to_unsigned(r_byte_cnt + C_CRC_BYTES, 16));
                            r_crc <= C_CRC16_INIT;
                            r_rd_ptr <= 0;
                            r_uart_data <= i_sof_val(15 downto 8);
                            r_uart_valid <= '1';
                            r_state <= ST_SEND_SOF_H;
                        end if;

                    when ST_SEND_SOF_H =>
                        if r_uart_valid = '1' and i_uart_tx_ready = '1' then
                            r_uart_data <= i_sof_val(7 downto 0);
                            r_uart_valid <= '1';
                            r_state <= ST_SEND_SOF_L;
                        end if;

                    when ST_SEND_SOF_L =>
                        if r_uart_valid = '1' and i_uart_tx_ready = '1' then
                            r_uart_data <= r_blen(15 downto 8);
                            r_uart_valid <= '1';
                            r_crc <= f_crc16_ccitt_byte(C_CRC16_INIT, r_blen(15 downto 8));
                            r_state <= ST_SEND_BLEN_H;
                        end if;

                    when ST_SEND_BLEN_H =>
                        if r_uart_valid = '1' and i_uart_tx_ready = '1' then
                            r_uart_data <= r_blen(7 downto 0);
                            r_uart_valid <= '1';
                            r_crc <= f_crc16_ccitt_byte(r_crc, r_blen(7 downto 0));
                            r_state <= ST_SEND_BLEN_L;
                        end if;

                    when ST_SEND_BLEN_L =>
                        if r_uart_valid = '1' and i_uart_tx_ready = '1' then
                            r_uart_valid <= '0';
                            r_rd_ptr <= 0;
                            r_state <= ST_LOAD_WORD;
                        end if;

                    when ST_LOAD_WORD =>
                        r_uart_valid <= '0';
                        r_cur_keep <= r_tx_ram(r_rd_ptr)(35 downto 32);
                        r_cur_word <= r_tx_ram(r_rd_ptr)(31 downto 0);
                        r_lane_idx <= 0;
                        r_state <= ST_SEND_PAYLOAD_BYTE;

                    when ST_SEND_PAYLOAD_BYTE =>
                        if r_uart_valid = '0' then
                            if r_cur_keep(r_lane_idx) = '1' then
                                case r_lane_idx is
                                    when 0 =>
                                        v_byte_sel := r_cur_word(7 downto 0);
                                    when 1 =>
                                        v_byte_sel := r_cur_word(15 downto 8);
                                    when 2 =>
                                        v_byte_sel := r_cur_word(23 downto 16);
                                    when others =>
                                        v_byte_sel := r_cur_word(31 downto 24);
                                end case;
                                r_uart_data <= v_byte_sel;
                                r_uart_valid <= '1';
                                r_crc <= f_crc16_ccitt_byte(r_crc, v_byte_sel);
                            else
                                if r_lane_idx = 3 then
                                    if r_rd_ptr + 1 < r_word_cnt then
                                        r_rd_ptr <= r_rd_ptr + 1;
                                        r_state <= ST_LOAD_WORD;
                                    else
                                        if r_corrupt_crc = '1' then
                                            r_uart_data <= not r_crc(15 downto 8);
                                        else
                                            r_uart_data <= r_crc(15 downto 8);
                                        end if;
                                        r_uart_valid <= '1';
                                        r_state <= ST_SEND_CRC_H;
                                    end if;
                                else
                                    r_lane_idx <= r_lane_idx + 1;
                                end if;
                            end if;
                        else
                            if i_uart_tx_ready = '1' then
                                r_uart_valid <= '0';
                                if r_lane_idx = 3 then
                                    if r_rd_ptr + 1 < r_word_cnt then
                                        r_rd_ptr <= r_rd_ptr + 1;
                                        r_state <= ST_LOAD_WORD;
                                    else
                                        if r_corrupt_crc = '1' then
                                            r_uart_data <= not r_crc(15 downto 8);
                                        else
                                            r_uart_data <= r_crc(15 downto 8);
                                        end if;
                                        r_uart_valid <= '1';
                                        r_state <= ST_SEND_CRC_H;
                                    end if;
                                else
                                    r_lane_idx <= r_lane_idx + 1;
                                end if;
                            end if;
                        end if;

                    when ST_SEND_CRC_H =>
                        if r_uart_valid = '1' and i_uart_tx_ready = '1' then
                            if r_corrupt_crc = '1' then
                                r_uart_data <= not r_crc(7 downto 0);
                            else
                                r_uart_data <= r_crc(7 downto 0);
                            end if;
                            r_uart_valid <= '1';
                            r_state <= ST_SEND_CRC_L;
                        end if;

                    when ST_SEND_CRC_L =>
                        if r_uart_valid = '1' and i_uart_tx_ready = '1' then
                            r_uart_valid <= '0';
                            r_state <= ST_PKT_DONE;
                        end if;

                    when ST_PKT_DONE =>
                        if i_uart_tx_ready = '1' then
                            r_pkt_done <= '1';
                            r_wr_ptr <= 0;
                            r_rd_ptr <= 0;
                            r_word_cnt <= 0;
                            r_byte_cnt <= 0;
                            r_tx_busy <= '0';
                            r_state <= ST_COLLECT_AXIS;
                        end if;

                    when others =>
                        r_state <= ST_COLLECT_AXIS;

                end case;
            end if;
        end if;
    end process p_tx_pkt;

end architecture rtl;