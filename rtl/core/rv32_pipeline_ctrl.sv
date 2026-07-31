module rv32_pipeline_ctrl (
    // older instruction(/stage/event) has higher priority
    input  logic                    rst,                        // all stage clear, restart from RESET_VECTOR
    input  logic                    trap_take,                  // MEM stage, synchronous exception
    input  logic                    post_commit_interrupt_take, // interrupt boundary: 1. after MEM stage commit
    input  logic                    empty_interrupt_take,       // interrupt boundary: 2. pipeline is empty, no load/store outstanding and MDU idle
    input  logic                    mret_commit,                // MEM stage, mret commit
    input  logic                    mem_response_wait,          // MEM stage, waiting for DMem response
    input  logic                    ex_request_wait,            // EX stage, waiting for DMem request handshake, req_valid = 1, req_ready = 0
    input  logic                    ex_multicycle_wait,         // EX stage, waiting for MDU result
    input  logic                    raw_redirect_valid,         // EX stage, taken branch or jal or jalr
    input  logic                    late_result_hazard,         // forward unit, compare id consumer and ex producer, load/csr-use hazard
    input  logic                    fetch_response_available,   // IF stage, IMem response valid

    output rv32_pkg::fetch_action_e fetch_action,
    output rv32_pkg::pipe_action_e  if_id_action,
    output rv32_pkg::pipe_action_e  id_ex_action,
    output rv32_pkg::pipe_action_e  ex_mem_action,
    output rv32_pkg::pipe_action_e  mem_wb_action,
    output logic                    redirect_commit
);

    import rv32_pkg::*;

    always_comb begin
        // default, all stages flow to the next stage
        fetch_action    = FETCH_SEQUENTIAL;
        if_id_action    = PIPE_LOAD;        // Attention: PIPE_LOAD does not mean valid, PIPE_LOAD can also load a bubble while candidate.valid = 0
        id_ex_action    = PIPE_LOAD;
        ex_mem_action   = PIPE_LOAD;
        mem_wb_action   = PIPE_LOAD;
        redirect_commit = 1'b0;
        if (rst) begin
            fetch_action    = FETCH_RESET;
            if_id_action    = PIPE_CLEAR;
            id_ex_action    = PIPE_CLEAR;
            ex_mem_action   = PIPE_CLEAR;
            mem_wb_action   = PIPE_CLEAR;
            redirect_commit = 1'b0;
        end
        else if (trap_take) begin
            fetch_action    = FETCH_REDIRECT;
            if_id_action    = PIPE_CLEAR;
            id_ex_action    = PIPE_CLEAR;
            ex_mem_action   = PIPE_CLEAR;
            mem_wb_action   = PIPE_CLEAR;
            redirect_commit = 1'b0;
        end
        else if (post_commit_interrupt_take) begin
            fetch_action    = FETCH_REDIRECT;
            if_id_action    = PIPE_CLEAR;
            id_ex_action    = PIPE_CLEAR;
            ex_mem_action   = PIPE_CLEAR;
            mem_wb_action   = PIPE_LOAD;
            redirect_commit = 1'b0;
        end
        else if (empty_interrupt_take) begin
            fetch_action    = FETCH_REDIRECT;
            if_id_action    = PIPE_CLEAR;
            id_ex_action    = PIPE_CLEAR;
            ex_mem_action   = PIPE_CLEAR;
            mem_wb_action   = PIPE_CLEAR;
            redirect_commit = 1'b0;
        end
        else if (mret_commit) begin
            fetch_action    = FETCH_REDIRECT;
            if_id_action    = PIPE_CLEAR;
            id_ex_action    = PIPE_CLEAR;
            ex_mem_action   = PIPE_CLEAR;
            mem_wb_action   = PIPE_LOAD;
            redirect_commit = 1'b0;
        end
        else if (mem_response_wait) begin
            fetch_action    = FETCH_HOLD;
            if_id_action    = PIPE_HOLD;
            id_ex_action    = PIPE_HOLD;
            ex_mem_action   = PIPE_HOLD;
            mem_wb_action = PIPE_CLEAR;         // Clear MEM/WB after the current WB instruction retires, preventing repeated retirement
            redirect_commit = 1'b0;
        end
        else if (ex_request_wait || ex_multicycle_wait) begin
            fetch_action    = FETCH_HOLD;
            if_id_action    = PIPE_HOLD;
            id_ex_action    = PIPE_HOLD;
            ex_mem_action = PIPE_CLEAR; // Insert a bubble into MEM while the current EX instruction waits
            mem_wb_action = PIPE_LOAD;  // Let the current MEM instruction advance to WB
            redirect_commit = 1'b0;
        end
        else if (raw_redirect_valid) begin      // taken branch/jal/jalr
            fetch_action    = FETCH_REDIRECT;   // Redirect fetch and stale wrong-path requests
            if_id_action    = PIPE_CLEAR;       // Flush the younger instruction currently in ID
            id_ex_action    = PIPE_CLEAR;       // Insert a bubble behind the redirecting EX instruction
            ex_mem_action   = PIPE_LOAD;        // Move the redirecting EX instruction into MEM
            mem_wb_action   = PIPE_LOAD;        // Move the older MEM instruction into WB
            redirect_commit = 1'b1;
        end
        else if (late_result_hazard) begin
            fetch_action    = FETCH_HOLD;  // Stop sequential fetch progression
            if_id_action    = PIPE_HOLD;   // Keep the dependent instruction in ID
            id_ex_action    = PIPE_CLEAR;  // Insert a bubble into EX
            ex_mem_action   = PIPE_LOAD;   // Let the late-result producer advance to MEM
            mem_wb_action   = PIPE_LOAD;   // Let the older MEM instruction advance to WB
            redirect_commit = 1'b0;
        end
        else if (!fetch_response_available) begin
            fetch_action    = FETCH_HOLD;  // No usable response; do not advance sequential fetch
            if_id_action    = PIPE_CLEAR;  // Insert a bubble into ID
            id_ex_action    = PIPE_LOAD;   // Let the current ID instruction advance to EX
            ex_mem_action   = PIPE_LOAD;   // Let the current EX instruction advance to MEM
            mem_wb_action   = PIPE_LOAD;   // Let the current MEM instruction advance to WB
            redirect_commit = 1'b0;
        end
    end
endmodule
