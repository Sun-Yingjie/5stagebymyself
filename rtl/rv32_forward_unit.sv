module rv32_forward_unit (
    // 当前 ID 阶段指令，用于检测 load-use
    input  logic                            id_valid,
    input  logic [4:0]                      id_rs1_addr,
    input  logic [4:0]                      id_rs2_addr,
    input  logic                            id_uses_rs1,
    input  logic                            id_uses_rs2,

    // 当前 EX 阶段指令，即 ID/EX 中的指令
    input  logic                            ex_valid,
    input  logic [4:0]                      ex_rs1_addr,
    input  logic [4:0]                      ex_rs2_addr,
    input  logic                            ex_uses_rs1,
    input  logic                            ex_uses_rs2,
    input  logic [4:0]                      ex_rd_addr,
    input  logic                            ex_memory_read,

    // 当前 MEM 阶段指令，即 EX/MEM 中的生产者
    input  logic                            ex_mem_valid,
    input  logic [4:0]                      ex_mem_rd_addr,
    input  logic                            ex_mem_register_write,
    input  logic                            ex_mem_memory_read,

    // 当前 WB 阶段指令，即 MEM/WB 中的生产者
    input  logic                            mem_wb_valid,
    input  logic [4:0]                      mem_wb_rd_addr,
    input  logic                            mem_wb_register_write,

    output rv32_pkg::forward_select_e       rs1_forward_select,
    output rv32_pkg::forward_select_e       rs2_forward_select,
    output logic                            load_use_hazard
);

    import rv32_pkg::*;

    always_comb begin
        rs1_forward_select = FWD_REG;
        rs2_forward_select = FWD_REG;
        // rs1 forwarding
        if (ex_valid && ex_uses_rs1) begin // execute stage, rs1 valid
            if ( // ex/mem can forward
                ex_mem_valid &&
                ex_mem_register_write &&
                (ex_mem_rd_addr != 5'b0) &&
                (ex_mem_rd_addr == ex_rs1_addr)
            ) begin
                if (!ex_mem_memory_read) begin // not load
                    rs1_forward_select = FWD_EX_MEM;
                end
            end
            else if ( // mem/wb can forward, low priority
                mem_wb_valid &&
                mem_wb_register_write &&
                (mem_wb_rd_addr != 5'b0) &&
                (mem_wb_rd_addr == ex_rs1_addr)
            ) begin
                rs1_forward_select = FWD_MEM_WB;
            end
        end
        // rs2 forwarding
        if (ex_valid && ex_uses_rs2) begin // execute stage, rs2 valid
            if ( // ex/mem can forward
                ex_mem_valid &&
                ex_mem_register_write &&
                (ex_mem_rd_addr != 5'b0) &&
                (ex_mem_rd_addr == ex_rs2_addr)
            ) begin
                if (!ex_mem_memory_read) begin // not load
                    rs2_forward_select = FWD_EX_MEM;
                end
            end
            else if ( // mem/wb can forward, low priority
                mem_wb_valid &&
                mem_wb_register_write &&
                (mem_wb_rd_addr != 5'b0) &&
                (mem_wb_rd_addr == ex_rs2_addr)
            ) begin
                rs2_forward_select = FWD_MEM_WB;
            end
        end
        // load-use harzard
        load_use_hazard = // highest priority
            id_valid &&
            ex_valid &&
            ex_memory_read &&
            (ex_rd_addr != 5'b0) &&
            (
                (id_uses_rs1 && (id_rs1_addr == ex_rd_addr)) ||
                (id_uses_rs2 && (id_rs2_addr == ex_rd_addr))
            );
    end

endmodule
