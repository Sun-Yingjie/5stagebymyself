module rv32_core #(
    parameter logic [31:0] RESET_VECTOR  = 32'h0000_0000,
    parameter logic [31:0] MTVEC_RESET   = 32'h0000_0000,
    parameter bit          COPROC_ENABLE = 1'b0
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        irq_software,
    input  logic        irq_timer,
    input  logic        irq_external,

    output logic        imem_req_valid,
    input  logic        imem_req_ready,
    output logic [31:0] imem_req_addr,
    input  logic        imem_rsp_valid,
    output logic        imem_rsp_ready,
    input  logic [31:0] imem_rsp_data,
    input  logic        imem_rsp_error,

    output logic        dmem_req_valid,
    input  logic        dmem_req_ready,
    output logic        dmem_req_write,
    output logic [31:0] dmem_req_addr,
    output logic [31:0] dmem_req_wdata,
    output logic [3:0]  dmem_req_wstrb,
    input  logic        dmem_rsp_valid,
    output logic        dmem_rsp_ready,
    input  logic [31:0] dmem_rsp_rdata,
    input  logic        dmem_rsp_error,

    // Optional architectural retirement trace interface.
    output logic        retire_valid,
    output logic [31:0] retire_pc,
    output logic [31:0] retire_instr,
    output logic        retire_rd_we,
    output logic [4:0]  retire_rd_addr,
    output logic [31:0] retire_rd_data,

    // Optional architectural trap observation interface.
    output logic        trap_valid,
    output logic [31:0] trap_pc,
    output logic [31:0] trap_cause,
    output logic [31:0] trap_value,

    // Reserved coprocessor interface; fixed inactive in this core version.
    output logic        cp_req_valid,
    input  logic        cp_req_ready,
    output logic [31:0] cp_req_pc,
    output logic [31:0] cp_req_instr,
    output logic [31:0] cp_req_rs1_data,
    output logic [31:0] cp_req_rs2_data,
    input  logic        cp_rsp_valid,
    output logic        cp_rsp_ready,
    input  logic [31:0] cp_rsp_data,
    input  logic        cp_rsp_error
);

    import rv32_pkg::*;

    // Pipeline-state naming convention:
    //   *_q         : current registered state
    //   *_d         : final next state after LOAD/HOLD/CLEAR selection
    //   *_candidate : combinational value proposed by the preceding stage
    // Only *_q is implemented as flip-flops. The other forms are combinational.

    // Pipeline state
    if_id_t  if_id_q;
    if_id_t  if_id_d;
    if_id_t  if_id_candidate;

    id_ex_t  id_ex_q;
    id_ex_t  id_ex_d;
    id_ex_t  id_ex_candidate;

    ex_mem_t ex_mem_q;
    ex_mem_t ex_mem_d;
    ex_mem_t ex_mem_active_candidate;

    mem_wb_t mem_wb_q;
    mem_wb_t mem_wb_d;
    mem_wb_t mem_wb_candidate;

    // Stage interconnect and global control
    wb_bus_t    wb_bus;
    redirect_t  raw_redirect;
    redirect_t  trap_redirect;
    redirect_t  interrupt_redirect;
    redirect_t  mret_redirect;
    redirect_t  qualified_redirect;
    exception_t lsu_exception;
    exception_t final_mem_exception;

    // Stable execute-stage observation retained for protocol assertions.
    logic      ex_hold_valid_q;

    fetch_action_e fetch_action;
    pipe_action_e  if_id_action;
    pipe_action_e  id_ex_action;
    pipe_action_e  ex_mem_action;
    pipe_action_e  mem_wb_action;

    forward_select_e rs1_forward_select;
    forward_select_e rs2_forward_select;

    logic fetch_response_available;
    logic late_result_hazard;
    logic csr_access_valid;
    logic csr_access_illegal;
    logic ex_request_block;
    logic mem_request_block;
    logic ex_request_wait;
    logic mem_memory_access;
    logic mem_stage_complete;
    logic mem_response_wait;
    logic lsu_response_fire;
    logic trap_take;
    logic post_commit_interrupt_take;
    logic empty_interrupt_take;
    logic interrupt_take;
    logic mret_commit;
    logic mem_commit_candidate;
    logic commit_valid;
    logic redirect_commit;
    logic if_id_ready;
    logic ex_multicycle_wait;
    logic lsu_outstanding;
    logic pipeline_empty;
    logic empty_interrupt_boundary;
    logic execute_kill;

    logic        mdu_req_valid;
    logic        mdu_req_ready;
    logic        mdu_rsp_valid;
    logic        mdu_rsp_ready;
    logic [31:0] mdu_rsp_result;
    logic        mdu_idle;
    logic        mdu_kill;

    logic [31:0] ex_mem_forward_value;
    logic [31:0] mem_wb_forward_value;
    logic [31:0] lsu_load_result;
    logic [31:0] csr_read_data;
    logic [31:0] mret_target;
    logic [31:0] effective_architectural_next_pc;
    logic [31:0] boundary_resume_pc;
    logic [31:0] resume_pc_q;
    logic [31:0] resume_pc_d;

    // Flattened control fields keep Icarus port widths unambiguous.
    logic id_ex_result_late;
    logic ex_mem_register_write;
    logic ex_mem_result_late;
    logic mem_wb_register_write;
    csr_operation_e ex_mem_csr_operation;
    logic ex_mem_csr_read_enable;
    logic ex_mem_csr_write_enable;

    // Writeback and architectural retirement observation
    rv32_wbu u_wbu (
        .rst            (rst),
        .mem_wb_q       (mem_wb_q),
        .wb_bus         (wb_bus),
        .retire_valid   (retire_valid),
        .retire_pc      (retire_pc),
        .retire_instr   (retire_instr),
        .retire_rd_we   (retire_rd_we),
        .retire_rd_addr (retire_rd_addr),
        .retire_rd_data (retire_rd_data)
    );

    // Forwarding datapath
    assign id_ex_result_late =
        id_ex_q.mem_ctrl.memory_read || id_ex_q.csr_ctrl.valid;
    assign ex_mem_register_write = ex_mem_q.wb_ctrl.register_write;
    assign ex_mem_result_late =
        ex_mem_q.mem_ctrl.memory_read || ex_mem_q.csr_ctrl.valid;
    assign mem_wb_register_write = mem_wb_q.wb_ctrl.register_write;
    assign ex_mem_csr_operation =
        csr_operation_e'(ex_mem_q.csr_ctrl.operation);
    assign ex_mem_csr_read_enable = ex_mem_q.csr_ctrl.read_enable;
    assign ex_mem_csr_write_enable = ex_mem_q.csr_ctrl.write_enable;

    assign mem_wb_forward_value = wb_bus.rd_data;

    always_comb begin
        ex_mem_forward_value = '0;

        case (ex_mem_q.wb_ctrl.writeback_select)
            WB_EXEC: begin
                ex_mem_forward_value = ex_mem_q.exec_result;
            end

            WB_PC_PLUS_4: begin
                ex_mem_forward_value = ex_mem_q.pc_plus_4;
            end

            default: begin
                ex_mem_forward_value = '0;
            end
        endcase
    end

    // Frontend control
    assign if_id_ready = (if_id_action == PIPE_LOAD);

    always_comb begin
        qualified_redirect = '0;

        if (trap_take) begin
            qualified_redirect = trap_redirect;
        end else if (interrupt_take) begin
            qualified_redirect = interrupt_redirect;
        end else if (mret_commit) begin
            qualified_redirect = mret_redirect;
        end else if (redirect_commit && raw_redirect.valid) begin
            qualified_redirect = raw_redirect;
        end
    end

    // Coprocessor is reserved but disabled in the frozen core architecture.
    assign cp_req_valid    = 1'b0;
    assign cp_req_pc       = '0;
    assign cp_req_instr    = '0;
    assign cp_req_rs1_data = '0;
    assign cp_req_rs2_data = '0;
    assign cp_rsp_ready    = 1'b0;

    // Pipeline stage modules
    rv32_ifu #(
        .RESET_VECTOR (RESET_VECTOR)
    ) u_ifu (
        .clk                      (clk),
        .rst                      (rst),
        .fetch_action             (fetch_action),
        .qualified_redirect       (qualified_redirect),
        .if_id_ready              (if_id_ready),
        .imem_req_valid           (imem_req_valid),
        .imem_req_ready           (imem_req_ready),
        .imem_req_addr            (imem_req_addr),
        .imem_rsp_valid           (imem_rsp_valid),
        .imem_rsp_ready           (imem_rsp_ready),
        .imem_rsp_data            (imem_rsp_data),
        .imem_rsp_error           (imem_rsp_error),
        .if_id_candidate          (if_id_candidate),
        .fetch_response_available (fetch_response_available)
    );

    rv32_idu u_idu (
        .clk             (clk),
        .if_id_q         (if_id_q),
        .wb_bus          (wb_bus),
        .id_ex_candidate (id_ex_candidate)
    );

    assign execute_kill = trap_take || interrupt_take || mret_commit;

    rv32_execute_stage u_execute_stage (
        .clk                  (clk),
        .rst                  (rst),
        .id_ex_q              (id_ex_q),
        .rs1_forward_select   (rs1_forward_select),
        .rs2_forward_select   (rs2_forward_select),
        .ex_mem_forward_value (ex_mem_forward_value),
        .mem_wb_forward_value (mem_wb_forward_value),
        .id_ex_action         (id_ex_action),
        .ex_mem_action        (ex_mem_action),
        .execute_kill         (execute_kill),
        .ex_mem_active_candidate(ex_mem_active_candidate),
        .raw_redirect         (raw_redirect),
        .ex_hold_valid        (ex_hold_valid_q),
        .ex_multicycle_wait   (ex_multicycle_wait),
        .mdu_idle             (mdu_idle),
        .mdu_req_valid        (mdu_req_valid),
        .mdu_req_ready        (mdu_req_ready),
        .mdu_rsp_valid        (mdu_rsp_valid),
        .mdu_rsp_ready        (mdu_rsp_ready),
        .mdu_rsp_result       (mdu_rsp_result),
        .mdu_kill             (mdu_kill)
    );

    rv32_lsu u_lsu (
        .clk              (clk),
        .rst              (rst),
        .ex_mem_candidate (ex_mem_active_candidate),
        .ex_mem_q         (ex_mem_q),
        .ex_request_block (ex_request_block),
        .dmem_req_valid   (dmem_req_valid),
        .dmem_req_ready   (dmem_req_ready),
        .dmem_req_write   (dmem_req_write),
        .dmem_req_addr    (dmem_req_addr),
        .dmem_req_wdata   (dmem_req_wdata),
        .dmem_req_wstrb   (dmem_req_wstrb),
        .dmem_rsp_valid   (dmem_rsp_valid),
        .dmem_rsp_ready   (dmem_rsp_ready),
        .dmem_rsp_rdata   (dmem_rsp_rdata),
        .dmem_rsp_error   (dmem_rsp_error),
        .response_fire    (lsu_response_fire),
        .ex_request_wait  (ex_request_wait),
        .mem_response_wait(mem_response_wait),
        .lsu_outstanding  (lsu_outstanding),
        .load_result      (lsu_load_result),
        .lsu_exception    (lsu_exception)
    );

    assign mret_redirect.valid  = mret_commit;
    assign mret_redirect.target = mret_commit ? mret_target : 32'b0;

    assign csr_access_valid =
        ex_mem_q.valid &&
        ex_mem_q.csr_ctrl.valid &&
        !ex_mem_q.exception.valid;

    assign ex_request_block =
        mem_request_block || interrupt_take;

    assign commit_valid =
        mem_commit_candidate &&
        (mem_wb_action == PIPE_LOAD);

    rv32_mem_commit u_mem_commit (
        .rst                            (rst),
        .ex_mem_q                       (ex_mem_q),
        .lsu_response_fire              (lsu_response_fire),
        .lsu_load_result                (lsu_load_result),
        .lsu_exception                  (lsu_exception),
        .csr_access_illegal             (csr_access_illegal),
        .csr_read_data                  (csr_read_data),
        .mret_target                    (mret_target),
        .resume_pc                      (resume_pc_q),
        .mem_memory_access              (mem_memory_access),
        .mem_stage_complete             (mem_stage_complete),
        .final_mem_exception            (final_mem_exception),
        .mem_wb_candidate               (mem_wb_candidate),
        .mem_commit_candidate           (mem_commit_candidate),
        .mret_commit                    (mret_commit),
        .effective_architectural_next_pc(effective_architectural_next_pc),
        .boundary_resume_pc             (boundary_resume_pc),
        .mem_request_block              (mem_request_block)
    );

    assign pipeline_empty =
        !if_id_q.valid &&
        !id_ex_q.valid &&
        !ex_mem_q.valid &&
        !mem_wb_q.valid;

    assign empty_interrupt_boundary =
        pipeline_empty &&
        !lsu_outstanding &&
        mdu_idle;

    rv32_csr_trap #(
        .MTVEC_RESET (MTVEC_RESET)
    ) u_csr_trap (
        .clk                 (clk),
        .rst                 (rst),
        .irq_software        (irq_software),
        .irq_timer           (irq_timer),
        .irq_external        (irq_external),
        .mem_valid           (ex_mem_q.valid),
        .mem_pc              (ex_mem_q.pc),
        .mem_instruction     (ex_mem_q.instruction),
        .mem_response_wait   (mem_response_wait),
        .csr_access_valid    (csr_access_valid),
        .csr_address         (ex_mem_q.csr_address),
        .csr_operation       (ex_mem_csr_operation),
        .csr_source          (ex_mem_q.csr_source),
        .csr_read_enable     (ex_mem_csr_read_enable),
        .csr_write_enable    (ex_mem_csr_write_enable),
        .final_mem_exception (final_mem_exception),
        .mret_commit         (mret_commit),
        .mem_commit_candidate(mem_commit_candidate),
        .commit_valid        (commit_valid),
        .boundary_resume_pc  (boundary_resume_pc),
        .empty_interrupt_boundary(empty_interrupt_boundary),
        .csr_read_data       (csr_read_data),
        .csr_access_illegal  (csr_access_illegal),
        .mret_target         (mret_target),
        .trap_take           (trap_take),
        .trap_redirect       (trap_redirect),
        .post_commit_interrupt_take(post_commit_interrupt_take),
        .empty_interrupt_take(empty_interrupt_take),
        .interrupt_take      (interrupt_take),
        .interrupt_redirect  (interrupt_redirect),
        .trap_valid          (trap_valid),
        .trap_pc             (trap_pc),
        .trap_cause          (trap_cause),
        .trap_value          (trap_value)
    );

    // Hazard detection and global pipeline control
    rv32_forward_unit u_forward_unit (
        // Current ID-stage consumer for late-result detection
        .id_valid              (id_ex_candidate.valid),
        .id_rs1_addr           (id_ex_candidate.rs1_addr),
        .id_rs2_addr           (id_ex_candidate.rs2_addr),
        .id_uses_rs1           (id_ex_candidate.uses_rs1),
        .id_uses_rs2           (id_ex_candidate.uses_rs2),

        // Current EX-stage consumer
        .ex_valid              (id_ex_q.valid),
        .ex_rs1_addr           (id_ex_q.rs1_addr),
        .ex_rs2_addr           (id_ex_q.rs2_addr),
        .ex_uses_rs1           (id_ex_q.uses_rs1),
        .ex_uses_rs2           (id_ex_q.uses_rs2),
        .ex_rd_addr            (id_ex_q.rd_addr),
        .ex_result_late        (id_ex_result_late),

        // MEM- and WB-stage producers
        .ex_mem_valid          (ex_mem_q.valid),
        .ex_mem_rd_addr        (ex_mem_q.rd_addr),
        .ex_mem_register_write (ex_mem_register_write),
        .ex_mem_result_late    (ex_mem_result_late),
        .mem_wb_valid          (mem_wb_q.valid),
        .mem_wb_rd_addr        (mem_wb_q.rd_addr),
        .mem_wb_register_write (mem_wb_register_write),

        .rs1_forward_select    (rs1_forward_select),
        .rs2_forward_select    (rs2_forward_select),
        .late_result_hazard    (late_result_hazard)
    );

    rv32_pipeline_ctrl u_pipeline_ctrl (
        .rst                     (rst),
        .trap_take               (trap_take),
        .post_commit_interrupt_take(post_commit_interrupt_take),
        .empty_interrupt_take    (empty_interrupt_take),
        .mret_commit             (mret_commit),
        .mem_response_wait       (mem_response_wait),
        .ex_request_wait         (ex_request_wait),
        .ex_multicycle_wait      (ex_multicycle_wait),
        .raw_redirect_valid      (raw_redirect.valid),
        .late_result_hazard      (late_result_hazard),
        .fetch_response_available(fetch_response_available),
        .fetch_action            (fetch_action),
        .if_id_action            (if_id_action),
        .id_ex_action            (id_ex_action),
        .ex_mem_action           (ex_mem_action),
        .mem_wb_action           (mem_wb_action),
        .redirect_commit         (redirect_commit)
    );

    // Pipeline next-state selection
    // Select the final next state of each pipeline register:
    //   PIPE_LOAD  - accept the new candidate
    //   PIPE_HOLD  - preserve the current registered state
    //   PIPE_CLEAR - invalidate the pipeline entry and insert a bubble
    always_comb begin
        if_id_d  = if_id_q;
        id_ex_d  = id_ex_q;
        ex_mem_d = ex_mem_q;
        mem_wb_d = mem_wb_q;

        case (if_id_action)
            PIPE_LOAD:  if_id_d       = if_id_candidate;
            PIPE_HOLD:  if_id_d       = if_id_q;
            PIPE_CLEAR: if_id_d.valid = 1'b0;
            default:    if_id_d       = if_id_q;
        endcase

        case (id_ex_action)
            PIPE_LOAD:  id_ex_d       = id_ex_candidate;
            PIPE_HOLD:  id_ex_d       = id_ex_q;
            PIPE_CLEAR: id_ex_d.valid = 1'b0;
            default:    id_ex_d       = id_ex_q;
        endcase

        case (ex_mem_action)
            PIPE_LOAD:  ex_mem_d       = ex_mem_active_candidate;
            PIPE_HOLD:  ex_mem_d       = ex_mem_q;
            PIPE_CLEAR: ex_mem_d.valid = 1'b0;
            default:    ex_mem_d       = ex_mem_q;
        endcase

        case (mem_wb_action)
            PIPE_LOAD:  mem_wb_d       = mem_wb_candidate;
            PIPE_HOLD:  mem_wb_d       = mem_wb_q;
            PIPE_CLEAR: mem_wb_d.valid = 1'b0;
            default:    mem_wb_d       = mem_wb_q;
        endcase
    end

    always_comb begin
        resume_pc_d = resume_pc_q;

        if (trap_take) begin
            resume_pc_d = trap_redirect.target;
        end else if (interrupt_take) begin
            resume_pc_d = interrupt_redirect.target;
        end else if (mret_commit) begin
            resume_pc_d = mret_target;
        end else if (mem_commit_candidate) begin
            resume_pc_d = effective_architectural_next_pc;
        end
    end

    // Pipeline state registers
    always_ff @(posedge clk) begin
        if (rst) begin
            if_id_q.valid  <= 1'b0;
            id_ex_q.valid  <= 1'b0;
            ex_mem_q.valid <= 1'b0;
            mem_wb_q.valid <= 1'b0;

            resume_pc_q         <= RESET_VECTOR;
        end else begin
            if_id_q  <= if_id_d;
            id_ex_q  <= id_ex_d;
            ex_mem_q <= ex_mem_d;
            mem_wb_q <= mem_wb_d;
            resume_pc_q <= resume_pc_d;

        end
    end
endmodule
