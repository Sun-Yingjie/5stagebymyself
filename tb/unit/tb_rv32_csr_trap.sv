module tb_rv32_csr_trap;

    timeunit 1ns;
    timeprecision 1ps;

    import rv32_pkg::*;

    logic           clk;
    logic           rst;
    logic           mem_valid;
    logic [31:0]    mem_pc;
    logic [31:0]    mem_instruction;
    logic           mem_response_wait;
    logic           csr_access_valid;
    logic [11:0]    csr_address;
    csr_operation_e csr_operation;
    logic [31:0]    csr_source;
    logic           csr_read_enable;
    logic           csr_write_enable;
    exception_t     final_mem_exception;
    logic           mret_commit;
    logic           mem_commit_candidate;
    logic           commit_valid;
    logic           irq_software;
    logic           irq_timer;
    logic           irq_external;
    logic [31:0]    boundary_resume_pc;
    logic           empty_interrupt_boundary;
    logic [31:0]    csr_read_data;
    logic           csr_access_illegal;
    logic [31:0]    mret_target;
    logic           trap_take;
    redirect_t      trap_redirect;
    logic           post_commit_interrupt_take;
    logic           empty_interrupt_take;
    logic           interrupt_take;
    redirect_t      interrupt_redirect;
    logic           trap_valid;
    logic [31:0]    trap_pc;
    logic [31:0]    trap_cause;
    logic [31:0]    trap_value;

    int unsigned error_count;

    rv32_csr_trap #(
        .MTVEC_RESET (32'h0000_0102)
    ) dut (
        .clk                 (clk),
        .rst                 (rst),
        .mem_valid           (mem_valid),
        .mem_pc              (mem_pc),
        .mem_instruction     (mem_instruction),
        .mem_response_wait   (mem_response_wait),
        .csr_access_valid    (csr_access_valid),
        .csr_address         (csr_address),
        .csr_operation       (csr_operation),
        .csr_source          (csr_source),
        .csr_read_enable     (csr_read_enable),
        .csr_write_enable    (csr_write_enable),
        .final_mem_exception (final_mem_exception),
        .mret_commit         (mret_commit),
        .mem_commit_candidate(mem_commit_candidate),
        .commit_valid        (commit_valid),
        .irq_software        (irq_software),
        .irq_timer           (irq_timer),
        .irq_external        (irq_external),
        .boundary_resume_pc  (boundary_resume_pc),
        .empty_interrupt_boundary(empty_interrupt_boundary),
        .csr_read_data       (csr_read_data),
        .csr_access_illegal  (csr_access_illegal),
        .mret_target         (mret_target),
        .trap_take           (trap_take),
        .trap_redirect       (trap_redirect),
        .post_commit_interrupt_take(post_commit_interrupt_take),
        .empty_interrupt_take(empty_interrupt_take),
        .interrupt_take      (interrupt_take),
        .interrupt_redirect  (interrupt_redirect),
        .trap_valid          (trap_valid),
        .trap_pc             (trap_pc),
        .trap_cause          (trap_cause),
        .trap_value          (trap_value)
    );

    always #5ns clk = ~clk;

    initial begin
        clk         = 1'b0;
        rst         = 1'b0;
        error_count = 0;
        set_idle_inputs();

        reset_dut();
        test_reset_profile();
        test_machine_counters();
        test_mscratch_rmw();
        test_fixed_and_read_only_csrs();
        test_unknown_and_invalid_accesses();
        test_warl_fields();
        test_trap_wait_and_commit();
        test_trap_priority_over_explicit_write();
        test_mret_restore();
        test_mie_mip_csrs();
        test_interrupt_masking_and_causes();
        test_interrupt_priority();
        test_interrupt_entry_and_event();
        test_empty_interrupt_boundary();
        test_post_commit_preview();
        test_mret_immediate_interrupt();
        test_interrupt_exception_priority_and_reset();

        if (error_count != 0) begin
            $fatal(
                1,
                "[FAIL] rv32_csr_trap: %0d check(s) failed",
                error_count
            );
        end

        $display("[PASS] rv32_csr_trap: all tests passed");
        $finish;
    end

    task automatic reset_dut;
        begin
            @(negedge clk);
            set_idle_inputs();
            rst = 1'b1;

            csr_access_valid          = 1'b1;
            csr_address               = CSR_ADDR_MSCRATCH;
            csr_operation             = CSR_WRITE;
            csr_source                = 32'hffff_ffff;
            csr_read_enable           = 1'b1;
            csr_write_enable          = 1'b1;
            mem_valid                 = 1'b1;
            mem_pc                    = 32'h0000_0123;
            mem_instruction           = 32'hffff_ffff;
            mem_response_wait         = 1'b0;
            final_mem_exception.valid = 1'b1;
            final_mem_exception.cause =
                EXCEPTION_CAUSE_ILLEGAL_INSTRUCTION;
            final_mem_exception.value = 32'hffff_ffff;
            mret_commit               = 1'b1;
            mem_commit_candidate      = 1'b1;
            commit_valid              = 1'b1;
            irq_software              = 1'b1;
            irq_timer                 = 1'b1;
            irq_external              = 1'b1;
            boundary_resume_pc        = 32'hffff_fffc;
            empty_interrupt_boundary  = 1'b1;
            #1ns;

            check_condition(!trap_take,
                            "reset suppresses trap_take");
            check_condition(!trap_redirect.valid,
                            "reset suppresses trap redirect");
            check_condition(!trap_valid,
                            "reset suppresses trap trace");
            check_condition(
                !post_commit_interrupt_take &&
                !empty_interrupt_take &&
                !interrupt_take &&
                !interrupt_redirect.valid,
                "reset suppresses all interrupt actions"
            );

            repeat (2) @(posedge clk);

            @(negedge clk);
            set_idle_inputs();
            rst = 1'b0;
            #1ns;
        end
    endtask

    task automatic test_machine_counters;
        logic [63:0] cycle_before;
        logic [63:0] instret_before;
        begin
            reset_dut();
            check_condition(
                (dut.mcycle_q == 64'b0) &&
                (dut.minstret_q == 64'b0),
                "Machine counters reset to zero"
            );

            pulse_commit(1'b0);
            pulse_commit(1'b0);
            pulse_commit(1'b0);
            check_condition(
                (dut.mcycle_q == 64'd3) &&
                (dut.minstret_q == 64'd0),
                "mcycle advances while minstret waits for commit"
            );

            pulse_commit(1'b1);
            check_condition(
                (dut.mcycle_q == 64'd4) &&
                (dut.minstret_q == 64'd1),
                "commit increments both mcycle and minstret once"
            );

            reset_dut();
            apply_counter_access(
                CSR_ADDR_MCYCLEH,
                CSR_WRITE,
                32'b0,
                1'b1,
                1'b1,
                32'b0,
                "write mcycle high half"
            );
            apply_counter_access(
                CSR_ADDR_MCYCLE,
                CSR_WRITE,
                32'hffff_ffff,
                1'b1,
                1'b1,
                32'd1,
                "write mcycle low half"
            );
            pulse_commit(1'b0);
            check_condition(
                dut.mcycle_q == 64'h0000_0001_0000_0000,
                "mcycle low-half overflow carries into high half"
            );

            reset_dut();
            apply_counter_access(
                CSR_ADDR_MINSTRETH,
                CSR_WRITE,
                32'b0,
                1'b1,
                1'b1,
                32'b0,
                "write minstret high half"
            );
            apply_counter_access(
                CSR_ADDR_MINSTRET,
                CSR_WRITE,
                32'hffff_ffff,
                1'b1,
                1'b1,
                32'd1,
                "write minstret low half"
            );
            pulse_commit(1'b1);
            check_condition(
                dut.minstret_q == 64'h0000_0001_0000_0000,
                "minstret low-half overflow carries into high half"
            );

            reset_dut();
            apply_counter_access(
                CSR_ADDR_MCYCLE,
                CSR_WRITE,
                32'h0000_000f,
                1'b1,
                1'b1,
                32'b0,
                "prepare mcycle for SET/CLEAR"
            );
            apply_counter_access(
                CSR_ADDR_MCYCLE,
                CSR_SET,
                32'h0000_00f0,
                1'b1,
                1'b1,
                32'h0000_000f,
                "mcycle SET uses the pre-update old value"
            );
            check_condition(
                dut.mcycle_q[31:0] == 32'h0000_00ff,
                "mcycle SET result overrides automatic low-half update"
            );
            apply_counter_access(
                CSR_ADDR_MCYCLE,
                CSR_CLEAR,
                32'h0000_000c,
                1'b1,
                1'b1,
                32'h0000_00ff,
                "mcycle CLEAR uses the pre-update old value"
            );
            check_condition(
                dut.mcycle_q[31:0] == 32'h0000_00f3,
                "mcycle CLEAR result overrides automatic low-half update"
            );

            cycle_before = dut.mcycle_q;
            instret_before = dut.minstret_q;
            apply_counter_access(
                CSR_ADDR_MCYCLE,
                CSR_SET,
                32'b0,
                1'b1,
                1'b0,
                cycle_before[31:0],
                "suppressed counter write remains a pure read"
            );
            check_condition(
                (dut.mcycle_q == (cycle_before + 64'd1)) &&
                (dut.minstret_q == (instret_before + 64'd1)),
                "suppressed write preserves automatic counter updates"
            );
        end
    endtask

    task automatic test_mret_restore;
        logic [31:0] initial_mstatus;
        logic [31:0] expected_mstatus;
        int unsigned mie_value;
        int unsigned mpie_value;
        begin
            for (mie_value = 0; mie_value < 2; mie_value++) begin
                for (mpie_value = 0; mpie_value < 2; mpie_value++) begin
                    reset_dut();

                    initial_mstatus =
                        32'h0000_1800 |
                        (mie_value << 3) |
                        (mpie_value << 7);
                    apply_access(
                        CSR_ADDR_MSTATUS,
                        CSR_WRITE,
                        initial_mstatus,
                        1'b1,
                        1'b1,
                        32'h0000_1800,
                        1'b0,
                        "prepare MIE/MPIE before MRET"
                    );
                    apply_access(
                        CSR_ADDR_MEPC,
                        CSR_WRITE,
                        32'h0000_0457,
                        1'b1,
                        1'b1,
                        32'b0,
                        1'b0,
                        "prepare aligned MRET target"
                    );

                    @(negedge clk);
                    set_idle_inputs();
                    mret_commit          = 1'b1;
                    mem_commit_candidate = 1'b1;
                    commit_valid         = 1'b1;
                    boundary_resume_pc   = 32'h0000_0454;
                    #1ns;
                    check_condition(
                        mret_target == 32'h0000_0454,
                        "MRET redirect uses pre-edge aligned mepc"
                    );
                    check_condition(
                        !trap_take && !trap_valid,
                        "MRET is not reported as a trap"
                    );

                    @(posedge clk);
                    #1ns;
                    @(negedge clk);
                    set_idle_inputs();

                    expected_mstatus =
                        32'h0000_1800 |
                        32'h0000_0080 |
                        (mpie_value << 3);
                    check_csr_value(
                        CSR_ADDR_MSTATUS,
                        expected_mstatus,
                        "MRET restores MIE from old MPIE and sets MPIE"
                    );
                    check_csr_value(
                        CSR_ADDR_MEPC,
                        32'h0000_0454,
                        "MRET leaves mepc unchanged"
                    );
                end
            end

            reset_dut();
            apply_access(
                CSR_ADDR_MSTATUS,
                CSR_WRITE,
                32'h0000_1888,
                1'b1,
                1'b1,
                32'h0000_1800,
                1'b0,
                "prepare MRET versus trap priority"
            );
            drive_trap_inputs(
                32'h0000_0800,
                32'hffff_ffff,
                EXCEPTION_CAUSE_ILLEGAL_INSTRUCTION,
                32'hffff_ffff,
                1'b0
            );
            mret_commit = 1'b1;
            #1ns;
            check_condition(trap_take, "trap wins over simultaneous MRET");
            @(posedge clk);
            #1ns;
            @(negedge clk);
            set_idle_inputs();
            check_csr_value(
                CSR_ADDR_MSTATUS,
                32'h0000_1880,
                "trap state update wins over MRET restore"
            );
        end
    endtask

    task automatic test_reset_profile;
        begin
            check_condition(!trap_take, "reset leaves trap_take low");
            check_condition(!trap_redirect.valid,
                            "reset leaves trap redirect invalid");
            check_condition(!trap_valid, "reset leaves trap trace invalid");

            check_csr_value(CSR_ADDR_MSTATUS, 32'h0000_1800,
                            "mstatus reset profile");
            check_csr_value(CSR_ADDR_MISA, 32'h4000_1100,
                            "misa reports RV32IM");
            check_csr_value(CSR_ADDR_MTVEC, 32'h0000_0100,
                            "mtvec reset is aligned and Direct");
            check_csr_value(CSR_ADDR_MSCRATCH, 32'b0,
                            "mscratch reset");
            check_csr_value(CSR_ADDR_MEPC, 32'b0, "mepc reset");
            check_csr_value(CSR_ADDR_MCAUSE, 32'b0, "mcause reset");
            check_csr_value(CSR_ADDR_MTVAL, 32'b0, "mtval reset");
            check_csr_value(CSR_ADDR_MVENDORID, 32'b0,
                            "mvendorid reads zero");
            check_csr_value(CSR_ADDR_MARCHID, 32'b0,
                            "marchid reads zero");
            check_csr_value(CSR_ADDR_MIMPID, 32'b0,
                            "mimpid reads zero");
            check_csr_value(CSR_ADDR_MHARTID, 32'b0,
                            "mhartid identifies hart zero");
            check_csr_value(CSR_ADDR_MCONFIGPTR, 32'b0,
                            "mconfigptr reads zero");
        end
    endtask

    task automatic test_mscratch_rmw;
        begin
            reset_dut();

            apply_access(
                CSR_ADDR_MSCRATCH,
                CSR_WRITE,
                32'ha5a5_5a5a,
                1'b1,
                1'b1,
                32'b0,
                1'b0,
                "prepare nonzero mscratch before read suppression"
            );
            apply_access(
                CSR_ADDR_MSCRATCH,
                CSR_WRITE,
                32'b0,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "CSRRW rd=x0 suppresses nonzero old value but writes zero"
            );
            check_csr_value(CSR_ADDR_MSCRATCH, 32'b0,
                            "CSRRW rd=x0 source zero still commits");

            apply_access(
                CSR_ADDR_MSCRATCH,
                CSR_WRITE,
                32'hf0f0_00ff,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "CSRRW rd=x0 writes mscratch without reading"
            );
            check_csr_value(CSR_ADDR_MSCRATCH, 32'hf0f0_00ff,
                            "mscratch WRITE commits");

            apply_access(
                CSR_ADDR_MSCRATCH,
                CSR_SET,
                32'h0f00_f000,
                1'b1,
                1'b1,
                32'hf0f0_00ff,
                1'b0,
                "CSRRS returns old mscratch value"
            );
            check_csr_value(CSR_ADDR_MSCRATCH, 32'hfff0_f0ff,
                            "mscratch SET uses OR");

            apply_access(
                CSR_ADDR_MSCRATCH,
                CSR_CLEAR,
                32'h00f0_00f0,
                1'b1,
                1'b1,
                32'hfff0_f0ff,
                1'b0,
                "CSRRC returns old mscratch value"
            );
            check_csr_value(CSR_ADDR_MSCRATCH, 32'hff00_f00f,
                            "mscratch CLEAR uses AND-NOT");
        end
    endtask

    task automatic test_fixed_and_read_only_csrs;
        begin
            reset_dut();

            apply_access(
                CSR_ADDR_MISA,
                CSR_WRITE,
                32'hffff_ffff,
                1'b1,
                1'b1,
                32'h4000_1100,
                1'b0,
                "misa fixed WARL write is legal"
            );
            check_csr_value(CSR_ADDR_MISA, 32'h4000_1100,
                            "misa ignores unsupported write value");

            apply_access(
                CSR_ADDR_MVENDORID,
                CSR_SET,
                32'hffff_ffff,
                1'b1,
                1'b0,
                32'b0,
                1'b0,
                "suppressed MRO write remains a legal read"
            );

            apply_access(
                CSR_ADDR_MVENDORID,
                CSR_SET,
                32'h0000_0001,
                1'b1,
                1'b1,
                32'b0,
                1'b1,
                "real MRO write is illegal"
            );

            apply_access(
                CSR_ADDR_MVENDORID,
                CSR_WRITE,
                32'h0000_0001,
                1'b0,
                1'b1,
                32'b0,
                1'b1,
                "CSRRW rd=x0 still attempts an illegal MRO write"
            );
            check_csr_value(CSR_ADDR_MVENDORID, 32'b0,
                            "illegal MRO write has no state effect");
        end
    endtask

    task automatic test_unknown_and_invalid_accesses;
        begin
            reset_dut();
            apply_access(
                CSR_ADDR_MSCRATCH,
                CSR_WRITE,
                32'hff00_f00f,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "prepare mscratch sentinel for invalid accesses"
            );

            apply_access(
                12'h302,
                CSR_SET,
                32'b0,
                1'b1,
                1'b0,
                32'b0,
                1'b1,
                "unknown CSR read is illegal"
            );

            apply_access(
                12'h302,
                CSR_WRITE,
                32'h1234_5678,
                1'b0,
                1'b1,
                32'b0,
                1'b1,
                "unknown CSR write is illegal"
            );

            apply_access(
                CSR_ADDR_MSCRATCH,
                CSR_WRITE,
                32'h1234_5678,
                1'b1,
                1'b0,
                32'hff00_f00f,
                1'b0,
                "write_enable=0 returns old writable CSR value"
            );
            check_csr_value(
                CSR_ADDR_MSCRATCH,
                32'hff00_f00f,
                "write_enable=0 cannot modify writable CSR"
            );

            @(negedge clk);
            csr_access_valid = 1'b0;
            csr_address      = CSR_ADDR_MSCRATCH;
            csr_operation    = CSR_WRITE;
            csr_source       = 32'h8765_4321;
            csr_read_enable  = 1'b1;
            csr_write_enable = 1'b1;
            #1ns;

            check_condition(!csr_access_illegal,
                            "invalid CSR request cannot be illegal");
            check_condition(csr_read_data == 32'b0,
                            "invalid CSR request returns zero");

            @(posedge clk);
            @(negedge clk);
            set_csr_idle();

            check_csr_value(CSR_ADDR_MSCRATCH, 32'hff00_f00f,
                            "access_valid=0 cannot modify writable CSR");
        end
    endtask

    task automatic test_warl_fields;
        int unsigned low_bits;
        begin
            reset_dut();

            for (low_bits = 0; low_bits < 4; low_bits++) begin
                apply_access(
                    CSR_ADDR_MTVEC,
                    CSR_WRITE,
                    32'h0000_0240 | low_bits,
                    1'b0,
                    1'b1,
                    32'b0,
                    1'b0,
                    $sformatf("mtvec low bits %0d legalize", low_bits)
                );
                check_csr_value(
                    CSR_ADDR_MTVEC,
                    32'h0000_0240,
                    $sformatf("mtvec low bits %0d read aligned", low_bits)
                );
            end

            for (low_bits = 0; low_bits < 4; low_bits++) begin
                apply_access(
                    CSR_ADDR_MEPC,
                    CSR_WRITE,
                    32'h0000_0340 | low_bits,
                    1'b0,
                    1'b1,
                    32'b0,
                    1'b0,
                    $sformatf("mepc low bits %0d legalize", low_bits)
                );
                check_csr_value(
                    CSR_ADDR_MEPC,
                    32'h0000_0340,
                    $sformatf("mepc low bits %0d read aligned", low_bits)
                );
            end

            apply_access(
                CSR_ADDR_MSTATUS,
                CSR_WRITE,
                32'hffff_ffff,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "mstatus accepts a legal WARL write"
            );
            check_csr_value(CSR_ADDR_MSTATUS, 32'h0000_1888,
                            "mstatus retains only MIE MPIE and MPP");

            apply_access(
                CSR_ADDR_MSTATUS,
                CSR_CLEAR,
                32'h0000_0008,
                1'b1,
                1'b1,
                32'h0000_1888,
                1'b0,
                "mstatus CLEAR returns old value"
            );
            check_csr_value(CSR_ADDR_MSTATUS, 32'h0000_1880,
                            "mstatus CLEAR updates MIE only");

            apply_access(
                CSR_ADDR_MCAUSE,
                CSR_WRITE,
                32'hdead_beef,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "mcause explicit write"
            );
            check_csr_value(CSR_ADDR_MCAUSE, 32'hdead_beef,
                            "mcause retains explicit WLRL choice");

            apply_access(
                CSR_ADDR_MTVAL,
                CSR_WRITE,
                32'hcafe_babe,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "mtval explicit write"
            );
            check_csr_value(CSR_ADDR_MTVAL, 32'hcafe_babe,
                            "mtval retains all bits");
        end
    endtask

    task automatic test_trap_wait_and_commit;
        begin
            reset_dut();

            apply_access(
                CSR_ADDR_MTVEC,
                CSR_WRITE,
                32'h0000_0280,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "program Direct trap vector"
            );
            apply_access(
                CSR_ADDR_MSTATUS,
                CSR_WRITE,
                32'h0000_0008,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "enable mstatus.MIE before trap"
            );
            apply_access(
                CSR_ADDR_MEPC,
                CSR_WRITE,
                32'h0000_0340,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "prepare mepc sentinel before waiting trap"
            );
            apply_access(
                CSR_ADDR_MCAUSE,
                CSR_WRITE,
                32'hdead_beef,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "prepare mcause sentinel before waiting trap"
            );
            apply_access(
                CSR_ADDR_MTVAL,
                CSR_WRITE,
                32'hcafe_babe,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "prepare mtval sentinel before waiting trap"
            );

            drive_trap_inputs(
                32'h0000_0123,
                32'h0000_0003,
                EXCEPTION_CAUSE_LOAD_ACCESS_FAULT,
                32'hbad0_1000,
                1'b1
            );
            #1ns;
            check_condition(!trap_take,
                            "MEM response wait suppresses trap_take");
            check_condition(!trap_redirect.valid,
                            "MEM response wait suppresses redirect");
            check_condition(trap_redirect.target == 32'b0,
                            "suppressed redirect target is zero");
            check_condition(!trap_valid,
                            "MEM response wait suppresses trap trace");
            check_condition(
                (trap_pc == 32'b0) &&
                (trap_cause == 32'b0) &&
                (trap_value == 32'b0),
                "suppressed trap trace payload is zero"
            );

            @(posedge clk);
            @(negedge clk);
            set_mem_idle();

            check_csr_value(CSR_ADDR_MEPC, 32'h0000_0340,
                            "waiting trap does not update mepc");
            check_csr_value(CSR_ADDR_MCAUSE, 32'hdead_beef,
                            "waiting trap does not update mcause");
            check_csr_value(CSR_ADDR_MTVAL, 32'hcafe_babe,
                            "waiting trap does not update mtval");
            check_csr_value(CSR_ADDR_MSTATUS, 32'h0000_1808,
                            "waiting trap does not update mstatus");

            drive_trap_inputs(
                32'h0000_0123,
                32'h0000_0003,
                EXCEPTION_CAUSE_LOAD_ACCESS_FAULT,
                32'hbad0_1000,
                1'b0
            );
            #1ns;
            check_condition(trap_take, "ready exception takes trap");
            check_condition(
                trap_redirect.valid &&
                (trap_redirect.target == 32'h0000_0280),
                "trap redirects to current Direct mtvec"
            );
            check_condition(
                trap_valid &&
                (trap_pc == 32'h0000_0123) &&
                (trap_cause == EXCEPTION_CAUSE_LOAD_ACCESS_FAULT) &&
                (trap_value == 32'hbad0_1000),
                "trap trace reports the committing exception"
            );

            @(posedge clk);
            #1ns;
            @(negedge clk);
            set_mem_idle();

            check_csr_value(CSR_ADDR_MEPC, 32'h0000_0120,
                            "trap aligns and records mepc");
            check_csr_value(
                CSR_ADDR_MCAUSE,
                EXCEPTION_CAUSE_LOAD_ACCESS_FAULT,
                "trap records mcause"
            );
            check_csr_value(CSR_ADDR_MTVAL, 32'hbad0_1000,
                            "trap records mtval");
            check_csr_value(CSR_ADDR_MSTATUS, 32'h0000_1880,
                            "trap stacks MIE into MPIE");
        end
    endtask

    task automatic test_trap_priority_over_explicit_write;
        begin
            reset_dut();

            apply_access(
                CSR_ADDR_MSCRATCH,
                CSR_WRITE,
                32'ha5a5_5a5a,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "prepare mscratch before priority test"
            );

            @(negedge clk);
            csr_access_valid       = 1'b1;
            csr_address            = CSR_ADDR_MSCRATCH;
            csr_operation          = CSR_WRITE;
            csr_source             = 32'h1234_5678;
            csr_read_enable        = 1'b1;
            csr_write_enable       = 1'b1;
            mem_valid              = 1'b1;
            mem_pc                 = 32'h0000_0207;
            mem_instruction        = 32'hffff_ffff;
            mem_response_wait      = 1'b0;
            final_mem_exception.valid = 1'b1;
            final_mem_exception.cause =
                EXCEPTION_CAUSE_ILLEGAL_INSTRUCTION;
            final_mem_exception.value = 32'hffff_ffff;
            #1ns;

            check_condition(!csr_access_illegal,
                            "legal CSR access remains legal beside trap");
            check_condition(csr_read_data == 32'ha5a5_5a5a,
                            "CSR read still observes pre-trap old value");
            check_condition(trap_take,
                            "trap is selected beside explicit CSR write");

            @(posedge clk);
            #1ns;
            @(negedge clk);
            set_idle_inputs();

            check_csr_value(CSR_ADDR_MSCRATCH, 32'ha5a5_5a5a,
                            "trap suppresses explicit CSR write");
            check_csr_value(CSR_ADDR_MEPC, 32'h0000_0204,
                            "priority trap records aligned mepc");
            check_csr_value(
                CSR_ADDR_MCAUSE,
                EXCEPTION_CAUSE_ILLEGAL_INSTRUCTION,
                "priority trap records illegal cause"
            );
            check_csr_value(CSR_ADDR_MTVAL, 32'hffff_ffff,
                            "priority trap records instruction value");
            check_csr_value(CSR_ADDR_MSTATUS, 32'h0000_1800,
                            "trap stacks reset MIE into MPIE");
        end
    endtask

    task automatic test_mie_mip_csrs;
        begin
            reset_dut();

            check_csr_value(CSR_ADDR_MIE, 32'b0, "mie resets to zero");
            check_csr_value(CSR_ADDR_MIP, 32'b0, "mip reads low IRQ levels");

            apply_access(
                CSR_ADDR_MIE,
                CSR_WRITE,
                32'hffff_ffff,
                1'b1,
                1'b1,
                32'b0,
                1'b0,
                "mie all-bit write returns old zero"
            );
            check_csr_value(
                CSR_ADDR_MIE,
                32'h0000_0888,
                "mie retains only MEIE MTIE and MSIE"
            );

            apply_access(
                CSR_ADDR_MIE,
                CSR_CLEAR,
                32'h0000_0080,
                1'b1,
                1'b1,
                32'h0000_0888,
                1'b0,
                "mie CLEAR returns old value"
            );
            check_csr_value(
                CSR_ADDR_MIE,
                32'h0000_0808,
                "mie CLEAR modifies implemented bits only"
            );

            @(negedge clk);
            irq_software = 1'b1;
            irq_timer    = 1'b1;
            irq_external = 1'b1;
            apply_access(
                CSR_ADDR_MIP,
                CSR_WRITE,
                32'hffff_ffff,
                1'b1,
                1'b1,
                32'h0000_0888,
                1'b0,
                "mip write is a legal WARL no-op"
            );
            check_csr_value(
                CSR_ADDR_MIP,
                32'h0000_0888,
                "mip continues reflecting asserted IRQ levels"
            );

            @(negedge clk);
            irq_software = 1'b1;
            irq_timer    = 1'b0;
            irq_external = 1'b0;
            check_csr_value(
                CSR_ADDR_MIP,
                32'h0000_0008,
                "mip maps software IRQ to MSIP"
            );

            @(negedge clk);
            irq_software = 1'b0;
            irq_timer    = 1'b1;
            irq_external = 1'b0;
            check_csr_value(
                CSR_ADDR_MIP,
                32'h0000_0080,
                "mip maps timer IRQ to MTIP"
            );

            @(negedge clk);
            irq_software = 1'b0;
            irq_timer    = 1'b0;
            irq_external = 1'b1;
            check_csr_value(
                CSR_ADDR_MIP,
                32'h0000_0800,
                "mip maps external IRQ to MEIP"
            );

            @(negedge clk);
            set_idle_inputs();
        end
    endtask

    task automatic run_post_interrupt_case(
        input logic [31:0] mie_value,
        input logic        global_enable,
        input logic        software_pending,
        input logic        timer_pending,
        input logic        external_pending,
        input logic        expected_take,
        input logic [31:0] expected_cause,
        input string       case_name
    );
        begin
            reset_dut();
            apply_access(
                CSR_ADDR_MIE,
                CSR_WRITE,
                mie_value,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                $sformatf("%s: configure mie", case_name)
            );
            apply_access(
                CSR_ADDR_MSTATUS,
                CSR_WRITE,
                global_enable ? 32'h0000_0008 : 32'b0,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                $sformatf("%s: configure mstatus.MIE", case_name)
            );

            @(negedge clk);
            set_idle_inputs();
            mem_valid                = 1'b1;
            mem_pc                   = 32'h0000_0200;
            mem_instruction          = 32'h0000_0013;
            mem_commit_candidate     = 1'b1;
            commit_valid             = 1'b1;
            boundary_resume_pc       = 32'h0000_0204;
            irq_software             = software_pending;
            irq_timer                = timer_pending;
            irq_external             = external_pending;
            #1ns;

            check_condition(
                post_commit_interrupt_take === expected_take,
                $sformatf("%s: post-commit take decision", case_name)
            );
            check_condition(
                (interrupt_take === expected_take) &&
                !empty_interrupt_take,
                $sformatf("%s: interrupt arbitration", case_name)
            );
            check_condition(
                !trap_take && !trap_valid,
                $sformatf("%s: interrupt is not an immediate trap event", case_name)
            );

            if (expected_take) begin
                check_condition(
                    interrupt_redirect.valid &&
                    (interrupt_redirect.target == 32'h0000_0100),
                    $sformatf("%s: interrupt redirect", case_name)
                );
            end else begin
                check_condition(
                    !interrupt_redirect.valid &&
                    (interrupt_redirect.target == 32'b0),
                    $sformatf("%s: masked interrupt has no redirect", case_name)
                );
            end

            @(posedge clk);
            #1ns;
            if (expected_take) begin
                check_condition(
                    trap_valid &&
                    (trap_pc == 32'h0000_0204) &&
                    (trap_cause == expected_cause) &&
                    (trap_value == 32'b0),
                    $sformatf("%s: delayed trap event payload", case_name)
                );
                check_condition(
                    (dut.mepc_q == 32'h0000_0204) &&
                    (dut.mcause_q == expected_cause) &&
                    (dut.mtval_q == 32'b0) &&
                    !dut.mstatus_mie_q &&
                    dut.mstatus_mpie_q,
                    $sformatf("%s: interrupt entry CSR state", case_name)
                );
            end else begin
                check_condition(
                    !trap_valid,
                    $sformatf("%s: masked interrupt has no event", case_name)
                );
            end

            @(negedge clk);
            set_idle_inputs();
            @(posedge clk);
            #1ns;
            check_condition(
                !trap_valid && !interrupt_take,
                $sformatf("%s: event is single-cycle", case_name)
            );
        end
    endtask

    task automatic test_interrupt_masking_and_causes;
        begin
            run_post_interrupt_case(
                32'b0, 1'b0, 1'b1, 1'b0, 1'b0,
                1'b0, 32'b0,
                "software pending global/local disabled"
            );
            run_post_interrupt_case(
                32'h0000_0008, 1'b0, 1'b1, 1'b0, 1'b0,
                1'b0, 32'b0,
                "software pending global disabled"
            );
            run_post_interrupt_case(
                32'b0, 1'b1, 1'b1, 1'b0, 1'b0,
                1'b0, 32'b0,
                "software pending local disabled"
            );
            run_post_interrupt_case(
                32'h0000_0008, 1'b1, 1'b0, 1'b0, 1'b0,
                1'b0, 32'b0,
                "software enabled but not pending"
            );
            run_post_interrupt_case(
                32'h0000_0008, 1'b1, 1'b1, 1'b0, 1'b0,
                1'b1, INTERRUPT_CAUSE_MACHINE_SOFTWARE,
                "Machine software interrupt"
            );
            run_post_interrupt_case(
                32'h0000_0080, 1'b1, 1'b0, 1'b1, 1'b0,
                1'b1, INTERRUPT_CAUSE_MACHINE_TIMER,
                "Machine timer interrupt"
            );
            run_post_interrupt_case(
                32'h0000_0800, 1'b1, 1'b0, 1'b0, 1'b1,
                1'b1, INTERRUPT_CAUSE_MACHINE_EXTERNAL,
                "Machine external interrupt"
            );
        end
    endtask

    task automatic test_interrupt_priority;
        begin
            run_post_interrupt_case(
                32'h0000_0888, 1'b1, 1'b1, 1'b1, 1'b1,
                1'b1, INTERRUPT_CAUSE_MACHINE_EXTERNAL,
                "MEI wins over MSI and MTI"
            );
            run_post_interrupt_case(
                32'h0000_0088, 1'b1, 1'b1, 1'b1, 1'b1,
                1'b1, INTERRUPT_CAUSE_MACHINE_SOFTWARE,
                "MSI wins when MEI is locally masked"
            );
            run_post_interrupt_case(
                32'h0000_0080, 1'b1, 1'b1, 1'b1, 1'b1,
                1'b1, INTERRUPT_CAUSE_MACHINE_TIMER,
                "MTI wins when higher priorities are masked"
            );
        end
    endtask

    task automatic test_interrupt_entry_and_event;
        logic [63:0] instret_before;
        begin
            reset_dut();
            apply_access(
                CSR_ADDR_MTVEC,
                CSR_WRITE,
                32'h0000_0283,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "interrupt entry: configure Direct mtvec"
            );
            apply_access(
                CSR_ADDR_MIE,
                CSR_WRITE,
                32'h0000_0800,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "interrupt entry: enable MEIE"
            );
            apply_access(
                CSR_ADDR_MSTATUS,
                CSR_WRITE,
                32'h0000_0088,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "interrupt entry: enable global MIE"
            );
            apply_access(
                CSR_ADDR_MCAUSE,
                CSR_WRITE,
                32'hdead_beef,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "interrupt entry: prepare mcause sentinel"
            );
            apply_access(
                CSR_ADDR_MTVAL,
                CSR_WRITE,
                32'hcafe_babe,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "interrupt entry: prepare mtval sentinel"
            );
            instret_before = dut.minstret_q;

            @(negedge clk);
            set_idle_inputs();
            mem_valid            = 1'b1;
            mem_pc               = 32'h0000_0440;
            mem_instruction      = 32'h0000_0013;
            mem_commit_candidate = 1'b1;
            commit_valid         = 1'b1;
            boundary_resume_pc   = 32'h0000_0444;
            irq_external         = 1'b1;
            #1ns;

            check_condition(
                post_commit_interrupt_take &&
                interrupt_take &&
                !empty_interrupt_take,
                "post-commit interrupt is selected"
            );
            check_condition(
                interrupt_redirect.valid &&
                (interrupt_redirect.target == 32'h0000_0280),
                "post-commit interrupt redirects to aligned mtvec"
            );
            check_condition(
                !trap_valid,
                "interrupt observation is not emitted in take cycle"
            );

            @(posedge clk);
            #1ns;
            check_condition(
                trap_valid &&
                (trap_pc == 32'h0000_0444) &&
                (trap_cause == INTERRUPT_CAUSE_MACHINE_EXTERNAL) &&
                (trap_value == 32'b0),
                "interrupt event is emitted one cycle later"
            );
            check_condition(
                !dut.mstatus_mie_q &&
                dut.mstatus_mpie_q &&
                (dut.mepc_q == 32'h0000_0444) &&
                (dut.mcause_q == INTERRUPT_CAUSE_MACHINE_EXTERNAL) &&
                (dut.mtval_q == 32'b0),
                "interrupt entry records mstatus mepc mcause and mtval"
            );
            check_condition(
                dut.minstret_q == (instret_before + 64'd1),
                "post-commit boundary increments minstret once"
            );

            @(negedge clk);
            mem_valid            = 1'b0;
            mem_commit_candidate = 1'b0;
            commit_valid         = 1'b0;
            boundary_resume_pc   = 32'b0;
            #1ns;
            check_condition(
                !interrupt_take,
                "asserted IRQ does not retrigger while mstatus.MIE is clear"
            );

            @(posedge clk);
            #1ns;
            check_condition(
                !trap_valid &&
                !dut.interrupt_event_pending_q &&
                (dut.minstret_q == (instret_before + 64'd1)),
                "interrupt event self-clears without duplicate retirement"
            );

            @(negedge clk);
            set_idle_inputs();
        end
    endtask

    task automatic test_empty_interrupt_boundary;
        logic [63:0] instret_before;
        begin
            reset_dut();
            apply_access(
                CSR_ADDR_MIE,
                CSR_WRITE,
                32'h0000_0008,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "empty interrupt: enable MSIE"
            );
            apply_access(
                CSR_ADDR_MSTATUS,
                CSR_WRITE,
                32'h0000_0008,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "empty interrupt: enable global MIE"
            );
            instret_before = dut.minstret_q;

            @(negedge clk);
            set_idle_inputs();
            irq_software             = 1'b1;
            empty_interrupt_boundary = 1'b1;
            boundary_resume_pc       = 32'h0000_0600;
            #1ns;

            check_condition(
                empty_interrupt_take &&
                interrupt_take &&
                !post_commit_interrupt_take,
                "empty-pipeline interrupt uses the empty boundary"
            );
            check_condition(
                interrupt_redirect.valid &&
                (interrupt_redirect.target == 32'h0000_0100),
                "empty-pipeline interrupt redirects to mtvec"
            );

            @(posedge clk);
            #1ns;
            check_condition(
                trap_valid &&
                (trap_pc == 32'h0000_0600) &&
                (trap_cause == INTERRUPT_CAUSE_MACHINE_SOFTWARE) &&
                (trap_value == 32'b0),
                "empty-pipeline interrupt emits delayed event"
            );
            check_condition(
                (dut.mepc_q == 32'h0000_0600) &&
                (dut.mcause_q == INTERRUPT_CAUSE_MACHINE_SOFTWARE) &&
                (dut.minstret_q == instret_before),
                "empty-pipeline entry saves resume PC without retirement"
            );

            @(negedge clk);
            empty_interrupt_boundary = 1'b0;
            boundary_resume_pc       = 32'b0;
            @(posedge clk);
            #1ns;
            check_condition(
                !trap_valid &&
                !interrupt_take &&
                (dut.minstret_q == instret_before),
                "empty interrupt event self-clears and does not repeat"
            );

            @(negedge clk);
            set_idle_inputs();
        end
    endtask

    task automatic test_post_commit_preview;
        begin
            reset_dut();
            apply_access(
                CSR_ADDR_MSTATUS,
                CSR_WRITE,
                32'h0000_0008,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "mie preview: enable global MIE"
            );

            @(negedge clk);
            set_idle_inputs();
            csr_access_valid       = 1'b1;
            csr_address            = CSR_ADDR_MIE;
            csr_operation          = CSR_WRITE;
            csr_source             = 32'h0000_0800;
            csr_write_enable       = 1'b1;
            mem_commit_candidate   = 1'b1;
            commit_valid           = 1'b0;
            boundary_resume_pc     = 32'h0000_0704;
            irq_external           = 1'b1;
            #1ns;
            check_condition(
                post_commit_interrupt_take,
                "mie preview enables interrupt without commit_valid feedback"
            );
            commit_valid = 1'b1;
            #1ns;
            check_condition(
                post_commit_interrupt_take,
                "mie preview decision is stable when commit_valid follows"
            );
            @(posedge clk);
            #1ns;
            check_condition(
                trap_valid &&
                dut.mie_meie_q &&
                !dut.mstatus_mie_q &&
                dut.mstatus_mpie_q,
                "mie write persists before interrupt entry"
            );

            reset_dut();
            apply_access(
                CSR_ADDR_MIE,
                CSR_WRITE,
                32'h0000_0800,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "mstatus preview: enable MEIE"
            );

            @(negedge clk);
            set_idle_inputs();
            csr_access_valid       = 1'b1;
            csr_address            = CSR_ADDR_MSTATUS;
            csr_operation          = CSR_WRITE;
            csr_source             = 32'h0000_0008;
            csr_write_enable       = 1'b1;
            mem_commit_candidate   = 1'b1;
            commit_valid           = 1'b0;
            boundary_resume_pc     = 32'h0000_0714;
            irq_external           = 1'b1;
            #1ns;
            check_condition(
                post_commit_interrupt_take,
                "mstatus post-write MIE immediately enables interrupt"
            );
            commit_valid = 1'b1;
            @(posedge clk);
            #1ns;
            check_condition(
                trap_valid &&
                !dut.mstatus_mie_q &&
                dut.mstatus_mpie_q,
                "interrupt entry stacks post-write mstatus.MIE"
            );

            reset_dut();
            apply_access(
                CSR_ADDR_MIE,
                CSR_WRITE,
                32'h0000_0800,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "mtvec preview: enable MEIE"
            );
            apply_access(
                CSR_ADDR_MSTATUS,
                CSR_WRITE,
                32'h0000_0008,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "mtvec preview: enable global MIE"
            );

            @(negedge clk);
            set_idle_inputs();
            csr_access_valid       = 1'b1;
            csr_address            = CSR_ADDR_MTVEC;
            csr_operation          = CSR_WRITE;
            csr_source             = 32'h0000_0347;
            csr_write_enable       = 1'b1;
            mem_commit_candidate   = 1'b1;
            commit_valid           = 1'b0;
            boundary_resume_pc     = 32'h0000_0724;
            irq_external           = 1'b1;
            #1ns;
            check_condition(
                post_commit_interrupt_take &&
                interrupt_redirect.valid &&
                (interrupt_redirect.target == 32'h0000_0344),
                "mtvec post-write value drives immediate redirect"
            );
            commit_valid = 1'b1;
            @(posedge clk);
            #1ns;
            check_condition(
                trap_valid &&
                (dut.mtvec_q == 32'h0000_0344),
                "mtvec post-write value persists through interrupt entry"
            );

            reset_dut();
            apply_access(
                CSR_ADDR_MIE,
                CSR_WRITE,
                32'h0000_0800,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "side-effect preview: enable MEIE"
            );
            apply_access(
                CSR_ADDR_MSTATUS,
                CSR_WRITE,
                32'h0000_0008,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "side-effect preview: enable global MIE"
            );

            @(negedge clk);
            set_idle_inputs();
            csr_access_valid       = 1'b1;
            csr_address            = CSR_ADDR_MSCRATCH;
            csr_operation          = CSR_WRITE;
            csr_source             = 32'ha5a5_5a5a;
            csr_write_enable       = 1'b1;
            mem_commit_candidate   = 1'b1;
            commit_valid           = 1'b1;
            boundary_resume_pc     = 32'h0000_0734;
            irq_external           = 1'b1;
            #1ns;
            check_condition(
                post_commit_interrupt_take,
                "ordinary CSR write can form post-commit interrupt"
            );
            @(posedge clk);
            #1ns;
            check_condition(
                trap_valid &&
                (dut.mscratch_q == 32'ha5a5_5a5a),
                "current CSR side effect survives interrupt entry"
            );

            @(negedge clk);
            set_idle_inputs();
        end
    endtask

    task automatic test_mret_immediate_interrupt;
        begin
            reset_dut();
            apply_access(
                CSR_ADDR_MTVEC,
                CSR_WRITE,
                32'h0000_0380,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "MRET interrupt: configure mtvec"
            );
            apply_access(
                CSR_ADDR_MIE,
                CSR_WRITE,
                32'h0000_0800,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "MRET interrupt: enable MEIE"
            );
            apply_access(
                CSR_ADDR_MEPC,
                CSR_WRITE,
                32'h0000_0557,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "MRET interrupt: prepare return target"
            );
            apply_access(
                CSR_ADDR_MSTATUS,
                CSR_WRITE,
                32'h0000_0080,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "MRET interrupt: prepare MPIE with MIE clear"
            );

            @(negedge clk);
            set_idle_inputs();
            mret_commit          = 1'b1;
            mem_commit_candidate = 1'b1;
            commit_valid         = 1'b0;
            boundary_resume_pc   = 32'h0000_0554;
            irq_external         = 1'b1;
            #1ns;

            check_condition(
                mret_target == 32'h0000_0554,
                "MRET immediate interrupt sees aligned return target"
            );
            check_condition(
                post_commit_interrupt_take &&
                interrupt_redirect.valid &&
                (interrupt_redirect.target == 32'h0000_0380),
                "MRET restored MIE immediately re-evaluates pending IRQ"
            );

            commit_valid = 1'b1;
            @(posedge clk);
            #1ns;
            check_condition(
                trap_valid &&
                (trap_pc == 32'h0000_0554) &&
                (trap_cause == INTERRUPT_CAUSE_MACHINE_EXTERNAL),
                "MRET immediate interrupt reports return target"
            );
            check_condition(
                !dut.mstatus_mie_q &&
                dut.mstatus_mpie_q &&
                (dut.mepc_q == 32'h0000_0554),
                "MRET semantics are applied before interrupt entry"
            );

            @(negedge clk);
            set_idle_inputs();
        end
    endtask

    task automatic test_interrupt_exception_priority_and_reset;
        begin
            reset_dut();
            apply_access(
                CSR_ADDR_MIE,
                CSR_WRITE,
                32'h0000_0888,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "priority: enable all local interrupts"
            );
            apply_access(
                CSR_ADDR_MSTATUS,
                CSR_WRITE,
                32'h0000_0008,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "priority: enable global interrupt"
            );

            @(negedge clk);
            set_idle_inputs();
            mem_valid                  = 1'b1;
            mem_pc                     = 32'h0000_0803;
            mem_instruction            = 32'hffff_ffff;
            final_mem_exception.valid  = 1'b1;
            final_mem_exception.cause  =
                EXCEPTION_CAUSE_ILLEGAL_INSTRUCTION;
            final_mem_exception.value  = 32'hffff_ffff;
            mem_commit_candidate       = 1'b1;
            boundary_resume_pc         = 32'h0000_0804;
            empty_interrupt_boundary   = 1'b1;
            irq_software               = 1'b1;
            irq_timer                  = 1'b1;
            irq_external               = 1'b1;
            #1ns;

            check_condition(
                trap_take &&
                trap_valid &&
                (trap_cause == EXCEPTION_CAUSE_ILLEGAL_INSTRUCTION),
                "synchronous exception is selected over pending interrupt"
            );
            check_condition(
                !post_commit_interrupt_take &&
                !empty_interrupt_take &&
                !interrupt_take &&
                !interrupt_redirect.valid,
                "synchronous exception suppresses every interrupt action"
            );

            @(posedge clk);
            #1ns;
            @(negedge clk);
            set_mem_idle();
            mem_commit_candidate     = 1'b0;
            empty_interrupt_boundary = 1'b0;
            #1ns;
            check_condition(
                !trap_valid && !interrupt_take,
                "synchronous trap does not enqueue an interrupt event"
            );
            check_condition(
                (dut.mcause_q == EXCEPTION_CAUSE_ILLEGAL_INSTRUCTION) &&
                (dut.mepc_q == 32'h0000_0800),
                "synchronous trap state wins over interrupt state"
            );

            reset_dut();
            apply_access(
                CSR_ADDR_MIE,
                CSR_WRITE,
                32'h0000_0800,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "pending reset: enable MEIE"
            );
            apply_access(
                CSR_ADDR_MSTATUS,
                CSR_WRITE,
                32'h0000_0008,
                1'b0,
                1'b1,
                32'b0,
                1'b0,
                "pending reset: enable global MIE"
            );

            @(negedge clk);
            set_idle_inputs();
            mem_commit_candidate = 1'b1;
            commit_valid         = 1'b1;
            boundary_resume_pc   = 32'h0000_0904;
            irq_external         = 1'b1;
            #1ns;
            check_condition(
                interrupt_take,
                "pending reset: create interrupt take"
            );
            @(posedge clk);
            #1ns;
            check_condition(
                trap_valid && dut.interrupt_event_pending_q,
                "pending reset: delayed event became visible"
            );

            @(negedge clk);
            rst = 1'b1;
            #1ns;
            check_condition(
                !trap_valid &&
                !interrupt_take &&
                !interrupt_redirect.valid,
                "reset immediately suppresses pending interrupt outputs"
            );
            @(posedge clk);
            #1ns;
            check_condition(
                !dut.interrupt_event_pending_q,
                "reset clears interrupt event pending state"
            );

            @(negedge clk);
            set_idle_inputs();
            rst = 1'b0;
            @(posedge clk);
            #1ns;
            check_condition(
                !trap_valid && !interrupt_take,
                "reset release has no late interrupt event"
            );
        end
    endtask

    task automatic apply_access (
        input logic [11:0]      address,
        input csr_operation_e  operation,
        input logic [31:0]      source,
        input logic             read_enable,
        input logic             write_enable,
        input logic [31:0]      expected_read_data,
        input logic             expected_illegal,
        input string            case_name
    );
        begin
            @(negedge clk);
            csr_access_valid = 1'b1;
            csr_address      = address;
            csr_operation    = operation;
            csr_source       = source;
            csr_read_enable  = read_enable;
            csr_write_enable = write_enable;
            mem_commit_candidate = 1'b1;
            commit_valid          = 1'b1;
            #1ns;

            if (
                (csr_read_data !== expected_read_data) ||
                (csr_access_illegal !== expected_illegal)
            ) begin
                error_count++;
                $error(
                    "[FAIL] %s: read=%h expected=%h illegal=%b expected=%b",
                    case_name,
                    csr_read_data,
                    expected_read_data,
                    csr_access_illegal,
                    expected_illegal
                );
            end else begin
                $display("[PASS] %s", case_name);
            end

            @(posedge clk);
            #1ns;
            @(negedge clk);
            set_csr_idle();
            mem_commit_candidate = 1'b0;
            commit_valid          = 1'b0;
        end
    endtask

    task automatic apply_counter_access (
        input logic [11:0]     address,
        input csr_operation_e operation,
        input logic [31:0]     source,
        input logic            read_enable,
        input logic            write_enable,
        input logic [31:0]     expected_read_data,
        input string           case_name
    );
        begin
            set_idle_inputs();
            csr_access_valid = 1'b1;
            csr_address      = address;
            csr_operation    = operation;
            csr_source       = source;
            csr_read_enable  = read_enable;
            csr_write_enable = write_enable;
            mem_commit_candidate = 1'b1;
            commit_valid          = 1'b1;
            #1ns;

            check_condition(
                !csr_access_illegal &&
                (csr_read_data == expected_read_data),
                case_name
            );

            @(posedge clk);
            #1ns;
            @(negedge clk);
            set_idle_inputs();
        end
    endtask

    task automatic pulse_commit (
        input logic commit_value
    );
        begin
            set_idle_inputs();
            mem_commit_candidate = commit_value;
            commit_valid          = commit_value;
            @(posedge clk);
            #1ns;
            @(negedge clk);
            set_idle_inputs();
        end
    endtask

    task automatic check_csr_value (
        input logic [11:0] address,
        input logic [31:0] expected_value,
        input string       case_name
    );
        begin
            apply_access(
                address,
                CSR_SET,
                32'b0,
                1'b1,
                1'b0,
                expected_value,
                1'b0,
                case_name
            );
        end
    endtask

    task automatic drive_trap_inputs (
        input logic [31:0] pc,
        input logic [31:0] instruction,
        input logic [31:0] cause,
        input logic [31:0] value,
        input logic        response_wait
    );
        begin
            @(negedge clk);
            mem_valid                = 1'b1;
            mem_pc                   = pc;
            mem_instruction          = instruction;
            mem_response_wait        = response_wait;
            final_mem_exception.valid = 1'b1;
            final_mem_exception.cause = cause;
            final_mem_exception.value = value;
        end
    endtask

    task automatic check_condition (
        input logic  condition,
        input string case_name
    );
        begin
            if (condition !== 1'b1) begin
                error_count++;
                $error("[FAIL] %s", case_name);
            end else begin
                $display("[PASS] %s", case_name);
            end
        end
    endtask

    task automatic set_csr_idle;
        begin
            csr_access_valid = 1'b0;
            csr_address      = 12'b0;
            csr_operation    = CSR_WRITE;
            csr_source       = 32'b0;
            csr_read_enable  = 1'b0;
            csr_write_enable = 1'b0;
        end
    endtask

    task automatic set_mem_idle;
        begin
            mem_valid                 = 1'b0;
            mem_pc                    = 32'b0;
            mem_instruction           = 32'b0;
            mem_response_wait         = 1'b0;
            final_mem_exception       = '0;
        end
    endtask

    task automatic set_idle_inputs;
        begin
            set_csr_idle();
            set_mem_idle();
            mret_commit             = 1'b0;
            mem_commit_candidate    = 1'b0;
            commit_valid            = 1'b0;
            irq_software            = 1'b0;
            irq_timer               = 1'b0;
            irq_external            = 1'b0;
            boundary_resume_pc      = 32'b0;
            empty_interrupt_boundary = 1'b0;
        end
    endtask

endmodule
