/**
 * sim.c
 *
 * RISC-V 32-bit Instruction Level Simulator
 *
 * ECE 18-447
 * Carnegie Mellon University
 *
 * This is the core part of the simulator. The `process_instruction` function
 * will be invoked by the simulator each time it needs to simulate a single
 * processor cycle. This is responsible for simulating the next processor cycle.
 * This corresponds to simulating the next instruction, and updating the
 * register file, memory, and PC register appropriately as required by the next
 * instruction.
 *
 * This is where you can start add code and make modifications to implement the
 * rest of the instructions. You can add any additional files or change and
 * delete files as you need to implement the simulator, provided that they are
 * under the src directory. You may not change any files outside the src
 * directory. The only requirement is that you define a `process_instruction`
 * function with the same interface as below.
 *
 * The Makefile will automatically find any files you add, provided they are
 * under the src directory and have either a *.c or *.h extension. The files may
 * be nested in subdirectories under the src directory as well. Additionally,
 * the build system sets up the include paths so that you can place header files
 * in any subdirectory under the src directory, and include them from anywhere
 * else inside the src directory.
 **/

/*----------------------------------------------------------------------------*
 *  You may edit this file and add or change any files in the src directory.  *
 *----------------------------------------------------------------------------*/

// Standard Includes
#include <stdio.h>              // Printf and related functions
#include <stdbool.h>            // Boolean type and definitions

// 18-447 Simulator Includes
#include <riscv_isa.h>          // Definition of RISC-V opcodes, ISA registers
#include <riscv_abi.h>          // ABI registers and definitions
#include <sim.h>                // Definitions for the simulator
#include <memory.h>             // Interface to the processor memory
#include <register_file.h>      // Interface to the register file

/**
 * Simulates a single cycle on the CPU, updating the CPU's state as needed.
 *
 * This is the core part of the simulator. This simulates the current
 * instruction pointed to by the PC. This performs the necessary actions for the
 * instruction, and updates the CPU state appropriately.
 *
 * You implement this function.
 *
 * Inputs:
 *  - cpu_state     The current state of the CPU being simulated.
 *
 * Outputs:
 *  - cpu_state     The next state of the CPU being simulated. This function
 *                  updates the fields of the state as needed by the current
 *                  instruction to simulate it.
 * 
 * 
 **/
void process_instruction(cpu_state_t *cpu_state)
{
    // Fetch the 4-bytes for the current instruction
    uint32_t instr = mem_read32(cpu_state, cpu_state->pc);

    // Decode the opcode, 7-bit function code, and registers
    opcode_t opcode = instr & 0x7F;
    
    switch (opcode)
    {
        // General R-Type arithmetic operation: ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND (pg 19)
        case OP_OP: {
            // form [funct7 - 7 bits | rs2 - 5 bits | rs1 - 5 bits | funct3 - 3 bits | rd - 5 bits | opcode - 7 bits]
            funct7_t funct7 = (instr >> 25) & 0x7F;
            riscv_isa_reg_t rs2 = (instr >> 20) & 0x1F;
            riscv_isa_reg_t rs1 = (instr >> 15) & 0x1F;
            rtype_funct3_t rtype_funct3 = (instr >> 12) & 0x7;
            riscv_isa_reg_t rd = (instr >> 7) & 0x1F;
            switch (rtype_funct3)
            {
                // 3-bit function code for add or subtract
                case FUNCT3_ADD_SUB: {
                    switch (funct7)
                    {
                        // 7-bit function code for typical integer instructions: ADD
                        case FUNCT7_INT: {
                            uint32_t sum = register_read(cpu_state, rs1) + register_read(cpu_state, rs2);
                            register_write(cpu_state, rd, sum);
                            cpu_state->pc = cpu_state->pc + sizeof(instr);
                            break;
                        }

                        //7-bit function code for SUB

                        //note to self: assuming, as asked/answered on Piazza,
                        //the semantics on slides are for all but the operation
                        //should still change (at least that's what makes sense
                        //to me)
                        case FUNCT7_ALT_INT: {
                            uint32_t sum = register_read(cpu_state, rs1) - register_read(cpu_state, rs2);
                            register_write(cpu_state, rd, sum);
                            cpu_state->pc = cpu_state->pc + sizeof(instr);
                            break;
                        }

                        default: {
                            fprintf(stderr, "Encountered unknown R-type ADD/SUB"
                                    "7-bit funct7 code 0x%01x. Halting "
                                    "simulation.\n", funct7);
                            cpu_state->halted = true;
                            break;
                        }
                    }
                    break;
                }
                case FUNCT3_SLL: {
                    switch(funct7) 
                    {
                        case FUNCT7_INT: {
                            // rd <- rs1 << rs2[4:0] (shift amount is the low
                            // 5 bits of rs2 per the ISA; also avoids C UB for
                            // shifts >= 32)
                            uint32_t sum = register_read(cpu_state, rs1) << (register_read(cpu_state, rs2) & 0x1F);
                            register_write(cpu_state, rd, sum);
                            cpu_state->pc = cpu_state->pc + sizeof(instr);
                            break;
                        }
                        default: {
                            fprintf(stderr, "Encountered unknown R-type ADD/SUB"
                                    "7-bit funct7 code 0x%01x. Halting "
                                    "simulation.\n", funct7);
                            cpu_state->halted = true;
                            break;
                        }
                    }
                    break;
                }

                case FUNCT3_SRL_SRA : {
                    switch(funct7)
                    {
                        //this is SRL
                        case FUNCT7_INT: {
                            // shift amount is rs2[4:0] per the ISA
                            uint32_t sum = register_read(cpu_state, rs1) >> (register_read(cpu_state, rs2) & 0x1F);
                            register_write(cpu_state, rd, sum);
                            cpu_state->pc = cpu_state->pc + sizeof(instr);
                            break;
                        }
                        //this is SRA, shift right arithmetic, if signed 
                        //should be doing SRA on its own, but check later during
                        //debugging
                        case FUNCT7_ALT_INT: {
                            int32_t orig_num = register_read(cpu_state, rs1);
                            // shift amount is rs2[4:0] per the ISA
                            uint32_t shift_num = register_read(cpu_state, rs2) & 0x1F;
                            int32_t sum = orig_num >> shift_num;
                            register_write(cpu_state, rd, sum);
                            cpu_state->pc = cpu_state->pc + sizeof(instr);
                            break;
                        }
                        default: {
                            fprintf(stderr, "Encountered unknown R-type ADD/SUB"
                                    "7-bit funct7 code 0x%01x. Halting "
                                    "simulation.\n", funct7);
                            cpu_state->halted = true;
                            break;
                        }
                    }
                    break;
                }

                case FUNCT3_SLT: {
                    int32_t r_one = (int32_t)register_read(cpu_state, rs1);
                    int32_t r_two = (int32_t)register_read(cpu_state, rs2);
                    if (r_one < r_two) {
                        register_write(cpu_state, rd, 1);
                    }
                    else {
                        register_write(cpu_state, rd, 0);
                    }
                    cpu_state->pc = cpu_state->pc + sizeof(instr);
                    break;
                }

                case FUNCT3_SLTU :{
                    uint32_t r_one = (int32_t)register_read(cpu_state, rs1);
                    uint32_t r_two = (int32_t)register_read(cpu_state, rs2);
                    if (r_one < r_two) {
                        register_write(cpu_state, rd, 1);
                    }
                    else {
                        register_write(cpu_state, rd, 0);
                    }
                    cpu_state->pc = cpu_state->pc + sizeof(instr);
                    break;
                }

                case FUNCT3_XOR: {
                    uint32_t val = register_read(cpu_state, rs1) ^ register_read(cpu_state, rs2);
                    register_write(cpu_state, rd, val);
                    cpu_state->pc = cpu_state->pc + sizeof(instr);
                    break;
                }

                case FUNCT3_OR: {
                    uint32_t val = register_read(cpu_state, rs1) | register_read(cpu_state, rs2);
                    register_write(cpu_state, rd, val);
                    cpu_state->pc = cpu_state->pc + sizeof(instr);
                    break;
                }

                case FUNCT3_AND: {
                    uint32_t val = register_read(cpu_state, rs1) & register_read(cpu_state, rs2);
                    register_write(cpu_state, rd, val);
                    cpu_state->pc = cpu_state->pc + sizeof(instr);
                    break;
                }

                default: {
                    fprintf(stderr, "Encountered unknown R-type "
                            "3-bit funct3 code 0x%01x. Halting "
                            "simulation.\n",
                            rtype_funct3);
                    cpu_state->halted = true;
                    break;
                }
            }
            break;
        }

        // General I-type arithmetic operations: ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI (pg 18)
        case OP_IMM: {
            // form [imm[11:0] - 12 bits | rs1 - 5 bits | funct3 - 3 bits | rd - 5 bits | opcode - 7 bits]
            itype_int_funct3_t itype_funct3 = (instr >> 12) & 0x7;
            int32_t itype_imm = ((int32_t)instr) >> 20;
            uint32_t u_imm = (instr >> 20) &0x0FFF; //12 bits unsigned
            uint32_t imm7 = (instr>> 25) & 0x7F; //7bits
            riscv_isa_reg_t rs1 = (instr >> 15) & 0x1F;
            riscv_isa_reg_t rd = (instr >> 7) & 0x1F;
            switch (itype_funct3)
            {
                // 3-bit function code for ADDI
                case FUNCT3_ADDI: {
                    uint32_t sum = register_read(cpu_state, rs1) + itype_imm;
                    register_write(cpu_state, rd, sum);
                    cpu_state->pc = cpu_state->pc + sizeof(instr);
                    break;
                }

                // function code for SLLI

                case FUNCT3_SLLI : {
                    //shifts by unsigned imm [4:0]
                    switch(imm7) {
                        case 0x00: {
                            uint32_t sum = register_read(cpu_state, rs1) << (u_imm & 0x1F);
                            register_write(cpu_state, rd, sum);
                            cpu_state->pc = cpu_state->pc + sizeof(instr);
                            break;
                        }
                        default: {
                            fprintf(stderr, "Encountered unknown I-type "
                                    "3-bit funct3 code 0x%01x. Halting "
                                    "simulation.\n",
                                    itype_funct3);
                            cpu_state->halted = true;
                            break;
                        } 
                    }
                    break;
                }

                case FUNCT3_SRLI_SRAI : {
                    //imm[11:5], 7 bits is the distinguishing factor
                    switch(imm7) {
                        case 0x00: {
                            uint32_t sum = register_read(cpu_state, rs1) >> (u_imm & 0x1F);
                            register_write(cpu_state, rd, sum);
                            cpu_state->pc = cpu_state->pc + sizeof(instr);
                            break;
                        }
                        // for SRAI, not sure if the logic is entirely right though
                        case 0x20: {
                            int32_t sum = (int32_t)register_read(cpu_state, rs1) >> (u_imm & 0x1F);
                            register_write(cpu_state, rd, sum);
                            cpu_state->pc = cpu_state->pc + sizeof(instr);
                            break;
                        }
                        default: {
                            fprintf(stderr, "Encountered unknown I-type "
                                    "3-bit funct3 code 0x%01x. Halting "
                                    "simulation.\n",
                                    itype_funct3);
                            cpu_state->halted = true;
                            break;
                        }
                    }
                    break;
                }

                case FUNCT3_SLTI : {
                    int32_t r_one = register_read(cpu_state, rs1);
                    if (r_one < itype_imm) {
                        register_write(cpu_state, rd, 1);
                    }
                    else {
                        register_write(cpu_state, rd, 0);
                    }
                    cpu_state->pc = cpu_state->pc + sizeof(instr);
                    break;
                }

                case FUNCT3_SLTIU : {
                    uint32_t r_one = register_read(cpu_state, rs1);
                    if (r_one < (uint32_t)itype_imm) {
                        register_write(cpu_state, rd, 1);
                    }
                    else {
                        register_write(cpu_state, rd, 0);
                    }
                    cpu_state->pc = cpu_state->pc + sizeof(instr);
                    break;
                }

                case FUNCT3_XORI: {
                    uint32_t val = register_read(cpu_state, rs1) ^ itype_imm;
                    register_write(cpu_state, rd, val);
                    cpu_state->pc = cpu_state->pc + sizeof(instr);
                    break;
                }

                case FUNCT3_ORI: {
                    uint32_t val = register_read(cpu_state, rs1) | itype_imm;
                    register_write(cpu_state, rd, val);
                    cpu_state->pc = cpu_state->pc + sizeof(instr);
                    break;
                }

                case FUNCT3_ANDI: {
                    uint32_t val = register_read(cpu_state, rs1) & itype_imm;
                    register_write(cpu_state, rd, val);
                    cpu_state->pc = cpu_state->pc + sizeof(instr);
                    break;
                }

                default: {
                    fprintf(stderr, "Encountered unknown I-type 3-bit "
                            "funct3 code 0x%01x. Halting simulation.\n",
                            itype_funct3);
                    cpu_state->halted = true;
                    break;
                }
            }
            break;
        }

        // Load operations (I-type): LB, LH, LW, LBU, LHU (pg 24)
        case OP_LOAD: {
            // form [imm[11:0] - 12 bits | rs1 - 5 bits | funct3 - 3 bits | rd - 5 bits | opcode - 7 bits]
            itype_load_funct3_t itype_load_funct3 = (instr >> 12) & 0x7;
            int32_t itype_imm = ((int32_t)instr) >> 20;
            riscv_isa_reg_t rs1 = (instr >> 15) & 0x1F;
            riscv_isa_reg_t rd = (instr >> 7) & 0x1F;
            /* remember little endian order: i.e
             * in memory 0x01 0x02 0x03 0x04
             * read out 0x04 0x03 0x02 0x01
             */
            switch (itype_load_funct3)
            {
                // 3-bit function code for LW
                case FUNCT3_LW: {
                    uint32_t addr = register_read(cpu_state, rs1) + itype_imm;
                    //uint32_t aligned_addr = (addr >> 2) << 2;
                    //printf("offset: %x | reading from: %x\n", itype_imm, addr);
                    int32_t result = mem_read32(cpu_state, addr);
                    register_write(cpu_state, rd, result);
                    cpu_state->pc = cpu_state->pc + sizeof(instr);
                    break;
                }

                case FUNCT3_LB: {
                    uint32_t addr = register_read(cpu_state, rs1) + itype_imm;
                    uint32_t aligned_addr = (addr >> 2) << 2;
                    uint32_t index = addr % 4;
                    // shift until all that remains is the MSB of the read data
                    // would be 0x04 in the above example
                    //grab MSB
                    int32_t result = (mem_read32(cpu_state, aligned_addr) >> (index*8)) & 0xFF;
                    //sign extend it
                    result = (result << 24) >> 24;
                    register_write(cpu_state, rd, result);
                    cpu_state->pc = cpu_state->pc + sizeof(instr);
                    break;
                }

                case FUNCT3_LBU: {
                    uint32_t addr = register_read(cpu_state, rs1) + itype_imm;
                    uint32_t aligned_addr = (addr >> 2) << 2;
                    uint32_t index = addr % 4;
                    uint32_t result = (mem_read32(cpu_state, aligned_addr) >> (index*8)) & 0xFF;
                    register_write(cpu_state, rd, result);
                    cpu_state->pc = cpu_state->pc + sizeof(instr);
                    break;
                }

                case FUNCT3_LH: {
                    uint32_t addr = register_read(cpu_state, rs1) + itype_imm;
                    uint32_t aligned_addr = (addr >> 2) << 2;
                    uint32_t index = addr % 4;
                    int32_t result = (mem_read32(cpu_state, aligned_addr) >> (index*8)) & 0xFFFF;
                    result = (result << 16) >> 16;
                    register_write(cpu_state, rd, result);
                    cpu_state->pc = cpu_state->pc + sizeof(instr);
                    break;
                }

                case FUNCT3_LHU: {
                    uint32_t addr = register_read(cpu_state, rs1) + itype_imm;
                    uint32_t aligned_addr = (addr >> 2) << 2;
                    uint32_t index = addr % 4;
                    uint32_t result = (mem_read32(cpu_state, aligned_addr) >> (index*8)) & 0xFFFF;
                    register_write(cpu_state, rd, result);
                    cpu_state->pc = cpu_state->pc + sizeof(instr);
                    break;
                }

                default: {
                    fprintf(stderr, "Encountered unknown/unimplemented 3-bit "
                            "load function code 0x%01x. Halting simulation.\n",
                            itype_load_funct3);
                    cpu_state->halted = true;
                    break;
                }
            }
            break;
        }

        // Store operations (S-type): SB, SH, SW (pg 24)
        case OP_STORE: {
            // form [imm[11:5] - 7 bits | rs2 - 5 bits | rs1 - 5 bits | funct3 - 3 bits | imm[4:0] - 5 bits | opcode - 7 bits]
            stype_funct3_t stype_funct3 = (instr >> 12) & 0x7;

            
            //this is the immediate from the slides 
            uint32_t stype_offset = (((int32_t)instr >> 25) << 5) | ((instr >> 7) & 0x1F);

            riscv_isa_reg_t rs1 = (instr >> 15) & 0x1F;
            riscv_isa_reg_t rs2 = (instr >> 20) & 0x1F;

            switch (stype_funct3)
            {

                case FUNCT3_SB: {
                    uint32_t addr = register_read(cpu_state, rs1) + stype_offset;
                    uint32_t aligned_addr = (addr>>2)<<2;
                    
                    //read the aligned word
                    uint32_t data = mem_read32(cpu_state, aligned_addr);
                    uint32_t byte_offset = addr % 4;

                    //edit the desired byte
                    //offset = 0: 0000_00FF -> FFFF_FF00
                    //offset = 1: 0000_FF00 -> FFFF_00FF
                    uint32_t mask = ~(0xFF << (byte_offset * 8));
                    // only rs2[7:0] is stored; upper bits of rs2 must not
                    // leak into the neighboring byte lanes
                    uint32_t new_data = (data & mask) |
                    ((register_read(cpu_state, rs2) & 0xFF) << (byte_offset * 8));

                    //write it back
                    mem_write32(cpu_state, aligned_addr, new_data);

                    //update pc
                    cpu_state->pc = cpu_state->pc + sizeof(instr);
                    break;
                }

                //TODO: fix bitmasking
                case FUNCT3_SH: {
                    uint32_t addr = register_read(cpu_state, rs1) + stype_offset;
                    //printf("address: %x\n", addr);
                    uint32_t aligned_addr = (addr>>2)<<2;
                    
                    //read the aligned word
                    uint32_t data = mem_read32(cpu_state, aligned_addr);
                    //printf("old data: %x, %d\n", data, data);
                    uint32_t byte_offset = addr % 4;
                    //printf("offset: %d\n", byte_offset);

                    //edit the desired byte
                    //offset = 0: 0000_FFFF -> FFFF_0000
                    //offset = 1: FFFF_0000 -> 0000_FFFF
                    uint32_t mask = ~(0xFFFF << (byte_offset * 8));
                    //printf("mask: %x\n", mask);
                    // only rs2[15:0] is stored; upper bits of rs2 must not
                    // leak into the neighboring byte lanes
                    uint32_t new_data = (data & mask) |
                    ((register_read(cpu_state, rs2) & 0xFFFF) << (byte_offset * 8));
                    //printf("new data: %x\n", new_data);
                    //write it back
                    mem_write32(cpu_state, aligned_addr, new_data);

                    //update pc
                    cpu_state->pc = cpu_state->pc + sizeof(instr);
                    break;
                }

                case FUNCT3_SW: {
                    uint32_t addr = register_read(cpu_state, rs1) + stype_offset;
                    
                    //dont need to do any reading this time
                    uint32_t new_data = register_read(cpu_state, rs2);

                    //write it back
                    mem_write32(cpu_state, addr, new_data);

                    //update pc
                    cpu_state->pc = cpu_state->pc + sizeof(instr);
                    break;
                }

                default: {
                    fprintf(stderr, "Encountered unknown/unimplemented 3-bit "
                            "S-type function code 0x%01x. Halting simulation.\n",
                            stype_funct3);
                    cpu_state->halted = true;
                    break;
                }
            }
            break;
        }

        // Load Upper Immediate operation (U-type) (pg 19)
        case OP_LUI: {
            // form [imm[31:12] - 20 bits| rd - 5 bits | opcode - 7 bits]

            //cpu_state->pc = cpu_state->pc + sizeof(instr), 
            //which is pc = pc + 4; um default should be halted otherwise
            //we want to program count (?)
            uint32_t immed = ((uint32_t)instr) & 0xFFFFF000;
            riscv_isa_reg_t rd = (instr >> 7) & 0x1F;
            register_write(cpu_state, rd, immed);
            cpu_state->pc = cpu_state->pc + sizeof(instr);
            
            //probably shouldnt break
            //register_write(cpu_state, rd, result);
            break;
        }

        // Add Upper Immediate to PC operation (U-type) (pg 19)
        case OP_AUIPC: {
            // form [imm[31:12] - 20 bits| rd - 5 bits | opcode - 7 bits]
            //signed this time because might want to go backwards
            int32_t immed = (int32_t)instr & 0xFFFFF000;
            riscv_isa_reg_t rd = (instr >> 7) & 0x1F;
            register_write(cpu_state, rd, immed + cpu_state->pc);
            cpu_state->pc = cpu_state->pc + sizeof(instr);
            break;
        }

        // Jump and Link operation (UJ-type)
        case OP_JAL: {
            // form [imm[20 | 10 : 1 | 11 | 19 : 12] - 20 bits| rd - 5 bits | opcode - 7 bits]

            riscv_isa_reg_t rd = (instr >> 7) & 0x1F;
            //rd <- pc + 4
            register_write(cpu_state, rd, cpu_state->pc +sizeof(instr));

            //printf("scrambled immediate: %x\n", instr>>12);
            //build immediate
            uint32_t ujtype_offset_20 = (instr >> 31) & 0x1;              // 1 bit (imm[20] = instr[31])
            uint32_t ujtype_offset_10_1 = (instr >> 21) & 0x3FF;          // 10 bits (imm[10:1] = instr[30:21])
            uint32_t ujtype_offset_11 = (instr >> 20) & 0x1;              // 1 bit (imm[11] = instr[20])
            uint32_t ujtype_offset_19_12 = (instr >> 12) & 0xFF;          // 8 bits (imm[19:12] = instr[19:12])
            int32_t immed = (int32_t)( (ujtype_offset_20 << 20) | (ujtype_offset_19_12 << 12) | (ujtype_offset_11 << 11) | (ujtype_offset_10_1 << 1) );
            //sign extend the 21-bit immediate from bit 20
            immed = (immed << 11) >> 11;

            //pc <- pc + imm
            cpu_state->pc = cpu_state->pc + immed;
            break;
        }

        // Jump and Link Register operation (I-type)
        case OP_JALR: {
            // form [imm[11:0] - 12 bits | rs1 - 5 bits | 000 | rd - 5 bits | opcode - 7 bits]
            int32_t itype_imm = ((int32_t)instr) >> 20;
            riscv_isa_reg_t rs1 = (instr >> 15) & 0x1F;
            riscv_isa_reg_t rd = (instr >> 7) & 0x1F;
            
            //compute the target BEFORE writing rd: if rd == rs1, writing
            //first would corrupt the jump target
            uint32_t target = register_read(cpu_state, rs1) + (uint32_t)(itype_imm);
            target = target & 0xFFFFFFFE;

            //rd <- pc + 4
            register_write(cpu_state, rd, cpu_state->pc +sizeof(instr));

            cpu_state->pc = target;
            break;
        }

        // Branch operations (SB-type): BEQ, BNE, BLT, BGE, BLTU, BGEU (pg 22)
        case OP_BRANCH: {
            // form [ imm[12 | 10:5] - 7 bits | rs2 - 5 bits | rs1 - 5 bits | funct3 - 3 bits | imm[4:1 | 11] - 5 bits | opcode - 7 bits]
            sbtype_funct3_t sbtype_funct3 = (instr >> 12) & 0x7;
            uint32_t sbtype_offset_12 = (uint32_t)((int32_t)instr >> 31);
            uint32_t sbtype_offset_11 = (instr >> 7) & 0x1;
            uint32_t sbtype_offset_10_5 = (instr >> 25) & 0x3F; // 5 bits
            uint32_t sbtype_offset_4_1 = (instr >> 8) & 0xF;
            uint32_t sbtype_offset_0 = 0; 
            int32_t sbtype_offset = (int32_t)((sbtype_offset_12 << 12) | (sbtype_offset_11 << 11) | (sbtype_offset_10_5 << 5) | (sbtype_offset_4_1 << 1) | sbtype_offset_0);
            riscv_isa_reg_t rs1 = (instr >> 15) & 0x1F;
            riscv_isa_reg_t rs2 = (instr >> 20) & 0x1F;
            switch (sbtype_funct3)
            {
                // 3-bit function code for BEQ
                case FUNCT3_BEQ: {
                    uint32_t target = cpu_state->pc + sbtype_offset;
                    cpu_state->pc = (register_read(cpu_state, rs1) == register_read(cpu_state, rs2)) ? target : cpu_state->pc + sizeof(instr);
                    break;
                }

				case FUNCT3_BNE: {
                    uint32_t target = cpu_state->pc + sbtype_offset;
                    cpu_state->pc = (register_read(cpu_state, rs1) != register_read(cpu_state, rs2)) ? target : cpu_state->pc + sizeof(instr);
                    break;
                }

				case FUNCT3_BLT: {
                    uint32_t target = cpu_state->pc + sbtype_offset;
                    cpu_state->pc = ((int32_t)register_read(cpu_state, rs1) < (int32_t)register_read(cpu_state, rs2)) ? target : cpu_state->pc + sizeof(instr);
                    break;
                }

				case FUNCT3_BGE: {
                    uint32_t target = cpu_state->pc + sbtype_offset;
                    cpu_state->pc = ((int32_t)register_read(cpu_state, rs1) >= (int32_t)register_read(cpu_state, rs2)) ? target : cpu_state->pc + sizeof(instr);
                    break;
                }

				case FUNCT3_BLTU: {
                    uint32_t target = cpu_state->pc + sbtype_offset;
                    cpu_state->pc = (register_read(cpu_state, rs1) < register_read(cpu_state, rs2)) ? target : cpu_state->pc + sizeof(instr);
                    break;
                }

			    case FUNCT3_BGEU: {
                    uint32_t target = cpu_state->pc + sbtype_offset;
                    cpu_state->pc = (register_read(cpu_state, rs1) >= register_read(cpu_state, rs2)) ? target : cpu_state->pc + sizeof(instr);
                    break;
                }

                default: {
                    fprintf(stderr, "Encountered unknown/unimplemented 3-bit "
                            "SB-type function code 0x%01x. Halting simulation.\n",
                            sbtype_funct3);
                    cpu_state->halted = true;
                    break;
                }
            }
            break;
        }

        // General system operation (I-type): ECALL
        case OP_SYSTEM: {
            // form [funct12 - 12 bits | all 0's | opcode - 7 bits]
            itype_funct12_t sys_funct12 = (instr >> 20) & 0xFFF;
            switch (sys_funct12)
            {
                // 12-bit function code for ECALL
                case FUNCT12_ECALL: {
                    uint32_t a0_value = register_read(cpu_state, REG_A0);
                    if (a0_value == ECALL_ARG_HALT) {
                        fprintf(stdout, "ECALL invoked with halt argument, "
                                "halting the simulator.\n");
                        cpu_state->halted = true;
                    }
                    else {
                        cpu_state->pc = cpu_state->pc + sizeof(instr);
                    }
                    break;
                }

                default: {
                    fprintf(stderr, "Encountered unknown/unimplemented 12-bit "
                            "system function code 0x%03x. Halting "
                            "simulation.\n", sys_funct12);
                    cpu_state->halted = true;
                    break;
                }
            }
            break;
        }

        default: {
            fprintf(stderr, "Encountered unknown opcode 0x%02x. Halting "
                    "simulation.\n", opcode);
            cpu_state->halted = true;
            break;
        }
    }

    return;
}