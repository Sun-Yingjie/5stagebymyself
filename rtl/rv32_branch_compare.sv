module rv32_branch_compare (
    input  logic [31:0]                       operand_a,
    input  logic [31:0]                       operand_b,
    input  rv32_pkg::branch_operation_e       branch_operation,
    output logic                              branch_taken
);

    import rv32_pkg::*;

endmodule
