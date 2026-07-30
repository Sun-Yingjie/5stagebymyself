module rv32_wbu (
    input  logic              rst,
    input  rv32_pkg::mem_wb_t mem_wb_q,

    output rv32_pkg::wb_bus_t wb_bus,

    output logic              retire_valid,
    output logic [31:0]       retire_pc,
    output logic [31:0]       retire_instr,
    output logic              retire_rd_we,
    output logic [4:0]        retire_rd_addr,
    output logic [31:0]       retire_rd_data
);

    import rv32_pkg::*;

    logic [31:0] write_data;

    always_comb begin
        write_data = '0;

        case (mem_wb_q.wb_ctrl.writeback_select)
            WB_EXEC:      write_data = mem_wb_q.exec_result;
            WB_LOAD:      write_data = mem_wb_q.load_result;
            WB_PC_PLUS_4: write_data = mem_wb_q.pc_plus_4;
            WB_CSR:       write_data = mem_wb_q.csr_read_data;
            default:      write_data = '0;
        endcase
    end

    always_comb begin
        wb_bus = '0;

        // MEM owns exception qualification; WBU consumes the qualified valid bit.
        wb_bus.valid           = !rst && mem_wb_q.valid;
        wb_bus.rd_write_enable = mem_wb_q.wb_ctrl.register_write;
        wb_bus.rd_addr         = mem_wb_q.rd_addr;
        wb_bus.rd_data         = write_data;
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

endmodule
