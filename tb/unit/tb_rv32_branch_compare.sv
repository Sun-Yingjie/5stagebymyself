module tb_rv32_branch_comparesv;
    timeunit 1ns;
    timeprecision 1ps;

    import rv32_pkg::*;

    logic [31:0]                    operand_a;
    logic [31:0]                    operand_b;
    rv32_pkg::branch_operation_e    branch_operation;
    logic                           branch_taken;
    int unsigned                    error_count;

    rv32_branch_compare dut(
        .operand_a(operand_a),
        .operand_b(operand_b),
        .branch_operation(branch_operation),
        .branch_taken(branch_taken)
    );

    initial begin
        
        operand_a = 0;
        operand_b = 0;
        branch_operation = BR_NONE;

        check_branch(
            BR_NONE,
            32'h0000_0001,
            32'h0000_0001,
            1'b0,
            "BR_NONE"
        );

        if (error_count != 0) begin
            $fatal(
                1,
                "[FAIL] rv32_branch_compare: %0d test(s) failed",
                error_count
            );
        end
        $$display("[PASS] rv32_branch_compare: all tests passed");
        $finish;
    end

    task automatic check_branch(
        input branch_operation_e    operation_value,
        input logic                 operand_a_value,
        input logic                 operand_b_value,
        input logic                 expected_value,
        input string                case_name
    );
        begin
            operand_a = operation_value;
            operand_b = operand_a_value;
            branch_operation = operand_b_value;
            
            #1ns;

            if (branch_taken !== expected_value) begin
                error_count++;
                $error(
                    "[FAIL] %s: branch_taken=%h, expected=%h",
                    case_name,
                    branch_taken,
                    expected_value
                );
            end
            else begin
                $display(
                    "[PASS] %s: branch_taken=%h",
                    case_name,
                    branch_taken
                );
            end
        end

    endtask //automatic
endmodule
