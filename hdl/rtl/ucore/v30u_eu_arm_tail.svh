    // ZERO-COST: run_micro's tail -- a staged write still owes the bus data.
    if (pend_active_n) st_n = S_TAIL_W;
    else if (opc_valid_n) st_n = S_INSTR_END;
    else st_n = S_TAIL_POP;
    if (st_n != S_INSTR_END) stop = 1'b1;
end

