    .text
    .global main
main:
    jal x20, foo
    addi x1, x0, 1
    addi x10, x0, 10
    ecall

foo:
    jal x21, bar
    addi x1, x0, 2
    addi x10, x0, 10
    ecall

bar:
    addi x1, x0, 3
    addi x10, x0, 10
    ecall
