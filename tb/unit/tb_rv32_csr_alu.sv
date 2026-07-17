module tb_rv32_csr_alu;
    timeunit 1ns;
    timeprecision 1ps;

    import rv32_pkg::*;

    csr_operation_e csr_operation;
    logic [31:0]    csr_read_data;
    logic [31:0]    csr_source;
    logic [31:0]    csr_write_data;
    int unsigned    error_count;

    rv32_csr_alu dut (
        .csr_operation(csr_operation),
        .csr_read_data(csr_read_data),
        .csr_source(csr_source),
        .csr_write_data(csr_write_data)
    );

    initial begin
        error_count = 0;
        csr_operation = CSR_WRITE;
        csr_read_data = 32'b0;
        csr_source = 32'b0;

        check_csr_alu(
            CSR_WRITE,
            32'haaaa_5555,
            32'h1234_5678,
            32'h1234_5678,
            "write ignores old value"
        );

        check_csr_alu(
            CSR_WRITE,
            32'hffff_ffff,
            32'h0000_0000,
            32'h0000_0000,
            "write zero"
        );

        check_csr_alu(
            CSR_SET,
            32'h0000_0000,
            32'h0000_0000,
            32'h0000_0000,
            "set zero"
        );

        check_csr_alu(
            CSR_SET,
            32'haaaa_0000,
            32'h5555_ffff,
            32'hffff_ffff,
            "set alternating bits"
        );

        check_csr_alu(
            CSR_SET,
            32'h1234_0000,
            32'h0000_5678,
            32'h1234_5678,
            "set ordinary data"
        );

        check_csr_alu(
            CSR_CLEAR,
            32'haaaa_5555,
            32'h0000_0000,
            32'haaaa_5555,
            "clear zero preserves old value"
        );

        check_csr_alu(
            CSR_CLEAR,
            32'hffff_ffff,
            32'hffff_ffff,
            32'h0000_0000,
            "clear all bits"
        );

        check_csr_alu(
            CSR_CLEAR,
            32'hffff_0000,
            32'h0f0f_0f0f,
            32'hf0f0_0000,
            "clear alternating bits"
        );

        check_csr_alu(
            CSR_CLEAR,
            32'h1234_5678,
            32'h0034_0078,
            32'h1200_5600,
            "clear ordinary data"
        );

        if (error_count != 0) begin
            $fatal(
                1,
                "[FAIL] rv32_csr_alu: %0d test(s) failed",
                error_count
            );
        end

        $display("[PASS] rv32_csr_alu: all tests passed");
        $finish;
    end

    task automatic check_csr_alu (
        input csr_operation_e operation_value,
        input logic [31:0]    read_data_value,
        input logic [31:0]    source_value,
        input logic [31:0]    expected_value,
        input string          case_name
    );
        begin
            csr_operation = operation_value;
            csr_read_data = read_data_value;
            csr_source = source_value;

            #1ns;

            if (csr_write_data !== expected_value) begin
                error_count++;
                $error(
                    "[FAIL] %s: csr_write_data=%h, expected=%h",
                    case_name,
                    csr_write_data,
                    expected_value
                );
            end
            else begin
                $display(
                    "[PASS] %s: csr_write_data=%h",
                    case_name,
                    csr_write_data
                );
            end
        end
    endtask
endmodule
