package rv32_tb_pkg;
    import rv32_pkg::*;

    localparam logic [31:0] RV32_NOP = 32'h0000_0013;
    
// r-type
    function automatic logic [31:0] encoder_r(
        input logic [2:0] funct3,
        input logic [6:0] funct7,
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input logic [4:0] rs2
    );
        encoder_r = {
            funct7,
            rs2,
            rs1,
            funct3,
            rd,
            OPCODE_OP
        };
    endfunction
// i_load-0000011 i_calculate-0010011 i_jalr-1100111
    function automatic logic [31:0] encoder_i(
        input logic [ 6:0] opcode,
        input logic [ 2:0] funct3,
        input logic [ 4:0] rd,
        input logic [ 4:0] rs1,
        input logic [31:0] immediate
    );
        encoder_i = {
            immediate[11:0],
            rs1,
            funct3,
            rd,
            opcode
        };
    endfunction
// store
    function automatic logic [31:0] encoder_s(
        input logic [2:0] funct3,
        input logic [4:0] rs1,
        input logic [4:0] rs2,
        input logic [31:0] immediate
    );
        encoder_s = {
            immediate[11:5],
            rs2,
            rs1,
            funct3,
            immediate[4:0],
            OPCODE_STORE
        };
    endfunction
// branch
    function automatic logic [31:0] encoder_b(
        input logic [2:0] funct3,
        input logic [4:0] rs1,
        input logic [4:0] rs2,
        input logic [31:0] immediate
    );
        encoder_b = {
            immediate[12],
            immediate[10:5],
            rs2,
            rs1,
            funct3,
            immediate[4:1],
            immediate[11],
            OPCODE_BRANCH
        };
    endfunction
// lui-0110111 auipc-0010111
    function automatic logic [31:0] encoder_u(
        input logic [6:0] opcode,
        input logic [4:0] rd,
        input logic [31:0] immediate
    );
        encoder_u = {
            immediate[31:12],
            rd,
            opcode
        };
    endfunction
// jal
    function automatic logic [31:0] encoder_j(
        input logic [ 4:0] rd,
        input logic [31:0] immediate
    );
        encoder_j = {
            immediate[20],
            immediate[10:1],
            immediate[11],
            immediate[19:12],
            rd,
            OPCODE_JAL
        };
    endfunction

    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] instruction;
        logic        rd_we;
        logic [4:0]  rd_addr;
        logic [31:0] rd_data;
    } expected_retire_t;
    typedef struct packed {
        logic        write;
        logic [31:0] addr;
        logic [31:0] wdata;
        logic [3:0]  wstrb;
    } expected_dmem_request_t;
endpackage
