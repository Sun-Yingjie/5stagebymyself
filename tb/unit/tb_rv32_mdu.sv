module tb_rv32_mdu;
    timeunit 1ns;
    timeprecision 1ps;

    import rv32_pkg::*;

    localparam int unsigned ABORT_IDLE     = 0;
    localparam int unsigned ABORT_RUN      = 1;
    localparam int unsigned ABORT_FINALIZE = 2;
    localparam int unsigned ABORT_RESPONSE = 3;

    logic           clk;
    logic           rst;
    logic           req_valid;
    logic           req_ready;
    mdu_operation_e req_operation;
    logic [31:0]    req_operand_a;
    logic [31:0]    req_operand_b;
    logic           rsp_valid;
    logic           rsp_ready;
    logic [31:0]    rsp_result;
    logic           idle;
    logic           kill;

    int unsigned error_count;
    int unsigned check_count;
    int unsigned case_count;
    integer      random_seed;
    logic [31:0] random_discard;
    logic [31:0] random_operand_a;
    logic [31:0] random_operand_b;
    int unsigned random_operation_index;
    int unsigned random_vector_index;
    mdu_operation_e random_operation;

    rv32_mdu dut (
        .clk          (clk),
        .rst          (rst),
        .req_valid    (req_valid),
        .req_ready    (req_ready),
        .req_operation(req_operation),
        .req_operand_a(req_operand_a),
        .req_operand_b(req_operand_b),
        .rsp_valid    (rsp_valid),
        .rsp_ready    (rsp_ready),
        .rsp_result   (rsp_result),
        .idle         (idle),
        .kill         (kill)
    );

    initial begin
        clk = 1'b0;
        forever #5ns clk = ~clk;
    end

    initial begin
        #1000000ns;
        $fatal(1, "[FAIL] rv32_mdu: global testbench timeout");
    end

    function automatic mdu_operation_e operation_from_index(
        input int unsigned index
    );
        case (index)
            0: operation_from_index = MDU_MUL;
            1: operation_from_index = MDU_MULH;
            2: operation_from_index = MDU_MULHSU;
            3: operation_from_index = MDU_MULHU;
            4: operation_from_index = MDU_DIV;
            5: operation_from_index = MDU_DIVU;
            6: operation_from_index = MDU_REM;
            default: operation_from_index = MDU_REMU;
        endcase
    endfunction

    function automatic logic [31:0] reference_result(
        input mdu_operation_e operation,
        input logic [31:0]    operand_a,
        input logic [31:0]    operand_b
    );
        logic signed [31:0] signed_operand_a_32;
        logic signed [31:0] signed_operand_b_32;
        logic signed [63:0] signed_operand_a_64;
        logic signed [63:0] signed_operand_b_64;
        logic signed [63:0] unsigned_b_as_signed_64;
        logic signed [63:0] signed_product;
        logic signed [63:0] mixed_product;
        logic        [63:0] unsigned_operand_a_64;
        logic        [63:0] unsigned_operand_b_64;
        logic        [63:0] unsigned_product;
        begin
            signed_operand_a_32 = operand_a;
            signed_operand_b_32 = operand_b;
            signed_operand_a_64 = {{32{operand_a[31]}}, operand_a};
            signed_operand_b_64 = {{32{operand_b[31]}}, operand_b};
            unsigned_b_as_signed_64 = {32'b0, operand_b};
            unsigned_operand_a_64 = {32'b0, operand_a};
            unsigned_operand_b_64 = {32'b0, operand_b};

            signed_product = signed_operand_a_64 * signed_operand_b_64;
            mixed_product =
                signed_operand_a_64 * unsigned_b_as_signed_64;
            unsigned_product =
                unsigned_operand_a_64 * unsigned_operand_b_64;

            reference_result = 32'b0;
            case (operation)
                MDU_MUL: begin
                    reference_result = unsigned_product[31:0];
                end

                MDU_MULH: begin
                    reference_result = signed_product[63:32];
                end

                MDU_MULHSU: begin
                    reference_result = mixed_product[63:32];
                end

                MDU_MULHU: begin
                    reference_result = unsigned_product[63:32];
                end

                MDU_DIV: begin
                    if (operand_b == 32'b0) begin
                        reference_result = 32'hffff_ffff;
                    end else if (
                        (operand_a == 32'h8000_0000) &&
                        (operand_b == 32'hffff_ffff)
                    ) begin
                        reference_result = 32'h8000_0000;
                    end else begin
                        reference_result =
                            signed_operand_a_32 / signed_operand_b_32;
                    end
                end

                MDU_DIVU: begin
                    if (operand_b == 32'b0) begin
                        reference_result = 32'hffff_ffff;
                    end else begin
                        reference_result = operand_a / operand_b;
                    end
                end

                MDU_REM: begin
                    if (operand_b == 32'b0) begin
                        reference_result = operand_a;
                    end else if (
                        (operand_a == 32'h8000_0000) &&
                        (operand_b == 32'hffff_ffff)
                    ) begin
                        reference_result = 32'b0;
                    end else begin
                        reference_result =
                            signed_operand_a_32 % signed_operand_b_32;
                    end
                end

                MDU_REMU: begin
                    if (operand_b == 32'b0) begin
                        reference_result = operand_a;
                    end else begin
                        reference_result = operand_a % operand_b;
                    end
                end

                default: begin
                    reference_result = 32'b0;
                end
            endcase
        end
    endfunction

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

    task automatic start_request(
        input mdu_operation_e operation,
        input logic [31:0]    operand_a,
        input logic [31:0]    operand_b,
        input logic           response_ready,
        input string          case_name
    );
        begin
            while (!idle) begin
                @(posedge clk);
                #1ns;
            end

            @(negedge clk);
            req_operation = operation;
            req_operand_a = operand_a;
            req_operand_b = operand_b;
            req_valid     = 1'b1;
            rsp_ready     = response_ready;
            #1ns;

            check_condition(
                req_ready,
                $sformatf("%s: IDLE request was not ready", case_name)
            );
            check_condition(
                idle,
                $sformatf("%s: idle was low before request fire", case_name)
            );

            @(posedge clk);
            #1ns;
            check_condition(
                !idle && !req_ready && !rsp_valid,
                $sformatf(
                    "%s: request fire did not enter busy RUN state",
                    case_name
                )
            );

            @(negedge clk);
            req_valid     = 1'b0;
            req_operation = MDU_MULHU;
            req_operand_a = 32'hdead_beef;
            req_operand_b = 32'h0123_4567;
        end
    endtask

    task automatic wait_for_fixed_response(
        input logic [31:0] expected_result,
        input string       case_name
    );
        int unsigned cycle_index;
        begin
            for (cycle_index = 1; cycle_index <= 32; cycle_index++) begin
                @(posedge clk);
                #1ns;
                check_condition(
                    !rsp_valid,
                    $sformatf(
                        "%s: response arrived early at E%0d",
                        case_name,
                        cycle_index
                    )
                );
                check_condition(
                    !req_ready && !idle,
                    $sformatf(
                        "%s: MDU became ready during iteration E%0d",
                        case_name,
                        cycle_index
                    )
                );
            end

            @(posedge clk);
            #1ns;
            check_condition(
                rsp_valid,
                $sformatf("%s: no response after E33", case_name)
            );
            check_condition(
                !req_ready && !idle,
                $sformatf("%s: RESPONSE incorrectly reported idle", case_name)
            );
            check_condition(
                rsp_result === expected_result,
                $sformatf(
                    "%s: result=%08h expected=%08h",
                    case_name,
                    rsp_result,
                    expected_result
                )
            );
        end
    endtask

    task automatic accept_response(
        input string case_name
    );
        begin
            @(posedge clk);
            #1ns;
            check_condition(
                idle && req_ready && !rsp_valid,
                $sformatf(
                    "%s: response fire did not return to IDLE",
                    case_name
                )
            );
            @(negedge clk);
            rsp_ready = 1'b0;
        end
    endtask

    task automatic run_case(
        input mdu_operation_e operation,
        input logic [31:0]    operand_a,
        input logic [31:0]    operand_b,
        input logic [31:0]    expected_result,
        input string          case_name
    );
        int unsigned errors_before;
        begin
            errors_before = error_count;
            case_count++;

            start_request(
                operation,
                operand_a,
                operand_b,
                1'b1,
                case_name
            );
            wait_for_fixed_response(expected_result, case_name);
            accept_response(case_name);

            if (error_count == errors_before) begin
                $display(
                    "[PASS] %-32s result=%08h",
                    case_name,
                    expected_result
                );
            end
        end
    endtask

    task automatic test_busy_request_rejection;
        int unsigned busy_cycle;
        int unsigned watchdog;
        int unsigned errors_before;
        logic [31:0] expected_result;
        begin
            errors_before = error_count;
            case_count++;
            expected_result = reference_result(
                MDU_DIVU,
                32'hfedc_ba98,
                32'h0000_0123
            );

            start_request(
                MDU_DIVU,
                32'hfedc_ba98,
                32'h0000_0123,
                1'b1,
                "busy request rejection"
            );

            req_valid     = 1'b1;
            req_operation = MDU_MUL;
            req_operand_a = 32'h1111_1111;
            req_operand_b = 32'h2222_2222;

            for (busy_cycle = 0; busy_cycle < 6; busy_cycle++) begin
                #1ns;
                check_condition(
                    !req_ready,
                    "busy request rejection: req_ready rose during RUN"
                );
                @(posedge clk);
                #1ns;
                check_condition(
                    !rsp_valid,
                    "busy request rejection: response arrived too early"
                );
                @(negedge clk);
            end
            req_valid = 1'b0;

            watchdog = 0;
            while (!rsp_valid && (watchdog < 40)) begin
                @(posedge clk);
                #1ns;
                watchdog++;
            end
            check_condition(
                rsp_valid,
                "busy request rejection: original request timed out"
            );
            check_condition(
                rsp_result === expected_result,
                $sformatf(
                    "busy request rejection: result=%08h expected=%08h",
                    rsp_result,
                    expected_result
                )
            );
            accept_response("busy request rejection");

            if (error_count == errors_before) begin
                $display("[PASS] busy request rejected and input snapshot held");
            end
        end
    endtask

    task automatic test_response_backpressure;
        int unsigned hold_cycle;
        int unsigned errors_before;
        logic [31:0] held_result;
        begin
            errors_before = error_count;
            case_count++;

            start_request(
                MDU_MULHSU,
                32'h8000_0000,
                32'hffff_ffff,
                1'b0,
                "response backpressure"
            );
            wait_for_fixed_response(
                32'h8000_0000,
                "response backpressure"
            );
            held_result = rsp_result;

            for (hold_cycle = 0; hold_cycle < 4; hold_cycle++) begin
                @(negedge clk);
                req_valid     = 1'b1;
                req_operation = MDU_DIV;
                req_operand_a = hold_cycle;
                req_operand_b = 32'd3;
                #1ns;
                check_condition(
                    rsp_valid && !req_ready && !idle,
                    "response backpressure: RESPONSE protocol changed"
                );
                check_condition(
                    rsp_result === held_result,
                    "response backpressure: payload changed before fire"
                );
                @(posedge clk);
                #1ns;
                check_condition(
                    rsp_valid && (rsp_result === held_result),
                    "response backpressure: response was not held"
                );
            end

            @(negedge clk);
            req_valid = 1'b0;
            rsp_ready = 1'b1;
            #1ns;
            check_condition(
                rsp_valid,
                "response backpressure: response disappeared before fire"
            );
            accept_response("response backpressure");

            if (error_count == errors_before) begin
                $display("[PASS] response backpressure holds valid and payload");
            end
        end
    endtask

    task automatic test_abort(
        input logic        use_reset,
        input int unsigned abort_phase,
        input string       case_name
    );
        int unsigned cycle_index;
        int unsigned errors_before;
        begin
            errors_before = error_count;
            case_count++;

            if (abort_phase == ABORT_IDLE) begin
                while (!idle) begin
                    @(posedge clk);
                    #1ns;
                end
                @(negedge clk);
                req_operation = MDU_MUL;
                req_operand_a = 32'h1234_5678;
                req_operand_b = 32'h9abc_def0;
                req_valid     = 1'b1;
                rsp_ready     = 1'b1;
            end else begin
                start_request(
                    MDU_DIVU,
                    32'hfedc_ba98,
                    32'h0000_0123,
                    (abort_phase == ABORT_RESPONSE) ? 1'b0 : 1'b1,
                    case_name
                );

                case (abort_phase)
                    ABORT_RUN: begin
                        for (cycle_index = 0;
                             cycle_index < 8;
                             cycle_index++) begin
                            @(posedge clk);
                            #1ns;
                        end
                    end

                    ABORT_FINALIZE: begin
                        for (cycle_index = 0;
                             cycle_index < 32;
                             cycle_index++) begin
                            @(posedge clk);
                            #1ns;
                        end
                        check_condition(
                            !rsp_valid && !idle,
                            $sformatf(
                                "%s: expected FINALIZE before abort",
                                case_name
                            )
                        );
                    end

                    ABORT_RESPONSE: begin
                        for (cycle_index = 0;
                             cycle_index < 32;
                             cycle_index++) begin
                            @(posedge clk);
                            #1ns;
                        end
                        @(posedge clk);
                        #1ns;
                        check_condition(
                            rsp_valid && !idle,
                            $sformatf(
                                "%s: expected held RESPONSE before abort",
                                case_name
                            )
                        );
                    end

                    default: begin
                    end
                endcase

                @(negedge clk);
                req_valid     = 1'b1;
                req_operation = MDU_MUL;
                req_operand_a = 32'h1111_1111;
                req_operand_b = 32'h2222_2222;
                rsp_ready     = 1'b1;
            end

            if (use_reset) begin
                rst = 1'b1;
            end else begin
                kill = 1'b1;
            end
            #1ns;
            check_condition(
                !req_ready && !rsp_valid,
                $sformatf(
                    "%s: abort did not suppress external handshake",
                    case_name
                )
            );

            @(posedge clk);
            #1ns;
            check_condition(
                idle && !req_ready && !rsp_valid,
                $sformatf("%s: abort did not clear state", case_name)
            );

            @(negedge clk);
            rst       = 1'b0;
            kill      = 1'b0;
            req_valid = 1'b0;
            rsp_ready = 1'b0;

            for (cycle_index = 0; cycle_index < 36; cycle_index++) begin
                @(posedge clk);
                #1ns;
                check_condition(
                    idle && req_ready && !rsp_valid,
                    $sformatf(
                        "%s: stale state/late response after abort",
                        case_name
                    )
                );
            end

            if (error_count == errors_before) begin
                $display("[PASS] %s", case_name);
            end
        end
    endtask

    initial begin
        rst           = 1'b1;
        kill          = 1'b0;
        req_valid     = 1'b0;
        req_operation = MDU_MUL;
        req_operand_a = 32'b0;
        req_operand_b = 32'b0;
        rsp_ready     = 1'b0;

        error_count = 0;
        check_count = 0;
        case_count  = 0;

        repeat (2) begin
            @(posedge clk);
            #1ns;
            check_condition(
                idle && !req_ready && !rsp_valid,
                "reset did not suppress request/response handshakes"
            );
        end

        @(negedge clk);
        rst = 1'b0;
        @(posedge clk);
        #1ns;
        check_condition(
            idle && req_ready && !rsp_valid,
            "reset release did not produce an idle MDU"
        );

        run_case(MDU_MUL, 32'h0000_0000, 32'hffff_ffff,
                 32'h0000_0000, "MUL zero");
        run_case(MDU_MUL, 32'hffff_ffff, 32'hffff_ffff,
                 32'h0000_0001, "MUL minus-one squared low");
        run_case(MDU_MUL, 32'h8000_0000, 32'h0000_0002,
                 32'h0000_0000, "MUL minimum times two low");
        run_case(MDU_MUL, 32'h1234_5678, 32'h0000_0010,
                 32'h2345_6780, "MUL low wrap");

        run_case(MDU_MULH, 32'hffff_ffff, 32'h0000_0001,
                 32'hffff_ffff, "MULH negative times positive");
        run_case(MDU_MULH, 32'hffff_ffff, 32'hffff_ffff,
                 32'h0000_0000, "MULH minus-one squared");
        run_case(MDU_MULH, 32'h8000_0000, 32'h0000_0002,
                 32'hffff_ffff, "MULH minimum times two");
        run_case(MDU_MULH, 32'h7fff_ffff, 32'h7fff_ffff,
                 32'h3fff_ffff, "MULH maximum squared");
        run_case(MDU_MULH, 32'h8000_0000, 32'h8000_0000,
                 32'h4000_0000, "MULH minimum squared");

        run_case(MDU_MULHSU, 32'hffff_ffff, 32'hffff_ffff,
                 32'hffff_ffff, "MULHSU minus-one times umax");
        run_case(MDU_MULHSU, 32'h8000_0000, 32'hffff_ffff,
                 32'h8000_0000, "MULHSU minimum times umax");
        run_case(MDU_MULHSU, 32'h7fff_ffff, 32'hffff_ffff,
                 32'h7fff_fffe, "MULHSU maximum times umax");
        run_case(MDU_MULHSU, 32'h0000_0001, 32'hffff_ffff,
                 32'h0000_0000, "MULHSU one times umax");

        run_case(MDU_MULHU, 32'hffff_ffff, 32'hffff_ffff,
                 32'hffff_fffe, "MULHU umax squared");
        run_case(MDU_MULHU, 32'h8000_0000, 32'h0000_0002,
                 32'h0000_0001, "MULHU high carry");
        run_case(MDU_MULHU, 32'h7fff_ffff, 32'h7fff_ffff,
                 32'h3fff_ffff, "MULHU maximum signed squared");
        run_case(MDU_MULHU, 32'h0000_0000, 32'hffff_ffff,
                 32'h0000_0000, "MULHU zero");

        run_case(MDU_DIV, 32'h0000_0007, 32'h0000_0003,
                 32'h0000_0002, "DIV positive");
        run_case(MDU_DIV, 32'hffff_fff9, 32'h0000_0003,
                 32'hffff_fffe, "DIV negative dividend");
        run_case(MDU_DIV, 32'h0000_0007, 32'hffff_fffd,
                 32'hffff_fffe, "DIV negative divisor");
        run_case(MDU_DIV, 32'hffff_fff9, 32'hffff_fffd,
                 32'h0000_0002, "DIV both negative");
        run_case(MDU_DIV, 32'h1234_5678, 32'h0000_0000,
                 32'hffff_ffff, "DIV by zero");
        run_case(MDU_DIV, 32'h8000_0000, 32'hffff_ffff,
                 32'h8000_0000, "DIV signed overflow");
        run_case(MDU_DIV, 32'h8000_0000, 32'h0000_0003,
                 32'hd555_5556, "DIV minimum by three");
        run_case(MDU_DIV, 32'h0000_0001, 32'h8000_0000,
                 32'h0000_0000, "DIV smaller than minimum divisor");

        run_case(MDU_DIVU, 32'h0000_0007, 32'h0000_0003,
                 32'h0000_0002, "DIVU basic");
        run_case(MDU_DIVU, 32'hffff_ffff, 32'h0000_0002,
                 32'h7fff_ffff, "DIVU umax by two");
        run_case(MDU_DIVU, 32'h8000_0000, 32'hffff_ffff,
                 32'h0000_0000, "DIVU smaller dividend");
        run_case(MDU_DIVU, 32'h1234_5678, 32'h0000_0000,
                 32'hffff_ffff, "DIVU by zero");
        run_case(MDU_DIVU, 32'hffff_ffff, 32'hffff_ffff,
                 32'h0000_0001, "DIVU equal operands");

        run_case(MDU_REM, 32'h0000_0007, 32'h0000_0003,
                 32'h0000_0001, "REM positive");
        run_case(MDU_REM, 32'hffff_fff9, 32'h0000_0003,
                 32'hffff_ffff, "REM negative dividend");
        run_case(MDU_REM, 32'h0000_0007, 32'hffff_fffd,
                 32'h0000_0001, "REM negative divisor");
        run_case(MDU_REM, 32'hffff_fff9, 32'hffff_fffd,
                 32'hffff_ffff, "REM both negative");
        run_case(MDU_REM, 32'h1234_5678, 32'h0000_0000,
                 32'h1234_5678, "REM by zero");
        run_case(MDU_REM, 32'h8000_0000, 32'hffff_ffff,
                 32'h0000_0000, "REM signed overflow");
        run_case(MDU_REM, 32'h8000_0000, 32'h0000_0003,
                 32'hffff_fffe, "REM minimum by three");

        run_case(MDU_REMU, 32'hffff_ffff, 32'h0000_0002,
                 32'h0000_0001, "REMU umax by two");
        run_case(MDU_REMU, 32'h8000_0000, 32'hffff_ffff,
                 32'h8000_0000, "REMU smaller dividend");
        run_case(MDU_REMU, 32'h89ab_cdef, 32'h0000_0000,
                 32'h89ab_cdef, "REMU by zero");
        run_case(MDU_REMU, 32'hffff_ffff, 32'hffff_ffff,
                 32'h0000_0000, "REMU equal operands");
        run_case(MDU_REMU, 32'h0000_0000, 32'h0000_1234,
                 32'h0000_0000, "REMU zero dividend");

        random_seed = 32'h5a17_2026;
        random_discard = $urandom(random_seed);
        for (random_operation_index = 0;
             random_operation_index < 8;
             random_operation_index++) begin
            for (random_vector_index = 0;
                 random_vector_index < 4;
                 random_vector_index++) begin
                random_operation =
                    operation_from_index(random_operation_index);
                random_operand_a = $urandom;
                random_operand_b = $urandom;
                run_case(
                    random_operation,
                    random_operand_a,
                    random_operand_b,
                    reference_result(
                        random_operation,
                        random_operand_a,
                        random_operand_b
                    ),
                    $sformatf(
                        "random op=%0d vector=%0d",
                        random_operation_index,
                        random_vector_index
                    )
                );
            end
        end

        test_busy_request_rejection();
        test_response_backpressure();

        test_abort(1'b0, ABORT_IDLE, "kill in IDLE");
        test_abort(1'b0, ABORT_RUN, "kill in RUN");
        test_abort(1'b0, ABORT_FINALIZE, "kill in FINALIZE");
        test_abort(1'b0, ABORT_RESPONSE, "kill in RESPONSE");
        test_abort(1'b1, ABORT_IDLE, "reset in IDLE");
        test_abort(1'b1, ABORT_RUN, "reset in RUN");
        test_abort(1'b1, ABORT_FINALIZE, "reset in FINALIZE");
        test_abort(1'b1, ABORT_RESPONSE, "reset in RESPONSE");

        if (error_count != 0) begin
            $fatal(
                1,
                "[FAIL] rv32_mdu: %0d errors across %0d cases and %0d checks",
                error_count,
                case_count,
                check_count
            );
        end

        $display(
            "[PASS] rv32_mdu: %0d cases and %0d checks passed",
            case_count,
            check_count
        );
        $finish;
    end

endmodule
