module tb_rv32_regfile;

    timeunit 1ns;
    timeprecision 1ps;

    logic        clk;

    logic [4:0]  rs1_addr;
    logic [31:0] rs1_data;
    logic [4:0]  rs2_addr;
    logic [31:0] rs2_data;

    logic        write_enable;
    logic [4:0]  write_addr;
    logic [31:0] write_data;

    int unsigned error_count;

    rv32_regfile dut (
        .clk          (clk),
        .rs1_addr     (rs1_addr),
        .rs1_data     (rs1_data),
        .rs2_addr     (rs2_addr),
        .rs2_data     (rs2_data),
        .write_enable (write_enable),
        .write_addr   (write_addr),
        .write_data   (write_data)
    );

    initial begin
        clk = 1'b0;
        forever #5ns clk = ~clk;
    end

    initial begin
        error_count  = 0;
        rs1_addr     = 5'd0;
        rs2_addr     = 5'd0;
        write_enable = 1'b0;
        write_addr   = 5'd0;
        write_data   = 32'b0;

        #1ns;

        write_enable = 1'b1;
        write_addr   = 5'd5;
        write_data   = 32'h1234_5678;

        @(posedge clk);
        #1ns;

        write_enable = 1'b0;

        check_read(
            5'd5,
            32'h1234_5678,
            5'd0,
            32'h0000_0000,
            "write x5 and read x5/x0"
        );

        write_register(1'b1, 5'd9, 32'ha5a5_5a5a);
        check_read(
            5'd5,
            32'h1234_5678,
            5'd9,
            32'ha5a5_5a5a,
            "read two different registers"
        );

        write_register(1'b1, 5'd0, 32'hdead_beef);
        check_read(
            5'd0,
            32'h0000_0000,
            5'd0,
            32'h0000_0000,
            "x0 remains zero after write attempt"
        );

        write_register(1'b0, 5'd5, 32'hffff_ffff);
        check_read(
            5'd5,
            32'h1234_5678,
            5'd9,
            32'ha5a5_5a5a,
            "write disabled preserves registers"
        );

        write_register(1'b1, 5'd5, 32'hcafe_babe);
        check_read(
            5'd5,
            32'hcafe_babe,
            5'd5,
            32'hcafe_babe,
            "overwrite and read same register on both ports"
        );

        write_register(1'b1, 5'd31, 32'h8000_0001);
        check_read(
            5'd31,
            32'h8000_0001,
            5'd9,
            32'ha5a5_5a5a,
            "write highest register address"
        );
        
        if (error_count != 0) begin
            $fatal(
                1,
                "[FAIL] rv32_regfile: %0d test(s) failed",
                error_count
            );
        end

        $display("[PASS] rv32_regfile: all tests passed");
        $finish;
    end

    task automatic write_register (
        input logic        enable,
        input logic [4:0]  addr,
        input logic [31:0] data
    );
        begin
            @(negedge clk);
            write_enable = enable;
            write_addr   = addr;
            write_data   = data;

            @(posedge clk);
            #1ns;

            write_enable = 1'b0;
        end
    endtask

    task automatic check_read (
        input logic [4:0]  rs1_addr_value,
        input logic [31:0] rs1_expected,
        input logic [4:0]  rs2_addr_value,
        input logic [31:0] rs2_expected,
        input string       case_name
    );
        begin
            rs1_addr = rs1_addr_value;
            rs2_addr = rs2_addr_value;

            #1ns;

            if ((rs1_data !== rs1_expected) ||
                (rs2_data !== rs2_expected)) begin
                error_count++;

                $error(
                    "[FAIL] %s: rs1_data=%h expected=%h, rs2_data=%h expected=%h",
                    case_name,
                    rs1_data,
                    rs1_expected,
                    rs2_data,
                    rs2_expected
                );
            end
            else begin
                $display("[PASS] %s", case_name);
            end
        end
    endtask
endmodule
