package rv32_pkg;
// opcode
    localparam logic [6:0] OPCODE_LUI       = 7'b011_0111;
    localparam logic [6:0] OPCODE_AUIPC     = 7'b001_0111;
    localparam logic [6:0] OPCODE_JAL       = 7'b110_1111;
    localparam logic [6:0] OPCODE_JALR      = 7'b110_0111;
    localparam logic [6:0] OPCODE_BRANCH    = 7'b110_0011;
    localparam logic [6:0] OPCODE_LOAD      = 7'b000_0011;
    localparam logic [6:0] OPCODE_STORE     = 7'b010_0011;
    localparam logic [6:0] OPCODE_MISC_MEM  = 7'b000_1111;
    localparam logic [6:0] OPCODE_OP_IMM    = 7'b001_0011;
    localparam logic [6:0] OPCODE_OP        = 7'b011_0011;
    localparam logic [6:0] OPCODE_SYSTEM    = 7'b111_0011;
// full instruction encodings
    localparam logic [31:0] INSTRUCTION_ECALL  = 32'h0000_0073;
    localparam logic [31:0] INSTRUCTION_EBREAK = 32'h0010_0073;
// funct7
    localparam logic [6:0] FUNCT7_BASE      = 7'b000_0000;
    localparam logic [6:0] FUNCT7_SUB_SRA   = 7'b010_0000;
// funct3
    // arithmetic logic operation
    localparam logic [2:0] FUNCT3_ADD_SUB   = 3'b000;
    localparam logic [2:0] FUNCT3_SLL       = 3'b001;
    localparam logic [2:0] FUNCT3_SLT       = 3'b010;
    localparam logic [2:0] FUNCT3_SLTU      = 3'b011;
    localparam logic [2:0] FUNCT3_XOR       = 3'b100;
    localparam logic [2:0] FUNCT3_SRL_SRA   = 3'b101;
    localparam logic [2:0] FUNCT3_OR        = 3'b110;
    localparam logic [2:0] FUNCT3_AND       = 3'b111;
    // branch
    localparam logic [2:0] FUNCT3_BEQ       = 3'b000;
    localparam logic [2:0] FUNCT3_BNE       = 3'b001;
    localparam logic [2:0] FUNCT3_BLT       = 3'b100;
    localparam logic [2:0] FUNCT3_BGE       = 3'b101;
    localparam logic [2:0] FUNCT3_BLTU      = 3'b110;
    localparam logic [2:0] FUNCT3_BGEU      = 3'b111;
    // load/store
    localparam logic [2:0] FUNCT3_LB        = 3'b000;
    localparam logic [2:0] FUNCT3_LH        = 3'b001;
    localparam logic [2:0] FUNCT3_LW        = 3'b010;
    localparam logic [2:0] FUNCT3_LBU       = 3'b100;
    localparam logic [2:0] FUNCT3_LHU       = 3'b101;
    localparam logic [2:0] FUNCT3_SB        = 3'b000;
    localparam logic [2:0] FUNCT3_SH        = 3'b001;
    localparam logic [2:0] FUNCT3_SW        = 3'b010;
    // memory ordering
    localparam logic [2:0] FUNCT3_FENCE     = 3'b000;
    // jalr
    localparam logic [2:0] FUNCT3_JALR      = 3'b000;
    // CSR
    localparam logic [2:0] FUNCT3_CSRRW     = 3'b001;
    localparam logic [2:0] FUNCT3_CSRRS     = 3'b010;
    localparam logic [2:0] FUNCT3_CSRRC     = 3'b011;
    localparam logic [2:0] FUNCT3_CSRRWI    = 3'b101;
    localparam logic [2:0] FUNCT3_CSRRSI    = 3'b110;
    localparam logic [2:0] FUNCT3_CSRRCI    = 3'b111;
// exception
    localparam logic [31:0] EXCEPTION_CAUSE_INSTRUCTION_ADDRESS_MISALIGNED  = 32'd0;
    localparam logic [31:0] EXCEPTION_CAUSE_INSTRUCTION_ACCESS_FAULT        = 32'd1;
    localparam logic [31:0] EXCEPTION_CAUSE_ILLEGAL_INSTRUCTION             = 32'd2;
    localparam logic [31:0] EXCEPTION_CAUSE_BREAKPOINT                      = 32'd3;
    localparam logic [31:0] EXCEPTION_CAUSE_LOAD_ADDRESS_MISALIGNED         = 32'd4;
    localparam logic [31:0] EXCEPTION_CAUSE_LOAD_ACCESS_FAULT               = 32'd5;
    localparam logic [31:0] EXCEPTION_CAUSE_STORE_ADDRESS_MISALIGNED        = 32'd6;
    localparam logic [31:0] EXCEPTION_CAUSE_STORE_ACCESS_FAULT              = 32'd7;
    localparam logic [31:0] EXCEPTION_CAUSE_ENVIRONMENT_CALL_M_MODE         = 32'd11;
// pipeline control
    typedef enum logic [1:0] {  // how to update pipeline reg
        PIPE_LOAD           = 2'b00, // update
        PIPE_HOLD           = 2'b01, // keep
        PIPE_CLEAR          = 2'b10  // valid = 0
    } pipe_action_e;

// fetch control
    typedef enum logic [1:0] { // how to update pc reg
        FETCH_RESET         = 2'b00,    // back to RESET_VECTOR
        FETCH_HOLD          = 2'b01,    // keep current pc
        FETCH_SEQUENTIAL    = 2'b10,    // pc = next pc, which means ifu fetch a valid instruction and there is no redirection, so ifu will use pc plus 4 for the next fetch.
        FETCH_REDIRECT      = 2'b11     // pc redirect, include branch, jump and trap
    } fetch_action_e;

// decode control
    typedef enum logic [2:0] { // sel immediate extend
        IMM_NONE            = 3'b000,
        IMM_I               = 3'b001,
        IMM_S               = 3'b010,
        IMM_B               = 3'b011,
        IMM_U               = 3'b100,
        IMM_J               = 3'b101
    } immediate_type_e; // o-decoder, i-imm_gen

// execute control
    typedef enum logic [1:0] { // sel alu opa
        OPA_RS1             = 2'b00,
        OPA_PC              = 2'b01,
        OPA_ZERO            = 2'b10
    } operand_a_select_e;

    typedef enum logic { // sel alu opb
        OPB_RS2             = 1'b0,
        OPB_IMMEDIATE       = 1'b1
    } operand_b_select_e;

    typedef enum logic [3:0] { // sel alu op
        ALU_ADD             = 4'b0000,
        ALU_SUB             = 4'b0001,
        ALU_SLL             = 4'b0010,
        ALU_SLT             = 4'b0011,
        ALU_SLTU            = 4'b0100,
        ALU_XOR             = 4'b0101,
        ALU_SRL             = 4'b0110,
        ALU_SRA             = 4'b0111,
        ALU_OR              = 4'b1000,
        ALU_AND             = 4'b1001
    } alu_operation_e;

    typedef enum logic [2:0] { // sel branch compare
        BR_NONE             = 3'b000,
        BR_EQ               = 3'b001,
        BR_NE               = 3'b010,
        BR_LT               = 3'b011,
        BR_GE               = 3'b100,
        BR_LTU              = 3'b101,
        BR_GEU              = 3'b110
    } branch_operation_e;

// CSR control
    localparam logic [11:0] CSR_ADDR_MSTATUS    = 12'h300;
    localparam logic [11:0] CSR_ADDR_MISA       = 12'h301;
    localparam logic [11:0] CSR_ADDR_MTVEC      = 12'h305;
    localparam logic [11:0] CSR_ADDR_MSCRATCH   = 12'h340;
    localparam logic [11:0] CSR_ADDR_MEPC       = 12'h341;
    localparam logic [11:0] CSR_ADDR_MCAUSE     = 12'h342;
    localparam logic [11:0] CSR_ADDR_MTVAL      = 12'h343;
    localparam logic [11:0] CSR_ADDR_MVENDORID  = 12'hF11;
    localparam logic [11:0] CSR_ADDR_MARCHID    = 12'hF12;
    localparam logic [11:0] CSR_ADDR_MIMPID     = 12'hF13;
    localparam logic [11:0] CSR_ADDR_MHARTID    = 12'hF14;
    localparam logic [11:0] CSR_ADDR_MCONFIGPTR = 12'hF15;

    typedef enum logic [1:0] { // select CSR read-modify-write operation
        CSR_WRITE           = 2'b00,
        CSR_SET             = 2'b01,
        CSR_CLEAR           = 2'b10
    } csr_operation_e;

    typedef struct packed { // decoded Zicsr instruction semantics
        logic           valid;
        csr_operation_e operation;
        logic           use_immediate;
        logic           read_enable;
        logic           write_enable;
    } csr_ctrl_t;

    typedef enum logic [1:0] { // sel rs source
        FWD_REG             = 2'b00, // from regfile
        FWD_EX_MEM          = 2'b01, // from ex/mem
        FWD_MEM_WB          = 2'b10  // from mem/wb
    } forward_select_e;

// memory control
    typedef enum logic [1:0] { // load/store width
        MEM_SIZE_BYTE       = 2'b00, // LB, LBU, SB
        MEM_SIZE_HALF       = 2'b01, // LH, LHU, SH
        MEM_SIZE_WORD       = 2'b10  // LW ,SW 
    } memory_size_e;

// write back control
    typedef enum logic [1:0] {  // sel write back source
        WB_EXEC             = 2'b00,
        WB_LOAD             = 2'b01,
        WB_PC_PLUS_4        = 2'b10,
        WB_CSR              = 2'b11
    } writeback_select_e;

// stage need package
    typedef struct packed { // execute stage need
        operand_a_select_e operand_a_select;
        operand_b_select_e operand_b_select;
        alu_operation_e    alu_operation;
        branch_operation_e branch_operation;
        logic              is_jump;
        logic              is_jalr;
    } ex_ctrl_t;

    typedef struct packed { // memory stage need
        logic         memory_read;
        logic         memory_write;
        memory_size_e memory_size;
        logic         load_unsigned;
    } mem_ctrl_t;

    typedef struct packed { // write back stage need
        logic              register_write;
        writeback_select_e writeback_select;
    } wb_ctrl_t;

    typedef struct packed { // decode stage need
        logic            uses_rs1;
        logic            uses_rs2;
        immediate_type_e immediate_type;
        logic            illegal_instruction;
        logic            environment_call;
        logic            breakpoint;
        csr_ctrl_t       csr_ctrl;
        ex_ctrl_t        ex_ctrl;
        mem_ctrl_t       mem_ctrl;
        wb_ctrl_t        wb_ctrl;
    } decode_ctrl_t;

    typedef struct packed { // exception info
        logic        valid;
        logic [31:0] cause;
        logic [31:0] value;
    } exception_t;

// pipeline reg package
    typedef struct packed { // IF/ID reg
        logic        valid;
        logic [31:0] pc;
        logic [31:0] instruction;
        logic [31:0] pc_plus_4; // jal, jalr writeback
        exception_t  exception;
    } if_id_t;

    typedef struct packed { // ID/EX reg
        logic        valid;
        logic [31:0] pc;
        logic [31:0] instruction;
        logic [31:0] pc_plus_4;

        logic [4:0]  rs1_addr;
        logic [4:0]  rs2_addr;
        logic [4:0]  rd_addr;
        logic [31:0] rs1_data;
        logic [31:0] rs2_data;
        logic        uses_rs1;
        logic        uses_rs2;

        logic [31:0] immediate;

        csr_ctrl_t  csr_ctrl;
        logic [11:0] csr_address;

        ex_ctrl_t    ex_ctrl;
        mem_ctrl_t   mem_ctrl;
        wb_ctrl_t    wb_ctrl;
        exception_t  exception;
    } id_ex_t;

    typedef struct packed { // EX/MEM reg
        logic        valid;
        logic [31:0] pc;
        logic [31:0] instruction;
        logic [31:0] pc_plus_4;

        logic [31:0] exec_result;
        logic [31:0] store_data;
        csr_ctrl_t   csr_ctrl;
        logic [11:0] csr_address;
        logic [31:0] csr_source;
        logic [4:0]  rd_addr;

        mem_ctrl_t   mem_ctrl;
        wb_ctrl_t    wb_ctrl;
        exception_t  exception;
    } ex_mem_t;

    typedef struct packed { // MEM/WB reg
        logic        valid;
        logic [31:0] pc;
        logic [31:0] instruction;
        logic [31:0] pc_plus_4;

        logic [31:0] exec_result;
        logic [31:0] load_result;
        logic [31:0] csr_read_data;
        logic [4:0]  rd_addr;

        wb_ctrl_t    wb_ctrl;
        exception_t  exception;
    } mem_wb_t;

    typedef struct packed {
        logic        valid;
        logic        rd_write_enable;
        logic [4:0]  rd_addr;
        logic [31:0] rd_data;
    } wb_bus_t;

    typedef struct packed {
        logic        valid;
        logic [31:0] target;
    } redirect_t;
endpackage
