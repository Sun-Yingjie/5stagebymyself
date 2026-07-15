module tb_rv32_imm_gen;

    timeunit 1ns;
    timeprecision 1ps;

    import rv32_pkg::*;

    logic [31:0]     instruction;
    immediate_type_e immediate_type;
    logic [31:0]     immediate;
    int unsigned error_count;

    rv32_imm_gen dut (
        .instruction   (instruction),
        .immediate_type(immediate_type),
        .immediate     (immediate)
    );
    
    initial begin
        error_count   = 0;
        instruction   = 32'b0;
        immediate_type = IMM_NONE;

        check_imm(
            IMM_NONE,
            32'hffff_ffff,
            32'h0000_0000,
            "NONE"
        );

        check_imm(
            IMM_I,
            {12'h7ff, 20'b0},
            32'h0000_07ff,
            "I positive"
        );

        check_imm(
            IMM_I,
            {12'hfff, 20'b0},
            32'hffff_ffff,
            "I negative"
        );

        check_imm(
            IMM_S,
            {7'b000_0000, 13'b0, 5'b0_1100, 7'b0},
            32'h0000_000c,
            "S positive"
        );

        check_imm(
            IMM_S,
            {7'b111_1111, 13'b0, 5'b1_1100, 7'b0},
            32'hffff_fffc,
            "S negative"
        );

        check_imm(
            IMM_B,
            {
                1'b0,
                6'b00_0000,
                5'b0,
                5'b0,
                3'b0,
                4'b1000,
                1'b0,
                7'b0
            },
            32'h0000_0010,
            "B positive"
        );

        check_imm(
            IMM_B,
            {
                1'b1,
                6'b11_1111,
                5'b0,
                5'b0,
                3'b0,
                4'b1111,
                1'b1,
                7'b0
            },
            32'hffff_fffe,
            "B negative"
        );

        check_imm(
            IMM_U,
            {20'habcde, 12'b0},
            32'habcde_000,
            "U"
        );

        check_imm(
            IMM_J,
            32'h0010_0000,
            32'h0000_0800,
            "J positive"
        );

        check_imm(
            IMM_J,
            32'hffff_f000,
            32'hffff_fffe,
            "J negative"
        );

        if (error_count != 0) begin
            $fatal(
                1,
                "[FAIL] rv32_imm_gen: %0d test(s) failed",
                error_count
            );
        end

        $display("[PASS] rv32_imm_gen: all tests passed");
        $finish;
    end

    task automatic check_imm (
        input immediate_type_e type_value,
        input logic [31:0]     instruction_value,
        input logic [31:0]     expected_value,
        input string           case_name
    );
        begin
            instruction  = instruction_value;
            immediate_type = type_value;

            #1ns;

            if (immediate !== expected_value) begin
                error_count++;
                $error(
                    "[FAIL] %s: immediate=%h, expected=%h",
                    case_name,
                    immediate,
                    expected_value
                );
            end
            else begin
                $display(
                    "[PASS] %s: immediate=%h",
                    case_name,
                    immediate
                );
            end
        end
    endtask

endmodule
