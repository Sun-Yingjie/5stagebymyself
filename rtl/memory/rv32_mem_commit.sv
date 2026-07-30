module rv32_mem_commit (
    input  logic                         rst,
    input  rv32_pkg::ex_mem_t            ex_mem_q,

    input  logic                         lsu_response_fire,
    input  logic [31:0]                  lsu_load_result,
    input  rv32_pkg::exception_t         lsu_exception,

    input  logic                         csr_access_illegal,
    input  logic [31:0]                  csr_read_data,
    input  logic [31:0]                  mret_target,
    input  logic [31:0]                  resume_pc,

    output logic                         mem_memory_access,
    output logic                         mem_stage_complete,
    output rv32_pkg::exception_t         final_mem_exception,
    output rv32_pkg::mem_wb_t            mem_wb_candidate,
    output logic                         mem_commit_candidate,
    output logic                         mret_commit,
    output logic [31:0]                  effective_architectural_next_pc,
    output logic [31:0]                  boundary_resume_pc,
    output logic                         mem_request_block
);

    import rv32_pkg::*;

    assign mem_memory_access =
        ex_mem_q.valid &&
        (
            ex_mem_q.mem_ctrl.memory_read ||
            ex_mem_q.mem_ctrl.memory_write
        );

    assign mem_stage_complete =
        !mem_memory_access || lsu_response_fire;

    // Preserve the synchronous-exception priority at the MEM boundary.
    always_comb begin
        final_mem_exception = '0;

        if (ex_mem_q.valid) begin
            if (ex_mem_q.exception.valid) begin
                final_mem_exception = ex_mem_q.exception;
            end else if (csr_access_illegal) begin
                final_mem_exception.valid = 1'b1;
                final_mem_exception.cause =
                    EXCEPTION_CAUSE_ILLEGAL_INSTRUCTION;
                final_mem_exception.value = ex_mem_q.instruction;
            end else if (lsu_exception.valid) begin
                final_mem_exception = lsu_exception;
            end
        end
    end

    always_comb begin
        mem_wb_candidate = '0;

        mem_wb_candidate.valid =
            ex_mem_q.valid &&
            mem_stage_complete &&
            !final_mem_exception.valid;

        mem_wb_candidate.pc            = ex_mem_q.pc;
        mem_wb_candidate.instruction   = ex_mem_q.instruction;
        mem_wb_candidate.pc_plus_4     = ex_mem_q.pc_plus_4;
        mem_wb_candidate.exec_result   = ex_mem_q.exec_result;
        mem_wb_candidate.load_result   = lsu_load_result;
        mem_wb_candidate.csr_read_data = csr_read_data;
        mem_wb_candidate.rd_addr       = ex_mem_q.rd_addr;
        mem_wb_candidate.wb_ctrl       = ex_mem_q.wb_ctrl;
        mem_wb_candidate.exception     = final_mem_exception;
    end

    // This preview is intentionally independent of pipeline acceptance.
    // rv32_core forms commit_valid only after pipeline control selects LOAD.
    assign mem_commit_candidate =
        !rst &&
        ex_mem_q.valid &&
        mem_stage_complete &&
        !final_mem_exception.valid &&
        mem_wb_candidate.valid;

    assign mret_commit =
        mem_commit_candidate && ex_mem_q.mret;

    assign effective_architectural_next_pc =
        ex_mem_q.mret ? mret_target : ex_mem_q.architectural_next_pc;

    assign boundary_resume_pc =
        mem_commit_candidate
            ? effective_architectural_next_pc
            : resume_pc;

    // Interrupt blocking remains a top-level OR term so interrupt preview
    // cannot feed back into mem_commit_candidate.
    assign mem_request_block =
        (ex_mem_q.valid && final_mem_exception.valid) ||
        mret_commit;

endmodule
