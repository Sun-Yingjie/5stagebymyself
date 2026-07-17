module tb_rv32_csr_decoder;
    timeunit 1ns;
    timeprecision 1ps;

    import rv32_pkg::*;

    logic [31:0] instruction;
    csr_ctrl_t  csr_ctrl;
    logic       uses_rs1;
    int unsigned error_count;

    rv32_csr_decoder dut (
        .instruction(instruction),
        .csr_ctrl(csr_ctrl),
        .uses_rs1(uses_rs1)
    );

    initial begin
        error_count = 0;
        instruction = 32'b0;

        check_csr_decode(
            12'h300, 5'd5, FUNCT3_CSRRW, 5'd1,
            CSR_WRITE, 1'b0, 1'b1, 1'b1, 1'b1,
            "CSRRW reads old value and writes source"
        );
        check_csr_decode(
            12'h000, 5'd0, FUNCT3_CSRRW, 5'd0,
            CSR_WRITE, 1'b0, 1'b0, 1'b1, 1'b1,
            "CSRRW rd=x0 suppresses read but still writes zero"
        );

        check_csr_decode(
            12'hfff, 5'd3, FUNCT3_CSRRS, 5'd0,
            CSR_SET, 1'b0, 1'b1, 1'b1, 1'b1,
            "CSRRS rd=x0 still reads and sets bits"
        );
        check_csr_decode(
            12'h301, 5'd0, FUNCT3_CSRRS, 5'd7,
            CSR_SET, 1'b0, 1'b1, 1'b0, 1'b1,
            "CSRRS rs1=x0 is read-only"
        );

        check_csr_decode(
            12'h302, 5'd31, FUNCT3_CSRRC, 5'd8,
            CSR_CLEAR, 1'b0, 1'b1, 1'b1, 1'b1,
            "CSRRC clears bits from nonzero rs1 field"
        );
        check_csr_decode(
            12'h303, 5'd0, FUNCT3_CSRRC, 5'd0,
            CSR_CLEAR, 1'b0, 1'b1, 1'b0, 1'b1,
            "CSRRC rs1=x0 is read-only even with rd=x0"
        );

        check_csr_decode(
            12'h304, 5'd0, FUNCT3_CSRRWI, 5'd2,
            CSR_WRITE, 1'b1, 1'b1, 1'b1, 1'b0,
            "CSRRWI uimm=0 still writes"
        );
        check_csr_decode(
            12'h305, 5'd31, FUNCT3_CSRRWI, 5'd0,
            CSR_WRITE, 1'b1, 1'b0, 1'b1, 1'b0,
            "CSRRWI rd=x0 suppresses read"
        );

        check_csr_decode(
            12'h306, 5'd4, FUNCT3_CSRRSI, 5'd0,
            CSR_SET, 1'b1, 1'b1, 1'b1, 1'b0,
            "CSRRSI nonzero uimm writes even with rd=x0"
        );
        check_csr_decode(
            12'h307, 5'd0, FUNCT3_CSRRSI, 5'd9,
            CSR_SET, 1'b1, 1'b1, 1'b0, 1'b0,
            "CSRRSI uimm=0 is read-only"
        );

        check_csr_decode(
            12'h308, 5'd31, FUNCT3_CSRRCI, 5'd10,
            CSR_CLEAR, 1'b1, 1'b1, 1'b1, 1'b0,
            "CSRRCI clears bits from nonzero uimm"
        );
        check_csr_decode(
            12'h309, 5'd0, FUNCT3_CSRRCI, 5'd0,
            CSR_CLEAR, 1'b1, 1'b1, 1'b0, 1'b0,
            "CSRRCI uimm=0 remains a read"
        );

        check_invalid(INSTRUCTION_ECALL, "ECALL is not a CSR instruction");
        check_invalid(INSTRUCTION_EBREAK, "EBREAK is not a CSR instruction");
        check_invalid(32'h3020_0073, "MRET is not a CSR instruction");
        check_invalid(
            make_instruction(12'h300, 5'd1, 3'b100, 5'd2, OPCODE_SYSTEM),
            "reserved SYSTEM funct3 is not Zicsr"
        );
        check_invalid(
            make_instruction(12'h300, 5'd1, FUNCT3_CSRRW, 5'd2, OPCODE_OP_IMM),
            "CSR funct3 under non-SYSTEM opcode is invalid"
        );

        if (error_count != 0) begin
            $fatal(
                1,
                "[FAIL] rv32_csr_decoder: %0d test(s) failed",
                error_count
            );
        end

        $display("[PASS] rv32_csr_decoder: all tests passed");
        $finish;
    end

    task automatic check_csr_decode (
        input logic [11:0]    csr_address,
        input logic [4:0]     source_field,
        input logic [2:0]     funct3,
        input logic [4:0]     rd_addr,
        input csr_operation_e expected_operation,
        input logic           expected_use_immediate,
        input logic           expected_read_enable,
        input logic           expected_write_enable,
        input logic           expected_uses_rs1,
        input string          case_name
    );
        csr_ctrl_t expected_ctrl;
        begin
            instruction = make_instruction(
                csr_address,
                source_field,
                funct3,
                rd_addr,
                OPCODE_SYSTEM
            );

            expected_ctrl = '0;
            expected_ctrl.valid = 1'b1;
            expected_ctrl.operation = expected_operation;
            expected_ctrl.use_immediate = expected_use_immediate;
            expected_ctrl.read_enable = expected_read_enable;
            expected_ctrl.write_enable = expected_write_enable;

            #1ns;

            if ((csr_ctrl !== expected_ctrl) ||
                (uses_rs1 !== expected_uses_rs1)) begin
                error_count++;
                $error(
                    "[FAIL] %s: ctrl=%b uses_rs1=%b, expected=%b/%b",
                    case_name,
                    csr_ctrl,
                    uses_rs1,
                    expected_ctrl,
                    expected_uses_rs1
                );
            end
            else begin
                $display("[PASS] %s", case_name);
            end
        end
    endtask

    task automatic check_invalid (
        input logic [31:0] instruction_value,
        input string       case_name
    );
        csr_ctrl_t expected_ctrl;
        begin
            instruction = instruction_value;
            expected_ctrl = '0;

            #1ns;

            if ((csr_ctrl !== expected_ctrl) || (uses_rs1 !== 1'b0)) begin
                error_count++;
                $error(
                    "[FAIL] %s: ctrl=%b uses_rs1=%b, expected all zero",
                    case_name,
                    csr_ctrl,
                    uses_rs1
                );
            end
            else begin
                $display("[PASS] %s", case_name);
            end
        end
    endtask

    function automatic logic [31:0] make_instruction (
        input logic [11:0] csr_address,
        input logic [4:0]  source_field,
        input logic [2:0]  funct3,
        input logic [4:0]  rd_addr,
        input logic [6:0]  opcode
    );
        begin
            make_instruction = {
                csr_address,
                source_field,
                funct3,
                rd_addr,
                opcode
            };
        end
    endfunction
endmodule
