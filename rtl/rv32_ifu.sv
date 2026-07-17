module rv32_ifu #(
    parameter logic [31:0] RESET_VECTOR = 32'h0000_0000
) (
    input  logic                    clk,
    input  logic                    rst,

    input  rv32_pkg::fetch_action_e fetch_action,
    input  rv32_pkg::redirect_t     qualified_redirect,
    input  logic                    if_id_ready,

    output logic                    imem_req_valid,
    input  logic                    imem_req_ready,
    output logic [31:0]             imem_req_addr,

    input  logic                    imem_rsp_valid,
    output logic                    imem_rsp_ready,
    input  logic [31:0]             imem_rsp_data,
    input  logic                    imem_rsp_error,

    output rv32_pkg::if_id_t        if_id_candidate,
    output logic                    fetch_response_available
);
// _q可以认为是上周期的结果，_d是这周期的结果，_d会在时钟边沿赋值给_q
    import rv32_pkg::*;

    logic [31:0] next_fetch_addr_q; // 保存“滞外”取指事件的PC+4
    logic [31:0] next_fetch_addr_d;

    logic        request_pending_q; // IFU的状态：IFU中有等待imem接收的取指请求
    logic        request_pending_d;
    logic [31:0] request_pending_addr_q;
    logic [31:0] request_pending_addr_d;
    logic        request_pending_stale_q; // IFU的状态：IFU中等待中的取指请求是无效的
    logic        request_pending_stale_d;

    logic        outstanding_q; // IFU的状态：滞外取指请求，response_fire=0
    logic        outstanding_d;
    logic [31:0] request_pc_q;
    logic [31:0] request_pc_d;
    logic        outstanding_stale_q; // IFU的状态：滞外取指请求是无效的
    logic        outstanding_stale_d;

    logic        redirect_pending_q; // IFU的状态：有等待中的重定向，因上次IFU取值请求未完成使得重定向处于等待状态
    logic        redirect_pending_d;
    logic [31:0] redirect_target_q;
    logic [31:0] redirect_target_d;

    logic        request_fire; // 取值请求成功发出并且被IMEM接收
    logic        response_fire; // 取值结果成功发出并且被IFU接收
    logic        redirect_now; // 当周期收到重定向
    logic        request_slot_available; // 是否能向IMEM发出取指请求
    logic        request_uses_redirect; // 是否能发出重定向的取指请求：是否能发出新的请求，是否是重定向请求

    assign request_fire  = imem_req_valid && imem_req_ready;
    assign response_fire = imem_rsp_valid && imem_rsp_ready;

    assign redirect_now = // 本周期收到了从EX发来的重定向
        (fetch_action == FETCH_REDIRECT) && qualified_redirect.valid;

    assign request_slot_available = !outstanding_q || response_fire; // 是否能向imem发送取指请求：当前没有已经发出但未返回的取指请求，或，本周期已经收到取指返回结果且该结果被消费

    assign request_uses_redirect = // 本周期是否能向imem发送重定向的取值请求：没有请求在等待发出（发了valid，没有收到ready），且，本周期能向imem发送取值请求，且，有重定向请求
        !request_pending_q &&
        request_slot_available &&
        (redirect_now || redirect_pending_q);

    assign fetch_response_available = // imem返回了一条正确路径的有效取值结果：不在复位状态，且，之前有已发出但未返回的取值请求，且，该已发出但未返回的取值请求没有被废弃，且，imem发出了握手请求；如果流水级没有出现重刷、访存wait、执行wait、load use hazard的话，PC就能顺利PC+4；
    //! fetch_response_available是ifu模块的关键信号，代表ifu是否从imem收到了有效的取指结果（指令）
        !rst &&
        outstanding_q &&
        !outstanding_stale_q &&
        imem_rsp_valid;

    always_comb begin
        if_id_candidate = '0;

        if (fetch_response_available) begin // 如果返回imem返回了正确路径的有效取值结果（包括返回error），那么就把这个结果打包作为IF/ID寄存器的输入，不过，到底用不用这个输入还得看流水线的控制（HOLD/LOAD/CLEAR）
            if_id_candidate.valid       = 1'b1;
            if_id_candidate.pc          = request_pc_q;
            if_id_candidate.instruction = imem_rsp_data;
            if_id_candidate.pc_plus_4   = request_pc_q + 32'd4;

            if_id_candidate.exception.valid =
                imem_rsp_error;
            if_id_candidate.exception.cause =
                EXCEPTION_CAUSE_INSTRUCTION_ACCESS_FAULT;
            if_id_candidate.exception.value =
                request_pc_q;
        end
    end

    always_comb begin
        imem_rsp_ready = 1'b0;

        if (!rst && outstanding_q) begin // 存在已经发出但是返回事务还没有完成（imem没有返回或者ifu没有接收）
            if (outstanding_stale_q || redirect_now) begin // 已经发出但是完成返回事务的请求已经被无效掉（之前被重定向），或者本周期收到重定向
                imem_rsp_ready = 1'b1; // 重定向会使得IF模块处于可以接收imem返回结果的状态，因为返回的事务是无效的，直接排空即可
            end else begin
                imem_rsp_ready = if_id_ready; // 正常响应只有在IF/ID本周期可以接收新指令时才能握手。
            end
        end
    end

    always_comb begin
        imem_req_valid = 1'b0;
        imem_req_addr  = '0;

        if (!rst) begin
            if (request_pending_q) begin // IF已准备好，但是IMEM没有接收
                // Preserve an unaccepted request until it handshakes.
                imem_req_valid = 1'b1; // IF向IMEM发出取指邀请（保持）
                imem_req_addr  = request_pending_addr_q; // IF向IMEM发出的取指邀请对应的地址要保持
            end else if (request_slot_available) begin // 没有正在处理中的取指事务，或者取指事务当前周期被消费
                if (redirect_now) begin // 当周期收到重定向的话就用收到的重定向的pc
                    imem_req_valid = 1'b1;
                    imem_req_addr  = qualified_redirect.target;
                end else if (redirect_pending_q) begin // 之前在等待的重定向，用之前保存的重定向pc
                    imem_req_valid = 1'b1;
                    imem_req_addr  = redirect_target_q;
                end else if ( // 取指事务当周期被消费，且该事务不是无效的，且流水控制顺序取指，则用PC+4
                    response_fire &&
                    !outstanding_stale_q &&
                    (fetch_action == FETCH_SEQUENTIAL)
                ) begin
                    imem_req_valid = 1'b1;
                    imem_req_addr  = next_fetch_addr_q;
                end
            end
        end
    end

    always_comb begin
        next_fetch_addr_d       = next_fetch_addr_q; // PC+4
        request_pending_d       = request_pending_q; // IFU发出取指邀请，但是IMEM没有响应的状态
        request_pending_addr_d  = request_pending_addr_q; // 记录“IFU发出取指邀请，但是IMEM没有响应的状态”对应的当时的PC
        request_pending_stale_d = request_pending_stale_q;  // 记录“IFU发出取指邀请，但是IMEM没有响应的状态”是否被无效掉了（重定向导致的）
        outstanding_d           = outstanding_q; // IFU已经发出取指请求，但是IMEM还没有返回结果或者返回的结果还没有被IFU接收（在途）
        request_pc_d            = request_pc_q; // 在途请求对应的PC
        outstanding_stale_d     = outstanding_stale_q; // 在途的请求被无效掉了
        redirect_pending_d      = redirect_pending_q; // 有重定向正在等待
        redirect_target_d       = redirect_target_q; // 正在等待的重定向对应的PC

        // The old outstanding transaction completes.
        if (response_fire) begin // 没有在途请求
            outstanding_d       = 1'b0;
            outstanding_stale_d = 1'b0;
        end

        // Save a redirect that cannot necessarily be issued immediately.
        if (redirect_now) begin // 收到重定向就保存（重定向只会来一个，不会有重定向的相互覆盖）
            redirect_pending_d = 1'b1;
            redirect_target_d  = qualified_redirect.target;

            if (request_pending_q) begin // 重定向会把等待中的请求置为无效
                request_pending_stale_d = 1'b1;
            end

            if (outstanding_q && !response_fire) begin // 重定向会把在途且本周期不返回的请求置为无效
                outstanding_stale_d = 1'b1;
            end
        end

        // A request is accepted by instruction memory.
        if (request_fire) begin // 如果成功握手发出了一个取指请求，则清空请求等待标志，添加在途标志，记录在途的请求地址
            request_pending_d       = 1'b0;
            request_pending_stale_d = 1'b0;

            outstanding_d = 1'b1;
            request_pc_d  = imem_req_addr;

            outstanding_stale_d = // 发出的成功握手的取指请求也可能是无效的，因为之前已经被置为无效，那么就标记为在途的无效指令
                request_pending_q && // 之前在等待请求的状态，且该请求被重定向给无效了（之前或现在）
                (request_pending_stale_q || redirect_now);

            next_fetch_addr_d = imem_req_addr + 32'd4; // PC+4
        end else if ( // 由于IMEM没准备好导致的没发出，之前没有在等待发出的指令，意思是新来的在等待的指令，那么就保存这个指令的相关信息
            imem_req_valid &&
            !imem_req_ready &&
            !request_pending_q
        ) begin
            // A newly generated request must be held until accepted.
            request_pending_d       = 1'b1;
            request_pending_addr_d  = imem_req_addr;
            request_pending_stale_d = 1'b0;
        end

        // The target is now represented by an accepted or pending request.
        if (imem_req_valid && request_uses_redirect) begin // 如果响应了正在等待的重定向，那么就把正在等待的重定向清除
            redirect_pending_d = 1'b0;
        end
    end

    always_ff @(posedge clk) begin // 状态
        if (rst) begin
            next_fetch_addr_q       <= RESET_VECTOR; 

            request_pending_q       <= 1'b1;
            request_pending_addr_q  <= RESET_VECTOR;
            request_pending_stale_q <= 1'b0;

            outstanding_q           <= 1'b0;
            request_pc_q            <= RESET_VECTOR;
            outstanding_stale_q     <= 1'b0;

            redirect_pending_q      <= 1'b0;
            redirect_target_q       <= '0;
        end else begin
            next_fetch_addr_q       <= next_fetch_addr_d;

            request_pending_q       <= request_pending_d;
            request_pending_addr_q  <= request_pending_addr_d;
            request_pending_stale_q <= request_pending_stale_d;

            outstanding_q           <= outstanding_d;
            request_pc_q            <= request_pc_d;
            outstanding_stale_q     <= outstanding_stale_d;

            redirect_pending_q      <= redirect_pending_d;
            redirect_target_q       <= redirect_target_d;
        end
    end
endmodule
