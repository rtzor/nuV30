    // the DEFERRED opcode pre-pop: `wait_bus()` then the pop, then M8b's
    // clock after it (`if (deferred) biu.charge(1)`).
    if (!retire_ok_n) stop = 1'b1;
    // the same boundary, on the deferred arm (`exec_impl.h`'s second
    // `at_fire_boundary()` call).  `poste` was raised by the `E` row itself
    // here, so only the decision is owed.
    else if (bnd_take) begin
        irq_shadow_n = 1'b0;
        irq_sel_nmi_n = irq_nmi_lvl;
        irq_sel_brk_n = !irq_take;                                // §86
        brk_arm_n = brk_arm_n && irq_take;                        // fz2 C1
        st_n = S_IRQ_D;
        stop = 1'b1;
    end
    else if (!q_ripe) stop = 1'b1;
    else begin
        irq_shadow_n = 1'b0;
        opc_byte_n = q_byte;
        opc_valid_n = 1'b1;
        pop_is_first_n = 1'b0;
        // M8b: the clock AFTER the pop belongs to the successor's decode --
        // `if (deferred) biu.charge(1)` -- which is this clock, spent here.
        st_n = S_INSTR_END;
    end
end

