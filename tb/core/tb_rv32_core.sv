`timescale 1ns/1ps

module tb_rv32_core;
    import rv32_pkg::*;
    import rv32_tb_pkg::*;

    localparam logic [31:0] RESET_VECTOR = 32'h0000_0000;
    localparam int unsigned IMEM_WORD_COUNT = 256;
    localparam int unsigned DMEM_BYTE_COUNT = 1024;
    localparam int unsigned MAX_EXPECTED = 128;
    localparam int unsigned SCENARIO_TIMEOUT_CYCLES = 600;

    logic clk;
    logic rst;

    logic imem_request_enable;
    logic imem_response_enable;
    logic dmem_request_enable;
    logic dmem_response_enable;

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

    int unsigned expected_retire_count;
    int unsigned observed_retire_count;
    int unsigned expected_dmem_request_count;
    int unsigned observed_dmem_request_count;

    int unsigned expected_load_use_count;
    int unsigned expected_redirect_count;
    int unsigned minimum_ex_request_wait_count;
    int unsigned minimum_mem_response_wait_count;
    int unsigned minimum_imem_request_stall_count;

    int unsigned load_use_count;
    int unsigned redirect_count;
    int unsigned ex_request_wait_count;
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

    assign imem_request_fire  = imem_req_valid && imem_req_ready;
    assign imem_response_fire = imem_rsp_valid && imem_rsp_ready;
    assign dmem_request_fire  = dmem_req_valid && dmem_req_ready;
    assign dmem_response_fire = dmem_rsp_valid && dmem_rsp_ready;

    rv32_core #(
        .RESET_VECTOR  (RESET_VECTOR),
        .COPROC_ENABLE (1'b0)
    ) dut (
        .clk             (clk),
        .rst             (rst),
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
        .request_enable  (imem_request_enable),
        .response_enable (imem_response_enable),
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
        .request_enable  (dmem_request_enable),
        .response_enable (dmem_response_enable),
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

            scenario_name   = name;
            scenario_active = 1'b1;
            scenario_count++;

            expected_retire_count       = 0;
            observed_retire_count       = 0;
            expected_dmem_request_count = 0;
            observed_dmem_request_count = 0;

            expected_load_use_count          = 0;
            expected_redirect_count          = 0;
            minimum_ex_request_wait_count    = 0;
            minimum_mem_response_wait_count  = 0;
            minimum_imem_request_stall_count = 0;

            load_use_count          = 0;
            redirect_count          = 0;
            ex_request_wait_count   = 0;
            mem_response_wait_count = 0;
            imem_request_stall_count = 0;

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
                (observed_retire_count < expected_retire_count) &&
                (scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES)
            ) begin
                @(posedge clk);
                #1;
            end

            check_condition(
                scenario_cycle_count < SCENARIO_TIMEOUT_CYCLES,
                $sformatf(
                    "timeout: observed %0d/%0d retirements",
                    observed_retire_count,
                    expected_retire_count
                )
            );
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
                load_use_count == expected_load_use_count,
                $sformatf(
                    "load-use event count %0d, expected %0d",
                    load_use_count,
                    expected_load_use_count
                )
            );
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
                    "[PASS] %-28s cycles=%0d retire=%0d dmem=%0d checks=%0d",
                    scenario_name,
                    scenario_cycle_count,
                    observed_retire_count,
                    observed_dmem_request_count,
                    scenario_check_count
                );
                $display(
                    "       events: load_use=%0d redirect=%0d ex_wait=%0d mem_wait=%0d imem_req_stall=%0d",
                    load_use_count,
                    redirect_count,
                    ex_request_wait_count,
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

            expected_load_use_count = 3;

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

            expected_load_use_count = 1;
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
            while (observed_dmem_request_count < 1) begin
                @(posedge clk);
                #1;
            end

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

    always @(posedge clk) begin
        if (rst) begin
            if (scenario_active) begin
                check_condition(
                    !imem_req_valid &&
                    !imem_rsp_ready &&
                    !dmem_req_valid &&
                    !dmem_rsp_ready &&
                    !retire_valid,
                    "reset did not suppress requests, responses, and retirement"
                );
            end

            imem_outstanding_count = 0;
            dmem_outstanding_count = 0;

            previous_imem_request_stalled = 1'b0;
            previous_dmem_request_stalled = 1'b0;
            previous_imem_response_stalled = 1'b0;
            previous_dmem_response_stalled = 1'b0;
            pipeline_history_valid = 1'b0;
        end else if (scenario_active) begin
            scenario_cycle_count++;

            if (
                $test$plusargs("TRACE") &&
                (scenario_name == "protocol_backpressure")
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
                dut.qualified_redirect.valid ===
                    (dut.redirect_commit && dut.raw_redirect.valid),
                "qualified redirect did not match commit qualification"
            );

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
            if (retire_valid) begin
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

            if (dut.mem_response_wait) begin
                mem_response_wait_count++;
                check_condition(
                    (dut.fetch_action == FETCH_HOLD) &&
                    (dut.if_id_action == PIPE_HOLD) &&
                    (dut.id_ex_action == PIPE_HOLD) &&
                    (dut.ex_mem_action == PIPE_HOLD) &&
                    (dut.mem_wb_action == PIPE_CLEAR),
                    "MEM response wait selected wrong pipeline actions"
                );
            end else if (dut.ex_request_wait) begin
                ex_request_wait_count++;
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
                dut.load_use_hazard &&
                (dut.if_id_action == PIPE_HOLD) &&
                (dut.id_ex_action == PIPE_CLEAR)
            ) begin
                load_use_count++;
                check_condition(
                    (dut.fetch_action == FETCH_HOLD) &&
                    (dut.ex_mem_action == PIPE_LOAD) &&
                    (dut.mem_wb_action == PIPE_LOAD),
                    "load-use selected wrong pipeline actions"
                );
            end

            if (imem_req_valid && !imem_req_ready) begin
                imem_request_stall_count++;
            end

            if (retire_valid) begin
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
        end else begin
            previous_imem_request_stalled = 1'b0;
            previous_dmem_request_stalled = 1'b0;
            previous_imem_response_stalled = 1'b0;
            previous_dmem_response_stalled = 1'b0;
            pipeline_history_valid = 1'b0;
        end
    end

    initial begin
        clk = 1'b0;
        rst = 1'b1;

        imem_request_enable  = 1'b1;
        imem_response_enable = 1'b1;
        dmem_request_enable  = 1'b1;
        dmem_response_enable = 1'b1;

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

        imem_outstanding_count = 0;
        dmem_outstanding_count = 0;
        previous_imem_request_stalled = 1'b0;
        previous_dmem_request_stalled = 1'b0;
        previous_imem_response_stalled = 1'b0;
        previous_dmem_response_stalled = 1'b0;
        pipeline_history_valid = 1'b0;

        scenario_integer_and_forwarding();
        scenario_load_store_and_hazards();
        scenario_control_flow();
        scenario_protocol_backpressure();
        scenario_mem_wait_blocks_redirect();
        scenario_reset_during_imem();
        scenario_reset_during_dmem();

        if (total_error_count == 0) begin
            $display("");
            $display(
                "[PASS] rv32_core: %0d/%0d scenarios, %0d retirements, %0d DMem requests, %0d checks",
                passed_scenario_count,
                scenario_count,
                total_retire_count,
                total_dmem_request_count,
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
