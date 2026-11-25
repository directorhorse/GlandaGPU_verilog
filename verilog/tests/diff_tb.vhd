library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity diff_tb is end;
architecture bench of diff_tb is
    signal clk, reset, wr, rd : std_ulogic := '0';
    signal addr : std_ulogic_vector(21 downto 0) := (others => '0');
    signal wd, q : std_ulogic_vector(31 downto 0) := (others => '0');
    signal stall, hs, vs, active, irq : std_ulogic;
    signal r,g,b : std_ulogic_vector(3 downto 0);
begin
    dut: entity work.top_gpu port map(clk, reset, addr, wr, wd, rd, q, stall,
                                      hs, vs, active, r, g, b, irq);
    process
        file vectors : text open read_mode is "vectors.txt";
        file trace : text open write_mode is "vhdl.trace";
        variable l, o : line;
        variable n, rst, w, re, a : natural;
        variable data : std_ulogic_vector(31 downto 0);
        variable pre_wait : std_ulogic;
        variable sample, prev : std_ulogic_vector(48 downto 0);
        variable cycle : natural := 0;
    begin
        while not endfile(vectors) loop
            readline(vectors,l); read(l,n); read(l,rst); read(l,w); read(l,re);
            read(l,a); hread(l,data);
            reset <= std_ulogic'val(2+rst); wr <= std_ulogic'val(2+w);
            rd <= std_ulogic'val(2+re); addr <= std_ulogic_vector(to_unsigned(a,22)); wd <= data;
            for i in 1 to n loop
                wait for 5 ns; pre_wait := stall; clk <= '1'; wait for 1 ns;
                sample := pre_wait & irq & hs & vs & active & r & g & b & x"00000000";
                if rd='1' and pre_wait='0' then sample(31 downto 0) := q; end if;
                sample := to_x01(sample); -- VHDL uninitialized RAM ('U') maps to Verilog 'x'
                if cycle=0 or sample/=prev then
                    write(o,cycle); write(o,string'(" ")); write(o,to_string(sample)); writeline(trace,o);
                end if;
                prev := sample; cycle := cycle+1; wait for 4 ns; clk <= '0';
            end loop;
        end loop;
        write(o,cycle); write(o,string'(" END")); writeline(trace,o);
        wait;
    end process;
end;
