    .text
    .global main
main:
    addi x8, x0, 0xf0
    addi x9, x0, 0x0f
    addi x11, x0, 0xf0

	beq x0, x0, here
back:	
    beq x8, x9, nottaken
    beq x0, x0, taken1
    addi x1, x0, 1
    addi x10, x0, 10
    ecall

there:
	beq x0, x0, where
	
nottaken:
    addi x1, x0, 2
    addi x10, x0, 10
    ecall

taken1:
    beq x8, x11, taken2
    addi x1, x0, 3
    addi x10, x0, 10
    ecall

taken2:
    addi x1, x0, 4
    addi x10, x0, 10
    ecall

here:
	beq x8, x9, here
	beq x8, x9, here
	beq x8, x9, here
	beq x8, x9, here
	beq x8, x9, next
	beq x8, x9, next
	beq x8, x9, next
	beq x8, x9, next
next:	
	beq x0, x0, there
where:
	beq x0, x0, back	
