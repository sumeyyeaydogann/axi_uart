library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package crc16_pkg is

    constant C_SOF_DEFAULT : std_logic_vector(15 downto 0) := x"A55A";
    constant C_MIN_PAYLOAD_BYTES : natural := 24;
    constant C_MAX_PAYLOAD_BYTES : natural := 2024;
    constant C_CRC_BYTES : natural := 2;
    constant C_MIN_BLEN_BYTES : natural := 26;
    constant C_MAX_BLEN_BYTES : natural := 2026;
    constant C_CRC16_INIT : std_logic_vector(15 downto 0) := x"FFFF";
    constant C_CRC16_POLY : std_logic_vector(15 downto 0) := x"1021";

    function f_crc16_ccitt_byte(
        i_crc_cur : std_logic_vector(15 downto 0);
        i_data_byte : std_logic_vector(7 downto 0)
    ) return std_logic_vector;

    function f_count_keep_bytes(
        i_tkeep : std_logic_vector(3 downto 0)
    ) return natural;

end package crc16_pkg;

package body crc16_pkg is

    function f_crc16_ccitt_byte(
        i_crc_cur : std_logic_vector(15 downto 0);
        i_data_byte : std_logic_vector(7 downto 0)
    ) return std_logic_vector is
        variable v_crc : std_logic_vector(15 downto 0);
        variable v_fb : std_logic;
    begin
        v_crc := i_crc_cur;
        for b in 7 downto 0 loop
            v_fb := v_crc(15) xor i_data_byte(b);
            v_crc := v_crc(14 downto 0) & '0';
            if v_fb = '1' then
                v_crc := v_crc xor C_CRC16_POLY;
            end if;
        end loop;
        return v_crc;
    end function f_crc16_ccitt_byte;

    function f_count_keep_bytes(
        i_tkeep : std_logic_vector(3 downto 0)
    ) return natural is
        variable v_cnt : natural range 0 to 4;
    begin
        v_cnt := 0;
        for i in 0 to 3 loop
            if i_tkeep(i) = '1' then
                v_cnt := v_cnt + 1;
            end if;
        end loop;
        return v_cnt;
    end function f_count_keep_bytes;

end package body crc16_pkg;