module tb_rv32_pipeline_ctrl;

    timeunit 1ns;
    timeprecision 1ps;

    import rv32_pkg::*;

    logic rst;
    logic trap_take;
    logic mem_response_wait;
    logic ex_request_wait;
    logic ex_multicycle_wait;
    logic raw_redirect_valid;
    logic load_use_hazard;
    logic fetch_response_available;

    fetch_action_e fetch_action;
    pipe_action_e  if_id_action;
    pipe_action_e  id_ex_action;
    pipe_action_e  ex_mem_action;
    pipe_action_e  mem_wb_action;
    logic          redirect_commit;

    int unsigned error_count;

    rv32_pipeline_ctrl dut (
        .rst                     (rst),
        .trap_take               (trap_take),
        .mem_response_wait       (mem_response_wait),
        .ex_request_wait         (ex_request_wait),
        .ex_multicycle_wait      (ex_multicycle_wait),
        .raw_redirect_valid      (raw_redirect_valid),
        .load_use_hazard         (load_use_hazard),
        .fetch_response_available(fetch_response_available),
        .fetch_action            (fetch_action),
        .if_id_action            (if_id_action),
        .id_ex_action            (id_ex_action),
        .ex_mem_action           (ex_mem_action),
        .mem_wb_action           (mem_wb_action),
        .redirect_commit         (redirect_commit)
    );

    initial begin
        error_count = 0;

        set_normal_inputs();
        check_actions(
            FETCH_SEQUENTIAL,
            PIPE_LOAD,
            PIPE_LOAD,
            PIPE_LOAD,
            PIPE_LOAD,
            1'b0,
            "normal"
        );

        set_normal_inputs();
        rst = 1'b1;
        check_actions(
            FETCH_RESET,
            PIPE_CLEAR,
            PIPE_CLEAR,
            PIPE_CLEAR,
            PIPE_CLEAR,
            1'b0,
            "reset"
        );

        set_normal_inputs();
        trap_take = 1'b1;
        check_actions(
            FETCH_REDIRECT,
            PIPE_CLEAR,
            PIPE_CLEAR,
            PIPE_CLEAR,
            PIPE_CLEAR,
            1'b0,
            "trap"
        );

        set_normal_inputs();
        mem_response_wait = 1'b1;
        check_actions(
            FETCH_HOLD,
            PIPE_HOLD,
            PIPE_HOLD,
            PIPE_HOLD,
            PIPE_CLEAR,
            1'b0,
            "MEM response wait"
        );

        set_normal_inputs();
        ex_request_wait = 1'b1;
        check_actions(
            FETCH_HOLD,
            PIPE_HOLD,
            PIPE_HOLD,
            PIPE_CLEAR,
            PIPE_LOAD,
            1'b0,
            "EX request wait"
        );

        set_normal_inputs();
        ex_multicycle_wait = 1'b1;
        check_actions(
            FETCH_HOLD,
            PIPE_HOLD,
            PIPE_HOLD,
            PIPE_CLEAR,
            PIPE_LOAD,
            1'b0,
            "EX multicycle wait"
        );

        set_normal_inputs();
        raw_redirect_valid = 1'b1;
        check_actions(
            FETCH_REDIRECT,
            PIPE_CLEAR,
            PIPE_CLEAR,
            PIPE_LOAD,
            PIPE_LOAD,
            1'b1,
            "EX redirect"
        );

        set_normal_inputs();
        load_use_hazard = 1'b1;
        check_actions(
            FETCH_HOLD,
            PIPE_HOLD,
            PIPE_CLEAR,
            PIPE_LOAD,
            PIPE_LOAD,
            1'b0,
            "load-use hazard"
        );

        set_normal_inputs();
        fetch_response_available = 1'b0;
        check_actions(
            FETCH_HOLD,
            PIPE_CLEAR,
            PIPE_LOAD,
            PIPE_LOAD,
            PIPE_LOAD,
            1'b0,
            "fetch response unavailable"
        );

        set_normal_inputs();
        rst                      = 1'b1;
        trap_take                = 1'b1;
        mem_response_wait        = 1'b1;
        ex_request_wait          = 1'b1;
        ex_multicycle_wait       = 1'b1;
        raw_redirect_valid       = 1'b1;
        load_use_hazard          = 1'b1;
        fetch_response_available = 1'b0;
        check_actions(
            FETCH_RESET,
            PIPE_CLEAR,
            PIPE_CLEAR,
            PIPE_CLEAR,
            PIPE_CLEAR,
            1'b0,
            "reset has highest priority"
        );

        set_normal_inputs();
        trap_take          = 1'b1;
        mem_response_wait  = 1'b1;
        raw_redirect_valid = 1'b1;
        check_actions(
            FETCH_REDIRECT,
            PIPE_CLEAR,
            PIPE_CLEAR,
            PIPE_CLEAR,
            PIPE_CLEAR,
            1'b0,
            "trap has priority over MEM wait and redirect"
        );

        set_normal_inputs();
        mem_response_wait  = 1'b1;
        ex_request_wait    = 1'b1;
        raw_redirect_valid = 1'b1;
        check_actions(
            FETCH_HOLD,
            PIPE_HOLD,
            PIPE_HOLD,
            PIPE_HOLD,
            PIPE_CLEAR,
            1'b0,
            "MEM wait has priority over EX wait and redirect"
        );

        set_normal_inputs();
        ex_request_wait    = 1'b1;
        raw_redirect_valid = 1'b1;
        load_use_hazard    = 1'b1;
        check_actions(
            FETCH_HOLD,
            PIPE_HOLD,
            PIPE_HOLD,
            PIPE_CLEAR,
            PIPE_LOAD,
            1'b0,
            "EX wait has priority over redirect and load-use"
        );

        set_normal_inputs();
        raw_redirect_valid       = 1'b1;
        load_use_hazard          = 1'b1;
        fetch_response_available = 1'b0;
        check_actions(
            FETCH_REDIRECT,
            PIPE_CLEAR,
            PIPE_CLEAR,
            PIPE_LOAD,
            PIPE_LOAD,
            1'b1,
            "redirect has priority over load-use and fetch unavailable"
        );

        set_normal_inputs();
        load_use_hazard          = 1'b1;
        fetch_response_available = 1'b0;
        check_actions(
            FETCH_HOLD,
            PIPE_HOLD,
            PIPE_CLEAR,
            PIPE_LOAD,
            PIPE_LOAD,
            1'b0,
            "load-use has priority over fetch unavailable"
        );

        if (error_count != 0) begin
            $fatal(
                1,
                "[FAIL] rv32_pipeline_ctrl: %0d test(s) failed",
                error_count
            );
        end

        $display("[PASS] rv32_pipeline_ctrl: all tests passed");
        $finish;
    end

    task automatic set_normal_inputs;
        begin
            rst                      = 1'b0;
            trap_take                = 1'b0;
            mem_response_wait        = 1'b0;
            ex_request_wait          = 1'b0;
            ex_multicycle_wait       = 1'b0;
            raw_redirect_valid       = 1'b0;
            load_use_hazard          = 1'b0;
            fetch_response_available = 1'b1;
        end
    endtask

    task automatic check_actions (
        input fetch_action_e expected_fetch_action,
        input pipe_action_e  expected_if_id_action,
        input pipe_action_e  expected_id_ex_action,
        input pipe_action_e  expected_ex_mem_action,
        input pipe_action_e  expected_mem_wb_action,
        input logic          expected_redirect_commit,
        input string         case_name
    );
        begin
            #1ns;

            if (
                (fetch_action !== expected_fetch_action) ||
                (if_id_action !== expected_if_id_action) ||
                (id_ex_action !== expected_id_ex_action) ||
                (ex_mem_action !== expected_ex_mem_action) ||
                (mem_wb_action !== expected_mem_wb_action) ||
                (redirect_commit !== expected_redirect_commit)
            ) begin
                error_count++;

                $error(
                    "[FAIL] %s: fetch=%b/%b if_id=%b/%b id_ex=%b/%b ex_mem=%b/%b mem_wb=%b/%b redirect_commit=%b/%b",
                    case_name,
                    fetch_action,
                    expected_fetch_action,
                    if_id_action,
                    expected_if_id_action,
                    id_ex_action,
                    expected_id_ex_action,
                    ex_mem_action,
                    expected_ex_mem_action,
                    mem_wb_action,
                    expected_mem_wb_action,
                    redirect_commit,
                    expected_redirect_commit
                );
            end
            else begin
                $display("[PASS] %s", case_name);
            end
        end
    endtask

endmodule
