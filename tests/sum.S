.global _start
_start:
    addi x1, x0, 0
    addi x2, x0, 1
    addi x3, x0, 10
loop:
    add  x1, x1, x2
    addi x2, x2, 1
    ble  x2, x3, loop
    li   a7, 93
    ecall
