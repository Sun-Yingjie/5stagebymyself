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
    input  logic                     mret_commit,
    input  logic                     mem_commit_candidate,
    input  logic                     commit_valid,

    input  logic                     irq_software,
    input  logic                     irq_timer,
    input  logic                     irq_external,
    input  logic [31:0]              boundary_resume_pc,
    input  logic                     empty_interrupt_boundary,

    output logic [31:0]              csr_read_data,
    output logic                     csr_access_illegal,
    output logic [31:0]              mret_target,

    output logic                     trap_take,
    output rv32_pkg::redirect_t      trap_redirect,
    output logic                     post_commit_interrupt_take,
    output logic                     empty_interrupt_take,
    output logic                     interrupt_take,
    output rv32_pkg::redirect_t      interrupt_redirect,
    output logic                     trap_valid,
    output logic [31:0]              trap_pc,
    output logic [31:0]              trap_cause,
    output logic [31:0]              trap_value
);

    import rv32_pkg::*;

    localparam logic [31:0] MISA_VALUE = 32'h4000_1100;
    localparam logic [31:0] MSTATUS_MPP = 32'h0000_1800;

    logic        mstatus_mie_q;
    logic        mstatus_mpie_q;
    logic        mie_msie_q;
    logic        mie_mtie_q;
    logic        mie_meie_q;
    logic [31:0] mtvec_q;
    logic [31:0] mscratch_q;
    logic [31:0] mepc_q;
    logic [31:0] mcause_q;
    logic [31:0] mtval_q;

    logic        mstatus_mie_d;
    logic        mstatus_mpie_d;
    logic        mie_msie_d;
    logic        mie_mtie_d;
    logic        mie_meie_d;
    logic [31:0] mtvec_d;
    logic [31:0] mscratch_d;
    logic [31:0] mepc_d;
    logic [31:0] mcause_d;
    logic [31:0] mtval_d;

    logic [63:0] mcycle_q;
    logic [63:0] minstret_q;
    logic [63:0] mcycle_d;
    logic [63:0] minstret_d;

    logic        csr_address_exists;
    logic        csr_whole_read_only;
    logic [31:0] csr_old_data;
    logic [31:0] csr_write_candidate;
    logic        csr_write_preview;
    logic        csr_write_commit;
    logic        counter_write_commit;
    logic        mret_state_commit;

    logic        effective_mstatus_mie;
    logic        effective_mstatus_mpie;
    logic        effective_mie_msie;
    logic        effective_mie_mtie;
    logic        effective_mie_meie;
    logic [31:0] effective_mtvec;
    logic [31:0] effective_mscratch;
    logic [31:0] effective_mepc;
    logic [31:0] effective_mcause;
    logic [31:0] effective_mtval;
    logic        external_interrupt_eligible;
    logic        software_interrupt_eligible;
    logic        timer_interrupt_eligible;
    logic        effective_interrupt_eligible;
    logic [31:0] selected_interrupt_cause;

    logic        interrupt_event_pending_q;
    logic [31:0] interrupt_event_pc_q;
    logic [31:0] interrupt_event_cause_q;

    rv32_csr_alu u_csr_alu (
        .csr_operation  (csr_operation),
        .csr_read_data  (csr_old_data),
        .csr_source     (csr_source),
        .csr_write_data (csr_write_candidate)
    );

    assign mret_target = mepc_q;
    assign csr_write_commit = csr_write_preview && commit_valid;
    assign counter_write_commit = csr_write_commit;
    assign mret_state_commit = mret_commit && commit_valid;

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

            CSR_ADDR_MIE: begin
                csr_old_data     = 32'b0;
                csr_old_data[11] = mie_meie_q;
                csr_old_data[7]  = mie_mtie_q;
                csr_old_data[3]  = mie_msie_q;
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

            CSR_ADDR_MIP: begin
                csr_old_data     = 32'b0;
                csr_old_data[11] = irq_external;
                csr_old_data[7]  = irq_timer;
                csr_old_data[3]  = irq_software;
            end

            CSR_ADDR_MCYCLE: begin
                csr_old_data = mcycle_q[31:0];
            end

            CSR_ADDR_MINSTRET: begin
                csr_old_data = minstret_q[31:0];
            end

            CSR_ADDR_MCYCLEH: begin
                csr_old_data = mcycle_q[63:32];
            end

            CSR_ADDR_MINSTRETH: begin
                csr_old_data = minstret_q[63:32];
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

        csr_write_preview =
            mem_commit_candidate &&
            csr_access_valid &&
            !csr_access_illegal &&
            csr_write_enable &&
            !trap_take;
    end

    always_comb begin
        effective_mstatus_mie  = mstatus_mie_q;
        effective_mstatus_mpie = mstatus_mpie_q;
        effective_mie_msie     = mie_msie_q;
        effective_mie_mtie     = mie_mtie_q;
        effective_mie_meie     = mie_meie_q;
        effective_mtvec        = mtvec_q;
        effective_mscratch     = mscratch_q;
        effective_mepc         = mepc_q;
        effective_mcause       = mcause_q;
        effective_mtval        = mtval_q;

        if (mret_commit) begin
            effective_mstatus_mie  = mstatus_mpie_q;
            effective_mstatus_mpie = 1'b1;
        end else if (csr_write_preview) begin
            case (csr_address)
                CSR_ADDR_MSTATUS: begin
                    effective_mstatus_mie  = csr_write_candidate[3];
                    effective_mstatus_mpie = csr_write_candidate[7];
                end

                CSR_ADDR_MIE: begin
                    effective_mie_msie = csr_write_candidate[3];
                    effective_mie_mtie = csr_write_candidate[7];
                    effective_mie_meie = csr_write_candidate[11];
                end

                CSR_ADDR_MTVEC: begin
                    effective_mtvec =
                        csr_write_candidate & 32'hffff_fffc;
                end

                CSR_ADDR_MSCRATCH: begin
                    effective_mscratch = csr_write_candidate;
                end

                CSR_ADDR_MEPC: begin
                    effective_mepc =
                        csr_write_candidate & 32'hffff_fffc;
                end

                CSR_ADDR_MCAUSE: begin
                    effective_mcause = csr_write_candidate;
                end

                CSR_ADDR_MTVAL: begin
                    effective_mtval = csr_write_candidate;
                end

                default: begin
                end
            endcase
        end
    end

    always_comb begin
        external_interrupt_eligible =
            effective_mstatus_mie &&
            effective_mie_meie &&
            irq_external;
        software_interrupt_eligible =
            effective_mstatus_mie &&
            effective_mie_msie &&
            irq_software;
        timer_interrupt_eligible =
            effective_mstatus_mie &&
            effective_mie_mtie &&
            irq_timer;

        effective_interrupt_eligible =
            external_interrupt_eligible ||
            software_interrupt_eligible ||
            timer_interrupt_eligible;

        selected_interrupt_cause = 32'b0;
        if (external_interrupt_eligible) begin
            selected_interrupt_cause =
                INTERRUPT_CAUSE_MACHINE_EXTERNAL;
        end else if (software_interrupt_eligible) begin
            selected_interrupt_cause =
                INTERRUPT_CAUSE_MACHINE_SOFTWARE;
        end else if (timer_interrupt_eligible) begin
            selected_interrupt_cause =
                INTERRUPT_CAUSE_MACHINE_TIMER;
        end

        post_commit_interrupt_take =
            !rst &&
            !trap_take &&
            mem_commit_candidate &&
            effective_interrupt_eligible;

        empty_interrupt_take =
            !rst &&
            !trap_take &&
            !post_commit_interrupt_take &&
            empty_interrupt_boundary &&
            effective_interrupt_eligible;

        interrupt_take =
            post_commit_interrupt_take || empty_interrupt_take;

        interrupt_redirect        = '0;
        interrupt_redirect.valid  = interrupt_take;
        interrupt_redirect.target =
            interrupt_take ? effective_mtvec : 32'b0;
    end

    always_comb begin
        trap_valid = 1'b0;
        trap_pc    = 32'b0;
        trap_cause = 32'b0;
        trap_value = 32'b0;

        if (!rst && trap_take) begin
            trap_valid = 1'b1;
            trap_pc    = mem_pc;
            trap_cause = final_mem_exception.cause;
            trap_value = final_mem_exception.value;
        end else if (!rst && interrupt_event_pending_q) begin
            trap_valid = 1'b1;
            trap_pc    = interrupt_event_pc_q;
            trap_cause = interrupt_event_cause_q;
            trap_value = 32'b0;
        end
    end

    always_comb begin
        mcycle_d   = mcycle_q + 64'd1;
        minstret_d = minstret_q + (commit_valid ? 64'd1 : 64'd0);

        if (counter_write_commit) begin
            case (csr_address)
                CSR_ADDR_MCYCLE: begin
                    mcycle_d[31:0] = csr_write_candidate;
                end

                CSR_ADDR_MCYCLEH: begin
                    mcycle_d[63:32] = csr_write_candidate;
                end

                CSR_ADDR_MINSTRET: begin
                    minstret_d[31:0] = csr_write_candidate;
                end

                CSR_ADDR_MINSTRETH: begin
                    minstret_d[63:32] = csr_write_candidate;
                end

                default: begin
                end
            endcase
        end
    end

    always_comb begin
        mstatus_mie_d  = mstatus_mie_q;
        mstatus_mpie_d = mstatus_mpie_q;
        mie_msie_d     = mie_msie_q;
        mie_mtie_d     = mie_mtie_q;
        mie_meie_d     = mie_meie_q;
        mtvec_d        = mtvec_q;
        mscratch_d     = mscratch_q;
        mepc_d         = mepc_q;
        mcause_d       = mcause_q;
        mtval_d        = mtval_q;

        if (mret_state_commit || csr_write_commit) begin
            mstatus_mie_d  = effective_mstatus_mie;
            mstatus_mpie_d = effective_mstatus_mpie;
            mie_msie_d     = effective_mie_msie;
            mie_mtie_d     = effective_mie_mtie;
            mie_meie_d     = effective_mie_meie;
            mtvec_d        = effective_mtvec;
            mscratch_d     = effective_mscratch;
            mepc_d         = effective_mepc;
            mcause_d       = effective_mcause;
            mtval_d        = effective_mtval;
        end

        if (trap_take) begin
            mstatus_mie_d  = 1'b0;
            mstatus_mpie_d = mstatus_mie_q;
            mepc_d         = mem_pc & 32'hffff_fffc;
            mcause_d       = final_mem_exception.cause;
            mtval_d        = final_mem_exception.value;
        end else if (interrupt_take) begin
            mstatus_mie_d  = 1'b0;
            mstatus_mpie_d = effective_mstatus_mie;
            mie_msie_d     = effective_mie_msie;
            mie_mtie_d     = effective_mie_mtie;
            mie_meie_d     = effective_mie_meie;
            mtvec_d        = effective_mtvec;
            mscratch_d     = effective_mscratch;
            mepc_d         = boundary_resume_pc & 32'hffff_fffc;
            mcause_d       = selected_interrupt_cause;
            mtval_d        = 32'b0;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            mstatus_mie_q  <= 1'b0;
            mstatus_mpie_q <= 1'b0;
            mie_msie_q     <= 1'b0;
            mie_mtie_q     <= 1'b0;
            mie_meie_q     <= 1'b0;
            mtvec_q        <= MTVEC_RESET & 32'hffff_fffc;
            mscratch_q     <= 32'b0;
            mepc_q         <= 32'b0;
            mcause_q       <= 32'b0;
            mtval_q        <= 32'b0;
            mcycle_q       <= 64'b0;
            minstret_q     <= 64'b0;
            interrupt_event_pending_q <= 1'b0;
            interrupt_event_pc_q      <= 32'b0;
            interrupt_event_cause_q   <= 32'b0;
        end else begin
            mstatus_mie_q  <= mstatus_mie_d;
            mstatus_mpie_q <= mstatus_mpie_d;
            mie_msie_q     <= mie_msie_d;
            mie_mtie_q     <= mie_mtie_d;
            mie_meie_q     <= mie_meie_d;
            mtvec_q        <= mtvec_d;
            mscratch_q     <= mscratch_d;
            mepc_q         <= mepc_d;
            mcause_q       <= mcause_d;
            mtval_q        <= mtval_d;
            mcycle_q   <= mcycle_d;
            minstret_q <= minstret_d;

            interrupt_event_pending_q <= interrupt_take;
            if (interrupt_take) begin
                interrupt_event_pc_q <=
                    boundary_resume_pc & 32'hffff_fffc;
                interrupt_event_cause_q <= selected_interrupt_cause;
            end
        end
    end

endmodule
