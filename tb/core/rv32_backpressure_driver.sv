module rv32_backpressure_driver (
    input  logic        clk,
    input  logic        rst,
    input  logic        enable,
    input  logic [31:0] seed,
    input  logic [31:0] stall_percent,
    input  logic [31:0] max_stall_cycles,

    output logic        imem_request_allow,
    output logic        imem_response_allow,
    output logic        dmem_request_allow,
    output logic        dmem_response_allow,

    output logic [31:0] random_state,
    output logic [31:0] imem_request_low_cycles,
    output logic [31:0] imem_response_low_cycles,
    output logic [31:0] dmem_request_low_cycles,
    output logic [31:0] dmem_response_low_cycles,
    output logic [31:0] imem_request_forced_grants,
    output logic [31:0] imem_response_forced_grants,
    output logic [31:0] dmem_request_forced_grants,
    output logic [31:0] dmem_response_forced_grants,
    output logic [31:0] imem_request_max_low_streak,
    output logic [31:0] imem_response_max_low_streak,
    output logic [31:0] dmem_request_max_low_streak,
    output logic [31:0] dmem_response_max_low_streak
);
    localparam logic [31:0] ZERO_SEED_REPLACEMENT = 32'h6d2b_79f5;

    logic [31:0] random_state_q;
    logic [31:0] imem_request_low_streak_q;
    logic [31:0] imem_response_low_streak_q;
    logic [31:0] dmem_request_low_streak_q;
    logic [31:0] dmem_response_low_streak_q;

    logic [31:0] random_word_0;
    logic [31:0] random_word_1;
    logic [31:0] random_word_2;
    logic [31:0] random_word_3;
    logic        imem_request_allow_next;
    logic        imem_response_allow_next;
    logic        dmem_request_allow_next;
    logic        dmem_response_allow_next;

    function automatic logic [31:0] xorshift32(
        input logic [31:0] value
    );
        logic [31:0] result;
        begin
            result = value;
            result = result ^ (result << 13);
            result = result ^ (result >> 17);
            result = result ^ (result << 5);
            xorshift32 = result;
        end
    endfunction

    function automatic logic choose_allow(
        input logic [31:0] random_word,
        input logic [31:0] current_low_streak
    );
        begin
            if (max_stall_cycles == 32'b0) begin
                choose_allow = 1'b1;
            end else if (current_low_streak >= max_stall_cycles) begin
                choose_allow = 1'b1;
            end else begin
                choose_allow =
                    ((random_word % 32'd100) >= stall_percent);
            end
        end
    endfunction

    always_comb begin
        random_word_0 = xorshift32(random_state_q);
        random_word_1 = xorshift32(random_word_0);
        random_word_2 = xorshift32(random_word_1);
        random_word_3 = xorshift32(random_word_2);

        imem_request_allow_next = choose_allow(
            random_word_0,
            imem_request_low_streak_q
        );
        imem_response_allow_next = choose_allow(
            random_word_1,
            imem_response_low_streak_q
        );
        dmem_request_allow_next = choose_allow(
            random_word_2,
            dmem_request_low_streak_q
        );
        dmem_response_allow_next = choose_allow(
            random_word_3,
            dmem_response_low_streak_q
        );
    end

    assign random_state = random_state_q;

    always_ff @(posedge clk) begin
        if (rst || !enable) begin
            random_state_q <=
                (seed == 32'b0) ? ZERO_SEED_REPLACEMENT : seed;

            imem_request_allow  <= 1'b1;
            imem_response_allow <= 1'b1;
            dmem_request_allow  <= 1'b1;
            dmem_response_allow <= 1'b1;

            imem_request_low_streak_q  <= 32'b0;
            imem_response_low_streak_q <= 32'b0;
            dmem_request_low_streak_q  <= 32'b0;
            dmem_response_low_streak_q <= 32'b0;

            imem_request_low_cycles  <= 32'b0;
            imem_response_low_cycles <= 32'b0;
            dmem_request_low_cycles  <= 32'b0;
            dmem_response_low_cycles <= 32'b0;

            imem_request_forced_grants  <= 32'b0;
            imem_response_forced_grants <= 32'b0;
            dmem_request_forced_grants  <= 32'b0;
            dmem_response_forced_grants <= 32'b0;

            imem_request_max_low_streak  <= 32'b0;
            imem_response_max_low_streak <= 32'b0;
            dmem_request_max_low_streak  <= 32'b0;
            dmem_response_max_low_streak <= 32'b0;
        end else begin
            random_state_q <= random_word_3;

            imem_request_allow  <= imem_request_allow_next;
            imem_response_allow <= imem_response_allow_next;
            dmem_request_allow  <= dmem_request_allow_next;
            dmem_response_allow <= dmem_response_allow_next;

            if (imem_request_allow_next) begin
                imem_request_low_streak_q <= 32'b0;
            end else begin
                imem_request_low_streak_q <=
                    imem_request_low_streak_q + 32'd1;
                imem_request_low_cycles <=
                    imem_request_low_cycles + 32'd1;
                if (
                    (imem_request_low_streak_q + 32'd1) >
                    imem_request_max_low_streak
                ) begin
                    imem_request_max_low_streak <=
                        imem_request_low_streak_q + 32'd1;
                end
            end

            if (imem_response_allow_next) begin
                imem_response_low_streak_q <= 32'b0;
            end else begin
                imem_response_low_streak_q <=
                    imem_response_low_streak_q + 32'd1;
                imem_response_low_cycles <=
                    imem_response_low_cycles + 32'd1;
                if (
                    (imem_response_low_streak_q + 32'd1) >
                    imem_response_max_low_streak
                ) begin
                    imem_response_max_low_streak <=
                        imem_response_low_streak_q + 32'd1;
                end
            end

            if (dmem_request_allow_next) begin
                dmem_request_low_streak_q <= 32'b0;
            end else begin
                dmem_request_low_streak_q <=
                    dmem_request_low_streak_q + 32'd1;
                dmem_request_low_cycles <=
                    dmem_request_low_cycles + 32'd1;
                if (
                    (dmem_request_low_streak_q + 32'd1) >
                    dmem_request_max_low_streak
                ) begin
                    dmem_request_max_low_streak <=
                        dmem_request_low_streak_q + 32'd1;
                end
            end

            if (dmem_response_allow_next) begin
                dmem_response_low_streak_q <= 32'b0;
            end else begin
                dmem_response_low_streak_q <=
                    dmem_response_low_streak_q + 32'd1;
                dmem_response_low_cycles <=
                    dmem_response_low_cycles + 32'd1;
                if (
                    (dmem_response_low_streak_q + 32'd1) >
                    dmem_response_max_low_streak
                ) begin
                    dmem_response_max_low_streak <=
                        dmem_response_low_streak_q + 32'd1;
                end
            end

            if (
                (max_stall_cycles != 32'b0) &&
                (imem_request_low_streak_q >= max_stall_cycles)
            ) begin
                imem_request_forced_grants <=
                    imem_request_forced_grants + 32'd1;
            end
            if (
                (max_stall_cycles != 32'b0) &&
                (imem_response_low_streak_q >= max_stall_cycles)
            ) begin
                imem_response_forced_grants <=
                    imem_response_forced_grants + 32'd1;
            end
            if (
                (max_stall_cycles != 32'b0) &&
                (dmem_request_low_streak_q >= max_stall_cycles)
            ) begin
                dmem_request_forced_grants <=
                    dmem_request_forced_grants + 32'd1;
            end
            if (
                (max_stall_cycles != 32'b0) &&
                (dmem_response_low_streak_q >= max_stall_cycles)
            ) begin
                dmem_response_forced_grants <=
                    dmem_response_forced_grants + 32'd1;
            end
        end
    end
endmodule
