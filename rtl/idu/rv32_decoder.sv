module rv32_decoder (
    input  logic [31:0]             instruction,
    output rv32_pkg::decode_ctrl_t  decode_ctrl
);

    import rv32_pkg::*;

    // Name the ISA fields once so the decode tree reads like the encoding
    // tables instead of repeating raw instruction bit slices.
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [4:0] rs1_or_zimm;
    logic [4:0] rd_addr;

    logic instruction_legal;
    logic subdecode_legal;

    assign opcode      = instruction[6:0];
    assign funct3      = instruction[14:12];
    assign funct7      = instruction[31:25];
    assign rs1_or_zimm = instruction[19:15];
    assign rd_addr     = instruction[11:7];

    always_comb begin
        // Canonical inactive controls. A decode leaf only enables the state
        // changes that belong to a recognized instruction encoding.
        decode_ctrl = '0;

        decode_ctrl.immediate_type = IMM_NONE;

        decode_ctrl.ex_ctrl.operand_a_select = OPA_RS1;
        decode_ctrl.ex_ctrl.operand_b_select = OPB_RS2;
        decode_ctrl.ex_ctrl.alu_operation = ALU_ADD;
        decode_ctrl.ex_ctrl.branch_operation = BR_NONE;

        decode_ctrl.mem_ctrl.memory_size = MEM_SIZE_WORD;

        decode_ctrl.wb_ctrl.writeback_select = WB_EXEC;

        instruction_legal = 1'b0;
        subdecode_legal   = 1'b0;

        case (opcode)
            // -----------------------------------------------------------------
            // Upper-immediate instructions
            // -----------------------------------------------------------------
            OPCODE_LUI: begin
                instruction_legal = 1'b1;
                decode_ctrl.immediate_type = IMM_U;

                decode_ctrl.ex_ctrl.operand_a_select = OPA_ZERO;
                decode_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;

                decode_ctrl.wb_ctrl.register_write = 1'b1;
            end

            OPCODE_AUIPC: begin
                instruction_legal = 1'b1;
                decode_ctrl.immediate_type = IMM_U;

                decode_ctrl.ex_ctrl.operand_a_select = OPA_PC;
                decode_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;

                decode_ctrl.wb_ctrl.register_write = 1'b1;
            end

            // -----------------------------------------------------------------
            // Control-flow instructions
            // -----------------------------------------------------------------
            OPCODE_JAL: begin
                instruction_legal = 1'b1;
                decode_ctrl.immediate_type = IMM_J;

                decode_ctrl.ex_ctrl.operand_a_select = OPA_PC;
                decode_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
                decode_ctrl.ex_ctrl.is_jump = 1'b1;

                decode_ctrl.wb_ctrl.register_write = 1'b1;
                decode_ctrl.wb_ctrl.writeback_select = WB_PC_PLUS_4;
            end

            OPCODE_JALR: begin
                if (funct3 == FUNCT3_JALR) begin
                    instruction_legal = 1'b1;
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
                subdecode_legal = 1'b1;

                case (funct3)
                    FUNCT3_BEQ:
                        decode_ctrl.ex_ctrl.branch_operation = BR_EQ;

                    FUNCT3_BNE:
                        decode_ctrl.ex_ctrl.branch_operation = BR_NE;

                    FUNCT3_BLT:
                        decode_ctrl.ex_ctrl.branch_operation = BR_LT;

                    FUNCT3_BGE:
                        decode_ctrl.ex_ctrl.branch_operation = BR_GE;

                    FUNCT3_BLTU:
                        decode_ctrl.ex_ctrl.branch_operation = BR_LTU;

                    FUNCT3_BGEU:
                        decode_ctrl.ex_ctrl.branch_operation = BR_GEU;

                    default:
                        subdecode_legal = 1'b0;
                endcase

                if (subdecode_legal) begin
                    instruction_legal = 1'b1;
                    decode_ctrl.uses_rs1 = 1'b1;
                    decode_ctrl.uses_rs2 = 1'b1;
                    decode_ctrl.immediate_type = IMM_B;

                    decode_ctrl.ex_ctrl.operand_a_select = OPA_PC;
                    decode_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
                end
            end

            // -----------------------------------------------------------------
            // Memory instructions
            // -----------------------------------------------------------------
            OPCODE_LOAD: begin
                subdecode_legal = 1'b1;

                case (funct3)
                    FUNCT3_LB:
                        decode_ctrl.mem_ctrl.memory_size = MEM_SIZE_BYTE;

                    FUNCT3_LH:
                        decode_ctrl.mem_ctrl.memory_size = MEM_SIZE_HALF;

                    FUNCT3_LW:
                        decode_ctrl.mem_ctrl.memory_size = MEM_SIZE_WORD;

                    FUNCT3_LBU: begin
                        decode_ctrl.mem_ctrl.memory_size = MEM_SIZE_BYTE;
                        decode_ctrl.mem_ctrl.load_unsigned = 1'b1;
                    end

                    FUNCT3_LHU: begin
                        decode_ctrl.mem_ctrl.memory_size = MEM_SIZE_HALF;
                        decode_ctrl.mem_ctrl.load_unsigned = 1'b1;
                    end

                    default:
                        subdecode_legal = 1'b0;
                endcase

                if (subdecode_legal) begin
                    instruction_legal = 1'b1;
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
                subdecode_legal = 1'b1;

                case (funct3)
                    FUNCT3_SB:
                        decode_ctrl.mem_ctrl.memory_size = MEM_SIZE_BYTE;

                    FUNCT3_SH:
                        decode_ctrl.mem_ctrl.memory_size = MEM_SIZE_HALF;

                    FUNCT3_SW:
                        decode_ctrl.mem_ctrl.memory_size = MEM_SIZE_WORD;

                    default:
                        subdecode_legal = 1'b0;
                endcase

                if (subdecode_legal) begin
                    instruction_legal = 1'b1;
                    decode_ctrl.uses_rs1 = 1'b1;
                    decode_ctrl.uses_rs2 = 1'b1;
                    decode_ctrl.immediate_type = IMM_S;

                    decode_ctrl.ex_ctrl.operand_a_select = OPA_RS1;
                    decode_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;

                    decode_ctrl.mem_ctrl.memory_write = 1'b1;
                end
            end

            OPCODE_MISC_MEM: begin
                if (funct3 == FUNCT3_FENCE) begin
                    // The in-order blocking memory system already provides
                    // conservative FENCE ordering. All fm/pred/succ/rs1/rd
                    // combinations retire without additional side effects.
                    instruction_legal = 1'b1;
                    decode_ctrl.ex_ctrl.operand_a_select = OPA_ZERO;
                    decode_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
                end
            end

            // -----------------------------------------------------------------
            // Integer execution instructions
            // -----------------------------------------------------------------
            OPCODE_OP_IMM: begin
                subdecode_legal = 1'b1;

                case (funct3)
                    FUNCT3_ADD_SUB:
                        decode_ctrl.ex_ctrl.alu_operation = ALU_ADD;

                    FUNCT3_SLL: begin
                        if (funct7 == FUNCT7_BASE)
                            decode_ctrl.ex_ctrl.alu_operation = ALU_SLL;
                        else
                            subdecode_legal = 1'b0;
                    end

                    FUNCT3_SLT:
                        decode_ctrl.ex_ctrl.alu_operation = ALU_SLT;

                    FUNCT3_SLTU:
                        decode_ctrl.ex_ctrl.alu_operation = ALU_SLTU;

                    FUNCT3_XOR:
                        decode_ctrl.ex_ctrl.alu_operation = ALU_XOR;

                    FUNCT3_SRL_SRA: begin
                        case (funct7)
                            FUNCT7_BASE:
                                decode_ctrl.ex_ctrl.alu_operation = ALU_SRL;

                            FUNCT7_SUB_SRA:
                                decode_ctrl.ex_ctrl.alu_operation = ALU_SRA;

                            default:
                                subdecode_legal = 1'b0;
                        endcase
                    end

                    FUNCT3_OR:
                        decode_ctrl.ex_ctrl.alu_operation = ALU_OR;

                    FUNCT3_AND:
                        decode_ctrl.ex_ctrl.alu_operation = ALU_AND;

                    default:
                        subdecode_legal = 1'b0;
                endcase

                if (subdecode_legal) begin
                    instruction_legal = 1'b1;
                    decode_ctrl.uses_rs1 = 1'b1;
                    decode_ctrl.immediate_type = IMM_I;

                    decode_ctrl.ex_ctrl.operand_a_select = OPA_RS1;
                    decode_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;

                    decode_ctrl.wb_ctrl.register_write = 1'b1;
                    decode_ctrl.wb_ctrl.writeback_select = WB_EXEC;
                end
            end

            OPCODE_OP: begin
                subdecode_legal = 1'b1;

                if (funct7 == FUNCT7_MULDIV) begin
                    decode_ctrl.mdu_ctrl.valid = 1'b1;

                    case (funct3)
                        3'b000:
                            decode_ctrl.mdu_ctrl.operation = MDU_MUL;
                        3'b001:
                            decode_ctrl.mdu_ctrl.operation = MDU_MULH;
                        3'b010:
                            decode_ctrl.mdu_ctrl.operation = MDU_MULHSU;
                        3'b011:
                            decode_ctrl.mdu_ctrl.operation = MDU_MULHU;
                        3'b100:
                            decode_ctrl.mdu_ctrl.operation = MDU_DIV;
                        3'b101:
                            decode_ctrl.mdu_ctrl.operation = MDU_DIVU;
                        3'b110:
                            decode_ctrl.mdu_ctrl.operation = MDU_REM;
                        3'b111:
                            decode_ctrl.mdu_ctrl.operation = MDU_REMU;
                        default: begin
                            subdecode_legal = 1'b0;
                            decode_ctrl.mdu_ctrl = '0;
                        end
                    endcase
                end
                else begin
                    case (funct3)
                        FUNCT3_ADD_SUB: begin
                            case (funct7)
                                FUNCT7_BASE:
                                    decode_ctrl.ex_ctrl.alu_operation = ALU_ADD;

                                FUNCT7_SUB_SRA:
                                    decode_ctrl.ex_ctrl.alu_operation = ALU_SUB;

                                default:
                                    subdecode_legal = 1'b0;
                            endcase
                        end

                        FUNCT3_SLL: begin
                            if (funct7 == FUNCT7_BASE)
                                decode_ctrl.ex_ctrl.alu_operation = ALU_SLL;
                            else
                                subdecode_legal = 1'b0;
                        end

                        FUNCT3_SLT: begin
                            if (funct7 == FUNCT7_BASE)
                                decode_ctrl.ex_ctrl.alu_operation = ALU_SLT;
                            else
                                subdecode_legal = 1'b0;
                        end

                        FUNCT3_SLTU: begin
                            if (funct7 == FUNCT7_BASE)
                                decode_ctrl.ex_ctrl.alu_operation = ALU_SLTU;
                            else
                                subdecode_legal = 1'b0;
                        end

                        FUNCT3_XOR: begin
                            if (funct7 == FUNCT7_BASE)
                                decode_ctrl.ex_ctrl.alu_operation = ALU_XOR;
                            else
                                subdecode_legal = 1'b0;
                        end

                        FUNCT3_SRL_SRA: begin
                            case (funct7)
                                FUNCT7_BASE:
                                    decode_ctrl.ex_ctrl.alu_operation = ALU_SRL;

                                FUNCT7_SUB_SRA:
                                    decode_ctrl.ex_ctrl.alu_operation = ALU_SRA;

                                default:
                                    subdecode_legal = 1'b0;
                            endcase
                        end

                        FUNCT3_OR: begin
                            if (funct7 == FUNCT7_BASE)
                                decode_ctrl.ex_ctrl.alu_operation = ALU_OR;
                            else
                                subdecode_legal = 1'b0;
                        end

                        FUNCT3_AND: begin
                            if (funct7 == FUNCT7_BASE)
                                decode_ctrl.ex_ctrl.alu_operation = ALU_AND;
                            else
                                subdecode_legal = 1'b0;
                        end

                        default:
                            subdecode_legal = 1'b0;
                    endcase
                end

                if (subdecode_legal) begin
                    instruction_legal = 1'b1;
                    decode_ctrl.uses_rs1 = 1'b1;
                    decode_ctrl.uses_rs2 = 1'b1;

                    decode_ctrl.ex_ctrl.operand_a_select = OPA_RS1;
                    decode_ctrl.ex_ctrl.operand_b_select = OPB_RS2;

                    decode_ctrl.wb_ctrl.register_write = 1'b1;
                    decode_ctrl.wb_ctrl.writeback_select = WB_EXEC;
                end
            end

            // -----------------------------------------------------------------
            // Environment, privileged, and Zicsr instructions
            // -----------------------------------------------------------------
            OPCODE_SYSTEM: begin
                case (funct3)
                    3'b000: begin
                        // These instructions use exact encodings. Other
                        // privileged encodings remain illegal in this profile.
                        case (instruction)
                            INSTRUCTION_ECALL: begin
                                instruction_legal = 1'b1;
                                decode_ctrl.environment_call = 1'b1;
                            end

                            INSTRUCTION_EBREAK: begin
                                instruction_legal = 1'b1;
                                decode_ctrl.breakpoint = 1'b1;
                            end

                            INSTRUCTION_MRET: begin
                                instruction_legal = 1'b1;
                                decode_ctrl.mret = 1'b1;
                                decode_ctrl.ex_ctrl.operand_a_select = OPA_ZERO;
                                decode_ctrl.ex_ctrl.operand_b_select =
                                    OPB_IMMEDIATE;
                            end

                            INSTRUCTION_WFI: begin
                                instruction_legal = 1'b1;
                                decode_ctrl.ex_ctrl.operand_a_select = OPA_ZERO;
                                decode_ctrl.ex_ctrl.operand_b_select =
                                    OPB_IMMEDIATE;
                            end

                            default: begin
                            end
                        endcase
                    end

                    FUNCT3_CSRRW: begin
                        subdecode_legal = 1'b1;
                        decode_ctrl.csr_ctrl.operation = CSR_WRITE;
                        decode_ctrl.csr_ctrl.read_enable =
                            (rd_addr != 5'd0);
                        decode_ctrl.csr_ctrl.write_enable = 1'b1;
                        decode_ctrl.uses_rs1 = 1'b1;
                    end

                    FUNCT3_CSRRS: begin
                        subdecode_legal = 1'b1;
                        decode_ctrl.csr_ctrl.operation = CSR_SET;
                        decode_ctrl.csr_ctrl.read_enable = 1'b1;
                        decode_ctrl.csr_ctrl.write_enable =
                            (rs1_or_zimm != 5'd0);
                        decode_ctrl.uses_rs1 = 1'b1;
                    end

                    FUNCT3_CSRRC: begin
                        subdecode_legal = 1'b1;
                        decode_ctrl.csr_ctrl.operation = CSR_CLEAR;
                        decode_ctrl.csr_ctrl.read_enable = 1'b1;
                        decode_ctrl.csr_ctrl.write_enable =
                            (rs1_or_zimm != 5'd0);
                        decode_ctrl.uses_rs1 = 1'b1;
                    end

                    FUNCT3_CSRRWI: begin
                        subdecode_legal = 1'b1;
                        decode_ctrl.csr_ctrl.operation = CSR_WRITE;
                        decode_ctrl.csr_ctrl.use_immediate = 1'b1;
                        decode_ctrl.csr_ctrl.read_enable =
                            (rd_addr != 5'd0);
                        decode_ctrl.csr_ctrl.write_enable = 1'b1;
                    end

                    FUNCT3_CSRRSI: begin
                        subdecode_legal = 1'b1;
                        decode_ctrl.csr_ctrl.operation = CSR_SET;
                        decode_ctrl.csr_ctrl.use_immediate = 1'b1;
                        decode_ctrl.csr_ctrl.read_enable = 1'b1;
                        decode_ctrl.csr_ctrl.write_enable =
                            (rs1_or_zimm != 5'd0);
                    end

                    FUNCT3_CSRRCI: begin
                        subdecode_legal = 1'b1;
                        decode_ctrl.csr_ctrl.operation = CSR_CLEAR;
                        decode_ctrl.csr_ctrl.use_immediate = 1'b1;
                        decode_ctrl.csr_ctrl.read_enable = 1'b1;
                        decode_ctrl.csr_ctrl.write_enable =
                            (rs1_or_zimm != 5'd0);
                    end

                    default: begin
                    end
                endcase

                if (subdecode_legal) begin
                    instruction_legal = 1'b1;
                    decode_ctrl.csr_ctrl.valid = 1'b1;

                    // CSR execution uses its own source and RMW datapath. Keep
                    // the otherwise-unused integer ALU result deterministic.
                    decode_ctrl.ex_ctrl.operand_a_select = OPA_ZERO;
                    decode_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;

                    decode_ctrl.wb_ctrl.register_write = 1'b1;
                    decode_ctrl.wb_ctrl.writeback_select = WB_CSR;
                end
            end

            default: begin
            end
        endcase

        // Legality is finalized once, after the complete opcode/subopcode tree.
        decode_ctrl.illegal_instruction = !instruction_legal;
    end

endmodule
