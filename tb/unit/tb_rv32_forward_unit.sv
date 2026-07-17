module tb_rv32_forward_unit;

    timeunit 1ns;
    timeprecision 1ps;

    import rv32_pkg::*;

    logic       id_valid;
    logic [4:0] id_rs1_addr;
    logic [4:0] id_rs2_addr;
    logic       id_uses_rs1;
    logic       id_uses_rs2;

    logic       ex_valid;
    logic [4:0] ex_rs1_addr;
    logic [4:0] ex_rs2_addr;
    logic       ex_uses_rs1;
    logic       ex_uses_rs2;
    logic [4:0] ex_rd_addr;
    logic       ex_result_late;

    logic       ex_mem_valid;
    logic [4:0] ex_mem_rd_addr;
    logic       ex_mem_register_write;
    logic       ex_mem_result_late;

    logic       mem_wb_valid;
    logic [4:0] mem_wb_rd_addr;
    logic       mem_wb_register_write;

    forward_select_e rs1_forward_select;
    forward_select_e rs2_forward_select;
    logic            late_result_hazard;

    int unsigned error_count;

    rv32_forward_unit dut (
        .id_valid             (id_valid),
        .id_rs1_addr          (id_rs1_addr),
        .id_rs2_addr          (id_rs2_addr),
        .id_uses_rs1          (id_uses_rs1),
        .id_uses_rs2          (id_uses_rs2),

        .ex_valid             (ex_valid),
        .ex_rs1_addr          (ex_rs1_addr),
        .ex_rs2_addr          (ex_rs2_addr),
        .ex_uses_rs1          (ex_uses_rs1),
        .ex_uses_rs2          (ex_uses_rs2),
        .ex_rd_addr           (ex_rd_addr),
        .ex_result_late       (ex_result_late),

        .ex_mem_valid         (ex_mem_valid),
        .ex_mem_rd_addr       (ex_mem_rd_addr),
        .ex_mem_register_write(ex_mem_register_write),
        .ex_mem_result_late   (ex_mem_result_late),

        .mem_wb_valid         (mem_wb_valid),
        .mem_wb_rd_addr       (mem_wb_rd_addr),
        .mem_wb_register_write(mem_wb_register_write),

        .rs1_forward_select   (rs1_forward_select),
        .rs2_forward_select   (rs2_forward_select),
        .late_result_hazard   (late_result_hazard)
    );

    initial begin
        error_count = 0;

        set_defaults();

        check_outputs(
            FWD_REG,
            FWD_REG,
            1'b0,
            "no dependency"
        );

        set_defaults();

        ex_valid    = 1'b1;
        ex_uses_rs1 = 1'b1;
        ex_rs1_addr = 5'd5;

        ex_mem_valid          = 1'b1;
        ex_mem_register_write = 1'b1;
        ex_mem_rd_addr        = 5'd5;
        ex_mem_result_late    = 1'b0;

        check_outputs(
            FWD_EX_MEM,
            FWD_REG,
            1'b0,
            "EX/MEM forwards to rs1"
        );

        set_defaults();

        ex_valid    = 1'b1;
        ex_uses_rs1 = 1'b1;
        ex_rs1_addr = 5'd5;

        ex_mem_valid          = 1'b1;
        ex_mem_register_write = 1'b1;
        ex_mem_rd_addr        = 5'd5;
        ex_mem_result_late    = 1'b0;

        mem_wb_valid          = 1'b1;
        mem_wb_register_write = 1'b1;
        mem_wb_rd_addr        = 5'd5;

        check_outputs(
            FWD_EX_MEM,
            FWD_REG,
            1'b0,
            "EX/MEM has priority over MEM/WB"
        );

        set_defaults();
        ex_valid              = 1'b1;
        ex_uses_rs1           = 1'b1;
        ex_rs1_addr           = 5'd7;
        mem_wb_valid          = 1'b1;
        mem_wb_register_write = 1'b1;
        mem_wb_rd_addr        = 5'd7;
        check_outputs(FWD_MEM_WB, FWD_REG, 1'b0,
                      "MEM/WB forwards to rs1");

        set_defaults();
        ex_valid              = 1'b1;
        ex_uses_rs2           = 1'b1;
        ex_rs2_addr           = 5'd8;
        ex_mem_valid          = 1'b1;
        ex_mem_register_write = 1'b1;
        ex_mem_rd_addr        = 5'd8;
        check_outputs(FWD_REG, FWD_EX_MEM, 1'b0,
                      "EX/MEM forwards to rs2");

        set_defaults();
        ex_valid              = 1'b1;
        ex_uses_rs1           = 1'b1;
        ex_uses_rs2           = 1'b1;
        ex_rs1_addr           = 5'd9;
        ex_rs2_addr           = 5'd10;
        ex_mem_valid          = 1'b1;
        ex_mem_register_write = 1'b1;
        ex_mem_rd_addr        = 5'd9;
        mem_wb_valid          = 1'b1;
        mem_wb_register_write = 1'b1;
        mem_wb_rd_addr        = 5'd10;
        check_outputs(FWD_EX_MEM, FWD_MEM_WB, 1'b0,
                      "rs1 and rs2 use different forward stages");

        set_defaults();
        ex_valid              = 1'b1;
        ex_rs1_addr           = 5'd5;
        ex_mem_valid          = 1'b1;
        ex_mem_register_write = 1'b1;
        ex_mem_rd_addr        = 5'd5;
        check_outputs(FWD_REG, FWD_REG, 1'b0,
                      "unused source does not forward");

        set_defaults();
        ex_valid              = 1'b1;
        ex_uses_rs1           = 1'b1;
        ex_rs1_addr           = 5'd5;
        ex_mem_register_write = 1'b1;
        ex_mem_rd_addr        = 5'd5;
        check_outputs(FWD_REG, FWD_REG, 1'b0,
                      "invalid EX/MEM producer does not forward");

        set_defaults();
        ex_valid              = 1'b1;
        ex_uses_rs1           = 1'b1;
        ex_rs1_addr           = 5'd5;
        ex_mem_valid          = 1'b1;
        ex_mem_rd_addr        = 5'd5;
        check_outputs(FWD_REG, FWD_REG, 1'b0,
                      "non-writing EX/MEM instruction does not forward");

        set_defaults();
        ex_valid              = 1'b1;
        ex_uses_rs1           = 1'b1;
        ex_rs1_addr           = 5'd0;
        ex_mem_valid          = 1'b1;
        ex_mem_register_write = 1'b1;
        ex_mem_rd_addr        = 5'd0;
        check_outputs(FWD_REG, FWD_REG, 1'b0,
                      "x0 is never a forward producer");

        set_defaults();
        ex_valid              = 1'b1;
        ex_uses_rs1           = 1'b1;
        ex_rs1_addr           = 5'd5;
        ex_mem_valid          = 1'b1;
        ex_mem_register_write = 1'b1;
        ex_mem_result_late    = 1'b1;
        ex_mem_rd_addr        = 5'd5;
        mem_wb_valid          = 1'b1;
        mem_wb_register_write = 1'b1;
        mem_wb_rd_addr        = 5'd5;
        check_outputs(FWD_REG, FWD_REG, 1'b0,
                      "EX/MEM late rs1 blocks older MEM/WB value");

        set_defaults();
        ex_valid              = 1'b1;
        ex_uses_rs2           = 1'b1;
        ex_rs2_addr           = 5'd6;
        ex_mem_valid          = 1'b1;
        ex_mem_register_write = 1'b1;
        ex_mem_result_late    = 1'b1;
        ex_mem_rd_addr        = 5'd6;
        mem_wb_valid          = 1'b1;
        mem_wb_register_write = 1'b1;
        mem_wb_rd_addr        = 5'd6;
        check_outputs(FWD_REG, FWD_REG, 1'b0,
                      "EX/MEM late rs2 blocks older MEM/WB value");

        set_defaults();
        ex_valid              = 1'b1;
        ex_uses_rs1           = 1'b1;
        ex_rs1_addr           = 5'd7;
        ex_mem_valid          = 1'b1;
        ex_mem_register_write = 1'b1;
        ex_mem_result_late    = 1'b1;
        ex_mem_rd_addr        = 5'd6;
        mem_wb_valid          = 1'b1;
        mem_wb_register_write = 1'b1;
        mem_wb_rd_addr        = 5'd7;
        check_outputs(FWD_MEM_WB, FWD_REG, 1'b0,
                      "unrelated EX/MEM late result does not block MEM/WB");

        set_defaults();
        ex_valid              = 1'b1;
        ex_uses_rs1           = 1'b1;
        ex_rs1_addr           = 5'd8;
        ex_mem_result_late    = 1'b1;
        ex_mem_rd_addr        = 5'd8;
        mem_wb_valid          = 1'b1;
        mem_wb_register_write = 1'b1;
        mem_wb_rd_addr        = 5'd8;
        check_outputs(FWD_MEM_WB, FWD_REG, 1'b0,
                      "invalid EX/MEM late result does not block MEM/WB");

        set_defaults();
        ex_valid              = 1'b1;
        ex_uses_rs1           = 1'b1;
        ex_rs1_addr           = 5'd9;
        ex_mem_valid          = 1'b1;
        ex_mem_result_late    = 1'b1;
        ex_mem_rd_addr        = 5'd9;
        mem_wb_valid          = 1'b1;
        mem_wb_register_write = 1'b1;
        mem_wb_rd_addr        = 5'd9;
        check_outputs(FWD_MEM_WB, FWD_REG, 1'b0,
                      "non-writing EX/MEM late result does not block MEM/WB");

        set_defaults();
        id_valid       = 1'b1;
        id_uses_rs1    = 1'b1;
        id_rs1_addr    = 5'd12;
        ex_valid       = 1'b1;
        ex_result_late = 1'b1;
        ex_rd_addr     = 5'd12;
        check_outputs(FWD_REG, FWD_REG, 1'b1,
                      "late-result hazard on ID rs1 (load)");

        set_defaults();
        id_valid       = 1'b1;
        id_uses_rs2    = 1'b1;
        id_rs2_addr    = 5'd13;
        ex_valid       = 1'b1;
        ex_result_late = 1'b1;
        ex_rd_addr     = 5'd13;
        check_outputs(FWD_REG, FWD_REG, 1'b1,
                      "late-result hazard on ID rs2 (CSR old value)");

        set_defaults();
        id_valid       = 1'b1;
        id_uses_rs1    = 1'b1;
        id_rs1_addr    = 5'd14;
        ex_valid       = 1'b1;
        ex_result_late = 1'b1;
        ex_rd_addr     = 5'd0;
        check_outputs(FWD_REG, FWD_REG, 1'b0,
                      "late-result rd=x0 causes no hazard");

        set_defaults();
        id_valid       = 1'b1;
        id_rs1_addr    = 5'd15;
        ex_valid       = 1'b1;
        ex_result_late = 1'b1;
        ex_rd_addr     = 5'd15;
        check_outputs(FWD_REG, FWD_REG, 1'b0,
                      "CSR immediate field is not an rs1 dependency");

        set_defaults();
        id_valid       = 1'b1;
        id_uses_rs1    = 1'b1;
        id_rs1_addr    = 5'd16;
        ex_valid       = 1'b1;
        ex_rd_addr     = 5'd16;
        check_outputs(FWD_REG, FWD_REG, 1'b0,
                      "non-late EX producer causes no hazard");

        set_defaults();
        id_valid       = 1'b1;
        id_uses_rs1    = 1'b1;
        id_rs1_addr    = 5'd17;
        ex_result_late = 1'b1;
        ex_rd_addr     = 5'd17;
        check_outputs(FWD_REG, FWD_REG, 1'b0,
                      "invalid EX late producer causes no hazard");

        if (error_count != 0) begin
            $fatal(
                1,
                "[FAIL] rv32_forward_unit: %0d test(s) failed",
                error_count
            );
        end

        $display("[PASS] rv32_forward_unit: all tests passed");
        $finish;
    end

    task automatic set_defaults;
        begin
            id_valid              = 1'b0;
            id_rs1_addr           = 5'd0;
            id_rs2_addr           = 5'd0;
            id_uses_rs1           = 1'b0;
            id_uses_rs2           = 1'b0;

            ex_valid              = 1'b0;
            ex_rs1_addr           = 5'd0;
            ex_rs2_addr           = 5'd0;
            ex_uses_rs1           = 1'b0;
            ex_uses_rs2           = 1'b0;
            ex_rd_addr            = 5'd0;
            ex_result_late        = 1'b0;

            ex_mem_valid          = 1'b0;
            ex_mem_rd_addr        = 5'd0;
            ex_mem_register_write = 1'b0;
            ex_mem_result_late    = 1'b0;

            mem_wb_valid          = 1'b0;
            mem_wb_rd_addr        = 5'd0;
            mem_wb_register_write = 1'b0;
        end
    endtask

    task automatic check_outputs (
        input forward_select_e expected_rs1_select,
        input forward_select_e expected_rs2_select,
        input logic            expected_late_result_hazard,
        input string           case_name
    );
        begin
            #1ns;

            if (
                (rs1_forward_select !== expected_rs1_select) ||
                (rs2_forward_select !== expected_rs2_select) ||
                (late_result_hazard !== expected_late_result_hazard)
            ) begin
                error_count++;

                $error(
                    "[FAIL] %s: rs1=%b expected=%b, rs2=%b expected=%b, hazard=%b expected=%b",
                    case_name,
                    rs1_forward_select,
                    expected_rs1_select,
                    rs2_forward_select,
                    expected_rs2_select,
                    late_result_hazard,
                    expected_late_result_hazard
                );
            end
            else begin
                $display("[PASS] %s", case_name);
            end
        end
    endtask

endmodule
