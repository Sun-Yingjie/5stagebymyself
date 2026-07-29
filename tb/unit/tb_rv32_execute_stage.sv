module tb_rv32_execute_stage;
    timeunit 1ns;
    timeprecision 1ps;

    import rv32_pkg::*;

    logic clk;
    logic rst;

    id_ex_t          id_ex_q;
    forward_select_e rs1_forward_select;
    forward_select_e rs2_forward_select;
    logic [31:0]     ex_mem_forward_value;
    logic [31:0]     mem_wb_forward_value;
    pipe_action_e    ex_mem_action;
    logic            execute_kill;

    ex_mem_t  ex_mem_candidate;
    redirect_t ex_raw_redirect;
    logic      ex_multicycle_wait;
    logic      mdu_idle;
    logic      mdu_req_valid;
    logic      mdu_req_ready;
    logic      mdu_rsp_valid;
    logic      mdu_rsp_ready;
    logic [31:0] mdu_rsp_result;
    logic      mdu_kill;

    int unsigned case_count;
    int unsigned check_count;
    int unsigned error_count;

    rv32_execute_stage dut (
        .clk                 (clk),
        .rst                 (rst),
        .id_ex_q             (id_ex_q),
        .rs1_forward_select  (rs1_forward_select),
        .rs2_forward_select  (rs2_forward_select),
        .ex_mem_forward_value(ex_mem_forward_value),
        .mem_wb_forward_value(mem_wb_forward_value),
        .ex_mem_action       (ex_mem_action),
        .execute_kill        (execute_kill),
        .ex_mem_candidate    (ex_mem_candidate),
        .ex_raw_redirect     (ex_raw_redirect),
        .ex_multicycle_wait  (ex_multicycle_wait),
        .mdu_idle            (mdu_idle),
        .mdu_req_valid       (mdu_req_valid),
        .mdu_req_ready       (mdu_req_ready),
        .mdu_rsp_valid       (mdu_rsp_valid),
        .mdu_rsp_ready       (mdu_rsp_ready),
        .mdu_rsp_result      (mdu_rsp_result),
        .mdu_kill            (mdu_kill)
    );

    initial begin
        clk = 1'b0;
        forever #5ns clk = ~clk;
    end

    initial begin
        #10000ns;
        $fatal(1, "[FAIL] rv32_execute_stage: global timeout");
    end

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

    task automatic clear_inputs;
        begin
            id_ex_q              = '0;
            rs1_forward_select   = FWD_REG;
            rs2_forward_select   = FWD_REG;
            ex_mem_forward_value = '0;
            mem_wb_forward_value = '0;
            ex_mem_action        = PIPE_LOAD;
            execute_kill         = 1'b0;
        end
    endtask

    task automatic reset_dut;
        begin
            clear_inputs();
            rst = 1'b1;
            repeat (2) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
            #1ns;
            check_condition(mdu_idle, "reset: MDU did not return idle");
            check_condition(!mdu_kill, "reset: kill remained asserted");
            check_condition(!mdu_req_valid, "reset: request appeared after reset");
            check_condition(!mdu_rsp_valid, "reset: response appeared after reset");
        end
    endtask

    task automatic test_single_cycle_passthrough;
        ex_mem_t expected;
        begin
            case_count++;
            @(negedge clk);
            clear_inputs();

            id_ex_q.valid       = 1'b1;
            id_ex_q.pc          = 32'h0000_0100;
            id_ex_q.instruction = 32'h0020_81b3;
            id_ex_q.pc_plus_4   = 32'h0000_0104;
            id_ex_q.rs1_data    = 32'd7;
            id_ex_q.rs2_data    = 32'd9;
            id_ex_q.rd_addr     = 5'd3;
            id_ex_q.ex_ctrl.operand_a_select = OPA_RS1;
            id_ex_q.ex_ctrl.operand_b_select = OPB_RS2;
            id_ex_q.ex_ctrl.alu_operation    = ALU_ADD;
            id_ex_q.ex_ctrl.branch_operation = BR_NONE;
            id_ex_q.mem_ctrl.memory_size     = MEM_SIZE_WORD;
            id_ex_q.wb_ctrl.register_write   = 1'b1;
            id_ex_q.wb_ctrl.writeback_select = WB_EXEC;

            expected = '0;
            expected.valid       = id_ex_q.valid;
            expected.pc          = id_ex_q.pc;
            expected.instruction = id_ex_q.instruction;
            expected.pc_plus_4   = id_ex_q.pc_plus_4;
            expected.architectural_next_pc = id_ex_q.pc_plus_4;
            expected.exec_result = 32'd16;
            expected.store_data  = id_ex_q.rs2_data;
            expected.csr_ctrl     = id_ex_q.csr_ctrl;
            expected.csr_address  = id_ex_q.csr_address;
            expected.csr_source   = '0;
            expected.rd_addr      = id_ex_q.rd_addr;
            expected.mret         = id_ex_q.mret;
            expected.mem_ctrl     = id_ex_q.mem_ctrl;
            expected.wb_ctrl      = id_ex_q.wb_ctrl;
            expected.exception    = id_ex_q.exception;

            #1ns;
            check_condition(
                ex_mem_candidate === expected,
                "single-cycle: EX/MEM candidate did not pass through EXU"
            );
            check_condition(
                !ex_raw_redirect.valid &&
                (ex_raw_redirect.target == 32'd16),
                "single-cycle: ordinary ALU instruction redirected"
            );
            check_condition(
                !ex_multicycle_wait && !mdu_req_valid && mdu_idle,
                "single-cycle: ordinary ALU instruction activated MDU"
            );
        end
    endtask

    task automatic test_single_cycle_redirect;
        ex_mem_t expected;
        begin
            case_count++;
            @(negedge clk);
            clear_inputs();

            id_ex_q.valid       = 1'b1;
            id_ex_q.pc          = 32'h0000_0200;
            id_ex_q.instruction = 32'h0200_00ef;
            id_ex_q.pc_plus_4   = 32'h0000_0204;
            id_ex_q.rs2_data    = 32'ha5a5_5a5a;
            id_ex_q.immediate   = 32'h0000_0040;
            id_ex_q.rd_addr     = 5'd1;
            id_ex_q.ex_ctrl.operand_a_select = OPA_PC;
            id_ex_q.ex_ctrl.operand_b_select = OPB_IMMEDIATE;
            id_ex_q.ex_ctrl.alu_operation    = ALU_ADD;
            id_ex_q.ex_ctrl.branch_operation = BR_NONE;
            id_ex_q.ex_ctrl.is_jump          = 1'b1;
            id_ex_q.mem_ctrl.memory_size     = MEM_SIZE_WORD;
            id_ex_q.wb_ctrl.register_write   = 1'b1;
            id_ex_q.wb_ctrl.writeback_select = WB_PC_PLUS_4;

            expected = '0;
            expected.valid       = id_ex_q.valid;
            expected.pc          = id_ex_q.pc;
            expected.instruction = id_ex_q.instruction;
            expected.pc_plus_4   = id_ex_q.pc_plus_4;
            expected.architectural_next_pc = 32'h0000_0240;
            expected.exec_result = 32'h0000_0240;
            expected.store_data  = id_ex_q.rs2_data;
            expected.csr_ctrl     = id_ex_q.csr_ctrl;
            expected.csr_address  = id_ex_q.csr_address;
            expected.csr_source   = '0;
            expected.rd_addr      = id_ex_q.rd_addr;
            expected.mret         = id_ex_q.mret;
            expected.mem_ctrl     = id_ex_q.mem_ctrl;
            expected.wb_ctrl      = id_ex_q.wb_ctrl;
            expected.exception    = id_ex_q.exception;

            #1ns;
            check_condition(
                ex_mem_candidate === expected,
                "redirect: EX/MEM packet did not preserve EXU result"
            );
            check_condition(
                ex_raw_redirect.valid &&
                (ex_raw_redirect.target == 32'h0000_0240),
                "redirect: aligned JAL redirect was not propagated"
            );
            check_condition(
                !ex_multicycle_wait && !mdu_req_valid,
                "redirect: single-cycle jump activated MDU"
            );
        end
    endtask

    task automatic drive_mdu_operation(
        input mdu_operation_e operation,
        input logic [31:0]    rs1_data,
        input logic [31:0]    rs2_data,
        input forward_select_e rs1_select,
        input forward_select_e rs2_select,
        input logic [31:0]    ex_mem_value,
        input logic [31:0]    mem_wb_value
    );
        begin
            clear_inputs();
            id_ex_q.valid       = 1'b1;
            id_ex_q.pc          = 32'h0000_0300;
            id_ex_q.instruction = 32'h0220_81b3;
            id_ex_q.pc_plus_4   = 32'h0000_0304;
            id_ex_q.rs1_data    = rs1_data;
            id_ex_q.rs2_data    = rs2_data;
            id_ex_q.rd_addr     = 5'd3;
            id_ex_q.mdu_ctrl.valid     = 1'b1;
            id_ex_q.mdu_ctrl.operation = operation;
            id_ex_q.ex_ctrl.operand_a_select = OPA_RS1;
            id_ex_q.ex_ctrl.operand_b_select = OPB_RS2;
            id_ex_q.ex_ctrl.alu_operation    = ALU_ADD;
            id_ex_q.ex_ctrl.branch_operation = BR_NONE;
            id_ex_q.wb_ctrl.register_write   = 1'b1;
            id_ex_q.wb_ctrl.writeback_select = WB_EXEC;
            rs1_forward_select   = rs1_select;
            rs2_forward_select   = rs2_select;
            ex_mem_forward_value = ex_mem_value;
            mem_wb_forward_value = mem_wb_value;
            ex_mem_action        = PIPE_HOLD;
        end
    endtask

    task automatic test_mdu_forwarding_hold_and_consume;
        int unsigned wait_cycles;
        logic [31:0] held_result;
        begin
            case_count++;
            @(negedge clk);
            drive_mdu_operation(
                MDU_MUL,
                32'hdead_beef,
                32'hcafe_f00d,
                FWD_EX_MEM,
                FWD_MEM_WB,
                32'd7,
                32'd9
            );
            #1ns;
            check_condition(
                mdu_req_valid && mdu_req_ready,
                "MDU forwarding: request was not offered while idle"
            );
            check_condition(
                ex_multicycle_wait && !ex_mem_candidate.valid,
                "MDU forwarding: unfinished operation entered EX/MEM"
            );

            @(posedge clk);
            #1ns;
            check_condition(
                !mdu_idle && !mdu_req_valid && !mdu_rsp_valid,
                "MDU forwarding: request was not captured exactly once"
            );
            check_condition(
                ex_multicycle_wait && !ex_mem_candidate.valid,
                "MDU forwarding: running operation formed a candidate"
            );

            @(negedge clk);
            ex_mem_forward_value = 32'd11;
            mem_wb_forward_value = 32'd13;
            #1ns;

            wait_cycles = 0;
            while (!mdu_rsp_valid && (wait_cycles < 40)) begin
                check_condition(
                    !ex_mem_candidate.valid,
                    "MDU forwarding: candidate became valid before response"
                );
                @(negedge clk);
                #1ns;
                wait_cycles++;
            end

            check_condition(
                mdu_rsp_valid && !mdu_rsp_ready,
                "MDU hold: response did not wait while EX/MEM was not LOAD"
            );
            check_condition(
                (mdu_rsp_result == 32'd63) &&
                ex_mem_candidate.valid &&
                (ex_mem_candidate.exec_result == 32'd63),
                "MDU forwarding: result did not use captured forwarded operands"
            );
            check_condition(
                !ex_multicycle_wait && !mdu_idle,
                "MDU hold: response state reported incorrect wait/idle"
            );

            held_result = mdu_rsp_result;
            repeat (3) begin
                @(posedge clk);
                #1ns;
                check_condition(
                    mdu_rsp_valid &&
                    !mdu_rsp_ready &&
                    (mdu_rsp_result == held_result) &&
                    ex_mem_candidate.valid &&
                    (ex_mem_candidate.exec_result == held_result),
                    "MDU hold: unaccepted response changed or disappeared"
                );
            end

            @(negedge clk);
            ex_mem_action = PIPE_LOAD;
            #1ns;
            check_condition(
                mdu_rsp_valid &&
                mdu_rsp_ready &&
                ex_mem_candidate.valid &&
                (ex_mem_candidate.exec_result == 32'd63),
                "MDU consume: PIPE_LOAD did not accept the response"
            );

            @(posedge clk);
            #1ns;
            check_condition(
                mdu_idle && !mdu_rsp_valid,
                "MDU consume: response handshake did not return to idle"
            );

            @(negedge clk);
            clear_inputs();
            #1ns;
            check_condition(
                mdu_idle && !mdu_req_valid && !mdu_rsp_valid,
                "MDU consume: cleared EX input retriggered the operation"
            );
        end
    endtask

    task automatic test_exception_suppresses_mdu_request;
        begin
            case_count++;
            @(negedge clk);
            drive_mdu_operation(
                MDU_MUL,
                32'd3,
                32'd5,
                FWD_REG,
                FWD_REG,
                '0,
                '0
            );
            id_ex_q.exception.valid = 1'b1;
            id_ex_q.exception.cause = EXCEPTION_CAUSE_ILLEGAL_INSTRUCTION;
            id_ex_q.exception.value = id_ex_q.instruction;
            #1ns;

            check_condition(
                mdu_idle && mdu_req_ready && !mdu_req_valid,
                "exception: poisoned M instruction issued an MDU request"
            );
            check_condition(
                !ex_multicycle_wait && !ex_mem_candidate.valid,
                "exception: poisoned M instruction stalled or entered EX/MEM"
            );
            check_condition(
                ex_mem_candidate.exception.valid &&
                (ex_mem_candidate.exception.cause ==
                    EXCEPTION_CAUSE_ILLEGAL_INSTRUCTION),
                "exception: EX metadata was not preserved on invalid candidate"
            );

            @(posedge clk);
            #1ns;
            check_condition(
                mdu_idle && !mdu_rsp_valid,
                "exception: suppressed request changed MDU state"
            );

            @(negedge clk);
            clear_inputs();
        end
    endtask

    task automatic test_execute_kill;
        begin
            case_count++;
            @(negedge clk);
            drive_mdu_operation(
                MDU_DIVU,
                32'd100,
                32'd7,
                FWD_REG,
                FWD_REG,
                '0,
                '0
            );
            #1ns;
            check_condition(
                mdu_req_valid && mdu_req_ready,
                "execute kill: setup request did not fire"
            );
            @(posedge clk);
            #1ns;
            check_condition(!mdu_idle, "execute kill: operation did not start");

            repeat (3) @(posedge clk);
            @(negedge clk);
            execute_kill = 1'b1;
            #1ns;
            check_condition(
                mdu_kill &&
                !mdu_req_valid &&
                !mdu_rsp_valid &&
                !ex_multicycle_wait &&
                !ex_mem_candidate.valid,
                "execute kill: combinational outputs were not suppressed"
            );

            @(posedge clk);
            #1ns;
            check_condition(mdu_idle, "execute kill: MDU did not abort");

            @(negedge clk);
            id_ex_q      = '0;
            execute_kill = 1'b0;
            #1ns;
            check_condition(
                mdu_idle && !mdu_kill && !mdu_rsp_valid,
                "execute kill: aborted operation produced a late response"
            );
        end
    endtask

    task automatic test_reset_kill;
        begin
            case_count++;
            @(negedge clk);
            drive_mdu_operation(
                MDU_MUL,
                32'd12,
                32'd13,
                FWD_REG,
                FWD_REG,
                '0,
                '0
            );
            #1ns;
            check_condition(
                mdu_req_valid && mdu_req_ready,
                "reset kill: setup request did not fire"
            );
            @(posedge clk);
            #1ns;
            check_condition(!mdu_idle, "reset kill: operation did not start");

            repeat (3) @(posedge clk);
            @(negedge clk);
            rst = 1'b1;
            #1ns;
            check_condition(
                mdu_kill &&
                !mdu_req_valid &&
                !mdu_rsp_valid &&
                !ex_multicycle_wait &&
                !ex_mem_candidate.valid,
                "reset kill: reset did not suppress execute outputs"
            );

            @(posedge clk);
            #1ns;
            check_condition(mdu_idle, "reset kill: MDU did not reset idle");

            @(negedge clk);
            id_ex_q = '0;
            rst     = 1'b0;
            #1ns;
            check_condition(
                mdu_idle && !mdu_kill && !mdu_rsp_valid,
                "reset kill: reset operation produced a late response"
            );
        end
    endtask

    initial begin
        rst         = 1'b1;
        case_count  = 0;
        check_count = 0;
        error_count = 0;
        clear_inputs();

        reset_dut();
        test_single_cycle_passthrough();
        test_single_cycle_redirect();
        test_mdu_forwarding_hold_and_consume();
        test_exception_suppresses_mdu_request();
        test_execute_kill();
        test_reset_kill();

        if (error_count != 0) begin
            $fatal(
                1,
                "[FAIL] rv32_execute_stage: %0d errors across %0d cases and %0d checks",
                error_count,
                case_count,
                check_count
            );
        end

        $display(
            "[PASS] rv32_execute_stage: %0d cases and %0d checks passed",
            case_count,
            check_count
        );
        $finish;
    end
endmodule
