module rv32_mdu (
    input  logic                     clk,
    input  logic                     rst,

    input  logic                     req_valid,
    output logic                     req_ready,
    input  rv32_pkg::mdu_operation_e req_operation,
    input  logic [31:0]              req_operand_a,
    input  logic [31:0]              req_operand_b,

    output logic                     rsp_valid,
    input  logic                     rsp_ready,
    output logic [31:0]              rsp_result,

    output logic                     idle,
    input  logic                     kill
);

    import rv32_pkg::*;

    typedef enum logic [1:0] {
        MDU_STATE_IDLE,
        MDU_STATE_RUN,
        MDU_STATE_FINALIZE,
        MDU_STATE_RESPONSE
    } mdu_state_e;

    mdu_state_e    state_q;
    mdu_operation_e operation_q;

    logic [4:0] iteration_q;

    logic [63:0] mul_acc_q;
    logic [63:0] mul_multiplicand_q;
    logic [31:0] mul_multiplier_q;
    logic [63:0] mul_acc_next;
    logic        product_negative_q;

    logic [31:0] div_divisor_q;
    logic [31:0] div_quotient_q;
    logic [32:0] div_remainder_q;
    logic [32:0] div_remainder_shift;
    logic [31:0] div_quotient_next;
    logic [32:0] div_remainder_next;
    logic        quotient_negative_q;
    logic        remainder_negative_q;
    logic        divide_by_zero_q;
    logic        signed_overflow_q;

    logic [31:0] operand_a_q;
    logic [31:0] result_q;

    logic        req_fire;
    logic        rsp_fire;
    logic        req_is_multiply;
    logic        req_operand_a_signed;
    logic        req_operand_b_signed;
    logic        req_operand_a_negative;
    logic        req_operand_b_negative;
    logic [31:0] req_operand_a_magnitude;
    logic [31:0] req_operand_b_magnitude;
    logic [63:0] corrected_product;
    logic [31:0] corrected_quotient;
    logic [31:0] corrected_remainder;
    logic [31:0] finalized_result;

    function automatic logic [31:0] twos_complement_32(
        input logic [31:0] value
    );
        twos_complement_32 = (~value) + 32'd1;
    endfunction

    function automatic logic [63:0] twos_complement_64(
        input logic [63:0] value
    );
        twos_complement_64 = (~value) + 64'd1;
    endfunction

    function automatic logic operation_is_multiply(
        input mdu_operation_e operation
    );
        case (operation)
            MDU_MUL,
            MDU_MULH,
            MDU_MULHSU,
            MDU_MULHU: operation_is_multiply = 1'b1;
            default:   operation_is_multiply = 1'b0;
        endcase
    endfunction

    assign idle       = (state_q == MDU_STATE_IDLE);
    assign req_ready  = idle && !rst && !kill;
    assign rsp_valid  = (state_q == MDU_STATE_RESPONSE) && !rst && !kill;
    assign rsp_result = result_q;

    assign req_fire = req_valid && req_ready;
    assign rsp_fire = rsp_valid && rsp_ready;

    always_comb begin
        req_is_multiply       = operation_is_multiply(req_operation);
        req_operand_a_signed = 1'b0;
        req_operand_b_signed = 1'b0;

        case (req_operation)
            MDU_MULH: begin
                req_operand_a_signed = 1'b1;
                req_operand_b_signed = 1'b1;
            end

            MDU_MULHSU: begin
                req_operand_a_signed = 1'b1;
                req_operand_b_signed = 1'b0;
            end

            MDU_DIV,
            MDU_REM: begin
                req_operand_a_signed = 1'b1;
                req_operand_b_signed = 1'b1;
            end

            default: begin
                req_operand_a_signed = 1'b0;
                req_operand_b_signed = 1'b0;
            end
        endcase

        req_operand_a_negative =
            req_operand_a_signed && req_operand_a[31];
        req_operand_b_negative =
            req_operand_b_signed && req_operand_b[31];

        req_operand_a_magnitude = req_operand_a;
        if (req_operand_a_negative) begin
            req_operand_a_magnitude =
                twos_complement_32(req_operand_a);
        end

        req_operand_b_magnitude = req_operand_b;
        if (req_operand_b_negative) begin
            req_operand_b_magnitude =
                twos_complement_32(req_operand_b);
        end
    end

    always_comb begin
        mul_acc_next = mul_acc_q;
        if (mul_multiplier_q[0]) begin
            mul_acc_next = mul_acc_q + mul_multiplicand_q;
        end
    end

    always_comb begin
        div_remainder_shift = {
            div_remainder_q[31:0],
            div_quotient_q[31]
        };
        div_quotient_next = {div_quotient_q[30:0], 1'b0};
        div_remainder_next = div_remainder_shift;

        if (div_remainder_shift >= {1'b0, div_divisor_q}) begin
            div_remainder_next =
                div_remainder_shift - {1'b0, div_divisor_q};
            div_quotient_next[0] = 1'b1;
        end
    end

    always_comb begin
        corrected_product = mul_acc_q;
        if (product_negative_q) begin
            corrected_product = twos_complement_64(mul_acc_q);
        end

        corrected_quotient = div_quotient_q;
        if (quotient_negative_q) begin
            corrected_quotient = twos_complement_32(div_quotient_q);
        end

        corrected_remainder = div_remainder_q[31:0];
        if (remainder_negative_q) begin
            corrected_remainder =
                twos_complement_32(div_remainder_q[31:0]);
        end

        finalized_result = 32'b0;
        case (operation_q)
            MDU_MUL: begin
                finalized_result = corrected_product[31:0];
            end

            MDU_MULH,
            MDU_MULHSU,
            MDU_MULHU: begin
                finalized_result = corrected_product[63:32];
            end

            MDU_DIV,
            MDU_DIVU: begin
                if (divide_by_zero_q) begin
                    finalized_result = 32'hffff_ffff;
                end else if (signed_overflow_q) begin
                    finalized_result = 32'h8000_0000;
                end else begin
                    finalized_result = corrected_quotient;
                end
            end

            MDU_REM,
            MDU_REMU: begin
                if (divide_by_zero_q) begin
                    finalized_result = operand_a_q;
                end else if (signed_overflow_q) begin
                    finalized_result = 32'b0;
                end else begin
                    finalized_result = corrected_remainder;
                end
            end

            default: begin
                finalized_result = 32'b0;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state_q                <= MDU_STATE_IDLE;
            operation_q            <= MDU_MUL;
            iteration_q            <= 5'b0;
            mul_acc_q              <= 64'b0;
            mul_multiplicand_q     <= 64'b0;
            mul_multiplier_q       <= 32'b0;
            product_negative_q     <= 1'b0;
            div_divisor_q          <= 32'b0;
            div_quotient_q         <= 32'b0;
            div_remainder_q        <= 33'b0;
            quotient_negative_q    <= 1'b0;
            remainder_negative_q   <= 1'b0;
            divide_by_zero_q       <= 1'b0;
            signed_overflow_q      <= 1'b0;
            operand_a_q            <= 32'b0;
            result_q               <= 32'b0;
        end else if (kill) begin
            state_q                <= MDU_STATE_IDLE;
            operation_q            <= MDU_MUL;
            iteration_q            <= 5'b0;
            mul_acc_q              <= 64'b0;
            mul_multiplicand_q     <= 64'b0;
            mul_multiplier_q       <= 32'b0;
            product_negative_q     <= 1'b0;
            div_divisor_q          <= 32'b0;
            div_quotient_q         <= 32'b0;
            div_remainder_q        <= 33'b0;
            quotient_negative_q    <= 1'b0;
            remainder_negative_q   <= 1'b0;
            divide_by_zero_q       <= 1'b0;
            signed_overflow_q      <= 1'b0;
            operand_a_q            <= 32'b0;
            result_q               <= 32'b0;
        end else begin
            case (state_q)
                MDU_STATE_IDLE: begin
                    if (req_fire) begin
                        state_q            <= MDU_STATE_RUN;
                        operation_q        <= req_operation;
                        iteration_q        <= 5'b0;
                        operand_a_q        <= req_operand_a;
                        result_q           <= 32'b0;

                        mul_acc_q          <= 64'b0;
                        mul_multiplicand_q <= {
                            32'b0,
                            req_operand_a_magnitude
                        };
                        mul_multiplier_q   <= req_operand_b_magnitude;
                        product_negative_q <=
                            req_is_multiply &&
                            (
                                req_operand_a_negative ^
                                req_operand_b_negative
                            );

                        div_divisor_q       <= req_operand_b_magnitude;
                        div_quotient_q      <= req_operand_a_magnitude;
                        div_remainder_q     <= 33'b0;
                        quotient_negative_q <=
                            !req_is_multiply &&
                            (
                                req_operand_a_negative ^
                                req_operand_b_negative
                            );
                        remainder_negative_q <=
                            !req_is_multiply &&
                            req_operand_a_negative;
                        divide_by_zero_q <=
                            !req_is_multiply &&
                            (req_operand_b == 32'b0);
                        signed_overflow_q <=
                            (
                                (req_operation == MDU_DIV) ||
                                (req_operation == MDU_REM)
                            ) &&
                            (req_operand_a == 32'h8000_0000) &&
                            (req_operand_b == 32'hffff_ffff);
                    end
                end

                MDU_STATE_RUN: begin
                    if (operation_is_multiply(operation_q)) begin
                        mul_acc_q          <= mul_acc_next;
                        mul_multiplicand_q <= mul_multiplicand_q << 1;
                        mul_multiplier_q   <= mul_multiplier_q >> 1;
                    end else begin
                        div_quotient_q  <= div_quotient_next;
                        div_remainder_q <= div_remainder_next;
                    end

                    if (iteration_q == 5'd31) begin
                        state_q <= MDU_STATE_FINALIZE;
                    end else begin
                        iteration_q <= iteration_q + 5'd1;
                    end
                end

                MDU_STATE_FINALIZE: begin
                    result_q <= finalized_result;
                    state_q  <= MDU_STATE_RESPONSE;
                end

                MDU_STATE_RESPONSE: begin
                    if (rsp_fire) begin
                        state_q <= MDU_STATE_IDLE;
                    end
                end

                default: begin
                    state_q <= MDU_STATE_IDLE;
                end
            endcase
        end
    end

endmodule
