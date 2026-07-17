module tb_rv32_decoder;

    timeunit 1ns;
    timeprecision 1ps;

    import rv32_pkg::*;

    logic [31:0] instruction;
    decode_ctrl_t decode_ctrl;
    decode_ctrl_t expected_ctrl;
    int unsigned error_count;

    rv32_decoder dut (
        .instruction(instruction),
        .decode_ctrl(decode_ctrl)
    );

    initial begin
        error_count = 0;

        test_u_type(OPCODE_LUI,   OPA_ZERO, "LUI");
        test_u_type(OPCODE_AUIPC, OPA_PC,   "AUIPC");
        test_jal();
        test_jalr();

        test_branch(FUNCT3_BEQ,  BR_EQ,  "BEQ");
        test_branch(FUNCT3_BNE,  BR_NE,  "BNE");
        test_branch(FUNCT3_BLT,  BR_LT,  "BLT");
        test_branch(FUNCT3_BGE,  BR_GE,  "BGE");
        test_branch(FUNCT3_BLTU, BR_LTU, "BLTU");
        test_branch(FUNCT3_BGEU, BR_GEU, "BGEU");

        test_load(FUNCT3_LB,  MEM_SIZE_BYTE, 1'b0, "LB");
        test_load(FUNCT3_LH,  MEM_SIZE_HALF, 1'b0, "LH");
        test_load(FUNCT3_LW,  MEM_SIZE_WORD, 1'b0, "LW");
        test_load(FUNCT3_LBU, MEM_SIZE_BYTE, 1'b1, "LBU");
        test_load(FUNCT3_LHU, MEM_SIZE_HALF, 1'b1, "LHU");

        test_store(FUNCT3_SB, MEM_SIZE_BYTE, "SB");
        test_store(FUNCT3_SH, MEM_SIZE_HALF, "SH");
        test_store(FUNCT3_SW, MEM_SIZE_WORD, "SW");

        test_fence();
        test_system_exceptions();

        test_op_imm(FUNCT3_ADD_SUB, FUNCT7_BASE,    ALU_ADD,  "ADDI");
        test_op_imm(FUNCT3_SLL,     FUNCT7_BASE,    ALU_SLL,  "SLLI");
        test_op_imm(FUNCT3_SLT,     FUNCT7_BASE,    ALU_SLT,  "SLTI");
        test_op_imm(FUNCT3_SLTU,    FUNCT7_BASE,    ALU_SLTU, "SLTIU");
        test_op_imm(FUNCT3_XOR,     FUNCT7_BASE,    ALU_XOR,  "XORI");
        test_op_imm(FUNCT3_SRL_SRA, FUNCT7_BASE,    ALU_SRL,  "SRLI");
        test_op_imm(FUNCT3_SRL_SRA, FUNCT7_SUB_SRA, ALU_SRA,  "SRAI");
        test_op_imm(FUNCT3_OR,      FUNCT7_BASE,    ALU_OR,   "ORI");
        test_op_imm(FUNCT3_AND,     FUNCT7_BASE,    ALU_AND,  "ANDI");

        test_op(FUNCT3_ADD_SUB, FUNCT7_BASE,    ALU_ADD,  "ADD");
        test_op(FUNCT3_ADD_SUB, FUNCT7_SUB_SRA, ALU_SUB,  "SUB");
        test_op(FUNCT3_SLL,     FUNCT7_BASE,    ALU_SLL,  "SLL");
        test_op(FUNCT3_SLT,     FUNCT7_BASE,    ALU_SLT,  "SLT");
        test_op(FUNCT3_SLTU,    FUNCT7_BASE,    ALU_SLTU, "SLTU");
        test_op(FUNCT3_XOR,     FUNCT7_BASE,    ALU_XOR,  "XOR");
        test_op(FUNCT3_SRL_SRA, FUNCT7_BASE,    ALU_SRL,  "SRL");
        test_op(FUNCT3_SRL_SRA, FUNCT7_SUB_SRA, ALU_SRA,  "SRA");
        test_op(FUNCT3_OR,      FUNCT7_BASE,    ALU_OR,   "OR");
        test_op(FUNCT3_AND,     FUNCT7_BASE,    ALU_AND,  "AND");

        test_illegal(OPCODE_JALR,   3'b001,        FUNCT7_BASE,
                     "illegal JALR funct3");
        test_illegal(OPCODE_LOAD,   3'b111,        FUNCT7_BASE,
                     "illegal LOAD funct3");
        test_illegal(OPCODE_STORE,  3'b111,        FUNCT7_BASE,
                     "illegal STORE funct3");
        test_illegal(OPCODE_OP_IMM, FUNCT3_SLL,    FUNCT7_SUB_SRA,
                     "illegal SLLI funct7");
        test_illegal(OPCODE_OP_IMM, FUNCT3_SRL_SRA, 7'b000_0001,
                     "illegal shift-immediate funct7");
        test_illegal(OPCODE_OP,     FUNCT3_ADD_SUB, 7'b000_0001,
                     "illegal RV32M encoding");
        test_illegal(OPCODE_MISC_MEM, 3'b001, FUNCT7_BASE,
                     "FENCE.I is illegal without Zifencei");
        test_illegal(7'b111_1111,   3'b000,        FUNCT7_BASE,
                     "illegal opcode");

        if (error_count != 0) begin
            $fatal(
                1,
                "[FAIL] rv32_decoder: %0d test(s) failed",
                error_count
            );
        end

        $display("[PASS] rv32_decoder: all tests passed");
        $finish;
    end

    task automatic test_u_type (
        input logic [6:0]        opcode,
        input operand_a_select_e operand_a_select,
        input string             case_name
    );
        begin
            set_expected_defaults();
            expected_ctrl.illegal_instruction = 1'b0;
            expected_ctrl.immediate_type = IMM_U;
            expected_ctrl.ex_ctrl.operand_a_select = operand_a_select;
            expected_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            expected_ctrl.wb_ctrl.register_write = 1'b1;
            check_decode(make_instruction(opcode, 3'b000, FUNCT7_BASE),
                         expected_ctrl, case_name);
        end
    endtask

    task automatic test_jal;
        begin
            set_expected_defaults();
            expected_ctrl.illegal_instruction = 1'b0;
            expected_ctrl.immediate_type = IMM_J;
            expected_ctrl.ex_ctrl.operand_a_select = OPA_PC;
            expected_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            expected_ctrl.ex_ctrl.is_jump = 1'b1;
            expected_ctrl.wb_ctrl.register_write = 1'b1;
            expected_ctrl.wb_ctrl.writeback_select = WB_PC_PLUS_4;
            check_decode(make_instruction(OPCODE_JAL, 3'b000, FUNCT7_BASE),
                         expected_ctrl, "JAL");
        end
    endtask

    task automatic test_fence;
        logic [31:0] fence_instruction;

        begin
            set_expected_defaults();
            expected_ctrl.illegal_instruction = 1'b0;
            expected_ctrl.ex_ctrl.operand_a_select = OPA_ZERO;
            expected_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;

            check_decode(
                32'h0ff0_000f,
                expected_ctrl,
                "FENCE RWIO,RWIO"
            );
            check_decode(
                32'h8330_000f,
                expected_ctrl,
                "FENCE.TSO is conservatively treated as FENCE"
            );

            fence_instruction = '0;
            fence_instruction[31:20] = 12'habc;
            fence_instruction[19:15] = 5'h1f;
            fence_instruction[14:12] = FUNCT3_FENCE;
            fence_instruction[11:7]  = 5'h1f;
            fence_instruction[6:0]   = OPCODE_MISC_MEM;
            check_decode(
                fence_instruction,
                expected_ctrl,
                "FENCE ignores reserved fm/pred/succ/rs1/rd fields"
            );
        end
    endtask

    task automatic test_system_exceptions;
        begin
            set_expected_defaults();
            expected_ctrl.illegal_instruction = 1'b0;
            expected_ctrl.environment_call = 1'b1;
            check_decode(
                INSTRUCTION_ECALL,
                expected_ctrl,
                "ECALL exception source"
            );

            set_expected_defaults();
            expected_ctrl.illegal_instruction = 1'b0;
            expected_ctrl.breakpoint = 1'b1;
            check_decode(
                INSTRUCTION_EBREAK,
                expected_ctrl,
                "EBREAK exception source"
            );

            set_expected_defaults();
            check_decode(
                INSTRUCTION_ECALL | 32'h0000_0080,
                expected_ctrl,
                "ECALL with nonzero rd is illegal"
            );
            check_decode(
                INSTRUCTION_ECALL | 32'h0000_8000,
                expected_ctrl,
                "ECALL with nonzero rs1 is illegal"
            );
            check_decode(
                32'h3020_0073,
                expected_ctrl,
                "MRET remains illegal before Machine Mode"
            );
            check_decode(
                32'h3000_1073,
                expected_ctrl,
                "CSR instruction remains illegal before Zicsr"
            );
        end
    endtask

    task automatic test_jalr;
        begin
            set_expected_defaults();
            expected_ctrl.illegal_instruction = 1'b0;
            expected_ctrl.uses_rs1 = 1'b1;
            expected_ctrl.immediate_type = IMM_I;
            expected_ctrl.ex_ctrl.operand_a_select = OPA_RS1;
            expected_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            expected_ctrl.ex_ctrl.is_jump = 1'b1;
            expected_ctrl.ex_ctrl.is_jalr = 1'b1;
            expected_ctrl.wb_ctrl.register_write = 1'b1;
            expected_ctrl.wb_ctrl.writeback_select = WB_PC_PLUS_4;
            check_decode(make_instruction(OPCODE_JALR, FUNCT3_JALR, FUNCT7_BASE),
                         expected_ctrl, "JALR");
        end
    endtask

    task automatic test_branch (
        input logic [2:0]        funct3,
        input branch_operation_e branch_operation,
        input string             case_name
    );
        begin
            set_expected_defaults();
            expected_ctrl.illegal_instruction = 1'b0;
            expected_ctrl.uses_rs1 = 1'b1;
            expected_ctrl.uses_rs2 = 1'b1;
            expected_ctrl.immediate_type = IMM_B;
            expected_ctrl.ex_ctrl.operand_a_select = OPA_PC;
            expected_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            expected_ctrl.ex_ctrl.branch_operation = branch_operation;
            check_decode(make_instruction(OPCODE_BRANCH, funct3, FUNCT7_BASE),
                         expected_ctrl, case_name);
        end
    endtask

    task automatic test_load (
        input logic [2:0]   funct3,
        input memory_size_e memory_size,
        input logic         load_unsigned,
        input string        case_name
    );
        begin
            set_expected_defaults();
            expected_ctrl.illegal_instruction = 1'b0;
            expected_ctrl.uses_rs1 = 1'b1;
            expected_ctrl.immediate_type = IMM_I;
            expected_ctrl.ex_ctrl.operand_a_select = OPA_RS1;
            expected_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            expected_ctrl.mem_ctrl.memory_read = 1'b1;
            expected_ctrl.mem_ctrl.memory_size = memory_size;
            expected_ctrl.mem_ctrl.load_unsigned = load_unsigned;
            expected_ctrl.wb_ctrl.register_write = 1'b1;
            expected_ctrl.wb_ctrl.writeback_select = WB_LOAD;
            check_decode(make_instruction(OPCODE_LOAD, funct3, FUNCT7_BASE),
                         expected_ctrl, case_name);
        end
    endtask

    task automatic test_store (
        input logic [2:0]   funct3,
        input memory_size_e memory_size,
        input string        case_name
    );
        begin
            set_expected_defaults();
            expected_ctrl.illegal_instruction = 1'b0;
            expected_ctrl.uses_rs1 = 1'b1;
            expected_ctrl.uses_rs2 = 1'b1;
            expected_ctrl.immediate_type = IMM_S;
            expected_ctrl.ex_ctrl.operand_a_select = OPA_RS1;
            expected_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            expected_ctrl.mem_ctrl.memory_write = 1'b1;
            expected_ctrl.mem_ctrl.memory_size = memory_size;
            check_decode(make_instruction(OPCODE_STORE, funct3, FUNCT7_BASE),
                         expected_ctrl, case_name);
        end
    endtask

    task automatic test_op_imm (
        input logic [2:0]     funct3,
        input logic [6:0]     funct7,
        input alu_operation_e alu_operation,
        input string          case_name
    );
        begin
            set_expected_defaults();
            expected_ctrl.illegal_instruction = 1'b0;
            expected_ctrl.uses_rs1 = 1'b1;
            expected_ctrl.immediate_type = IMM_I;
            expected_ctrl.ex_ctrl.operand_a_select = OPA_RS1;
            expected_ctrl.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            expected_ctrl.ex_ctrl.alu_operation = alu_operation;
            expected_ctrl.wb_ctrl.register_write = 1'b1;
            expected_ctrl.wb_ctrl.writeback_select = WB_EXEC;
            check_decode(make_instruction(OPCODE_OP_IMM, funct3, funct7),
                         expected_ctrl, case_name);
        end
    endtask

    task automatic test_op (
        input logic [2:0]     funct3,
        input logic [6:0]     funct7,
        input alu_operation_e alu_operation,
        input string          case_name
    );
        begin
            set_expected_defaults();
            expected_ctrl.illegal_instruction = 1'b0;
            expected_ctrl.uses_rs1 = 1'b1;
            expected_ctrl.uses_rs2 = 1'b1;
            expected_ctrl.ex_ctrl.operand_a_select = OPA_RS1;
            expected_ctrl.ex_ctrl.operand_b_select = OPB_RS2;
            expected_ctrl.ex_ctrl.alu_operation = alu_operation;
            expected_ctrl.wb_ctrl.register_write = 1'b1;
            expected_ctrl.wb_ctrl.writeback_select = WB_EXEC;
            check_decode(make_instruction(OPCODE_OP, funct3, funct7),
                         expected_ctrl, case_name);
        end
    endtask

    task automatic test_illegal (
        input logic [6:0] opcode,
        input logic [2:0] funct3,
        input logic [6:0] funct7,
        input string      case_name
    );
        begin
            set_expected_defaults();
            check_decode(make_instruction(opcode, funct3, funct7),
                         expected_ctrl, case_name);
        end
    endtask

    function automatic logic [31:0] make_instruction (
        input logic [6:0] opcode,
        input logic [2:0] funct3,
        input logic [6:0] funct7
    );
        logic [31:0] value;

        begin
            value = 32'b0;
            value[6:0]   = opcode;
            value[14:12] = funct3;
            value[31:25] = funct7;

            make_instruction = value;
        end
    endfunction

    task automatic set_expected_defaults;
        begin
            expected_ctrl = '0;

            expected_ctrl.immediate_type = IMM_NONE;
            expected_ctrl.illegal_instruction = 1'b1;

            expected_ctrl.ex_ctrl.operand_a_select = OPA_RS1;
            expected_ctrl.ex_ctrl.operand_b_select = OPB_RS2;
            expected_ctrl.ex_ctrl.alu_operation = ALU_ADD;
            expected_ctrl.ex_ctrl.branch_operation = BR_NONE;

            expected_ctrl.mem_ctrl.memory_size = MEM_SIZE_WORD;

            expected_ctrl.wb_ctrl.writeback_select = WB_EXEC;
        end
    endtask

    task automatic check_decode (
        input logic [31:0]  instruction_value,
        input decode_ctrl_t expected_value,
        input string        case_name
    );
        begin
            instruction = instruction_value;

            #1ns;

            if (decode_ctrl !== expected_value) begin
                error_count++;

                $error(
                    "[FAIL] %s: decode_ctrl=%h, expected=%h",
                    case_name,
                    decode_ctrl,
                    expected_value
                );
            end
            else begin
                $display("[PASS] %s", case_name);
            end
        end
    endtask

endmodule
