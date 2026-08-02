module rv32_ifu #(
    parameter logic [31:0] RESET_VECTOR = 32'h0000_0000
) (
    input  logic                    clk,
    input  logic                    rst,

    input  rv32_pkg::fetch_action_e fetch_action,
    input  rv32_pkg::redirect_t     qualified_redirect,
    input  logic                    if_id_ready,                // if_id_action == PIPE_LOAD

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

    // phase_q only answers where the current IMEM transaction is. Whether the
    // transaction is still useful is tracked independently by transaction_stale_q.
    typedef enum logic [1:0] {
        IFU_IDLE            = 2'b00,
        IFU_WAIT_REQ_ACCEPT = 2'b01,
        IFU_WAIT_RSP        = 2'b10
    } ifu_phase_e;

    ifu_phase_e phase_q;
    ifu_phase_e phase_d;

    // In IFU_WAIT_REQ_ACCEPT this is the held request address. In IFU_WAIT_RSP
    // it is the PC associated with the outstanding response.
    logic [31:0] transaction_addr_q;
    logic [31:0] transaction_addr_d;
    logic        transaction_stale_q;
    logic        transaction_stale_d;

    // A redirect must be buffered while an older request is being held or an
    // accepted stale request is being drained.
    logic        redirect_pending_q;
    logic        redirect_pending_d;
    logic [31:0] redirect_target_q;
    logic [31:0] redirect_target_d;

    logic request_fire;
    logic response_fire;
    logic redirect_now;
    logic can_start_new_request;
    logic new_request_valid;
    logic new_request_fire;
    logic new_request_is_redirect;
    logic [31:0] new_request_addr;

    // Combinational state decodes retained for verification visibility. They
    // do not infer the flag registers used by the original implementation.
    logic        request_pending_q;
    logic [31:0] request_pending_addr_q;
    logic        request_pending_stale_q;
    logic        outstanding_q;
    logic        outstanding_stale_q;

    assign request_pending_q = phase_q == IFU_WAIT_REQ_ACCEPT;
    assign request_pending_addr_q = transaction_addr_q;
    assign outstanding_q = phase_q == IFU_WAIT_RSP;

    assign request_pending_stale_q =
        request_pending_q && transaction_stale_q;   // pending + stale = pending stale
    assign outstanding_stale_q =                    // outstanding + stale = outstanding stale
        outstanding_q && transaction_stale_q;

    assign request_fire  = imem_req_valid && imem_req_ready;

    assign redirect_now =
        (fetch_action == FETCH_REDIRECT) && qualified_redirect.valid;

    // imem_rsp_ready always equals to if_id_ready, unless redirect(ed)
    always_comb begin
        imem_rsp_ready = 1'b0;

        if (!rst && (phase_q == IFU_WAIT_RSP)) begin
            if (transaction_stale_q || redirect_now) begin  // if req is stale, rsp ready will not depend on if_id_ready and it will keep 1
                imem_rsp_ready = 1'b1;
            end else begin
                imem_rsp_ready = if_id_ready;
            end
        end
    end

    assign response_fire = imem_rsp_valid && imem_rsp_ready;

    assign fetch_response_available =
        !rst &&
        (phase_q == IFU_WAIT_RSP) &&
        !transaction_stale_q &&
        imem_rsp_valid;

    // Candidate visibility is independent of if_id_ready. In a same-cycle
    // redirect, the old candidate remains observable and pipeline clear drops it.
    always_comb begin
        if_id_candidate = '0;

        if (fetch_response_available) begin
            if_id_candidate.valid       = 1'b1;
            if_id_candidate.pc          = transaction_addr_q;
            if_id_candidate.instruction = imem_rsp_data;
            if_id_candidate.pc_plus_4   =
                transaction_addr_q + 32'd4;

            if_id_candidate.exception.valid = imem_rsp_error;
            if_id_candidate.exception.cause =
                EXCEPTION_CAUSE_INSTRUCTION_ACCESS_FAULT;
            if_id_candidate.exception.value = transaction_addr_q;
        end
    end

    // A completed response makes the single IMEM transaction slot available
    // soon enough to generate the following request in the same cycle.
    assign can_start_new_request =
        (phase_q == IFU_IDLE) ||
        ((phase_q == IFU_WAIT_RSP) && response_fire);

    // Select only a newly generated request here. A request already waiting
    // for acceptance is handled separately and always keeps channel ownership.
    always_comb begin
        new_request_valid       = 1'b0;
        new_request_addr        = '0;
        new_request_is_redirect = 1'b0;

        if (!rst && can_start_new_request) begin
            if (redirect_now) begin
                new_request_valid       = 1'b1;
                new_request_addr        = qualified_redirect.target;
                new_request_is_redirect = 1'b1;
            end else if (redirect_pending_q) begin
                new_request_valid       = 1'b1;
                new_request_addr        = redirect_target_q;
                new_request_is_redirect = 1'b1;
            end else if (
                response_fire &&
                (phase_q == IFU_WAIT_RSP) &&
                !transaction_stale_q &&
                (fetch_action == FETCH_SEQUENTIAL)
            ) begin
                new_request_valid = 1'b1;
                new_request_addr  = transaction_addr_q + 32'd4;
            end
        end
    end

    assign new_request_fire = new_request_valid && imem_req_ready;

    // The public request channel is owned either by a previously held request
    // or by the newly selected request above. A redirect cannot rewrite a held
    // request before its valid/ready handshake completes.
    always_comb begin
        imem_req_valid = 1'b0;
        imem_req_addr  = '0;

        if (!rst) begin
            if (phase_q == IFU_WAIT_REQ_ACCEPT) begin
                imem_req_valid = 1'b1;
                imem_req_addr  = transaction_addr_q;
            end else begin
                imem_req_valid = new_request_valid;
                imem_req_addr  = new_request_addr;
            end
        end
    end

    // The redirect buffer has one responsibility: remember the newest target
    // until that target is represented by an accepted or held IMEM request.
    always_comb begin
        redirect_pending_d = redirect_pending_q;
        redirect_target_d  = redirect_target_q;

        if (redirect_now) begin
            redirect_pending_d = 1'b1;
            redirect_target_d  = qualified_redirect.target;
        end

        if (new_request_valid && new_request_is_redirect) begin
            redirect_pending_d = 1'b0;
        end
    end

    // phase_q describes only the transaction lifetime. transaction_stale_q
    // independently records whether redirect has invalidated that transaction.
    always_comb begin
        phase_d             = phase_q;
        transaction_addr_d  = transaction_addr_q;
        transaction_stale_d = transaction_stale_q;

        unique case (phase_q)
            IFU_IDLE: begin
                transaction_stale_d = 1'b0;

                if (new_request_valid) begin
                    transaction_addr_d = new_request_addr;
                    if (new_request_fire) begin
                        phase_d = IFU_WAIT_RSP;             // wait for response
                    end else begin
                        phase_d = IFU_WAIT_REQ_ACCEPT;      // wait for request accept
                    end
                end
            end

            IFU_WAIT_REQ_ACCEPT: begin
                // The channel payload stays unchanged. Redirect only marks the
                // held request stale and saves its new target in the buffer.
                if (redirect_now) begin
                    transaction_stale_d = 1'b1;
                end

                if (request_fire) begin                     // only request_fire can change the state
                    phase_d = IFU_WAIT_RSP;
                end
            end

            IFU_WAIT_RSP: begin
                if (response_fire) begin
                    if (new_request_valid) begin
                        // The completed transaction is replaced by a fresh
                        // redirect or sequential request in the same cycle.
                        transaction_addr_d  = new_request_addr;
                        transaction_stale_d = 1'b0;
                        if (new_request_fire) begin
                            phase_d = IFU_WAIT_RSP;
                        end else begin
                            phase_d = IFU_WAIT_REQ_ACCEPT;
                        end
                    end else begin
                        phase_d             = IFU_IDLE;
                        transaction_stale_d = 1'b0;
                    end
                end else if (redirect_now) begin
                    transaction_stale_d = 1'b1;
                end
            end

            default: begin
                phase_d             = IFU_IDLE;
                transaction_stale_d = 1'b0;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            phase_q             <= IFU_WAIT_REQ_ACCEPT;
            transaction_addr_q  <= RESET_VECTOR;
            transaction_stale_q <= 1'b0;

            redirect_pending_q <= 1'b0;
            redirect_target_q  <= '0;
        end else begin
            phase_q             <= phase_d;
            transaction_addr_q  <= transaction_addr_d;
            transaction_stale_q <= transaction_stale_d;

            redirect_pending_q <= redirect_pending_d;
            redirect_target_q  <= redirect_target_d;
        end
    end
endmodule
