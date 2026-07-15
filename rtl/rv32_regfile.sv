module rv32_regfile (
    input  logic        clk,

    input  logic [4:0]  rs1_addr,
    output logic [31:0] rs1_data,

    input  logic [4:0]  rs2_addr,
    output logic [31:0] rs2_data,

    input  logic        write_enable,
    input  logic [4:0]  write_addr,
    input  logic [31:0] write_data
);

    logic [31:0] registers [0:31];
    always_ff @(posedge clk)begin
        if(write_enable && write_addr!= '0) registers[write_addr] <= write_data;
    end
    assign rs1_data = (rs1_addr == '0) ? '0 : registers[rs1_addr];
    assign rs2_data = (rs2_addr == '0) ? '0 : registers[rs2_addr];
endmodule
