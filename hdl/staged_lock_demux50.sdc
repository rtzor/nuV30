# Abstract synchronous host interface, not physical board timing.
create_clock -name SYS -period 20.000 [get_ports SYS]
# Each exposed input is launched by host registers; wrapper synchronously samples it.
set_input_delay -clock SYS -max 1.000 [get_ports {RESET_I READY_I IRQ_I NMI_I POLL_N_I DATA_I[*]}]
set_input_delay -clock SYS -min 0.000 [get_ports {RESET_I READY_I IRQ_I NMI_I POLL_N_I DATA_I[*]}]
set_output_delay -clock SYS -max 1.000 [get_ports {ADDR_O[*] DATA_O[*] STATUS_O[*] BS[*] QS[*] RD_N UBE_N LOCK_N LOCK_SYS_Q LOCK_CE_Q STATUS_SYS_Q[*] CE_O QUIET_O SS_ERR_O}]
set_output_delay -clock SYS -min 0.000 [get_ports {ADDR_O[*] DATA_O[*] STATUS_O[*] BS[*] QS[*] RD_N UBE_N LOCK_N LOCK_SYS_Q LOCK_CE_Q STATUS_SYS_Q[*] CE_O QUIET_O SS_ERR_O}]
# ALL paths single-cycle20ns. No generated CE clock, multicycle or false paths.
derive_clock_uncertainty
