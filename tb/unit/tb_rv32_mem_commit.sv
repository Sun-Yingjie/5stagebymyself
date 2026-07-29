module tb_rv32_mem_commit;
    timeunit 1ns;
    timeprecision 1ps;

    import rv32_pkg::*;

    logic       rst;
    ex_mem_t    ex_mem_q;

    logic       lsu_response_fire;
    logic [31:0] lsu_load_result;
    exception_t lsu_exception;

    logic        csr_access_illegal;
    logic [31:0] csr_read_data;
    logic [31:0] mret_target;
    logic [31:0] resume_pc;

    logic        mem_memory_access;
    logic        mem_stage_complete;
    exception_t  final_mem_exception;
    mem_wb_t     mem_wb_candidate;
    logic        mem_commit_candidate;
    logic        mret_commit;
    logic [31:0] effective_architectural_next_pc;
    logic [31:0] boundary_resume_pc;
    logic        mem_request_block;

    int unsigned case_count;
    int unsigned check_count;
    int unsigned error_count;

    rv32_mem_commit dut (
        .rst                            (rst),
        .ex_mem_q                       (ex_mem_q),
        .lsu_response_fire              (lsu_response_fire),
        .lsu_load_result                (lsu_load_result),
        .lsu_exception                  (lsu_exception),
        .csr_access_illegal             (csr_access_illegal),
        .csr_read_data                  (csr_read_data),
        .mret_target                    (mret_target),
        .resume_pc                      (resume_pc),
        .mem_memory_access              (mem_memory_access),
        .mem_stage_complete             (mem_stage_complete),
        .final_mem_exception            (final_mem_exception),
        .mem_wb_candidate               (mem_wb_candidate),
        .mem_commit_candidate           (mem_commit_candidate),
        .mret_commit                    (mret_commit),
        .effective_architectural_next_pc(effective_architectural_next_pc),
        .boundary_resume_pc             (boundary_resume_pc),
        .mem_request_block              (mem_request_block)
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

    // Give every carried field a visibly different value.  Whole-packet
    // comparisons then catch omissions as well as accidental field swaps.
    task automatic seed_inputs(input int unsigned seed);
        begin
            rst                = 1'b0;
            ex_mem_q           = '0;
            lsu_response_fire  = 1'b0;
            lsu_load_result    = 32'ha100_0000 + seed;
            lsu_exception      = '0;
            csr_access_illegal = 1'b0;
            csr_read_data      = 32'hb200_0000 + seed;
            mret_target        = 32'hc300_0000 + seed;
            resume_pc          = 32'hd400_0000 + seed;

            ex_mem_q.valid                  = 1'b1;
            ex_mem_q.pc                     = 32'h1100_0000 + seed;
            ex_mem_q.instruction            = 32'h2200_0013 + seed;
            ex_mem_q.pc_plus_4              = 32'h3300_0004 + seed;
            ex_mem_q.architectural_next_pc  = 32'h4400_0040 + seed;
            ex_mem_q.exec_result            = 32'h5500_0000 + seed;
            ex_mem_q.store_data             = 32'h6600_0000 + seed;
            ex_mem_q.csr_ctrl.valid         = 1'b0;
            ex_mem_q.csr_ctrl.operation     = CSR_CLEAR;
            ex_mem_q.csr_ctrl.use_immediate = 1'b1;
            ex_mem_q.csr_ctrl.read_enable   = 1'b1;
            ex_mem_q.csr_ctrl.write_enable  = 1'b1;
            ex_mem_q.csr_address            = 12'h7a5;
            ex_mem_q.csr_source             = 32'h7700_0000 + seed;
            ex_mem_q.rd_addr                = 5'd19;
            ex_mem_q.mret                   = 1'b0;
            ex_mem_q.mem_ctrl.memory_read   = 1'b0;
            ex_mem_q.mem_ctrl.memory_write  = 1'b0;
            ex_mem_q.mem_ctrl.memory_size   = MEM_SIZE_HALF;
            ex_mem_q.mem_ctrl.load_unsigned = 1'b1;
            ex_mem_q.wb_ctrl.register_write = 1'b1;
            ex_mem_q.wb_ctrl.writeback_select = WB_EXEC;
            ex_mem_q.exception              = '0;
        end
    endtask

    function automatic mem_wb_t make_expected_mem_wb(
        input logic       expected_valid,
        input exception_t expected_exception
    );
        mem_wb_t expected;
        begin
            expected = '0;
            expected.valid          = expected_valid;
            expected.pc             = ex_mem_q.pc;
            expected.instruction    = ex_mem_q.instruction;
            expected.pc_plus_4      = ex_mem_q.pc_plus_4;
            expected.exec_result    = ex_mem_q.exec_result;
            expected.load_result    = lsu_load_result;
            expected.csr_read_data  = csr_read_data;
            expected.rd_addr        = ex_mem_q.rd_addr;
            expected.wb_ctrl        = ex_mem_q.wb_ctrl;
            expected.exception      = expected_exception;
            make_expected_mem_wb    = expected;
        end
    endfunction

    task automatic check_case(
        input string       case_name,
        input logic        expected_memory_access,
        input logic        expected_stage_complete,
        input exception_t  expected_exception,
        input logic        expected_wb_valid,
        input logic        expected_commit_candidate,
        input logic        expected_mret_commit,
        input logic [31:0] expected_effective_next_pc,
        input logic [31:0] expected_boundary_pc,
        input logic        expected_request_block
    );
        mem_wb_t expected_mem_wb;
        begin
            expected_mem_wb = make_expected_mem_wb(
                expected_wb_valid,
                expected_exception
            );

            #1ns;

            check_condition(
                mem_memory_access === expected_memory_access,
                $sformatf("%s: mem_memory_access", case_name)
            );
            check_condition(
                mem_stage_complete === expected_stage_complete,
                $sformatf("%s: mem_stage_complete", case_name)
            );
            check_condition(
                final_mem_exception === expected_exception,
                $sformatf(
                    "%s: final exception expected=%h actual=%h",
                    case_name,
                    expected_exception,
                    final_mem_exception
                )
            );
            check_condition(
                mem_wb_candidate === expected_mem_wb,
                $sformatf(
                    "%s: MEM/WB packet expected=%h actual=%h",
                    case_name,
                    expected_mem_wb,
                    mem_wb_candidate
                )
            );
            check_condition(
                mem_commit_candidate === expected_commit_candidate,
                $sformatf("%s: mem_commit_candidate", case_name)
            );
            check_condition(
                mret_commit === expected_mret_commit,
                $sformatf("%s: mret_commit", case_name)
            );
            check_condition(
                effective_architectural_next_pc ===
                    expected_effective_next_pc,
                $sformatf(
                    "%s: effective_architectural_next_pc",
                    case_name
                )
            );
            check_condition(
                boundary_resume_pc === expected_boundary_pc,
                $sformatf("%s: boundary_resume_pc", case_name)
            );
            check_condition(
                mem_request_block === expected_request_block,
                $sformatf("%s: mem_request_block", case_name)
            );
        end
    endtask

    task automatic test_invalid_noise;
        exception_t expected_exception;
        begin
            case_count++;
            seed_inputs(case_count);

            ex_mem_q.valid                   = 1'b0;
            ex_mem_q.mret                    = 1'b1;
            ex_mem_q.mem_ctrl.memory_read    = 1'b1;
            ex_mem_q.mem_ctrl.memory_write   = 1'b1;
            ex_mem_q.exception.valid         = 1'b1;
            ex_mem_q.exception.cause         = 32'h0101_0101;
            ex_mem_q.exception.value         = 32'h0202_0202;
            csr_access_illegal                = 1'b1;
            lsu_exception.valid               = 1'b1;
            lsu_exception.cause               = 32'h0303_0303;
            lsu_exception.value               = 32'h0404_0404;
            lsu_response_fire                 = 1'b1;
            expected_exception                = '0;

            check_case(
                "invalid packet masks noisy side inputs",
                1'b0,
                1'b1,
                expected_exception,
                1'b0,
                1'b0,
                1'b0,
                mret_target,
                resume_pc,
                1'b0
            );
        end
    endtask

    task automatic test_normal_alu_control_flow;
        exception_t expected_exception;
        begin
            case_count++;
            seed_inputs(case_count);
            expected_exception = '0;

            check_case(
                "ordinary ALU carries architectural control-flow next PC",
                1'b0,
                1'b1,
                expected_exception,
                1'b1,
                1'b1,
                1'b0,
                ex_mem_q.architectural_next_pc,
                ex_mem_q.architectural_next_pc,
                1'b0
            );
        end
    endtask

    task automatic test_legal_csr_data;
        exception_t expected_exception;
        begin
            case_count++;
            seed_inputs(case_count);

            ex_mem_q.csr_ctrl.valid           = 1'b1;
            ex_mem_q.wb_ctrl.writeback_select = WB_CSR;
            csr_access_illegal                 = 1'b0;
            expected_exception                 = '0;

            check_case(
                "legal CSR read data enters MEM/WB packet",
                1'b0,
                1'b1,
                expected_exception,
                1'b1,
                1'b1,
                1'b0,
                ex_mem_q.architectural_next_pc,
                ex_mem_q.architectural_next_pc,
                1'b0
            );
        end
    endtask

    task automatic test_load_wait;
        exception_t expected_exception;
        begin
            case_count++;
            seed_inputs(case_count);

            ex_mem_q.mem_ctrl.memory_read     = 1'b1;
            ex_mem_q.wb_ctrl.writeback_select = WB_LOAD;
            lsu_response_fire                  = 1'b0;
            expected_exception                 = '0;

            check_case(
                "load waits for LSU response fire",
                1'b1,
                1'b0,
                expected_exception,
                1'b0,
                1'b0,
                1'b0,
                ex_mem_q.architectural_next_pc,
                resume_pc,
                1'b0
            );
        end
    endtask

    task automatic test_store_wait;
        exception_t expected_exception;
        begin
            case_count++;
            seed_inputs(case_count);

            ex_mem_q.mem_ctrl.memory_write    = 1'b1;
            ex_mem_q.wb_ctrl.register_write   = 1'b0;
            lsu_response_fire                  = 1'b0;
            expected_exception                 = '0;

            check_case(
                "store waits for LSU response fire",
                1'b1,
                1'b0,
                expected_exception,
                1'b0,
                1'b0,
                1'b0,
                ex_mem_q.architectural_next_pc,
                resume_pc,
                1'b0
            );
        end
    endtask

    task automatic test_load_fire;
        exception_t expected_exception;
        begin
            case_count++;
            seed_inputs(case_count);

            ex_mem_q.mem_ctrl.memory_read     = 1'b1;
            ex_mem_q.wb_ctrl.writeback_select = WB_LOAD;
            lsu_response_fire                  = 1'b1;
            expected_exception                 = '0;

            check_case(
                "load response fire completes packet",
                1'b1,
                1'b1,
                expected_exception,
                1'b1,
                1'b1,
                1'b0,
                ex_mem_q.architectural_next_pc,
                ex_mem_q.architectural_next_pc,
                1'b0
            );
        end
    endtask

    task automatic test_store_fire;
        exception_t expected_exception;
        begin
            case_count++;
            seed_inputs(case_count);

            ex_mem_q.mem_ctrl.memory_write  = 1'b1;
            ex_mem_q.wb_ctrl.register_write = 1'b0;
            lsu_response_fire                = 1'b1;
            expected_exception               = '0;

            check_case(
                "store response fire completes packet",
                1'b1,
                1'b1,
                expected_exception,
                1'b1,
                1'b1,
                1'b0,
                ex_mem_q.architectural_next_pc,
                ex_mem_q.architectural_next_pc,
                1'b0
            );
        end
    endtask

    task automatic test_early_exception_priority;
        exception_t expected_exception;
        begin
            case_count++;
            seed_inputs(case_count);

            ex_mem_q.mret            = 1'b1;
            ex_mem_q.exception.valid = 1'b1;
            ex_mem_q.exception.cause = EXCEPTION_CAUSE_BREAKPOINT;
            ex_mem_q.exception.value = 32'he100_0001;
            csr_access_illegal        = 1'b1;
            lsu_exception.valid       = 1'b1;
            lsu_exception.cause       = EXCEPTION_CAUSE_STORE_ACCESS_FAULT;
            lsu_exception.value       = 32'he300_0003;
            expected_exception        = ex_mem_q.exception;

            check_case(
                "early exception outranks CSR and LSU",
                1'b0,
                1'b1,
                expected_exception,
                1'b0,
                1'b0,
                1'b0,
                mret_target,
                resume_pc,
                1'b1
            );
        end
    endtask

    task automatic test_csr_exception_priority;
        exception_t expected_exception;
        begin
            case_count++;
            seed_inputs(case_count);

            ex_mem_q.csr_ctrl.valid = 1'b1;
            csr_access_illegal       = 1'b1;
            lsu_exception.valid      = 1'b1;
            lsu_exception.cause      = EXCEPTION_CAUSE_LOAD_ACCESS_FAULT;
            lsu_exception.value      = 32'he500_0005;

            expected_exception       = '0;
            expected_exception.valid = 1'b1;
            expected_exception.cause = EXCEPTION_CAUSE_ILLEGAL_INSTRUCTION;
            expected_exception.value = ex_mem_q.instruction;

            check_case(
                "CSR illegal outranks LSU exception",
                1'b0,
                1'b1,
                expected_exception,
                1'b0,
                1'b0,
                1'b0,
                ex_mem_q.architectural_next_pc,
                resume_pc,
                1'b1
            );
        end
    endtask

    task automatic test_lsu_exception_only;
        exception_t expected_exception;
        begin
            case_count++;
            seed_inputs(case_count);

            ex_mem_q.mem_ctrl.memory_read = 1'b1;
            lsu_response_fire              = 1'b1;
            lsu_exception.valid            = 1'b1;
            lsu_exception.cause            = EXCEPTION_CAUSE_LOAD_ACCESS_FAULT;
            lsu_exception.value            = 32'he700_0007;
            expected_exception             = lsu_exception;

            check_case(
                "LSU-only exception reaches MEM boundary",
                1'b1,
                1'b1,
                expected_exception,
                1'b0,
                1'b0,
                1'b0,
                ex_mem_q.architectural_next_pc,
                resume_pc,
                1'b1
            );
        end
    endtask

    task automatic test_reset_candidate_gate;
        exception_t expected_exception;
        begin
            case_count++;
            seed_inputs(case_count);

            rst                = 1'b1;
            expected_exception = '0;

            check_case(
                "reset gates commit candidate but preserves MEM/WB valid",
                1'b0,
                1'b1,
                expected_exception,
                1'b1,
                1'b0,
                1'b0,
                ex_mem_q.architectural_next_pc,
                resume_pc,
                1'b0
            );
        end
    endtask

    task automatic test_normal_mret;
        exception_t expected_exception;
        begin
            case_count++;
            seed_inputs(case_count);

            ex_mem_q.instruction = INSTRUCTION_MRET;
            ex_mem_q.mret        = 1'b1;
            expected_exception   = '0;

            check_case(
                "normal MRET selects target and blocks younger request",
                1'b0,
                1'b1,
                expected_exception,
                1'b1,
                1'b1,
                1'b1,
                mret_target,
                mret_target,
                1'b1
            );
        end
    endtask

    initial begin
        rst                = 1'b0;
        ex_mem_q           = '0;
        lsu_response_fire  = 1'b0;
        lsu_load_result    = '0;
        lsu_exception      = '0;
        csr_access_illegal = 1'b0;
        csr_read_data      = '0;
        mret_target        = '0;
        resume_pc          = '0;
        case_count         = 0;
        check_count        = 0;
        error_count        = 0;

        test_invalid_noise();
        test_normal_alu_control_flow();
        test_legal_csr_data();
        test_load_wait();
        test_store_wait();
        test_load_fire();
        test_store_fire();
        test_early_exception_priority();
        test_csr_exception_priority();
        test_lsu_exception_only();
        test_reset_candidate_gate();
        test_normal_mret();

        if (error_count != 0) begin
            $fatal(
                1,
                "[FAIL] rv32_mem_commit: %0d errors across %0d cases and %0d checks",
                error_count,
                case_count,
                check_count
            );
        end

        $display(
            "[PASS] rv32_mem_commit: %0d cases and %0d checks passed",
            case_count,
            check_count
        );
        $finish;
    end
endmodule
