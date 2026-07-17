module tb_rv32_idu;

    timeunit 1ns;
    timeprecision 1ps;

    import rv32_pkg::*;

    logic   clk;
    if_id_t if_id_q;
    wb_bus_t wb_bus;
    id_ex_t id_ex_candidate;
    id_ex_t expected_candidate;
    int unsigned error_count;

    rv32_idu dut (
        .clk            (clk),
        .if_id_q        (if_id_q),
        .wb_bus         (wb_bus),
        .id_ex_candidate(id_ex_candidate)
    );

    initial begin
        clk = 1'b0;
        forever #5ns clk = ~clk;
    end

    initial begin
        error_count = 0;
        set_defaults();
// basic test
        write_register(5'd5, 32'h1234_5678);
        write_register(5'd6, 32'ha5a5_5a5a);

        if_id_q                 = '0;
        if_id_q.valid           = 1'b1;
        if_id_q.pc              = 32'h0000_0100;
        if_id_q.instruction     = make_r_instruction(
            FUNCT7_BASE,
            5'd6,
            5'd5,
            FUNCT3_ADD_SUB,
            5'd7
        );
        if_id_q.pc_plus_4       = 32'h0000_0104;

        expected_candidate = '0;

        expected_candidate.valid       = 1'b1;
        expected_candidate.pc          = 32'h0000_0100;
        expected_candidate.instruction = if_id_q.instruction;
        expected_candidate.pc_plus_4   = 32'h0000_0104;

        expected_candidate.rs1_addr = 5'd5;
        expected_candidate.rs2_addr = 5'd6;
        expected_candidate.rd_addr  = 5'd7;
        expected_candidate.rs1_data = 32'h1234_5678;
        expected_candidate.rs2_data = 32'ha5a5_5a5a;
        expected_candidate.uses_rs1 = 1'b1;
        expected_candidate.uses_rs2 = 1'b1;

        expected_candidate.immediate = 32'b0;

        expected_candidate.ex_ctrl.operand_a_select = OPA_RS1;
        expected_candidate.ex_ctrl.operand_b_select = OPB_RS2;
        expected_candidate.ex_ctrl.alu_operation    = ALU_ADD;
        expected_candidate.ex_ctrl.branch_operation = BR_NONE;

        expected_candidate.mem_ctrl.memory_size = MEM_SIZE_WORD;

        expected_candidate.wb_ctrl.register_write  = 1'b1;
        expected_candidate.wb_ctrl.writeback_select = WB_EXEC;

        check_candidate(expected_candidate, "basic ADD integration");
// read while writing
        @(negedge clk);

        if_id_q             = '0;
        if_id_q.valid       = 1'b1;
        if_id_q.pc          = 32'h0000_0200;
        if_id_q.instruction = make_r_instruction(
            FUNCT7_BASE,
            5'd5,
            5'd5,
            FUNCT3_ADD_SUB,
            5'd8
        );
        if_id_q.pc_plus_4 = 32'h0000_0204;

        wb_bus                 = '0;
        wb_bus.valid           = 1'b1;
        wb_bus.rd_write_enable = 1'b1;
        wb_bus.rd_addr         = 5'd5;
        wb_bus.rd_data         = 32'hdead_beef;

        expected_candidate = '0;

        expected_candidate.valid       = 1'b1;
        expected_candidate.pc          = 32'h0000_0200;
        expected_candidate.instruction = if_id_q.instruction;
        expected_candidate.pc_plus_4   = 32'h0000_0204;

        expected_candidate.rs1_addr = 5'd5;
        expected_candidate.rs2_addr = 5'd5;
        expected_candidate.rd_addr  = 5'd8;
        expected_candidate.rs1_data = 32'hdead_beef;
        expected_candidate.rs2_data = 32'hdead_beef;
        expected_candidate.uses_rs1 = 1'b1;
        expected_candidate.uses_rs2 = 1'b1;

        expected_candidate.immediate = 32'b0;

        expected_candidate.ex_ctrl.operand_a_select = OPA_RS1;
        expected_candidate.ex_ctrl.operand_b_select = OPB_RS2;
        expected_candidate.ex_ctrl.alu_operation    = ALU_ADD;
        expected_candidate.ex_ctrl.branch_operation = BR_NONE;

        expected_candidate.mem_ctrl.memory_size = MEM_SIZE_WORD;

        expected_candidate.wb_ctrl.register_write   = 1'b1;
        expected_candidate.wb_ctrl.writeback_select = WB_EXEC;

        check_candidate(
            expected_candidate,
            "WB bypasses both rs1 and rs2 before write edge"
        );

        wb_bus = '0;

        // wb_bus.valid=0，即使地址匹配也不能旁路
        @(negedge clk);

        if_id_q             = '0;
        if_id_q.valid       = 1'b1;
        if_id_q.instruction = make_r_instruction(
            FUNCT7_BASE,
            5'd5,
            5'd5,
            FUNCT3_ADD_SUB,
            5'd8
        );

        wb_bus                 = '0;
        wb_bus.valid           = 1'b0;
        wb_bus.rd_write_enable = 1'b1;
        wb_bus.rd_addr         = 5'd5;
        wb_bus.rd_data         = 32'hcafe_babe;

        check_source_data(
            32'h1234_5678,
            32'h1234_5678,
            "invalid WB does not bypass"
        );

        wb_bus = '0;

        // rd_write_enable=0，也不能旁路
        @(negedge clk);

        wb_bus                 = '0;
        wb_bus.valid           = 1'b1;
        wb_bus.rd_write_enable = 1'b0;
        wb_bus.rd_addr         = 5'd5;
        wb_bus.rd_data         = 32'hface_feed;

        check_source_data(
            32'h1234_5678,
            32'h1234_5678,
            "non-writing WB does not bypass"
        );

        wb_bus = '0;

        // 写 x0 的 WB 不能把非零数据旁路给 x0
        @(negedge clk);

        if_id_q             = '0;
        if_id_q.valid       = 1'b1;
        if_id_q.instruction = make_r_instruction(
            FUNCT7_BASE,
            5'd0,
            5'd0,
            FUNCT3_ADD_SUB,
            5'd9
        );

        wb_bus                 = '0;
        wb_bus.valid           = 1'b1;
        wb_bus.rd_write_enable = 1'b1;
        wb_bus.rd_addr         = 5'd0;
        wb_bus.rd_data         = 32'hdead_beef;

        check_source_data(
            32'h0000_0000,
            32'h0000_0000,
            "x0 is never bypassed"
        );

        wb_bus = '0;

        // Match rs1 only, so rs2 must retain its regfile value.
        @(negedge clk);

        if_id_q             = '0;
        if_id_q.valid       = 1'b1;
        if_id_q.instruction = make_r_instruction(
            FUNCT7_BASE,
            5'd6,
            5'd5,
            FUNCT3_ADD_SUB,
            5'd8
        );

        wb_bus                 = '0;
        wb_bus.valid           = 1'b1;
        wb_bus.rd_write_enable = 1'b1;
        wb_bus.rd_addr         = 5'd5;
        wb_bus.rd_data         = 32'h1111_2222;

        check_source_data(
            32'h1111_2222,
            32'ha5a5_5a5a,
            "WB bypasses rs1 only"
        );

        wb_bus = '0;

        // Match rs2 only, so rs1 must retain its regfile value.
        @(negedge clk);

        wb_bus                 = '0;
        wb_bus.valid           = 1'b1;
        wb_bus.rd_write_enable = 1'b1;
        wb_bus.rd_addr         = 5'd6;
        wb_bus.rd_data         = 32'h3333_4444;

        check_source_data(
            32'h1234_5678,
            32'h3333_4444,
            "WB bypasses rs2 only"
        );

        wb_bus = '0;

        // ADDI x10, x5, -32 checks I-immediate sign extension.
        @(negedge clk);

        if_id_q             = '0;
        if_id_q.valid       = 1'b1;
        if_id_q.pc          = 32'h0000_0300;
        if_id_q.instruction = make_i_instruction(
            12'hfe0,
            5'd5,
            FUNCT3_ADD_SUB,
            5'd10,
            OPCODE_OP_IMM
        );
        if_id_q.pc_plus_4 = 32'h0000_0304;

        expected_candidate = '0;

        expected_candidate.valid       = 1'b1;
        expected_candidate.pc          = 32'h0000_0300;
        expected_candidate.instruction = if_id_q.instruction;
        expected_candidate.pc_plus_4   = 32'h0000_0304;

        expected_candidate.rs1_addr = 5'd5;
        expected_candidate.rs2_addr = 5'd0;
        expected_candidate.rd_addr  = 5'd10;
        expected_candidate.rs1_data = 32'h1234_5678;
        expected_candidate.rs2_data = 32'h0000_0000;
        expected_candidate.uses_rs1 = 1'b1;
        expected_candidate.uses_rs2 = 1'b0;

        expected_candidate.immediate = 32'hffff_ffe0;

        expected_candidate.ex_ctrl.operand_a_select = OPA_RS1;
        expected_candidate.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
        expected_candidate.ex_ctrl.alu_operation    = ALU_ADD;
        expected_candidate.ex_ctrl.branch_operation = BR_NONE;

        expected_candidate.mem_ctrl.memory_size = MEM_SIZE_WORD;

        expected_candidate.wb_ctrl.register_write   = 1'b1;
        expected_candidate.wb_ctrl.writeback_select = WB_EXEC;

        check_candidate(expected_candidate, "ADDI negative immediate");

        // Stale instruction bits in an invalid IF/ID entry are not an exception.
        if_id_q             = '0;
        if_id_q.instruction = 32'hffff_ffff;
        wb_bus              = '0;

        check_invalid_input("invalid IF/ID ignores illegal encoding");

        // A valid illegal instruction carries cause/value and no side effects.
        if_id_q             = '0;
        if_id_q.valid       = 1'b1;
        if_id_q.pc          = 32'h0000_0400;
        if_id_q.instruction = 32'hffff_ffff;
        if_id_q.pc_plus_4   = 32'h0000_0404;

        check_exception_state(
            EXCEPTION_CAUSE_ILLEGAL_INSTRUCTION,
            32'hffff_ffff,
            "illegal instruction metadata"
        );

        // ECALL and EBREAK are legal instructions that request distinct traps.
        if_id_q             = '0;
        if_id_q.valid       = 1'b1;
        if_id_q.pc          = 32'h0000_0500;
        if_id_q.instruction = INSTRUCTION_ECALL;
        if_id_q.pc_plus_4   = 32'h0000_0504;

        check_exception_state(
            EXCEPTION_CAUSE_ENVIRONMENT_CALL_M_MODE,
            32'b0,
            "ECALL creates Machine environment-call metadata"
        );

        if_id_q             = '0;
        if_id_q.valid       = 1'b1;
        if_id_q.pc          = 32'h0000_0600;
        if_id_q.instruction = INSTRUCTION_EBREAK;
        if_id_q.pc_plus_4   = 32'h0000_0604;

        check_exception_state(
            EXCEPTION_CAUSE_BREAKPOINT,
            32'b0,
            "EBREAK creates breakpoint metadata"
        );

        // An exception detected in IF poisons an otherwise legal instruction.
        if_id_q                   = '0;
        if_id_q.valid             = 1'b1;
        if_id_q.instruction       = make_r_instruction(
            FUNCT7_BASE,
            5'd6,
            5'd5,
            FUNCT3_ADD_SUB,
            5'd7
        );
        if_id_q.exception.valid   = 1'b1;
        if_id_q.exception.cause   = 32'd1;
        if_id_q.exception.value   = 32'h0000_1000;

        check_exception_state(
            32'd1,
            32'h0000_1000,
            "incoming IF exception poisons legal instruction"
        );

        // Existing IF exception metadata has priority over ID illegal decode.
        if_id_q                   = '0;
        if_id_q.valid             = 1'b1;
        if_id_q.instruction       = 32'hffff_ffff;
        if_id_q.exception.valid   = 1'b1;
        if_id_q.exception.cause   = 32'h1234_5678;
        if_id_q.exception.value   = 32'h8765_4321;

        check_exception_state(
            32'h1234_5678,
            32'h8765_4321,
            "incoming exception has priority over illegal decode"
        );

        if (error_count != 0) begin
            $fatal(
                1,
                "[FAIL] rv32_idu: %0d test(s) failed",
                error_count
            );
        end

        $display("[PASS] rv32_idu: current tests passed");
        $finish;
    end

    task automatic set_defaults;
        begin
            if_id_q = '0;
            wb_bus  = '0;
        end
    endtask

    task automatic write_register (
        input logic [4:0]  addr,
        input logic [31:0] data
    );
        begin
            @(negedge clk);

            wb_bus.valid           = 1'b1;
            wb_bus.rd_write_enable = 1'b1;
            wb_bus.rd_addr         = addr;
            wb_bus.rd_data         = data;

            @(posedge clk);
            #1ns;

            wb_bus = '0;
        end
    endtask

    function automatic logic [31:0] make_r_instruction (
        input logic [6:0] funct7,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd
    );
        begin
            make_r_instruction = {
                funct7,
                rs2,
                rs1,
                funct3,
                rd,
                OPCODE_OP
            };
        end
    endfunction

    function automatic logic [31:0] make_i_instruction (
        input logic [11:0] immediate_value,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3,
        input logic [4:0]  rd,
        input logic [6:0]  opcode
    );
        begin
            make_i_instruction = {
                immediate_value,
                rs1,
                funct3,
                rd,
                opcode
            };
        end
    endfunction

    task automatic check_candidate (
        input id_ex_t expected_value,
        input string  case_name
    );
        begin
            #1ns;

            if (id_ex_candidate !== expected_value) begin
                error_count++;

                $error(
                    "[FAIL] %s: candidate=%h expected=%h",
                    case_name,
                    id_ex_candidate,
                    expected_value
                );
            end
            else begin
                $display("[PASS] %s", case_name);
            end
        end
    endtask

    task automatic check_source_data (
        input logic [31:0] expected_rs1_data,
        input logic [31:0] expected_rs2_data,
        input string       case_name
    );
        begin
            #1ns;

            if (
                (id_ex_candidate.rs1_data !== expected_rs1_data) ||
                (id_ex_candidate.rs2_data !== expected_rs2_data)
            ) begin
                error_count++;

                $error(
                    "[FAIL] %s: rs1=%h/%h rs2=%h/%h",
                    case_name,
                    id_ex_candidate.rs1_data,
                    expected_rs1_data,
                    id_ex_candidate.rs2_data,
                    expected_rs2_data
                );
            end
            else begin
                $display("[PASS] %s", case_name);
            end
        end
    endtask

    task automatic check_invalid_input (
        input string case_name
    );
        begin
            #1ns;

            if (
                (id_ex_candidate.valid !== 1'b0) ||
                (id_ex_candidate.exception.valid !== 1'b0)
            ) begin
                error_count++;

                $error(
                    "[FAIL] %s: valid=%b exception_valid=%b",
                    case_name,
                    id_ex_candidate.valid,
                    id_ex_candidate.exception.valid
                );
            end
            else begin
                $display("[PASS] %s", case_name);
            end
        end
    endtask

    task automatic check_exception_state (
        input logic [31:0] expected_cause,
        input logic [31:0] expected_value,
        input string       case_name
    );
        begin
            #1ns;

            if (
                (id_ex_candidate.valid !== 1'b1) ||
                (id_ex_candidate.exception.valid !== 1'b1) ||
                (id_ex_candidate.exception.cause !== expected_cause) ||
                (id_ex_candidate.exception.value !== expected_value) ||
                (id_ex_candidate.uses_rs1 !== 1'b0) ||
                (id_ex_candidate.uses_rs2 !== 1'b0) ||
                (id_ex_candidate.ex_ctrl !== '0) ||
                (id_ex_candidate.mem_ctrl !== '0) ||
                (id_ex_candidate.wb_ctrl !== '0)
            ) begin
                error_count++;

                $error(
                    "[FAIL] %s: valid=%b exception=%h uses=%b%b ex=%h mem=%h wb=%h",
                    case_name,
                    id_ex_candidate.valid,
                    id_ex_candidate.exception,
                    id_ex_candidate.uses_rs1,
                    id_ex_candidate.uses_rs2,
                    id_ex_candidate.ex_ctrl,
                    id_ex_candidate.mem_ctrl,
                    id_ex_candidate.wb_ctrl
                );
            end
            else begin
                $display("[PASS] %s", case_name);
            end
        end
    endtask

endmodule
