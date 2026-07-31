module rv32_csr_alu (
    input  rv32_pkg::csr_operation_e       csr_operation,
    input  logic [31:0]                    csr_read_data,
    input  logic [31:0]                    csr_source,
    output logic [31:0]                    csr_write_data
);

    import rv32_pkg::*;

    always_comb begin
        csr_write_data = 32'b0;

        case (csr_operation)
            CSR_WRITE: begin
                csr_write_data = csr_source;
            end

            CSR_SET: begin
                csr_write_data = csr_read_data | csr_source;
            end

            CSR_CLEAR: begin
                csr_write_data = csr_read_data & ~csr_source;
            end

            default: begin
                csr_write_data = 32'b0;
            end
        endcase
    end
endmodule
