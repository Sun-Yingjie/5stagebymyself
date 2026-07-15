module rv32_pipeline_ctrl (
    input  logic                    rst,
    input  logic                    trap_take,
    input  logic                    mem_response_wait,
    input  logic                    ex_request_wait,
    input  logic                    ex_multicycle_wait,
    input  logic                    raw_redirect_valid,
    input  logic                    load_use_hazard,
    input  logic                    fetch_response_available,

    output rv32_pkg::fetch_action_e fetch_action,
    output rv32_pkg::pipe_action_e  if_id_action,
    output rv32_pkg::pipe_action_e  id_ex_action,
    output rv32_pkg::pipe_action_e  ex_mem_action,
    output rv32_pkg::pipe_action_e  mem_wb_action,
    output logic                    redirect_commit
);

    import rv32_pkg::*;

    always_comb begin
        // 默认情况：前端有新指令，所有流水级正常前进
        fetch_action    = FETCH_SEQUENTIAL;
        if_id_action    = PIPE_LOAD;
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
        else if (mem_response_wait) begin
            fetch_action    = FETCH_HOLD;
            if_id_action    = PIPE_HOLD;
            id_ex_action    = PIPE_HOLD;
            ex_mem_action   = PIPE_HOLD;
            mem_wb_action   = PIPE_CLEAR;
            redirect_commit = 1'b0;
        end
        else if (ex_request_wait || ex_multicycle_wait) begin
            fetch_action    = FETCH_HOLD;
            if_id_action    = PIPE_HOLD;
            id_ex_action    = PIPE_HOLD;
            ex_mem_action   = PIPE_CLEAR;
            mem_wb_action   = PIPE_LOAD;
            redirect_commit = 1'b0;
        end
        else if (raw_redirect_valid) begin
            fetch_action    = FETCH_REDIRECT;
            if_id_action    = PIPE_CLEAR;
            id_ex_action    = PIPE_CLEAR;
            ex_mem_action   = PIPE_LOAD;
            mem_wb_action   = PIPE_LOAD;
            redirect_commit = 1'b1;
        end
        else if (load_use_hazard) begin
            fetch_action    = FETCH_HOLD;
            if_id_action    = PIPE_HOLD;
            id_ex_action    = PIPE_CLEAR;
            ex_mem_action   = PIPE_LOAD;
            mem_wb_action   = PIPE_LOAD;
            redirect_commit = 1'b0;
        end
        else if (!fetch_response_available) begin
            fetch_action    = FETCH_HOLD;
            if_id_action    = PIPE_CLEAR;
            id_ex_action    = PIPE_LOAD;
            ex_mem_action   = PIPE_LOAD;
            mem_wb_action   = PIPE_LOAD;
            redirect_commit = 1'b0;
        end
    end
endmodule
