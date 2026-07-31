module rv32_imm_gen (
    input  logic [31:0]                instruction,
    input  rv32_pkg::immediate_type_e  immediate_type,
    output logic [31:0]                immediate
);

    import rv32_pkg::*;

    always_comb begin
        immediate = 32'b0;

        case (immediate_type)
            IMM_NONE: begin
                immediate = 32'b0;
            end

            IMM_I: begin
                immediate = {
                    {20{instruction[31]}},
                    instruction[31:20]
                };
            end

            IMM_S: begin
                immediate = {
                    {20{instruction[31]}},
                    instruction[31:25],
                    instruction[11:7]
                };
            end

            IMM_B: begin
                immediate = {
                    {19{instruction[31]}},
                    instruction[31],
                    instruction[7],
                    instruction[30:25],
                    instruction[11:8],
                    1'b0
                };
            end

            IMM_U: begin
                immediate = {
                    instruction[31:12],
                    12'b0
                };
            end

            IMM_J: begin
                immediate = {
                    {11{instruction[31]}},
                    instruction[31],
                    instruction[19:12],
                    instruction[20],
                    instruction[30:21],
                    1'b0
                };
            end

            default: begin
                immediate = 32'b0;
            end
        endcase
    end

endmodule
