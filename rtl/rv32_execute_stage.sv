module rv32_execute_stage (
    input  logic                         clk,
    input  logic                         rst,

    input  rv32_pkg::id_ex_t             id_ex_q,
    input  rv32_pkg::forward_select_e    rs1_forward_select,
    input  rv32_pkg::forward_select_e    rs2_forward_select,
    input  logic [31:0]                  ex_mem_forward_value,
    input  logic [31:0]                  mem_wb_forward_value,

    input  rv32_pkg::pipe_action_e       id_ex_action,
    input  rv32_pkg::pipe_action_e       ex_mem_action,
    input  logic                         execute_kill,

    output rv32_pkg::ex_mem_t            ex_mem_active_candidate,
    output rv32_pkg::redirect_t          raw_redirect,
    output logic                         ex_hold_valid,
    output logic                         ex_multicycle_wait,
    output logic                         mdu_idle,

    // Stable verification observability for the multicycle protocol.
    output logic                         mdu_req_valid,
    output logic                         mdu_req_ready,
    output logic                         mdu_rsp_valid,
    output logic                         mdu_rsp_ready,
    output logic [31:0]                  mdu_rsp_result,
    output logic                         mdu_kill
);

    import rv32_pkg::*;

    ex_mem_t        ex_mem_base_candidate;
    ex_mem_t        ex_mem_candidate;
    ex_mem_t        ex_mem_hold_q;
    redirect_t      ex_raw_redirect;
    redirect_t      ex_redirect_hold_q;
    logic           ex_hold_valid_q;
    logic           m_ex_valid;
    logic [31:0]    rs1_exec;
    logic [31:0]    rs2_exec;
    mdu_operation_e mdu_req_operation;

    rv32_exu u_exu (
        .id_ex_q             (id_ex_q),
        .rs1_forward_select  (rs1_forward_select),
        .rs2_forward_select  (rs2_forward_select),
        .ex_mem_forward_value(ex_mem_forward_value),
        .mem_wb_forward_value(mem_wb_forward_value),
        .rs1_exec            (rs1_exec),
        .rs2_exec            (rs2_exec),
        .ex_mem_candidate    (ex_mem_base_candidate),
        .raw_redirect        (ex_raw_redirect)
    );

    assign m_ex_valid =
        id_ex_q.valid &&
        id_ex_q.mdu_ctrl.valid &&
        !id_ex_q.exception.valid;

    assign mdu_kill = rst || execute_kill;
    assign mdu_req_operation =
        mdu_operation_e'(id_ex_q.mdu_ctrl.operation);
    assign mdu_req_valid = m_ex_valid && mdu_idle && !mdu_kill;
    assign ex_multicycle_wait =
        m_ex_valid && !mdu_rsp_valid && !mdu_kill;
    assign mdu_rsp_ready =
        m_ex_valid &&
        (ex_mem_action == PIPE_LOAD) &&
        !mdu_kill;

    rv32_mdu u_mdu (
        .clk           (clk),
        .rst           (rst),
        .req_valid     (mdu_req_valid),
        .req_ready     (mdu_req_ready),
        .req_operation (mdu_req_operation),
        .req_operand_a (rs1_exec),
        .req_operand_b (rs2_exec),
        .rsp_valid     (mdu_rsp_valid),
        .rsp_ready     (mdu_rsp_ready),
        .rsp_result    (mdu_rsp_result),
        .idle          (mdu_idle),
        .kill          (mdu_kill)
    );

    always_comb begin
        ex_mem_candidate = ex_mem_base_candidate;

        if (id_ex_q.mdu_ctrl.valid) begin
            ex_mem_candidate.valid       = m_ex_valid && mdu_rsp_valid;
            ex_mem_candidate.exec_result = mdu_rsp_result;
        end
    end

    // A non-M instruction can remain in ID/EX after its forwarding producers
    // have advanced. Preserve the first post-forwarding packet and redirect
    // until pipeline control releases ID/EX.
    always_comb begin
        ex_mem_active_candidate = ex_mem_candidate;

        if (ex_hold_valid_q) begin
            ex_mem_active_candidate = ex_mem_hold_q;
        end
    end

    assign raw_redirect =
        ex_hold_valid_q ? ex_redirect_hold_q : ex_raw_redirect;
    assign ex_hold_valid = ex_hold_valid_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            ex_hold_valid_q    <= 1'b0;
            ex_mem_hold_q      <= '0;
            ex_redirect_hold_q <= '0;
        end else begin
            if (
                !ex_hold_valid_q &&
                id_ex_q.valid &&
                !id_ex_q.mdu_ctrl.valid &&
                (id_ex_action == PIPE_HOLD)
            ) begin
                ex_hold_valid_q    <= 1'b1;
                ex_mem_hold_q      <= ex_mem_candidate;
                ex_redirect_hold_q <= ex_raw_redirect;
            end else if (id_ex_action != PIPE_HOLD) begin
                ex_hold_valid_q <= 1'b0;
            end
        end
    end

endmodule
