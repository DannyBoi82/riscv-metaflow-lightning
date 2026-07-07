/**
 * multest.S
 *
 * Mul Test
 *
 * This test exercises the mul instruction in the RISC-V ISA.
 **/

/**
 * When files have a *.S extension, the compiler will run the preprocessor on
 * the file before assembling it. Thus, you can leverage the C preprocessor
 * (#define, #include, #ifdef, etc.) in your assembly code.
 *
 * Also, you can use C++-style comments (//) in addition to the normal assembly
 * comments (#, slash-*). Be careful with using #, because certain words
 * (e.g. if, define, etc.) may be interpreted as preprocessor directives.
 **/

// The initial value to seed the test with
#define TEST_SEED               512

    .text                       // Declare the code to be in the .text segment
    .global main                // Make main visible to the linker
main:
    addi  t0, zero, 1           // t0=1 
    addi  t1, zero, 2           // t1=2
    addi  t2, zero, -1          // t2=-1
    addi  t6, zero, -1          // t6=-1
    mul   t3, t0, t1            // t3=2
    mul   t3, t3, t1            // t3=4
    mul   t3, t3, t1            // t3=8
    mul   t3, t3, t1            // t6=16
    mul   t4, t3, t2            // t4=-16; note mul is half-length and unsigned
    mul   t5, t4, t2            // t5=16; mul is half-length and unsigned
    mul   t6, t5, zero          // t6=0

    addi  a0, zero, 0xa         // a0 (x10) = 0xa
    ecall                       // Terminate the simulation by passing 0xa to
                                // ecall in register a0 (x10).
