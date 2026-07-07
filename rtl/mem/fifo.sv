`include "internal_defines.vh"

module fifo # (
    // I found a paper by Sutherland & Mills (2013) about synthesisable
    // generic types and it's pretty cool
    parameter WIDTH = 64,
    parameter MAX_ELEMENTS = 2,
    parameter MAX_ENQ      = 1,
    parameter MAX_DEQ      = 1
) (
    input logic clk, rst_l,
    input logic peek_only,  
    input logic flush, 
    
    input logic [ MAX_ENQ - 1 : 0 ][WIDTH-1:0]    enq_data,
    input logic [ $clog2(MAX_ENQ + 1) - 1 : 0] num_enq,
    input logic [ $clog2(MAX_DEQ + 1) - 1 : 0] num_deq,

    output logic [ MAX_DEQ - 1 : 0 ][WIDTH-1:0]             deq_data,
    output logic [ $clog2(MAX_ENQ + 1) - 1 : 0]      num_suc_enq,
    output logic [ $clog2(MAX_DEQ + 1) - 1 : 0]      num_suc_deq,
    output logic [ $clog2(MAX_ELEMENTS + 1) - 1 : 0] num_q_elem
);

    typedef struct packed {
        logic [MAX_ELEMENTS - 1 : 0 ] [WIDTH-1:0]                data;
        logic [ $clog2(MAX_ELEMENTS + 1) - 1 : 0 ] head_ptr, tail_ptr, num_elems;
    } queue_state_t;
    
    queue_state_t curr_queue_state, new_queue_state; 

    always_ff @(posedge clk, negedge rst_l) begin
        if (~rst_l) begin
            curr_queue_state <= 'b0; 
        end else if (flush) begin
            curr_queue_state <= 'b0; 
        end else begin
            curr_queue_state <= new_queue_state; 
        end
    end
    
    // variables owned by each thread for local counting of elements
    logic [ $clog2(MAX_ELEMENTS + 1) - 1 : 0] new_head, new_tail;

    /* deq_data always shows the entries at the head of the queue (qualified
     * by num_suc_deq / valid bits embedded in the data), computed in its own
     * block that reads only registered state. Keeping it independent of
     * num_deq/peek_only means there is no combinational path from the
     * dequeue-control inputs to deq_data; consumers that derive their stall
     * (and hence peek_only) from deq_data would otherwise form a
     * combinational loop, which Verilator cannot schedule. Behavior is
     * unchanged: the old code assigned deq_data before the peek_only
     * override, and entries beyond num_elems read as '0 either way. */
    logic [ $clog2(MAX_ELEMENTS + 1) - 1 : 0] rd_ptr;
    always_comb begin
        rd_ptr = curr_queue_state.head_ptr;
        for (int i = 0; i < MAX_DEQ; i++) begin
            if (i < curr_queue_state.num_elems)
                deq_data[i] = curr_queue_state.data[rd_ptr];
            else
                deq_data[i] = '0;
            rd_ptr ++;
            if (rd_ptr >= MAX_ELEMENTS) begin
                rd_ptr = '0;
            end
        end
    end

    always_comb begin
        // DEQ from the head of the current queue
        if (curr_queue_state.num_elems < num_deq)
            num_suc_deq = curr_queue_state.num_elems;
        else
            num_suc_deq = num_deq;

        new_head = curr_queue_state.head_ptr;
        for (int i = 0; i < num_suc_deq; i++) begin
            new_head ++;
            if (new_head >= MAX_ELEMENTS) begin
                new_head = '0;
            end
        end
        if (peek_only) begin
            new_head    = curr_queue_state.head_ptr;
            num_suc_deq = '0;
        end
    end

    always_comb begin
        new_queue_state.data = curr_queue_state.data; 
        // ENQ from the tail of the current queue
        if (MAX_ELEMENTS == curr_queue_state.num_elems) 
            num_suc_enq = '0; // MAX_ELEMENTS - curr_queue_state.num_elems; 
        else 
            num_suc_enq = num_enq; 

        new_tail = curr_queue_state.tail_ptr; 
        for (int i = 0; i < num_suc_enq; i++) begin
            new_queue_state.data[new_tail] = enq_data[i];
            new_tail ++; 
            if (new_tail >= MAX_ELEMENTS) begin
                new_tail = '0; 
            end
        end
    end

    assign new_queue_state.num_elems = curr_queue_state.num_elems - num_suc_deq + num_suc_enq; 
    assign new_queue_state.tail_ptr  = new_tail;
    assign new_queue_state.head_ptr  = new_head;
    assign num_q_elem                = curr_queue_state.num_elems;  
endmodule: fifo
