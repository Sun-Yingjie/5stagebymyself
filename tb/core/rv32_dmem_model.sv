module rv32_dmem_model #(
    parameter logic [31:0] BASE_ADDR  = 32'h0000_0000,
    parameter int unsigned BYTE_COUNT = 1024
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        request_enable,
    input  logic        response_enable,

    input  logic        dmem_req_valid,
    output logic        dmem_req_ready,
    input  logic        dmem_req_write,
    input  logic [31:0] dmem_req_addr,
    input  logic [31:0] dmem_req_wdata,
    input  logic [3:0]  dmem_req_wstrb,

    output logic        dmem_rsp_valid,
    input  logic        dmem_rsp_ready,
    output logic [31:0] dmem_rsp_rdata,
    output logic        dmem_rsp_error
);
    localparam logic [32:0] MEMORY_SIZE_BYTES = 33'(BYTE_COUNT);
    localparam logic [32:0] LAST_WORD_OFFSET =
        MEMORY_SIZE_BYTES - 33'd4;

    logic [7:0] memory [0:BYTE_COUNT-1];

    logic [31:0] request_aligned_addr;
    logic [31:0] request_offset;
    logic [32:0] request_offset_ext;
    logic        request_addr_in_range;
    int unsigned request_byte_index;

    logic        transaction_pending_q;
    logic        response_started_q;
    logic [31:0] response_data_q;
    logic        response_error_q;

    logic request_fire;
    logic response_fire;
    logic request_slot_available;

    // Request and response handshake
    assign dmem_rsp_valid =
        !rst &&
        transaction_pending_q &&
        (response_started_q || response_enable);

    assign dmem_rsp_rdata = response_data_q;
    assign dmem_rsp_error = response_error_q;

    assign response_fire =
        dmem_rsp_valid && dmem_rsp_ready;

    assign request_slot_available =
        !transaction_pending_q || response_fire;

    assign dmem_req_ready =
        !rst &&
        request_enable &&
        request_slot_available;

    assign request_fire =
        dmem_req_valid && dmem_req_ready;

    // Requests use byte addresses; memory data is returned as an aligned word.
    assign request_aligned_addr =
        dmem_req_addr - {30'b0, dmem_req_addr[1:0]};

    assign request_offset_ext =
        {1'b0, request_aligned_addr} - {1'b0, BASE_ADDR};

    assign request_addr_in_range =
        request_offset_ext <= LAST_WORD_OFFSET;

    assign request_offset =
        request_offset_ext[31:0];

    assign request_byte_index =
        request_offset;

    // Transaction state and write side effects
    always_ff @(posedge clk) begin
        if (rst) begin
            transaction_pending_q <= 1'b0;
            response_started_q    <= 1'b0;
            response_data_q       <= '0;
            response_error_q      <= 1'b0;
        end else begin
            if (
                transaction_pending_q &&
                response_enable
            ) begin
                response_started_q <= 1'b1;
            end

            if (response_fire) begin
                transaction_pending_q <= 1'b0;
                response_started_q    <= 1'b0;
            end

            if (request_fire) begin
                transaction_pending_q <= 1'b1;
                response_started_q    <= 1'b0;
                response_data_q       <= '0;
                response_error_q      <= !request_addr_in_range;

                if (request_addr_in_range) begin
                    if (dmem_req_write) begin
                        if (dmem_req_wstrb[0]) begin
                            memory[request_byte_index] <=
                                dmem_req_wdata[7:0];
                        end

                        if (dmem_req_wstrb[1]) begin
                            memory[request_byte_index + 1] <=
                                dmem_req_wdata[15:8];
                        end

                        if (dmem_req_wstrb[2]) begin
                            memory[request_byte_index + 2] <=
                                dmem_req_wdata[23:16];
                        end

                        if (dmem_req_wstrb[3]) begin
                            memory[request_byte_index + 3] <=
                                dmem_req_wdata[31:24];
                        end
                    end else begin
                        response_data_q <= {
                            memory[request_byte_index + 3],
                            memory[request_byte_index + 2],
                            memory[request_byte_index + 1],
                            memory[request_byte_index]
                        };
                    end
                end
            end
        end
    end

    // Data loading and inspection helpers
    task automatic clear_memory(
        input logic [7:0] fill_byte
    );
        int unsigned byte_index;
        begin
            for (
                byte_index = 0;
                byte_index < BYTE_COUNT;
                byte_index++
            ) begin
                memory[byte_index] = fill_byte;
            end
        end
    endtask

    task automatic write_byte(
        input logic [31:0] address,
        input logic [7:0]  data
    );
        logic [32:0] offset;
        begin
            offset = {1'b0, address} - {1'b0, BASE_ADDR};

            if (offset >= MEMORY_SIZE_BYTES) begin
                $fatal(
                    1,
                    "rv32_dmem_model: byte address %08h is out of range",
                    address
                );
            end

            memory[offset[31:0]] = data;
        end
    endtask

    task automatic write_word(
        input logic [31:0] address,
        input logic [31:0] data
    );
        logic [31:0] offset;
        begin
            offset = checked_word_offset(address);

            memory[offset]     = data[7:0];
            memory[offset + 1] = data[15:8];
            memory[offset + 2] = data[23:16];
            memory[offset + 3] = data[31:24];
        end
    endtask

    function automatic logic [31:0] read_word(
        input logic [31:0] address
    );
        logic [31:0] offset;
        begin
            offset = checked_word_offset(address);

            read_word = {
                memory[offset + 3],
                memory[offset + 2],
                memory[offset + 1],
                memory[offset]
            };
        end
    endfunction

    function automatic logic [31:0] checked_word_offset(
        input logic [31:0] address
    );
        logic [32:0] offset;
        begin
            offset = {1'b0, address} - {1'b0, BASE_ADDR};

            if (address[1:0] != 2'b00) begin
                $fatal(
                    1,
                    "rv32_dmem_model: unaligned word address %08h",
                    address
                );
            end

            if (offset > LAST_WORD_OFFSET) begin
                $fatal(
                    1,
                    "rv32_dmem_model: word address %08h is out of range",
                    address
                );
            end

            checked_word_offset = offset[31:0];
        end
    endfunction

    // The hex file contains one byte per entry in increasing address order.
    task automatic load_hex(
        input string file_name
    );
        begin
            $readmemh(file_name, memory);
        end
    endtask
endmodule
