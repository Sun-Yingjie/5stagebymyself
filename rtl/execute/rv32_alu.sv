module rv32_alu (
    input  logic [31:0]                    operand_a,
    input  logic [31:0]                    operand_b,
    input  rv32_pkg::alu_operation_e       alu_operation,
    output logic [31:0]                    result
);

    import rv32_pkg::*;
    always_comb begin
        result = 32'b0;

        case (alu_operation)
            ALU_ADD: begin
                result = operand_a + operand_b;
            end

            ALU_SUB: begin
                result = operand_a - operand_b;
            end

            ALU_XOR: begin
                result = operand_a ^ operand_b;
            end

            ALU_OR: begin
                result = operand_a | operand_b;
            end

            ALU_AND: begin
                result = operand_a & operand_b;
            end

            ALU_SLL: begin
                result = operand_a << operand_b[4:0];
            end

            ALU_SRL: begin
                result = operand_a >> operand_b[4:0];
            end

            ALU_SRA: begin
                result = $signed(operand_a) >>> operand_b[4:0];
            end

            ALU_SLT: begin
                result = {
                    31'b0,
                    $signed(operand_a) < $signed(operand_b)
                };
            end

            ALU_SLTU: begin
                result = {
                    31'b0,
                    operand_a < operand_b
                };
            end
            
            default: begin
                result = 32'b0;
            end
        endcase
    end
endmodule
