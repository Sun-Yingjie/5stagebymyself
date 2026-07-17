module rv32_decoder(
    input logic [31:0]              instruction,
    output rv32_pkg::decode_ctrl_t  decode_ctrl
);

    import rv32_pkg::*;

    always_comb begin
        decode_ctrl = '0;

        decode_ctrl.immediate_type = IMM_NONE;
        decode_ctrl.illegal_instruction = 1'b1;

        decode_ctrl.ex_ctrl.operand_a_select = OPA_RS1;
        decode_ctrl.ex_ctrl.operand_b_select = OPB_RS2;
        decode_ctrl.ex_ctrl.alu_operation = ALU_ADD;
        decode_ctrl.ex_ctrl.branch_operation = BR_NONE;

        decode_ctrl.mem_ctrl.memory_size = MEM_SIZE_WORD;

        decode_ctrl.wb_ctrl.writeback_select = WB_EXEC;
        case (instruction[6:0])
            OPCODE_LUI: begin
                decode_ctrl.illegal_instruction = 1'b0;
                decode_ctrl.immediate_type = IMM_U;

                decode_ctrl.ex_ctrl.operand_a_select = OPA_ZERO;
                decode_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;

                decode_ctrl.wb_ctrl.register_write = 1'b1;
            end

            OPCODE_AUIPC: begin
                decode_ctrl.illegal_instruction = 1'b0;
                decode_ctrl.immediate_type = IMM_U;

                decode_ctrl.ex_ctrl.operand_a_select = OPA_PC;
                decode_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;

                decode_ctrl.wb_ctrl.register_write = 1'b1;
            end

            OPCODE_JAL: begin
                decode_ctrl.illegal_instruction = 1'b0;
                decode_ctrl.immediate_type = IMM_J;

                decode_ctrl.ex_ctrl.operand_a_select = OPA_PC;
                decode_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
                decode_ctrl.ex_ctrl.is_jump = 1'b1;

                decode_ctrl.wb_ctrl.register_write = 1'b1;
                decode_ctrl.wb_ctrl.writeback_select = WB_PC_PLUS_4;
            end

            OPCODE_JALR: begin
                if (instruction[14:12] == FUNCT3_JALR) begin
                    decode_ctrl.illegal_instruction = 1'b0;
                    decode_ctrl.uses_rs1 = 1'b1;
                    decode_ctrl.immediate_type = IMM_I;

                    decode_ctrl.ex_ctrl.operand_a_select = OPA_RS1;
                    decode_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
                    decode_ctrl.ex_ctrl.is_jump = 1'b1;
                    decode_ctrl.ex_ctrl.is_jalr = 1'b1;

                    decode_ctrl.wb_ctrl.register_write = 1'b1;
                    decode_ctrl.wb_ctrl.writeback_select = WB_PC_PLUS_4;
                end
            end

            OPCODE_BRANCH: begin
                decode_ctrl.uses_rs1 = 1'b1;
                decode_ctrl.uses_rs2 = 1'b1;
                decode_ctrl.immediate_type = IMM_B;

                decode_ctrl.ex_ctrl.operand_a_select = OPA_PC;
                decode_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;

                case (instruction[14:12])
                    FUNCT3_BEQ: begin
                        decode_ctrl.illegal_instruction = 1'b0;
                        decode_ctrl.ex_ctrl.branch_operation = BR_EQ;
                    end

                    FUNCT3_BNE: begin
                        decode_ctrl.illegal_instruction = 1'b0;
                        decode_ctrl.ex_ctrl.branch_operation = BR_NE;
                    end

                    FUNCT3_BLT: begin
                        decode_ctrl.illegal_instruction = 1'b0;
                        decode_ctrl.ex_ctrl.branch_operation = BR_LT;
                    end

                    FUNCT3_BGE: begin
                        decode_ctrl.illegal_instruction = 1'b0;
                        decode_ctrl.ex_ctrl.branch_operation = BR_GE;
                    end

                    FUNCT3_BLTU: begin
                        decode_ctrl.illegal_instruction = 1'b0;
                        decode_ctrl.ex_ctrl.branch_operation = BR_LTU;
                    end

                    FUNCT3_BGEU: begin
                        decode_ctrl.illegal_instruction = 1'b0;
                        decode_ctrl.ex_ctrl.branch_operation = BR_GEU;
                    end

                    default: begin
                        decode_ctrl.illegal_instruction = 1'b1;
                    end
                endcase
            end

            OPCODE_LOAD: begin
                case (instruction[14:12])
                    FUNCT3_LB: begin
                        decode_ctrl.illegal_instruction = 1'b0;
                        decode_ctrl.mem_ctrl.memory_size = MEM_SIZE_BYTE;
                    end

                    FUNCT3_LH: begin
                        decode_ctrl.illegal_instruction = 1'b0;
                        decode_ctrl.mem_ctrl.memory_size = MEM_SIZE_HALF;
                    end

                    FUNCT3_LW: begin
                        decode_ctrl.illegal_instruction = 1'b0;
                        decode_ctrl.mem_ctrl.memory_size = MEM_SIZE_WORD;
                    end

                    FUNCT3_LBU: begin
                        decode_ctrl.illegal_instruction = 1'b0;
                        decode_ctrl.mem_ctrl.memory_size = MEM_SIZE_BYTE;
                        decode_ctrl.mem_ctrl.load_unsigned = 1'b1;
                    end

                    FUNCT3_LHU: begin
                        decode_ctrl.illegal_instruction = 1'b0;
                        decode_ctrl.mem_ctrl.memory_size = MEM_SIZE_HALF;
                        decode_ctrl.mem_ctrl.load_unsigned = 1'b1;
                    end

                    default: begin
                        decode_ctrl.illegal_instruction = 1'b1;
                    end
                endcase

                if (!decode_ctrl.illegal_instruction) begin
                    decode_ctrl.uses_rs1 = 1'b1;
                    decode_ctrl.immediate_type = IMM_I;

                    decode_ctrl.ex_ctrl.operand_a_select = OPA_RS1;
                    decode_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;

                    decode_ctrl.mem_ctrl.memory_read = 1'b1;

                    decode_ctrl.wb_ctrl.register_write = 1'b1;
                    decode_ctrl.wb_ctrl.writeback_select = WB_LOAD;
                end
            end

            OPCODE_STORE: begin
                case (instruction[14:12])
                    FUNCT3_SB: begin
                        decode_ctrl.illegal_instruction = 1'b0;
                        decode_ctrl.mem_ctrl.memory_size = MEM_SIZE_BYTE;
                    end

                    FUNCT3_SH: begin
                        decode_ctrl.illegal_instruction = 1'b0;
                        decode_ctrl.mem_ctrl.memory_size = MEM_SIZE_HALF;
                    end

                    FUNCT3_SW: begin
                        decode_ctrl.illegal_instruction = 1'b0;
                        decode_ctrl.mem_ctrl.memory_size = MEM_SIZE_WORD;
                    end

                    default: begin
                        decode_ctrl.illegal_instruction = 1'b1;
                    end
                endcase

                if (!decode_ctrl.illegal_instruction) begin
                    decode_ctrl.uses_rs1 = 1'b1;
                    decode_ctrl.uses_rs2 = 1'b1;
                    decode_ctrl.immediate_type = IMM_S;

                    decode_ctrl.ex_ctrl.operand_a_select = OPA_RS1;
                    decode_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;

                    decode_ctrl.mem_ctrl.memory_write = 1'b1;
                end
            end

            OPCODE_MISC_MEM: begin
                if (instruction[14:12] == FUNCT3_FENCE) begin
                    // This in-order, blocking memory system already provides
                    // conservative FENCE ordering. Keep the instruction valid
                    // for retirement, but add no architectural side effects.
                    // This implementation conservatively treats every
                    // fm/pred/succ combination as a full fence; base RV32I
                    // also requires rs1/rd and reserved configurations to be
                    // accepted rather than decoded as illegal.
                    decode_ctrl.illegal_instruction = 1'b0;
                    decode_ctrl.ex_ctrl.operand_a_select = OPA_ZERO;
                    decode_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
                end
            end

            OPCODE_SYSTEM: begin
                case (instruction)
                    INSTRUCTION_ECALL: begin
                        decode_ctrl.illegal_instruction = 1'b0;
                        decode_ctrl.environment_call = 1'b1;
                    end

                    INSTRUCTION_EBREAK: begin
                        decode_ctrl.illegal_instruction = 1'b0;
                        decode_ctrl.breakpoint = 1'b1;
                    end

                    default: begin
                        // Zicsr and privileged SYSTEM instructions are added
                        // by later, independently verified increments.
                        decode_ctrl.illegal_instruction = 1'b1;
                    end
                endcase
            end

            OPCODE_OP_IMM: begin
                case (instruction[14:12])
                    FUNCT3_ADD_SUB: begin
                        decode_ctrl.illegal_instruction = 1'b0;
                        decode_ctrl.ex_ctrl.alu_operation = ALU_ADD;
                    end

                    FUNCT3_SLL: begin
                        if (instruction[31:25] == FUNCT7_BASE) begin
                            decode_ctrl.illegal_instruction = 1'b0;
                            decode_ctrl.ex_ctrl.alu_operation = ALU_SLL;
                        end
                    end

                    FUNCT3_SLT: begin
                        decode_ctrl.illegal_instruction = 1'b0;
                        decode_ctrl.ex_ctrl.alu_operation = ALU_SLT;
                    end

                    FUNCT3_SLTU: begin
                        decode_ctrl.illegal_instruction = 1'b0;
                        decode_ctrl.ex_ctrl.alu_operation = ALU_SLTU;
                    end

                    FUNCT3_XOR: begin
                        decode_ctrl.illegal_instruction = 1'b0;
                        decode_ctrl.ex_ctrl.alu_operation = ALU_XOR;
                    end

                    FUNCT3_SRL_SRA: begin
                        case (instruction[31:25])
                            FUNCT7_BASE: begin
                                decode_ctrl.illegal_instruction = 1'b0;
                                decode_ctrl.ex_ctrl.alu_operation = ALU_SRL;
                            end

                            FUNCT7_SUB_SRA: begin
                                decode_ctrl.illegal_instruction = 1'b0;
                                decode_ctrl.ex_ctrl.alu_operation = ALU_SRA;
                            end

                            default: begin
                                decode_ctrl.illegal_instruction = 1'b1;
                            end
                        endcase
                    end

                    FUNCT3_OR: begin
                        decode_ctrl.illegal_instruction = 1'b0;
                        decode_ctrl.ex_ctrl.alu_operation = ALU_OR;
                    end

                    FUNCT3_AND: begin
                        decode_ctrl.illegal_instruction = 1'b0;
                        decode_ctrl.ex_ctrl.alu_operation = ALU_AND;
                    end

                    default: begin
                        decode_ctrl.illegal_instruction = 1'b1;
                    end
                endcase

                if (!decode_ctrl.illegal_instruction) begin
                    decode_ctrl.uses_rs1 = 1'b1;
                    decode_ctrl.immediate_type = IMM_I;

                    decode_ctrl.ex_ctrl.operand_a_select = OPA_RS1;
                    decode_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;

                    decode_ctrl.wb_ctrl.register_write = 1'b1;
                    decode_ctrl.wb_ctrl.writeback_select = WB_EXEC;
                end
            end

            OPCODE_OP: begin
                case (instruction[14:12])
                    FUNCT3_ADD_SUB: begin
                        case (instruction[31:25])
                            FUNCT7_BASE: begin
                                decode_ctrl.illegal_instruction = 1'b0;
                                decode_ctrl.ex_ctrl.alu_operation = ALU_ADD;
                            end

                            FUNCT7_SUB_SRA: begin
                                decode_ctrl.illegal_instruction = 1'b0;
                                decode_ctrl.ex_ctrl.alu_operation = ALU_SUB;
                            end

                            default: begin
                                decode_ctrl.illegal_instruction = 1'b1;
                            end
                        endcase
                    end

                    FUNCT3_SLL: begin
                        if (instruction[31:25] == FUNCT7_BASE) begin
                            decode_ctrl.illegal_instruction = 1'b0;
                            decode_ctrl.ex_ctrl.alu_operation = ALU_SLL;
                        end
                    end

                    FUNCT3_SLT: begin
                        if (instruction[31:25] == FUNCT7_BASE) begin
                            decode_ctrl.illegal_instruction = 1'b0;
                            decode_ctrl.ex_ctrl.alu_operation = ALU_SLT;
                        end
                    end

                    FUNCT3_SLTU: begin
                        if (instruction[31:25] == FUNCT7_BASE) begin
                            decode_ctrl.illegal_instruction = 1'b0;
                            decode_ctrl.ex_ctrl.alu_operation = ALU_SLTU;
                        end
                    end

                    FUNCT3_XOR: begin
                        if (instruction[31:25] == FUNCT7_BASE) begin
                            decode_ctrl.illegal_instruction = 1'b0;
                            decode_ctrl.ex_ctrl.alu_operation = ALU_XOR;
                        end
                    end

                    FUNCT3_SRL_SRA: begin
                        case (instruction[31:25])
                            FUNCT7_BASE: begin
                                decode_ctrl.illegal_instruction = 1'b0;
                                decode_ctrl.ex_ctrl.alu_operation = ALU_SRL;
                            end

                            FUNCT7_SUB_SRA: begin
                                decode_ctrl.illegal_instruction = 1'b0;
                                decode_ctrl.ex_ctrl.alu_operation = ALU_SRA;
                            end

                            default: begin
                                decode_ctrl.illegal_instruction = 1'b1;
                            end
                        endcase
                    end

                    FUNCT3_OR: begin
                        if (instruction[31:25] == FUNCT7_BASE) begin
                            decode_ctrl.illegal_instruction = 1'b0;
                            decode_ctrl.ex_ctrl.alu_operation = ALU_OR;
                        end
                    end

                    FUNCT3_AND: begin
                        if (instruction[31:25] == FUNCT7_BASE) begin
                            decode_ctrl.illegal_instruction = 1'b0;
                            decode_ctrl.ex_ctrl.alu_operation = ALU_AND;
                        end
                    end

                    default: begin
                        decode_ctrl.illegal_instruction = 1'b1;
                    end
                endcase

                if (!decode_ctrl.illegal_instruction) begin
                    decode_ctrl.uses_rs1 = 1'b1;
                    decode_ctrl.uses_rs2 = 1'b1;

                    decode_ctrl.ex_ctrl.operand_a_select = OPA_RS1;
                    decode_ctrl.ex_ctrl.operand_b_select = OPB_RS2;

                    decode_ctrl.wb_ctrl.register_write = 1'b1;
                    decode_ctrl.wb_ctrl.writeback_select = WB_EXEC;
                end
            end

            default: begin
                decode_ctrl.illegal_instruction = 1'b1;
            end
        endcase
    end
endmodule
