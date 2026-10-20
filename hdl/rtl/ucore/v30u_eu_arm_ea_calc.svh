    // ZERO-COST: the address adder; the clocks it needs were spent above.
    rmmod = ld_rm_n[7:6];
    rmrm  = ld_rm_n[2:0];
    case (rmrm)
        3'd0: ea = gpr_n[R_BW] + gpr_n[R_IX];
        3'd1: ea = gpr_n[R_BW] + gpr_n[R_IY];
        3'd2: ea = gpr_n[R_BP] + gpr_n[R_IX];
        3'd3: ea = gpr_n[R_BP] + gpr_n[R_IY];
        3'd4: ea = gpr_n[R_IX];
        3'd5: ea = gpr_n[R_IY];
        3'd6: ea = (rmmod == 2'd0) ? 16'd0 : gpr_n[R_BP];
        default: ea = gpr_n[R_BW];
    endcase
    // Retain the EA adder's pre-displacement half without overwriting the
    // microcode tmpa register.  The distinction is normally invisible, but
    // register-form LEA exposes it through the still-armed ADD datapath.
    ea_residue_n = ea;
    // Backport upstream 427a3f5a: every EA calculation loads the retained
    // second addend. Register-form LEA can observe this otherwise hidden rail.
    ea_pair_valid_n = 1'b1;
    ea_pair_rhs_n = ((rmmod == 2'd0) && (rmrm <= 3'd3))
                  ? (rmrm[0] ? gpr_n[R_IY] : gpr_n[R_IX])
                  : ld_disp_n;
    ea = ea + ld_disp_n;
    rseg = seg_override_n ? {1'b0, seg_ovr_n}
         : ((rmrm == 3'd2) || (rmrm == 3'd3) ||
            ((rmrm == 3'd6) && (rmmod != 2'd0))) ? 3'd2 : 3'd3;
    ind_n = ea;
    al_eaconst_n = 1'b1;
    al_eaval_n   = ea;
    m_ea_n = ea;  m_seg_n = rseg;
    st_n = S_BIND;
end

//----------------------------------------------------------------------------
// loader_impl.h -- group dispatch, OPC select, operand binding
//----------------------------------------------------------------------------
