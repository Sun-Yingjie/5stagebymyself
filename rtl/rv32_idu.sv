module rv32_idu (
    input logic clk,
    input rv32_pkg::if_id_t if_id_q,
    input rv32_pkg::wb_bus_t wb_bus,
    output rv32_pkg::id_ex_t id_ex_candidate
);
    import rv32_pkg::*;

    logic [4:0] rs1_addr;
    logic [4:0] rs2_addr;
    logic [4:0] rd_addr;
    logic [31:0] rs1_regfile_data;
    logic [31:0] rs2_regfile_data;
    logic [31:0] immediate;
    logic regfile_write_enable;
    decode_ctrl_t decode_ctrl;
    logic [31:0] rs1_id_data;
    logic [31:0] rs2_id_data;
    logic        rs1_wb_bypass;
    logic        rs2_wb_bypass;
    assign rs1_addr = if_id_q.instruction[19:15];
    assign rs2_addr = if_id_q.instruction[24:20];
    assign rd_addr = if_id_q.instruction[11:7];
    assign regfile_write_enable =
        wb_bus.valid && wb_bus.rd_write_enable;
    assign rs1_wb_bypass =
        regfile_write_enable &&
        (wb_bus.rd_addr != '0) &&
        (wb_bus.rd_addr == rs1_addr);

    assign rs2_wb_bypass =
        regfile_write_enable &&
        (wb_bus.rd_addr != '0) &&
        (wb_bus.rd_addr == rs2_addr);

    assign rs1_id_data =
        rs1_wb_bypass ? wb_bus.rd_data : rs1_regfile_data;

    assign rs2_id_data =
        rs2_wb_bypass ? wb_bus.rd_data : rs2_regfile_data;
    rv32_decoder u_decoder (
        .instruction(if_id_q.instruction),
        .decode_ctrl(decode_ctrl)
    );
    rv32_imm_gen u_imm_gen (
        .instruction(if_id_q.instruction),
        .immediate_type(decode_ctrl.immediate_type),
        .immediate(immediate)
    );
    rv32_regfile u_regfile (
        .clk(clk),
        .rs1_addr(rs1_addr),
        .rs1_data(rs1_regfile_data),
        .rs2_addr(rs2_addr),
        .rs2_data(rs2_regfile_data),
        .write_enable(regfile_write_enable),
        .write_addr(wb_bus.rd_addr),
        .write_data(wb_bus.rd_data)
    );
    always_comb begin
        id_ex_candidate = '0;

        id_ex_candidate.valid       = if_id_q.valid;
        id_ex_candidate.pc          = if_id_q.pc;
        id_ex_candidate.instruction = if_id_q.instruction;
        id_ex_candidate.pc_plus_4   = if_id_q.pc_plus_4;

        id_ex_candidate.rs1_addr = rs1_addr;
        id_ex_candidate.rs2_addr = rs2_addr;
        id_ex_candidate.rd_addr  = rd_addr;
        id_ex_candidate.rs1_data = rs1_id_data;
        id_ex_candidate.rs2_data = rs2_id_data;
        id_ex_candidate.uses_rs1 = decode_ctrl.uses_rs1;
        id_ex_candidate.uses_rs2 = decode_ctrl.uses_rs2;

        id_ex_candidate.immediate = immediate;

        id_ex_candidate.csr_ctrl = decode_ctrl.csr_ctrl;
        if (decode_ctrl.csr_ctrl.valid) begin
            id_ex_candidate.csr_address = if_id_q.instruction[31:20];
        end

        id_ex_candidate.ex_ctrl  = decode_ctrl.ex_ctrl;
        id_ex_candidate.mem_ctrl = decode_ctrl.mem_ctrl;
        id_ex_candidate.wb_ctrl  = decode_ctrl.wb_ctrl;

        id_ex_candidate.exception = if_id_q.exception;
        if (if_id_q.valid && !if_id_q.exception.valid) begin
            if (decode_ctrl.environment_call) begin
                id_ex_candidate.exception.valid = 1'b1;
                id_ex_candidate.exception.cause =
                    EXCEPTION_CAUSE_ENVIRONMENT_CALL_M_MODE;
                id_ex_candidate.exception.value = 32'b0;
            end
            else if (decode_ctrl.breakpoint) begin
                id_ex_candidate.exception.valid = 1'b1;
                id_ex_candidate.exception.cause =
                    EXCEPTION_CAUSE_BREAKPOINT;
                id_ex_candidate.exception.value = 32'b0;
            end
            else if (decode_ctrl.illegal_instruction) begin
                id_ex_candidate.exception.valid = 1'b1;
                id_ex_candidate.exception.cause =
                    EXCEPTION_CAUSE_ILLEGAL_INSTRUCTION;
                id_ex_candidate.exception.value = if_id_q.instruction;
            end
        end

        if (id_ex_candidate.exception.valid) begin
            id_ex_candidate.uses_rs1 = 1'b0;
            id_ex_candidate.uses_rs2 = 1'b0;
            id_ex_candidate.csr_ctrl = '0;
            id_ex_candidate.ex_ctrl  = '0;
            id_ex_candidate.mem_ctrl = '0;
            id_ex_candidate.wb_ctrl  = '0;
        end
    end
endmodule
