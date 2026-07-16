module tb_rv32_ifu;

    timeunit 1ns;
    timeprecision 1ps;

    import rv32_pkg::*;

    localparam logic [31:0] TEST_RESET_VECTOR = 32'h0000_1000;
    localparam int unsigned TEST_CASE_COUNT    = 13;

    logic          clk;
    logic          rst;
    fetch_action_e fetch_action;
    redirect_t     qualified_redirect;
    logic          if_id_ready;

    logic          imem_req_valid;
    logic          imem_req_ready;
    logic [31:0]   imem_req_addr;

    logic          imem_rsp_valid;
    logic          imem_rsp_ready;
    logic [31:0]   imem_rsp_data;
    logic          imem_rsp_error;

    if_id_t if_id_candidate;
    logic   fetch_response_available;

    int unsigned error_count;
    int unsigned check_count;

    rv32_ifu #(
        .RESET_VECTOR(TEST_RESET_VECTOR)
    ) dut (
        .clk                     (clk),
        .rst                     (rst),
        .fetch_action            (fetch_action),
        .qualified_redirect      (qualified_redirect),
        .if_id_ready             (if_id_ready),
        .imem_req_valid          (imem_req_valid),
        .imem_req_ready          (imem_req_ready),
        .imem_req_addr           (imem_req_addr),
        .imem_rsp_valid          (imem_rsp_valid),
        .imem_rsp_ready          (imem_rsp_ready),
        .imem_rsp_data           (imem_rsp_data),
        .imem_rsp_error          (imem_rsp_error),
        .if_id_candidate         (if_id_candidate),
        .fetch_response_available(fetch_response_available)
    );

    initial begin
        clk = 1'b0;
        forever #5ns clk = ~clk;
    end

    initial begin
        error_count = 0;
        check_count = 0;
        set_defaults();

        test_reset_and_first_request();
        test_request_backpressure();
        test_response_backpressure_and_metadata();
        test_continuous_sequential_fetch();
        test_instruction_access_error();
        test_redirect_without_active_transaction();
        test_redirect_before_pending_request_accepts();
        test_redirect_as_pending_request_accepts();
        test_redirect_while_response_is_pending();
        test_redirect_with_same_cycle_response();
        test_latest_redirect_wins();
        test_redirect_replaces_pending_redirect_request();
        test_reset_clears_transaction_state();

        if (error_count != 0) begin
            $fatal(
                1,
                "[FAIL] rv32_ifu: %0d check(s) failed",
                error_count
            );
        end

        $display(
            "[PASS] rv32_ifu: %0d scenarios, %0d checks passed",
            TEST_CASE_COUNT,
            check_count
        );
        $finish;
    end

    task automatic set_defaults;
        begin
            rst                       = 1'b0;
            fetch_action              = FETCH_HOLD;
            qualified_redirect        = '0;
            if_id_ready               = 1'b0;
            imem_req_ready            = 1'b0;
            imem_rsp_valid            = 1'b0;
            imem_rsp_data             = '0;
            imem_rsp_error            = 1'b0;
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
            if (!rst) begin
                check_internal_invariants();
            end
        end
    endtask

    task automatic reset_dut;
        begin
            set_defaults();
            rst = 1'b1;
            tick();

            check_condition(
                !imem_req_valid,
                "reset: request valid must be low"
            );
            check_condition(
                !imem_rsp_ready,
                "reset: response ready must be low"
            );
            check_condition(
                !fetch_response_available && !if_id_candidate.valid,
                "reset: no response may reach IF/ID"
            );

            rst = 1'b0;
            settle();
        end
    endtask

    task automatic accept_initial_request;
        begin
            check_request(
                1'b1,
                TEST_RESET_VECTOR,
                "accept initial request: reset-vector request"
            );

            imem_req_ready = 1'b1;
            settle();
            tick();
            imem_req_ready = 1'b0;
            settle();

            check_condition(
                !imem_req_valid,
                "accept initial request: no second request before response"
            );
        end
    endtask

    task automatic drive_redirect(input logic [31:0] target);
        begin
            fetch_action             = FETCH_REDIRECT;
            qualified_redirect.valid = 1'b1;
            qualified_redirect.target = target;
        end
    endtask

    task automatic clear_redirect;
        begin
            fetch_action              = FETCH_HOLD;
            qualified_redirect        = '0;
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
        input logic [31:0] expected_addr,
        input string       message
    );
        begin
            check_condition(
                imem_req_valid === expected_valid,
                $sformatf(
                    "%s: valid=%b expected=%b",
                    message,
                    imem_req_valid,
                    expected_valid
                )
            );

            if (expected_valid) begin
                check_condition(
                    imem_req_addr === expected_addr,
                    $sformatf(
                        "%s: addr=%h expected=%h",
                        message,
                        imem_req_addr,
                        expected_addr
                    )
                );
            end
        end
    endtask

    task automatic check_candidate(
        input logic [31:0] expected_pc,
        input logic [31:0] expected_instruction,
        input logic        expected_error,
        input string       message
    );
        begin
            check_condition(
                if_id_candidate.valid,
                $sformatf("%s: candidate must be valid", message)
            );
            check_condition(
                if_id_candidate.pc === expected_pc,
                $sformatf(
                    "%s: pc=%h expected=%h",
                    message,
                    if_id_candidate.pc,
                    expected_pc
                )
            );
            check_condition(
                if_id_candidate.instruction === expected_instruction,
                $sformatf(
                    "%s: instruction=%h expected=%h",
                    message,
                    if_id_candidate.instruction,
                    expected_instruction
                )
            );
            check_condition(
                if_id_candidate.pc_plus_4 === (expected_pc + 32'd4),
                $sformatf("%s: pc_plus_4 is incorrect", message)
            );
            check_condition(
                if_id_candidate.exception.valid === expected_error,
                $sformatf("%s: exception.valid is incorrect", message)
            );

            if (expected_error) begin
                check_condition(
                    if_id_candidate.exception.cause ===
                        EXCEPTION_CAUSE_INSTRUCTION_ACCESS_FAULT,
                    $sformatf("%s: exception cause is incorrect", message)
                );
                check_condition(
                    if_id_candidate.exception.value === expected_pc,
                    $sformatf("%s: exception value is incorrect", message)
                );
            end
        end
    endtask

    task automatic check_internal_invariants;
        begin
            check_condition(
                !(dut.request_pending_q && dut.outstanding_q),
                "invariant: pending and outstanding are mutually exclusive"
            );
            check_condition(
                !dut.request_pending_stale_q || dut.request_pending_q,
                "invariant: pending stale requires a pending request"
            );
            check_condition(
                !dut.outstanding_stale_q || dut.outstanding_q,
                "invariant: outstanding stale requires an outstanding request"
            );
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

    task automatic test_reset_and_first_request;
        int unsigned errors_before;
        begin
            errors_before = error_count;
            reset_dut();

            check_request(
                1'b1,
                TEST_RESET_VECTOR,
                "reset release starts the first request"
            );
            check_condition(
                !imem_rsp_ready,
                "first request: no response is accepted before request handshake"
            );
            check_condition(
                !fetch_response_available,
                "first request: no response is available"
            );

            report_case(errors_before, "reset and first request");
        end
    endtask

    task automatic test_request_backpressure;
        int unsigned errors_before;
        int unsigned cycle;
        begin
            errors_before = error_count;
            reset_dut();

            fetch_action = FETCH_SEQUENTIAL;
            for (cycle = 0; cycle < 3; cycle++) begin
                check_request(
                    1'b1,
                    TEST_RESET_VECTOR,
                    "request backpressure preserves valid and address"
                );
                tick();
            end

            imem_req_ready = 1'b1;
            settle();
            check_request(
                1'b1,
                TEST_RESET_VECTOR,
                "request remains stable in its handshake cycle"
            );
            tick();

            imem_req_ready = 1'b0;
            settle();
            check_request(
                1'b0,
                '0,
                "accepted request becomes the sole outstanding transaction"
            );

            report_case(errors_before, "request backpressure and handshake");
        end
    endtask

    task automatic test_response_backpressure_and_metadata;
        int unsigned errors_before;
        begin
            errors_before = error_count;
            reset_dut();
            accept_initial_request();

            imem_rsp_valid = 1'b1;
            imem_rsp_data  = 32'h0000_0013;
            if_id_ready    = 1'b0;
            fetch_action   = FETCH_HOLD;
            settle();

            check_condition(
                fetch_response_available,
                "response backpressure: availability is independent of ready"
            );
            check_condition(
                !imem_rsp_ready,
                "response backpressure: useful response must be held"
            );
            check_candidate(
                TEST_RESET_VECTOR,
                32'h0000_0013,
                1'b0,
                "response backpressure metadata"
            );

            tick();
            check_condition(
                fetch_response_available && !imem_rsp_ready,
                "response backpressure: response remains available"
            );

            if_id_ready    = 1'b1;
            fetch_action   = FETCH_SEQUENTIAL;
            imem_req_ready = 1'b0;
            settle();

            check_condition(
                imem_rsp_ready,
                "response backpressure: response handshakes after release"
            );
            check_request(
                1'b1,
                TEST_RESET_VECTOR + 32'd4,
                "response release launches the next sequential request"
            );
            tick();

            imem_rsp_valid = 1'b0;
            if_id_ready    = 1'b0;
            fetch_action   = FETCH_HOLD;
            settle();
            check_request(
                1'b1,
                TEST_RESET_VECTOR + 32'd4,
                "unaccepted sequential request is retained during hold"
            );

            report_case(
                errors_before,
                "response backpressure, metadata, and pending next request"
            );
        end
    endtask

    task automatic test_continuous_sequential_fetch;
        int unsigned errors_before;
        int unsigned index;
        logic [31:0] response_pc;
        logic [31:0] response_instruction;
        begin
            errors_before = error_count;
            reset_dut();

            imem_req_ready = 1'b1;
            tick();

            if_id_ready  = 1'b1;
            fetch_action = FETCH_SEQUENTIAL;
            response_pc  = TEST_RESET_VECTOR;

            for (index = 0; index < 4; index++) begin
                response_instruction = 32'h1000_0013 + index;
                imem_rsp_valid = 1'b1;
                imem_rsp_data  = response_instruction;
                settle();

                check_condition(
                    imem_rsp_ready && fetch_response_available,
                    "continuous fetch: response must be consumed"
                );
                check_candidate(
                    response_pc,
                    response_instruction,
                    1'b0,
                    "continuous fetch candidate"
                );
                check_request(
                    1'b1,
                    response_pc + 32'd4,
                    "continuous fetch next request"
                );

                tick();
                response_pc = response_pc + 32'd4;
            end

            imem_rsp_valid = 1'b0;
            settle();
            report_case(
                errors_before,
                "four-cycle continuous sequential fetch"
            );
        end
    endtask

    task automatic test_instruction_access_error;
        int unsigned errors_before;
        begin
            errors_before = error_count;
            reset_dut();
            accept_initial_request();

            imem_rsp_valid = 1'b1;
            imem_rsp_data  = 32'hffff_ffff;
            imem_rsp_error = 1'b1;
            if_id_ready    = 1'b0;
            settle();

            check_condition(
                fetch_response_available && !imem_rsp_ready,
                "instruction error remains available under backpressure"
            );
            check_candidate(
                TEST_RESET_VECTOR,
                32'hffff_ffff,
                1'b1,
                "instruction access error metadata"
            );

            report_case(errors_before, "instruction access error");
        end
    endtask

    task automatic test_redirect_without_active_transaction;
        int unsigned errors_before;
        localparam logic [31:0] TARGET = 32'h0000_2000;
        begin
            errors_before = error_count;
            reset_dut();
            accept_initial_request();

            // Consume the response without launching a sequential request.
            imem_rsp_valid = 1'b1;
            imem_rsp_data  = 32'h0000_0013;
            if_id_ready    = 1'b1;
            fetch_action   = FETCH_HOLD;
            tick();

            imem_rsp_valid = 1'b0;
            if_id_ready    = 1'b0;
            drive_redirect(TARGET);
            settle();

            check_request(
                1'b1,
                TARGET,
                "idle redirect issues its target immediately"
            );

            tick();
            clear_redirect();
            settle();
            check_request(
                1'b1,
                TARGET,
                "unaccepted idle redirect target becomes pending"
            );

            imem_req_ready = 1'b1;
            tick();
            imem_req_ready = 1'b0;
            settle();
            check_condition(
                !imem_req_valid,
                "accepted idle redirect target becomes outstanding"
            );

            report_case(errors_before, "redirect without active transaction");
        end
    endtask

    task automatic test_redirect_before_pending_request_accepts;
        int unsigned errors_before;
        localparam logic [31:0] TARGET = 32'h0000_3000;
        begin
            errors_before = error_count;
            reset_dut();

            drive_redirect(TARGET);
            settle();
            check_request(
                1'b1,
                TEST_RESET_VECTOR,
                "redirect cannot rewrite an unaccepted request"
            );
            tick();

            clear_redirect();
            tick();
            check_request(
                1'b1,
                TEST_RESET_VECTOR,
                "stale pending request remains stable"
            );

            imem_req_ready = 1'b1;
            tick();
            imem_req_ready = 1'b0;
            settle();

            check_condition(
                imem_rsp_ready && !fetch_response_available,
                "accepted stale request waits for a drain-only response"
            );
            check_request(
                1'b0,
                '0,
                "redirect target waits for stale response"
            );

            imem_rsp_valid = 1'b1;
            imem_rsp_data  = 32'hdead_beef;
            settle();
            check_condition(
                imem_rsp_ready && !fetch_response_available &&
                    !if_id_candidate.valid,
                "stale response is drained and hidden from IF/ID"
            );
            check_request(
                1'b1,
                TARGET,
                "saved redirect issues as stale response drains"
            );

            tick();
            imem_rsp_valid = 1'b0;
            settle();
            check_request(
                1'b1,
                TARGET,
                "backpressured redirect target is retained"
            );

            report_case(
                errors_before,
                "redirect before pending request acceptance"
            );
        end
    endtask

    task automatic test_redirect_as_pending_request_accepts;
        int unsigned errors_before;
        localparam logic [31:0] TARGET = 32'h0000_4000;
        begin
            errors_before = error_count;
            reset_dut();

            drive_redirect(TARGET);
            imem_req_ready = 1'b1;
            settle();
            check_request(
                1'b1,
                TEST_RESET_VECTOR,
                "same-cycle redirect preserves pending request payload"
            );
            tick();

            clear_redirect();
            imem_rsp_valid = 1'b1;
            imem_rsp_data  = 32'hdead_beef;
            settle();
            check_condition(
                imem_rsp_ready && !fetch_response_available,
                "same-cycle accepted old request is marked stale"
            );
            check_request(
                1'b1,
                TARGET,
                "same-cycle redirect target issues after stale response"
            );

            report_case(
                errors_before,
                "redirect in the pending request handshake cycle"
            );
        end
    endtask

    task automatic test_redirect_while_response_is_pending;
        int unsigned errors_before;
        localparam logic [31:0] TARGET = 32'h0000_5000;
        begin
            errors_before = error_count;
            reset_dut();
            accept_initial_request();

            drive_redirect(TARGET);
            settle();
            check_request(
                1'b0,
                '0,
                "redirect waits while an accepted request has no response"
            );
            tick();

            clear_redirect();
            settle();
            check_condition(
                imem_rsp_ready && !fetch_response_available,
                "old outstanding request becomes stale"
            );

            imem_rsp_valid = 1'b1;
            imem_rsp_data  = 32'hdead_beef;
            imem_req_ready = 1'b1;
            settle();
            check_request(
                1'b1,
                TARGET,
                "redirect target issues with stale response drain"
            );
            tick();

            imem_rsp_valid = 1'b0;
            settle();
            check_request(
                1'b0,
                '0,
                "redirect target is now the sole outstanding request"
            );

            report_case(errors_before, "redirect while waiting for response");
        end
    endtask

    task automatic test_redirect_with_same_cycle_response;
        int unsigned errors_before;
        localparam logic [31:0] TARGET = 32'h0000_6000;
        begin
            errors_before = error_count;
            reset_dut();
            accept_initial_request();

            imem_rsp_valid = 1'b1;
            imem_rsp_data  = 32'h1234_5678;
            if_id_ready    = 1'b0;
            imem_req_ready = 1'b1;
            drive_redirect(TARGET);
            settle();

            check_condition(
                fetch_response_available,
                "same-cycle redirect does not feed back into availability"
            );
            check_condition(
                imem_rsp_ready,
                "same-cycle redirect forces the old response to drain"
            );
            check_candidate(
                TEST_RESET_VECTOR,
                32'h1234_5678,
                1'b0,
                "same-cycle redirect leaves candidate data observable"
            );
            check_request(
                1'b1,
                TARGET,
                "same-cycle redirect replaces the consumed old response"
            );

            tick();
            imem_rsp_valid = 1'b0;
            clear_redirect();
            settle();
            check_request(
                1'b0,
                '0,
                "same-cycle redirect target becomes outstanding"
            );

            report_case(errors_before, "redirect with same-cycle response");
        end
    endtask

    task automatic test_latest_redirect_wins;
        int unsigned errors_before;
        localparam logic [31:0] FIRST_TARGET  = 32'h0000_7000;
        localparam logic [31:0] SECOND_TARGET = 32'h0000_8000;
        begin
            errors_before = error_count;
            reset_dut();

            drive_redirect(FIRST_TARGET);
            tick();
            drive_redirect(SECOND_TARGET);
            tick();
            clear_redirect();

            check_request(
                1'b1,
                TEST_RESET_VECTOR,
                "multiple redirects still preserve the old pending request"
            );

            imem_req_ready = 1'b1;
            tick();
            imem_req_ready = 1'b0;
            imem_rsp_valid = 1'b1;
            settle();

            check_request(
                1'b1,
                SECOND_TARGET,
                "the newest saved redirect target wins"
            );

            report_case(errors_before, "latest redirect target wins");
        end
    endtask

    task automatic test_redirect_replaces_pending_redirect_request;
        int unsigned errors_before;
        localparam logic [31:0] FIRST_TARGET  = 32'h0000_9000;
        localparam logic [31:0] SECOND_TARGET = 32'h0000_a000;
        begin
            errors_before = error_count;
            reset_dut();
            accept_initial_request();

            drive_redirect(FIRST_TARGET);
            tick();
            clear_redirect();

            imem_rsp_valid = 1'b1;
            imem_rsp_data  = 32'hdead_beef;
            imem_req_ready = 1'b0;
            settle();
            check_request(
                1'b1,
                FIRST_TARGET,
                "first redirect target is generated"
            );
            tick();

            imem_rsp_valid = 1'b0;
            drive_redirect(SECOND_TARGET);
            settle();
            check_request(
                1'b1,
                FIRST_TARGET,
                "new redirect cannot rewrite a pending redirect request"
            );
            tick();

            clear_redirect();
            imem_req_ready = 1'b1;
            tick();

            imem_rsp_valid = 1'b1;
            settle();
            check_condition(
                !fetch_response_available,
                "superseded redirect request response is stale"
            );
            check_request(
                1'b1,
                SECOND_TARGET,
                "second target issues after superseded target drains"
            );

            report_case(
                errors_before,
                "new redirect supersedes a pending redirect request"
            );
        end
    endtask

    task automatic test_reset_clears_transaction_state;
        int unsigned errors_before;
        localparam logic [31:0] TARGET = 32'h0000_b000;
        begin
            errors_before = error_count;
            reset_dut();
            accept_initial_request();

            drive_redirect(TARGET);
            tick();

            rst = 1'b1;
            settle();
            check_condition(
                !imem_req_valid && !imem_rsp_ready,
                "reset immediately gates both memory channels"
            );
            tick();

            clear_redirect();
            rst = 1'b0;
            settle();
            check_request(
                1'b1,
                TEST_RESET_VECTOR,
                "reset restarts from RESET_VECTOR instead of saved redirect"
            );
            check_condition(
                !dut.redirect_pending_q && !dut.outstanding_q &&
                    !dut.outstanding_stale_q,
                "reset clears redirect and outstanding state"
            );

            report_case(errors_before, "reset clears transaction state");
        end
    endtask

endmodule
