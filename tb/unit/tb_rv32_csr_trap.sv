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
    logic [31:0]    csr_read_data;
    logic           csr_access_illegal;
    logic           trap_take;
    redirect_t      trap_redirect;
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
        .csr_read_data       (csr_read_data),
        .csr_access_illegal  (csr_access_illegal),
        .trap_take           (trap_take),
        .trap_redirect       (trap_redirect),
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
        test_mscratch_rmw();
        test_fixed_and_read_only_csrs();
        test_unknown_and_invalid_accesses();
        test_warl_fields();
        test_trap_wait_and_commit();
        test_trap_priority_over_explicit_write();

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
            #1ns;

            check_condition(!trap_take,
                            "reset suppresses trap_take");
            check_condition(!trap_redirect.valid,
                            "reset suppresses trap redirect");
            check_condition(!trap_valid,
                            "reset suppresses trap trace");

            repeat (2) @(posedge clk);

            @(negedge clk);
            set_idle_inputs();
            rst = 1'b0;
            #1ns;
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
            check_csr_value(CSR_ADDR_MISA, 32'h4000_0100,
                            "misa reports RV32I");
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
                32'h4000_0100,
                1'b0,
                "misa fixed WARL write is legal"
            );
            check_csr_value(CSR_ADDR_MISA, 32'h4000_0100,
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
        end
    endtask

endmodule
