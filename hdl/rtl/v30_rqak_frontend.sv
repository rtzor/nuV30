// SPDX-License-Identifier: GPL-2.0-only
// Standalone FPGA pulse frontend, not native NEC pin timing/yield emulation.
// Inputs are synchronous to CLK, sampled at CE. CE remains available while
// v30_bus_ownership freezes CPU enables. Resolve lines externally: a 1 on
// RQAK_DRIVE_LOW means drive low, never high. External ownership begins at
// ACK end, later than INTERNAL_GRANT. Return's HIGH+two-CE gap is engineering
// policy; native BIU scheduling and physical edge alignment are not modeled.
// Remote masters must stop driving on RESET independently of grant state.
module v30_rqak_frontend (
    input  logic       CLK,
    input  logic       RESET,
    input  logic       CE,
    input  logic [1:0] RQAK_I_N,
    input  logic [1:0] INTERNAL_GRANT,
    output logic [1:0] REQUEST,
    output logic [1:0] RQAK_DRIVE_LOW,
    output logic [1:0] EXTERNAL_GRANT,
    output logic [1:0] PROTOCOL_ERROR
);
    typedef enum logic [2:0] {
        IDLE, WAIT_HIGH, ACK, OWNED, RETURN_LOW, RETURN_GAP, RELEASE_WAIT
    } phase_t;
    phase_t phase;
    logic [1:0] armed;
    logic owner;
    logic [1:0] age;
    logic [1:0] owner_mask;
    assign owner_mask = owner ? 2'b10 : 2'b01;

    always_ff @(posedge CLK) begin
        if (RESET) begin
            phase <= IDLE;
            armed <= 0;
            owner <= 0;
            age <= 0;
            REQUEST <= 0;
            RQAK_DRIVE_LOW <= 0;
            EXTERNAL_GRANT <= 0;
            PROTOCOL_ERROR <= 0;
        end else if (CE) begin
            // Independent channel capture. The active owner is handled by
            // its phase below, including local ACK echo masking.
            for (int ch = 0; ch < 2; ch++) begin
                if (phase == IDLE || ch != int'(owner)) begin
                    if (RQAK_I_N[ch]) armed[ch] <= 1;
                    else if (armed[ch]) begin
                        armed[ch] <= 0;
                        if (REQUEST[ch]) PROTOCOL_ERROR[ch] <= 1;
                        else REQUEST[ch] <= 1;
                    end
                end
            end
            case (phase)
                IDLE: if (|INTERNAL_GRANT) begin
                    owner <= INTERNAL_GRANT[1];
                    armed[INTERNAL_GRANT[1]] <= 0;
                    if ((RQAK_I_N & INTERNAL_GRANT) != 0) begin
                        RQAK_DRIVE_LOW <= INTERNAL_GRANT;
                        phase <= ACK;
                    end else phase <= WAIT_HIGH;
                end
                WAIT_HIGH: if (RQAK_I_N[owner]) begin
                    armed[owner] <= 0;
                    RQAK_DRIVE_LOW <= owner_mask;
                    phase <= ACK;
                end
                ACK: begin
                    // Sample at ACK end belongs to our own reflected pulse.
                    RQAK_DRIVE_LOW <= 0;
                    EXTERNAL_GRANT <= owner_mask;
                    armed[owner] <= 0;
                    age <= 0;
                    phase <= OWNED;
                end
                OWNED: begin
                    if (age != 2) age <= age + 1'b1;
                    if (RQAK_I_N[owner]) armed[owner] <= 1;
                    else if (age == 0) begin
                        // E+1 LOW is malformed even before a post-ACK HIGH
                        // arms an edge; it cannot mature into a later return.
                        PROTOCOL_ERROR[owner] <= 1;
                        armed[owner] <= 0;
                    end else if (armed[owner]) begin
                        armed[owner] <= 0;
                        EXTERNAL_GRANT <= 0;
                        phase <= RETURN_LOW;
                    end
                end
                RETURN_LOW: if (RQAK_I_N[owner]) begin
                    age <= 0;
                    armed[owner] <= 1;
                    phase <= RETURN_GAP;
                end
                RETURN_GAP: begin
                    if (!RQAK_I_N[owner] && armed[owner]) begin
                        PROTOCOL_ERROR[owner] <= 1;
                        armed[owner] <= 0;
                    end else if (RQAK_I_N[owner]) armed[owner] <= 1;
                    if (age == 1) begin
                        REQUEST[owner] <= 0;
                        phase <= RELEASE_WAIT;
                    end else age <= age + 1'b1;
                end
                RELEASE_WAIT: begin
                    if (!RQAK_I_N[owner] && armed[owner]) begin
                        PROTOCOL_ERROR[owner] <= 1;
                        armed[owner] <= 0;
                    end else if (RQAK_I_N[owner]) armed[owner] <= 1;
                    if (!(|INTERNAL_GRANT)) phase <= IDLE;
                end
                default: phase <= IDLE;
            endcase
        end
    end
endmodule
