module rv32_csr_decoder (
    input  logic [31:0]              instruction,
    output rv32_pkg::csr_ctrl_t      csr_ctrl,
    output logic                     uses_rs1
);

    import rv32_pkg::*;

    always_comb begin
        csr_ctrl = '0;
        uses_rs1 = 1'b0;

        if (instruction[6:0] == OPCODE_SYSTEM) begin
            case (instruction[14:12])
                FUNCT3_CSRRW: begin
                    csr_ctrl.valid = 1'b1;
                    csr_ctrl.operation = CSR_WRITE;
                    csr_ctrl.read_enable = instruction[11:7] != 5'b0;
                    csr_ctrl.write_enable = 1'b1;
                    uses_rs1 = 1'b1;
                end

                FUNCT3_CSRRS: begin
                    csr_ctrl.valid = 1'b1;
                    csr_ctrl.operation = CSR_SET;
                    csr_ctrl.read_enable = 1'b1;
                    csr_ctrl.write_enable = instruction[19:15] != 5'b0;
                    uses_rs1 = 1'b1;
                end

                FUNCT3_CSRRC: begin
                    csr_ctrl.valid = 1'b1;
                    csr_ctrl.operation = CSR_CLEAR;
                    csr_ctrl.read_enable = 1'b1;
                    csr_ctrl.write_enable = instruction[19:15] != 5'b0;
                    uses_rs1 = 1'b1;
                end

                FUNCT3_CSRRWI: begin
                    csr_ctrl.valid = 1'b1;
                    csr_ctrl.operation = CSR_WRITE;
                    csr_ctrl.use_immediate = 1'b1;
                    csr_ctrl.read_enable = instruction[11:7] != 5'b0;
                    csr_ctrl.write_enable = 1'b1;
                end

                FUNCT3_CSRRSI: begin
                    csr_ctrl.valid = 1'b1;
                    csr_ctrl.operation = CSR_SET;
                    csr_ctrl.use_immediate = 1'b1;
                    csr_ctrl.read_enable = 1'b1;
                    csr_ctrl.write_enable = instruction[19:15] != 5'b0;
                end

                FUNCT3_CSRRCI: begin
                    csr_ctrl.valid = 1'b1;
                    csr_ctrl.operation = CSR_CLEAR;
                    csr_ctrl.use_immediate = 1'b1;
                    csr_ctrl.read_enable = 1'b1;
                    csr_ctrl.write_enable = instruction[19:15] != 5'b0;
                end

                default: begin
                    csr_ctrl = '0;
                    uses_rs1 = 1'b0;
                end
            endcase
        end
    end
endmodule
