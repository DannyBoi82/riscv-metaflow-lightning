# jal_fwd_test.s
# Tests that JAL correctly forwards npc_plus4 (return addr) not alu_out (target)
# when the BTB predicts it correctly.
#
# First call: BTB cold miss, flushes — x1 gets written from WB, sw stores correctly
# Second call: BTB hit, no flush — x1 must be forwarded from M1/M2, not alu_out
# If forwarding is broken, jalr on the second return jumps to fibr entry not past the call

.text
.globl _start
_start:

    jal  x1, callee       # call 1: BTB cold miss, safe
    jal  x1, callee       # call 2: BTB hit — x1 forwarding must be npc_plus4

    addi    a0, zero, 0xa       # a0 (x10) = 0xa
    ecall                      # Terminate the simulation by passing 0xa to
                                # ecall in register a0 (x10).
callee:
    # immediately use x1 — this is the hazard window
    addi x2, x2, -4
    sw   x1, 0(x2)        # store return addr — forwarded x1 must be correct here
    lw   x1, 0(x2)
    addi x2, x2, 4
    jalr x0, 0(x1)        # return — goes wrong if x1 was forwarded incorrectly