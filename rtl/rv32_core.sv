module rv32_core #(
    parameter logic [31:0] RESET_VECTOR  = 32'h0000_0000,
    parameter bit          COPROC_ENABLE = 1'b0
) (
    input  logic        clk,
    input  logic        rst,

    output logic        imem_req_valid,
    input  logic        imem_req_ready,
    output logic [31:0] imem_req_addr,
    input  logic        imem_rsp_valid,
    output logic        imem_rsp_ready,
    input  logic [31:0] imem_rsp_data,
    input  logic        imem_rsp_error,

    output logic        dmem_req_valid,
    input  logic        dmem_req_ready,
    output logic        dmem_req_write,
    output logic [31:0] dmem_req_addr,
    output logic [31:0] dmem_req_wdata,
    output logic [3:0]  dmem_req_wstrb,
    input  logic        dmem_rsp_valid,
    output logic        dmem_rsp_ready,
    input  logic [31:0] dmem_rsp_rdata,
    input  logic        dmem_rsp_error,

    output logic        retire_valid,
    output logic [31:0] retire_pc,
    output logic [31:0] retire_instr,
    output logic        retire_rd_we,
    output logic [4:0]  retire_rd_addr,
    output logic [31:0] retire_rd_data,

    output logic        cp_req_valid,
    input  logic        cp_req_ready,
    output logic [31:0] cp_req_pc,
    output logic [31:0] cp_req_instr,
    output logic [31:0] cp_req_rs1_data,
    output logic [31:0] cp_req_rs2_data,
    input  logic        cp_rsp_valid,
    output logic        cp_rsp_ready,
    input  logic [31:0] cp_rsp_data,
    input  logic        cp_rsp_error
);

    import rv32_pkg::*;

    // Pipeline state
    if_id_t  if_id_q;
    if_id_t  if_id_d;
    if_id_t  if_id_candidate;

    id_ex_t  id_ex_q;
    id_ex_t  id_ex_d;
    id_ex_t  id_ex_candidate;

    ex_mem_t ex_mem_q;
    ex_mem_t ex_mem_d;
    ex_mem_t ex_mem_candidate;
    ex_mem_t ex_mem_active_candidate;

    mem_wb_t mem_wb_q;
    mem_wb_t mem_wb_d;
    mem_wb_t mem_wb_candidate;

    // Stage interconnect and global control
    wb_bus_t    wb_bus;
    redirect_t  ex_raw_redirect;
    redirect_t  raw_redirect;
    redirect_t  qualified_redirect;
    exception_t lsu_exception;
    exception_t mem_exception;

    // Preserve the complete EX candidate while ID/EX is held.
    logic      ex_hold_valid_q;
    ex_mem_t   ex_mem_hold_q;
    redirect_t ex_redirect_hold_q;

    fetch_action_e fetch_action;
    pipe_action_e  if_id_action;
    pipe_action_e  id_ex_action;
    pipe_action_e  ex_mem_action;
    pipe_action_e  mem_wb_action;

    forward_select_e rs1_forward_select;
    forward_select_e rs2_forward_select;

    logic fetch_response_available;
    logic late_result_hazard;
    logic ex_request_block;
    logic ex_request_wait;
    logic mem_response_wait;
    logic redirect_commit;
    logic if_id_ready;

    logic [31:0] ex_mem_forward_value;
    logic [31:0] mem_wb_forward_value;
    logic [31:0] wb_write_data;
    logic [31:0] lsu_load_result;

    // Flattened control fields keep Icarus port widths unambiguous.
    logic id_ex_result_late;
    logic ex_mem_register_write;
    logic ex_mem_result_late;
    logic mem_wb_register_write;

    // Writeback and retirement
    always_comb begin
        wb_write_data = '0;

        case (mem_wb_q.wb_ctrl.writeback_select)
            WB_EXEC:      wb_write_data = mem_wb_q.exec_result;
            WB_LOAD:      wb_write_data = mem_wb_q.load_result;
            WB_PC_PLUS_4: wb_write_data = mem_wb_q.pc_plus_4;
            WB_CSR:       wb_write_data = mem_wb_q.csr_read_data;
            default:      wb_write_data = '0;
        endcase
    end

    always_comb begin
        wb_bus = '0;

        wb_bus.valid           = !rst && mem_wb_q.valid;
        wb_bus.rd_write_enable = mem_wb_q.wb_ctrl.register_write;
        wb_bus.rd_addr         = mem_wb_q.rd_addr;
        wb_bus.rd_data         = wb_write_data;
    end

    assign retire_valid   = wb_bus.valid;
    assign retire_pc      = mem_wb_q.pc;
    assign retire_instr   = mem_wb_q.instruction;
    assign retire_rd_we   =
        retire_valid &&
        wb_bus.rd_write_enable &&
        (wb_bus.rd_addr != '0);
    assign retire_rd_addr = wb_bus.rd_addr;
    assign retire_rd_data = wb_bus.rd_data;

    // Forwarding datapath
    assign id_ex_result_late =
        id_ex_q.mem_ctrl.memory_read || id_ex_q.csr_ctrl.valid;
    assign ex_mem_register_write = ex_mem_q.wb_ctrl.register_write;
    assign ex_mem_result_late =
        ex_mem_q.mem_ctrl.memory_read || ex_mem_q.csr_ctrl.valid;
    assign mem_wb_register_write = mem_wb_q.wb_ctrl.register_write;

    assign mem_wb_forward_value = wb_write_data;

    always_comb begin
        ex_mem_active_candidate = ex_mem_candidate;

        if (ex_hold_valid_q) begin
            ex_mem_active_candidate = ex_mem_hold_q;
        end
    end

    assign raw_redirect =
        ex_hold_valid_q ? ex_redirect_hold_q : ex_raw_redirect;

    // The final MEM exception path will drive this qualification when the
    // standalone CSR/trap owner is integrated. Keep v0.1 behavior unchanged.
    assign ex_request_block = 1'b0;

    always_comb begin
        ex_mem_forward_value = '0;

        case (ex_mem_q.wb_ctrl.writeback_select)
            WB_EXEC: begin
                ex_mem_forward_value = ex_mem_q.exec_result;
            end

            WB_PC_PLUS_4: begin
                ex_mem_forward_value = ex_mem_q.pc_plus_4;
            end

            default: begin
                ex_mem_forward_value = '0;
            end
        endcase
    end

    // Frontend control
    assign if_id_ready = (if_id_action == PIPE_LOAD);

    assign qualified_redirect.valid =
        redirect_commit && raw_redirect.valid;
    assign qualified_redirect.target = raw_redirect.target;

    // Coprocessor is disabled in v0.1.
    assign cp_req_valid    = 1'b0;
    assign cp_req_pc       = '0;
    assign cp_req_instr    = '0;
    assign cp_req_rs1_data = '0;
    assign cp_req_rs2_data = '0;
    assign cp_rsp_ready    = 1'b0;

    // Pipeline stage modules
    rv32_ifu #(
        .RESET_VECTOR (RESET_VECTOR)
    ) u_ifu (
        .clk                      (clk),
        .rst                      (rst),
        .fetch_action             (fetch_action),
        .qualified_redirect       (qualified_redirect),
        .if_id_ready              (if_id_ready),
        .imem_req_valid           (imem_req_valid),
        .imem_req_ready           (imem_req_ready),
        .imem_req_addr            (imem_req_addr),
        .imem_rsp_valid           (imem_rsp_valid),
        .imem_rsp_ready           (imem_rsp_ready),
        .imem_rsp_data            (imem_rsp_data),
        .imem_rsp_error           (imem_rsp_error),
        .if_id_candidate          (if_id_candidate),
        .fetch_response_available (fetch_response_available)
    );

    rv32_idu u_idu (
        .clk             (clk),
        .if_id_q         (if_id_q),
        .wb_bus          (wb_bus),
        .id_ex_candidate (id_ex_candidate)
    );

    rv32_exu u_exu (
        .id_ex_q             (id_ex_q),
        .rs1_forward_select  (rs1_forward_select),
        .rs2_forward_select  (rs2_forward_select),
        .ex_mem_forward_value(ex_mem_forward_value),
        .mem_wb_forward_value(mem_wb_forward_value),
        .ex_mem_candidate    (ex_mem_candidate),
        .raw_redirect        (ex_raw_redirect)
    );

    rv32_lsu u_lsu (
        .clk              (clk),
        .rst              (rst),
        .ex_mem_candidate (ex_mem_active_candidate),
        .ex_mem_q         (ex_mem_q),
        .ex_request_block (ex_request_block),
        .dmem_req_valid   (dmem_req_valid),
        .dmem_req_ready   (dmem_req_ready),
        .dmem_req_write   (dmem_req_write),
        .dmem_req_addr    (dmem_req_addr),
        .dmem_req_wdata   (dmem_req_wdata),
        .dmem_req_wstrb   (dmem_req_wstrb),
        .dmem_rsp_valid   (dmem_rsp_valid),
        .dmem_rsp_ready   (dmem_rsp_ready),
        .dmem_rsp_rdata   (dmem_rsp_rdata),
        .dmem_rsp_error   (dmem_rsp_error),
        .ex_request_wait  (ex_request_wait),
        .mem_response_wait(mem_response_wait),
        .load_result      (lsu_load_result),
        .lsu_exception    (lsu_exception),
        .mem_wb_candidate (mem_wb_candidate),
        .mem_exception    (mem_exception)
    );

    // Hazard detection and global pipeline control
    rv32_forward_unit u_forward_unit (
        // Current ID-stage consumer for late-result detection
        .id_valid              (id_ex_candidate.valid),
        .id_rs1_addr           (id_ex_candidate.rs1_addr),
        .id_rs2_addr           (id_ex_candidate.rs2_addr),
        .id_uses_rs1           (id_ex_candidate.uses_rs1),
        .id_uses_rs2           (id_ex_candidate.uses_rs2),

        // Current EX-stage consumer
        .ex_valid              (id_ex_q.valid),
        .ex_rs1_addr           (id_ex_q.rs1_addr),
        .ex_rs2_addr           (id_ex_q.rs2_addr),
        .ex_uses_rs1           (id_ex_q.uses_rs1),
        .ex_uses_rs2           (id_ex_q.uses_rs2),
        .ex_rd_addr            (id_ex_q.rd_addr),
        .ex_result_late        (id_ex_result_late),

        // MEM- and WB-stage producers
        .ex_mem_valid          (ex_mem_q.valid),
        .ex_mem_rd_addr        (ex_mem_q.rd_addr),
        .ex_mem_register_write (ex_mem_register_write),
        .ex_mem_result_late    (ex_mem_result_late),
        .mem_wb_valid          (mem_wb_q.valid),
        .mem_wb_rd_addr        (mem_wb_q.rd_addr),
        .mem_wb_register_write (mem_wb_register_write),

        .rs1_forward_select    (rs1_forward_select),
        .rs2_forward_select    (rs2_forward_select),
        .late_result_hazard    (late_result_hazard)
    );

    rv32_pipeline_ctrl u_pipeline_ctrl (
        .rst                     (rst),
        .trap_take               (1'b0),
        .mem_response_wait       (mem_response_wait),
        .ex_request_wait         (ex_request_wait),
        .ex_multicycle_wait      (1'b0),
        .raw_redirect_valid      (raw_redirect.valid),
        .late_result_hazard      (late_result_hazard),
        .fetch_response_available(fetch_response_available),
        .fetch_action            (fetch_action),
        .if_id_action            (if_id_action),
        .id_ex_action            (id_ex_action),
        .ex_mem_action           (ex_mem_action),
        .mem_wb_action           (mem_wb_action),
        .redirect_commit         (redirect_commit)
    );

    // Pipeline next-state selection
    always_comb begin
        if_id_d  = if_id_q;
        id_ex_d  = id_ex_q;
        ex_mem_d = ex_mem_q;
        mem_wb_d = mem_wb_q;

        case (if_id_action)
            PIPE_LOAD:  if_id_d       = if_id_candidate;
            PIPE_HOLD:  if_id_d       = if_id_q;
            PIPE_CLEAR: if_id_d.valid = 1'b0;
            default:    if_id_d       = if_id_q;
        endcase

        case (id_ex_action)
            PIPE_LOAD:  id_ex_d       = id_ex_candidate;
            PIPE_HOLD:  id_ex_d       = id_ex_q;
            PIPE_CLEAR: id_ex_d.valid = 1'b0;
            default:    id_ex_d       = id_ex_q;
        endcase

        case (ex_mem_action)
            PIPE_LOAD:  ex_mem_d       = ex_mem_active_candidate;
            PIPE_HOLD:  ex_mem_d       = ex_mem_q;
            PIPE_CLEAR: ex_mem_d.valid = 1'b0;
            default:    ex_mem_d       = ex_mem_q;
        endcase

        case (mem_wb_action)
            PIPE_LOAD:  mem_wb_d       = mem_wb_candidate;
            PIPE_HOLD:  mem_wb_d       = mem_wb_q;
            PIPE_CLEAR: mem_wb_d.valid = 1'b0;
            default:    mem_wb_d       = mem_wb_q;
        endcase
    end

    // Pipeline state registers
    always_ff @(posedge clk) begin
        if (rst) begin
            if_id_q.valid  <= 1'b0;
            id_ex_q.valid  <= 1'b0;
            ex_mem_q.valid <= 1'b0;
            mem_wb_q.valid <= 1'b0;

            ex_hold_valid_q    <= 1'b0;
            ex_mem_hold_q      <= '0;
            ex_redirect_hold_q <= '0;
        end else begin
            if_id_q  <= if_id_d;
            id_ex_q  <= id_ex_d;
            ex_mem_q <= ex_mem_d;
            mem_wb_q <= mem_wb_d;

            if (
                !ex_hold_valid_q &&
                id_ex_q.valid &&
                (id_ex_action == PIPE_HOLD)
            ) begin
                ex_hold_valid_q    <= 1'b1;
                ex_mem_hold_q      <= ex_mem_candidate;
                ex_redirect_hold_q <= ex_raw_redirect;
            end else if (id_ex_action != PIPE_HOLD) begin
                ex_hold_valid_q <= 1'b0;
            end
        end
    end
endmodule
