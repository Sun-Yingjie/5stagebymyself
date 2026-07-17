module tb_rv32_exu;

    timeunit 1ns;
    timeprecision 1ps;

    import rv32_pkg::*;

    id_ex_t         id_ex_q;
    forward_select_e rs1_forward_select;
    forward_select_e rs2_forward_select;
    logic [31:0]     ex_mem_forward_value;
    logic [31:0]     mem_wb_forward_value;

    ex_mem_t  ex_mem_candidate;
    redirect_t raw_redirect;

    ex_mem_t expected_candidate;

    int unsigned error_count;

    rv32_exu dut (
        .id_ex_q            (id_ex_q),
        .rs1_forward_select (rs1_forward_select),
        .rs2_forward_select (rs2_forward_select),
        .ex_mem_forward_value(ex_mem_forward_value),
        .mem_wb_forward_value(mem_wb_forward_value),
        .ex_mem_candidate   (ex_mem_candidate),
        .raw_redirect       (raw_redirect)
    );

    initial begin
        error_count = 0;

        test_basic_add();
        test_mixed_forwarding();
        test_reverse_forwarding();
        test_pc_immediate_operands();
        test_zero_immediate_operands();
        test_store_address_and_data_forwarding();
        test_taken_branch_with_forwarding();
        test_taken_branch_address_misaligned();
        test_not_taken_branch();
        test_jal_redirect();
        test_jal_address_misaligned();
        test_jalr_forwarding_and_alignment();
        test_jalr_address_misaligned();
        test_byte_address_alignment();
        test_load_address_misaligned();
        test_load_word_address_misaligned();
        test_store_address_misaligned();
        test_store_half_address_misaligned();
        test_invalid_jump_does_not_redirect();
        test_exception_jump_does_not_redirect();

        if (error_count != 0) begin
            $fatal(
                1,
                "[FAIL] rv32_exu: %0d test(s) failed",
                error_count
            );
        end

        $display("[PASS] rv32_exu: all tests passed");
        $finish;
    end

    task automatic set_defaults;
        begin
            id_ex_q              = '0;
            rs1_forward_select   = FWD_REG;
            rs2_forward_select   = FWD_REG;
            ex_mem_forward_value = 32'b0;
            mem_wb_forward_value = 32'b0;
            expected_candidate   = '0;
        end
    endtask

    task automatic set_instruction_metadata (
        input logic [31:0] pc,
        input logic [31:0] instruction,
        input logic [4:0]  rd_addr
    );
        begin
            id_ex_q.valid       = 1'b1;
            id_ex_q.pc          = pc;
            id_ex_q.instruction = instruction;
            id_ex_q.pc_plus_4   = pc + 32'd4;
            id_ex_q.rd_addr     = rd_addr;

            id_ex_q.mem_ctrl.memory_size = MEM_SIZE_WORD;
            id_ex_q.wb_ctrl.writeback_select = WB_EXEC;
        end
    endtask

    task automatic build_expected_candidate (
        input logic [31:0] expected_exec_result,
        input logic [31:0] expected_store_data
    );
        begin
            expected_candidate = '0;

            expected_candidate.valid       = id_ex_q.valid;
            expected_candidate.pc          = id_ex_q.pc;
            expected_candidate.instruction = id_ex_q.instruction;
            expected_candidate.pc_plus_4   = id_ex_q.pc_plus_4;
            expected_candidate.exec_result = expected_exec_result;
            expected_candidate.store_data  = expected_store_data;
            expected_candidate.rd_addr     = id_ex_q.rd_addr;
            expected_candidate.mem_ctrl    = id_ex_q.mem_ctrl;
            expected_candidate.wb_ctrl     = id_ex_q.wb_ctrl;
            expected_candidate.exception   = id_ex_q.exception;
        end
    endtask

    task automatic check_outputs (
        input logic        expected_redirect_valid,
        input logic [31:0] expected_redirect_target,
        input string       case_name
    );
        begin
            #1ns;

            if (
                (ex_mem_candidate !== expected_candidate) ||
                (raw_redirect.valid !== expected_redirect_valid) ||
                (
                    expected_redirect_valid &&
                    (raw_redirect.target !== expected_redirect_target)
                )
            ) begin
                error_count++;

                $error(
                    "[FAIL] %s: candidate=%h/%h redirect=%b:%h/%b:%h",
                    case_name,
                    ex_mem_candidate,
                    expected_candidate,
                    raw_redirect.valid,
                    raw_redirect.target,
                    expected_redirect_valid,
                    expected_redirect_target
                );
            end
            else begin
                $display("[PASS] %s", case_name);
            end
        end
    endtask

    task automatic test_basic_add;
        begin
            set_defaults();
            set_instruction_metadata(
                32'h0000_0100,
                32'h0062_83b3,
                5'd7
            );

            id_ex_q.rs1_data = 32'd10;
            id_ex_q.rs2_data = 32'd20;
            id_ex_q.uses_rs1 = 1'b1;
            id_ex_q.uses_rs2 = 1'b1;
            id_ex_q.ex_ctrl.operand_a_select = OPA_RS1;
            id_ex_q.ex_ctrl.operand_b_select = OPB_RS2;
            id_ex_q.ex_ctrl.alu_operation = ALU_ADD;
            id_ex_q.wb_ctrl.register_write = 1'b1;

            build_expected_candidate(32'd30, 32'd20);
            check_outputs(1'b0, 32'b0, "basic ADD and metadata");
        end
    endtask

    task automatic test_mixed_forwarding;
        begin
            set_defaults();
            set_instruction_metadata(
                32'h0000_0110,
                32'h4062_83b3,
                5'd7
            );

            id_ex_q.rs1_data = 32'haaaa_aaaa;
            id_ex_q.rs2_data = 32'hbbbb_bbbb;
            id_ex_q.uses_rs1 = 1'b1;
            id_ex_q.uses_rs2 = 1'b1;
            id_ex_q.ex_ctrl.alu_operation = ALU_SUB;

            rs1_forward_select   = FWD_EX_MEM;
            rs2_forward_select   = FWD_MEM_WB;
            ex_mem_forward_value = 32'd16;
            mem_wb_forward_value = 32'd3;

            build_expected_candidate(32'd13, 32'd3);
            check_outputs(
                1'b0,
                32'b0,
                "EX/MEM forwards rs1 and MEM/WB forwards rs2"
            );
        end
    endtask

    task automatic test_reverse_forwarding;
        begin
            set_defaults();
            set_instruction_metadata(
                32'h0000_0120,
                32'h4062_83b3,
                5'd7
            );

            id_ex_q.rs1_data = 32'haaaa_aaaa;
            id_ex_q.rs2_data = 32'hbbbb_bbbb;
            id_ex_q.uses_rs1 = 1'b1;
            id_ex_q.uses_rs2 = 1'b1;
            id_ex_q.ex_ctrl.alu_operation = ALU_SUB;

            rs1_forward_select   = FWD_MEM_WB;
            rs2_forward_select   = FWD_EX_MEM;
            ex_mem_forward_value = 32'd5;
            mem_wb_forward_value = 32'd20;

            build_expected_candidate(32'd15, 32'd5);
            check_outputs(
                1'b0,
                32'b0,
                "MEM/WB forwards rs1 and EX/MEM forwards rs2"
            );
        end
    endtask

    task automatic test_pc_immediate_operands;
        begin
            set_defaults();
            set_instruction_metadata(
                32'h0000_1000,
                32'h0340_0097,
                5'd1
            );

            id_ex_q.immediate = 32'h0000_0034;
            id_ex_q.ex_ctrl.operand_a_select = OPA_PC;
            id_ex_q.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            id_ex_q.ex_ctrl.alu_operation = ALU_ADD;
            id_ex_q.wb_ctrl.register_write = 1'b1;

            build_expected_candidate(32'h0000_1034, 32'b0);
            check_outputs(1'b0, 32'b0, "PC plus immediate operands");
        end
    endtask

    task automatic test_zero_immediate_operands;
        begin
            set_defaults();
            set_instruction_metadata(
                32'h0000_1100,
                32'h1234_50b7,
                5'd1
            );

            id_ex_q.immediate = 32'h1234_5000;
            id_ex_q.ex_ctrl.operand_a_select = OPA_ZERO;
            id_ex_q.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            id_ex_q.ex_ctrl.alu_operation = ALU_ADD;
            id_ex_q.wb_ctrl.register_write = 1'b1;

            build_expected_candidate(32'h1234_5000, 32'b0);
            check_outputs(1'b0, 32'b0, "zero plus U-immediate operands");
        end
    endtask

    task automatic test_store_address_and_data_forwarding;
        begin
            set_defaults();
            set_instruction_metadata(
                32'h0000_1200,
                32'h0062_a823,
                5'd0
            );

            id_ex_q.rs1_data = 32'haaaa_aaaa;
            id_ex_q.rs2_data = 32'hbbbb_bbbb;
            id_ex_q.uses_rs1 = 1'b1;
            id_ex_q.uses_rs2 = 1'b1;
            id_ex_q.immediate = 32'h0000_0010;
            id_ex_q.ex_ctrl.operand_a_select = OPA_RS1;
            id_ex_q.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            id_ex_q.ex_ctrl.alu_operation = ALU_ADD;
            id_ex_q.mem_ctrl.memory_write = 1'b1;

            rs1_forward_select   = FWD_EX_MEM;
            rs2_forward_select   = FWD_MEM_WB;
            ex_mem_forward_value = 32'h0000_1000;
            mem_wb_forward_value = 32'hdead_beef;

            build_expected_candidate(32'h0000_1010, 32'hdead_beef);
            check_outputs(
                1'b0,
                32'b0,
                "store address and data use forwarded operands"
            );
        end
    endtask

    task automatic test_taken_branch_with_forwarding;
        begin
            set_defaults();
            set_instruction_metadata(
                32'h0000_0200,
                32'h0062_8863,
                5'd0
            );

            id_ex_q.rs1_data = 32'd1;
            id_ex_q.rs2_data = 32'd2;
            id_ex_q.uses_rs1 = 1'b1;
            id_ex_q.uses_rs2 = 1'b1;
            id_ex_q.immediate = 32'h0000_0040;
            id_ex_q.ex_ctrl.operand_a_select = OPA_PC;
            id_ex_q.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            id_ex_q.ex_ctrl.branch_operation = BR_EQ;

            rs1_forward_select   = FWD_EX_MEM;
            rs2_forward_select   = FWD_MEM_WB;
            ex_mem_forward_value = 32'd7;
            mem_wb_forward_value = 32'd7;

            build_expected_candidate(32'h0000_0240, 32'd7);
            check_outputs(
                1'b1,
                32'h0000_0240,
                "taken branch compares forwarded operands"
            );
        end
    endtask

    task automatic test_taken_branch_address_misaligned;
        begin
            set_defaults();
            set_instruction_metadata(
                32'h0000_0260,
                32'h0020_8163,
                5'd0
            );

            id_ex_q.rs1_data = 32'd9;
            id_ex_q.rs2_data = 32'd9;
            id_ex_q.uses_rs1 = 1'b1;
            id_ex_q.uses_rs2 = 1'b1;
            id_ex_q.immediate = 32'd2;
            id_ex_q.ex_ctrl.operand_a_select = OPA_PC;
            id_ex_q.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            id_ex_q.ex_ctrl.branch_operation = BR_EQ;

            build_expected_candidate(32'h0000_0262, 32'd9);
            expected_candidate.mem_ctrl = '0;
            expected_candidate.wb_ctrl = '0;
            expected_candidate.exception.valid = 1'b1;
            expected_candidate.exception.cause =
                EXCEPTION_CAUSE_INSTRUCTION_ADDRESS_MISALIGNED;
            expected_candidate.exception.value = 32'h0000_0262;

            check_outputs(
                1'b0,
                32'b0,
                "taken branch with misaligned target traps"
            );
        end
    endtask

    task automatic test_not_taken_branch;
        begin
            set_defaults();
            set_instruction_metadata(
                32'h0000_0220,
                32'h0062_8463,
                5'd0
            );

            id_ex_q.rs1_data = 32'd7;
            id_ex_q.rs2_data = 32'd8;
            id_ex_q.uses_rs1 = 1'b1;
            id_ex_q.uses_rs2 = 1'b1;
            id_ex_q.immediate = 32'h0000_0002;
            id_ex_q.ex_ctrl.operand_a_select = OPA_PC;
            id_ex_q.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            id_ex_q.ex_ctrl.branch_operation = BR_EQ;

            build_expected_candidate(32'h0000_0222, 32'd8);
            check_outputs(
                1'b0,
                32'b0,
                "not-taken branch ignores a misaligned target"
            );
        end
    endtask

    task automatic test_jal_redirect;
        begin
            set_defaults();
            set_instruction_metadata(
                32'h0000_0300,
                32'h0200_00ef,
                5'd1
            );

            id_ex_q.immediate = 32'h0000_0020;
            id_ex_q.ex_ctrl.operand_a_select = OPA_PC;
            id_ex_q.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            id_ex_q.ex_ctrl.is_jump = 1'b1;
            id_ex_q.wb_ctrl.register_write = 1'b1;
            id_ex_q.wb_ctrl.writeback_select = WB_PC_PLUS_4;

            build_expected_candidate(32'h0000_0320, 32'b0);
            check_outputs(1'b1, 32'h0000_0320, "JAL redirect");
        end
    endtask

    task automatic test_jal_address_misaligned;
        begin
            set_defaults();
            set_instruction_metadata(
                32'h0000_0320,
                32'h0020_00ef,
                5'd1
            );

            id_ex_q.immediate = 32'd2;
            id_ex_q.ex_ctrl.operand_a_select = OPA_PC;
            id_ex_q.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            id_ex_q.ex_ctrl.is_jump = 1'b1;
            id_ex_q.wb_ctrl.register_write = 1'b1;
            id_ex_q.wb_ctrl.writeback_select = WB_PC_PLUS_4;

            build_expected_candidate(32'h0000_0322, 32'b0);
            expected_candidate.mem_ctrl = '0;
            expected_candidate.wb_ctrl = '0;
            expected_candidate.exception.valid = 1'b1;
            expected_candidate.exception.cause =
                EXCEPTION_CAUSE_INSTRUCTION_ADDRESS_MISALIGNED;
            expected_candidate.exception.value = 32'h0000_0322;

            check_outputs(1'b0, 32'b0, "JAL with misaligned target traps");
        end
    endtask

    task automatic test_jalr_forwarding_and_alignment;
        begin
            set_defaults();
            set_instruction_metadata(
                32'h0000_0340,
                32'h0042_80e7,
                5'd1
            );

            id_ex_q.rs1_data = 32'haaaa_aaaa;
            id_ex_q.uses_rs1 = 1'b1;
            id_ex_q.immediate = 32'd4;
            id_ex_q.ex_ctrl.operand_a_select = OPA_RS1;
            id_ex_q.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            id_ex_q.ex_ctrl.is_jump = 1'b1;
            id_ex_q.ex_ctrl.is_jalr = 1'b1;
            id_ex_q.wb_ctrl.register_write = 1'b1;
            id_ex_q.wb_ctrl.writeback_select = WB_PC_PLUS_4;

            rs1_forward_select   = FWD_EX_MEM;
            ex_mem_forward_value = 32'h0000_1001;

            build_expected_candidate(32'h0000_1005, 32'b0);
            check_outputs(
                1'b1,
                32'h0000_1004,
                "aligned JALR uses forwarded rs1 and clears target bit zero"
            );
        end
    endtask

    task automatic test_jalr_address_misaligned;
        begin
            set_defaults();
            set_instruction_metadata(
                32'h0000_0360,
                32'h0042_80e7,
                5'd1
            );

            id_ex_q.rs1_data = 32'h0000_1003;
            id_ex_q.uses_rs1 = 1'b1;
            id_ex_q.immediate = 32'd4;
            id_ex_q.ex_ctrl.operand_a_select = OPA_RS1;
            id_ex_q.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            id_ex_q.ex_ctrl.is_jump = 1'b1;
            id_ex_q.ex_ctrl.is_jalr = 1'b1;
            id_ex_q.wb_ctrl.register_write = 1'b1;
            id_ex_q.wb_ctrl.writeback_select = WB_PC_PLUS_4;

            build_expected_candidate(32'h0000_1007, 32'b0);
            expected_candidate.mem_ctrl = '0;
            expected_candidate.wb_ctrl = '0;
            expected_candidate.exception.valid = 1'b1;
            expected_candidate.exception.cause =
                EXCEPTION_CAUSE_INSTRUCTION_ADDRESS_MISALIGNED;
            expected_candidate.exception.value = 32'h0000_1006;

            check_outputs(
                1'b0,
                32'b0,
                "JALR clears bit zero before checking IALIGN=32"
            );
        end
    endtask

    task automatic test_load_address_misaligned;
        begin
            set_defaults();
            set_instruction_metadata(
                32'h0000_0380,
                32'h0000_9283,
                5'd5
            );

            id_ex_q.rs1_data = 32'h0000_1001;
            id_ex_q.immediate = 32'b0;
            id_ex_q.ex_ctrl.operand_a_select = OPA_RS1;
            id_ex_q.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            id_ex_q.mem_ctrl.memory_read = 1'b1;
            id_ex_q.mem_ctrl.memory_size = MEM_SIZE_HALF;
            id_ex_q.wb_ctrl.register_write = 1'b1;
            id_ex_q.wb_ctrl.writeback_select = WB_LOAD;

            build_expected_candidate(32'h0000_1001, 32'b0);
            expected_candidate.mem_ctrl = '0;
            expected_candidate.wb_ctrl = '0;
            expected_candidate.exception.valid = 1'b1;
            expected_candidate.exception.cause =
                EXCEPTION_CAUSE_LOAD_ADDRESS_MISALIGNED;
            expected_candidate.exception.value = 32'h0000_1001;

            check_outputs(1'b0, 32'b0, "misaligned LH is poisoned in EX");
        end
    endtask

    task automatic test_byte_address_alignment;
        begin
            set_defaults();
            set_instruction_metadata(
                32'h0000_0370,
                32'h0000_8283,
                5'd5
            );

            id_ex_q.rs1_data = 32'h0000_1003;
            id_ex_q.immediate = 32'b0;
            id_ex_q.ex_ctrl.operand_a_select = OPA_RS1;
            id_ex_q.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            id_ex_q.mem_ctrl.memory_read = 1'b1;
            id_ex_q.mem_ctrl.memory_size = MEM_SIZE_BYTE;
            id_ex_q.wb_ctrl.register_write = 1'b1;
            id_ex_q.wb_ctrl.writeback_select = WB_LOAD;

            build_expected_candidate(32'h0000_1003, 32'b0);
            check_outputs(1'b0, 32'b0, "byte load accepts any byte address");
        end
    endtask

    task automatic test_load_word_address_misaligned;
        begin
            set_defaults();
            set_instruction_metadata(
                32'h0000_0390,
                32'h0000_a283,
                5'd5
            );

            id_ex_q.rs1_data = 32'h0000_1002;
            id_ex_q.immediate = 32'b0;
            id_ex_q.ex_ctrl.operand_a_select = OPA_RS1;
            id_ex_q.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            id_ex_q.mem_ctrl.memory_read = 1'b1;
            id_ex_q.mem_ctrl.memory_size = MEM_SIZE_WORD;
            id_ex_q.wb_ctrl.register_write = 1'b1;
            id_ex_q.wb_ctrl.writeback_select = WB_LOAD;

            build_expected_candidate(32'h0000_1002, 32'b0);
            expected_candidate.mem_ctrl = '0;
            expected_candidate.wb_ctrl = '0;
            expected_candidate.exception.valid = 1'b1;
            expected_candidate.exception.cause =
                EXCEPTION_CAUSE_LOAD_ADDRESS_MISALIGNED;
            expected_candidate.exception.value = 32'h0000_1002;

            check_outputs(1'b0, 32'b0, "misaligned LW is poisoned in EX");
        end
    endtask

    task automatic test_store_address_misaligned;
        begin
            set_defaults();
            set_instruction_metadata(
                32'h0000_03a0,
                32'h0051_2023,
                5'd0
            );

            id_ex_q.rs1_data = 32'h0000_1002;
            id_ex_q.rs2_data = 32'hdead_beef;
            id_ex_q.immediate = 32'b0;
            id_ex_q.ex_ctrl.operand_a_select = OPA_RS1;
            id_ex_q.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            id_ex_q.mem_ctrl.memory_write = 1'b1;
            id_ex_q.mem_ctrl.memory_size = MEM_SIZE_WORD;

            build_expected_candidate(32'h0000_1002, 32'hdead_beef);
            expected_candidate.mem_ctrl = '0;
            expected_candidate.wb_ctrl = '0;
            expected_candidate.exception.valid = 1'b1;
            expected_candidate.exception.cause =
                EXCEPTION_CAUSE_STORE_ADDRESS_MISALIGNED;
            expected_candidate.exception.value = 32'h0000_1002;

            check_outputs(1'b0, 32'b0, "misaligned SW is poisoned in EX");
        end
    endtask

    task automatic test_store_half_address_misaligned;
        begin
            set_defaults();
            set_instruction_metadata(
                32'h0000_03b0,
                32'h0051_1023,
                5'd0
            );

            id_ex_q.rs1_data = 32'h0000_1001;
            id_ex_q.rs2_data = 32'hdead_beef;
            id_ex_q.immediate = 32'b0;
            id_ex_q.ex_ctrl.operand_a_select = OPA_RS1;
            id_ex_q.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            id_ex_q.mem_ctrl.memory_write = 1'b1;
            id_ex_q.mem_ctrl.memory_size = MEM_SIZE_HALF;

            build_expected_candidate(32'h0000_1001, 32'hdead_beef);
            expected_candidate.mem_ctrl = '0;
            expected_candidate.wb_ctrl = '0;
            expected_candidate.exception.valid = 1'b1;
            expected_candidate.exception.cause =
                EXCEPTION_CAUSE_STORE_ADDRESS_MISALIGNED;
            expected_candidate.exception.value = 32'h0000_1001;

            check_outputs(1'b0, 32'b0, "misaligned SH is poisoned in EX");
        end
    endtask

    task automatic test_invalid_jump_does_not_redirect;
        begin
            set_defaults();

            id_ex_q.valid = 1'b0;
            id_ex_q.pc = 32'h0000_0400;
            id_ex_q.immediate = 32'h0000_0020;
            id_ex_q.ex_ctrl.operand_a_select = OPA_PC;
            id_ex_q.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            id_ex_q.ex_ctrl.is_jump = 1'b1;

            build_expected_candidate(32'h0000_0420, 32'b0);
            check_outputs(1'b0, 32'b0, "invalid jump does not redirect");
        end
    endtask

    task automatic test_exception_jump_does_not_redirect;
        begin
            set_defaults();
            set_instruction_metadata(
                32'h0000_0500,
                32'h0200_00ef,
                5'd1
            );

            id_ex_q.immediate = 32'h0000_0002;
            id_ex_q.ex_ctrl.operand_a_select = OPA_PC;
            id_ex_q.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            id_ex_q.ex_ctrl.is_jump = 1'b1;
            id_ex_q.wb_ctrl.register_write = 1'b1;
            id_ex_q.exception.valid = 1'b1;
            id_ex_q.exception.cause = EXCEPTION_CAUSE_ILLEGAL_INSTRUCTION;
            id_ex_q.exception.value = id_ex_q.instruction;

            build_expected_candidate(32'h0000_0502, 32'b0);
            expected_candidate.mem_ctrl = '0;
            expected_candidate.wb_ctrl = '0;
            check_outputs(
                1'b0,
                32'b0,
                "incoming exception wins over EX misalignment"
            );
        end
    endtask

endmodule
