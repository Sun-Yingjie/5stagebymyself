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

    import rv32_pkg::*;

    logic [31:0] next_fetch_addr_q;
    logic [31:0] next_fetch_addr_d;

    logic        request_pending_q;
    logic        request_pending_d;
    logic [31:0] request_pending_addr_q;
    logic [31:0] request_pending_addr_d;
    logic        request_pending_stale_q;
    logic        request_pending_stale_d;

    logic        outstanding_q;
    logic        outstanding_d;
    logic [31:0] request_pc_q;
    logic [31:0] request_pc_d;
    logic        outstanding_stale_q;
    logic        outstanding_stale_d;

    logic        redirect_pending_q;
    logic        redirect_pending_d;
    logic [31:0] redirect_target_q;
    logic [31:0] redirect_target_d;

    logic        request_fire;
    logic        response_fire;
    logic        redirect_now;
    logic        request_slot_available;
    logic        request_uses_redirect;

    assign request_fire  = imem_req_valid && imem_req_ready;
    assign response_fire = imem_rsp_valid && imem_rsp_ready;

    assign redirect_now =
        (fetch_action == FETCH_REDIRECT) && qualified_redirect.valid;

    assign request_slot_available = !outstanding_q || response_fire;

    assign request_uses_redirect =
        !request_pending_q &&
        request_slot_available &&
        (redirect_now || redirect_pending_q);

    assign fetch_response_available =
        !rst &&
        outstanding_q &&
        !outstanding_stale_q &&
        imem_rsp_valid;

    always_comb begin
        if_id_candidate = '0;

        if (fetch_response_available) begin
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

        if (!rst && outstanding_q) begin
            if (outstanding_stale_q || redirect_now) begin
                // Stale responses are drained without entering IF/ID.
                imem_rsp_ready = 1'b1;
            end else begin
                imem_rsp_ready = if_id_ready;
            end
        end
    end

    always_comb begin
        imem_req_valid = 1'b0;
        imem_req_addr  = '0;

        if (!rst) begin
            if (request_pending_q) begin
                // Preserve an unaccepted request until it handshakes.
                imem_req_valid = 1'b1;
                imem_req_addr  = request_pending_addr_q;
            end else if (request_slot_available) begin
                if (redirect_now) begin
                    imem_req_valid = 1'b1;
                    imem_req_addr  = qualified_redirect.target;
                end else if (redirect_pending_q) begin
                    imem_req_valid = 1'b1;
                    imem_req_addr  = redirect_target_q;
                end else if (
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
        next_fetch_addr_d       = next_fetch_addr_q;
        request_pending_d       = request_pending_q;
        request_pending_addr_d  = request_pending_addr_q;
        request_pending_stale_d = request_pending_stale_q;
        outstanding_d           = outstanding_q;
        request_pc_d            = request_pc_q;
        outstanding_stale_d     = outstanding_stale_q;
        redirect_pending_d      = redirect_pending_q;
        redirect_target_d       = redirect_target_q;

        // The old outstanding transaction completes.
        if (response_fire) begin
            outstanding_d       = 1'b0;
            outstanding_stale_d = 1'b0;
        end

        // Save a redirect that cannot necessarily be issued immediately.
        if (redirect_now) begin
            redirect_pending_d = 1'b1;
            redirect_target_d  = qualified_redirect.target;

            if (request_pending_q) begin
                request_pending_stale_d = 1'b1;
            end

            if (outstanding_q && !response_fire) begin
                outstanding_stale_d = 1'b1;
            end
        end

        // A request is accepted by instruction memory.
        if (request_fire) begin
            request_pending_d       = 1'b0;
            request_pending_stale_d = 1'b0;

            outstanding_d = 1'b1;
            request_pc_d  = imem_req_addr;

            outstanding_stale_d =
                request_pending_q &&
                (request_pending_stale_q || redirect_now);

            next_fetch_addr_d = imem_req_addr + 32'd4;
        end else if (
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
        if (imem_req_valid && request_uses_redirect) begin
            redirect_pending_d = 1'b0;
        end
    end

    always_ff @(posedge clk) begin
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
