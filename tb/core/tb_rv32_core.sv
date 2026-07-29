`timescale 1ns/1ps

module tb_rv32_core;
    import rv32_pkg::*;
    import rv32_tb_pkg::*;

    localparam logic [31:0] RESET_VECTOR = 32'h0000_0000;
    localparam logic [31:0] TRAP_VECTOR  = 32'h0000_0300;
    localparam int unsigned IMEM_WORD_COUNT = 256;
    localparam int unsigned DMEM_BYTE_COUNT = 1024;
    localparam int unsigned MAX_EXPECTED = 128;
    int unsigned SCENARIO_TIMEOUT_CYCLES;

    logic clk;
    logic rst;
    logic irq_software;
    logic irq_timer;
    logic irq_external;

    logic imem_request_enable;
    logic imem_response_enable;
    logic dmem_request_enable;
    logic dmem_response_enable;
    logic imem_model_request_enable;
    logic imem_model_response_enable;
    logic dmem_model_request_enable;
    logic dmem_model_response_enable;

    logic        d5_only_mode;
    logic        d5_random_active;
    logic        d5_drain_active;
    logic [31:0] d5_seed;
    logic [31:0] d5_stall_percent;
    logic [31:0] d5_max_stall_cycles;
    logic        d5_imem_request_allow;
    logic        d5_imem_response_allow;
    logic        d5_dmem_request_allow;
    logic        d5_dmem_response_allow;
    logic [31:0] d5_random_state;
    logic [31:0] d5_imem_request_low_cycles;
    logic [31:0] d5_imem_response_low_cycles;
    logic [31:0] d5_dmem_request_low_cycles;
    logic [31:0] d5_dmem_response_low_cycles;
    logic [31:0] d5_imem_request_forced_grants;
    logic [31:0] d5_imem_response_forced_grants;
    logic [31:0] d5_dmem_request_forced_grants;
    logic [31:0] d5_dmem_response_forced_grants;
    logic [31:0] d5_imem_request_max_low_streak;
    logic [31:0] d5_imem_response_max_low_streak;
    logic [31:0] d5_dmem_request_max_low_streak;
    logic [31:0] d5_dmem_response_max_low_streak;
    logic [15:0] d5_coverage_bitmap;

    int unsigned d5_imem_request_stall_cycles;
    int unsigned d5_imem_response_delay_cycles;
    int unsigned d5_dmem_request_stall_cycles;
    int unsigned d5_dmem_response_delay_cycles;
    integer      d5_plusarg_status;

    logic        imem_req_valid;
    logic        imem_req_ready;
    logic [31:0] imem_req_addr;
    logic        imem_rsp_valid;
    logic        imem_rsp_ready;
    logic [31:0] imem_rsp_data;
    logic        imem_rsp_error;

    logic        dmem_req_valid;
    logic        dmem_req_ready;
    logic        dmem_req_write;
    logic [31:0] dmem_req_addr;
    logic [31:0] dmem_req_wdata;
    logic [3:0]  dmem_req_wstrb;
    logic        dmem_rsp_valid;
    logic        dmem_rsp_ready;
    logic [31:0] dmem_rsp_rdata;
    logic        dmem_rsp_error;

    logic        retire_valid;
    logic [31:0] retire_pc;
    logic [31:0] retire_instr;
    logic        retire_rd_we;
    logic [4:0]  retire_rd_addr;
    logic [31:0] retire_rd_data;

    logic        trap_valid;
    logic [31:0] trap_pc;
    logic [31:0] trap_cause;
    logic [31:0] trap_value;

    logic        cp_req_valid;
    logic        cp_req_ready;
    logic [31:0] cp_req_pc;
    logic [31:0] cp_req_instr;
    logic [31:0] cp_req_rs1_data;
    logic [31:0] cp_req_rs2_data;
    logic        cp_rsp_valid;
    logic        cp_rsp_ready;
    logic [31:0] cp_rsp_data;
    logic        cp_rsp_error;

    // Parallel arrays avoid Icarus failures on dynamically indexed structs.
    logic [31:0] expected_retire_pc [0:MAX_EXPECTED-1];
    logic [31:0] expected_retire_instruction [0:MAX_EXPECTED-1];
    logic        expected_retire_rd_we [0:MAX_EXPECTED-1];
    logic [4:0]  expected_retire_rd_addr [0:MAX_EXPECTED-1];
    logic [31:0] expected_retire_rd_data [0:MAX_EXPECTED-1];

    logic        expected_dmem_write [0:MAX_EXPECTED-1];
    logic [31:0] expected_dmem_addr [0:MAX_EXPECTED-1];
    logic [31:0] expected_dmem_wdata [0:MAX_EXPECTED-1];
    logic [3:0]  expected_dmem_wstrb [0:MAX_EXPECTED-1];

    logic [31:0] expected_trap_pc [0:MAX_EXPECTED-1];
    logic [31:0] expected_trap_cause [0:MAX_EXPECTED-1];
    logic [31:0] expected_trap_value [0:MAX_EXPECTED-1];

    int unsigned expected_retire_count;
    int unsigned observed_retire_count;
    int unsigned expected_dmem_request_count;
    int unsigned observed_dmem_request_count;
    int unsigned expected_trap_count;
    int unsigned observed_trap_count;
    int unsigned expected_trap_vector_fetch_count;
    int unsigned observed_trap_vector_fetch_count;
    int unsigned expected_mdu_request_count;
    int unsigned observed_mdu_request_count;
    int unsigned expected_mdu_response_count;
    int unsigned observed_mdu_response_count;
    int unsigned expected_interrupt_take_count;
    int unsigned observed_interrupt_take_count;
    int unsigned expected_post_interrupt_take_count;
    int unsigned observed_post_interrupt_take_count;
    int unsigned expected_empty_interrupt_take_count;
    int unsigned observed_empty_interrupt_take_count;

    int unsigned expected_late_result_hazard_count;
    int unsigned expected_redirect_count;
    int unsigned minimum_ex_request_wait_count;
    int unsigned minimum_ex_multicycle_wait_count;
    int unsigned minimum_mem_response_wait_count;
    int unsigned minimum_imem_request_stall_count;

    int unsigned late_result_hazard_count;
    int unsigned redirect_count;
    int unsigned ex_request_wait_count;
    int unsigned ex_multicycle_wait_count;
    int unsigned mem_response_wait_count;
    int unsigned imem_request_stall_count;

    int unsigned scenario_count;
    int unsigned passed_scenario_count;
    int unsigned scenario_cycle_count;
    int unsigned scenario_check_count;
    int unsigned scenario_error_count;
    int unsigned total_check_count;
    int unsigned total_error_count;
    int unsigned total_retire_count;
    int unsigned total_dmem_request_count;
    int unsigned total_trap_count;
    int unsigned total_mdu_request_count;
    int unsigned total_mdu_response_count;
    int unsigned total_interrupt_take_count;


    logic [31:0] program_pc;
    logic        scenario_active;
    string       scenario_name;
    string       dump_file_name;

    logic imem_request_fire;
    logic imem_response_fire;
    logic dmem_request_fire;
    logic dmem_response_fire;

    int unsigned imem_outstanding_count;
    int unsigned dmem_outstanding_count;

    logic        previous_imem_request_stalled;
    logic [31:0] previous_imem_request_addr;
    logic        previous_dmem_request_stalled;
    logic        previous_dmem_request_write;
    logic [31:0] previous_dmem_request_addr;
    logic [31:0] previous_dmem_request_wdata;
    logic [3:0]  previous_dmem_request_wstrb;

    logic        previous_imem_response_stalled;
    logic [31:0] previous_imem_response_data;
    logic        previous_imem_response_error;
    logic        previous_dmem_response_stalled;
    logic [31:0] previous_dmem_response_data;
    logic        previous_dmem_response_error;

    logic         pipeline_history_valid;
    pipe_action_e previous_if_id_action;
    pipe_action_e previous_id_ex_action;
    pipe_action_e previous_ex_mem_action;
    pipe_action_e previous_mem_wb_action;
    if_id_t       previous_if_id_q;
    id_ex_t       previous_id_ex_q;
    ex_mem_t      previous_ex_mem_q;
    mem_wb_t      previous_mem_wb_q;

    logic        previous_interrupt_take;
    logic        previous_post_interrupt_take;
    logic        previous_empty_interrupt_take;
    logic [31:0] previous_interrupt_resume_pc;
    logic [31:0] previous_interrupt_cause;
    logic [31:0] previous_interrupt_boundary_pc;
    logic [31:0] previous_interrupt_boundary_instruction;
    logic [31:0] previous_interrupt_redirect_target;
    logic        previous_interrupt_expected_mpie;
    logic        interrupt_event_retire_seen;

    assign imem_request_fire  = imem_req_valid && imem_req_ready;
    assign imem_response_fire = imem_rsp_valid && imem_rsp_ready;
    assign dmem_request_fire  = dmem_req_valid && dmem_req_ready;
    assign dmem_response_fire = dmem_rsp_valid && dmem_rsp_ready;

    assign imem_model_request_enable =
        imem_request_enable &&
        (!d5_random_active || d5_imem_request_allow);
    assign imem_model_response_enable =
        imem_response_enable &&
        (!d5_random_active || d5_imem_response_allow);
    assign dmem_model_request_enable =
        dmem_request_enable &&
        (!d5_random_active || d5_dmem_request_allow);
    assign dmem_model_response_enable =
        dmem_response_enable &&
        (!d5_random_active || d5_dmem_response_allow);

    rv32_backpressure_driver u_backpressure_driver (
        .clk                              (clk),
        .rst                              (rst),
        .enable                           (d5_random_active),
        .seed                             (d5_seed),
        .stall_percent                    (d5_stall_percent),
        .max_stall_cycles                 (d5_max_stall_cycles),
        .imem_request_allow               (d5_imem_request_allow),
        .imem_response_allow              (d5_imem_response_allow),
        .dmem_request_allow               (d5_dmem_request_allow),
        .dmem_response_allow              (d5_dmem_response_allow),
        .random_state                     (d5_random_state),
        .imem_request_low_cycles          (d5_imem_request_low_cycles),
        .imem_response_low_cycles         (d5_imem_response_low_cycles),
        .dmem_request_low_cycles          (d5_dmem_request_low_cycles),
        .dmem_response_low_cycles         (d5_dmem_response_low_cycles),
        .imem_request_forced_grants       (d5_imem_request_forced_grants),
        .imem_response_forced_grants      (d5_imem_response_forced_grants),
        .dmem_request_forced_grants       (d5_dmem_request_forced_grants),
        .dmem_response_forced_grants      (d5_dmem_response_forced_grants),
        .imem_request_max_low_streak      (d5_imem_request_max_low_streak),
        .imem_response_max_low_streak     (d5_imem_response_max_low_streak),
        .dmem_request_max_low_streak      (d5_dmem_request_max_low_streak),
        .dmem_response_max_low_streak     (d5_dmem_response_max_low_streak)
    );

    rv32_core #(
        .RESET_VECTOR  (RESET_VECTOR),
        .MTVEC_RESET   (TRAP_VECTOR),
        .COPROC_ENABLE (1'b0)
    ) dut (
        .clk             (clk),
        .rst             (rst),
        .irq_software    (irq_software),
        .irq_timer       (irq_timer),
        .irq_external    (irq_external),
        .imem_req_valid  (imem_req_valid),
        .imem_req_ready  (imem_req_ready),
        .imem_req_addr   (imem_req_addr),
        .imem_rsp_valid  (imem_rsp_valid),
        .imem_rsp_ready  (imem_rsp_ready),
        .imem_rsp_data   (imem_rsp_data),
        .imem_rsp_error  (imem_rsp_error),
        .dmem_req_valid  (dmem_req_valid),
        .dmem_req_ready  (dmem_req_ready),
        .dmem_req_write  (dmem_req_write),
        .dmem_req_addr   (dmem_req_addr),
        .dmem_req_wdata  (dmem_req_wdata),
        .dmem_req_wstrb  (dmem_req_wstrb),
        .dmem_rsp_valid  (dmem_rsp_valid),
        .dmem_rsp_ready  (dmem_rsp_ready),
        .dmem_rsp_rdata  (dmem_rsp_rdata),
        .dmem_rsp_error  (dmem_rsp_error),
        .retire_valid    (retire_valid),
        .retire_pc       (retire_pc),
        .retire_instr    (retire_instr),
        .retire_rd_we    (retire_rd_we),
        .retire_rd_addr  (retire_rd_addr),
        .retire_rd_data  (retire_rd_data),
        .trap_valid      (trap_valid),
        .trap_pc         (trap_pc),
        .trap_cause      (trap_cause),
        .trap_value      (trap_value),
        .cp_req_valid    (cp_req_valid),
        .cp_req_ready    (cp_req_ready),
        .cp_req_pc       (cp_req_pc),
        .cp_req_instr    (cp_req_instr),
        .cp_req_rs1_data (cp_req_rs1_data),
        .cp_req_rs2_data (cp_req_rs2_data),
        .cp_rsp_valid    (cp_rsp_valid),
        .cp_rsp_ready    (cp_rsp_ready),
        .cp_rsp_data     (cp_rsp_data),
        .cp_rsp_error    (cp_rsp_error)
    );

    rv32_imem_model #(
        .BASE_ADDR  (RESET_VECTOR),
        .WORD_COUNT (IMEM_WORD_COUNT)
    ) u_imem (
        .clk             (clk),
        .rst             (rst),
        .request_enable  (imem_model_request_enable),
        .response_enable (imem_model_response_enable),
        .imem_req_valid  (imem_req_valid),
        .imem_req_ready  (imem_req_ready),
        .imem_req_addr   (imem_req_addr),
        .imem_rsp_valid  (imem_rsp_valid),
        .imem_rsp_ready  (imem_rsp_ready),
        .imem_rsp_data   (imem_rsp_data),
        .imem_rsp_error  (imem_rsp_error)
    );

    rv32_dmem_model #(
        .BASE_ADDR  (32'h0000_0000),
        .BYTE_COUNT (DMEM_BYTE_COUNT)
    ) u_dmem (
        .clk             (clk),
        .rst             (rst),
        .request_enable  (dmem_model_request_enable),
        .response_enable (dmem_model_response_enable),
        .dmem_req_valid  (dmem_req_valid),
        .dmem_req_ready  (dmem_req_ready),
        .dmem_req_write  (dmem_req_write),
        .dmem_req_addr   (dmem_req_addr),
        .dmem_req_wdata  (dmem_req_wdata),
        .dmem_req_wstrb  (dmem_req_wstrb),
        .dmem_rsp_valid  (dmem_rsp_valid),
        .dmem_rsp_ready  (dmem_rsp_ready),
        .dmem_rsp_rdata  (dmem_rsp_rdata),
        .dmem_rsp_error  (dmem_rsp_error)
    );

    always #5 clk = ~clk;

    initial begin
        if ($value$plusargs("DUMP=%s", dump_file_name)) begin
            $dumpfile(dump_file_name);
            $dumpvars(0, tb_rv32_core);
        end
    end

    task automatic check_condition(
        input logic  condition,
        input string message
    );
        begin
            scenario_check_count++;
            total_check_count++;

            if (condition !== 1'b1) begin
                scenario_error_count++;
                total_error_count++;
                $error(
                    "[%s][cycle %0d] %s",
                    scenario_name,
                    scenario_cycle_count,
                    message
                );
            end
        end
    endtask

    function automatic logic [31:0] instruction_op_imm(
        input logic [2:0]  funct3,
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [31:0] immediate
    );
        instruction_op_imm = encoder_i(
            OPCODE_OP_IMM,
            funct3,
            rd,
            rs1,
            immediate
        );
    endfunction

    function automatic logic [31:0] instruction_shift_imm(
        input logic [2:0] funct3,
        input logic [6:0] funct7,
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input logic [4:0] shift_amount
    );
        logic [31:0] immediate;
        begin
            immediate = {
                20'b0,
                funct7,
                shift_amount
            };

            instruction_shift_imm = encoder_i(
                OPCODE_OP_IMM,
                funct3,
                rd,
                rs1,
                immediate
            );
        end
    endfunction

    function automatic logic [31:0] instruction_m(
        input logic [2:0] operation,
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input logic [4:0] rs2
    );
        instruction_m = encoder_r(
            operation,
            FUNCT7_MULDIV,
            rd,
            rs1,
            rs2
        );
    endfunction

    function automatic logic [31:0] sign_extend_immediate_12(
        input logic [31:0] value
    );
        sign_extend_immediate_12 = {
            {20{value[11]}},
            value[11:0]
        };
    endfunction

    function automatic logic [31:0] instruction_load(
        input logic [2:0]  funct3,
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [31:0] immediate
    );
        instruction_load = encoder_i(
            OPCODE_LOAD,
            funct3,
            rd,
            rs1,
            immediate
        );
    endfunction

    function automatic logic [31:0] instruction_jalr(
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [31:0] immediate
    );
        instruction_jalr = encoder_i(
            OPCODE_JALR,
            FUNCT3_JALR,
            rd,
            rs1,
            immediate
        );
    endfunction

    function automatic logic [31:0] instruction_csr(
        input logic [11:0] csr_address,
        input logic [4:0]  source_field,
        input logic [2:0]  funct3,
        input logic [4:0]  rd_addr
    );
        instruction_csr = {
            csr_address,
            source_field,
            funct3,
            rd_addr,
            OPCODE_SYSTEM
        };
    endfunction

    task automatic expect_retirement(
        input logic [31:0] pc,
        input logic [31:0] instruction,
        input logic        rd_we,
        input logic [4:0]  rd_addr,
        input logic [31:0] rd_data
    );
        begin
            if (expected_retire_count >= MAX_EXPECTED) begin
                $fatal(1, "retirement expectation capacity exceeded");
            end

            expected_retire_pc[expected_retire_count] = pc;
            expected_retire_instruction[expected_retire_count] =
                instruction;
            expected_retire_rd_we[expected_retire_count] = rd_we;
            expected_retire_rd_addr[expected_retire_count] = rd_addr;
            expected_retire_rd_data[expected_retire_count] = rd_data;
            expected_retire_count++;
        end
    endtask

    task automatic expect_dmem_request(
        input logic        write,
        input logic [31:0] addr,
        input logic [31:0] wdata,
        input logic [3:0]  wstrb
    );
        begin
            if (expected_dmem_request_count >= MAX_EXPECTED) begin
                $fatal(1, "DMem request expectation capacity exceeded");
            end

            expected_dmem_write[expected_dmem_request_count] = write;
            expected_dmem_addr[expected_dmem_request_count] = addr;
            expected_dmem_wdata[expected_dmem_request_count] = wdata;
            expected_dmem_wstrb[expected_dmem_request_count] = wstrb;
            expected_dmem_request_count++;
        end
    endtask

    task automatic expect_trap(
        input logic [31:0] pc,
        input logic [31:0] cause,
        input logic [31:0] value
    );
        begin
            if (expected_trap_count >= MAX_EXPECTED) begin
                $fatal(1, "trap expectation capacity exceeded");
            end

            expected_trap_pc[expected_trap_count]    = pc;
            expected_trap_cause[expected_trap_count] = cause;
            expected_trap_value[expected_trap_count] = value;
            expected_trap_count++;
        end
    endtask

    task automatic emit_writeback_instruction(
        input logic [31:0] instruction,
        input logic [4:0]  rd_addr,
        input logic [31:0] rd_data
    );
        begin
            u_imem.write_word(program_pc, instruction);
            expect_retirement(
                program_pc,
                instruction,
                1'b1,
                rd_addr,
                rd_data
            );
            program_pc = program_pc + 32'd4;
        end
    endtask

    task automatic emit_no_write_instruction(
        input logic [31:0] instruction
    );
        begin
            u_imem.write_word(program_pc, instruction);
            expect_retirement(
                program_pc,
                instruction,
                1'b0,
                '0,
                '0
            );
            program_pc = program_pc + 32'd4;
        end
    endtask

    task automatic emit_squashed_instruction(
        input logic [31:0] instruction
    );
        begin
            u_imem.write_word(program_pc, instruction);
            program_pc = program_pc + 32'd4;
        end
    endtask

    task automatic emit_csr_retirement(
        input logic [11:0] csr_address,
        input logic [4:0]  source_field,
        input logic [2:0]  funct3,
        input logic [4:0]  rd_addr,
        input logic [31:0] expected_old_data
    );
        logic [31:0] instruction;
        begin
            instruction = instruction_csr(
                csr_address,
                source_field,
                funct3,
                rd_addr
            );

            if (rd_addr == 5'b0) begin
                emit_no_write_instruction(instruction);
            end else begin
                emit_writeback_instruction(
                    instruction,
                    rd_addr,
                    expected_old_data
                );
            end
        end
    endtask

    task automatic check_csr_trap_blocks_store(
        input logic [31:0] fault_pc,
        input logic [31:0] fault_instruction,
        input logic [31:0] younger_store_pc
    );
        begin
            while (
                (trap_valid !== 1'b1) &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(posedge clk);
                #1;
            end

            check_condition(
                (trap_valid === 1'b1) &&
                (trap_pc === fault_pc) &&
                (trap_cause === EXCEPTION_CAUSE_ILLEGAL_INSTRUCTION) &&
                (trap_value === fault_instruction),
                "CSR access did not produce the expected illegal trap"
            );
            check_condition(
                (dut.ex_mem_q.csr_ctrl.valid === 1'b1) &&
                (dut.csr_access_illegal === 1'b1) &&
                (dut.final_mem_exception.valid === 1'b1) &&
                (dut.final_mem_exception.cause ===
                    EXCEPTION_CAUSE_ILLEGAL_INSTRUCTION),
                "illegal CSR access did not reach the MEM access checker"
            );
            check_condition(
                (dut.ex_mem_active_candidate.valid === 1'b1) &&
                (dut.ex_mem_active_candidate.pc === younger_store_pc) &&
                (dut.ex_mem_active_candidate.mem_ctrl.memory_write === 1'b1),
                "younger store was not aligned in EX with the CSR trap"
            );
            check_condition(
                (dmem_req_ready === 1'b1) &&
                (dmem_req_valid === 1'b0) &&
                (dut.u_lsu.request_fire === 1'b0) &&
                (dut.u_lsu.outstanding_q === 1'b0) &&
                (dut.ex_request_block === 1'b1),
                "illegal CSR trap did not block the ready younger store"
            );
        end
    endtask

    task automatic install_trap_handler(
        input logic [4:0]  rd_addr,
        input logic [31:0] rd_data
    );
        logic [31:0] instruction;
        begin
            instruction = instruction_op_imm(
                FUNCT3_ADD_SUB,
                rd_addr,
                5'd0,
                rd_data
            );
            u_imem.write_word(TRAP_VECTOR, instruction);
            expect_retirement(
                TRAP_VECTOR,
                instruction,
                1'b1,
                rd_addr,
                rd_data
            );
            expected_trap_vector_fetch_count++;
        end
    endtask

    task automatic emit_interrupt_configuration(
        input logic [31:0] mie_value,
        input logic        global_enable
    );
        logic [31:0] mie_source_value;
        begin
            mie_source_value = sign_extend_immediate_12(mie_value);
            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd20,
                    5'd0,
                    mie_value
                ),
                5'd20,
                mie_source_value
            );
            emit_csr_retirement(
                CSR_ADDR_MIE,
                5'd20,
                FUNCT3_CSRRW,
                5'd0,
                32'b0
            );
            emit_csr_retirement(
                CSR_ADDR_MSTATUS,
                global_enable ? 5'd8 : 5'd0,
                FUNCT3_CSRRWI,
                5'd0,
                32'h0000_1800
            );
        end
    endtask

    task automatic install_interrupt_handler_no_return(
        input logic [31:0] vector,
        input logic [31:0] first_value,
        input logic [31:0] second_value
    );
        logic [31:0] first_instruction;
        logic [31:0] second_instruction;
        begin
            first_instruction = instruction_op_imm(
                FUNCT3_ADD_SUB,
                5'd31,
                5'd0,
                first_value
            );
            second_instruction = instruction_op_imm(
                FUNCT3_ADD_SUB,
                5'd30,
                5'd0,
                second_value
            );

            u_imem.write_word(vector, first_instruction);
            expect_retirement(
                vector,
                first_instruction,
                1'b1,
                5'd31,
                first_value
            );
            u_imem.write_word(vector + 32'd4, second_instruction);
            expect_retirement(
                vector + 32'd4,
                second_instruction,
                1'b1,
                5'd30,
                second_value
            );

            if (vector == TRAP_VECTOR) begin
                expected_trap_vector_fetch_count++;
            end
        end
    endtask

    task automatic install_interrupt_handler_mret(
        input logic [31:0] vector,
        input logic [31:0] marker_value
    );
        logic [31:0] marker_instruction;
        begin
            marker_instruction = instruction_op_imm(
                FUNCT3_ADD_SUB,
                5'd31,
                5'd0,
                marker_value
            );
            u_imem.write_word(vector, marker_instruction);
            expect_retirement(
                vector,
                marker_instruction,
                1'b1,
                5'd31,
                marker_value
            );
            u_imem.write_word(vector + 32'd4, INSTRUCTION_MRET);
            expect_retirement(
                vector + 32'd4,
                INSTRUCTION_MRET,
                1'b0,
                5'd0,
                32'b0
            );

            if (vector == TRAP_VECTOR) begin
                expected_trap_vector_fetch_count++;
            end
        end
    endtask

    task automatic wait_for_committable_mem_pc(
        input logic [31:0] expected_pc
    );
        begin
            while (
                !(
                    dut.ex_mem_q.valid &&
                    (dut.ex_mem_q.pc == expected_pc) &&
                    dut.mem_commit_candidate
                ) &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(negedge clk);
                #1;
            end
            check_condition(
                dut.ex_mem_q.valid &&
                (dut.ex_mem_q.pc == expected_pc) &&
                dut.mem_commit_candidate,
                "expected instruction did not reach a committable MEM boundary"
            );
        end
    endtask

    task automatic drive_irq_levels(
        input logic software_pending,
        input logic timer_pending,
        input logic external_pending
    );
        begin
            irq_software = software_pending;
            irq_timer    = timer_pending;
            irq_external = external_pending;
        end
    endtask

    task automatic run_single_trap_scenario(
        input string       name,
        input logic [31:0] fault_instruction,
        input logic [31:0] expected_cause,
        input logic [31:0] expected_value,
        input logic        inject_imem_error,
        input logic [31:0] handler_value
    );
        logic [31:0] younger_store;
        logic [31:0] fault_pc;
        begin
            begin_scenario(name);

            younger_store = encoder_s(
                FUNCT3_SW,
                5'd0,
                5'd30,
                32'h0000_0100
            );

            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd30,
                    5'd0,
                    32'h0000_005a
                ),
                5'd30,
                32'h0000_005a
            );

            fault_pc = program_pc;
            u_imem.write_word(fault_pc, fault_instruction);
            if (inject_imem_error) begin
                u_imem.set_error(fault_pc, 1'b1);
            end
            expect_trap(
                fault_pc,
                expected_cause,
                expected_value
            );
            program_pc = program_pc + 32'd4;

            emit_squashed_instruction(younger_store);
            install_trap_handler(5'd31, handler_value);

            release_reset();
            wait_for_completion();

            check_condition(
                u_dmem.read_word(32'h0000_0100) == 32'b0,
                "faulting or younger store modified memory"
            );
            check_condition(
                !dut.u_lsu.outstanding_q,
                "trap scenario left a phantom LSU transaction"
            );
            check_condition(
                (dut.u_csr_trap.mepc_q == fault_pc) &&
                (dut.u_csr_trap.mcause_q == expected_cause) &&
                (dut.u_csr_trap.mtval_q == expected_value),
                "trap CSRs do not match the committed trap payload"
            );

            end_scenario();
        end
    endtask

    task automatic begin_scenario(
        input string name
    );
        begin
            @(negedge clk);
            rst = 1'b1;

            imem_request_enable  = 1'b1;
            imem_response_enable = 1'b1;
            dmem_request_enable  = 1'b1;
            dmem_response_enable = 1'b1;
            d5_random_active = 1'b0;
            d5_drain_active = 1'b0;
            irq_software = 1'b0;
            irq_timer    = 1'b0;
            irq_external = 1'b0;

            scenario_name   = name;
            scenario_active = 1'b1;
            scenario_count++;

            expected_retire_count       = 0;
            observed_retire_count       = 0;
            expected_dmem_request_count = 0;
            observed_dmem_request_count = 0;
            expected_trap_count         = 0;
            observed_trap_count         = 0;
            expected_trap_vector_fetch_count = 0;
            observed_trap_vector_fetch_count = 0;
            expected_mdu_request_count  = 0;
            observed_mdu_request_count  = 0;
            expected_mdu_response_count = 0;
            observed_mdu_response_count = 0;
            expected_interrupt_take_count = 0;
            observed_interrupt_take_count = 0;
            expected_post_interrupt_take_count = 0;
            observed_post_interrupt_take_count = 0;
            expected_empty_interrupt_take_count = 0;
            observed_empty_interrupt_take_count = 0;

            expected_late_result_hazard_count = 0;
            expected_redirect_count          = 0;
            minimum_ex_request_wait_count    = 0;
            minimum_ex_multicycle_wait_count = 0;
            minimum_mem_response_wait_count  = 0;
            minimum_imem_request_stall_count = 0;

            late_result_hazard_count = 0;
            redirect_count          = 0;
            ex_request_wait_count   = 0;
            ex_multicycle_wait_count = 0;
            mem_response_wait_count = 0;
            imem_request_stall_count = 0;

            d5_imem_request_stall_cycles = 0;
            d5_imem_response_delay_cycles = 0;
            d5_dmem_request_stall_cycles = 0;
            d5_dmem_response_delay_cycles = 0;
            d5_coverage_bitmap = 16'b0;


            scenario_cycle_count = 0;
            scenario_check_count = 0;
            scenario_error_count = 0;
            program_pc = RESET_VECTOR;

            u_imem.clear_memory(RV32_NOP);
            u_dmem.clear_memory(8'h00);

            repeat (2) begin
                @(posedge clk);
                #1;
            end
        end
    endtask

    task automatic release_reset;
        begin
            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    task automatic wait_for_completion;
        begin
            while (
                (
                    (observed_retire_count < expected_retire_count) ||
                    (observed_trap_count < expected_trap_count)
                ) &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(posedge clk);
                #1;
            end

            check_condition(
                scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES,
                $sformatf(
                    "timeout: retire %0d/%0d trap %0d/%0d",
                    observed_retire_count,
                    expected_retire_count,
                    observed_trap_count,
                    expected_trap_count
                )
            );
        end
    endtask

    task automatic wait_for_d5_quiescence;
        int unsigned drain_cycle_count;
        begin
            d5_drain_active = 1'b1;
            imem_request_enable = 1'b0;
            drain_cycle_count = d5_max_stall_cycles + 32'd8;

            check_condition(
                !dmem_req_valid &&
                !dmem_rsp_valid &&
                !dut.u_lsu.outstanding_q &&
                (dmem_outstanding_count == 0),
                "D5 completion left a live LSU request or response"
            );
            check_condition(
                dut.mdu_idle &&
                !dut.mdu_req_valid &&
                !dut.mdu_rsp_valid &&
                !dut.ex_hold_valid,
                "D5 completion left a live MDU or held EX operation"
            );

            repeat (drain_cycle_count) begin
                @(posedge clk);
                #1;
                check_condition(
                    !dmem_req_valid &&
                    !dmem_rsp_valid &&
                    !dut.u_lsu.outstanding_q &&
                    (dmem_outstanding_count == 0),
                    "D5 drain observed a late LSU request or response"
                );
                check_condition(
                    dut.mdu_idle &&
                    !dut.mdu_req_valid &&
                    !dut.mdu_rsp_valid &&
                    !dut.ex_hold_valid,
                    "D5 drain observed a late MDU or held EX operation"
                );
            end

            d5_drain_active = 1'b0;
        end
    endtask

    task automatic end_scenario;
        begin
            check_condition(
                observed_retire_count == expected_retire_count,
                $sformatf(
                    "retirement count %0d, expected %0d",
                    observed_retire_count,
                    expected_retire_count
                )
            );
            check_condition(
                observed_dmem_request_count ==
                    expected_dmem_request_count,
                $sformatf(
                    "DMem request count %0d, expected %0d",
                    observed_dmem_request_count,
                    expected_dmem_request_count
                )
            );
            check_condition(
                observed_trap_count == expected_trap_count,
                $sformatf(
                    "trap count %0d, expected %0d",
                    observed_trap_count,
                    expected_trap_count
                )
            );
            check_condition(
                observed_trap_vector_fetch_count ==
                    expected_trap_vector_fetch_count,
                $sformatf(
                    "trap-vector fetch count %0d, expected %0d",
                    observed_trap_vector_fetch_count,
                    expected_trap_vector_fetch_count
                )
            );
            check_condition(
                observed_mdu_request_count == expected_mdu_request_count,
                $sformatf(
                    "MDU request count %0d, expected %0d",
                    observed_mdu_request_count,
                    expected_mdu_request_count
                )
            );
            check_condition(
                observed_mdu_response_count == expected_mdu_response_count,
                $sformatf(
                    "MDU response count %0d, expected %0d",
                    observed_mdu_response_count,
                    expected_mdu_response_count
                )
            );
            check_condition(
                observed_interrupt_take_count ==
                    expected_interrupt_take_count,
                $sformatf(
                    "interrupt take count %0d, expected %0d",
                    observed_interrupt_take_count,
                    expected_interrupt_take_count
                )
            );
            check_condition(
                observed_post_interrupt_take_count ==
                    expected_post_interrupt_take_count,
                $sformatf(
                    "post-commit interrupt count %0d, expected %0d",
                    observed_post_interrupt_take_count,
                    expected_post_interrupt_take_count
                )
            );
            check_condition(
                observed_empty_interrupt_take_count ==
                    expected_empty_interrupt_take_count,
                $sformatf(
                    "empty-pipeline interrupt count %0d, expected %0d",
                    observed_empty_interrupt_take_count,
                    expected_empty_interrupt_take_count
                )
            );
            if (!d5_random_active) begin
                check_condition(
                    late_result_hazard_count ==
                        expected_late_result_hazard_count,
                    $sformatf(
                        "late-result hazard count %0d, expected %0d",
                        late_result_hazard_count,
                        expected_late_result_hazard_count
                    )
                );
            end
            check_condition(
                redirect_count == expected_redirect_count,
                $sformatf(
                    "redirect count %0d, expected %0d",
                    redirect_count,
                    expected_redirect_count
                )
            );
            check_condition(
                ex_request_wait_count >= minimum_ex_request_wait_count,
                $sformatf(
                    "EX request wait count %0d, expected at least %0d",
                    ex_request_wait_count,
                    minimum_ex_request_wait_count
                )
            );
            check_condition(
                ex_multicycle_wait_count >=
                    minimum_ex_multicycle_wait_count,
                $sformatf(
                    "EX multicycle wait count %0d, expected at least %0d",
                    ex_multicycle_wait_count,
                    minimum_ex_multicycle_wait_count
                )
            );
            check_condition(
                mem_response_wait_count >= minimum_mem_response_wait_count,
                $sformatf(
                    "MEM response wait count %0d, expected at least %0d",
                    mem_response_wait_count,
                    minimum_mem_response_wait_count
                )
            );
            check_condition(
                imem_request_stall_count >=
                    minimum_imem_request_stall_count,
                $sformatf(
                    "IMem request stall count %0d, expected at least %0d",
                    imem_request_stall_count,
                    minimum_imem_request_stall_count
                )
            );

            if (scenario_error_count == 0) begin
                passed_scenario_count++;
                $display(
                    "[PASS] %-28s cycles=%0d retire=%0d trap=%0d dmem=%0d checks=%0d",
                    scenario_name,
                    scenario_cycle_count,
                    observed_retire_count,
                    observed_trap_count,
                    observed_dmem_request_count,
                    scenario_check_count
                );
                $display(
                    "       events: late_result=%0d redirect=%0d ex_wait=%0d mdu_wait=%0d mdu_req/rsp=%0d/%0d irq=%0d(post=%0d empty=%0d) mem_wait=%0d imem_req_stall=%0d",
                    late_result_hazard_count,
                    redirect_count,
                    ex_request_wait_count,
                    ex_multicycle_wait_count,
                    observed_mdu_request_count,
                    observed_mdu_response_count,
                    observed_interrupt_take_count,
                    observed_post_interrupt_take_count,
                    observed_empty_interrupt_take_count,
                    mem_response_wait_count,
                    imem_request_stall_count
                );
            end else begin
                $display(
                    "[FAIL] %-28s errors=%0d",
                    scenario_name,
                    scenario_error_count
                );
            end

            scenario_active = 1'b0;
        end
    endtask

    task automatic scenario_integer_and_forwarding;
        begin
            begin_scenario("integer_and_forwarding");

            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd1, 5'd0, 32'd5),
                5'd1,
                32'd5
            );
            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd2,
                    5'd0,
                    32'hffff_fffd
                ),
                5'd2,
                32'hffff_fffd
            );
            emit_writeback_instruction(
                encoder_r(FUNCT3_ADD_SUB, FUNCT7_BASE, 5'd3, 5'd1, 5'd2),
                5'd3,
                32'd2
            );
            emit_writeback_instruction(
                encoder_r(
                    FUNCT3_ADD_SUB,
                    FUNCT7_SUB_SRA,
                    5'd4,
                    5'd1,
                    5'd2
                ),
                5'd4,
                32'd8
            );
            emit_writeback_instruction(
                encoder_r(FUNCT3_SLL, FUNCT7_BASE, 5'd5, 5'd1, 5'd3),
                5'd5,
                32'd20
            );
            emit_writeback_instruction(
                encoder_r(FUNCT3_SLT, FUNCT7_BASE, 5'd6, 5'd2, 5'd1),
                5'd6,
                32'd1
            );
            emit_writeback_instruction(
                encoder_r(FUNCT3_SLTU, FUNCT7_BASE, 5'd7, 5'd2, 5'd1),
                5'd7,
                32'd0
            );
            emit_writeback_instruction(
                encoder_r(FUNCT3_XOR, FUNCT7_BASE, 5'd8, 5'd1, 5'd2),
                5'd8,
                32'hffff_fff8
            );
            emit_writeback_instruction(
                encoder_r(FUNCT3_SRL_SRA, FUNCT7_BASE, 5'd9, 5'd2, 5'd1),
                5'd9,
                32'h07ff_ffff
            );
            emit_writeback_instruction(
                encoder_r(
                    FUNCT3_SRL_SRA,
                    FUNCT7_SUB_SRA,
                    5'd10,
                    5'd2,
                    5'd1
                ),
                5'd10,
                32'hffff_ffff
            );
            emit_writeback_instruction(
                encoder_r(FUNCT3_OR, FUNCT7_BASE, 5'd11, 5'd1, 5'd2),
                5'd11,
                32'hffff_fffd
            );
            emit_writeback_instruction(
                encoder_r(FUNCT3_AND, FUNCT7_BASE, 5'd12, 5'd1, 5'd2),
                5'd12,
                32'd5
            );
            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd13,
                    5'd1,
                    32'hffff_fffa
                ),
                5'd13,
                32'hffff_ffff
            );
            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_SLT,
                    5'd14,
                    5'd2,
                    32'hffff_fffe
                ),
                5'd14,
                32'd1
            );
            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_SLTU,
                    5'd15,
                    5'd1,
                    32'hffff_ffff
                ),
                5'd15,
                32'd1
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_XOR, 5'd16, 5'd1, 32'h0000_000f),
                5'd16,
                32'h0000_000a
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_OR, 5'd17, 5'd1, 32'h0000_0020),
                5'd17,
                32'h0000_0025
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_AND, 5'd18, 5'd2, 32'h0000_000f),
                5'd18,
                32'h0000_000d
            );
            emit_writeback_instruction(
                instruction_shift_imm(
                    FUNCT3_SLL,
                    FUNCT7_BASE,
                    5'd19,
                    5'd1,
                    5'd31
                ),
                5'd19,
                32'h8000_0000
            );
            emit_writeback_instruction(
                instruction_shift_imm(
                    FUNCT3_SRL_SRA,
                    FUNCT7_BASE,
                    5'd20,
                    5'd19,
                    5'd31
                ),
                5'd20,
                32'd1
            );
            emit_writeback_instruction(
                instruction_shift_imm(
                    FUNCT3_SRL_SRA,
                    FUNCT7_SUB_SRA,
                    5'd21,
                    5'd19,
                    5'd31
                ),
                5'd21,
                32'hffff_ffff
            );
            emit_writeback_instruction(
                encoder_u(OPCODE_LUI, 5'd22, 32'h1234_5000),
                5'd22,
                32'h1234_5000
            );
            emit_writeback_instruction(
                encoder_u(OPCODE_AUIPC, 5'd23, 32'h0000_1000),
                5'd23,
                32'h0000_1058
            );
            emit_no_write_instruction(32'h0ff0_000f);
            emit_no_write_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd0, 5'd0, 32'd123)
            );
            emit_writeback_instruction(
                encoder_r(FUNCT3_ADD_SUB, FUNCT7_BASE, 5'd24, 5'd0, 5'd1),
                5'd24,
                32'd5
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd25, 5'd0, 32'd1),
                5'd25,
                32'd1
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd25, 5'd25, 32'd2),
                5'd25,
                32'd3
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd26, 5'd25, 32'd4),
                5'd26,
                32'd7
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd27, 5'd0, 32'd9),
                5'd27,
                32'd9
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd28, 5'd0, 32'd1),
                5'd28,
                32'd1
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd29, 5'd0, 32'd2),
                5'd29,
                32'd2
            );
            emit_writeback_instruction(
                encoder_r(FUNCT3_ADD_SUB, FUNCT7_BASE, 5'd30, 5'd27, 5'd0),
                5'd30,
                32'd9
            );

            release_reset();
            wait_for_completion();
            end_scenario();
        end
    endtask

    task automatic scenario_load_store_and_hazards;
        begin
            begin_scenario("load_store_and_hazards");
            u_dmem.write_word(32'h0000_0100, 32'h1122_3344);

            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd1, 5'd0, 32'h100),
                5'd1,
                32'h0000_0100
            );
            emit_writeback_instruction(
                instruction_load(FUNCT3_LW, 5'd2, 5'd1, 32'd0),
                5'd2,
                32'h1122_3344
            );
            expect_dmem_request(1'b0, 32'h100, '0, '0);

            emit_writeback_instruction(
                encoder_r(FUNCT3_ADD_SUB, FUNCT7_BASE, 5'd3, 5'd2, 5'd2),
                5'd3,
                32'h2244_6688
            );
            emit_no_write_instruction(
                encoder_s(FUNCT3_SW, 5'd1, 5'd3, 32'd4)
            );
            expect_dmem_request(
                1'b1,
                32'h104,
                32'h2244_6688,
                4'b1111
            );

            emit_writeback_instruction(
                instruction_load(FUNCT3_LW, 5'd4, 5'd1, 32'd4),
                5'd4,
                32'h2244_6688
            );
            expect_dmem_request(1'b0, 32'h104, '0, '0);

            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd5, 5'd4, 32'd1),
                5'd5,
                32'h2244_6689
            );
            emit_writeback_instruction(
                encoder_r(FUNCT3_ADD_SUB, FUNCT7_BASE, 5'd6, 5'd3, 5'd5),
                5'd6,
                32'h4488_cd11
            );
            emit_no_write_instruction(
                encoder_s(FUNCT3_SW, 5'd1, 5'd6, 32'd8)
            );
            expect_dmem_request(
                1'b1,
                32'h108,
                32'h4488_cd11,
                4'b1111
            );

            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd7, 5'd0, 32'h80),
                5'd7,
                32'h0000_0080
            );
            emit_no_write_instruction(
                encoder_s(FUNCT3_SB, 5'd1, 5'd7, 32'd9)
            );
            expect_dmem_request(
                1'b1,
                32'h109,
                32'h0000_8000,
                4'b0010
            );

            emit_writeback_instruction(
                instruction_load(FUNCT3_LB, 5'd8, 5'd1, 32'd9),
                5'd8,
                32'hffff_ff80
            );
            expect_dmem_request(1'b0, 32'h109, '0, '0);
            emit_writeback_instruction(
                instruction_load(FUNCT3_LBU, 5'd9, 5'd1, 32'd9),
                5'd9,
                32'h0000_0080
            );
            expect_dmem_request(1'b0, 32'h109, '0, '0);

            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd10,
                    5'd0,
                    32'hffff_ff80
                ),
                5'd10,
                32'hffff_ff80
            );
            emit_no_write_instruction(
                encoder_s(FUNCT3_SH, 5'd1, 5'd10, 32'd10)
            );
            expect_dmem_request(
                1'b1,
                32'h10a,
                32'hff80_0000,
                4'b1100
            );

            emit_writeback_instruction(
                instruction_load(FUNCT3_LH, 5'd11, 5'd1, 32'd10),
                5'd11,
                32'hffff_ff80
            );
            expect_dmem_request(1'b0, 32'h10a, '0, '0);
            emit_writeback_instruction(
                instruction_load(FUNCT3_LHU, 5'd12, 5'd1, 32'd10),
                5'd12,
                32'h0000_ff80
            );
            expect_dmem_request(1'b0, 32'h10a, '0, '0);

            emit_writeback_instruction(
                instruction_load(FUNCT3_LW, 5'd13, 5'd1, 32'd4),
                5'd13,
                32'h2244_6688
            );
            expect_dmem_request(1'b0, 32'h104, '0, '0);
            emit_no_write_instruction(
                encoder_s(FUNCT3_SW, 5'd1, 5'd13, 32'd12)
            );
            expect_dmem_request(
                1'b1,
                32'h10c,
                32'h2244_6688,
                4'b1111
            );
            emit_writeback_instruction(
                instruction_load(FUNCT3_LW, 5'd14, 5'd1, 32'd12),
                5'd14,
                32'h2244_6688
            );
            expect_dmem_request(1'b0, 32'h10c, '0, '0);

            expected_late_result_hazard_count = 3;

            release_reset();
            wait_for_completion();

            check_condition(
                u_dmem.read_word(32'h100) == 32'h1122_3344,
                "source data word changed unexpectedly"
            );
            check_condition(
                u_dmem.read_word(32'h104) == 32'h2244_6688,
                "SW result at 0x104 is incorrect"
            );
            check_condition(
                u_dmem.read_word(32'h108) == 32'hff80_8011,
                "SB/SH lane merge at 0x108 is incorrect"
            );
            check_condition(
                u_dmem.read_word(32'h10c) == 32'h2244_6688,
                "load-to-store result at 0x10c is incorrect"
            );

            end_scenario();
        end
    endtask

    task automatic scenario_control_flow;
        logic [31:0] poison_store;
        begin
            begin_scenario("control_flow_and_flush");
            poison_store = encoder_s(
                FUNCT3_SW,
                5'd0,
                5'd2,
                32'h0000_0180
            );

            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd1,
                    5'd0,
                    32'hffff_ffff
                ),
                5'd1,
                32'hffff_ffff
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd2, 5'd0, 32'd1),
                5'd2,
                32'd1
            );

            emit_no_write_instruction(
                encoder_b(FUNCT3_BEQ, 5'd2, 5'd2, 32'd8)
            );
            emit_squashed_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd31, 5'd0, 32'd1)
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd3, 5'd0, 32'd3),
                5'd3,
                32'd3
            );
            emit_no_write_instruction(
                encoder_b(FUNCT3_BEQ, 5'd1, 5'd2, 32'd8)
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd4, 5'd0, 32'd4),
                5'd4,
                32'd4
            );

            emit_no_write_instruction(
                encoder_b(FUNCT3_BNE, 5'd1, 5'd2, 32'd8)
            );
            emit_squashed_instruction(poison_store);
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd5, 5'd0, 32'd5),
                5'd5,
                32'd5
            );
            emit_no_write_instruction(
                encoder_b(FUNCT3_BNE, 5'd2, 5'd2, 32'd8)
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd6, 5'd0, 32'd6),
                5'd6,
                32'd6
            );

            emit_no_write_instruction(
                encoder_b(FUNCT3_BLT, 5'd1, 5'd2, 32'd8)
            );
            emit_squashed_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd31, 5'd0, 32'd2)
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd7, 5'd0, 32'd7),
                5'd7,
                32'd7
            );
            emit_no_write_instruction(
                encoder_b(FUNCT3_BLT, 5'd2, 5'd1, 32'd8)
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd8, 5'd0, 32'd8),
                5'd8,
                32'd8
            );

            emit_no_write_instruction(
                encoder_b(FUNCT3_BGE, 5'd2, 5'd1, 32'd8)
            );
            emit_squashed_instruction(poison_store);
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd9, 5'd0, 32'd9),
                5'd9,
                32'd9
            );
            emit_no_write_instruction(
                encoder_b(FUNCT3_BGE, 5'd1, 5'd2, 32'd8)
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd10, 5'd0, 32'd10),
                5'd10,
                32'd10
            );

            emit_no_write_instruction(
                encoder_b(FUNCT3_BLTU, 5'd2, 5'd1, 32'd8)
            );
            emit_squashed_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd31, 5'd0, 32'd3)
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd11, 5'd0, 32'd11),
                5'd11,
                32'd11
            );
            emit_no_write_instruction(
                encoder_b(FUNCT3_BLTU, 5'd1, 5'd2, 32'd8)
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd12, 5'd0, 32'd12),
                5'd12,
                32'd12
            );

            emit_no_write_instruction(
                encoder_b(FUNCT3_BGEU, 5'd1, 5'd2, 32'd8)
            );
            emit_squashed_instruction(poison_store);
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd13, 5'd0, 32'd13),
                5'd13,
                32'd13
            );
            emit_no_write_instruction(
                encoder_b(FUNCT3_BGEU, 5'd2, 5'd1, 32'd8)
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd14, 5'd0, 32'd14),
                5'd14,
                32'd14
            );

            emit_writeback_instruction(
                encoder_j(5'd15, 32'd8),
                5'd15,
                32'h0000_0084
            );
            emit_squashed_instruction(poison_store);
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd16, 5'd0, 32'd16),
                5'd16,
                32'd16
            );

            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd17, 5'd0, 32'h99),
                5'd17,
                32'h0000_0099
            );
            emit_writeback_instruction(
                instruction_jalr(5'd18, 5'd17, 32'd0),
                5'd18,
                32'h0000_0094
            );
            emit_squashed_instruction(poison_store);
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd19, 5'd0, 32'd19),
                5'd19,
                32'd19
            );

            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd20, 5'd0, 32'd5),
                5'd20,
                32'd5
            );
            emit_no_write_instruction(
                encoder_b(FUNCT3_BEQ, 5'd20, 5'd20, 32'd8)
            );
            emit_squashed_instruction(poison_store);
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd21, 5'd0, 32'd21),
                5'd21,
                32'd21
            );

            expected_redirect_count = 9;

            release_reset();
            wait_for_completion();
            check_condition(
                u_dmem.read_word(32'h180) == 32'h0000_0000,
                "wrong-path store modified data memory"
            );
            end_scenario();
        end
    endtask

    task automatic scenario_protocol_backpressure;
        begin
            begin_scenario("protocol_backpressure");

            imem_request_enable  = 1'b0;
            imem_response_enable = 1'b0;
            dmem_request_enable  = 1'b0;
            dmem_response_enable = 1'b0;

            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd1, 5'd0, 32'h100),
                5'd1,
                32'h0000_0100
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd2, 5'd0, 32'h55),
                5'd2,
                32'h0000_0055
            );
            emit_no_write_instruction(
                encoder_s(FUNCT3_SW, 5'd1, 5'd2, 32'd0)
            );
            expect_dmem_request(
                1'b1,
                32'h100,
                32'h0000_0055,
                4'b1111
            );
            emit_writeback_instruction(
                instruction_load(FUNCT3_LW, 5'd3, 5'd1, 32'd0),
                5'd3,
                32'h0000_0055
            );
            expect_dmem_request(1'b0, 32'h100, '0, '0);
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd4, 5'd3, 32'd1),
                5'd4,
                32'h0000_0056
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd5, 5'd4, 32'd1),
                5'd5,
                32'h0000_0057
            );

            expected_late_result_hazard_count = 1;
            minimum_imem_request_stall_count = 3;
            minimum_ex_request_wait_count = 3;
            minimum_mem_response_wait_count = 3;

            release_reset();

            repeat (3) begin
                @(posedge clk);
                #1;
            end
            @(negedge clk);
            imem_request_enable = 1'b1;

            @(posedge clk);
            #1;
            check_condition(
                imem_outstanding_count == 1,
                "initial IMem request did not become outstanding"
            );

            repeat (2) begin
                @(posedge clk);
                #1;
            end
            @(negedge clk);
            imem_response_enable = 1'b1;

            while (dmem_req_valid !== 1'b1) begin
                @(negedge clk);
            end

            repeat (3) begin
                @(posedge clk);
                #1;
                check_condition(
                    dut.ex_hold_valid,
                    "backpressured EX request did not preserve a snapshot"
                );
                check_condition(
                    dut.ex_mem_active_candidate.exec_result === 32'h0000_0100,
                    "held EX request address changed after forwarding expired"
                );
                check_condition(
                    dut.ex_mem_active_candidate.mem_ctrl.memory_write &&
                        !dut.ex_mem_active_candidate.exception.valid,
                    "held EX request changed memory control or exception state"
                );
            end
            @(negedge clk);
            dmem_request_enable = 1'b1;

            @(posedge clk);
            #1;
            repeat (3) begin
                @(posedge clk);
                #1;
            end
            @(negedge clk);
            dmem_response_enable = 1'b1;

            wait_for_completion();
            check_condition(
                u_dmem.read_word(32'h100) == 32'h0000_0055,
                "backpressured store produced wrong memory value"
            );
            end_scenario();
        end
    endtask

    task automatic scenario_reset_during_imem;
        begin
            begin_scenario("reset_during_imem");
            imem_response_enable = 1'b0;

            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd1, 5'd0, 32'd42),
                5'd1,
                32'd42
            );

            release_reset();
            @(posedge clk);
            #1;
            check_condition(
                imem_outstanding_count == 1,
                "IMem request was not outstanding before reset"
            );

            @(negedge clk);
            rst = 1'b1;
            repeat (2) begin
                @(posedge clk);
                #1;
            end

            @(negedge clk);
            imem_response_enable = 1'b1;
            rst = 1'b0;

            wait_for_completion();
            end_scenario();
        end
    endtask

    task automatic scenario_mem_wait_blocks_redirect;
        logic [31:0] poison_store;
        begin
            begin_scenario("mem_wait_blocks_redirect");
            dmem_response_enable = 1'b0;
            u_dmem.write_word(32'h0000_0100, 32'h7654_3210);

            poison_store = encoder_s(
                FUNCT3_SW,
                5'd0,
                5'd1,
                32'h0000_0180
            );

            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd1, 5'd0, 32'd0),
                5'd1,
                32'd0
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd1, 5'd0, 32'd1),
                5'd1,
                32'd1
            );
            emit_writeback_instruction(
                instruction_load(FUNCT3_LW, 5'd2, 5'd0, 32'h100),
                5'd2,
                32'h7654_3210
            );
            expect_dmem_request(1'b0, 32'h100, '0, '0);
            emit_no_write_instruction(
                encoder_b(FUNCT3_BNE, 5'd1, 5'd0, 32'd8)
            );
            emit_squashed_instruction(poison_store);
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd3, 5'd0, 32'd3),
                5'd3,
                32'd3
            );

            expected_redirect_count = 1;
            minimum_mem_response_wait_count = 3;

            release_reset();
            while (
                (observed_dmem_request_count < 1) &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(posedge clk);
                #1;
            end
            check_condition(
                observed_dmem_request_count == 1,
                "blocking load request was not observed before timeout"
            );

            repeat (3) begin
                @(posedge clk);
                #1;
                check_condition(
                    dut.mem_response_wait &&
                    dut.raw_redirect.valid &&
                    !dut.redirect_commit,
                    "younger redirect was not blocked by MEM wait"
                );
            end

            @(negedge clk);
            dmem_response_enable = 1'b1;

            wait_for_completion();
            check_condition(
                u_dmem.read_word(32'h180) == 32'h0000_0000,
                "store on the branch wrong path modified memory"
            );
            end_scenario();
        end
    endtask

    task automatic scenario_precise_illegal_trap;
        logic [31:0] older_load;
        logic [31:0] illegal_instruction;
        logic [31:0] younger_store;
        begin
            begin_scenario("precise_illegal_trap");
            dmem_request_enable  = 1'b0;
            dmem_response_enable = 1'b0;

            older_load = instruction_load(
                FUNCT3_LW,
                5'd1,
                5'd0,
                32'h0000_0040
            );
            illegal_instruction = 32'hffff_ffff;
            younger_store = encoder_s(
                FUNCT3_SW,
                5'd0,
                5'd1,
                32'h0000_0100
            );

            u_dmem.write_word(32'h0000_0040, 32'h1122_3344);
            emit_writeback_instruction(
                older_load,
                5'd1,
                32'h1122_3344
            );
            expect_dmem_request(1'b0, 32'h0000_0040, '0, '0);

            u_imem.write_word(program_pc, illegal_instruction);
            expect_trap(
                program_pc,
                EXCEPTION_CAUSE_ILLEGAL_INSTRUCTION,
                illegal_instruction
            );
            program_pc = program_pc + 32'd4;

            emit_squashed_instruction(younger_store);
            install_trap_handler(5'd2, 32'd2);

            minimum_ex_request_wait_count   = 1;
            minimum_mem_response_wait_count = 1;

            release_reset();
            while (
                !(
                    (dut.ex_request_wait === 1'b1) &&
                    (dut.id_ex_q.valid === 1'b1) &&
                    (dut.id_ex_q.pc === 32'h0000_0000) &&
                    (dut.id_ex_q.instruction === older_load) &&
                    (dut.if_id_q.valid === 1'b1) &&
                    (dut.if_id_q.pc === 32'h0000_0004) &&
                    (dut.if_id_q.instruction === illegal_instruction) &&
                    (dut.fetch_response_available === 1'b1) &&
                    (imem_rsp_data === younger_store)
                ) &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(posedge clk);
                #1;
            end
            check_condition(
                (dut.ex_request_wait === 1'b1) &&
                (dut.id_ex_q.valid === 1'b1) &&
                (dut.id_ex_q.pc === 32'h0000_0000) &&
                (dut.id_ex_q.instruction === older_load) &&
                (dut.if_id_q.valid === 1'b1) &&
                (dut.if_id_q.pc === 32'h0000_0004) &&
                (dut.if_id_q.instruction === illegal_instruction) &&
                (dut.fetch_response_available === 1'b1) &&
                (imem_rsp_data === younger_store),
                "could not align load request, illegal instruction, and store response"
            );

            @(posedge clk);
            #1;
            check_condition(
                (dut.ex_request_wait === 1'b1) &&
                (dut.id_ex_q.instruction === older_load) &&
                (dut.if_id_q.instruction === illegal_instruction) &&
                (dut.fetch_response_available === 1'b1) &&
                (imem_rsp_data === younger_store),
                "aligned pre-request collision state was not held for one full cycle"
            );

            @(negedge clk);
            dmem_request_enable = 1'b1;

            while (
                !(
                    (dut.mem_response_wait === 1'b1) &&
                    (dut.u_lsu.outstanding_q === 1'b1) &&
                    (dmem_rsp_valid === 1'b0) &&
                    (dut.ex_mem_q.valid === 1'b1) &&
                    (dut.ex_mem_q.pc === 32'h0000_0000) &&
                    (dut.ex_mem_q.mem_ctrl.memory_read === 1'b1) &&
                    (dut.id_ex_q.valid === 1'b1) &&
                    (dut.id_ex_q.pc === 32'h0000_0004) &&
                    (dut.if_id_q.valid === 1'b1) &&
                    (dut.if_id_q.pc === 32'h0000_0008)
                ) &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(posedge clk);
                #1;
            end
            check_condition(
                (dut.mem_response_wait === 1'b1) &&
                (dut.u_lsu.outstanding_q === 1'b1) &&
                (dmem_rsp_valid === 1'b0) &&
                (dut.ex_mem_q.valid === 1'b1) &&
                (dut.ex_mem_q.pc === 32'h0000_0000) &&
                (dut.ex_mem_q.mem_ctrl.memory_read === 1'b1) &&
                (dut.id_ex_q.valid === 1'b1) &&
                (dut.id_ex_q.pc === 32'h0000_0004) &&
                (dut.if_id_q.valid === 1'b1) &&
                (dut.if_id_q.pc === 32'h0000_0008),
                "could not align older load, illegal instruction, and younger store"
            );

            @(posedge clk);
            #1;
            check_condition(
                (dut.mem_response_wait === 1'b1) &&
                (dut.u_lsu.outstanding_q === 1'b1) &&
                (dmem_rsp_valid === 1'b0) &&
                (dut.ex_mem_q.valid === 1'b1) &&
                (dut.ex_mem_q.pc === 32'h0000_0000) &&
                (dut.ex_mem_q.mem_ctrl.memory_read === 1'b1) &&
                (dut.id_ex_q.valid === 1'b1) &&
                (dut.id_ex_q.pc === 32'h0000_0004) &&
                (dut.if_id_q.valid === 1'b1) &&
                (dut.if_id_q.pc === 32'h0000_0008),
                "aligned trap collision state was not held for one full cycle"
            );

            @(negedge clk);
            dmem_response_enable = 1'b1;

            @(posedge clk);
            #1;
            check_condition(
                (trap_valid === 1'b1) &&
                (retire_valid === 1'b1) &&
                (dut.ex_mem_q.pc === 32'h0000_0004) &&
                (dut.mem_wb_q.pc === 32'h0000_0000),
                "controlled older-WB and illegal-trap collision did not form"
            );
            check_condition(
                (retire_pc === 32'h0000_0000) &&
                (retire_instr === older_load) &&
                (retire_rd_we === 1'b1) &&
                (retire_rd_addr === 5'd1) &&
                (retire_rd_data === 32'h1122_3344),
                "older load retirement payload was wrong beside trap"
            );
            check_condition(
                (trap_pc === 32'h0000_0004) &&
                (trap_cause === EXCEPTION_CAUSE_ILLEGAL_INSTRUCTION) &&
                (trap_value === illegal_instruction),
                "illegal trap payload was wrong beside older retirement"
            );
            check_condition(
                (dut.ex_mem_active_candidate.valid === 1'b1) &&
                (dut.ex_mem_active_candidate.pc === 32'h0000_0008) &&
                (dut.ex_mem_active_candidate.mem_ctrl.memory_write === 1'b1) &&
                (dmem_req_ready === 1'b1) &&
                (dmem_req_valid === 1'b0) &&
                (dut.u_lsu.request_fire === 1'b0) &&
                (dut.ex_request_block === 1'b1),
                "ready younger store was not blocked during controlled trap collision"
            );

            wait_for_completion();

            check_condition(
                u_dmem.read_word(32'h0000_0100) == 32'b0,
                "younger store modified memory before trap flush"
            );
            check_condition(
                !dut.u_lsu.outstanding_q,
                "blocked younger store left a phantom LSU transaction"
            );

            end_scenario();
        end
    endtask

    task automatic scenario_trap_beats_redirect;
        logic [31:0] illegal_instruction;
        begin
            begin_scenario("trap_beats_redirect");

            illegal_instruction = 32'h0000_0000;

            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd1, 5'd0, 32'd1),
                5'd1,
                32'd1
            );

            u_imem.write_word(program_pc, illegal_instruction);
            expect_trap(
                program_pc,
                EXCEPTION_CAUSE_ILLEGAL_INSTRUCTION,
                illegal_instruction
            );
            program_pc = program_pc + 32'd4;

            emit_squashed_instruction(
                encoder_b(FUNCT3_BEQ, 5'd0, 5'd0, 32'd8)
            );
            install_trap_handler(5'd3, 32'd3);

            release_reset();
            while (
                (trap_valid !== 1'b1) &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(posedge clk);
                #1;
            end

            check_condition(
                trap_valid === 1'b1,
                "MEM trap was not observed before timeout"
            );
            check_condition(
                (dut.raw_redirect.valid === 1'b1) &&
                (dut.raw_redirect.target === 32'h0000_0010),
                "younger taken branch did not present its raw redirect beside trap"
            );
            check_condition(
                (dut.redirect_commit === 1'b0) &&
                (dut.qualified_redirect === dut.trap_redirect) &&
                (dut.qualified_redirect.target === TRAP_VECTOR),
                "younger branch was not suppressed by the older MEM trap"
            );

            wait_for_completion();
            check_condition(
                redirect_count == 0,
                "younger branch redirect committed beside MEM trap"
            );

            end_scenario();
        end
    endtask

    task automatic scenario_dmem_fault_trap_wait;
        logic [31:0] faulting_load;
        begin
            begin_scenario("dmem_fault_trap_wait");
            dmem_response_enable = 1'b0;

            emit_writeback_instruction(
                encoder_u(OPCODE_LUI, 5'd1, 32'h0000_1000),
                5'd1,
                32'h0000_1000
            );

            faulting_load = instruction_load(
                FUNCT3_LW,
                5'd2,
                5'd1,
                32'b0
            );
            u_imem.write_word(program_pc, faulting_load);
            expect_dmem_request(1'b0, 32'h0000_1000, '0, '0);
            expect_trap(
                program_pc,
                EXCEPTION_CAUSE_LOAD_ACCESS_FAULT,
                32'h0000_1000
            );
            program_pc = program_pc + 32'd4;

            emit_squashed_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd31, 5'd0, 32'd31)
            );
            install_trap_handler(5'd4, 32'd4);

            minimum_mem_response_wait_count = 3;

            release_reset();
            while (
                (observed_dmem_request_count < 1) &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(posedge clk);
                #1;
            end
            check_condition(
                observed_dmem_request_count == 1,
                "faulting load request was not observed before timeout"
            );

            repeat (3) begin
                @(posedge clk);
                #1;
                check_condition(
                    dut.mem_response_wait &&
                    !trap_valid &&
                    (observed_trap_count == 0),
                    "load fault trapped before its response completed"
                );
            end

            @(negedge clk);
            dmem_response_enable = 1'b1;

            wait_for_completion();
            check_condition(
                !dut.u_lsu.outstanding_q,
                "faulting load transaction did not drain after trap"
            );

            end_scenario();
        end
    endtask

    task automatic scenario_trap_redirect_backpressure;
        begin
            begin_scenario("trap_redirect_backpressure");

            u_imem.write_word(program_pc, INSTRUCTION_ECALL);
            expect_trap(
                program_pc,
                EXCEPTION_CAUSE_ENVIRONMENT_CALL_M_MODE,
                32'b0
            );
            program_pc = program_pc + 32'd4;
            install_trap_handler(5'd5, 32'd5);

            minimum_imem_request_stall_count = 3;

            release_reset();
            while (
                (trap_valid !== 1'b1) &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(negedge clk);
            end
            check_condition(
                trap_valid === 1'b1,
                "ECALL trap was not observed before timeout"
            );
            imem_request_enable = 1'b0;

            repeat (3) begin
                @(posedge clk);
                #1;
                check_condition(
                    imem_req_valid &&
                    !imem_req_ready &&
                    (imem_req_addr == TRAP_VECTOR),
                    "backpressured trap target request was not held stable"
                );
            end

            @(negedge clk);
            imem_request_enable = 1'b1;

            wait_for_completion();
            end_scenario();
        end
    endtask

    task automatic scenario_control_address_misaligned;
        logic [31:0] not_taken_branch;
        logic [31:0] faulting_jalr;
        logic [31:0] younger_store;
        logic [31:0] fault_pc;
        begin
            begin_scenario("control_address_misaligned");

            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd1, 5'd0, 32'd3),
                5'd1,
                32'd3
            );

            not_taken_branch = encoder_b(
                FUNCT3_BEQ,
                5'd1,
                5'd0,
                32'd2
            );
            emit_no_write_instruction(not_taken_branch);

            fault_pc = program_pc;
            faulting_jalr = instruction_jalr(5'd2, 5'd1, 32'd0);
            u_imem.write_word(fault_pc, faulting_jalr);
            expect_trap(
                fault_pc,
                EXCEPTION_CAUSE_INSTRUCTION_ADDRESS_MISALIGNED,
                32'h0000_0002
            );
            program_pc = program_pc + 32'd4;

            younger_store = encoder_s(
                FUNCT3_SW,
                5'd0,
                5'd1,
                32'h0000_0100
            );
            emit_squashed_instruction(younger_store);
            install_trap_handler(5'd31, 32'h0000_0020);

            release_reset();
            wait_for_completion();

            check_condition(
                u_dmem.read_word(32'h0000_0100) == 32'b0,
                "younger store survived the misaligned control transfer"
            );
            check_condition(
                (dut.u_csr_trap.mepc_q == fault_pc) &&
                (dut.u_csr_trap.mcause_q ==
                    EXCEPTION_CAUSE_INSTRUCTION_ADDRESS_MISALIGNED) &&
                (dut.u_csr_trap.mtval_q == 32'h0000_0002),
                "control-transfer trap CSRs are incorrect"
            );

            end_scenario();
        end
    endtask

    task automatic scenario_store_access_fault;
        logic [31:0] faulting_store;
        logic [31:0] younger_store;
        logic [31:0] fault_pc;
        begin
            begin_scenario("store_access_fault");
            dmem_response_enable = 1'b0;

            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd1,
                    5'd0,
                    32'h0000_0400
                ),
                5'd1,
                32'h0000_0400
            );
            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd2,
                    5'd0,
                    32'h0000_005a
                ),
                5'd2,
                32'h0000_005a
            );

            fault_pc = program_pc;
            faulting_store = encoder_s(
                FUNCT3_SW,
                5'd1,
                5'd2,
                32'd0
            );
            u_imem.write_word(fault_pc, faulting_store);
            expect_dmem_request(
                1'b1,
                32'h0000_0400,
                32'h0000_005a,
                4'b1111
            );
            expect_trap(
                fault_pc,
                EXCEPTION_CAUSE_STORE_ACCESS_FAULT,
                32'h0000_0400
            );
            program_pc = program_pc + 32'd4;

            younger_store = encoder_s(
                FUNCT3_SW,
                5'd0,
                5'd2,
                32'h0000_0100
            );
            emit_squashed_instruction(younger_store);
            install_trap_handler(5'd31, 32'h0000_0021);

            minimum_mem_response_wait_count = 1;

            release_reset();
            while (
                !(
                    (dut.mem_response_wait === 1'b1) &&
                    (dut.u_lsu.outstanding_q === 1'b1) &&
                    (dut.ex_mem_active_candidate.valid === 1'b1) &&
                    (dut.ex_mem_active_candidate.pc === fault_pc + 32'd4) &&
                    (dut.ex_mem_active_candidate.mem_ctrl.memory_write === 1'b1)
                ) &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(posedge clk);
                #1;
            end
            check_condition(
                (dut.mem_response_wait === 1'b1) &&
                (dut.u_lsu.outstanding_q === 1'b1) &&
                (dut.ex_mem_active_candidate.valid === 1'b1) &&
                (dut.ex_mem_active_candidate.pc === fault_pc + 32'd4) &&
                (dut.ex_mem_active_candidate.mem_ctrl.memory_write === 1'b1),
                "could not align the faulting and younger stores"
            );
            check_condition(
                !trap_valid &&
                (observed_trap_count == 0),
                "store access fault trapped before its response"
            );

            @(posedge clk);
            #1;
            check_condition(
                dut.mem_response_wait &&
                !trap_valid &&
                (observed_trap_count == 0),
                "store access fault did not remain pending for a full cycle"
            );

            @(negedge clk);
            dmem_response_enable = 1'b1;

            wait_for_completion();
            check_condition(
                u_dmem.read_word(32'h0000_0100) == 32'b0,
                "younger store modified memory beside the access fault"
            );
            check_condition(
                !dut.u_lsu.outstanding_q,
                "faulting store transaction did not drain"
            );
            check_condition(
                (dut.u_csr_trap.mepc_q == fault_pc) &&
                (dut.u_csr_trap.mcause_q ==
                    EXCEPTION_CAUSE_STORE_ACCESS_FAULT) &&
                (dut.u_csr_trap.mtval_q == 32'h0000_0400),
                "store-access-fault trap CSRs are incorrect"
            );

            end_scenario();
        end
    endtask

    task automatic scenario_zicsr_rmw_and_hazard;
        begin
            begin_scenario("zicsr_rmw_and_hazard");

            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd1, 5'd0, 32'd15),
                5'd1,
                32'h0000_000f
            );

            emit_csr_retirement(
                CSR_ADDR_MSCRATCH,
                5'd1,
                FUNCT3_CSRRW,
                5'd5,
                32'h0000_0000
            );
            emit_csr_retirement(
                CSR_ADDR_MSCRATCH,
                5'd0,
                FUNCT3_CSRRS,
                5'd6,
                32'h0000_000f
            );
            emit_csr_retirement(
                CSR_ADDR_MSCRATCH,
                5'd6,
                FUNCT3_CSRRC,
                5'd7,
                32'h0000_000f
            );

            // The prior CSR result must be forwarded as the CSRRC source.
            // Read mscratch again to prove that the forwarded 0x0f cleared it.
            emit_csr_retirement(
                CSR_ADDR_MSCRATCH,
                5'd0,
                FUNCT3_CSRRS,
                5'd13,
                32'h0000_0000
            );

            emit_csr_retirement(
                CSR_ADDR_MSCRATCH,
                5'd27,
                FUNCT3_CSRRWI,
                5'd0,
                32'h0000_0000
            );
            emit_csr_retirement(
                CSR_ADDR_MSCRATCH,
                5'd4,
                FUNCT3_CSRRSI,
                5'd8,
                32'h0000_001b
            );
            emit_csr_retirement(
                CSR_ADDR_MSCRATCH,
                5'd3,
                FUNCT3_CSRRCI,
                5'd9,
                32'h0000_001f
            );
            emit_csr_retirement(
                CSR_ADDR_MSCRATCH,
                5'd0,
                FUNCT3_CSRRSI,
                5'd10,
                32'h0000_001c
            );
            emit_csr_retirement(
                CSR_ADDR_MSCRATCH,
                5'd0,
                FUNCT3_CSRRCI,
                5'd11,
                32'h0000_001c
            );
            emit_csr_retirement(
                CSR_ADDR_MSCRATCH,
                5'd0,
                FUNCT3_CSRRS,
                5'd12,
                32'h0000_001c
            );

            expected_late_result_hazard_count = 1;

            release_reset();
            wait_for_completion();
            check_condition(
                dut.u_csr_trap.mscratch_q == 32'h0000_001c,
                "final mscratch value did not match the CSR RMW sequence"
            );
            end_scenario();
        end
    endtask

    task automatic scenario_zicsr_mro_illegal;
        logic [31:0] fault_instruction;
        logic [31:0] fault_pc;
        logic [31:0] younger_store;
        logic [31:0] younger_store_pc;
        begin
            begin_scenario("zicsr_mro_illegal");

            emit_csr_retirement(
                CSR_ADDR_MVENDORID,
                5'd0,
                FUNCT3_CSRRS,
                5'd1,
                32'b0
            );
            emit_csr_retirement(
                CSR_ADDR_MVENDORID,
                5'd0,
                FUNCT3_CSRRC,
                5'd2,
                32'b0
            );
            emit_csr_retirement(
                CSR_ADDR_MVENDORID,
                5'd0,
                FUNCT3_CSRRSI,
                5'd3,
                32'b0
            );
            emit_csr_retirement(
                CSR_ADDR_MVENDORID,
                5'd0,
                FUNCT3_CSRRCI,
                5'd4,
                32'b0
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd5, 5'd0, 32'd1),
                5'd5,
                32'd1
            );

            fault_instruction = instruction_csr(
                CSR_ADDR_MVENDORID,
                5'd5,
                FUNCT3_CSRRW,
                5'd0
            );
            fault_pc = program_pc;
            u_imem.write_word(program_pc, fault_instruction);
            expect_trap(
                program_pc,
                EXCEPTION_CAUSE_ILLEGAL_INSTRUCTION,
                fault_instruction
            );
            program_pc = program_pc + 32'd4;

            younger_store = encoder_s(
                FUNCT3_SW,
                5'd0,
                5'd5,
                32'h0000_0100
            );
            younger_store_pc = program_pc;
            emit_squashed_instruction(younger_store);
            install_trap_handler(5'd14, 32'd14);

            release_reset();
            check_csr_trap_blocks_store(
                fault_pc,
                fault_instruction,
                younger_store_pc
            );
            wait_for_completion();
            check_condition(
                u_dmem.read_word(32'h0000_0100) == 32'b0,
                "MRO-illegal younger store modified memory"
            );
            check_condition(
                !dut.u_lsu.outstanding_q,
                "MRO-illegal younger store left an LSU transaction"
            );
            end_scenario();
        end
    endtask

    task automatic scenario_zicsr_unknown_illegal;
        logic [31:0] fault_instruction;
        logic [31:0] fault_pc;
        logic [31:0] younger_store;
        logic [31:0] younger_store_pc;
        begin
            begin_scenario("zicsr_unknown_illegal");

            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd1, 5'd0, 32'h5a),
                5'd1,
                32'h0000_005a
            );

            fault_instruction = instruction_csr(
                12'h302,
                5'd0,
                FUNCT3_CSRRS,
                5'd2
            );
            fault_pc = program_pc;
            u_imem.write_word(program_pc, fault_instruction);
            expect_trap(
                program_pc,
                EXCEPTION_CAUSE_ILLEGAL_INSTRUCTION,
                fault_instruction
            );
            program_pc = program_pc + 32'd4;

            younger_store = encoder_s(
                FUNCT3_SW,
                5'd0,
                5'd1,
                32'h0000_0104
            );
            younger_store_pc = program_pc;
            emit_squashed_instruction(younger_store);
            install_trap_handler(5'd15, 32'd15);

            release_reset();
            check_csr_trap_blocks_store(
                fault_pc,
                fault_instruction,
                younger_store_pc
            );
            wait_for_completion();
            check_condition(
                u_dmem.read_word(32'h0000_0104) == 32'b0,
                "unknown-CSR younger store modified memory"
            );
            check_condition(
                !dut.u_lsu.outstanding_q,
                "unknown-CSR younger store left an LSU transaction"
            );
            end_scenario();
        end
    endtask

    task automatic scenario_mret_wfi_return;
        logic [31:0] handler_write_mepc;
        logic [31:0] younger_store;
        logic [31:0] resume_instruction;
        begin
            begin_scenario("mret_wfi_return");

            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd1,
                    5'd0,
                    32'h0000_005a
                ),
                5'd1,
                32'h0000_005a
            );
            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd31,
                    5'd0,
                    32'b0
                ),
                5'd31,
                32'b0
            );

            u_imem.write_word(program_pc, INSTRUCTION_ECALL);
            expect_trap(
                program_pc,
                EXCEPTION_CAUSE_ENVIRONMENT_CALL_M_MODE,
                32'b0
            );
            program_pc = program_pc + 32'd4;

            emit_squashed_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd31,
                    5'd0,
                    32'h0000_0031
                )
            );

            program_pc = 32'h0000_0010;
            u_imem.write_word(program_pc, INSTRUCTION_WFI);
            resume_instruction = instruction_op_imm(
                FUNCT3_ADD_SUB,
                5'd2,
                5'd0,
                32'd2
            );
            u_imem.write_word(program_pc + 32'd4, resume_instruction);

            handler_write_mepc = instruction_csr(
                CSR_ADDR_MEPC,
                5'd16,
                FUNCT3_CSRRWI,
                5'd0
            );
            u_imem.write_word(TRAP_VECTOR, handler_write_mepc);
            expect_retirement(
                TRAP_VECTOR,
                handler_write_mepc,
                1'b0,
                5'd0,
                32'b0
            );
            u_imem.write_word(TRAP_VECTOR + 32'd4, INSTRUCTION_MRET);
            expect_retirement(
                TRAP_VECTOR + 32'd4,
                INSTRUCTION_MRET,
                1'b0,
                5'd0,
                32'b0
            );
            expect_retirement(
                32'h0000_0010,
                INSTRUCTION_WFI,
                1'b0,
                5'd0,
                32'b0
            );
            expect_retirement(
                32'h0000_0014,
                resume_instruction,
                1'b1,
                5'd2,
                32'd2
            );
            younger_store = encoder_s(
                FUNCT3_SW,
                5'd0,
                5'd1,
                32'h0000_0100
            );
            u_imem.write_word(TRAP_VECTOR + 32'd8, younger_store);
            expected_trap_vector_fetch_count = 1;

            release_reset();
            while (
                !dut.mret_commit &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(negedge clk);
                #1;
            end
            check_condition(
                dut.mret_commit &&
                dut.ex_mem_q.mret &&
                (dut.ex_mem_active_candidate.instruction == younger_store),
                "MRET did not align with the younger handler store"
            );
            check_condition(
                dut.ex_request_block &&
                !dmem_req_valid &&
                !dut.u_lsu.request_fire,
                "MRET did not suppress the younger store request"
            );
            check_condition(
                retire_valid &&
                (retire_pc == TRAP_VECTOR),
                "older handler CSR did not retire with MRET commit"
            );

            wait_for_completion();
            check_condition(
                u_dmem.read_word(32'h0000_0100) == 32'b0,
                "MRET wrong-path store modified memory"
            );
            check_condition(
                dut.u_idu.u_regfile.registers[2] == 32'd2,
                "first instruction after MRET target did not execute"
            );
            check_condition(
                dut.u_idu.u_regfile.registers[31] == 32'b0,
                "pre-return wrong-path instruction executed"
            );
            end_scenario();
        end
    endtask

    task automatic scenario_mret_beats_young_redirect;
        logic [31:0] handler_write_mepc;
        logic [31:0] younger_jal;
        logic [31:0] resume_instruction;
        begin
            begin_scenario("mret_beats_young_redirect");

            u_imem.write_word(program_pc, INSTRUCTION_ECALL);
            expect_trap(
                program_pc,
                EXCEPTION_CAUSE_ENVIRONMENT_CALL_M_MODE,
                32'b0
            );

            resume_instruction = instruction_op_imm(
                FUNCT3_ADD_SUB,
                5'd3,
                5'd0,
                32'd3
            );
            u_imem.write_word(32'h0000_001c, resume_instruction);

            handler_write_mepc = instruction_csr(
                CSR_ADDR_MEPC,
                5'd28,
                FUNCT3_CSRRWI,
                5'd0
            );
            u_imem.write_word(TRAP_VECTOR, handler_write_mepc);
            expect_retirement(
                TRAP_VECTOR,
                handler_write_mepc,
                1'b0,
                5'd0,
                32'b0
            );
            u_imem.write_word(TRAP_VECTOR + 32'd4, INSTRUCTION_MRET);
            expect_retirement(
                TRAP_VECTOR + 32'd4,
                INSTRUCTION_MRET,
                1'b0,
                5'd0,
                32'b0
            );
            expect_retirement(
                32'h0000_001c,
                resume_instruction,
                1'b1,
                5'd3,
                32'd3
            );
            younger_jal = encoder_j(5'd0, 32'h0000_0040);
            u_imem.write_word(TRAP_VECTOR + 32'd8, younger_jal);
            expected_trap_vector_fetch_count = 1;

            release_reset();
            while (
                !(
                    dut.mret_commit &&
                    dut.raw_redirect.valid
                ) &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(negedge clk);
                #1;
            end
            check_condition(
                dut.mret_commit &&
                dut.raw_redirect.valid &&
                !dut.redirect_commit &&
                (dut.qualified_redirect == dut.mret_redirect),
                "MRET redirect did not beat the younger taken JAL"
            );

            wait_for_completion();
            check_condition(
                dut.u_idu.u_regfile.registers[3] == 32'd3,
                "MRET redirect did not reach the programmed resume target"
            );
            end_scenario();
        end
    endtask

    task automatic scenario_machine_counters;
        logic [63:0] cycle_before_wait;
        begin
            begin_scenario("machine_counters");
            dmem_response_enable = 1'b0;
            u_dmem.write_word(32'h0000_0000, 32'h1234_5678);

            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd1,
                    5'd0,
                    32'd1
                ),
                5'd1,
                32'd1
            );
            emit_writeback_instruction(
                instruction_load(
                    FUNCT3_LW,
                    5'd2,
                    5'd0,
                    32'b0
                ),
                5'd2,
                32'h1234_5678
            );
            expect_dmem_request(1'b0, 32'b0, 32'b0, 4'b0000);
            emit_csr_retirement(
                CSR_ADDR_MINSTRET,
                5'd0,
                FUNCT3_CSRRS,
                5'd3,
                32'd2
            );
            emit_csr_retirement(
                CSR_ADDR_MINSTRET,
                5'd5,
                FUNCT3_CSRRWI,
                5'd4,
                32'd3
            );
            emit_csr_retirement(
                CSR_ADDR_MINSTRET,
                5'd0,
                FUNCT3_CSRRS,
                5'd5,
                32'd5
            );
            emit_no_write_instruction(INSTRUCTION_WFI);
            emit_csr_retirement(
                CSR_ADDR_MINSTRET,
                5'd0,
                FUNCT3_CSRRS,
                5'd6,
                32'd7
            );
            emit_csr_retirement(
                CSR_ADDR_MCYCLE,
                5'd0,
                FUNCT3_CSRRS,
                5'd0,
                32'b0
            );

            minimum_mem_response_wait_count = 3;
            release_reset();
            while (
                !dut.mem_response_wait &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(posedge clk);
                #1;
            end
            check_condition(
                dut.mem_response_wait,
                "counter scenario did not reach MEM response wait"
            );
            cycle_before_wait = dut.u_csr_trap.mcycle_q;
            repeat (3) begin
                @(posedge clk);
                #1;
                check_condition(
                    dut.mem_response_wait,
                    "load left MEM wait before response was enabled"
                );
            end
            check_condition(
                dut.u_csr_trap.mcycle_q ==
                    (cycle_before_wait + 64'd3),
                "mcycle did not advance once per MEM-wait cycle"
            );

            @(negedge clk);
            dmem_response_enable = 1'b1;
            wait_for_completion();
            check_condition(
                (dut.u_idu.u_regfile.registers[3] == 32'd2) &&
                (dut.u_idu.u_regfile.registers[4] == 32'd3) &&
                (dut.u_idu.u_regfile.registers[5] == 32'd5) &&
                (dut.u_idu.u_regfile.registers[6] == 32'd7),
                "counter reads did not observe program-order commit values"
            );
            end_scenario();
        end
    endtask

    task automatic scenario_counter_fault_exclusion;
        logic [31:0] illegal_instruction;
        logic [31:0] handler_counter_read;
        begin
            begin_scenario("counter_fault_exclusion");

            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd1,
                    5'd0,
                    32'd1
                ),
                5'd1,
                32'd1
            );
            illegal_instruction = 32'hffff_ffff;
            u_imem.write_word(program_pc, illegal_instruction);
            expect_trap(
                program_pc,
                EXCEPTION_CAUSE_ILLEGAL_INSTRUCTION,
                illegal_instruction
            );
            program_pc = program_pc + 32'd4;
            emit_squashed_instruction(
                encoder_s(
                    FUNCT3_SW,
                    5'd0,
                    5'd1,
                    32'h0000_0100
                )
            );

            handler_counter_read = instruction_csr(
                CSR_ADDR_MINSTRET,
                5'd0,
                FUNCT3_CSRRS,
                5'd7
            );
            u_imem.write_word(TRAP_VECTOR, handler_counter_read);
            expect_retirement(
                TRAP_VECTOR,
                handler_counter_read,
                1'b1,
                5'd7,
                32'd1
            );
            expected_trap_vector_fetch_count = 1;

            release_reset();
            wait_for_completion();
            check_condition(
                dut.u_idu.u_regfile.registers[7] == 32'd1,
                "faulting instruction incorrectly incremented minstret"
            );
            check_condition(
                u_dmem.read_word(32'h0000_0100) == 32'b0,
                "fault-younger store modified memory"
            );
            end_scenario();
        end
    endtask

    task automatic scenario_reset_during_dmem;
        begin
            begin_scenario("reset_during_dmem");
            dmem_response_enable = 1'b0;
            u_dmem.write_word(32'h0000_0000, 32'ha5a5_5a5a);

            emit_writeback_instruction(
                instruction_load(FUNCT3_LW, 5'd2, 5'd0, 32'd0),
                5'd2,
                32'ha5a5_5a5a
            );
            expect_dmem_request(1'b0, 32'h0000_0000, '0, '0);
            expect_dmem_request(1'b0, 32'h0000_0000, '0, '0);

            release_reset();
            while (observed_dmem_request_count < 1) begin
                @(posedge clk);
                #1;
            end

            @(negedge clk);
            rst = 1'b1;
            repeat (2) begin
                @(posedge clk);
                #1;
            end

            @(negedge clk);
            dmem_response_enable = 1'b1;
            rst = 1'b0;

            wait_for_completion();
            end_scenario();
        end
    endtask

    task automatic scenario_rv32m_multiply_variants;
        begin
            begin_scenario("rv32m_multiply_variants");

            emit_csr_retirement(
                CSR_ADDR_MISA,
                5'd0,
                FUNCT3_CSRRS,
                5'd8,
                32'h4000_1100
            );
            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd1,
                    5'd0,
                    32'hffff_fffe
                ),
                5'd1,
                32'hffff_fffe
            );
            emit_writeback_instruction(
                encoder_u(OPCODE_LUI, 5'd2, 32'h8000_0000),
                5'd2,
                32'h8000_0000
            );
            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd3,
                    5'd0,
                    32'd3
                ),
                5'd3,
                32'd3
            );

            emit_writeback_instruction(
                instruction_m(MDU_MUL, 5'd4, 5'd1, 5'd3),
                5'd4,
                32'hffff_fffa
            );
            emit_writeback_instruction(
                instruction_m(MDU_MULH, 5'd5, 5'd1, 5'd2),
                5'd5,
                32'h0000_0001
            );
            emit_writeback_instruction(
                instruction_m(MDU_MULHSU, 5'd6, 5'd1, 5'd2),
                5'd6,
                32'hffff_ffff
            );
            emit_writeback_instruction(
                instruction_m(MDU_MULHU, 5'd7, 5'd1, 5'd2),
                5'd7,
                32'h7fff_ffff
            );
            emit_no_write_instruction(
                instruction_m(MDU_MUL, 5'd0, 5'd3, 5'd3)
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd9, 5'd0, 32'd0),
                5'd9,
                32'd0
            );

            expected_mdu_request_count = 5;
            expected_mdu_response_count = 5;
            minimum_ex_multicycle_wait_count = 160;

            release_reset();
            wait_for_completion();
            check_condition(
                dut.mdu_idle,
                "multiply sequence did not leave the MDU idle"
            );
            end_scenario();
        end
    endtask

    task automatic scenario_rv32m_divide_variants;
        begin
            begin_scenario("rv32m_divide_variants");

            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd1,
                    5'd0,
                    32'hffff_ffec
                ),
                5'd1,
                32'hffff_ffec
            );
            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd2,
                    5'd0,
                    32'd6
                ),
                5'd2,
                32'd6
            );
            emit_writeback_instruction(
                encoder_u(OPCODE_LUI, 5'd11, 32'h8000_0000),
                5'd11,
                32'h8000_0000
            );
            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd12,
                    5'd0,
                    32'hffff_ffff
                ),
                5'd12,
                32'hffff_ffff
            );

            emit_writeback_instruction(
                instruction_m(MDU_DIV, 5'd3, 5'd1, 5'd2),
                5'd3,
                32'hffff_fffd
            );
            emit_writeback_instruction(
                instruction_m(MDU_DIVU, 5'd4, 5'd1, 5'd2),
                5'd4,
                32'h2aaa_aaa7
            );
            emit_writeback_instruction(
                instruction_m(MDU_REM, 5'd5, 5'd1, 5'd2),
                5'd5,
                32'hffff_fffe
            );
            emit_writeback_instruction(
                instruction_m(MDU_REMU, 5'd6, 5'd1, 5'd2),
                5'd6,
                32'h0000_0002
            );

            emit_writeback_instruction(
                instruction_m(MDU_DIV, 5'd7, 5'd1, 5'd0),
                5'd7,
                32'hffff_ffff
            );
            emit_writeback_instruction(
                instruction_m(MDU_DIVU, 5'd8, 5'd1, 5'd0),
                5'd8,
                32'hffff_ffff
            );
            emit_writeback_instruction(
                instruction_m(MDU_REM, 5'd9, 5'd1, 5'd0),
                5'd9,
                32'hffff_ffec
            );
            emit_writeback_instruction(
                instruction_m(MDU_REMU, 5'd10, 5'd1, 5'd0),
                5'd10,
                32'hffff_ffec
            );

            emit_writeback_instruction(
                instruction_m(MDU_DIV, 5'd13, 5'd11, 5'd12),
                5'd13,
                32'h8000_0000
            );
            emit_writeback_instruction(
                instruction_m(MDU_REM, 5'd14, 5'd11, 5'd12),
                5'd14,
                32'h0000_0000
            );
            emit_writeback_instruction(
                instruction_m(MDU_DIVU, 5'd15, 5'd11, 5'd12),
                5'd15,
                32'h0000_0000
            );
            emit_writeback_instruction(
                instruction_m(MDU_REMU, 5'd16, 5'd11, 5'd12),
                5'd16,
                32'h8000_0000
            );

            expected_mdu_request_count = 12;
            expected_mdu_response_count = 12;
            minimum_ex_multicycle_wait_count = 384;

            release_reset();
            wait_for_completion();
            check_condition(
                dut.mdu_idle,
                "divide sequence did not leave the MDU idle"
            );
            end_scenario();
        end
    endtask

    task automatic scenario_rv32m_forwarding_and_consumers;
        logic [31:0] poison_store;
        begin
            begin_scenario("rv32m_forwarding_consumers");
            u_dmem.write_word(32'h0000_0100, 32'd11);

            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd10,
                    5'd0,
                    32'h0000_0100
                ),
                5'd10,
                32'h0000_0100
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd1, 5'd0, 32'd7),
                5'd1,
                32'd7
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd2, 5'd0, 32'd9),
                5'd2,
                32'd9
            );

            emit_writeback_instruction(
                instruction_m(MDU_MUL, 5'd3, 5'd1, 5'd2),
                5'd3,
                32'd63
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd4, 5'd3, 32'd1),
                5'd4,
                32'd64
            );

            emit_writeback_instruction(
                instruction_load(FUNCT3_LW, 5'd5, 5'd10, 32'd0),
                5'd5,
                32'd11
            );
            expect_dmem_request(1'b0, 32'h0000_0100, '0, '0);
            emit_writeback_instruction(
                instruction_m(MDU_MUL, 5'd6, 5'd5, 5'd1),
                5'd6,
                32'd77
            );
            emit_no_write_instruction(
                encoder_s(FUNCT3_SW, 5'd10, 5'd6, 32'd4)
            );
            expect_dmem_request(
                1'b1,
                32'h0000_0104,
                32'd77,
                4'b1111
            );

            emit_writeback_instruction(
                instruction_m(MDU_MUL, 5'd7, 5'd1, 5'd2),
                5'd7,
                32'd63
            );
            emit_no_write_instruction(
                encoder_b(FUNCT3_BEQ, 5'd7, 5'd3, 32'd8)
            );
            poison_store = encoder_s(
                FUNCT3_SW,
                5'd0,
                5'd4,
                32'h0000_0180
            );
            emit_squashed_instruction(poison_store);

            emit_writeback_instruction(
                instruction_m(MDU_MUL, 5'd8, 5'd3, 5'd1),
                5'd8,
                32'd441
            );
            emit_writeback_instruction(
                instruction_m(MDU_DIV, 5'd9, 5'd8, 5'd1),
                5'd9,
                32'd63
            );

            emit_csr_retirement(
                CSR_ADDR_MSCRATCH,
                5'd5,
                FUNCT3_CSRRWI,
                5'd0,
                32'b0
            );
            emit_csr_retirement(
                CSR_ADDR_MSCRATCH,
                5'd0,
                FUNCT3_CSRRS,
                5'd11,
                32'd5
            );
            emit_writeback_instruction(
                instruction_m(MDU_MUL, 5'd12, 5'd11, 5'd1),
                5'd12,
                32'd35
            );
            emit_csr_retirement(
                CSR_ADDR_MSCRATCH,
                5'd12,
                FUNCT3_CSRRS,
                5'd0,
                32'd5
            );
            emit_csr_retirement(
                CSR_ADDR_MSCRATCH,
                5'd0,
                FUNCT3_CSRRS,
                5'd13,
                32'd39
            );

            expected_late_result_hazard_count = 2;
            expected_redirect_count = 1;
            expected_mdu_request_count = 6;
            expected_mdu_response_count = 6;
            minimum_ex_multicycle_wait_count = 192;

            release_reset();
            wait_for_completion();
            check_condition(
                u_dmem.read_word(32'h0000_0104) == 32'd77,
                "M-to-store forwarding wrote the wrong value"
            );
            check_condition(
                u_dmem.read_word(32'h0000_0180) == 32'b0,
                "M-to-branch redirect did not squash the poison store"
            );
            check_condition(
                dut.u_csr_trap.mscratch_q == 32'd39,
                "M-to-CSR forwarding wrote the wrong mscratch value"
            );
            check_condition(
                dut.mdu_idle,
                "forwarding sequence did not leave the MDU idle"
            );
            end_scenario();
        end
    endtask

    task automatic scenario_rv32m_load_wait_response_hold;
        logic [31:0] held_result;
        begin
            begin_scenario("rv32m_load_wait_rsp_hold");
            dmem_response_enable = 1'b0;
            u_dmem.write_word(32'h0000_0100, 32'hdead_beef);

            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd10,
                    5'd0,
                    32'h0000_0100
                ),
                5'd10,
                32'h0000_0100
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd1, 5'd0, 32'd7),
                5'd1,
                32'd7
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd2, 5'd0, 32'd9),
                5'd2,
                32'd9
            );
            emit_writeback_instruction(
                instruction_load(FUNCT3_LW, 5'd3, 5'd10, 32'd0),
                5'd3,
                32'hdead_beef
            );
            expect_dmem_request(1'b0, 32'h0000_0100, '0, '0);
            emit_writeback_instruction(
                instruction_m(MDU_MUL, 5'd4, 5'd1, 5'd2),
                5'd4,
                32'd63
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd5, 5'd4, 32'd1),
                5'd5,
                32'd64
            );

            expected_mdu_request_count = 1;
            expected_mdu_response_count = 1;
            minimum_ex_multicycle_wait_count = 32;
            minimum_mem_response_wait_count = 3;

            release_reset();
            while (
                !(dut.mem_response_wait && dut.mdu_rsp_valid) &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(posedge clk);
                #1;
            end
            check_condition(
                dut.mem_response_wait && dut.mdu_rsp_valid,
                "load wait did not overlap a completed MDU response"
            );
            held_result = dut.mdu_rsp_result;
            check_condition(
                (held_result == 32'd63) &&
                !dut.mdu_rsp_ready &&
                !dut.ex_multicycle_wait &&
                (observed_mdu_request_count == 1) &&
                (observed_mdu_response_count == 0),
                "completed MDU result was not blocked behind the load"
            );

            repeat (3) begin
                @(posedge clk);
                #1;
                check_condition(
                    dut.mdu_rsp_valid &&
                    !dut.mdu_rsp_ready &&
                    (dut.mdu_rsp_result === held_result) &&
                    (observed_mdu_response_count == 0),
                    "MDU response changed while the older load was waiting"
                );
            end

            @(negedge clk);
            dmem_response_enable = 1'b1;

            wait_for_completion();
            check_condition(
                dut.mdu_idle,
                "load release did not return the MDU to idle"
            );
            end_scenario();
        end
    endtask

    task automatic scenario_rv32m_store_wait_response_hold;
        logic [31:0] held_result;
        begin
            begin_scenario("rv32m_store_wait_rsp_hold");
            dmem_response_enable = 1'b0;

            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd10,
                    5'd0,
                    32'h0000_0100
                ),
                5'd10,
                32'h0000_0100
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd1, 5'd0, 32'h55),
                5'd1,
                32'h0000_0055
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd2, 5'd0, 32'd8),
                5'd2,
                32'd8
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd3, 5'd0, 32'd9),
                5'd3,
                32'd9
            );
            emit_no_write_instruction(
                encoder_s(FUNCT3_SW, 5'd10, 5'd1, 32'd0)
            );
            expect_dmem_request(
                1'b1,
                32'h0000_0100,
                32'h0000_0055,
                4'b1111
            );
            emit_writeback_instruction(
                instruction_m(MDU_MUL, 5'd4, 5'd2, 5'd3),
                5'd4,
                32'd72
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd5, 5'd4, 32'd1),
                5'd5,
                32'd73
            );

            expected_mdu_request_count = 1;
            expected_mdu_response_count = 1;
            minimum_ex_multicycle_wait_count = 32;
            minimum_mem_response_wait_count = 3;

            release_reset();
            while (
                !(dut.mem_response_wait && dut.mdu_rsp_valid) &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(posedge clk);
                #1;
            end
            check_condition(
                dut.mem_response_wait && dut.mdu_rsp_valid,
                "store wait did not overlap a completed MDU response"
            );
            held_result = dut.mdu_rsp_result;
            check_condition(
                (held_result == 32'd72) &&
                !dut.mdu_rsp_ready &&
                !dut.ex_multicycle_wait &&
                (observed_mdu_request_count == 1) &&
                (observed_mdu_response_count == 0),
                "completed MDU result was not blocked behind the store"
            );

            repeat (3) begin
                @(posedge clk);
                #1;
                check_condition(
                    dut.mdu_rsp_valid &&
                    !dut.mdu_rsp_ready &&
                    (dut.mdu_rsp_result === held_result) &&
                    (observed_mdu_response_count == 0),
                    "MDU response changed while the older store was waiting"
                );
            end

            @(negedge clk);
            dmem_response_enable = 1'b1;

            wait_for_completion();
            check_condition(
                (u_dmem.read_word(32'h0000_0100) == 32'h0000_0055) &&
                dut.mdu_idle,
                "store release lost the store or left the MDU busy"
            );
            end_scenario();
        end
    endtask

    task automatic scenario_rv32m_trap_kills_response;
        logic [31:0] fault_pc;
        logic [31:0] faulting_load;
        logic [31:0] younger_mul;
        logic [31:0] held_result;
        begin
            begin_scenario("rv32m_trap_kills_response");
            dmem_response_enable = 1'b0;

            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd1, 5'd0, 32'd7),
                5'd1,
                32'd7
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd2, 5'd0, 32'd9),
                5'd2,
                32'd9
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd4, 5'd0, 32'd0),
                5'd4,
                32'd0
            );
            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd10,
                    5'd0,
                    32'h0000_0400
                ),
                5'd10,
                32'h0000_0400
            );

            fault_pc = program_pc;
            faulting_load = instruction_load(
                FUNCT3_LW,
                5'd3,
                5'd10,
                32'd0
            );
            u_imem.write_word(fault_pc, faulting_load);
            expect_dmem_request(1'b0, 32'h0000_0400, '0, '0);
            expect_trap(
                fault_pc,
                EXCEPTION_CAUSE_LOAD_ACCESS_FAULT,
                32'h0000_0400
            );
            program_pc = program_pc + 32'd4;

            younger_mul = instruction_m(MDU_MUL, 5'd4, 5'd1, 5'd2);
            emit_squashed_instruction(younger_mul);
            install_trap_handler(5'd31, 32'h0000_0033);

            expected_mdu_request_count = 1;
            expected_mdu_response_count = 0;
            minimum_ex_multicycle_wait_count = 32;
            minimum_mem_response_wait_count = 3;

            release_reset();
            while (
                !(dut.mem_response_wait && dut.mdu_rsp_valid) &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(posedge clk);
                #1;
            end
            check_condition(
                dut.mem_response_wait && dut.mdu_rsp_valid,
                "faulting load did not hold a completed younger M result"
            );
            held_result = dut.mdu_rsp_result;
            check_condition(
                (held_result == 32'd63) &&
                !dut.mdu_rsp_ready &&
                (observed_mdu_request_count == 1) &&
                (observed_mdu_response_count == 0),
                "younger M result was not pending before the trap"
            );

            @(negedge clk);
            dmem_response_enable = 1'b1;
            #1;
            check_condition(
                dut.trap_take &&
                dut.mdu_kill &&
                !dut.mdu_rsp_valid &&
                !dut.mdu_rsp_ready &&
                (dut.mdu_rsp_result === held_result),
                "trap did not kill the pending younger MDU response"
            );

            wait_for_completion();
            check_condition(
                (dut.u_idu.u_regfile.registers[4] == 32'b0) &&
                (observed_mdu_response_count == 0) &&
                dut.mdu_idle,
                "trap-killed M instruction produced a late architectural result"
            );
            end_scenario();
        end
    endtask

    task automatic scenario_rv32m_mret_kills_request;
        logic [31:0] handler_write_mepc;
        logic [31:0] younger_mul;
        logic [31:0] resume_instruction;
        begin
            begin_scenario("rv32m_mret_kills_request");

            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd1, 5'd0, 32'd7),
                5'd1,
                32'd7
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd2, 5'd0, 32'd9),
                5'd2,
                32'd9
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd4, 5'd0, 32'd0),
                5'd4,
                32'd0
            );
            u_imem.write_word(program_pc, INSTRUCTION_ECALL);
            expect_trap(
                program_pc,
                EXCEPTION_CAUSE_ENVIRONMENT_CALL_M_MODE,
                32'b0
            );
            program_pc = program_pc + 32'd4;
            emit_squashed_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd30, 5'd0, 32'd30)
            );

            program_pc = 32'h0000_001c;
            resume_instruction = instruction_op_imm(
                FUNCT3_ADD_SUB,
                5'd5,
                5'd0,
                32'd5
            );
            u_imem.write_word(program_pc, resume_instruction);

            handler_write_mepc = instruction_csr(
                CSR_ADDR_MEPC,
                5'd28,
                FUNCT3_CSRRWI,
                5'd0
            );
            u_imem.write_word(TRAP_VECTOR, handler_write_mepc);
            expect_retirement(
                TRAP_VECTOR,
                handler_write_mepc,
                1'b0,
                5'd0,
                32'b0
            );
            u_imem.write_word(TRAP_VECTOR + 32'd4, INSTRUCTION_MRET);
            expect_retirement(
                TRAP_VECTOR + 32'd4,
                INSTRUCTION_MRET,
                1'b0,
                5'd0,
                32'b0
            );
            expect_retirement(
                32'h0000_001c,
                resume_instruction,
                1'b1,
                5'd5,
                32'd5
            );
            younger_mul = instruction_m(MDU_MUL, 5'd4, 5'd1, 5'd2);
            u_imem.write_word(TRAP_VECTOR + 32'd8, younger_mul);
            expected_trap_vector_fetch_count = 1;

            expected_mdu_request_count = 0;
            expected_mdu_response_count = 0;

            release_reset();
            while (
                !(
                    dut.mret_commit &&
                    dut.id_ex_q.valid &&
                    dut.id_ex_q.mdu_ctrl.valid
                ) &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(negedge clk);
                #1;
            end
            check_condition(
                dut.mret_commit &&
                dut.id_ex_q.mdu_ctrl.valid &&
                (dut.id_ex_q.instruction == younger_mul) &&
                dut.mdu_kill &&
                !dut.mdu_req_valid &&
                !dut.mdu_rsp_valid &&
                dut.mdu_idle,
                "MRET did not suppress the aligned younger MDU request"
            );

            wait_for_completion();
            check_condition(
                (dut.u_idu.u_regfile.registers[4] == 32'b0) &&
                (dut.u_idu.u_regfile.registers[5] == 32'd5) &&
                dut.mdu_idle,
                "MRET-killed M instruction escaped or return target failed"
            );
            end_scenario();
        end
    endtask

    task automatic run_interrupt_arbitration_case(
        input string       name,
        input logic [31:0] mie_value,
        input logic        global_enable,
        input logic        software_pending,
        input logic        timer_pending,
        input logic        external_pending,
        input logic        expected_take,
        input logic [31:0] expected_cause
    );
        logic [31:0] boundary_pc;
        logic [31:0] boundary_instruction;
        logic [31:0] next_instruction;
        begin
            begin_scenario(name);
            emit_interrupt_configuration(mie_value, global_enable);

            boundary_pc = program_pc;
            boundary_instruction = instruction_op_imm(
                FUNCT3_ADD_SUB,
                5'd1,
                5'd0,
                32'd1
            );
            emit_writeback_instruction(
                boundary_instruction,
                5'd1,
                32'd1
            );

            next_instruction = instruction_op_imm(
                FUNCT3_ADD_SUB,
                5'd2,
                5'd0,
                32'd2
            );
            if (expected_take) begin
                emit_squashed_instruction(next_instruction);
                expect_trap(
                    boundary_pc + 32'd4,
                    expected_cause,
                    32'b0
                );
                install_interrupt_handler_no_return(
                    TRAP_VECTOR,
                    32'h31,
                    32'h30
                );
                expected_interrupt_take_count = 1;
                expected_post_interrupt_take_count = 1;
            end else begin
                emit_writeback_instruction(
                    next_instruction,
                    5'd2,
                    32'd2
                );
            end

            release_reset();
            wait_for_committable_mem_pc(boundary_pc);
            drive_irq_levels(
                software_pending,
                timer_pending,
                external_pending
            );
            #1;

            check_condition(
                dut.post_commit_interrupt_take === expected_take,
                "interrupt arbitration produced the wrong take decision"
            );
            if (expected_take) begin
                check_condition(
                    dut.interrupt_take &&
                    (dut.u_csr_trap.selected_interrupt_cause ==
                        expected_cause) &&
                    (dut.boundary_resume_pc == boundary_pc + 32'd4) &&
                    (dut.qualified_redirect.target == TRAP_VECTOR),
                    "interrupt arbitration selected the wrong cause or payload"
                );
            end

            wait_for_completion();
            check_condition(
                observed_interrupt_take_count ==
                    (expected_take ? 1 : 0),
                "level-held IRQ caused a missing or repeated interrupt"
            );
            if (expected_take) begin
                check_condition(
                    (dut.u_csr_trap.mepc_q == boundary_pc + 32'd4) &&
                    (dut.u_csr_trap.mcause_q == expected_cause) &&
                    (dut.u_csr_trap.mtval_q == 32'b0) &&
                    !dut.u_csr_trap.mstatus_mie_q &&
                    dut.u_csr_trap.mstatus_mpie_q,
                    "interrupt entry CSR state is incorrect"
                );
            end

            @(negedge clk);
            drive_irq_levels(1'b0, 1'b0, 1'b0);
            end_scenario();
        end
    endtask

    task automatic run_interrupt_control_resume_case(
        input string       name,
        input int unsigned control_kind
    );
        logic [31:0] boundary_pc;
        logic [31:0] boundary_instruction;
        logic [31:0] expected_resume_pc;
        logic        expected_rd_we;
        logic [4:0]  expected_rd_addr;
        logic [31:0] expected_rd_data;
        begin
            begin_scenario(name);
            emit_interrupt_configuration(32'h0000_0800, 1'b1);
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd1, 5'd0, 32'd1),
                5'd1,
                32'd1
            );
            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd2,
                    5'd0,
                    32'h0000_0180
                ),
                5'd2,
                32'h0000_0180
            );

            boundary_pc = program_pc;
            expected_rd_we = 1'b0;
            expected_rd_addr = 5'b0;
            expected_rd_data = 32'b0;
            case (control_kind)
                0: begin
                    boundary_instruction = encoder_b(
                        FUNCT3_BEQ,
                        5'd1,
                        5'd1,
                        32'd8
                    );
                    expected_resume_pc = boundary_pc + 32'd8;
                    expected_redirect_count = 1;
                end
                1: begin
                    boundary_instruction = encoder_b(
                        FUNCT3_BEQ,
                        5'd1,
                        5'd0,
                        32'd8
                    );
                    expected_resume_pc = boundary_pc + 32'd4;
                end
                2: begin
                    boundary_instruction = encoder_j(5'd5, 32'd8);
                    expected_resume_pc = boundary_pc + 32'd8;
                    expected_rd_we = 1'b1;
                    expected_rd_addr = 5'd5;
                    expected_rd_data = boundary_pc + 32'd4;
                    expected_redirect_count = 1;
                end
                default: begin
                    boundary_instruction = instruction_jalr(
                        5'd5,
                        5'd2,
                        32'd0
                    );
                    expected_resume_pc = 32'h0000_0180;
                    expected_rd_we = 1'b1;
                    expected_rd_addr = 5'd5;
                    expected_rd_data = boundary_pc + 32'd4;
                    expected_redirect_count = 1;
                end
            endcase

            u_imem.write_word(boundary_pc, boundary_instruction);
            expect_retirement(
                boundary_pc,
                boundary_instruction,
                expected_rd_we,
                expected_rd_addr,
                expected_rd_data
            );
            program_pc = program_pc + 32'd4;
            u_imem.write_word(
                boundary_pc + 32'd4,
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd29,
                    5'd0,
                    32'h29
                )
            );

            expect_trap(
                expected_resume_pc,
                INTERRUPT_CAUSE_MACHINE_EXTERNAL,
                32'b0
            );
            install_interrupt_handler_no_return(
                TRAP_VECTOR,
                32'h41 + control_kind,
                32'h51 + control_kind
            );
            expected_interrupt_take_count = 1;
            expected_post_interrupt_take_count = 1;

            release_reset();
            wait_for_committable_mem_pc(boundary_pc);
            drive_irq_levels(1'b0, 1'b0, 1'b1);
            #1;
            check_condition(
                dut.post_commit_interrupt_take &&
                (dut.ex_mem_q.architectural_next_pc ==
                    expected_resume_pc) &&
                (dut.boundary_resume_pc == expected_resume_pc),
                "control-flow interrupt saved the wrong architectural successor"
            );

            @(posedge clk);
            #1;
            @(negedge clk);
            drive_irq_levels(1'b0, 1'b0, 1'b0);
            wait_for_completion();
            check_condition(
                (dut.u_csr_trap.mepc_q == expected_resume_pc) &&
                (dut.u_csr_trap.mcause_q ==
                    INTERRUPT_CAUSE_MACHINE_EXTERNAL),
                "control-flow interrupt CSR payload is incorrect"
            );
            end_scenario();
        end
    endtask

    task automatic scenario_interrupt_alu_mret_counter;
        logic [31:0] boundary_pc;
        logic [31:0] boundary_instruction;
        logic [31:0] resume_instruction;
        begin
            begin_scenario("irq_alu_mret_counter_order");
            emit_interrupt_configuration(32'h0000_0800, 1'b1);
            emit_csr_retirement(
                CSR_ADDR_MINSTRET,
                5'd10,
                FUNCT3_CSRRWI,
                5'd0,
                32'd3
            );

            boundary_pc = program_pc;
            boundary_instruction = instruction_op_imm(
                FUNCT3_ADD_SUB,
                5'd1,
                5'd0,
                32'h5a
            );
            emit_writeback_instruction(
                boundary_instruction,
                5'd1,
                32'h5a
            );

            resume_instruction = instruction_op_imm(
                FUNCT3_ADD_SUB,
                5'd2,
                5'd0,
                32'h2a
            );
            u_imem.write_word(boundary_pc + 32'd4, resume_instruction);

            expect_trap(
                boundary_pc + 32'd4,
                INTERRUPT_CAUSE_MACHINE_EXTERNAL,
                32'b0
            );
            install_interrupt_handler_mret(TRAP_VECTOR, 32'h6a);
            expect_retirement(
                boundary_pc + 32'd4,
                resume_instruction,
                1'b1,
                5'd2,
                32'h2a
            );
            expected_interrupt_take_count = 1;
            expected_post_interrupt_take_count = 1;

            release_reset();
            wait_for_committable_mem_pc(boundary_pc);
            drive_irq_levels(1'b0, 1'b0, 1'b1);
            #1;
            check_condition(
                dut.post_commit_interrupt_take &&
                dut.commit_valid &&
                (dut.boundary_resume_pc == boundary_pc + 32'd4),
                "ALU interrupt boundary did not commit before entry"
            );

            @(posedge clk);
            #1;
            check_condition(
                retire_valid &&
                trap_valid &&
                (retire_pc == boundary_pc) &&
                (retire_instr == boundary_instruction) &&
                (trap_pc == boundary_pc + 32'd4) &&
                (dut.u_csr_trap.minstret_q == 64'd11),
                "post-interrupt retire/trap ordering or minstret boundary is wrong"
            );

            @(negedge clk);
            drive_irq_levels(1'b0, 1'b0, 1'b0);
            wait_for_completion();
            check_condition(
                (dut.u_idu.u_regfile.registers[2] == 32'h2a) &&
                dut.u_csr_trap.mstatus_mie_q &&
                (dut.u_csr_trap.minstret_q >= 64'd14),
                "MRET resume or interrupt minstret accounting is wrong"
            );
            end_scenario();
        end
    endtask

    task automatic run_interrupt_csr_preview_case(
        input string       name,
        input int unsigned preview_kind
    );
        logic [31:0] boundary_pc;
        logic [31:0] expected_vector;
        begin
            begin_scenario(name);
            expected_vector = TRAP_VECTOR;

            case (preview_kind)
                0: begin
                    emit_interrupt_configuration(32'b0, 1'b1);
                    emit_writeback_instruction(
                        instruction_op_imm(
                            FUNCT3_ADD_SUB,
                            5'd21,
                            5'd0,
                            32'h0000_0800
                        ),
                        5'd21,
                        32'hffff_f800
                    );
                    boundary_pc = program_pc;
                    emit_csr_retirement(
                        CSR_ADDR_MIE,
                        5'd21,
                        FUNCT3_CSRRW,
                        5'd0,
                        32'b0
                    );
                end
                1: begin
                    emit_interrupt_configuration(32'h0000_0800, 1'b0);
                    boundary_pc = program_pc;
                    emit_csr_retirement(
                        CSR_ADDR_MSTATUS,
                        5'd8,
                        FUNCT3_CSRRWI,
                        5'd0,
                        32'h0000_1800
                    );
                end
                default: begin
                    emit_interrupt_configuration(32'h0000_0800, 1'b1);
                    emit_writeback_instruction(
                        instruction_op_imm(
                            FUNCT3_ADD_SUB,
                            5'd21,
                            5'd0,
                            32'h0000_0240
                        ),
                        5'd21,
                        32'h0000_0240
                    );
                    boundary_pc = program_pc;
                    emit_csr_retirement(
                        CSR_ADDR_MTVEC,
                        5'd21,
                        FUNCT3_CSRRW,
                        5'd0,
                        TRAP_VECTOR
                    );
                    expected_vector = 32'h0000_0240;
                end
            endcase

            u_imem.write_word(
                boundary_pc + 32'd4,
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd29,
                    5'd0,
                    32'h29
                )
            );
            expect_trap(
                boundary_pc + 32'd4,
                INTERRUPT_CAUSE_MACHINE_EXTERNAL,
                32'b0
            );
            install_interrupt_handler_no_return(
                expected_vector,
                32'h70 + preview_kind,
                32'h78 + preview_kind
            );
            expected_interrupt_take_count = 1;
            expected_post_interrupt_take_count = 1;

            release_reset();
            wait_for_committable_mem_pc(boundary_pc);
            drive_irq_levels(1'b0, 1'b0, 1'b1);
            #1;
            check_condition(
                dut.post_commit_interrupt_take &&
                (dut.interrupt_redirect.target == expected_vector),
                "CSR post-write preview did not take the pending interrupt"
            );
            case (preview_kind)
                0: check_condition(
                    dut.u_csr_trap.effective_mie_meie,
                    "mie post-write preview did not enable MEIE"
                );
                1: check_condition(
                    dut.u_csr_trap.effective_mstatus_mie,
                    "mstatus post-write preview did not enable global MIE"
                );
                default: check_condition(
                    dut.u_csr_trap.effective_mtvec == expected_vector,
                    "mtvec post-write preview did not select the new vector"
                );
            endcase

            @(posedge clk);
            #1;
            @(negedge clk);
            drive_irq_levels(1'b0, 1'b0, 1'b0);
            wait_for_completion();
            check_condition(
                dut.u_csr_trap.mie_meie_q &&
                !dut.u_csr_trap.mstatus_mie_q &&
                dut.u_csr_trap.mstatus_mpie_q &&
                (dut.u_csr_trap.mtvec_q == expected_vector),
                "CSR preview value was not preserved through interrupt entry"
            );
            end_scenario();
        end
    endtask

    task automatic scenario_interrupt_mret_immediate_reentry;
        logic [31:0] boundary_pc;
        logic [31:0] return_instruction;
        begin
            begin_scenario("irq_mret_immediate_reentry");
            emit_interrupt_configuration(32'h0000_0800, 1'b0);
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd5, 5'd0, 32'd0),
                5'd5,
                32'd0
            );
            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd21,
                    5'd0,
                    32'h0000_0180
                ),
                5'd21,
                32'h0000_0180
            );
            emit_csr_retirement(
                CSR_ADDR_MEPC,
                5'd21,
                FUNCT3_CSRRW,
                5'd0,
                32'b0
            );
            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd22,
                    5'd0,
                    32'h0000_0080
                ),
                5'd22,
                32'h0000_0080
            );
            emit_csr_retirement(
                CSR_ADDR_MSTATUS,
                5'd22,
                FUNCT3_CSRRW,
                5'd0,
                32'h0000_1800
            );

            boundary_pc = program_pc;
            emit_no_write_instruction(INSTRUCTION_MRET);
            return_instruction = instruction_op_imm(
                FUNCT3_ADD_SUB,
                5'd5,
                5'd0,
                32'h55
            );
            u_imem.write_word(32'h0000_0180, return_instruction);
            expect_trap(
                32'h0000_0180,
                INTERRUPT_CAUSE_MACHINE_EXTERNAL,
                32'b0
            );
            install_interrupt_handler_no_return(
                TRAP_VECTOR,
                32'h61,
                32'h62
            );
            expected_interrupt_take_count = 1;
            expected_post_interrupt_take_count = 1;

            release_reset();
            wait_for_committable_mem_pc(boundary_pc);
            drive_irq_levels(1'b0, 1'b0, 1'b1);
            #1;
            check_condition(
                dut.mret_commit &&
                dut.post_commit_interrupt_take &&
                dut.u_csr_trap.effective_mstatus_mie &&
                (dut.boundary_resume_pc == 32'h0000_0180) &&
                (dut.qualified_redirect == dut.interrupt_redirect) &&
                (dut.qualified_redirect != dut.mret_redirect),
                "pending IRQ did not immediately re-enter after MRET"
            );

            @(posedge clk);
            #1;
            @(negedge clk);
            drive_irq_levels(1'b0, 1'b0, 1'b0);
            wait_for_completion();
            check_condition(
                (dut.u_idu.u_regfile.registers[5] == 32'b0) &&
                (dut.u_csr_trap.mepc_q == 32'h0000_0180) &&
                !dut.u_csr_trap.mstatus_mie_q &&
                dut.u_csr_trap.mstatus_mpie_q,
                "MRET immediate re-entry executed the return path or saved bad state"
            );
            end_scenario();
        end
    endtask

    task automatic scenario_interrupt_sync_fault_priority;
        logic [31:0] fault_pc;
        begin
            begin_scenario("irq_sync_fault_priority");
            dmem_response_enable = 1'b0;
            emit_interrupt_configuration(32'h0000_0888, 1'b1);
            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd10,
                    5'd0,
                    32'h0000_0400
                ),
                5'd10,
                32'h0000_0400
            );
            fault_pc = program_pc;
            u_imem.write_word(
                fault_pc,
                instruction_load(FUNCT3_LW, 5'd3, 5'd10, 32'd0)
            );
            expect_dmem_request(1'b0, 32'h0000_0400, 32'b0, 4'b0);
            expect_trap(
                fault_pc,
                EXCEPTION_CAUSE_LOAD_ACCESS_FAULT,
                32'h0000_0400
            );
            program_pc = program_pc + 32'd4;
            emit_squashed_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd29, 5'd0, 32'h29)
            );
            install_trap_handler(5'd31, 32'h7f);

            minimum_mem_response_wait_count = 2;
            release_reset();
            while (
                !dut.mem_response_wait &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(negedge clk);
                #1;
            end
            drive_irq_levels(1'b1, 1'b1, 1'b1);
            repeat (2) begin
                @(posedge clk);
                #1;
                check_condition(
                    dut.mem_response_wait &&
                    !dut.trap_take &&
                    !dut.interrupt_take,
                    "IRQ or synchronous fault escaped before DMem response"
                );
            end

            @(negedge clk);
            dmem_response_enable = 1'b1;
            #1;
            check_condition(
                dut.trap_take &&
                !dut.interrupt_take &&
                (dut.qualified_redirect == dut.trap_redirect),
                "pending interrupt beat the synchronous DMem fault"
            );

            wait_for_completion();
            check_condition(
                (observed_interrupt_take_count == 0) &&
                (dut.u_csr_trap.mcause_q ==
                    EXCEPTION_CAUSE_LOAD_ACCESS_FAULT),
                "synchronous fault priority produced interrupt state"
            );
            @(negedge clk);
            drive_irq_levels(1'b0, 1'b0, 1'b0);
            end_scenario();
        end
    endtask

    task automatic scenario_interrupt_load_wait_kills_store;
        logic [31:0] load_pc;
        logic [31:0] younger_store;
        begin
            begin_scenario("irq_load_wait_kills_store");
            dmem_response_enable = 1'b0;
            u_dmem.write_word(32'h0000_0100, 32'hdead_beef);
            emit_interrupt_configuration(32'h0000_0800, 1'b1);
            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd10,
                    5'd0,
                    32'h0000_0100
                ),
                5'd10,
                32'h0000_0100
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd1, 5'd0, 32'h5a),
                5'd1,
                32'h5a
            );

            load_pc = program_pc;
            emit_writeback_instruction(
                instruction_load(FUNCT3_LW, 5'd3, 5'd10, 32'd0),
                5'd3,
                32'hdead_beef
            );
            expect_dmem_request(1'b0, 32'h0000_0100, 32'b0, 4'b0);
            younger_store = encoder_s(
                FUNCT3_SW,
                5'd10,
                5'd1,
                32'd4
            );
            emit_squashed_instruction(younger_store);
            expect_trap(
                load_pc + 32'd4,
                INTERRUPT_CAUSE_MACHINE_EXTERNAL,
                32'b0
            );
            install_interrupt_handler_no_return(
                TRAP_VECTOR,
                32'h51,
                32'h52
            );
            expected_interrupt_take_count = 1;
            expected_post_interrupt_take_count = 1;
            minimum_mem_response_wait_count = 3;

            release_reset();
            while (
                !dut.mem_response_wait &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(negedge clk);
                #1;
            end
            drive_irq_levels(1'b0, 1'b0, 1'b1);
            repeat (3) begin
                @(posedge clk);
                #1;
                check_condition(
                    dut.mem_response_wait &&
                    !dut.interrupt_take &&
                    (observed_interrupt_take_count == 0),
                    "load wait allowed an early interrupt"
                );
            end

            @(negedge clk);
            dmem_response_enable = 1'b1;
            #1;
            check_condition(
                dut.post_commit_interrupt_take &&
                dut.commit_valid &&
                dut.ex_mem_active_candidate.valid &&
                (dut.ex_mem_active_candidate.instruction == younger_store) &&
                !dmem_req_valid &&
                dut.ex_request_block,
                "load completion interrupt did not block the younger store"
            );

            @(posedge clk);
            #1;
            @(negedge clk);
            drive_irq_levels(1'b0, 1'b0, 1'b0);
            wait_for_completion();
            check_condition(
                (observed_dmem_request_count == 1) &&
                (u_dmem.read_word(32'h0000_0104) == 32'b0) &&
                !dut.u_lsu.outstanding_q,
                "interrupt repeated the load or allowed the younger store"
            );
            end_scenario();
        end
    endtask

    task automatic scenario_interrupt_store_wait_kills_branch;
        logic [31:0] store_pc;
        logic [31:0] younger_branch;
        begin
            begin_scenario("irq_store_wait_kills_branch");
            dmem_response_enable = 1'b0;
            emit_interrupt_configuration(32'h0000_0800, 1'b1);
            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd10,
                    5'd0,
                    32'h0000_0100
                ),
                5'd10,
                32'h0000_0100
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd1, 5'd0, 32'h5b),
                5'd1,
                32'h5b
            );

            store_pc = program_pc;
            emit_no_write_instruction(
                encoder_s(FUNCT3_SW, 5'd10, 5'd1, 32'd0)
            );
            expect_dmem_request(
                1'b1,
                32'h0000_0100,
                32'h0000_005b,
                4'b1111
            );
            younger_branch = encoder_b(
                FUNCT3_BNE,
                5'd1,
                5'd0,
                32'd8
            );
            emit_squashed_instruction(younger_branch);
            emit_squashed_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd29, 5'd0, 32'h29)
            );
            expect_trap(
                store_pc + 32'd4,
                INTERRUPT_CAUSE_MACHINE_EXTERNAL,
                32'b0
            );
            install_interrupt_handler_no_return(
                TRAP_VECTOR,
                32'h53,
                32'h54
            );
            expected_interrupt_take_count = 1;
            expected_post_interrupt_take_count = 1;
            minimum_mem_response_wait_count = 3;

            release_reset();
            while (
                !(dut.mem_response_wait && dut.raw_redirect.valid) &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(negedge clk);
                #1;
            end
            drive_irq_levels(1'b0, 1'b0, 1'b1);
            repeat (3) begin
                @(posedge clk);
                #1;
                check_condition(
                    dut.mem_response_wait &&
                    dut.raw_redirect.valid &&
                    !dut.redirect_commit &&
                    !dut.interrupt_take,
                    "store wait released the branch or interrupt too early"
                );
            end

            @(negedge clk);
            dmem_response_enable = 1'b1;
            #1;
            check_condition(
                dut.post_commit_interrupt_take &&
                dut.raw_redirect.valid &&
                !dut.redirect_commit &&
                (dut.qualified_redirect == dut.interrupt_redirect),
                "store completion interrupt did not beat the younger branch"
            );

            @(posedge clk);
            #1;
            @(negedge clk);
            drive_irq_levels(1'b0, 1'b0, 1'b0);
            wait_for_completion();
            check_condition(
                (observed_dmem_request_count == 1) &&
                (u_dmem.read_word(32'h0000_0100) == 32'h0000_005b) &&
                (redirect_count == 0),
                "store was repeated or the younger branch committed"
            );
            end_scenario();
        end
    endtask

    task automatic scenario_interrupt_load_wait_kills_mdu_response;
        logic [31:0] load_pc;
        logic [31:0] younger_mul;
        logic [31:0] held_result;
        begin
            begin_scenario("irq_load_wait_kills_mdu_rsp");
            dmem_response_enable = 1'b0;
            u_dmem.write_word(32'h0000_0100, 32'hcafe_babe);
            emit_interrupt_configuration(32'h0000_0800, 1'b1);
            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd10,
                    5'd0,
                    32'h0000_0100
                ),
                5'd10,
                32'h0000_0100
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd1, 5'd0, 32'd7),
                5'd1,
                32'd7
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd2, 5'd0, 32'd9),
                5'd2,
                32'd9
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd4, 5'd0, 32'd0),
                5'd4,
                32'd0
            );

            load_pc = program_pc;
            emit_writeback_instruction(
                instruction_load(FUNCT3_LW, 5'd3, 5'd10, 32'd0),
                5'd3,
                32'hcafe_babe
            );
            expect_dmem_request(1'b0, 32'h0000_0100, 32'b0, 4'b0);
            younger_mul = instruction_m(MDU_MUL, 5'd4, 5'd1, 5'd2);
            emit_squashed_instruction(younger_mul);
            expect_trap(
                load_pc + 32'd4,
                INTERRUPT_CAUSE_MACHINE_EXTERNAL,
                32'b0
            );
            install_interrupt_handler_no_return(
                TRAP_VECTOR,
                32'h55,
                32'h56
            );
            expected_interrupt_take_count = 1;
            expected_post_interrupt_take_count = 1;
            expected_mdu_request_count = 1;
            expected_mdu_response_count = 0;
            minimum_ex_multicycle_wait_count = 32;
            minimum_mem_response_wait_count = 3;

            release_reset();
            while (
                !dut.mem_response_wait &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(negedge clk);
                #1;
            end
            drive_irq_levels(1'b0, 1'b0, 1'b1);
            while (
                !(dut.mem_response_wait && dut.mdu_rsp_valid) &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(posedge clk);
                #1;
                check_condition(
                    !dut.interrupt_take,
                    "interrupt escaped while an older load awaited response"
                );
            end
            held_result = dut.mdu_rsp_result;
            check_condition(
                dut.mem_response_wait &&
                dut.mdu_rsp_valid &&
                !dut.mdu_rsp_ready &&
                (held_result == 32'd63),
                "younger MDU result was not held behind the load"
            );

            @(negedge clk);
            dmem_response_enable = 1'b1;
            #1;
            check_condition(
                dut.post_commit_interrupt_take &&
                dut.mdu_kill &&
                !dut.mdu_rsp_valid &&
                !dut.mdu_rsp_ready &&
                (dut.mdu_rsp_result == held_result),
                "interrupt did not kill the younger held MDU response"
            );

            @(posedge clk);
            #1;
            @(negedge clk);
            drive_irq_levels(1'b0, 1'b0, 1'b0);
            wait_for_completion();
            check_condition(
                (dut.u_idu.u_regfile.registers[4] == 32'b0) &&
                (observed_mdu_response_count == 0) &&
                dut.mdu_idle,
                "interrupt-killed MDU response became architectural"
            );
            end_scenario();
        end
    endtask

    task automatic scenario_interrupt_empty_with_ifu_pending;
        logic [31:0] final_pc;
        logic [31:0] held_fetch_pc;
        begin
            begin_scenario("irq_empty_with_ifu_pending");
            emit_interrupt_configuration(32'h0000_0800, 1'b1);
            final_pc = program_pc;
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd1, 5'd0, 32'h5c),
                5'd1,
                32'h5c
            );
            held_fetch_pc = final_pc + 32'd4;
            expect_trap(
                held_fetch_pc,
                INTERRUPT_CAUSE_MACHINE_EXTERNAL,
                32'b0
            );
            install_interrupt_handler_no_return(
                TRAP_VECTOR,
                32'h57,
                32'h58
            );
            expected_interrupt_take_count = 1;
            expected_empty_interrupt_take_count = 1;

            release_reset();
            while (
                !(
                    imem_req_valid &&
                    (imem_req_addr == held_fetch_pc)
                ) &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(negedge clk);
                #1;
            end
            imem_request_enable = 1'b0;

            while (
                !(
                    dut.pipeline_empty &&
                    dut.u_ifu.request_pending_q &&
                    (dut.u_ifu.request_pending_addr_q == held_fetch_pc)
                ) &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(negedge clk);
                #1;
            end
            check_condition(
                dut.pipeline_empty &&
                dut.u_ifu.request_pending_q &&
                (dut.resume_pc_q == held_fetch_pc),
                "pipeline did not drain with the expected IFU request pending"
            );

            drive_irq_levels(1'b0, 1'b0, 1'b1);
            #1;
            check_condition(
                dut.empty_interrupt_take &&
                !dut.post_commit_interrupt_take &&
                (dut.boundary_resume_pc == held_fetch_pc) &&
                (dut.interrupt_redirect.target == TRAP_VECTOR),
                "empty-pipeline interrupt ignored resume_pc_q or IFU pending"
            );

            @(posedge clk);
            #1;
            @(negedge clk);
            drive_irq_levels(1'b0, 1'b0, 1'b0);
            imem_request_enable = 1'b1;
            wait_for_completion();
            check_condition(
                observed_empty_interrupt_take_count == 1,
                "empty-pipeline interrupt was missing or repeated"
            );
            end_scenario();
        end
    endtask

    task automatic scenario_interrupt_reset_clears_pending;
        logic [31:0] boundary_pc;
        logic [31:0] boundary_instruction;
        begin
            begin_scenario("irq_reset_clears_pending");
            emit_interrupt_configuration(32'h0000_0800, 1'b1);
            boundary_pc = program_pc;
            boundary_instruction = instruction_op_imm(
                FUNCT3_ADD_SUB,
                5'd1,
                5'd0,
                32'h5d
            );
            u_imem.write_word(boundary_pc, boundary_instruction);
            program_pc = program_pc + 32'd4;
            expected_interrupt_take_count = 1;
            expected_post_interrupt_take_count = 1;

            release_reset();
            wait_for_committable_mem_pc(boundary_pc);
            imem_request_enable = 1'b0;
            drive_irq_levels(1'b0, 1'b0, 1'b1);
            #1;
            check_condition(
                dut.post_commit_interrupt_take,
                "reset-pending scenario did not create an interrupt take"
            );

            @(posedge clk);
            #1;
            check_condition(
                dut.u_csr_trap.interrupt_event_pending_q &&
                trap_valid &&
                retire_valid &&
                (retire_pc == boundary_pc),
                "interrupt event was not pending before reset"
            );

            @(negedge clk);
            rst = 1'b1;
            drive_irq_levels(1'b0, 1'b0, 1'b0);
            repeat (2) begin
                @(posedge clk);
                #1;
                check_condition(
                    !dut.u_csr_trap.interrupt_event_pending_q &&
                    !trap_valid &&
                    !retire_valid &&
                    !imem_req_valid &&
                    !dmem_req_valid,
                    "reset did not clear the delayed interrupt event and outputs"
                );
            end
            end_scenario();
        end
    endtask

    task automatic scenario_d5_random_backpressure;
        logic [31:0] branch_instruction;
        logic [31:0] jal_instruction;
        logic [31:0] poison_store_0;
        logic [31:0] poison_store_1;
        logic [31:0] fault_pc;
        begin
            begin_scenario("d5_random_backpressure");

            emit_writeback_instruction(
                instruction_op_imm(
                    FUNCT3_ADD_SUB,
                    5'd1,
                    5'd0,
                    32'h0000_0100
                ),
                5'd1,
                32'h0000_0100
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd2, 5'd0, 32'd7),
                5'd2,
                32'd7
            );
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd3, 5'd0, 32'd9),
                5'd3,
                32'd9
            );

            emit_no_write_instruction(
                encoder_s(FUNCT3_SW, 5'd1, 5'd2, 32'd0)
            );
            expect_dmem_request(
                1'b1,
                32'h0000_0100,
                32'd7,
                4'b1111
            );
            emit_writeback_instruction(
                instruction_load(FUNCT3_LW, 5'd4, 5'd1, 32'd0),
                5'd4,
                32'd7
            );
            expect_dmem_request(1'b0, 32'h0000_0100, 32'b0, 4'b0);
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd5, 5'd4, 32'd1),
                5'd5,
                32'd8
            );

            emit_writeback_instruction(
                instruction_m(MDU_MUL, 5'd6, 5'd2, 5'd3),
                5'd6,
                32'd63
            );
            emit_writeback_instruction(
                encoder_r(
                    FUNCT3_ADD_SUB,
                    FUNCT7_BASE,
                    5'd7,
                    5'd6,
                    5'd5
                ),
                5'd7,
                32'd71
            );
            emit_writeback_instruction(
                instruction_m(MDU_DIV, 5'd8, 5'd6, 5'd2),
                5'd8,
                32'd9
            );

            emit_no_write_instruction(
                encoder_s(FUNCT3_SW, 5'd1, 5'd8, 32'd4)
            );
            expect_dmem_request(
                1'b1,
                32'h0000_0104,
                32'd9,
                4'b1111
            );
            emit_writeback_instruction(
                instruction_load(FUNCT3_LW, 5'd9, 5'd1, 32'd4),
                5'd9,
                32'd9
            );
            expect_dmem_request(1'b0, 32'h0000_0104, 32'b0, 4'b0);

            branch_instruction = encoder_b(
                FUNCT3_BEQ,
                5'd9,
                5'd3,
                32'd8
            );
            emit_no_write_instruction(branch_instruction);
            poison_store_0 = encoder_s(
                FUNCT3_SW,
                5'd1,
                5'd3,
                32'd8
            );
            emit_squashed_instruction(poison_store_0);
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd10, 5'd0, 32'd10),
                5'd10,
                32'd10
            );

            jal_instruction = encoder_j(5'd11, 32'd8);
            emit_writeback_instruction(
                jal_instruction,
                5'd11,
                program_pc + 32'd4
            );
            poison_store_1 = encoder_s(
                FUNCT3_SW,
                5'd1,
                5'd3,
                32'd12
            );
            emit_squashed_instruction(poison_store_1);
            emit_writeback_instruction(
                instruction_op_imm(FUNCT3_ADD_SUB, 5'd12, 5'd0, 32'd12),
                5'd12,
                32'd12
            );
            emit_no_write_instruction(INSTRUCTION_WFI);

            fault_pc = program_pc;
            u_imem.write_word(fault_pc, INSTRUCTION_ECALL);
            expect_trap(
                fault_pc,
                EXCEPTION_CAUSE_ENVIRONMENT_CALL_M_MODE,
                32'b0
            );
            program_pc = program_pc + 32'd4;
            emit_squashed_instruction(
                encoder_s(FUNCT3_SW, 5'd1, 5'd3, 32'd16)
            );
            install_trap_handler(5'd31, 32'h0000_005a);

            expected_redirect_count = 2;
            expected_mdu_request_count = 2;
            expected_mdu_response_count = 2;

            d5_random_active = 1'b1;
            release_reset();
            wait_for_completion();
            wait_for_d5_quiescence();

            check_condition(
                u_dmem.read_word(32'h0000_0100) == 32'd7,
                "D5 randomized store/load word at 0x100 is incorrect"
            );
            check_condition(
                u_dmem.read_word(32'h0000_0104) == 32'd9,
                "D5 randomized MDU store/load word at 0x104 is incorrect"
            );
            check_condition(
                (u_dmem.read_word(32'h0000_0108) == 32'b0) &&
                (u_dmem.read_word(32'h0000_010c) == 32'b0) &&
                (u_dmem.read_word(32'h0000_0110) == 32'b0),
                "D5 wrong-path or post-trap store modified memory"
            );
            check_condition(
                (dut.u_idu.u_regfile.registers[7] == 32'd71) &&
                (dut.u_idu.u_regfile.registers[12] == 32'd12) &&
                (dut.u_idu.u_regfile.registers[31] == 32'h0000_005a),
                "D5 architectural register results are incorrect"
            );

            d5_coverage_bitmap = 16'b0;
            d5_coverage_bitmap[0] =
                (d5_imem_request_stall_cycles != 0);
            d5_coverage_bitmap[1] =
                (d5_imem_response_delay_cycles != 0);
            d5_coverage_bitmap[2] =
                (d5_dmem_request_stall_cycles != 0);
            d5_coverage_bitmap[3] =
                (d5_dmem_response_delay_cycles != 0);
            d5_coverage_bitmap[4] = (ex_request_wait_count != 0);
            d5_coverage_bitmap[5] = (mem_response_wait_count != 0);
            d5_coverage_bitmap[6] = (redirect_count != 0);
            d5_coverage_bitmap[7] = (ex_multicycle_wait_count != 0);
            d5_coverage_bitmap[8] = (observed_trap_count != 0);
            d5_coverage_bitmap[9] =
                (
                    d5_imem_request_forced_grants != 0 ||
                    d5_imem_response_forced_grants != 0 ||
                    d5_dmem_request_forced_grants != 0 ||
                    d5_dmem_response_forced_grants != 0
                );

            end_scenario();
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            if (scenario_active) begin
                check_condition(
                    !imem_req_valid &&
                    !imem_rsp_ready &&
                    !dmem_req_valid &&
                    !dmem_rsp_ready &&
                    !retire_valid &&
                    !trap_valid,
                    "reset did not suppress requests, responses, retirement, and trap"
                );
            end

            imem_outstanding_count = 0;
            dmem_outstanding_count = 0;

            previous_imem_request_stalled = 1'b0;
            previous_dmem_request_stalled = 1'b0;
            previous_imem_response_stalled = 1'b0;
            previous_dmem_response_stalled = 1'b0;
            pipeline_history_valid = 1'b0;
            previous_interrupt_take = 1'b0;
            previous_post_interrupt_take = 1'b0;
            previous_empty_interrupt_take = 1'b0;
            interrupt_event_retire_seen = 1'b0;
        end else if (scenario_active) begin
            scenario_cycle_count++;
            interrupt_event_retire_seen = 1'b0;

            if (
                $test$plusargs("TRACE") &&
                (
                    (scenario_name == "protocol_backpressure") ||
                    d5_random_active
                )
            ) begin
                $display(
                    "TRACE c=%0d idex=%0b/%08h exmem=%0b/%08h memwb=%0b/%08h fwd=%0d/%0d regs=%08h/%08h saved=%08h/%08h dreq=%0b/%0b/%08h/%08h/%b actions=%0d/%0d/%0d/%0d",
                    scenario_cycle_count,
                    dut.id_ex_q.valid,
                    dut.id_ex_q.pc,
                    dut.ex_mem_q.valid,
                    dut.ex_mem_q.pc,
                    dut.mem_wb_q.valid,
                    dut.mem_wb_q.pc,
                    dut.rs1_forward_select,
                    dut.rs2_forward_select,
                    dut.u_idu.u_regfile.registers[1],
                    dut.u_idu.u_regfile.registers[2],
                    dut.id_ex_q.rs1_data,
                    dut.id_ex_q.rs2_data,
                    dmem_req_valid,
                    dmem_req_ready,
                    dmem_req_addr,
                    dmem_req_wdata,
                    dmem_req_wstrb,
                    dut.if_id_action,
                    dut.id_ex_action,
                    dut.ex_mem_action,
                    dut.mem_wb_action
                );
            end

            if (d5_random_active) begin
                if (imem_req_valid && !imem_req_ready) begin
                    d5_imem_request_stall_cycles++;
                end
                if (
                    u_imem.transaction_pending_q &&
                    !imem_rsp_valid
                ) begin
                    d5_imem_response_delay_cycles++;
                end
                if (dmem_req_valid && !dmem_req_ready) begin
                    d5_dmem_request_stall_cycles++;
                end
                if (
                    u_dmem.transaction_pending_q &&
                    !dmem_rsp_valid
                ) begin
                    d5_dmem_response_delay_cycles++;
                end
            end

            check_condition(
                !cp_req_valid &&
                (cp_req_pc == '0) &&
                (cp_req_instr == '0) &&
                (cp_req_rs1_data == '0) &&
                (cp_req_rs2_data == '0) &&
                !cp_rsp_ready,
                "disabled coprocessor interface became active"
            );
            check_condition(
                !retire_rd_we || retire_valid,
                "retire_rd_we asserted without retire_valid"
            );
            check_condition(
                !dut.commit_valid ||
                (
                    dut.mem_commit_candidate &&
                    (dut.mem_wb_action == PIPE_LOAD)
                ),
                "commit_valid did not represent an accepted MEM candidate"
            );
            check_condition(
                dut.qualified_redirect.valid ===
                    (
                        dut.trap_take ||
                        dut.interrupt_take ||
                        dut.mret_commit ||
                        (dut.redirect_commit && dut.raw_redirect.valid)
                    ),
                "qualified redirect did not match commit qualification"
            );
            check_condition(
                !(dut.trap_take && dut.redirect_commit),
                "trap and younger EX redirect committed in the same cycle"
            );
            check_condition(
                !(dut.trap_take && dut.interrupt_take),
                "synchronous trap and interrupt committed in the same cycle"
            );
            if (dut.trap_take) begin
                check_condition(
                    dut.qualified_redirect === dut.trap_redirect,
                    "trap redirect did not win final redirect mux"
                );
            end else if (dut.interrupt_take) begin
                check_condition(
                    dut.qualified_redirect === dut.interrupt_redirect,
                    "interrupt redirect did not win final redirect mux"
                );
            end else if (dut.mret_commit) begin
                check_condition(
                    dut.qualified_redirect === dut.mret_redirect,
                    "MRET redirect did not win final redirect mux"
                );
            end else if (dut.redirect_commit) begin
                check_condition(
                    dut.qualified_redirect === dut.raw_redirect,
                    "EX redirect did not reach final redirect mux"
                );
            end

            if (imem_req_valid) begin
                check_condition(
                    (^imem_req_addr) !== 1'bx,
                    "IMem request address contains X/Z"
                );
            end
            if (dmem_req_valid) begin
                check_condition(
                    (^{
                        dmem_req_write,
                        dmem_req_addr,
                        dmem_req_wdata,
                        dmem_req_wstrb
                    }) !== 1'bx,
                    "DMem request fields contain X/Z"
                );
            end
            if (retire_valid && d5_drain_active) begin
                check_condition(
                    (retire_pc >= (TRAP_VECTOR + 32'd4)) &&
                    (retire_instr === RV32_NOP) &&
                    !retire_rd_we,
                    $sformatf(
                        "D5 drain observed a non-NOP retirement PC=%08h instruction=%08h rd_we=%0b",
                        retire_pc,
                        retire_instr,
                        retire_rd_we
                    )
                );
            end else if (retire_valid) begin
                check_condition(
                    (^{
                        retire_pc,
                        retire_instr,
                        retire_rd_we,
                        retire_rd_addr,
                        retire_rd_data
                    }) !== 1'bx,
                    "retirement fields contain X/Z"
                );
            end
            if (trap_valid) begin
                check_condition(
                    (^{trap_pc, trap_cause, trap_value}) !== 1'bx,
                    "trap fields contain X/Z"
                );
            end else begin
                check_condition(
                    (trap_pc == 32'b0) &&
                    (trap_cause == 32'b0) &&
                    (trap_value == 32'b0),
                    "inactive trap trace payload is not zero"
                );
            end
            check_condition(
                trap_valid ===
                    (
                        dut.trap_take ||
                        dut.u_csr_trap.interrupt_event_pending_q
                    ),
                "trap trace source is neither synchronous trap nor delayed interrupt"
            );

            if (previous_interrupt_take) begin
                check_condition(
                    dut.u_csr_trap.interrupt_event_pending_q &&
                    trap_valid &&
                    (trap_pc == previous_interrupt_resume_pc) &&
                    (trap_cause == previous_interrupt_cause) &&
                    (trap_value == 32'b0),
                    "interrupt take did not produce the required delayed event"
                );
                check_condition(
                    !dut.interrupt_take &&
                    !dut.interrupt_redirect.valid &&
                    !dut.qualified_redirect.valid,
                    "delayed interrupt event repeated redirect or interrupt entry"
                );
                check_condition(
                    (dut.u_csr_trap.mepc_q ==
                        previous_interrupt_resume_pc) &&
                    (dut.u_csr_trap.mcause_q ==
                        previous_interrupt_cause) &&
                    (dut.u_csr_trap.mtval_q == 32'b0) &&
                    !dut.u_csr_trap.mstatus_mie_q &&
                    (dut.u_csr_trap.mstatus_mpie_q ==
                        previous_interrupt_expected_mpie),
                    "interrupt entry CSR state changed before event observation"
                );
                check_condition(
                    dut.resume_pc_q == previous_interrupt_redirect_target,
                    "interrupt redirect target was not captured in resume_pc_q"
                );
            end

            if (previous_imem_request_stalled) begin
                check_condition(
                    imem_req_valid &&
                    (imem_req_addr === previous_imem_request_addr),
                    "stalled IMem request was not held stable"
                );
            end
            if (previous_dmem_request_stalled) begin
                check_condition(
                    dmem_req_valid &&
                    (dmem_req_write === previous_dmem_request_write) &&
                    (dmem_req_addr === previous_dmem_request_addr) &&
                    (dmem_req_wdata === previous_dmem_request_wdata) &&
                    (dmem_req_wstrb === previous_dmem_request_wstrb),
                    "stalled DMem request was not held stable"
                );
            end
            if (previous_imem_response_stalled) begin
                check_condition(
                    imem_rsp_valid &&
                    (imem_rsp_data === previous_imem_response_data) &&
                    (imem_rsp_error === previous_imem_response_error),
                    "stalled IMem response was not held stable"
                );
            end
            if (previous_dmem_response_stalled) begin
                check_condition(
                    dmem_rsp_valid &&
                    (dmem_rsp_rdata === previous_dmem_response_data) &&
                    (dmem_rsp_error === previous_dmem_response_error),
                    "stalled DMem response was not held stable"
                );
            end

            if (pipeline_history_valid) begin
                if (previous_if_id_action == PIPE_HOLD) begin
                    check_condition(
                        dut.if_id_q === previous_if_id_q,
                        "IF/ID changed after PIPE_HOLD"
                    );
                end else if (previous_if_id_action == PIPE_CLEAR) begin
                    check_condition(
                        !dut.if_id_q.valid,
                        "IF/ID remained valid after PIPE_CLEAR"
                    );
                end

                if (previous_id_ex_action == PIPE_HOLD) begin
                    check_condition(
                        dut.id_ex_q === previous_id_ex_q,
                        "ID/EX changed after PIPE_HOLD"
                    );
                end else if (previous_id_ex_action == PIPE_CLEAR) begin
                    check_condition(
                        !dut.id_ex_q.valid,
                        "ID/EX remained valid after PIPE_CLEAR"
                    );
                end

                if (previous_ex_mem_action == PIPE_HOLD) begin
                    check_condition(
                        dut.ex_mem_q === previous_ex_mem_q,
                        "EX/MEM changed after PIPE_HOLD"
                    );
                end else if (previous_ex_mem_action == PIPE_CLEAR) begin
                    check_condition(
                        !dut.ex_mem_q.valid,
                        "EX/MEM remained valid after PIPE_CLEAR"
                    );
                end

                if (previous_mem_wb_action == PIPE_HOLD) begin
                    check_condition(
                        dut.mem_wb_q === previous_mem_wb_q,
                        "MEM/WB changed after PIPE_HOLD"
                    );
                end else if (previous_mem_wb_action == PIPE_CLEAR) begin
                    check_condition(
                        !dut.mem_wb_q.valid,
                        "MEM/WB remained valid after PIPE_CLEAR"
                    );
                end
            end

            if (dut.trap_take) begin
                check_condition(
                    (dut.fetch_action == FETCH_REDIRECT) &&
                    (dut.if_id_action == PIPE_CLEAR) &&
                    (dut.id_ex_action == PIPE_CLEAR) &&
                    (dut.ex_mem_action == PIPE_CLEAR) &&
                    (dut.mem_wb_action == PIPE_CLEAR),
                    "trap selected wrong pipeline actions"
                );
            end else if (dut.post_commit_interrupt_take) begin
                check_condition(
                    (dut.fetch_action == FETCH_REDIRECT) &&
                    (dut.if_id_action == PIPE_CLEAR) &&
                    (dut.id_ex_action == PIPE_CLEAR) &&
                    (dut.ex_mem_action == PIPE_CLEAR) &&
                    (dut.mem_wb_action == PIPE_LOAD) &&
                    dut.mem_commit_candidate &&
                    dut.commit_valid,
                    "post-commit interrupt selected wrong pipeline actions"
                );
            end else if (dut.empty_interrupt_take) begin
                check_condition(
                    (dut.fetch_action == FETCH_REDIRECT) &&
                    (dut.if_id_action == PIPE_CLEAR) &&
                    (dut.id_ex_action == PIPE_CLEAR) &&
                    (dut.ex_mem_action == PIPE_CLEAR) &&
                    (dut.mem_wb_action == PIPE_CLEAR) &&
                    !dut.mem_commit_candidate &&
                    !dut.commit_valid,
                    "empty-pipeline interrupt selected wrong pipeline actions"
                );
            end else if (dut.mret_commit) begin
                check_condition(
                    (dut.fetch_action == FETCH_REDIRECT) &&
                    (dut.if_id_action == PIPE_CLEAR) &&
                    (dut.id_ex_action == PIPE_CLEAR) &&
                    (dut.ex_mem_action == PIPE_CLEAR) &&
                    (dut.mem_wb_action == PIPE_LOAD),
                    "MRET selected wrong pipeline actions"
                );
            end else if (dut.mem_response_wait) begin
                mem_response_wait_count++;
                check_condition(
                    !trap_valid,
                    "trap committed while MEM response was still pending"
                );
                check_condition(
                    (dut.fetch_action == FETCH_HOLD) &&
                    (dut.if_id_action == PIPE_HOLD) &&
                    (dut.id_ex_action == PIPE_HOLD) &&
                    (dut.ex_mem_action == PIPE_HOLD) &&
                    (dut.mem_wb_action == PIPE_CLEAR),
                    "MEM response wait selected wrong pipeline actions"
                );
            end else if (
                dut.ex_request_wait || dut.ex_multicycle_wait
            ) begin
                if (dut.ex_request_wait) begin
                    ex_request_wait_count++;
                end
                check_condition(
                    (dut.fetch_action == FETCH_HOLD) &&
                    (dut.if_id_action == PIPE_HOLD) &&
                    (dut.id_ex_action == PIPE_HOLD) &&
                    (dut.ex_mem_action == PIPE_CLEAR) &&
                    (dut.mem_wb_action == PIPE_LOAD),
                    "EX request wait selected wrong pipeline actions"
                );
            end else if (dut.redirect_commit) begin
                redirect_count++;
                check_condition(
                    (dut.fetch_action == FETCH_REDIRECT) &&
                    (dut.if_id_action == PIPE_CLEAR) &&
                    (dut.id_ex_action == PIPE_CLEAR) &&
                    (dut.ex_mem_action == PIPE_LOAD) &&
                    (dut.mem_wb_action == PIPE_LOAD),
                    "redirect selected wrong pipeline actions"
                );
            end else if (
                dut.late_result_hazard &&
                (dut.if_id_action == PIPE_HOLD) &&
                (dut.id_ex_action == PIPE_CLEAR)
            ) begin
                late_result_hazard_count++;
                check_condition(
                    (dut.fetch_action == FETCH_HOLD) &&
                    (dut.ex_mem_action == PIPE_LOAD) &&
                    (dut.mem_wb_action == PIPE_LOAD),
                    "late-result hazard selected wrong pipeline actions"
                );
            end

            if (imem_req_valid && !imem_req_ready) begin
                imem_request_stall_count++;
            end
            if (dut.ex_multicycle_wait) begin
                ex_multicycle_wait_count++;
                check_condition(
                    !dut.ex_hold_valid,
                    "multicycle M instruction created an EX snapshot"
                );
            end
            if (dut.mdu_req_valid && dut.mdu_req_ready) begin
                observed_mdu_request_count++;
                total_mdu_request_count++;
            end
            if (dut.mdu_rsp_valid && dut.mdu_rsp_ready) begin
                observed_mdu_response_count++;
                total_mdu_response_count++;
            end
            if (dut.interrupt_take) begin
                observed_interrupt_take_count++;
                total_interrupt_take_count++;
                check_condition(
                    dut.mdu_kill &&
                    dut.ex_request_block &&
                    !dut.redirect_commit,
                    "interrupt did not suppress younger EX side effects"
                );

                if (dut.post_commit_interrupt_take) begin
                    observed_post_interrupt_take_count++;
                end
                if (dut.empty_interrupt_take) begin
                    observed_empty_interrupt_take_count++;
                end

                if (
                    dut.ex_mem_active_candidate.valid &&
                    dut.ex_mem_active_candidate.mem_ctrl.memory_write
                ) begin
                    check_condition(
                        !dmem_req_valid &&
                        !dut.u_lsu.request_fire &&
                        dut.ex_request_block,
                        "interrupt did not block a younger store request"
                    );
                end

                if (dut.raw_redirect.valid) begin
                    check_condition(
                        !dut.redirect_commit &&
                        (dut.qualified_redirect == dut.interrupt_redirect),
                        "interrupt did not suppress a younger EX redirect"
                    );
                end
            end

            if (retire_valid && !d5_drain_active) begin
                if (dut.u_csr_trap.interrupt_event_pending_q) begin
                    interrupt_event_retire_seen = 1'b1;
                end
                total_retire_count++;

                if (observed_retire_count < expected_retire_count) begin
                    check_condition(
                        retire_pc ===
                            expected_retire_pc[observed_retire_count],
                        $sformatf(
                            "retire[%0d] PC=%08h expected=%08h",
                            observed_retire_count,
                            retire_pc,
                            expected_retire_pc[observed_retire_count]
                        )
                    );
                    check_condition(
                        retire_instr ===
                            expected_retire_instruction[
                                observed_retire_count
                            ],
                        $sformatf(
                            "retire[%0d] instruction=%08h expected=%08h",
                            observed_retire_count,
                            retire_instr,
                            expected_retire_instruction[
                                observed_retire_count
                            ]
                        )
                    );
                    check_condition(
                        retire_rd_we ===
                            expected_retire_rd_we[observed_retire_count],
                        $sformatf(
                            "retire[%0d] rd_we=%0b expected=%0b",
                            observed_retire_count,
                            retire_rd_we,
                            expected_retire_rd_we[observed_retire_count]
                        )
                    );

                    if (expected_retire_rd_we[observed_retire_count]) begin
                        check_condition(
                            retire_rd_addr ===
                                expected_retire_rd_addr[
                                    observed_retire_count
                                ],
                            $sformatf(
                                "retire[%0d] rd=x%0d expected=x%0d",
                                observed_retire_count,
                                retire_rd_addr,
                                expected_retire_rd_addr[
                                    observed_retire_count
                                ]
                            )
                        );
                        check_condition(
                            retire_rd_data ===
                                expected_retire_rd_data[
                                    observed_retire_count
                                ],
                            $sformatf(
                                "retire[%0d] data=%08h expected=%08h",
                                observed_retire_count,
                                retire_rd_data,
                                expected_retire_rd_data[
                                    observed_retire_count
                                ]
                            )
                        );
                    end
                end else begin
                    check_condition(
                        1'b0,
                        $sformatf(
                            "unexpected retirement PC=%08h instruction=%08h",
                            retire_pc,
                            retire_instr
                        )
                    );
                end

                observed_retire_count++;
            end

            if (trap_valid) begin
                total_trap_count++;

                if (dut.trap_take) begin
                    check_condition(
                        !dut.mem_wb_candidate.valid,
                        "faulting MEM instruction formed a retirement candidate"
                    );
                    if (
                        dut.ex_mem_active_candidate.valid &&
                        dut.ex_mem_active_candidate.mem_ctrl.memory_write
                    ) begin
                        check_condition(
                            !dmem_req_valid &&
                            !dut.u_lsu.request_fire &&
                            dut.ex_request_block,
                            "trap did not block a younger store inside LSU"
                        );
                    end
                end else begin
                    check_condition(
                        dut.u_csr_trap.interrupt_event_pending_q &&
                        previous_interrupt_take,
                        "interrupt trap event was not backed by a prior take"
                    );
                    if (previous_post_interrupt_take) begin
                        check_condition(
                            interrupt_event_retire_seen &&
                            retire_valid &&
                            (retire_pc ==
                                previous_interrupt_boundary_pc) &&
                            (retire_instr ==
                                previous_interrupt_boundary_instruction),
                            "post-interrupt event was not ordered after its boundary retirement"
                        );
                    end
                    if (previous_empty_interrupt_take) begin
                        check_condition(
                            !interrupt_event_retire_seen && !retire_valid,
                            "empty interrupt event incorrectly paired with retirement"
                        );
                    end
                end

                if (observed_trap_count < expected_trap_count) begin
                    check_condition(
                        trap_pc === expected_trap_pc[observed_trap_count],
                        $sformatf(
                            "trap[%0d] PC=%08h expected=%08h",
                            observed_trap_count,
                            trap_pc,
                            expected_trap_pc[observed_trap_count]
                        )
                    );
                    check_condition(
                        trap_cause ===
                            expected_trap_cause[observed_trap_count],
                        $sformatf(
                            "trap[%0d] cause=%08h expected=%08h",
                            observed_trap_count,
                            trap_cause,
                            expected_trap_cause[observed_trap_count]
                        )
                    );
                    check_condition(
                        trap_value ===
                            expected_trap_value[observed_trap_count],
                        $sformatf(
                            "trap[%0d] value=%08h expected=%08h",
                            observed_trap_count,
                            trap_value,
                            expected_trap_value[observed_trap_count]
                        )
                    );
                end else begin
                    check_condition(
                        1'b0,
                        $sformatf(
                            "unexpected trap PC=%08h cause=%08h value=%08h",
                            trap_pc,
                            trap_cause,
                            trap_value
                        )
                    );
                end

                observed_trap_count++;
            end

            if (dmem_request_fire) begin
                total_dmem_request_count++;

                if (
                    observed_dmem_request_count <
                    expected_dmem_request_count
                ) begin
                    check_condition(
                        dmem_req_write ===
                            expected_dmem_write[
                                observed_dmem_request_count
                            ],
                        $sformatf(
                            "dmem[%0d] write=%0b expected=%0b",
                            observed_dmem_request_count,
                            dmem_req_write,
                            expected_dmem_write[
                                observed_dmem_request_count
                            ]
                        )
                    );
                    check_condition(
                        dmem_req_addr ===
                            expected_dmem_addr[
                                observed_dmem_request_count
                            ],
                        $sformatf(
                            "dmem[%0d] addr=%08h expected=%08h",
                            observed_dmem_request_count,
                            dmem_req_addr,
                            expected_dmem_addr[
                                observed_dmem_request_count
                            ]
                        )
                    );
                    check_condition(
                        dmem_req_wdata ===
                            expected_dmem_wdata[
                                observed_dmem_request_count
                            ],
                        $sformatf(
                            "dmem[%0d] wdata=%08h expected=%08h",
                            observed_dmem_request_count,
                            dmem_req_wdata,
                            expected_dmem_wdata[
                                observed_dmem_request_count
                            ]
                        )
                    );
                    check_condition(
                        dmem_req_wstrb ===
                            expected_dmem_wstrb[
                                observed_dmem_request_count
                            ],
                        $sformatf(
                            "dmem[%0d] wstrb=%b expected=%b",
                            observed_dmem_request_count,
                            dmem_req_wstrb,
                            expected_dmem_wstrb[
                                observed_dmem_request_count
                            ]
                        )
                    );
                end else begin
                    check_condition(
                        1'b0,
                        $sformatf(
                            "unexpected DMem request write=%0b addr=%08h",
                            dmem_req_write,
                            dmem_req_addr
                        )
                    );
                end

                observed_dmem_request_count++;
            end

            if (
                imem_request_fire &&
                (imem_req_addr == TRAP_VECTOR)
            ) begin
                observed_trap_vector_fetch_count++;
            end

            if (imem_response_fire) begin
                check_condition(
                    imem_outstanding_count == 1,
                    "IMem response completed without an outstanding request"
                );
            end
            if (dmem_response_fire) begin
                check_condition(
                    dmem_outstanding_count == 1,
                    "DMem response completed without an outstanding request"
                );
            end

            case ({imem_request_fire, imem_response_fire})
                2'b10: begin
                    check_condition(
                        imem_outstanding_count == 0,
                        "second IMem request accepted while one was outstanding"
                    );
                    imem_outstanding_count = 1;
                end
                2'b01: imem_outstanding_count = 0;
                2'b11: imem_outstanding_count = 1;
                default: begin
                end
            endcase

            case ({dmem_request_fire, dmem_response_fire})
                2'b10: begin
                    check_condition(
                        dmem_outstanding_count == 0,
                        "second DMem request accepted while one was outstanding"
                    );
                    dmem_outstanding_count = 1;
                end
                2'b01: dmem_outstanding_count = 0;
                2'b11: dmem_outstanding_count = 1;
                default: begin
                end
            endcase

            previous_imem_request_stalled =
                imem_req_valid && !imem_req_ready;
            previous_imem_request_addr = imem_req_addr;

            previous_dmem_request_stalled =
                dmem_req_valid && !dmem_req_ready;
            previous_dmem_request_write = dmem_req_write;
            previous_dmem_request_addr  = dmem_req_addr;
            previous_dmem_request_wdata = dmem_req_wdata;
            previous_dmem_request_wstrb = dmem_req_wstrb;

            previous_imem_response_stalled =
                imem_rsp_valid && !imem_rsp_ready;
            previous_imem_response_data  = imem_rsp_data;
            previous_imem_response_error = imem_rsp_error;

            previous_dmem_response_stalled =
                dmem_rsp_valid && !dmem_rsp_ready;
            previous_dmem_response_data  = dmem_rsp_rdata;
            previous_dmem_response_error = dmem_rsp_error;

            previous_if_id_action = dut.if_id_action;
            previous_id_ex_action = dut.id_ex_action;
            previous_ex_mem_action = dut.ex_mem_action;
            previous_mem_wb_action = dut.mem_wb_action;
            previous_if_id_q = dut.if_id_q;
            previous_id_ex_q = dut.id_ex_q;
            previous_ex_mem_q = dut.ex_mem_q;
            previous_mem_wb_q = dut.mem_wb_q;
            pipeline_history_valid = 1'b1;

            previous_interrupt_take = dut.interrupt_take;
            previous_post_interrupt_take =
                dut.post_commit_interrupt_take;
            previous_empty_interrupt_take = dut.empty_interrupt_take;
            if (dut.interrupt_take) begin
                previous_interrupt_resume_pc = dut.boundary_resume_pc;
                previous_interrupt_cause =
                    dut.u_csr_trap.selected_interrupt_cause;
                previous_interrupt_boundary_pc = dut.ex_mem_q.pc;
                previous_interrupt_boundary_instruction =
                    dut.ex_mem_q.instruction;
                previous_interrupt_redirect_target =
                    dut.interrupt_redirect.target;
                previous_interrupt_expected_mpie =
                    dut.u_csr_trap.effective_mstatus_mie;
            end
        end else begin
            previous_imem_request_stalled = 1'b0;
            previous_dmem_request_stalled = 1'b0;
            previous_imem_response_stalled = 1'b0;
            previous_dmem_response_stalled = 1'b0;
            pipeline_history_valid = 1'b0;
            previous_interrupt_take = 1'b0;
            previous_post_interrupt_take = 1'b0;
            previous_empty_interrupt_take = 1'b0;
            interrupt_event_retire_seen = 1'b0;
        end
    end

    initial begin
        clk = 1'b0;
        rst = 1'b1;

        imem_request_enable  = 1'b1;
        imem_response_enable = 1'b1;
        dmem_request_enable  = 1'b1;
        dmem_response_enable = 1'b1;
        d5_only_mode = $test$plusargs("D5_ONLY");
        d5_random_active = 1'b0;
        d5_drain_active = 1'b0;
        d5_seed = 32'h0000_0001;
        d5_stall_percent = 32'd50;
        d5_max_stall_cycles = 32'd8;
        SCENARIO_TIMEOUT_CYCLES =
            d5_only_mode ? 10_000 : 600;
        d5_plusarg_status = $value$plusargs("SEED=%h", d5_seed);
        d5_plusarg_status = $value$plusargs(
            "STALL_PCT=%d",
            d5_stall_percent
        );
        d5_plusarg_status = $value$plusargs(
            "MAX_STALL=%d",
            d5_max_stall_cycles
        );
        d5_plusarg_status = $value$plusargs(
            "TIMEOUT=%d",
            SCENARIO_TIMEOUT_CYCLES
        );
        if (d5_stall_percent > 32'd100) begin
            $fatal(1, "STALL_PCT must be in the range 0..100");
        end
        if (d5_max_stall_cycles > 32'd1024) begin
            $fatal(1, "MAX_STALL must be in the range 0..1024");
        end
        if (SCENARIO_TIMEOUT_CYCLES == 0) begin
            $fatal(1, "TIMEOUT must be greater than zero");
        end
        if (d5_only_mode) begin
            $display(
                "[D5_CONFIG] seed=%08h stall_pct=%0d max_stall=%0d timeout=%0d",
                d5_seed,
                d5_stall_percent,
                d5_max_stall_cycles,
                SCENARIO_TIMEOUT_CYCLES
            );
        end
        irq_software = 1'b0;
        irq_timer    = 1'b0;
        irq_external = 1'b0;

        cp_req_ready = 1'b1;
        cp_rsp_valid = 1'b0;
        cp_rsp_data  = '0;
        cp_rsp_error = 1'b0;

        scenario_active = 1'b0;
        scenario_name = "initialization";

        scenario_count = 0;
        passed_scenario_count = 0;
        scenario_cycle_count = 0;
        scenario_check_count = 0;
        scenario_error_count = 0;
        total_check_count = 0;
        total_error_count = 0;
        total_retire_count = 0;
        total_dmem_request_count = 0;
        total_trap_count = 0;
        total_mdu_request_count = 0;
        total_mdu_response_count = 0;
        total_interrupt_take_count = 0;
        expected_trap_vector_fetch_count = 0;
        observed_trap_vector_fetch_count = 0;
        expected_mdu_request_count = 0;
        observed_mdu_request_count = 0;
        expected_mdu_response_count = 0;
        observed_mdu_response_count = 0;
        expected_interrupt_take_count = 0;
        observed_interrupt_take_count = 0;
        expected_post_interrupt_take_count = 0;
        observed_post_interrupt_take_count = 0;
        expected_empty_interrupt_take_count = 0;
        observed_empty_interrupt_take_count = 0;


        imem_outstanding_count = 0;
        dmem_outstanding_count = 0;
        previous_imem_request_stalled = 1'b0;
        previous_dmem_request_stalled = 1'b0;
        previous_imem_response_stalled = 1'b0;
        previous_dmem_response_stalled = 1'b0;
        pipeline_history_valid = 1'b0;
        previous_interrupt_take = 1'b0;
        previous_post_interrupt_take = 1'b0;
        previous_empty_interrupt_take = 1'b0;
        previous_interrupt_resume_pc = 32'b0;
        previous_interrupt_cause = 32'b0;
        previous_interrupt_boundary_pc = 32'b0;
        previous_interrupt_boundary_instruction = 32'b0;
        previous_interrupt_redirect_target = 32'b0;
        previous_interrupt_expected_mpie = 1'b0;
        interrupt_event_retire_seen = 1'b0;

        if (d5_only_mode) begin
            scenario_d5_random_backpressure();
        end else begin
        scenario_integer_and_forwarding();
        scenario_load_store_and_hazards();
        scenario_control_flow();
        scenario_protocol_backpressure();
        scenario_mem_wait_blocks_redirect();
        scenario_precise_illegal_trap();
        scenario_trap_beats_redirect();
        scenario_dmem_fault_trap_wait();
        scenario_trap_redirect_backpressure();
        run_single_trap_scenario(
            "instruction_access_fault",
            encoder_s(
                FUNCT3_SW,
                5'd0,
                5'd30,
                32'h0000_0100
            ),
            EXCEPTION_CAUSE_INSTRUCTION_ACCESS_FAULT,
            32'h0000_0004,
            1'b1,
            32'h0000_0010
        );
        run_single_trap_scenario(
            "breakpoint_trap",
            INSTRUCTION_EBREAK,
            EXCEPTION_CAUSE_BREAKPOINT,
            32'b0,
            1'b0,
            32'h0000_0011
        );
        scenario_control_address_misaligned();
        run_single_trap_scenario(
            "load_address_misaligned",
            instruction_load(FUNCT3_LW, 5'd1, 5'd0, 32'd2),
            EXCEPTION_CAUSE_LOAD_ADDRESS_MISALIGNED,
            32'h0000_0002,
            1'b0,
            32'h0000_0012
        );
        run_single_trap_scenario(
            "store_address_misaligned",
            encoder_s(FUNCT3_SW, 5'd0, 5'd30, 32'd2),
            EXCEPTION_CAUSE_STORE_ADDRESS_MISALIGNED,
            32'h0000_0002,
            1'b0,
            32'h0000_0013
        );
        scenario_store_access_fault();
        scenario_zicsr_rmw_and_hazard();
        scenario_zicsr_mro_illegal();
        scenario_zicsr_unknown_illegal();
        scenario_mret_wfi_return();
        scenario_mret_beats_young_redirect();
        scenario_machine_counters();
        scenario_counter_fault_exclusion();
        scenario_rv32m_multiply_variants();
        scenario_rv32m_divide_variants();
        scenario_rv32m_forwarding_and_consumers();
        scenario_rv32m_load_wait_response_hold();
        scenario_rv32m_store_wait_response_hold();
        scenario_rv32m_trap_kills_response();
        scenario_rv32m_mret_kills_request();
        run_interrupt_arbitration_case(
            "irq_priority_external",
            32'h0000_0888,
            1'b1,
            1'b1,
            1'b1,
            1'b1,
            1'b1,
            INTERRUPT_CAUSE_MACHINE_EXTERNAL
        );
        run_interrupt_arbitration_case(
            "irq_priority_software",
            32'h0000_0088,
            1'b1,
            1'b1,
            1'b1,
            1'b1,
            1'b1,
            INTERRUPT_CAUSE_MACHINE_SOFTWARE
        );
        run_interrupt_arbitration_case(
            "irq_timer_cause",
            32'h0000_0080,
            1'b1,
            1'b1,
            1'b1,
            1'b1,
            1'b1,
            INTERRUPT_CAUSE_MACHINE_TIMER
        );
        run_interrupt_arbitration_case(
            "irq_global_mask",
            32'h0000_0008,
            1'b0,
            1'b1,
            1'b0,
            1'b0,
            1'b0,
            32'b0
        );
        run_interrupt_arbitration_case(
            "irq_local_mask",
            32'h0000_0000,
            1'b1,
            1'b1,
            1'b0,
            1'b0,
            1'b0,
            32'b0
        );
        run_interrupt_control_resume_case("irq_resume_taken_branch", 0);
        run_interrupt_control_resume_case("irq_resume_not_taken_branch", 1);
        run_interrupt_control_resume_case("irq_resume_jal", 2);
        run_interrupt_control_resume_case("irq_resume_jalr", 3);
        scenario_interrupt_alu_mret_counter();
        run_interrupt_csr_preview_case("irq_preview_mie", 0);
        run_interrupt_csr_preview_case("irq_preview_mstatus", 1);
        run_interrupt_csr_preview_case("irq_preview_mtvec", 2);
        scenario_interrupt_mret_immediate_reentry();
        scenario_interrupt_sync_fault_priority();
        scenario_interrupt_load_wait_kills_store();
        scenario_interrupt_store_wait_kills_branch();
        scenario_interrupt_load_wait_kills_mdu_response();
        scenario_interrupt_empty_with_ifu_pending();
        scenario_reset_during_imem();
        scenario_reset_during_dmem();
        scenario_interrupt_reset_clears_pending();
        end

        if (d5_only_mode) begin
            if (total_error_count == 0) begin
                $display(
                    "[D5_RESULT] status=PASS seed=%08h cycles=%0d retire=%0d trap=%0d dmem=%0d mdu_req=%0d mdu_rsp=%0d irq=%0d checks=%0d imem_req_stall=%0d imem_rsp_delay=%0d dmem_req_stall=%0d dmem_rsp_delay=%0d imem_req_low=%0d imem_rsp_low=%0d dmem_req_low=%0d dmem_rsp_low=%0d imem_req_forced=%0d imem_rsp_forced=%0d dmem_req_forced=%0d dmem_rsp_forced=%0d imem_req_max=%0d imem_rsp_max=%0d dmem_req_max=%0d dmem_rsp_max=%0d coverage=%04h state=%08h",
                    d5_seed,
                    scenario_cycle_count,
                    total_retire_count,
                    total_trap_count,
                    total_dmem_request_count,
                    total_mdu_request_count,
                    total_mdu_response_count,
                    total_interrupt_take_count,
                    total_check_count,
                    d5_imem_request_stall_cycles,
                    d5_imem_response_delay_cycles,
                    d5_dmem_request_stall_cycles,
                    d5_dmem_response_delay_cycles,
                    d5_imem_request_low_cycles,
                    d5_imem_response_low_cycles,
                    d5_dmem_request_low_cycles,
                    d5_dmem_response_low_cycles,
                    d5_imem_request_forced_grants,
                    d5_imem_response_forced_grants,
                    d5_dmem_request_forced_grants,
                    d5_dmem_response_forced_grants,
                    d5_imem_request_max_low_streak,
                    d5_imem_response_max_low_streak,
                    d5_dmem_request_max_low_streak,
                    d5_dmem_response_max_low_streak,
                    d5_coverage_bitmap,
                    d5_random_state
                );
            end else begin
                $display(
                    "[D5_RESULT] status=FAIL seed=%08h cycles=%0d retire=%0d trap=%0d dmem=%0d mdu_req=%0d mdu_rsp=%0d irq=%0d checks=%0d coverage=%04h state=%08h",
                    d5_seed,
                    scenario_cycle_count,
                    total_retire_count,
                    total_trap_count,
                    total_dmem_request_count,
                    total_mdu_request_count,
                    total_mdu_response_count,
                    total_interrupt_take_count,
                    total_check_count,
                    d5_coverage_bitmap,
                    d5_random_state
                );
            end
        end

        if (total_error_count == 0) begin
            $display("");
            $display(
                "[PASS] rv32_core: %0d/%0d scenarios, %0d retirements, %0d traps, %0d DMem requests, %0d/%0d MDU req/rsp, %0d interrupts, %0d checks",
                passed_scenario_count,
                scenario_count,
                total_retire_count,
                total_trap_count,
                total_dmem_request_count,
                total_mdu_request_count,
                total_mdu_response_count,
                total_interrupt_take_count,
                total_check_count
            );
            $finish;
        end else begin
            $fatal(
                1,
                "[FAIL] rv32_core: %0d errors across %0d scenarios",
                total_error_count,
                scenario_count
            );
        end
    end
endmodule
