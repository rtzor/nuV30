    // ZERO-COST: the successor's opcode was pre-popped on the E row's clock.
    ld_b_n = opc_byte_n;
    opc_valid_n = 1'b0;
    pc_n = pc_n + 16'd1;
    st_n = S_DECODE;
end

