    // ZERO-COST: the prefix test.
    opc8080_n = mode8080_n;
    pv = pla3_lookup(mode8080_n ? PLA3_MODE_8080 : PLA3_MODE_NATIVE, ld_b_n);
    if (pla3_is_prefix(pv)) begin
        case (pla3_xop(pv))
            PLA3_BL1_SEG_PREFIX: begin
                seg_override_n = 1'b1; seg_ovr_n = ld_b_n[4:3];
            end
            PLA3_BL1_REP_PFX:   rep_kind_n = REP_E;
            PLA3_BL1_REPNE_PFX: rep_kind_n = REP_NE;
            PLA3_BL1_REPC_PFX:  rep_kind_n = REP_C;
            PLA3_BL1_REPNC_PFX: rep_kind_n = REP_NC;
            PLA3_BL1_LOCK, PLA3_BL1_LOCK_ALIAS: lock_pfx_n = 1'b1;
            PLA3_BL1_EXT_PREFIX: ld_ext_n = 1'b1;
            default: ;
        endcase
        pfxcnt_n = pfxcnt_n + 8'd1;
        // the 0F escape is a 2-clock re-decode; every other prefix retires as
        // its own 2-clock instruction with its own F pop.
        // KM (2026-08-11): that stays true of the POPS and the `QS` pins, and
        // it is deliberately NOT what the TF boundary reads any more -- silicon
        // samples the escape's OPCODE pop (`S_EXT_POP`) too, and the term that
        // says so is `q_bnd_pop` in v30u_eu.sv.  `S_EXT_CHG1` still sets
        // nothing: setting `pop_is_first_n` here would be INERT (`q_first`
        // consults it only at `S_OPC_POP`, and this branch's successor is
        // `S_EXT_POP`), so it would move neither the boundary nor the pins.
        st_n = (pla3_xop(pv) == PLA3_BL1_EXT_PREFIX) ? S_EXT_CHG1 : S_PFX_CHG;
        stop = 1'b1;
    end else begin
        st_n = S_DECODE2;
    end
end

