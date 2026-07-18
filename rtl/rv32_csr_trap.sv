module rv32_csr_trap #(
    parameter logic [31:0] MTVEC_RESET = 32'h0000_0000
) (
    input  logic                     clk,
    input  logic                     rst,

    input  logic                     mem_valid,
    input  logic [31:0]              mem_pc,
    input  logic [31:0]              mem_instruction,
    input  logic                     mem_response_wait,

    input  logic                     csr_access_valid,
    input  logic [11:0]              csr_address,
    input  rv32_pkg::csr_operation_e csr_operation,
    input  logic [31:0]              csr_source,
    input  logic                     csr_read_enable,
    input  logic                     csr_write_enable,

    input  rv32_pkg::exception_t     final_mem_exception,

    output logic [31:0]              csr_read_data,
    output logic                     csr_access_illegal,

    output logic                     trap_take,
    output rv32_pkg::redirect_t      trap_redirect,
    output logic                     trap_valid,
    output logic [31:0]              trap_pc,
    output logic [31:0]              trap_cause,
    output logic [31:0]              trap_value
);

    import rv32_pkg::*;

    localparam logic [31:0] MISA_VALUE = 32'h4000_0100;
    localparam logic [31:0] MSTATUS_MPP = 32'h0000_1800;

    logic        mstatus_mie_q;
    logic        mstatus_mpie_q;
    logic [31:0] mtvec_q;
    logic [31:0] mscratch_q;
    logic [31:0] mepc_q;
    logic [31:0] mcause_q;
    logic [31:0] mtval_q;

    logic        csr_address_exists;
    logic        csr_whole_read_only;
    logic [31:0] csr_old_data;
    logic [31:0] csr_write_candidate;
    logic        csr_write_commit;

    rv32_csr_alu u_csr_alu (
        .csr_operation  (csr_operation),
        .csr_read_data  (csr_old_data),
        .csr_source     (csr_source),
        .csr_write_data (csr_write_candidate)
    );

    always_comb begin
        csr_address_exists  = 1'b1;
        csr_whole_read_only = 1'b0;
        csr_old_data        = 32'b0;

        case (csr_address)
            CSR_ADDR_MSTATUS: begin
                csr_old_data    = MSTATUS_MPP;
                csr_old_data[7] = mstatus_mpie_q;
                csr_old_data[3] = mstatus_mie_q;
            end

            CSR_ADDR_MISA: begin
                csr_old_data = MISA_VALUE;
            end

            CSR_ADDR_MTVEC: begin
                csr_old_data = mtvec_q;
            end

            CSR_ADDR_MSCRATCH: begin
                csr_old_data = mscratch_q;
            end

            CSR_ADDR_MEPC: begin
                csr_old_data = mepc_q;
            end

            CSR_ADDR_MCAUSE: begin
                csr_old_data = mcause_q;
            end

            CSR_ADDR_MTVAL: begin
                csr_old_data = mtval_q;
            end

            CSR_ADDR_MVENDORID,
            CSR_ADDR_MARCHID,
            CSR_ADDR_MIMPID,
            CSR_ADDR_MHARTID,
            CSR_ADDR_MCONFIGPTR: begin
                csr_whole_read_only = 1'b1;
                csr_old_data        = 32'b0;
            end

            default: begin
                csr_address_exists = 1'b0;
                csr_old_data       = 32'b0;
            end
        endcase

        csr_access_illegal =
            csr_access_valid &&
            (
                !csr_address_exists ||
                (csr_write_enable && csr_whole_read_only)
            );

        csr_read_data = 32'b0;
        if (
            csr_access_valid &&
            !csr_access_illegal &&
            csr_read_enable
        ) begin
            csr_read_data = csr_old_data;
        end
    end

    always_comb begin
        trap_take =
            !rst &&
            mem_valid &&
            final_mem_exception.valid &&
            !mem_response_wait;

        trap_redirect        = '0;
        trap_redirect.valid  = trap_take;
        trap_redirect.target = trap_take ? mtvec_q : 32'b0;

        trap_valid = trap_take;
        trap_pc    = trap_take ? mem_pc : 32'b0;
        trap_cause = trap_take ? final_mem_exception.cause : 32'b0;
        trap_value = trap_take ? final_mem_exception.value : 32'b0;

        csr_write_commit =
            csr_access_valid &&
            !csr_access_illegal &&
            csr_write_enable &&
            !trap_take;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            mstatus_mie_q  <= 1'b0;
            mstatus_mpie_q <= 1'b0;
            mtvec_q        <= MTVEC_RESET & 32'hffff_fffc;
            mscratch_q     <= 32'b0;
            mepc_q         <= 32'b0;
            mcause_q       <= 32'b0;
            mtval_q        <= 32'b0;
        end else if (trap_take) begin
            mstatus_mie_q  <= 1'b0;
            mstatus_mpie_q <= mstatus_mie_q;
            mepc_q         <= mem_pc & 32'hffff_fffc;
            mcause_q       <= final_mem_exception.cause;
            mtval_q        <= final_mem_exception.value;
        end else if (csr_write_commit) begin
            case (csr_address)
                CSR_ADDR_MSTATUS: begin
                    mstatus_mie_q  <= csr_write_candidate[3];
                    mstatus_mpie_q <= csr_write_candidate[7];
                end

                CSR_ADDR_MISA: begin
                    // The supported ISA is fixed; writes are legal WARL writes.
                end

                CSR_ADDR_MTVEC: begin
                    mtvec_q <= csr_write_candidate & 32'hffff_fffc;
                end

                CSR_ADDR_MSCRATCH: begin
                    mscratch_q <= csr_write_candidate;
                end

                CSR_ADDR_MEPC: begin
                    mepc_q <= csr_write_candidate & 32'hffff_fffc;
                end

                CSR_ADDR_MCAUSE: begin
                    mcause_q <= csr_write_candidate;
                end

                CSR_ADDR_MTVAL: begin
                    mtval_q <= csr_write_candidate;
                end

                default: begin
                end
            endcase
        end
    end

endmodule
