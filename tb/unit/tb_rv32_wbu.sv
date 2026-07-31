module tb_rv32_wbu;
    timeunit 1ns;
    timeprecision 1ps;

    import rv32_pkg::*;

    logic    rst;
    mem_wb_t mem_wb_q;
    wb_bus_t wb_bus;

    logic        retire_valid;
    logic [31:0] retire_pc;
    logic [31:0] retire_instr;
    logic        retire_rd_we;
    logic [4:0]  retire_rd_addr;
    logic [31:0] retire_rd_data;

    int unsigned case_count;
    int unsigned check_count;
    int unsigned error_count;

    rv32_wbu dut (
        .rst           (rst),
        .mem_wb_q      (mem_wb_q),
        .wb_bus        (wb_bus),
        .retire_valid  (retire_valid),
        .retire_pc     (retire_pc),
        .retire_instr  (retire_instr),
        .retire_rd_we  (retire_rd_we),
        .retire_rd_addr(retire_rd_addr),
        .retire_rd_data(retire_rd_data)
    );

    task automatic check_condition(
        input logic  condition,
        input string message
    );
        begin
            check_count++;
            if (condition !== 1'b1) begin
                error_count++;
                $error("[FAIL] %s", message);
            end
        end
    endtask

    task automatic run_case(
        input string             case_name,
        input logic              rst_value,
        input logic              packet_valid,
        input logic              register_write,
        input logic [4:0]        rd_addr,
        input writeback_select_e writeback_select,
        input logic              exception_valid,
        input logic              expected_bus_valid,
        input logic              expected_retire_rd_we
    );
        logic [31:0] expected_data;
        begin
            case_count++;

            rst      = rst_value;
            mem_wb_q = '0;

            mem_wb_q.valid          = packet_valid;
            mem_wb_q.pc             = 32'h1000_0000 + case_count;
            mem_wb_q.instruction    = 32'h2000_0013 + case_count;
            mem_wb_q.pc_plus_4      = 32'h3000_0004 + case_count;
            mem_wb_q.exec_result    = 32'h4000_0000 + case_count;
            mem_wb_q.load_result    = 32'h5000_0000 + case_count;
            mem_wb_q.csr_read_data  = 32'h6000_0000 + case_count;
            mem_wb_q.rd_addr        = rd_addr;
            mem_wb_q.wb_ctrl.register_write   = register_write;
            mem_wb_q.wb_ctrl.writeback_select = writeback_select;
            mem_wb_q.exception.valid = exception_valid;
            mem_wb_q.exception.cause = 32'hdead_0000 + case_count;
            mem_wb_q.exception.value = 32'hbeef_0000 + case_count;

            case (writeback_select)
                WB_EXEC:      expected_data = mem_wb_q.exec_result;
                WB_LOAD:      expected_data = mem_wb_q.load_result;
                WB_PC_PLUS_4: expected_data = mem_wb_q.pc_plus_4;
                WB_CSR:       expected_data = mem_wb_q.csr_read_data;
                default:      expected_data = '0;
            endcase

            #1ns;

            check_condition(
                wb_bus.valid === expected_bus_valid,
                $sformatf("%s: wb_bus.valid", case_name)
            );
            check_condition(
                wb_bus.rd_write_enable === register_write,
                $sformatf("%s: wb_bus.rd_write_enable", case_name)
            );
            check_condition(
                wb_bus.rd_addr === rd_addr,
                $sformatf("%s: wb_bus.rd_addr", case_name)
            );
            check_condition(
                wb_bus.rd_data === expected_data,
                $sformatf("%s: wb_bus.rd_data", case_name)
            );

            check_condition(
                retire_valid === expected_bus_valid,
                $sformatf("%s: retire_valid", case_name)
            );
            check_condition(
                retire_pc === mem_wb_q.pc,
                $sformatf("%s: retire_pc", case_name)
            );
            check_condition(
                retire_instr === mem_wb_q.instruction,
                $sformatf("%s: retire_instr", case_name)
            );
            check_condition(
                retire_rd_we === expected_retire_rd_we,
                $sformatf("%s: retire_rd_we", case_name)
            );
            check_condition(
                retire_rd_addr === rd_addr,
                $sformatf("%s: retire_rd_addr", case_name)
            );
            check_condition(
                retire_rd_data === expected_data,
                $sformatf("%s: retire_rd_data", case_name)
            );
        end
    endtask

    initial begin
        rst         = 1'b0;
        mem_wb_q    = '0;
        case_count  = 0;
        check_count = 0;
        error_count = 0;

        run_case(
            "reset suppresses validity only",
            1'b1,
            1'b1,
            1'b1,
            5'd5,
            WB_EXEC,
            1'b0,
            1'b0,
            1'b0
        );
        run_case(
            "invalid packet suppresses validity only",
            1'b0,
            1'b0,
            1'b1,
            5'd6,
            WB_LOAD,
            1'b0,
            1'b0,
            1'b0
        );
        run_case(
            "faulting packet arrives invalid from MEM",
            1'b0,
            1'b0,
            1'b1,
            5'd13,
            WB_EXEC,
            1'b1,
            1'b0,
            1'b0
        );

        run_case(
            "WB_EXEC source",
            1'b0,
            1'b1,
            1'b1,
            5'd7,
            WB_EXEC,
            1'b0,
            1'b1,
            1'b1
        );
        run_case(
            "WB_LOAD source",
            1'b0,
            1'b1,
            1'b1,
            5'd8,
            WB_LOAD,
            1'b0,
            1'b1,
            1'b1
        );
        run_case(
            "WB_PC_PLUS_4 source",
            1'b0,
            1'b1,
            1'b1,
            5'd9,
            WB_PC_PLUS_4,
            1'b0,
            1'b1,
            1'b1
        );
        run_case(
            "WB_CSR source",
            1'b0,
            1'b1,
            1'b1,
            5'd10,
            WB_CSR,
            1'b0,
            1'b1,
            1'b1
        );

        run_case(
            "x0 masks retire write enable only",
            1'b0,
            1'b1,
            1'b1,
            5'd0,
            WB_EXEC,
            1'b0,
            1'b1,
            1'b0
        );
        run_case(
            "register-write disable preserves retirement",
            1'b0,
            1'b1,
            1'b0,
            5'd11,
            WB_LOAD,
            1'b0,
            1'b1,
            1'b0
        );
        run_case(
            "exception metadata is transparent to WBU",
            1'b0,
            1'b1,
            1'b1,
            5'd12,
            WB_CSR,
            1'b1,
            1'b1,
            1'b1
        );

        if (error_count != 0) begin
            $fatal(
                1,
                "[FAIL] rv32_wbu: %0d errors across %0d cases and %0d checks",
                error_count,
                case_count,
                check_count
            );
        end

        $display(
            "[PASS] rv32_wbu: %0d cases and %0d checks passed",
            case_count,
            check_count
        );
        $finish;
    end
endmodule
