module rv32_exu (
    input rv32_pkg::id_ex_t id_ex_q,
    input rv32_pkg::forward_select_e rs1_forward_select,
    input rv32_pkg::forward_select_e rs2_forward_select,
    input logic [31:0] ex_mem_forward_value,
    input logic [31:0] mem_wb_forward_value,
    output rv32_pkg::ex_mem_t ex_mem_candidate,
    output rv32_pkg::redirect_t raw_redirect
);
    import rv32_pkg::*;

    logic [31:0] rs1_exec;
    logic [31:0] rs2_exec;
    logic [31:0] alu_operand_a;
    logic [31:0] alu_operand_b;
    logic [31:0] alu_result;
    logic branch_taken;
    logic control_transfer_taken;
    logic instruction_address_misaligned;
    logic data_address_misaligned;
    logic [31:0] redirect_target;
    alu_operation_e    alu_operation;
    branch_operation_e branch_operation;

assign alu_operation =
    alu_operation_e'(id_ex_q.ex_ctrl.alu_operation);

assign branch_operation =
    branch_operation_e'(id_ex_q.ex_ctrl.branch_operation);

    always_comb begin
        case (rs1_forward_select)
            FWD_REG: rs1_exec = id_ex_q.rs1_data;
            FWD_EX_MEM: rs1_exec = ex_mem_forward_value;
            FWD_MEM_WB: rs1_exec = mem_wb_forward_value;
            default: rs1_exec = id_ex_q.rs1_data;
        endcase
    end

    always_comb begin
        case (rs2_forward_select)
            FWD_REG: rs2_exec = id_ex_q.rs2_data;
            FWD_EX_MEM: rs2_exec = ex_mem_forward_value;
            FWD_MEM_WB: rs2_exec = mem_wb_forward_value;
            default: rs2_exec = id_ex_q.rs2_data;
        endcase
    end

    always_comb begin
        case (id_ex_q.ex_ctrl.operand_a_select)
            OPA_RS1: alu_operand_a = rs1_exec;
            OPA_PC: alu_operand_a = id_ex_q.pc;
            OPA_ZERO: alu_operand_a = '0;
            default: alu_operand_a = rs1_exec;
        endcase
    end

    always_comb begin
        case (id_ex_q.ex_ctrl.operand_b_select)
            OPB_RS2: alu_operand_b = rs2_exec;
            OPB_IMMEDIATE: alu_operand_b = id_ex_q.immediate;
            default: alu_operand_b = rs2_exec;
        endcase
    end

    rv32_alu u_alu (
        .operand_a(alu_operand_a),
        .operand_b(alu_operand_b),
        .alu_operation(alu_operation),
        .result(alu_result)
    );

    rv32_branch_compare u_branch_compare (
        .operand_a(rs1_exec),
        .operand_b(rs2_exec),
        .branch_operation(branch_operation),
        .branch_taken(branch_taken)
    );

    always_comb begin
        if (id_ex_q.ex_ctrl.is_jalr) begin
            redirect_target = {alu_result[31:1], 1'b0};
        end
        else begin
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
        ex_mem_candidate = '0;
        ex_mem_candidate.valid = id_ex_q.valid;
        ex_mem_candidate.pc = id_ex_q.pc;
        ex_mem_candidate.instruction = id_ex_q.instruction;
        ex_mem_candidate.pc_plus_4 = id_ex_q.pc_plus_4;
        ex_mem_candidate.exec_result = alu_result;
        ex_mem_candidate.store_data = rs2_exec;
        ex_mem_candidate.rd_addr = id_ex_q.rd_addr;
        ex_mem_candidate.mem_ctrl = id_ex_q.mem_ctrl;
        ex_mem_candidate.wb_ctrl = id_ex_q.wb_ctrl;
        ex_mem_candidate.exception = id_ex_q.exception;

        if (id_ex_q.valid && !id_ex_q.exception.valid) begin
            if (instruction_address_misaligned) begin
                ex_mem_candidate.exception.valid = 1'b1;
                ex_mem_candidate.exception.cause =
                    EXCEPTION_CAUSE_INSTRUCTION_ADDRESS_MISALIGNED;
                ex_mem_candidate.exception.value = redirect_target;
            end
            else if (data_address_misaligned) begin
                ex_mem_candidate.exception.valid = 1'b1;
                ex_mem_candidate.exception.value = alu_result;

                if (id_ex_q.mem_ctrl.memory_read) begin
                    ex_mem_candidate.exception.cause =
                        EXCEPTION_CAUSE_LOAD_ADDRESS_MISALIGNED;
                end
                else begin
                    ex_mem_candidate.exception.cause =
                        EXCEPTION_CAUSE_STORE_ADDRESS_MISALIGNED;
                end
            end
        end

        if (ex_mem_candidate.exception.valid) begin
            ex_mem_candidate.mem_ctrl = '0;
            ex_mem_candidate.wb_ctrl = '0;
        end
    end
    always_comb begin
        raw_redirect = '0;

        raw_redirect.valid =
            control_transfer_taken &&
            !ex_mem_candidate.exception.valid;
        raw_redirect.target = redirect_target;
    end
endmodule
