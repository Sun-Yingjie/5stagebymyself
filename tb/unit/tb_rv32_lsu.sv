module tb_rv32_lsu;

    timeunit 1ns;
    timeprecision 1ps;

    import rv32_pkg::*;

    localparam int unsigned TEST_CASE_COUNT = 14;

    logic       clk;
    logic       rst;
    ex_mem_t    ex_mem_candidate;
    ex_mem_t    ex_mem_q;
    logic       ex_request_block;

    logic        dmem_req_valid;
    logic        dmem_req_ready;
    logic        dmem_req_write;
    logic [31:0] dmem_req_addr;
    logic [31:0] dmem_req_wdata;
    logic [3:0]  dmem_req_wstrb;

    logic        dmem_rsp_valid;
    logic        dmem_rsp_ready;
    logic [31:0] dmem_rsp_rdata;
    logic        dmem_rsp_error;

    logic       ex_request_wait;
    logic       mem_response_wait;
    mem_wb_t    mem_wb_candidate;
    exception_t mem_exception;

    int unsigned error_count;
    int unsigned check_count;

    rv32_lsu dut (
        .clk              (clk),
        .rst              (rst),
        .ex_mem_candidate (ex_mem_candidate),
        .ex_mem_q         (ex_mem_q),
        .ex_request_block (ex_request_block),
        .dmem_req_valid   (dmem_req_valid),
        .dmem_req_ready   (dmem_req_ready),
        .dmem_req_write   (dmem_req_write),
        .dmem_req_addr    (dmem_req_addr),
        .dmem_req_wdata   (dmem_req_wdata),
        .dmem_req_wstrb   (dmem_req_wstrb),
        .dmem_rsp_valid   (dmem_rsp_valid),
        .dmem_rsp_ready   (dmem_rsp_ready),
        .dmem_rsp_rdata   (dmem_rsp_rdata),
        .dmem_rsp_error   (dmem_rsp_error),
        .ex_request_wait  (ex_request_wait),
        .mem_response_wait(mem_response_wait),
        .mem_wb_candidate (mem_wb_candidate),
        .mem_exception    (mem_exception)
    );

    initial begin
        clk = 1'b0;
        forever #5ns clk = ~clk;
    end

    initial begin
        error_count = 0;
        check_count = 0;
        set_defaults();

        test_reset_and_idle_protocol();
        test_nonmemory_passthrough();
        test_request_qualification();
        test_external_request_block();
        test_load_request_backpressure();
        test_store_lane_matrix();
        test_load_extension_matrix();
        test_store_wait_and_single_completion();
        test_response_with_blocked_next_request();
        test_back_to_back_transactions();
        test_load_access_fault_suppresses_store();
        test_store_access_fault();
        test_incoming_exception_priority();
        test_reset_clears_outstanding_transaction();

        if (error_count != 0) begin
            $fatal(
                1,
                "[FAIL] rv32_lsu: %0d check(s) failed",
                error_count
            );
        end

        $display(
            "[PASS] rv32_lsu: %0d scenarios, %0d checks passed",
            TEST_CASE_COUNT,
            check_count
        );
        $finish;
    end

    task automatic set_defaults;
        begin
            rst              = 1'b0;
            ex_mem_candidate = '0;
            ex_mem_q         = '0;
            ex_request_block = 1'b0;
            dmem_req_ready   = 1'b0;
            dmem_rsp_valid   = 1'b0;
            dmem_rsp_rdata   = '0;
            dmem_rsp_error   = 1'b0;
        end
    endtask

    task automatic test_external_request_block;
        int unsigned errors_before;
        begin
            errors_before = error_count;
            reset_dut();

            set_memory_candidate(
                1'b0,
                1'b1,
                MEM_SIZE_WORD,
                1'b0,
                32'h0000_4800,
                32'hcafe_babe,
                32'h0000_0340
            );
            ex_request_block = 1'b1;
            dmem_req_ready   = 1'b1;
            settle();

            check_condition(
                !dmem_req_valid && !ex_request_wait && !dut.request_fire,
                "external block suppresses ready request and internal fire"
            );

            tick();
            check_condition(
                !dut.outstanding_q && !dmem_rsp_ready &&
                    !mem_response_wait,
                "blocked request cannot create internal outstanding state"
            );

            ex_request_block = 1'b0;
            dmem_req_ready   = 1'b0;
            settle();
            check_condition(
                dmem_req_valid && ex_request_wait,
                "releasing block exposes the preserved request"
            );

            dmem_req_ready = 1'b1;
            settle();
            check_condition(
                dmem_req_valid && !ex_request_wait,
                "released request can handshake normally"
            );

            tick();
            ex_mem_q         = ex_mem_candidate;
            ex_mem_candidate = '0;
            dmem_req_ready   = 1'b0;
            settle();
            check_condition(
                dut.outstanding_q && dmem_rsp_ready,
                "released handshake alone creates outstanding state"
            );

            ex_request_block = 1'b1;
            dmem_rsp_valid   = 1'b1;
            settle();
            check_condition(
                dmem_rsp_ready && !mem_response_wait,
                "request block does not prevent an old response completing"
            );
            tick();
            set_defaults();
            settle();
            check_condition(
                !dut.outstanding_q,
                "completed released request clears outstanding state"
            );

            report_case(errors_before, "external request block");
        end
    endtask

    task automatic settle;
        begin
            #1ns;
        end
    endtask

    task automatic tick;
        begin
            @(posedge clk);
            #1ns;
        end
    endtask

    task automatic reset_dut;
        begin
            set_defaults();
            rst = 1'b1;
            tick();

            check_condition(
                !dmem_req_valid && !dmem_rsp_ready,
                "reset: both memory channels must be inactive"
            );
            check_condition(
                !ex_request_wait && !mem_response_wait,
                "reset: no wait event may be asserted"
            );
            check_condition(
                !dut.outstanding_q,
                "reset: outstanding state must be clear"
            );

            rst = 1'b0;
            settle();
        end
    endtask

    task automatic set_memory_candidate(
        input logic         memory_read,
        input logic         memory_write,
        input memory_size_e memory_size,
        input logic         load_unsigned,
        input logic [31:0]  address,
        input logic [31:0]  store_data,
        input logic [31:0]  pc
    );
        begin
            ex_mem_candidate = '0;
            ex_mem_candidate.valid       = 1'b1;
            ex_mem_candidate.pc          = pc;
            ex_mem_candidate.instruction =
                memory_write ? 32'h0051_2023 : 32'h0001_2283;
            ex_mem_candidate.pc_plus_4   = pc + 32'd4;
            ex_mem_candidate.exec_result = address;
            ex_mem_candidate.store_data  = store_data;
            ex_mem_candidate.rd_addr     = memory_read ? 5'd5 : 5'd0;
            ex_mem_candidate.mem_ctrl.memory_read  = memory_read;
            ex_mem_candidate.mem_ctrl.memory_write = memory_write;
            ex_mem_candidate.mem_ctrl.memory_size  = memory_size;
            ex_mem_candidate.mem_ctrl.load_unsigned = load_unsigned;
            ex_mem_candidate.wb_ctrl.register_write = memory_read;
            if (memory_read) begin
                ex_mem_candidate.wb_ctrl.writeback_select = WB_LOAD;
            end else begin
                ex_mem_candidate.wb_ctrl.writeback_select = WB_EXEC;
            end
        end
    endtask

    task automatic accept_candidate_into_mem;
        begin
            dmem_req_ready = 1'b1;
            settle();
            check_condition(
                dmem_req_valid,
                "request acceptance: request must be valid"
            );

            tick();
            ex_mem_q         = ex_mem_candidate;
            ex_mem_candidate = '0;
            dmem_req_ready   = 1'b0;
            settle();

            check_condition(
                dut.outstanding_q,
                "request acceptance: transaction becomes outstanding"
            );
            check_condition(
                dmem_rsp_ready,
                "request acceptance: LSU must be ready for the response"
            );
        end
    endtask

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

    task automatic check_request(
        input logic        expected_valid,
        input logic        expected_write,
        input logic [31:0] expected_addr,
        input logic [31:0] expected_wdata,
        input logic [3:0]  expected_wstrb,
        input string       message
    );
        begin
            check_condition(
                dmem_req_valid === expected_valid,
                $sformatf(
                    "%s: valid=%b expected=%b",
                    message,
                    dmem_req_valid,
                    expected_valid
                )
            );

            if (expected_valid) begin
                check_condition(
                    dmem_req_write === expected_write,
                    $sformatf("%s: write direction is incorrect", message)
                );
                check_condition(
                    dmem_req_addr === expected_addr,
                    $sformatf(
                        "%s: addr=%h expected=%h",
                        message,
                        dmem_req_addr,
                        expected_addr
                    )
                );
                check_condition(
                    dmem_req_wdata === expected_wdata,
                    $sformatf(
                        "%s: wdata=%h expected=%h",
                        message,
                        dmem_req_wdata,
                        expected_wdata
                    )
                );
                check_condition(
                    dmem_req_wstrb === expected_wstrb,
                    $sformatf(
                        "%s: wstrb=%b expected=%b",
                        message,
                        dmem_req_wstrb,
                        expected_wstrb
                    )
                );
            end
        end
    endtask

    task automatic check_mem_wb_from_q(
        input logic        expected_valid,
        input logic [31:0] expected_load_result,
        input string       message
    );
        begin
            check_condition(
                mem_wb_candidate.valid === expected_valid,
                $sformatf(
                    "%s: valid=%b expected=%b",
                    message,
                    mem_wb_candidate.valid,
                    expected_valid
                )
            );

            if (expected_valid) begin
                check_condition(
                    mem_wb_candidate.pc === ex_mem_q.pc,
                    $sformatf("%s: pc is incorrect", message)
                );
                check_condition(
                    mem_wb_candidate.instruction === ex_mem_q.instruction,
                    $sformatf("%s: instruction is incorrect", message)
                );
                check_condition(
                    mem_wb_candidate.pc_plus_4 === ex_mem_q.pc_plus_4,
                    $sformatf("%s: pc_plus_4 is incorrect", message)
                );
                check_condition(
                    mem_wb_candidate.exec_result === ex_mem_q.exec_result,
                    $sformatf("%s: exec_result is incorrect", message)
                );
                check_condition(
                    mem_wb_candidate.load_result === expected_load_result,
                    $sformatf(
                        "%s: load=%h expected=%h",
                        message,
                        mem_wb_candidate.load_result,
                        expected_load_result
                    )
                );
                check_condition(
                    mem_wb_candidate.rd_addr === ex_mem_q.rd_addr,
                    $sformatf("%s: rd_addr is incorrect", message)
                );
                check_condition(
                    mem_wb_candidate.wb_ctrl === ex_mem_q.wb_ctrl,
                    $sformatf("%s: wb_ctrl is incorrect", message)
                );
                check_condition(
                    !mem_wb_candidate.exception.valid,
                    $sformatf("%s: unexpected exception", message)
                );
            end
        end
    endtask

    task automatic report_case(
        input int unsigned errors_before,
        input string       case_name
    );
        begin
            if (error_count == errors_before) begin
                $display("[PASS] %s", case_name);
            end
        end
    endtask

    task automatic check_store_case(
        input memory_size_e size,
        input logic [1:0]   offset,
        input logic [31:0]  expected_wdata,
        input logic [3:0]   expected_wstrb,
        input string        case_name
    );
        logic [31:0] address;
        begin
            address = 32'h0000_2000 + {30'b0, offset};
            set_memory_candidate(
                1'b0,
                1'b1,
                size,
                1'b0,
                address,
                32'haabb_ccdd,
                32'h0000_0100
            );
            settle();
            check_request(
                1'b1,
                1'b1,
                address,
                expected_wdata,
                expected_wstrb,
                case_name
            );
        end
    endtask

    task automatic run_load_case(
        input memory_size_e size,
        input logic         load_unsigned,
        input logic [1:0]   offset,
        input logic [31:0]  response_data,
        input logic [31:0]  expected_result,
        input string        case_name
    );
        logic [31:0] address;
        begin
            reset_dut();
            address = 32'h0000_3000 + {30'b0, offset};
            set_memory_candidate(
                1'b1,
                1'b0,
                size,
                load_unsigned,
                address,
                '0,
                32'h0000_0200 + {30'b0, offset}
            );
            accept_candidate_into_mem();

            dmem_rsp_valid = 1'b1;
            dmem_rsp_rdata = response_data;
            settle();

            check_condition(
                dmem_rsp_ready && !mem_response_wait,
                $sformatf("%s: response must complete", case_name)
            );
            check_mem_wb_from_q(1'b1, expected_result, case_name);
        end
    endtask

    task automatic test_reset_and_idle_protocol;
        int unsigned errors_before;
        begin
            errors_before = error_count;
            reset_dut();

            check_request(
                1'b0,
                1'b0,
                '0,
                '0,
                '0,
                "idle request channel"
            );
            check_condition(
                !dmem_rsp_ready && !ex_request_wait && !mem_response_wait,
                "idle: response and wait outputs must be low"
            );
            check_condition(
                !mem_wb_candidate.valid && !mem_exception.valid,
                "idle: no MEM/WB candidate or exception"
            );

            report_case(errors_before, "reset and idle protocol");
        end
    endtask

    task automatic test_nonmemory_passthrough;
        int unsigned errors_before;
        begin
            errors_before = error_count;
            reset_dut();

            ex_mem_q                 = '0;
            ex_mem_q.valid           = 1'b1;
            ex_mem_q.pc              = 32'h0000_0100;
            ex_mem_q.instruction     = 32'h0052_8333;
            ex_mem_q.pc_plus_4       = 32'h0000_0104;
            ex_mem_q.exec_result     = 32'h1234_5678;
            ex_mem_q.rd_addr         = 5'd6;
            ex_mem_q.wb_ctrl.register_write = 1'b1;
            ex_mem_q.wb_ctrl.writeback_select = WB_EXEC;
            settle();

            check_request(
                1'b0,
                1'b0,
                '0,
                '0,
                '0,
                "nonmemory instruction does not request data memory"
            );
            check_mem_wb_from_q(
                1'b1,
                32'b0,
                "nonmemory instruction passes through MEM"
            );
            check_condition(
                !ex_request_wait && !mem_response_wait &&
                    !mem_exception.valid,
                "nonmemory instruction has no LSU event"
            );

            report_case(errors_before, "nonmemory MEM/WB passthrough");
        end
    endtask

    task automatic test_request_qualification;
        int unsigned errors_before;
        begin
            errors_before = error_count;
            reset_dut();

            ex_mem_candidate = '0;
            ex_mem_candidate.mem_ctrl.memory_write = 1'b1;
            settle();
            check_condition(
                !dmem_req_valid,
                "invalid candidate must not issue a store"
            );

            set_memory_candidate(
                1'b0,
                1'b1,
                MEM_SIZE_WORD,
                1'b0,
                32'h0000_4000,
                32'hdead_beef,
                32'h0000_0300
            );
            ex_mem_candidate.exception.valid = 1'b1;
            settle();
            check_condition(
                !dmem_req_valid,
                "poisoned candidate must not issue a store"
            );

            ex_mem_candidate = '0;
            ex_mem_candidate.valid = 1'b1;
            settle();
            check_condition(
                !dmem_req_valid,
                "nonmemory candidate must not issue a request"
            );

            ex_mem_candidate = '0;
            dmem_rsp_valid   = 1'b1;
            dmem_rsp_error   = 1'b1;
            settle();
            check_condition(
                !dmem_rsp_ready && !mem_exception.valid,
                "response without outstanding request must be ignored"
            );

            report_case(errors_before, "request and response qualification");
        end
    endtask

    task automatic test_load_request_backpressure;
        int unsigned errors_before;
        int unsigned cycle;
        begin
            errors_before = error_count;
            reset_dut();
            set_memory_candidate(
                1'b1,
                1'b0,
                MEM_SIZE_BYTE,
                1'b0,
                32'h0000_5003,
                '0,
                32'h0000_0400
            );

            for (cycle = 0; cycle < 3; cycle++) begin
                settle();
                check_request(
                    1'b1,
                    1'b0,
                    32'h0000_5003,
                    32'b0,
                    4'b0000,
                    "backpressured load request remains stable"
                );
                check_condition(
                    ex_request_wait && !mem_response_wait &&
                        !dut.outstanding_q,
                    "backpressured request remains in EX"
                );
                tick();
            end

            dmem_req_ready = 1'b1;
            settle();
            check_condition(
                dmem_req_valid && !ex_request_wait,
                "load request handshakes when ready rises"
            );
            tick();

            ex_mem_q         = ex_mem_candidate;
            ex_mem_candidate = '0;
            dmem_req_ready   = 1'b0;
            settle();
            check_condition(
                dut.outstanding_q && dmem_rsp_ready && mem_response_wait,
                "accepted load waits in MEM for its response"
            );
            check_mem_wb_from_q(
                1'b0,
                '0,
                "load must not reach WB before its response"
            );

            report_case(errors_before, "load request backpressure");
        end
    endtask

    task automatic test_store_lane_matrix;
        int unsigned errors_before;
        begin
            errors_before = error_count;
            reset_dut();

            check_store_case(
                MEM_SIZE_BYTE, 2'd0, 32'h0000_00dd, 4'b0001, "SB lane 0"
            );
            check_store_case(
                MEM_SIZE_BYTE, 2'd1, 32'h0000_dd00, 4'b0010, "SB lane 1"
            );
            check_store_case(
                MEM_SIZE_BYTE, 2'd2, 32'h00dd_0000, 4'b0100, "SB lane 2"
            );
            check_store_case(
                MEM_SIZE_BYTE, 2'd3, 32'hdd00_0000, 4'b1000, "SB lane 3"
            );
            check_store_case(
                MEM_SIZE_HALF, 2'd0, 32'h0000_ccdd, 4'b0011, "SH lanes 1:0"
            );
            check_store_case(
                MEM_SIZE_HALF, 2'd2, 32'hccdd_0000, 4'b1100, "SH lanes 3:2"
            );
            check_store_case(
                MEM_SIZE_WORD, 2'd0, 32'haabb_ccdd, 4'b1111, "SW all lanes"
            );

            set_memory_candidate(
                1'b1,
                1'b0,
                MEM_SIZE_BYTE,
                1'b0,
                32'h0000_2003,
                32'hffff_ffff,
                32'h0000_0100
            );
            settle();
            check_request(
                1'b1,
                1'b0,
                32'h0000_2003,
                32'b0,
                4'b0000,
                "load request has no store lanes"
            );

            report_case(errors_before, "store byte-lane matrix");
        end
    endtask

    task automatic test_load_extension_matrix;
        int unsigned errors_before;
        begin
            errors_before = error_count;

            run_load_case(
                MEM_SIZE_BYTE, 1'b0, 2'd0,
                32'h80ff_7f01, 32'h0000_0001, "LB lane 0"
            );
            run_load_case(
                MEM_SIZE_BYTE, 1'b0, 2'd1,
                32'h80ff_7f01, 32'h0000_007f, "LB lane 1"
            );
            run_load_case(
                MEM_SIZE_BYTE, 1'b0, 2'd2,
                32'h80ff_7f01, 32'hffff_ffff, "LB lane 2 sign extension"
            );
            run_load_case(
                MEM_SIZE_BYTE, 1'b0, 2'd3,
                32'h80ff_7f01, 32'hffff_ff80, "LB lane 3 sign extension"
            );
            run_load_case(
                MEM_SIZE_BYTE, 1'b1, 2'd2,
                32'h80ff_7f01, 32'h0000_00ff, "LBU lane 2"
            );
            run_load_case(
                MEM_SIZE_BYTE, 1'b1, 2'd3,
                32'h80ff_7f01, 32'h0000_0080, "LBU lane 3"
            );
            run_load_case(
                MEM_SIZE_HALF, 1'b0, 2'd0,
                32'h80ff_7f01, 32'h0000_7f01, "LH lanes 1:0"
            );
            run_load_case(
                MEM_SIZE_HALF, 1'b0, 2'd2,
                32'h80ff_7f01, 32'hffff_80ff, "LH lanes 3:2 sign extension"
            );
            run_load_case(
                MEM_SIZE_HALF, 1'b1, 2'd2,
                32'h80ff_7f01, 32'h0000_80ff, "LHU lanes 3:2"
            );
            run_load_case(
                MEM_SIZE_WORD, 1'b0, 2'd0,
                32'h80ff_7f01, 32'h80ff_7f01, "LW full word"
            );

            report_case(errors_before, "load selection and extension matrix");
        end
    endtask

    task automatic test_store_wait_and_single_completion;
        int unsigned errors_before;
        int unsigned cycle;
        begin
            errors_before = error_count;
            reset_dut();
            set_memory_candidate(
                1'b0,
                1'b1,
                MEM_SIZE_WORD,
                1'b0,
                32'h0000_6000,
                32'hcafe_babe,
                32'h0000_0500
            );

            dmem_req_ready = 1'b1;
            tick();
            ex_mem_q         = ex_mem_candidate;
            ex_mem_candidate = '0;
            dmem_req_ready   = 1'b0;

            for (cycle = 0; cycle < 3; cycle++) begin
                settle();
                check_condition(
                    !dmem_req_valid && dmem_rsp_ready && mem_response_wait,
                    "accepted store waits without repeating its request"
                );
                check_mem_wb_from_q(
                    1'b0,
                    '0,
                    "store must not retire before completion response"
                );
                tick();
            end

            dmem_rsp_valid = 1'b1;
            dmem_rsp_rdata = 32'hdead_beef;
            settle();
            check_condition(
                dmem_rsp_ready && !mem_response_wait,
                "store completion response is accepted"
            );
            check_mem_wb_from_q(
                1'b1,
                32'b0,
                "completed store reaches WB exactly once"
            );
            check_condition(
                !mem_wb_candidate.wb_ctrl.register_write,
                "completed store does not write a register"
            );

            tick();
            dmem_rsp_valid = 1'b0;
            settle();
            check_condition(
                !dut.outstanding_q && !dmem_rsp_ready,
                "store transaction state clears after completion"
            );

            report_case(errors_before, "store waits and completes once");
        end
    endtask

    task automatic test_response_with_blocked_next_request;
        int unsigned errors_before;
        begin
            errors_before = error_count;
            reset_dut();
            set_memory_candidate(
                1'b1, 1'b0, MEM_SIZE_WORD, 1'b0,
                32'h0000_7000, '0, 32'h0000_0600
            );
            accept_candidate_into_mem();

            set_memory_candidate(
                1'b0, 1'b1, MEM_SIZE_BYTE, 1'b0,
                32'h0000_7101, 32'h0000_00aa, 32'h0000_0604
            );
            dmem_rsp_valid = 1'b1;
            dmem_rsp_rdata = 32'h1234_5678;
            dmem_req_ready = 1'b0;
            settle();

            check_mem_wb_from_q(
                1'b1,
                32'h1234_5678,
                "old response completes while next request is blocked"
            );
            check_request(
                1'b1,
                1'b1,
                32'h0000_7101,
                32'h0000_aa00,
                4'b0010,
                "next request is presented with old response"
            );
            check_condition(
                ex_request_wait && !mem_response_wait,
                "EX wait replaces MEM wait when next request is blocked"
            );

            tick();
            dmem_rsp_valid = 1'b0;
            ex_mem_q       = '0;
            settle();
            check_condition(
                !dut.outstanding_q && dmem_req_valid && ex_request_wait,
                "blocked next request remains in EX after old response"
            );

            dmem_req_ready = 1'b1;
            tick();
            check_condition(
                dut.outstanding_q,
                "blocked next request is accepted later"
            );

            report_case(
                errors_before,
                "response completion with blocked next request"
            );
        end
    endtask

    task automatic test_back_to_back_transactions;
        int unsigned errors_before;
        begin
            errors_before = error_count;
            reset_dut();
            set_memory_candidate(
                1'b1, 1'b0, MEM_SIZE_WORD, 1'b0,
                32'h0000_8000, '0, 32'h0000_0700
            );
            accept_candidate_into_mem();

            set_memory_candidate(
                1'b0, 1'b1, MEM_SIZE_HALF, 1'b0,
                32'h0000_8102, 32'h0000_beef, 32'h0000_0704
            );
            dmem_rsp_valid = 1'b1;
            dmem_rsp_rdata = 32'ha5a5_5a5a;
            dmem_req_ready = 1'b1;
            settle();

            check_mem_wb_from_q(
                1'b1,
                32'ha5a5_5a5a,
                "back-to-back old load response"
            );
            check_request(
                1'b1,
                1'b1,
                32'h0000_8102,
                32'hbeef_0000,
                4'b1100,
                "back-to-back new store request"
            );
            check_condition(
                !ex_request_wait && !mem_response_wait,
                "back-to-back cycle has no wait"
            );

            tick();
            ex_mem_q         = ex_mem_candidate;
            ex_mem_candidate = '0;
            dmem_rsp_valid   = 1'b0;
            dmem_req_ready   = 1'b0;
            settle();

            check_condition(
                dut.outstanding_q && dmem_rsp_ready && mem_response_wait,
                "new transaction replaces the completed transaction"
            );

            report_case(errors_before, "back-to-back response and request");
        end
    endtask

    task automatic test_load_access_fault_suppresses_store;
        int unsigned errors_before;
        begin
            errors_before = error_count;
            reset_dut();
            set_memory_candidate(
                1'b1, 1'b0, MEM_SIZE_WORD, 1'b0,
                32'h0000_9000, '0, 32'h0000_0800
            );
            accept_candidate_into_mem();

            set_memory_candidate(
                1'b0, 1'b1, MEM_SIZE_WORD, 1'b0,
                32'h0000_9100, 32'hdead_beef, 32'h0000_0804
            );
            dmem_rsp_valid = 1'b1;
            dmem_rsp_error = 1'b1;
            dmem_req_ready = 1'b1;
            settle();

            check_condition(
                mem_exception.valid &&
                    mem_exception.cause ===
                        EXCEPTION_CAUSE_LOAD_ACCESS_FAULT &&
                    mem_exception.value === 32'h0000_9000,
                "load access fault metadata"
            );
            check_condition(
                !mem_wb_candidate.valid,
                "faulting load invalidates the MEM/WB candidate"
            );
            check_condition(
                !dmem_req_valid && !ex_request_wait,
                "older load fault suppresses younger store request"
            );

            tick();
            check_condition(
                !dut.outstanding_q,
                "faulting response clears outstanding state"
            );

            report_case(
                errors_before,
                "load access fault suppresses younger store"
            );
        end
    endtask

    task automatic test_store_access_fault;
        int unsigned errors_before;
        begin
            errors_before = error_count;
            reset_dut();
            set_memory_candidate(
                1'b0, 1'b1, MEM_SIZE_WORD, 1'b0,
                32'h0000_a000, 32'hface_feed, 32'h0000_0900
            );
            accept_candidate_into_mem();

            dmem_rsp_valid = 1'b1;
            dmem_rsp_error = 1'b1;
            settle();

            check_condition(
                mem_exception.valid &&
                    mem_exception.cause ===
                        EXCEPTION_CAUSE_STORE_ACCESS_FAULT &&
                    mem_exception.value === 32'h0000_a000,
                "store access fault metadata"
            );
            check_condition(
                !mem_wb_candidate.valid,
                "faulting store invalidates the MEM/WB candidate"
            );

            report_case(errors_before, "store access fault");
        end
    endtask

    task automatic test_incoming_exception_priority;
        int unsigned errors_before;
        begin
            errors_before = error_count;
            reset_dut();

            ex_mem_q                   = '0;
            ex_mem_q.valid             = 1'b1;
            ex_mem_q.pc                = 32'h0000_0a00;
            ex_mem_q.exception.valid   = 1'b1;
            ex_mem_q.exception.cause   = 32'h1234_5678;
            ex_mem_q.exception.value   = 32'h8765_4321;
            ex_mem_q.wb_ctrl.register_write = 1'b1;

            set_memory_candidate(
                1'b0, 1'b1, MEM_SIZE_WORD, 1'b0,
                32'h0000_b000, 32'hdead_beef, 32'h0000_0a04
            );
            dmem_req_ready = 1'b1;
            settle();

            check_condition(
                mem_exception === ex_mem_q.exception,
                "incoming MEM exception metadata keeps priority"
            );
            check_condition(
                !mem_wb_candidate.valid,
                "incoming exception invalidates the MEM/WB candidate"
            );
            check_condition(
                !dmem_req_valid,
                "incoming exception suppresses younger memory request"
            );

            report_case(errors_before, "incoming exception priority");
        end
    endtask

    task automatic test_reset_clears_outstanding_transaction;
        int unsigned errors_before;
        begin
            errors_before = error_count;
            reset_dut();
            set_memory_candidate(
                1'b0, 1'b1, MEM_SIZE_WORD, 1'b0,
                32'h0000_c000, 32'h1234_5678, 32'h0000_0b00
            );
            accept_candidate_into_mem();

            check_condition(
                mem_response_wait,
                "pre-reset transaction must be waiting"
            );

            rst = 1'b1;
            settle();
            check_condition(
                !dmem_req_valid && !dmem_rsp_ready && !mem_response_wait,
                "reset immediately gates the active transaction"
            );
            tick();

            ex_mem_q = '0;
            rst      = 1'b0;
            settle();
            check_condition(
                !dut.outstanding_q && !dmem_rsp_ready &&
                    !mem_response_wait,
                "reset permanently clears outstanding state"
            );

            report_case(errors_before, "reset clears outstanding transaction");
        end
    endtask

endmodule
