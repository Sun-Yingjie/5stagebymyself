module rv32_branch_compare (
    input  logic [31:0]                       operand_a,
    input  logic [31:0]                       operand_b,
    input  rv32_pkg::branch_operation_e       branch_operation,
    output logic                              branch_taken
);

    import rv32_pkg::*;

    logic equal;
    logic signed_less_than;
    logic unsigned_less_than;

    assign equal =
        operand_a == operand_b;

    assign signed_less_than =
        $signed(operand_a) < $signed(operand_b);

    assign unsigned_less_than =
        operand_a < operand_b;

    always_comb begin
        branch_taken = 1'b0;

        case (branch_operation)
            BR_NONE: begin
                branch_taken = 1'b0;
            end

            BR_EQ: begin
                branch_taken = equal;
            end

            BR_NE: begin
                branch_taken = !equal;
            end

            BR_LT: begin
                branch_taken = signed_less_than;
            end

            BR_GE: begin
                branch_taken = !signed_less_than;
            end

            BR_LTU: begin
                branch_taken = unsigned_less_than;
            end

            BR_GEU: begin
                branch_taken = !unsigned_less_than;
            end

            default: begin
                branch_taken = 1'b0;
            end
        endcase
    end
endmodule
