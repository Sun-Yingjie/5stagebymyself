module rv32_exu (
    input  logic                         clk,
    input  logic                         rst,

    input  rv32_pkg::id_ex_t             id_ex_q,
    input  rv32_pkg::forward_select_e    rs1_forward_select,
    input  rv32_pkg::forward_select_e    rs2_forward_select,
    // Registered EX/MEM producer packet used to form the forwarding value.
    input  rv32_pkg::ex_mem_t            ex_mem_q,
    input  logic [31:0]                  mem_wb_forward_data,

    input  rv32_pkg::pipe_action_e       id_ex_action,
    // PIPE_LOAD indicates that EX/MEM can accept an MDU response.
    input  rv32_pkg::pipe_action_e       ex_mem_action,
    input  logic                         execute_kill,

    output rv32_pkg::ex_mem_t            ex_mem_candidate,
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

    logic [31:0]    ex_mem_forward_data;
    logic [31:0]    rs1_exec;
    logic [31:0]    rs2_exec;
    logic [31:0]    alu_operand_a;
    logic [31:0]    alu_operand_b;
    logic [31:0]    alu_result;
    logic           branch_taken;
    logic           control_transfer_taken;
    logic           instruction_address_misaligned;
    logic           data_address_misaligned;
    logic [31:0]    redirect_target;
    logic [31:0]    csr_source;
    alu_operation_e    alu_operation;
    branch_operation_e branch_operation;

    ex_mem_t        ex_mem_single_cycle_candidate;
    ex_mem_t        ex_mem_live_candidate;
    ex_mem_t        ex_mem_hold_q;
    redirect_t      single_cycle_redirect;
    redirect_t      ex_redirect_hold_q;
    logic           ex_hold_valid_q;

    logic           m_ex_valid;
    mdu_operation_e mdu_req_operation;

    // The forwarding unit chooses the producer. The EXU resolves both operands
    // once so the ALU, branch comparator, and MDU observe identical values.
    always_comb begin
        ex_mem_forward_data = '0;

        case (ex_mem_q.wb_ctrl.writeback_select)
            WB_EXEC: begin
                ex_mem_forward_data = ex_mem_q.exec_result;
            end

            WB_PC_PLUS_4: begin
                ex_mem_forward_data = ex_mem_q.pc_plus_4;
            end

            default: begin
                ex_mem_forward_data = '0;
            end
        endcase
    end

    always_comb begin
        case (rs1_forward_select)
            FWD_REG:    rs1_exec = id_ex_q.rs1_data;
            FWD_EX_MEM: rs1_exec = ex_mem_forward_data;
            FWD_MEM_WB: rs1_exec = mem_wb_forward_data;
            default:    rs1_exec = id_ex_q.rs1_data;
        endcase
    end

    always_comb begin
        case (rs2_forward_select)
            FWD_REG:    rs2_exec = id_ex_q.rs2_data;
            FWD_EX_MEM: rs2_exec = ex_mem_forward_data;
            FWD_MEM_WB: rs2_exec = mem_wb_forward_data;
            default:    rs2_exec = id_ex_q.rs2_data;
        endcase
    end

    assign alu_operation =
        alu_operation_e'(id_ex_q.ex_ctrl.alu_operation);

    assign branch_operation =
        branch_operation_e'(id_ex_q.ex_ctrl.branch_operation);

    always_comb begin
        case (id_ex_q.ex_ctrl.operand_a_select)
            OPA_RS1:  alu_operand_a = rs1_exec;
            OPA_PC:   alu_operand_a = id_ex_q.pc;
            OPA_ZERO: alu_operand_a = '0;
            default:  alu_operand_a = rs1_exec;
        endcase
    end

    always_comb begin
        case (id_ex_q.ex_ctrl.operand_b_select)
            OPB_RS2:      alu_operand_b = rs2_exec;
            OPB_IMMEDIATE: alu_operand_b = id_ex_q.immediate;
            default:       alu_operand_b = rs2_exec;
        endcase
    end

    rv32_alu u_alu (
        .operand_a     (alu_operand_a),
        .operand_b     (alu_operand_b),
        .alu_operation (alu_operation),
        .result        (alu_result)
    );

    rv32_branch_compare u_branch_compare (
        .operand_a        (rs1_exec),
        .operand_b        (rs2_exec),
        .branch_operation (branch_operation),
        .branch_taken     (branch_taken)
    );

    always_comb begin
        csr_source = 32'b0;

        if (id_ex_q.csr_ctrl.valid) begin
            if (id_ex_q.csr_ctrl.use_immediate) begin
                csr_source = {27'b0, id_ex_q.instruction[19:15]};
            end else begin
                csr_source = rs1_exec;
            end
        end
    end

    always_comb begin
        if (id_ex_q.ex_ctrl.is_jalr) begin
            redirect_target = {alu_result[31:1], 1'b0};
        end else begin
            redirect_target = alu_result;
        end

        control_transfer_taken =
            id_ex_q.valid &&
            (
                id_ex_q.ex_ctrl.is_jump ||
                branch_taken
            );

        instruction_address_misaligned =
            control_transfer_taken &&
            (redirect_target[1:0] != 2'b00);

        data_address_misaligned = 1'b0;
        if (
            id_ex_q.valid &&
            (
                id_ex_q.mem_ctrl.memory_read ||
                id_ex_q.mem_ctrl.memory_write
            )
        ) begin
            case (id_ex_q.mem_ctrl.memory_size)
                MEM_SIZE_BYTE: begin
                    data_address_misaligned = 1'b0;
                end

                MEM_SIZE_HALF: begin
                    data_address_misaligned = alu_result[0];
                end

                MEM_SIZE_WORD: begin
                    data_address_misaligned = |alu_result[1:0];
                end

                default: begin
                    data_address_misaligned = 1'b0;
                end
            endcase
        end
    end

    always_comb begin
        ex_mem_single_cycle_candidate = '0;
        ex_mem_single_cycle_candidate.valid = id_ex_q.valid;
        ex_mem_single_cycle_candidate.pc = id_ex_q.pc;
        ex_mem_single_cycle_candidate.instruction = id_ex_q.instruction;
        ex_mem_single_cycle_candidate.pc_plus_4 = id_ex_q.pc_plus_4;
        ex_mem_single_cycle_candidate.architectural_next_pc =
            control_transfer_taken ? redirect_target : id_ex_q.pc_plus_4;
        ex_mem_single_cycle_candidate.exec_result = alu_result;
        ex_mem_single_cycle_candidate.store_data = rs2_exec;
        ex_mem_single_cycle_candidate.csr_ctrl = id_ex_q.csr_ctrl;
        ex_mem_single_cycle_candidate.csr_address = id_ex_q.csr_address;
        ex_mem_single_cycle_candidate.csr_source = csr_source;
        ex_mem_single_cycle_candidate.rd_addr = id_ex_q.rd_addr;
        ex_mem_single_cycle_candidate.mem_ctrl = id_ex_q.mem_ctrl;
        ex_mem_single_cycle_candidate.wb_ctrl = id_ex_q.wb_ctrl;
        ex_mem_single_cycle_candidate.exception = id_ex_q.exception;
        ex_mem_single_cycle_candidate.mret = id_ex_q.mret;

        if (id_ex_q.valid && !id_ex_q.exception.valid) begin
            if (instruction_address_misaligned) begin
                ex_mem_single_cycle_candidate.exception.valid = 1'b1;
                ex_mem_single_cycle_candidate.exception.cause =
                    EXCEPTION_CAUSE_INSTRUCTION_ADDRESS_MISALIGNED;
                ex_mem_single_cycle_candidate.exception.value =
                    redirect_target;
            end else if (data_address_misaligned) begin
                ex_mem_single_cycle_candidate.exception.valid = 1'b1;
                ex_mem_single_cycle_candidate.exception.value = alu_result;

                if (id_ex_q.mem_ctrl.memory_read) begin
                    ex_mem_single_cycle_candidate.exception.cause =
                        EXCEPTION_CAUSE_LOAD_ADDRESS_MISALIGNED;
                end else begin
                    ex_mem_single_cycle_candidate.exception.cause =
                        EXCEPTION_CAUSE_STORE_ADDRESS_MISALIGNED;
                end
            end
        end

        if (ex_mem_single_cycle_candidate.exception.valid) begin
            ex_mem_single_cycle_candidate.mret = 1'b0;
            ex_mem_single_cycle_candidate.csr_ctrl = '0;
            ex_mem_single_cycle_candidate.csr_source = 32'b0;
            ex_mem_single_cycle_candidate.mem_ctrl = '0;
            ex_mem_single_cycle_candidate.wb_ctrl = '0;
        end
    end

    always_comb begin
        single_cycle_redirect = '0;
        single_cycle_redirect.valid =
            control_transfer_taken &&
            !ex_mem_single_cycle_candidate.exception.valid;
        single_cycle_redirect.target = redirect_target;
    end

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
        ex_mem_live_candidate = ex_mem_single_cycle_candidate;

        if (id_ex_q.mdu_ctrl.valid) begin
            ex_mem_live_candidate.valid       = m_ex_valid && mdu_rsp_valid;
            ex_mem_live_candidate.exec_result = mdu_rsp_result;
        end
    end

    // A non-M instruction can remain in ID/EX after its forwarding producers
    // have advanced. Preserve the first post-forwarding packet and redirect
    // until pipeline control releases ID/EX.
    always_comb begin
        ex_mem_candidate = ex_mem_live_candidate;

        if (ex_hold_valid_q) begin
            ex_mem_candidate = ex_mem_hold_q;
        end
    end

    assign raw_redirect =
        ex_hold_valid_q ? ex_redirect_hold_q : single_cycle_redirect;
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
                ex_mem_hold_q      <= ex_mem_live_candidate;
                ex_redirect_hold_q <= single_cycle_redirect;
            end else if (id_ex_action != PIPE_HOLD) begin
                ex_hold_valid_q <= 1'b0;
            end
        end
    end

endmodule
