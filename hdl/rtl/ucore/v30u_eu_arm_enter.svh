    // ZERO-COST: micro-row 0 opens on the clock the caller handed over
    upc_page_n = ld_page_n;
    upc_opc_n  = opc_reg_n;
    upc_loc_n  = 4'd0;
    ending_n = 1'b0; rowq_n = 2'd0; row_posted_n = 1'b0; row_paired_n = 1'b0;
    suppress_commit_n = 1'b0;
    st_n = S_ROW;
    stop = 1'b1;
end

//----------------------------------------------------------------------------
// exec_impl.h -- run_micro
//----------------------------------------------------------------------------
