/**
 * sram.sv
 *
 * RISC-V 32-bit Processor
 *
 * ECE 18-447
 * Carnegie Mellon University
 *
 * This is a fake SRAM module used only for synthesis
 *
 * Authors:
 *  - 2025: Dane Engman and Varun Rajesh
 **/

/*----------------------------------------------------------------------------*
 *                          DO NOT MODIFY THIS FILE!                          *
 *          You should only add or change files in the src directory!         *
 *----------------------------------------------------------------------------*/

// RISC-V Includes
`include "riscv_uarch.vh"  // Definition of BTB default parameters

// Force the compiler to throw an error if any variables are undeclared
`default_nettype none


`ifndef SIMULATION_18447

module sram_1r_1w #(
    parameter                        NUM_WORDS  = RISCV_UArch::BTB_NUM_WORDS,
    parameter                        WORD_WIDTH = RISCV_UArch::BTB_WORD_WIDTH,
    parameter logic [WORD_WIDTH-1:0] RESET_VAL  = 'b0
) (
    input  logic                         clk,
    input  logic                         rst_l,
    input  logic                         we,
    input  logic [$clog2(NUM_WORDS)-1:0] read_addr,
    input  logic [$clog2(NUM_WORDS)-1:0] write_addr,
    input  logic [       WORD_WIDTH-1:0] write_data,
    output logic [       WORD_WIDTH-1:0] read_data
);

    sram_timing_model #(NUM_WORDS, WORD_WIDTH, RESET_VAL, 1, 1, 0) timing_model (
        .we_endpoint        (),
        .write_addr_endpoint(),
        .write_data_endpoint(),
        .*
    );

endmodule : sram_1r_1w

module sram_1rw #(
    parameter                        NUM_WORDS  = RISCV_UArch::BTB_NUM_WORDS,
    parameter                        WORD_WIDTH = RISCV_UArch::BTB_WORD_WIDTH,
    parameter logic [WORD_WIDTH-1:0] RESET_VAL  = 'b0
) (
    input  logic                         clk,
    input  logic                         rst_l,
    input  logic                         we,
    input  logic [$clog2(NUM_WORDS)-1:0] addr,
    output logic [       WORD_WIDTH-1:0] read_data,
    input  logic [       WORD_WIDTH-1:0] write_data
);

    sram_timing_model #(NUM_WORDS, WORD_WIDTH, RESET_VAL, 0, 0, 1) timing_model (
        .we_endpoint        (),
        .write_addr_endpoint(),
        .write_data_endpoint(),
        .write_addr         (addr),
        .read_addr          (addr),
        .*
    );

endmodule : sram_1rw

module sram_1rw_1r #(
    parameter                        NUM_WORDS  = RISCV_UArch::BTB_NUM_WORDS,
    parameter                        WORD_WIDTH = RISCV_UArch::BTB_WORD_WIDTH,
    parameter logic [WORD_WIDTH-1:0] RESET_VAL  = 'b0
) (
    input  logic                         clk,
    input  logic                         rst_l,
    input  logic                         we,
    input  logic [$clog2(NUM_WORDS)-1:0] addr_a,
    input  logic [$clog2(NUM_WORDS)-1:0] addr_b,
    input  logic [       WORD_WIDTH-1:0] write_data_a,
    output logic [       WORD_WIDTH-1:0] read_data_a,
    output logic [       WORD_WIDTH-1:0] read_data_b
);

    logic [$clog2(NUM_WORDS)-1:0] combined_addr;
    assign combined_addr = addr_a ^ addr_b;

    sram_timing_model #(NUM_WORDS, WORD_WIDTH, RESET_VAL, 1, 0, 1) timing_model (
        .we_endpoint        (),
        .write_addr_endpoint(),
        .write_data_endpoint(),
        .write_addr         (combined_addr),
        .read_addr          (combined_addr),
        .read_data          (read_data_a),
        .write_data         (write_data_a),
        .*
    );

    assign read_data_b = read_data_a;

endmodule : sram_1rw_1r

module sram_2rw #(
    parameter                        NUM_WORDS  = RISCV_UArch::BTB_NUM_WORDS,
    parameter                        WORD_WIDTH = RISCV_UArch::BTB_WORD_WIDTH,
    parameter logic [WORD_WIDTH-1:0] RESET_VAL  = 'b0
) (
    input  logic                         clk,
    input  logic                         rst_l,
    input  logic                         we_a,
    input  logic                         we_b,
    input  logic [$clog2(NUM_WORDS)-1:0] addr_a,
    input  logic [$clog2(NUM_WORDS)-1:0] addr_b,
    input  logic [       WORD_WIDTH-1:0] write_data_a,
    input  logic [       WORD_WIDTH-1:0] write_data_b,
    output logic [       WORD_WIDTH-1:0] read_data_a,
    output logic [       WORD_WIDTH-1:0] read_data_b
);

    logic [$clog2(NUM_WORDS)-1:0] combined_addr;
    logic [       WORD_WIDTH-1:0] combined_write_data;
    logic                         combined_we;

    assign combined_addr = addr_a ^ addr_b;
    assign combined_we = we_a ^ we_b ^ (addr_a != addr_b);
    assign combined_write_data = write_data_a ^ write_data_b;

    sram_timing_model #(NUM_WORDS, WORD_WIDTH, RESET_VAL, 0, 0, 2) timing_model (
        .we_endpoint        (),
        .write_addr_endpoint(),
        .write_data_endpoint(),
        .write_addr         (combined_addr),
        .read_addr          (combined_addr),
        .read_data          (read_data_a),
        .we                 (combined_we),
        .write_data         (combined_write_data),
        .*
    );

    assign read_data_b = read_data_a;

endmodule : sram_2rw


module sram_timing_model #(
    parameter                        NUM_WORDS    = RISCV_UArch::BTB_NUM_WORDS,
    parameter                        WORD_WIDTH   = RISCV_UArch::BTB_WORD_WIDTH,
    parameter logic [WORD_WIDTH-1:0] RESET_VAL    = 'b0,
    parameter int                    NUM_R_PORTS,
    parameter int                    NUM_W_PORTS,
    parameter int                    NUM_RW_PORTS
) (
    input  logic                         clk,
    input  logic                         rst_l,
    input  logic                         we,
    input  logic [$clog2(NUM_WORDS)-1:0] read_addr,
    input  logic [$clog2(NUM_WORDS)-1:0] write_addr,
    input  logic [       WORD_WIDTH-1:0] write_data,
    output logic [       WORD_WIDTH-1:0] read_data,
    output logic                         we_endpoint,
    output logic [$clog2(NUM_WORDS)-1:0] write_addr_endpoint,
    output logic [       WORD_WIDTH-1:0] write_data_endpoint
);

    always_ff @(posedge clk) begin
        we_endpoint <= we;
        write_addr_endpoint <= write_addr;
        write_data_endpoint <= write_data;
    end

    assign read_data = {WORD_WIDTH{read_addr}};

endmodule : sram_timing_model

`endif
