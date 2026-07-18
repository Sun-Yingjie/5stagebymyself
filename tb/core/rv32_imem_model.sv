module rv32_imem_model #(
    parameter logic [31:0] BASE_ADDR  = 32'h0000_0000,
    parameter int unsigned WORD_COUNT = 256
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        request_enable,
    input  logic        response_enable,

    input  logic        imem_req_valid,
    output logic        imem_req_ready,
    input  logic [31:0] imem_req_addr,

    output logic        imem_rsp_valid,
    input  logic        imem_rsp_ready,
    output logic [31:0] imem_rsp_data,
    output logic        imem_rsp_error
);
    localparam logic [31:0] MEMORY_SIZE_BYTES = WORD_COUNT * 4;

    logic [31:0] request_offset;
    logic        request_addr_aligned;
    logic        request_addr_in_range;
    int unsigned request_word_index;

    logic [31:0] memory [0:WORD_COUNT-1];
    logic        error_map [0:WORD_COUNT-1];

    logic        transaction_pending_q;
    logic        response_started_q;
    logic [31:0] response_data_q;
    logic        response_error_q;

    logic request_fire;
    logic response_fire;
    logic request_slot_available;

    // Request and response handshake
    assign imem_rsp_valid =
        !rst &&
        transaction_pending_q &&
        (response_started_q || response_enable);

    assign imem_rsp_data  = response_data_q;
    assign imem_rsp_error = response_error_q;

    assign response_fire =
        imem_rsp_valid && imem_rsp_ready;

    assign request_slot_available =
        !transaction_pending_q || response_fire;

    assign imem_req_ready =
        !rst &&
        request_enable &&
        request_slot_available;

    assign request_fire =
        imem_req_valid && imem_req_ready;

    // Request address decode
    assign request_offset =
        imem_req_addr - BASE_ADDR;

    assign request_addr_aligned =
        (imem_req_addr[1:0] == 2'b00);

    assign request_addr_in_range =
        (imem_req_addr >= BASE_ADDR) &&
        (request_offset < MEMORY_SIZE_BYTES);

    assign request_word_index =
        request_offset >> 2;

    // Transaction state
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

                if (
                    request_addr_aligned &&
                    request_addr_in_range
                ) begin
                    response_error_q <=
                        error_map[request_word_index];
                    response_data_q <=
                        memory[request_word_index];
                end else begin
                    response_error_q <= 1'b1;
                    response_data_q <= '0;
                end
            end
        end
    end

    // Program loading helpers
    task automatic clear_memory(
        input logic [31:0] fill_word
    );
        int unsigned word_index;
        begin
            for (
                word_index = 0;
                word_index < WORD_COUNT;
                word_index++
            ) begin
                memory[word_index] = fill_word;
                error_map[word_index] = 1'b0;
            end
        end
    endtask

    task automatic write_word(
        input logic [31:0] address,
        input logic [31:0] data
    );
        logic [31:0] offset;
        int unsigned word_index;
        begin
            offset = address - BASE_ADDR;

            if (address[1:0] != 2'b00) begin
                $fatal(
                    1,
                    "rv32_imem_model: unaligned program address %08h",
                    address
                );
            end

            if (
                (address < BASE_ADDR) ||
                (offset >= MEMORY_SIZE_BYTES)
            ) begin
                $fatal(
                    1,
                    "rv32_imem_model: program address %08h is out of range",
                    address
                );
            end

            word_index = offset >> 2;
            memory[word_index] = data;
        end
    endtask

    task automatic set_error(
        input logic [31:0] address,
        input logic        error
    );
        logic [31:0] offset;
        int unsigned word_index;
        begin
            offset = address - BASE_ADDR;

            if (address[1:0] != 2'b00) begin
                $fatal(
                    1,
                    "rv32_imem_model: unaligned error address %08h",
                    address
                );
            end

            if (
                (address < BASE_ADDR) ||
                (offset >= MEMORY_SIZE_BYTES)
            ) begin
                $fatal(
                    1,
                    "rv32_imem_model: error address %08h is out of range",
                    address
                );
            end

            word_index = offset >> 2;
            error_map[word_index] = error;
        end
    endtask

    task automatic load_hex(
        input string file_name
    );
        int unsigned word_index;
        begin
            for (
                word_index = 0;
                word_index < WORD_COUNT;
                word_index++
            ) begin
                error_map[word_index] = 1'b0;
            end

            $readmemh(file_name, memory);
        end
    endtask
endmodule
