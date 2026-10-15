# TimeQuest report script, planned only; run after explicit root authorization.
# No constraint edits. Collections are physical-retention witnesses, NOT 5/4 endpoints.
set stages [get_registers {*dut*u_staged_lock*}]
set consumer [get_registers {*LOCK_SYS_Q*}]
set tickconsumer [get_registers {*LOCK_CE_Q*}]
if {[get_collection_size $stages]==0 || [get_collection_size $consumer]==0 || [get_collection_size $tickconsumer]==0} {error "Expected full stage/LOCK consumers absent"}
report_timing -to $consumer -npaths 100 -detail full_path -file lock_sys_paths.rpt
report_timing -to $tickconsumer -npaths 100 -detail full_path -file lock_ce_paths.rpt
report_timing -from $stages -npaths 100 -detail full_path -file stage_launch_paths.rpt
report_timing -to $stages -npaths 100 -detail full_path -file stage_capture_paths.rpt
# Root must separately inspect retained VQM connectivity, replica enables, all-domain
# setup/hold/TNS, unconstrained ports/cones and ignored assignments. A nonempty
# register collection alone does NOT prove that a timed path or required cone survives.
