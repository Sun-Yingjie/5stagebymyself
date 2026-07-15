module tb_rv32_alu;
    timeunit 1ns;
    timeprecision 1ps;
    import rv32_pkg::*;

    logic [31:0]    operand_a;
    logic [31:0]    operand_b;
    alu_operation_e alu_operation;
    logic [31:0]    result;
    int unsigned    error_count;

    rv32_alu dut(
        .operand_a(operand_a),
        .operand_b(operand_b),
        .alu_operation(alu_operation),
        .result(result)
    );

    initial begin
        error_count = 0;
        operand_a = 0;
        operand_b = 0;
        alu_operation = ALU_ADD;

        check_alu(
            ALU_ADD,
            32'h0000_0001,
            32'h0000_0002,
            32'h0000_0003,
            "add normal"
        );

        check_alu(
            ALU_ADD,
            32'hffff_ffff,
            32'h0000_0001,
            32'h0000_0000,
            "add wrap"
        );

        check_alu(
            ALU_ADD,
            32'h7fff_ffff,
            32'h0000_0001,
            32'h8000_0000,
            "add signed overflow"
        );

        check_alu(
            ALU_SUB,
            32'h0000_0005,
            32'h0000_0003,
            32'h0000_0002,
            "sub normal"
        );

        check_alu(
            ALU_SUB,
            32'h0000_0000,
            32'h0000_0001,
            32'hffff_ffff,
            "sub wrap"
        );

        check_alu(
            ALU_AND,
            32'hffff_0000,
            32'h0f0f_0f0f,
            32'h0f0f_0000,
            "and"
        );

        check_alu(
            ALU_OR,
            32'hffff_0000,
            32'h0f0f_0f0f,
            32'hffff_0f0f,
            "or"
        );

        check_alu(
            ALU_XOR,
            32'hffff_0000,
            32'h0f0f_0f0f,
            32'hf0f0_0f0f,
            "xor"
        );

        check_alu(
            ALU_SLL,
            32'h0000_0001,
            32'h0000_0001,
            32'h0000_0002,
            "sll"
        );

        check_alu(
            ALU_SLL,
            32'h0000_0001,
            32'h0000_0020,
            32'h0000_0001,
            "sll masked shift amount"
        );

        check_alu(
            ALU_SRL,
            32'h8000_0000,
            32'h0000_0001,
            32'h4000_0000,
            "srl"
        );

        check_alu(
            ALU_SRA,
            32'h8000_0000,
            32'h0000_0001,
            32'hc000_0000,
            "sra"
        );

        check_alu(
            ALU_SRA,
            32'h8000_0000,
            32'h0000_0020,
            32'h8000_0000,
            "sra masked shift amount"
        );

        check_alu(
            ALU_SLT,
            32'hffff_ffff,
            32'h0000_0001,
            32'h0000_0001,
            "slt signed"
        );

        check_alu(
            ALU_SLTU,
            32'hffff_ffff,
            32'h0000_0001,
            32'h0000_0000,
            "sltu unsigned"
        );

        check_alu(
            ALU_SLT,
            32'h1234_5678,
            32'h1234_5678,
            32'h0000_0000,
            "slt equal"
        );

        if (error_count != 0) begin
            $fatal(
                1,
                "[FAIL] rv32_alu: %0d test(s) failed",
                error_count
            );
        end
        $display("[PASS] rv32_alu: all tests passed");
        $finish;
    end

    task automatic check_alu (
        input alu_operation_e operation_value,
        input logic [31:0]    operand_a_value,
        input logic [31:0]    operand_b_value,
        input logic [31:0]    expected_value,
        input string          case_name
    );
        begin
            alu_operation = operation_value;
            operand_a = operand_a_value;
            operand_b = operand_b_value;
            #1ns;
            if (result !== expected_value) begin
                error_count++;
                $error(
                    "[FAIL] %s: result=%h, expected=%h",
                    case_name,
                    result,
                    expected_value
                );
            end
            else begin
                $display(
                    "[PASS] %s: result=%h",
                    case_name,
                    result
                );
            end
        end
    endtask
endmodule
