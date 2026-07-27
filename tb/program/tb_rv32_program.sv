`timescale 1ns/1ps

module tb_rv32_program #(
    parameter logic [31:0] RESET_VECTOR = 32'h8000_0000,
    parameter logic [31:0] MTVEC_RESET  = 32'h8000_0300,
    parameter int unsigned MEM_BYTES    = 16 * 1024
);
    localparam int unsigned MEM_WORDS    = MEM_BYTES / 4;

    logic clk;
    logic rst;

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

    logic [31:0] imem_words [0:MEM_WORDS-1];
    logic [31:0] dmem_words [0:MEM_WORDS-1];

    logic        imem_pending_q;
    logic [31:0] imem_rsp_data_q;
    logic        imem_rsp_error_q;

    logic        dmem_pending_q;
    logic [31:0] dmem_rsp_data_q;
    logic        dmem_rsp_error_q;
    logic [31:0] dmem_txn_pc_q;
    logic [31:0] dmem_txn_instr_q;

    logic        finish_pending_q;
    logic [31:0] finish_pc_q;
    logic [31:0] finish_instr_q;
    logic [31:0] tohost_value_q;

    logic imem_addr_in_range;
    logic dmem_addr_in_range;
    logic imem_request_fire;
    logic imem_response_fire;
    logic dmem_request_fire;
    logic dmem_response_fire;

    string mem_hex_path;
    string trace_path;
    integer trace_fd;
    integer init_index;
    integer cycle_count;
    integer max_cycles;
    integer arch_order;
    integer memory_order;
    integer retire_count;
    integer trap_count;
    logic [31:0] tohost_addr;

    function automatic logic [31:0] merge_word(
        input logic [31:0] old_word,
        input logic [31:0] new_word,
        input logic [3:0]  write_strobe
    );
        logic [31:0] merged;
        begin
            merged = old_word;
            if (write_strobe[0]) merged[7:0]   = new_word[7:0];
            if (write_strobe[1]) merged[15:8]  = new_word[15:8];
            if (write_strobe[2]) merged[23:16] = new_word[23:16];
            if (write_strobe[3]) merged[31:24] = new_word[31:24];
            merge_word = merged;
        end
    endfunction

    assign imem_addr_in_range =
        (imem_req_addr >= RESET_VECTOR) &&
        ((imem_req_addr - RESET_VECTOR) < MEM_BYTES);
    assign dmem_addr_in_range =
        (dmem_req_addr >= RESET_VECTOR) &&
        ((dmem_req_addr - RESET_VECTOR) < MEM_BYTES);

    assign imem_req_ready = !rst && !imem_pending_q;
    assign imem_rsp_valid = !rst && imem_pending_q;
    assign imem_rsp_data  = imem_rsp_data_q;
    assign imem_rsp_error = imem_rsp_error_q;

    assign dmem_req_ready = !rst && !dmem_pending_q;
    assign dmem_rsp_valid = !rst && dmem_pending_q;
    assign dmem_rsp_rdata = dmem_rsp_data_q;
    assign dmem_rsp_error = dmem_rsp_error_q;

    assign imem_request_fire  = imem_req_valid && imem_req_ready;
    assign imem_response_fire = imem_rsp_valid && imem_rsp_ready;
    assign dmem_request_fire  = dmem_req_valid && dmem_req_ready;
    assign dmem_response_fire = dmem_rsp_valid && dmem_rsp_ready;

    assign cp_req_ready = 1'b1;
    assign cp_rsp_valid = 1'b0;
    assign cp_rsp_data  = 32'b0;
    assign cp_rsp_error = 1'b0;

    rv32_core #(
        .RESET_VECTOR  (RESET_VECTOR),
        .MTVEC_RESET   (MTVEC_RESET),
        .COPROC_ENABLE (1'b0)
    ) dut (
        .clk             (clk),
        .rst             (rst),
        .irq_software    (1'b0),
        .irq_timer       (1'b0),
        .irq_external    (1'b0),
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

    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        if (rst) begin
            imem_pending_q   <= 1'b0;
            imem_rsp_data_q  <= 32'b0;
            imem_rsp_error_q <= 1'b0;
        end else begin
            if (imem_response_fire) begin
                imem_pending_q <= 1'b0;
            end

            if (imem_request_fire) begin
                imem_pending_q <= 1'b1;
                if (imem_addr_in_range && (imem_req_addr[1:0] == 2'b00)) begin
                    imem_rsp_data_q <=
                        imem_words[(imem_req_addr - RESET_VECTOR) >> 2];
                    imem_rsp_error_q <= 1'b0;
                end else begin
                    imem_rsp_data_q  <= 32'b0;
                    imem_rsp_error_q <= 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            dmem_pending_q   <= 1'b0;
            dmem_rsp_data_q  <= 32'b0;
            dmem_rsp_error_q <= 1'b0;
            dmem_txn_pc_q    <= 32'b0;
            dmem_txn_instr_q <= 32'b0;
            finish_pending_q <= 1'b0;
            finish_pc_q      <= 32'b0;
            finish_instr_q   <= 32'b0;
            tohost_value_q   <= 32'b0;
        end else begin
            if (dmem_response_fire) begin
                dmem_pending_q <= 1'b0;
            end

            if (dmem_request_fire) begin
                dmem_pending_q   <= 1'b1;
                dmem_txn_pc_q    <= dut.ex_mem_active_candidate.pc;
                dmem_txn_instr_q <= dut.ex_mem_active_candidate.instruction;

                if (dmem_addr_in_range) begin
                    dmem_rsp_error_q <= 1'b0;
                    dmem_rsp_data_q <=
                        dmem_words[(dmem_req_addr - RESET_VECTOR) >> 2];

                    if (dmem_req_write) begin
                        dmem_words[(dmem_req_addr - RESET_VECTOR) >> 2] <=
                            merge_word(
                                dmem_words[
                                    (dmem_req_addr - RESET_VECTOR) >> 2
                                ],
                                dmem_req_wdata,
                                dmem_req_wstrb
                            );

                        if ((dmem_req_addr & 32'hffff_fffc) == tohost_addr) begin
                            tohost_value_q <= merge_word(
                                dmem_words[
                                    (dmem_req_addr - RESET_VECTOR) >> 2
                                ],
                                dmem_req_wdata,
                                dmem_req_wstrb
                            );
                            finish_pending_q <= 1'b1;
                            finish_pc_q <= dut.ex_mem_active_candidate.pc;
                            finish_instr_q <=
                                dut.ex_mem_active_candidate.instruction;
                        end
                    end
                end else begin
                    dmem_rsp_data_q  <= 32'b0;
                    dmem_rsp_error_q <= 1'b1;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (!rst) begin
            cycle_count = cycle_count + 1;

            if (retire_valid) begin
                $fdisplay(
                    trace_fd,
                    "{\"kind\":\"retire\",\"order\":%0d,\"cycle\":%0d,\"pc\":\"0x%08x\",\"insn\":\"0x%08x\",\"rd_we\":%0d,\"rd_addr\":%0d,\"rd_data\":\"0x%08x\"}",
                    arch_order,
                    cycle_count,
                    retire_pc,
                    retire_instr,
                    retire_rd_we,
                    retire_rd_addr,
                    retire_rd_data
                );
                arch_order = arch_order + 1;
                retire_count = retire_count + 1;
            end

            if (trap_valid) begin
                $fdisplay(
                    trace_fd,
                    "{\"kind\":\"trap\",\"order\":%0d,\"cycle\":%0d,\"pc\":\"0x%08x\",\"cause\":\"0x%08x\",\"value\":\"0x%08x\"}",
                    arch_order,
                    cycle_count,
                    trap_pc,
                    trap_cause,
                    trap_value
                );
                arch_order = arch_order + 1;
                trap_count = trap_count + 1;
            end

            if (dmem_request_fire) begin
                $fdisplay(
                    trace_fd,
                    "{\"kind\":\"memory\",\"order\":%0d,\"cycle\":%0d,\"pc\":\"0x%08x\",\"insn\":\"0x%08x\",\"write\":%0d,\"addr\":\"0x%08x\",\"wdata\":\"0x%08x\",\"wstrb\":\"0x%01x\"}",
                    memory_order,
                    cycle_count,
                    dut.ex_mem_active_candidate.pc,
                    dut.ex_mem_active_candidate.instruction,
                    dmem_req_write,
                    dmem_req_addr,
                    dmem_req_wdata,
                    dmem_req_wstrb
                );
                memory_order = memory_order + 1;
            end

            if (dmem_response_fire) begin
                $fdisplay(
                    trace_fd,
                    "{\"kind\":\"memory_response\",\"cycle\":%0d,\"pc\":\"0x%08x\",\"insn\":\"0x%08x\",\"error\":%0d,\"rdata\":\"0x%08x\"}",
                    cycle_count,
                    dmem_txn_pc_q,
                    dmem_txn_instr_q,
                    dmem_rsp_error,
                    dmem_rsp_rdata
                );
            end

            $fflush(trace_fd);

            if (
                retire_valid &&
                finish_pending_q &&
                (retire_pc == finish_pc_q) &&
                (retire_instr == finish_instr_q)
            ) begin
                if (tohost_value_q == 32'd1) begin
                    $fdisplay(
                        trace_fd,
                        "{\"kind\":\"summary\",\"status\":\"pass\",\"cycles\":%0d,\"retires\":%0d,\"traps\":%0d,\"tohost\":\"0x%08x\"}",
                        cycle_count,
                        retire_count,
                        trap_count,
                        tohost_value_q
                    );
                    $display(
                        "[PASS] rv32_program: cycles=%0d retires=%0d traps=%0d",
                        cycle_count,
                        retire_count,
                        trap_count
                    );
                    $fclose(trace_fd);
                    $finish;
                end else begin
                    $fdisplay(
                        trace_fd,
                        "{\"kind\":\"summary\",\"status\":\"fail\",\"cycles\":%0d,\"retires\":%0d,\"traps\":%0d,\"tohost\":\"0x%08x\"}",
                        cycle_count,
                        retire_count,
                        trap_count,
                        tohost_value_q
                    );
                    $fclose(trace_fd);
                    $fatal(1, "rv32_program: tohost failure value %08x", tohost_value_q);
                end
            end

            if (cycle_count >= max_cycles) begin
                $fdisplay(
                    trace_fd,
                    "{\"kind\":\"summary\",\"status\":\"timeout\",\"cycles\":%0d,\"retires\":%0d,\"traps\":%0d}",
                    cycle_count,
                    retire_count,
                    trap_count
                );
                $fclose(trace_fd);
                $fatal(1, "rv32_program: timeout after %0d cycles", cycle_count);
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        cycle_count = 0;
        arch_order = 0;
        memory_order = 0;
        retire_count = 0;
        trap_count = 0;
        max_cycles = 20000;
        tohost_addr = 32'h8000_1ff0;

        if ((MEM_BYTES < 4096) || ((MEM_BYTES % 4096) != 0)) begin
            $fatal(
                1,
                "rv32_program: MEM_BYTES=%0d must be a positive 4 KiB multiple",
                MEM_BYTES
            );
        end

        if (!$value$plusargs("MEM_HEX=%s", mem_hex_path)) begin
            $fatal(1, "rv32_program: +MEM_HEX=<path> is required");
        end
        if (!$value$plusargs("TRACE=%s", trace_path)) begin
            $fatal(1, "rv32_program: +TRACE=<path> is required");
        end
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) begin
            max_cycles = 20000;
        end
        if (!$value$plusargs("TOHOST=%h", tohost_addr)) begin
            tohost_addr = 32'h8000_1ff0;
        end

        for (init_index = 0; init_index < MEM_WORDS; init_index++) begin
            imem_words[init_index] = 32'b0;
            dmem_words[init_index] = 32'b0;
        end
        $readmemh(mem_hex_path, imem_words);
        $readmemh(mem_hex_path, dmem_words);

        trace_fd = $fopen(trace_path, "w");
        if (trace_fd == 0) begin
            $fatal(1, "rv32_program: cannot open trace file %s", trace_path);
        end

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
    end
endmodule
