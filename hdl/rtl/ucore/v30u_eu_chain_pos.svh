// Original project adaptation of upstream chain position bookkeeping.
`ifndef SYNTHESIS
    chain_used = chain_used + 4'd1;
`ifdef CHAIN_PROBE
    if (!cp_seen[{chain_used - 4'd1, st_n}]) begin
        cp_seen[{chain_used - 4'd1, st_n}] = 1'b1;
        cp_fd = $fopen(`CHAIN_PROBE, "a");
        $fwrite(cp_fd, "POS %0d ST %0d\n", chain_used - 4'd1, st_n);
        $fclose(cp_fd);
    end
`endif
`endif
