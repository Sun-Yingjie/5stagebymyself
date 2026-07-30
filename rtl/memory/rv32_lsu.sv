module rv32_lsu (
    input  logic                 clk,
    input  logic                 rst,

    input  rv32_pkg::ex_mem_t    ex_mem_candidate,
    input  rv32_pkg::ex_mem_t    ex_mem_q,
    input  logic                 ex_request_block,

    output logic                 dmem_req_valid,
    input  logic                 dmem_req_ready,
    output logic                 dmem_req_write,
    output logic [31:0]          dmem_req_addr,
    output logic [31:0]          dmem_req_wdata,
    output logic [3:0]           dmem_req_wstrb,

    input  logic                 dmem_rsp_valid,
    output logic                 dmem_rsp_ready,
    input  logic [31:0]          dmem_rsp_rdata,
    input  logic                 dmem_rsp_error,

    output logic                 response_fire,
    output logic                 ex_request_wait,
    output logic                 mem_response_wait,
    output logic                 lsu_outstanding,
    output logic [31:0]          load_result,
    output rv32_pkg::exception_t lsu_exception
);

    import rv32_pkg::*;

    logic        outstanding_q;
    logic        outstanding_d;
    logic        request_fire;
    logic        request_slot_available;
    logic        ex_memory_access;
    logic        mem_memory_access;
    logic [4:0]  store_shift_amount;
    logic [15:0] selected_load_data;

    // Transaction classification
    assign ex_memory_access =
        ex_mem_candidate.valid &&
        !ex_mem_candidate.exception.valid &&
        (
            ex_mem_candidate.mem_ctrl.memory_read ||
            ex_mem_candidate.mem_ctrl.memory_write
        );

    assign mem_memory_access =
        ex_mem_q.valid &&
        (
            ex_mem_q.mem_ctrl.memory_read ||
            ex_mem_q.mem_ctrl.memory_write
        );

    // Response channel and LSU-local access exception
    assign dmem_rsp_ready = !rst && outstanding_q;
    assign response_fire  = dmem_rsp_valid && dmem_rsp_ready;

    assign mem_response_wait =
        !rst && outstanding_q && !dmem_rsp_valid;
    assign lsu_outstanding = outstanding_q;

    always_comb begin
        lsu_exception = '0;

        if (
            ex_mem_q.valid &&
            !ex_mem_q.exception.valid &&
            mem_memory_access &&
            response_fire &&
            dmem_rsp_error
        ) begin
            lsu_exception.valid = 1'b1;
            lsu_exception.value = ex_mem_q.exec_result;

            if (ex_mem_q.mem_ctrl.memory_read) begin
                lsu_exception.cause =
                    EXCEPTION_CAUSE_LOAD_ACCESS_FAULT;
            end else begin
                lsu_exception.cause =
                    EXCEPTION_CAUSE_STORE_ACCESS_FAULT;
            end
        end
    end

    // Request channel and store byte-lane formatting
    assign request_slot_available = !outstanding_q || response_fire;

    // Final MEM exceptions, MRET and interrupts arrive through
    // ex_request_block; the LSU does not duplicate their merge locally.
    assign dmem_req_valid =
        !rst &&
        !ex_request_block &&
        request_slot_available &&
        ex_memory_access;

    assign request_fire = dmem_req_valid && dmem_req_ready;

    assign ex_request_wait = dmem_req_valid && !dmem_req_ready;

    assign store_shift_amount = {
        ex_mem_candidate.exec_result[1:0],
        3'b000
    };

    always_comb begin
        dmem_req_write = ex_mem_candidate.mem_ctrl.memory_write;
        dmem_req_addr  = ex_mem_candidate.exec_result;
        dmem_req_wdata = '0;
        dmem_req_wstrb = '0;

        if (ex_mem_candidate.mem_ctrl.memory_write) begin
            case (ex_mem_candidate.mem_ctrl.memory_size)
                MEM_SIZE_BYTE: begin
                    dmem_req_wdata =
                        {24'b0, ex_mem_candidate.store_data[7:0]}
                        << store_shift_amount;

                    dmem_req_wstrb =
                        4'b0001
                        << ex_mem_candidate.exec_result[1:0];
                end

                MEM_SIZE_HALF: begin
                    dmem_req_wdata =
                        {16'b0, ex_mem_candidate.store_data[15:0]}
                        << store_shift_amount;

                    dmem_req_wstrb =
                        4'b0011
                        << ex_mem_candidate.exec_result[1:0];
                end

                MEM_SIZE_WORD: begin
                    dmem_req_wdata = ex_mem_candidate.store_data;
                    dmem_req_wstrb = 4'b1111;
                end

                default: begin
                    dmem_req_wdata = '0;
                    dmem_req_wstrb = '0;
                end
            endcase
        end
    end

    // Load byte-lane selection and extension
    always_comb begin
        case (ex_mem_q.exec_result[1:0])
            2'b00: selected_load_data = dmem_rsp_rdata[15:0];
            2'b01: selected_load_data = dmem_rsp_rdata[23:8];
            2'b10: selected_load_data = dmem_rsp_rdata[31:16];
            2'b11: selected_load_data = {8'b0, dmem_rsp_rdata[31:24]};
            default: selected_load_data = '0;
        endcase
    end

    always_comb begin
        load_result = '0;

        if (mem_memory_access && ex_mem_q.mem_ctrl.memory_read) begin
            case (ex_mem_q.mem_ctrl.memory_size)
                MEM_SIZE_BYTE: begin
                    if (ex_mem_q.mem_ctrl.load_unsigned) begin
                        load_result = {
                            24'b0,
                            selected_load_data[7:0]
                        };
                    end else begin
                        load_result = {
                            {24{selected_load_data[7]}},
                            selected_load_data[7:0]
                        };
                    end
                end

                MEM_SIZE_HALF: begin
                    if (ex_mem_q.mem_ctrl.load_unsigned) begin
                        load_result = {
                            16'b0,
                            selected_load_data
                        };
                    end else begin
                        load_result = {
                            {16{selected_load_data[15]}},
                            selected_load_data
                        };
                    end
                end

                MEM_SIZE_WORD: begin
                    load_result = dmem_rsp_rdata;
                end

                default: begin
                    load_result = '0;
                end
            endcase
        end
    end

    // Outstanding transaction state
    always_comb begin
        outstanding_d = outstanding_q;

        if (response_fire) begin
            outstanding_d = 1'b0;
        end

        if (request_fire) begin
            outstanding_d = 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            outstanding_q <= 1'b0;
        end else begin
            outstanding_q <= outstanding_d;
        end
    end
endmodule
