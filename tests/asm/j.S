    .text
    .global main
main:
    j foo
    addi x1, x0, 11
    addi x10, x0, 10
    ecall

foo:
    j bar
    addi x1, x0, 22
    addi x10, x0, 10
    ecall

bar:
    addi x1, x0, 33
    addi x10, x0, 10
    ecall
