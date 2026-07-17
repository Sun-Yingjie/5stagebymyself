module rv32_lsu (
    input  logic                 clk,
    input  logic                 rst,

    input  rv32_pkg::ex_mem_t    ex_mem_candidate,
    input  rv32_pkg::ex_mem_t    ex_mem_q,

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

    output logic                 ex_request_wait,
    output logic                 mem_response_wait,
    output rv32_pkg::mem_wb_t    mem_wb_candidate,
    output rv32_pkg::exception_t mem_exception
);

    import rv32_pkg::*;

    logic        outstanding_q;
    logic        outstanding_d;
    logic        request_fire;
    logic        response_fire;
    logic        request_slot_available;
    logic        ex_memory_access;
    logic        mem_memory_access;
    logic [4:0]  store_shift_amount;
    logic [15:0] selected_load_data;
    logic [31:0] load_result;

    // Transaction classification
    assign ex_memory_access = // 执行模块要发出访存请求
        ex_mem_candidate.valid &&
        !ex_mem_candidate.exception.valid &&
        (
            ex_mem_candidate.mem_ctrl.memory_read ||
            ex_mem_candidate.mem_ctrl.memory_write
        );

    assign mem_memory_access = // 访存模块等待接收访存结果，MEM阶段的指令是有效的访存指令
        ex_mem_q.valid &&
        (
            ex_mem_q.mem_ctrl.memory_read ||
            ex_mem_q.mem_ctrl.memory_write
        );

    // Response channel and MEM-stage exception
    assign dmem_rsp_ready = !rst && outstanding_q;
    assign response_fire  = dmem_rsp_valid && dmem_rsp_ready;

    assign mem_response_wait = // 有滞外访存，且DMEM未返回结果
        !rst && outstanding_q && !dmem_rsp_valid;

    always_comb begin
        mem_exception = '0;

        if (ex_mem_q.valid) begin
            mem_exception = ex_mem_q.exception;

            if ( // 处在MEM阶段的指令不是异常指令，且MEM阶段的指令是访存指令，且当前收到了DMEM返回的结果，且返回的结果是error
                !ex_mem_q.exception.valid &&
                mem_memory_access &&
                response_fire &&
                dmem_rsp_error
            ) begin
                mem_exception.valid = 1'b1;
                mem_exception.value = ex_mem_q.exec_result; // 访存地址

                if (ex_mem_q.mem_ctrl.memory_read) begin
                    mem_exception.cause =
                        EXCEPTION_CAUSE_LOAD_ACCESS_FAULT;
                end else begin
                    mem_exception.cause =
                        EXCEPTION_CAUSE_STORE_ACCESS_FAULT;
                end
            end
        end
    end

    // Request channel and store byte-lane formatting
    assign request_slot_available = !outstanding_q || response_fire; // MEM阶段没有访存指令，或者MEM阶段的访存指令本周期返回了

    assign dmem_req_valid = // EX阶段能发出访存请求：MEM阶段的指令不是异常指令（防止要被重刷的EX阶段访存指令产生副作用）；访存通道空闲；EX阶段是访存指令；
        !rst &&
        !mem_exception.valid &&
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

    // MEM/WB candidate
    always_comb begin
        mem_wb_candidate = '0;

        mem_wb_candidate.valid = // MEM阶段的指令有效且已经处理完成：本条指令进MEM阶段前有效，经过MEM处理后还是有效的，不是访存指令或者是访存指令且已经返回
            ex_mem_q.valid &&
            !mem_exception.valid && // 异常在MEM阶段产生trap_take，不进入WB
            (
                !mem_memory_access ||
                response_fire
            );

        mem_wb_candidate.pc          = ex_mem_q.pc;
        mem_wb_candidate.instruction = ex_mem_q.instruction;
        mem_wb_candidate.pc_plus_4   = ex_mem_q.pc_plus_4;

        mem_wb_candidate.exec_result = ex_mem_q.exec_result;
        mem_wb_candidate.load_result = load_result;
        mem_wb_candidate.rd_addr     = ex_mem_q.rd_addr;

        mem_wb_candidate.wb_ctrl     = ex_mem_q.wb_ctrl;
        mem_wb_candidate.exception   = mem_exception;
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
