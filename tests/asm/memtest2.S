/**
 * memtest2.S
 **/

// The size of the data section accessed, in bytes
#define DATA_SEG_SIZE           128

    .data                       // Declare items to be in the .data segment
data:                           // Symbol representing the start of .data
    // Preset data for testing
    .word -1                    // 0x00: -1
    .word -2                    // 0x04: -2
    .word -3                    // 0x08: -3
    .word -4                    // 0x0C: -4
    .word -11                   // 0x10: -11
    .word -12                   // 0x14: -12
    .word -13                   // 0x18: -13
    .word -14                   // 0x1C: -14
    .word -21                   // 0x20: -21
    .word -22                   // 0x24: -22
    .word -23                   // 0x28: -23
    .word -24                   // 0x2C: -24
    .word -31                   // 0x30: -31
    .word -32                   // 0x34: -32
    .word -33                   // 0x38: -33
    .word -34                   // 0x3C: -34
    .space  DATA_SEG_SIZE - 64  // Allocate remaining space for the .data segment
data_end:                       // Symbol representing the end of .data

    .text                       // Declare the code to be in the .text segment
    .global main                // Make main visible to the linker
main:
    add     x1,  zero,  gp      // At program start gp has the start of the
                                // .data segment. x1 = gp (x3)
    
    // Save original data pointer for reading initialized data
    addi    x30, x1, 0          // x30 = x1 (save original data pointer)
    
    // Move pointer for all store operations to offset 64
    addi    x1, x1, 64          // x1 = x1 + 64 (new base address for stores)
    
    // Initialize test values
    li      x5,  255     // x5 = 255
    li      x6,  513     // x6 = 513
    li      x7,  1027    // x7 = 1027
    li      x8,  2049    // x8 = 2049
    li      x18, 4096    // x18 = 4096
    li      x19, 8192    // x19 = 8192
    li      x20, 16384   // x20 = 16384
    li      x21, 32768   // x21 = 32768

    // Test 1: Back-to-back stores to the same address
    sw      x5,  0(x1)          // *(x1 + 0) = x5
    sw      x6,  0(x1)          // *(x1 + 0) = x6
    sw      x7,  0(x1)          // *(x1 + 0) = x7
    sw      x8,  0(x1)          // *(x1 + 0) = x8
    lw      x9,  0(x1)          // x9 = *(x1 + 0) - should be x8's value

    // Test 2: Store followed immediately by load from same address
    sw      x6,  4(x1)          // *(x1 + 4) = x6
    lw      x10, 4(x1)          // x10 = *(x1 + 4) - should be x6's value
    
    // Test 3: Load followed immediately by store to same address
    sw      x6,  8(x1)
    lw      x11, 8(x1)          // x11 = *(x1 + 8) - x6
    sw      x7,  8(x1)          // *(x1 + 8) = x7
    lw      x12, 8(x1)          // x12 = *(x1 + 8) - should be x7's value

    // Test 4: Interleaved loads and stores to different addresses
    sw      x8,  12(x1)         // *(x1 + 12) = x8
    lw      x13, 4(x1)          // x13 = *(x1 + 4) - should be x6's value
    sw      x5,  16(x1)         // *(x1 + 16) = x5
    lw      x14, 12(x1)         // x14 = *(x1 + 12) - should be x8's value
    
    // Test 5: Multiple access patterns
    sw      x18, 20(x1)         // *(x1 + 20) = x18
    sw      x19, 24(x1)         // *(x1 + 24) = x19
    sw      x20, 28(x1)         // *(x1 + 28) = x20
    sw      x21, 32(x1)         // *(x1 + 32) = x21
    
    // Non-sequential loads
    lw      x22, 32(x1)         // x22 = *(x1 + 32) - should be x21's value
    lw      x23, 20(x1)         // x23 = *(x1 + 20) - should be x18's value
    lw      x24, 28(x1)         // x24 = *(x1 + 28) - should be x20's value
    lw      x25, 24(x1)         // x25 = *(x1 + 24) - should be x19's value
    
    // Test 6: 4 byte stride memory access 
    addi    x4,  x1,    36      // x4 = x1 + 36 (new base address)
    sw      x5,  0(x4)          // *(x4 + 0) = x5
    sw      x6,  4(x4)          // *(x4 + 4) = x6
    sw      x7,  8(x4)          // *(x4 + 8) = x7
    sw      x8,  12(x4)         // *(x4 + 12) = x8
    lw      x26, 0(x4)          // x26 = *(x4 + 0) - should be x5's value
    lw      x27, 12(x4)         // x27 = *(x4 + 12) - should be x8's value
    lw      x28, 4(x4)          // x28 = *(x4 + 4) - should be x6's value
    lw      x29, 8(x4)          // x29 = *(x4 + 8) - should be x7's value
    
    // Test 7: Back-to-back stores with different word alignments
    // Store bytes and half-words to test alignment and byte-enable logic
    sb      x5,  52(x1)         // *(x1 + 52)[7:0] = x5[7:0]
    sb      x6,  53(x1)         // *(x1 + 53)[7:0] = x6[7:0]
    sh      x7,  54(x1)         // *(x1 + 54)[15:0] = x7[15:0]
    lw      x30, 52(x1)         // x30 = *(x1 + 52) - combined value
    
    // Test 8: More stores and loads
    sw      x18, 56(x1)         // *(x1 + 56) = x18
    sw      x19, 60(x1)         // *(x1 + 60) = x19
    lw      x31, 56(x1)         // x31 = *(x1 + 56) - should be x18's value
    sw      x20, 56(x1)         // *(x1 + 56) = x20
    lw      x30, 56(x1)         // x30 = *(x1 + 56) - should be x20's value

    // Test 9: Multiple stores to load
    sw      x18, 56(x1)
    sw      x19, 56(x1)
    sw      x20, 56(x1)
    lw      x4,  56(x1)

    // Test 10: Strided memory reads using initialized data (from .word directives)
    // Save the original base pointer
    addi    x30, x1, 0          // x30 = x1 (save original data pointer)
    
    // Strided by 16 bytes (4 words)
    lw      x2,  0(x30)         // x2 = *(x30 + 0) = -1
    lw      x3,  16(x30)        // x3 = *(x30 + 16) = -11
    lw      x4,  32(x30)        // x4 = *(x30 + 32) = -21
    lw      x5,  48(x30)        // x5 = *(x30 + 48) = -31
    
    // Backwards strided by 16 bytes
    addi    x6,  x30,  48       // x6 = x30 + 48
    lw      x7,  0(x6)          // x7 = *(x6 + 0) = -31
    lw      x8,  -16(x6)        // x8 = *(x6 - 16) = -21
    lw      x9,  -32(x6)        // x9 = *(x6 - 32) = -11
    lw      x10, -48(x6)        // x10 = *(x6 - 48) = -1
    
    // Strided by 4 bytes (adjacent words)
    lw      x11, 0(x30)         // x11 = *(x30 + 0) = -1
    lw      x12, 4(x30)         // x12 = *(x30 + 4) = -2
    lw      x13, 8(x30)         // x13 = *(x30 + 8) = -3
    lw      x14, 12(x30)        // x14 = *(x30 + 12) = -4
    
    // Alternate strided pattern
    lw      x15, 0(x30)         // x15 = *(x30 + 0) = -1
    lw      x16, 8(x30)         // x16 = *(x30 + 8) = -3
    lw      x17, 16(x30)        // x17 = *(x30 + 16) = -11
    lw      x18, 24(x30)        // x18 = *(x30 + 24) = -13

    // Calculate a checksum for easy comparison
    add     x2, zero,  x9       // x2 = x9
    add     x2, x2,    x10      // x2 = x2 + x10
    add     x2, x2,    x12      // x2 = x2 + x12
    add     x2, x2,    x13      // x2 = x2 + x13
    add     x2, x2,    x14      // x2 = x2 + x14
    add     x2, x2,    x22      // x2 = x2 + x22
    add     x2, x2,    x23      // x2 = x2 + x23
    add     x2, x2,    x24      // x2 = x2 + x24
    add     x2, x2,    x25      // x2 = x2 + x25
    add     x2, x2,    x26      // x2 = x2 + x26
    add     x2, x2,    x27      // x2 = x2 + x27
    add     x2, x2,    x28      // x2 = x2 + x28
    add     x2, x2,    x29      // x2 = x2 + x29
    add     x2, x2,    x30      // x2 = x2 + x30
    add     x2, x2,    x31      // x2 = x2 + x31

    addi    a0,  zero,  0x7
    addi    a0,  zero,  0xa     // a0 (x10) = 0xa
    ecall                       // Terminate the simulation by passing 0xa to
                                // ecall in register a0 (x10).