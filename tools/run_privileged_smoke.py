#!/usr/bin/env python3

import subprocess
import tempfile
import textwrap
from pathlib import Path

from run_emulator_tests import EMU_DIR, build_emulator
from run_rtl_elf_tests import ROOT, build_sim, elf_to_words, run_vvp
from run_state_diff import compare_states, parse_state


LD = r"""
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;
  .text : { *(.text.init) *(.text*) }
  .rodata : { *(.rodata*) }
  .data : { *(.data*) }
  .bss : { *(.bss*) *(COMMON) }
  . = ALIGN(8);
  .tohost : { *(.tohost) }
}
"""


ASM_INTERRUPT = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, trap_handler
    csrw mtvec, t0
    li t0, 0x80
    csrw mie, t0
    li t0, 0x8
    csrs mstatus, t0

irq_window:
    addi s0, s0, 1
irq_resume:
    addi s0, s0, 1
    addi s0, s0, 1
    addi s0, s0, 1

wait_irq:
    la t0, flag
    ld t1, 0(t0)
    beqz t1, irq_window

    la t0, saved_cause
    ld t1, 0(t0)
    li t2, 0x8000000000000007
    bne t1, t2, fail

    la t0, saved_tval
    ld t1, 0(t0)
    bnez t1, fail

    la t0, saved_mip
    ld t1, 0(t0)
    li t2, 0x80
    and t1, t1, t2
    beqz t1, fail

    la t0, saved_epc
    ld t1, 0(t0)
    andi t2, t1, 3
    bnez t2, fail
    li t2, 0x80000000
    bltu t1, t2, fail

pass:
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

trap_handler:
    csrr t0, mcause
    la t1, saved_cause
    sd t0, 0(t1)
    csrr t0, mepc
    la t1, saved_epc
    sd t0, 0(t1)
    csrr t0, mtval
    la t1, saved_tval
    sd t0, 0(t1)
    csrr t0, mip
    la t1, saved_mip
    sd t0, 0(t1)
    li t0, 1
    la t1, flag
    sd t0, 0(t1)
    csrwi mie, 0
    mret

    .section .bss
    .align 3
flag:
    .dword 0
saved_cause:
    .dword 0
saved_epc:
    .dword 0
saved_tval:
    .dword 0
saved_mip:
    .dword 0

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_MACHINE_EXTERNAL_IRQ = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, trap_handler
    csrw mtvec, t0
    li t0, 0x800
    csrw mie, t0
    li t0, 0x8
    csrs mstatus, t0

irq_window:
    addi s0, s0, 1
irq_resume:
    addi s0, s0, 1
    addi s0, s0, 1
    addi s0, s0, 1

wait_irq:
    la t0, flag
    ld t1, 0(t0)
    beqz t1, irq_window

    la t0, saved_cause
    ld t1, 0(t0)
    li t2, 0x800000000000000b
    bne t1, t2, fail

    la t0, saved_tval
    ld t1, 0(t0)
    bnez t1, fail

    la t0, saved_mip
    ld t1, 0(t0)
    li t2, 0x800
    and t1, t1, t2
    beqz t1, fail

    la t0, saved_epc
    ld t1, 0(t0)
    andi t2, t1, 3
    bnez t2, fail
    li t2, 0x80000000
    bltu t1, t2, fail

pass:
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

trap_handler:
    csrr t0, mcause
    la t1, saved_cause
    sd t0, 0(t1)
    csrr t0, mepc
    la t1, saved_epc
    sd t0, 0(t1)
    csrr t0, mtval
    la t1, saved_tval
    sd t0, 0(t1)
    csrr t0, mip
    la t1, saved_mip
    sd t0, 0(t1)
    li t0, 1
    la t1, flag
    sd t0, 0(t1)
    csrwi mie, 0
    mret

    .section .bss
    .align 3
flag:
    .dword 0
saved_cause:
    .dword 0
saved_epc:
    .dword 0
saved_tval:
    .dword 0
saved_mip:
    .dword 0

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_S_MODE_MACHINE_TIMER_IRQ = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, trap_handler
    csrw mtvec, t0
    li t0, 0x80
    csrw mie, t0
    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    la t0, s_entry
    csrw mepc, t0
    mret

s_entry:
    csrr t0, sstatus
    andi t0, t0, 2
    bnez t0, fail

irq_window:
    addi s0, s0, 1
irq_resume:
    addi s0, s0, 1
    addi s0, s0, 1
    addi s0, s0, 1

wait_irq:
    la t0, flag
    ld t1, 0(t0)
    beqz t1, irq_window

    la t0, saved_cause
    ld t1, 0(t0)
    li t2, 0x8000000000000007
    bne t1, t2, fail

    la t0, saved_tval
    ld t1, 0(t0)
    bnez t1, fail

    la t0, saved_mstatus
    ld t1, 0(t0)
    li t2, 0x1800
    and t1, t1, t2
    li t2, 0x800
    bne t1, t2, fail

    la t0, saved_mip
    ld t1, 0(t0)
    li t2, 0x80
    and t1, t1, t2
    beqz t1, fail

    la t0, saved_epc
    ld t1, 0(t0)
    andi t2, t1, 3
    bnez t2, fail
    li t2, 0x80000000
    bltu t1, t2, fail

pass:
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

trap_handler:
    csrr t0, mcause
    la t1, saved_cause
    sd t0, 0(t1)
    csrr t0, mepc
    la t1, saved_epc
    sd t0, 0(t1)
    csrr t0, mtval
    la t1, saved_tval
    sd t0, 0(t1)
    csrr t0, mstatus
    la t1, saved_mstatus
    sd t0, 0(t1)
    csrr t0, mip
    la t1, saved_mip
    sd t0, 0(t1)
    li t0, 1
    la t1, flag
    sd t0, 0(t1)
    csrwi mie, 0
    mret

    .section .bss
    .align 3
flag:
    .dword 0
saved_cause:
    .dword 0
saved_epc:
    .dword 0
saved_tval:
    .dword 0
saved_mstatus:
    .dword 0
saved_mip:
    .dword 0

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_S_MODE_MACHINE_EXTERNAL_IRQ = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, trap_handler
    csrw mtvec, t0
    li t0, 0x800
    csrw mie, t0
    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    la t0, s_entry
    csrw mepc, t0
    mret

s_entry:
    csrr t0, sstatus
    andi t0, t0, 2
    bnez t0, fail

irq_window:
    addi s0, s0, 1
irq_resume:
    addi s0, s0, 1
    addi s0, s0, 1
    addi s0, s0, 1

wait_irq:
    la t0, flag
    ld t1, 0(t0)
    beqz t1, irq_window

    la t0, saved_cause
    ld t1, 0(t0)
    li t2, 0x800000000000000b
    bne t1, t2, fail

    la t0, saved_tval
    ld t1, 0(t0)
    bnez t1, fail

    la t0, saved_mstatus
    ld t1, 0(t0)
    li t2, 0x1800
    and t1, t1, t2
    li t2, 0x800
    bne t1, t2, fail

    la t0, saved_mip
    ld t1, 0(t0)
    li t2, 0x800
    and t1, t1, t2
    beqz t1, fail

    la t0, saved_epc
    ld t1, 0(t0)
    andi t2, t1, 3
    bnez t2, fail
    li t2, 0x80000000
    bltu t1, t2, fail

pass:
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

trap_handler:
    csrr t0, mcause
    la t1, saved_cause
    sd t0, 0(t1)
    csrr t0, mepc
    la t1, saved_epc
    sd t0, 0(t1)
    csrr t0, mtval
    la t1, saved_tval
    sd t0, 0(t1)
    csrr t0, mstatus
    la t1, saved_mstatus
    sd t0, 0(t1)
    csrr t0, mip
    la t1, saved_mip
    sd t0, 0(t1)
    li t0, 1
    la t1, flag
    sd t0, 0(t1)
    csrwi mie, 0
    mret

    .section .bss
    .align 3
flag:
    .dword 0
saved_cause:
    .dword 0
saved_epc:
    .dword 0
saved_tval:
    .dword 0
saved_mstatus:
    .dword 0
saved_mip:
    .dword 0

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_SUPERVISOR_ECALL_TO_M = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, m_trap
    csrw mtvec, t0
    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    la t0, s_entry
    csrw mepc, t0
    mret

s_entry:
s_ecall:
    ecall
    j fail

m_trap:
    csrr t0, mcause
    li t1, 9
    bne t0, t1, fail
    csrr t0, mepc
    la t1, s_ecall
    bne t0, t1, fail
    csrr t0, mtval
    bnez t0, fail
    csrr t0, mstatus
    li t1, 0x1800
    and t0, t0, t1
    li t1, 0x800
    bne t0, t1, fail
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_DELEGATED_BREAKPOINT = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, fail_trap
    csrw mtvec, t0
    la t0, s_trap
    csrw stvec, t0
    li t0, 8
    csrw medeleg, t0
    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    la t0, s_entry
    csrw mepc, t0
    mret

s_entry:
do_break:
    ebreak
    j fail

s_trap:
    csrr t0, scause
    li t1, 3
    bne t0, t1, fail
    csrr t0, sepc
    la t1, do_break
    bne t0, t1, fail
    la t0, pass
    csrw sepc, t0
    sret

fail_trap:
    j fail

pass:
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_DELEGATED_USER_ECALL = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, fail_trap
    csrw mtvec, t0
    la t0, s_trap
    csrw stvec, t0
    li t0, 0x100
    csrw medeleg, t0
    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    la t0, s_entry
    csrw mepc, t0
    mret

s_entry:
    li t0, 0x100
    csrc sstatus, t0
    la t0, user_entry
    csrw sepc, t0
    sret

user_entry:
    ecall
    j fail

s_trap:
    csrr t0, scause
    li t1, 8
    bne t0, t1, fail
    csrr t0, sepc
    la t1, user_entry
    bne t0, t1, fail
    la t0, user_pass
    csrw sepc, t0
    sret

fail_trap:
    j fail

user_pass:
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_SUPERVISOR_SOFTIRQ = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, fail_trap
    csrw mtvec, t0
    la t0, s_trap
    csrw stvec, t0
    li t0, 2
    csrw sie, t0
    csrw sip, t0
    csrw mideleg, t0
    csrs sstatus, t0
    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    la t0, s_entry
    csrw mepc, t0
    mret

s_entry:
    j fail

s_trap:
    csrr t0, scause
    li t1, 0x8000000000000001
    bne t0, t1, fail
    csrr t0, sepc
    la t1, s_entry
    bne t0, t1, fail
    csrr t0, sip
    li t1, 2
    and t0, t0, t1
    beqz t0, fail
    csrwi sip, 0
    la t0, after_irq
    csrw sepc, t0
    sret

fail_trap:
    j fail

after_irq:
    csrr t0, sip
    li t1, 2
    and t0, t0, t1
    bnez t0, fail
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_SUPERVISOR_TIMER_IRQ = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, fail_trap
    csrw mtvec, t0
    la t0, s_trap
    csrw stvec, t0
    li t0, 0x20
    csrw sie, t0
    csrw sip, t0
    csrw mideleg, t0
    li t1, 0x2
    csrs sstatus, t1
    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    la t0, s_entry
    csrw mepc, t0
    mret

s_entry:
    j fail

s_trap:
    csrr t0, scause
    li t1, 0x8000000000000005
    bne t0, t1, fail
    csrr t0, sepc
    la t1, s_entry
    bne t0, t1, fail
    csrr t0, sip
    li t1, 0x20
    and t0, t0, t1
    beqz t0, fail
    csrwi sip, 0
    la t0, after_irq
    csrw sepc, t0
    sret

fail_trap:
    j fail

after_irq:
    csrr t0, sip
    li t1, 0x20
    and t0, t0, t1
    bnez t0, fail
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_SUPERVISOR_EXTERNAL_IRQ = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, fail_trap
    csrw mtvec, t0
    la t0, s_trap
    csrw stvec, t0
    li t0, 0x200
    csrw sie, t0
    csrw sip, t0
    csrw mideleg, t0
    li t1, 0x2
    csrs sstatus, t1
    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    la t0, s_entry
    csrw mepc, t0
    mret

s_entry:
    j fail

s_trap:
    csrr t0, scause
    li t1, 0x8000000000000009
    bne t0, t1, fail
    csrr t0, sepc
    la t1, s_entry
    bne t0, t1, fail
    csrr t0, sip
    li t1, 0x200
    and t0, t0, t1
    beqz t0, fail
    csrwi sip, 0
    la t0, after_irq
    csrw sepc, t0
    sret

fail_trap:
    j fail

after_irq:
    csrr t0, sip
    li t1, 0x200
    and t0, t0, t1
    bnez t0, fail
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_U_MODE_SUPERVISOR_TIMER_IRQ = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, fail_trap
    csrw mtvec, t0
    la t0, s_trap
    csrw stvec, t0
    li t0, 0x20
    csrw sie, t0
    csrw sip, t0
    csrw mideleg, t0
    li t0, 0x1800
    csrc mstatus, t0
    la t0, u_entry
    csrw mepc, t0
    mret

u_entry:
    j fail

s_trap:
    csrr t0, scause
    li t1, 0x8000000000000005
    bne t0, t1, fail
    csrr t0, sepc
    la t1, u_entry
    bne t0, t1, fail
    csrr t0, sip
    li t1, 0x20
    and t0, t0, t1
    beqz t0, fail
    csrwi sip, 0
    la t0, after_irq
    csrw sepc, t0
    sret

fail_trap:
    j fail

after_irq:
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_S_MODE_SUPERVISOR_TIMER_MASKED = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, fail_trap
    csrw mtvec, t0
    la t0, s_trap
    csrw stvec, t0
    li t0, 0x20
    csrw sie, t0
    csrw sip, t0
    csrw mideleg, t0
    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    la t0, s_entry
    csrw mepc, t0
    mret

s_entry:
    li s0, 8
1:
    addi s0, s0, -1
    bnez s0, 1b

    csrr t0, scause
    bnez t0, fail
    csrr t0, sepc
    bnez t0, fail
    csrr t0, sip
    li t1, 0x20
    and t0, t0, t1
    beqz t0, fail
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
2:
    j 2b

s_trap:
    j fail

fail_trap:
    j fail

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
3:
    j 3b

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_SUPERVISOR_BREAKPOINT_TO_M = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, m_trap
    csrw mtvec, t0
    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    la t0, s_entry
    csrw mepc, t0
    mret

s_entry:
s_break:
    ebreak
    j fail

m_trap:
    csrr t0, mcause
    li t1, 3
    bne t0, t1, fail
    csrr t0, mepc
    la t1, s_break
    bne t0, t1, fail
    csrr t0, mtval
    bnez t0, fail
    csrr t0, mstatus
    li t1, 0x1800
    and t0, t0, t1
    li t1, 0x800
    bne t0, t1, fail
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_SRET_PENDING_SUPERVISOR_IRQ = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, fail_trap
    csrw mtvec, t0
    la t0, s_trap
    csrw stvec, t0
    li t0, 0x20
    csrw sie, t0
    csrw mideleg, t0
    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    la t0, s_entry
    csrw mepc, t0
    mret

s_entry:
    la t0, user_entry
    csrw sepc, t0
    li t0, 0x20
    csrw sip, t0
do_sret:
    sret
    j fail

user_entry:
    j fail

s_trap:
    csrr t0, scause
    li t1, 0x8000000000000005
    bne t0, t1, fail
    csrr t0, sepc
    la t1, user_entry
    bne t0, t1, fail
    csrwi sip, 0
    la t0, after_irq
    csrw sepc, t0
    sret

fail_trap:
    j fail

after_irq:
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_TVM_SFENCE = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, trap_handler
    csrw mtvec, t0
    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    li t0, 0x100000
    csrs mstatus, t0
    la t0, s_entry
    csrw mepc, t0
    mret

s_entry:
bad_sfence:
    sfence.vma
    j fail

trap_handler:
    csrr t0, mcause
    li t1, 2
    bne t0, t1, fail
    csrr t0, mepc
    la t1, bad_sfence
    bne t0, t1, fail
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_TVM_SATP = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, trap_handler
    csrw mtvec, t0
    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    li t0, 0x100000
    csrs mstatus, t0
    la t0, s_entry
    csrw mepc, t0
    mret

s_entry:
bad_satp:
    csrr t2, satp
    j fail

trap_handler:
    csrr t0, mcause
    li t1, 2
    bne t0, t1, fail
    csrr t0, mepc
    la t1, bad_satp
    bne t0, t1, fail
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_TSR_SRET = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, trap_handler
    csrw mtvec, t0
    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    li t0, 0x400000
    csrs mstatus, t0
    la t0, s_entry
    csrw mepc, t0
    mret

s_entry:
    la t0, after_sret
    csrw sepc, t0
bad_sret:
    sret
    j fail

after_sret:
    j fail

trap_handler:
    csrr t0, mcause
    li t1, 2
    bne t0, t1, fail
    csrr t0, mepc
    la t1, bad_sret
    bne t0, t1, fail
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_S_PAGE_FAULT_THEN_PENDING_SUPERVISOR_IRQ = r"""
    .option norvc
    .section .text.init
    .globl _start
    .equ USER_VA, 0x0000000040000000
_start:
    la t0, fail_trap
    csrw mtvec, t0
    la t0, s_trap
    csrw stvec, t0

    li t0, 0x2000
    csrw medeleg, t0
    li t0, 0x20
    csrw mideleg, t0
    csrw sie, t0

    la t0, l1_pt
    srli t0, t0, 12
    slli t0, t0, 10
    ori t0, t0, 1
    la t1, root_pt + 8
    sd t0, 0(t1)

    la t0, _start
    srli t0, t0, 12
    slli t0, t0, 10
    li t1, 0xcf
    or t0, t0, t1
    la t1, root_pt + 16
    sd t0, 0(t1)

    la t0, l0_pt
    srli t0, t0, 12
    slli t0, t0, 10
    ori t0, t0, 1
    la t1, l1_pt
    sd t0, 0(t1)

    la t0, user_page
    srli t0, t0, 12
    slli t0, t0, 10
    li t1, 0x87
    or t0, t0, t1
    la t1, l0_pt
    sd t0, 0(t1)

    la t0, phase
    sd zero, 0(t0)

    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    la t0, s_entry
    csrw mepc, t0
    mret

s_entry:
    la t0, root_pt
    srli t1, t0, 12
    li t2, 0x8000000000000000
    or t1, t1, t2
    csrw satp, t1
    sfence.vma
    li t0, 0x20
    csrw sip, t0
    li t2, USER_VA
bad_load:
    ld t3, 0(t2)
    j fail

s_trap:
    la t0, phase
    ld t1, 0(t0)
    beqz t1, phase_page_fault
    li t2, 1
    beq t1, t2, phase_interrupt
    j fail

phase_page_fault:
    csrr t2, scause
    li t3, 13
    bne t2, t3, fail
    csrr t2, sepc
    la t3, bad_load
    bne t2, t3, fail
    csrr t2, stval
    li t3, USER_VA
    bne t2, t3, fail
    csrr t2, sip
    li t3, 0x20
    and t2, t2, t3
    beqz t2, fail
    li t2, 1
    sd t2, 0(t0)
    csrwi satp, 0
    sfence.vma
    la t2, after_fault
    csrw sepc, t2
    li t2, 0x20
    csrs sstatus, t2
    sret

phase_interrupt:
    csrr t2, scause
    li t3, 0x8000000000000005
    bne t2, t3, fail
    csrr t2, sepc
    la t3, after_fault
    bne t2, t3, fail
    csrr t2, stval
    bnez t2, fail
    csrwi sip, 0
    li t2, 2
    sd t2, 0(t0)
    la t2, after_irq
    csrw sepc, t2
    li t2, 0x20
    csrs sstatus, t2
    sret

after_fault:
    j fail

after_irq:
    la t0, phase
    ld t1, 0(t0)
    li t2, 2
    bne t1, t2, fail
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail_trap:
    csrwi satp, 0
    sfence.vma
    j fail

fail:
    csrwi satp, 0
    sfence.vma
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .data
    .balign 4096
root_pt:
    .zero 4096
    .balign 4096
l1_pt:
    .zero 4096
    .balign 4096
l0_pt:
    .zero 4096
user_page:
    .dword 0x1122334455667788
phase:
    .dword 0

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_MPRV_SUM_LOAD_FAULT = r"""
    .option norvc
    .section .text.init
    .globl _start
    .equ USER_VA, 0x0000000040000000
_start:
    la t0, trap_handler
    csrw mtvec, t0

    la t0, root_pt
    srli t1, t0, 12
    li t2, 0x8000000000000000
    or t1, t1, t2
    csrw satp, t1

    la t0, l1_pt
    srli t0, t0, 12
    slli t0, t0, 10
    ori t0, t0, 1
    la t1, root_pt + 8
    sd t0, 0(t1)

    la t0, l0_pt
    srli t0, t0, 12
    slli t0, t0, 10
    ori t0, t0, 1
    la t1, l1_pt
    sd t0, 0(t1)

    la t0, user_page
    srli t0, t0, 12
    slli t0, t0, 10
    li t1, 0xd7
    or t0, t0, t1
    la t1, l0_pt
    sd t0, 0(t1)

    sfence.vma

    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    li t0, 0x40000
    csrc mstatus, t0
    li t0, 0x20000
    csrs mstatus, t0

    li t2, USER_VA
bad_load:
    ld t3, 0(t2)
    j fail

trap_handler:
    csrr t0, mcause
    li t1, 13
    bne t0, t1, fail
    csrr t0, mepc
    la t1, bad_load
    bne t0, t1, fail
    csrr t0, mtval
    li t1, USER_VA
    bne t0, t1, fail
    li t4, 0x20000
    csrc mstatus, t4
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    li t4, 0x20000
    csrc mstatus, t4
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .data
    .balign 4096
root_pt:
    .zero 4096
    .balign 4096
l1_pt:
    .zero 4096
    .balign 4096
l0_pt:
    .zero 4096
    .balign 4096
user_page:
    .dword 0x1122334455667788

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_MPRV_SUM_LOAD_OK = r"""
    .option norvc
    .section .text.init
    .globl _start
    .equ USER_VA, 0x0000000040000000
_start:
    la t0, trap_handler
    csrw mtvec, t0

    la t0, root_pt
    srli t1, t0, 12
    li t2, 0x8000000000000000
    or t1, t1, t2
    csrw satp, t1

    la t0, l1_pt
    srli t0, t0, 12
    slli t0, t0, 10
    ori t0, t0, 1
    la t1, root_pt + 8
    sd t0, 0(t1)

    la t0, l0_pt
    srli t0, t0, 12
    slli t0, t0, 10
    ori t0, t0, 1
    la t1, l1_pt
    sd t0, 0(t1)

    la t0, user_page
    srli t0, t0, 12
    slli t0, t0, 10
    li t1, 0xd7
    or t0, t0, t1
    la t1, l0_pt
    sd t0, 0(t1)

    sfence.vma

    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    li t0, 0x60000
    csrs mstatus, t0

    li t2, USER_VA
    ld t3, 0(t2)
    li t4, 0x1122334455667788
    bne t3, t4, fail

pass:
    li t4, 0x20000
    csrc mstatus, t4
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    li t4, 0x20000
    csrc mstatus, t4
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

trap_handler:
    li t4, 0x20000
    csrc mstatus, t4
    la t0, tohost
    li t1, 5
    sd t1, 0(t0)
3:
    j 3b

    .section .data
    .balign 4096
root_pt:
    .zero 4096
    .balign 4096
l1_pt:
    .zero 4096
    .balign 4096
l0_pt:
    .zero 4096
    .balign 4096
user_page:
    .dword 0x1122334455667788

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_MPRV_SUM_STORE_FAULT = r"""
    .option norvc
    .section .text.init
    .globl _start
    .equ USER_VA, 0x0000000040000000
_start:
    la t0, trap_handler
    csrw mtvec, t0

    la t0, root_pt
    srli t1, t0, 12
    li t2, 0x8000000000000000
    or t1, t1, t2
    csrw satp, t1

    la t0, l1_pt
    srli t0, t0, 12
    slli t0, t0, 10
    ori t0, t0, 1
    la t1, root_pt + 8
    sd t0, 0(t1)

    la t0, l0_pt
    srli t0, t0, 12
    slli t0, t0, 10
    ori t0, t0, 1
    la t1, l1_pt
    sd t0, 0(t1)

    la t0, user_page
    srli t0, t0, 12
    slli t0, t0, 10
    li t1, 0xd7
    or t0, t0, t1
    la t1, l0_pt
    sd t0, 0(t1)

    sfence.vma

    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    li t0, 0x40000
    csrc mstatus, t0
    li t0, 0x20000
    csrs mstatus, t0

    li t2, USER_VA
    li t3, 0x123456789abcdef0
bad_store:
    sd t3, 0(t2)
    j fail

trap_handler:
    csrr t0, mcause
    li t1, 15
    bne t0, t1, fail
    csrr t0, mepc
    la t1, bad_store
    bne t0, t1, fail
    csrr t0, mtval
    li t1, USER_VA
    bne t0, t1, fail
    li t4, 0x20000
    csrc mstatus, t4
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    li t4, 0x20000
    csrc mstatus, t4
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .data
    .balign 4096
root_pt:
    .zero 4096
    .balign 4096
l1_pt:
    .zero 4096
    .balign 4096
l0_pt:
    .zero 4096
    .balign 4096
user_page:
    .dword 0

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_MPRV_SUM_STORE_OK = r"""
    .option norvc
    .section .text.init
    .globl _start
    .equ USER_VA, 0x0000000040000000
_start:
    la t0, trap_handler
    csrw mtvec, t0

    la t0, root_pt
    srli t1, t0, 12
    li t2, 0x8000000000000000
    or t1, t1, t2
    csrw satp, t1

    la t0, l1_pt
    srli t0, t0, 12
    slli t0, t0, 10
    ori t0, t0, 1
    la t1, root_pt + 8
    sd t0, 0(t1)

    la t0, l0_pt
    srli t0, t0, 12
    slli t0, t0, 10
    ori t0, t0, 1
    la t1, l1_pt
    sd t0, 0(t1)

    la t0, user_page
    srli t0, t0, 12
    slli t0, t0, 10
    li t1, 0xd7
    or t0, t0, t1
    la t1, l0_pt
    sd t0, 0(t1)

    sfence.vma

    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    li t0, 0x60000
    csrs mstatus, t0

    li t2, USER_VA
    li t3, 0x123456789abcdef0
    sd t3, 0(t2)

    li t0, 0x20000
    csrc mstatus, t0
    la t1, user_page
    ld t4, 0(t1)
    bne t4, t3, fail

pass:
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

trap_handler:
    li t4, 0x20000
    csrc mstatus, t4
    la t0, tohost
    li t1, 5
    sd t1, 0(t0)
3:
    j 3b

    .section .data
    .balign 4096
root_pt:
    .zero 4096
    .balign 4096
l1_pt:
    .zero 4096
    .balign 4096
l0_pt:
    .zero 4096
    .balign 4096
user_page:
    .dword 0

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_MXR_EXEC_LOAD_FAULT = r"""
    .option norvc
    .section .text.init
    .globl _start
    .equ EXEC_VA, 0x0000000040000000
_start:
    la t0, trap_handler
    csrw mtvec, t0

    la t0, root_pt
    srli t1, t0, 12
    li t2, 0x8000000000000000
    or t1, t1, t2
    csrw satp, t1

    la t0, l1_pt
    srli t0, t0, 12
    slli t0, t0, 10
    ori t0, t0, 1
    la t1, root_pt + 8
    sd t0, 0(t1)

    la t0, l0_pt
    srli t0, t0, 12
    slli t0, t0, 10
    ori t0, t0, 1
    la t1, l1_pt
    sd t0, 0(t1)

    la t0, exec_page
    srli t0, t0, 12
    slli t0, t0, 10
    li t1, 0x49
    or t0, t0, t1
    la t1, l0_pt
    sd t0, 0(t1)

    sfence.vma

    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    li t0, 0x20000
    csrs mstatus, t0
    li t1, EXEC_VA
bad_load:
    ld t2, 0(t1)
    j fail

trap_handler:
    csrr t0, mcause
    li t1, 13
    bne t0, t1, fail
    csrr t0, mepc
    la t1, bad_load
    bne t0, t1, fail
    csrr t0, mtval
    li t1, EXEC_VA
    bne t0, t1, fail
    csrwi satp, 0
    sfence.vma
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    csrwi satp, 0
    sfence.vma
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .data
    .balign 4096
root_pt:
    .zero 4096
    .balign 4096
l1_pt:
    .zero 4096
    .balign 4096
l0_pt:
    .zero 4096
    .balign 4096
exec_page:
    .dword 0x8877665544332211

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_MXR_EXEC_LOAD_OK = r"""
    .option norvc
    .section .text.init
    .globl _start
    .equ EXEC_VA, 0x0000000040000000
_start:
    la t0, trap_handler
    csrw mtvec, t0

    la t0, root_pt
    srli t1, t0, 12
    li t2, 0x8000000000000000
    or t1, t1, t2
    csrw satp, t1

    la t0, l1_pt
    srli t0, t0, 12
    slli t0, t0, 10
    ori t0, t0, 1
    la t1, root_pt + 8
    sd t0, 0(t1)

    la t0, l0_pt
    srli t0, t0, 12
    slli t0, t0, 10
    ori t0, t0, 1
    la t1, l1_pt
    sd t0, 0(t1)

    la t0, exec_page
    srli t0, t0, 12
    slli t0, t0, 10
    li t1, 0x49
    or t0, t0, t1
    la t1, l0_pt
    sd t0, 0(t1)

    sfence.vma

    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    li t0, 0xa0000
    csrs mstatus, t0
    li t1, EXEC_VA
    ld t2, 0(t1)
    li t3, 0x8877665544332211
    bne t2, t3, fail
    csrwi satp, 0
    sfence.vma
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

trap_handler:
    csrwi satp, 0
    sfence.vma
    la t0, tohost
    li t1, 5
    sd t1, 0(t0)
2:
    j 2b

fail:
    csrwi satp, 0
    sfence.vma
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
3:
    j 3b

    .section .data
    .balign 4096
root_pt:
    .zero 4096
    .balign 4096
l1_pt:
    .zero 4096
    .balign 4096
l0_pt:
    .zero 4096
    .balign 4096
exec_page:
    .dword 0x8877665544332211

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_FETCH_A_FAULT = r"""
    .option norvc
    .section .text.init
    .globl _start
    .equ EXEC_VA, 0x0000000040000000
_start:
    la t0, trap_handler
    csrw mtvec, t0

    la t0, root_pt
    srli t1, t0, 12
    li t2, 0x8000000000000000
    or t1, t1, t2
    csrw satp, t1

    la t0, l1_pt
    srli t0, t0, 12
    slli t0, t0, 10
    ori t0, t0, 1
    la t1, root_pt + 8
    sd t0, 0(t1)

    la t0, l0_pt
    srli t0, t0, 12
    slli t0, t0, 10
    ori t0, t0, 1
    la t1, l1_pt
    sd t0, 0(t1)

    la t0, exec_page_code
    srli t0, t0, 12
    slli t0, t0, 10
    li t1, 0x09
    or t0, t0, t1
    la t1, l0_pt
    sd t0, 0(t1)

    sfence.vma

    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    li t0, EXEC_VA
    csrw mepc, t0
    mret

trap_handler:
    csrr t0, mcause
    li t1, 12
    bne t0, t1, fail
    csrr t0, mepc
    li t1, EXEC_VA
    bne t0, t1, fail
    csrr t0, mtval
    li t1, EXEC_VA
    bne t0, t1, fail
    csrwi satp, 0
    sfence.vma
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    csrwi satp, 0
    sfence.vma
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .text.execpage,"ax"
    .balign 4096
exec_page_code:
    la t0, tohost
    li t1, 7
    sd t1, 0(t0)
3:
    j 3b

    .section .data
    .balign 4096
root_pt:
    .zero 4096
    .balign 4096
l1_pt:
    .zero 4096
    .balign 4096
l0_pt:
    .zero 4096

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_MPRV_A_LOAD_FAULT = r"""
    .option norvc
    .section .text.init
    .globl _start
    .equ USER_VA, 0x0000000040000000
_start:
    la t0, trap_handler
    csrw mtvec, t0

    la t0, root_pt
    srli t1, t0, 12
    li t2, 0x8000000000000000
    or t1, t1, t2
    csrw satp, t1

    la t0, l1_pt
    srli t0, t0, 12
    slli t0, t0, 10
    ori t0, t0, 1
    la t1, root_pt + 8
    sd t0, 0(t1)

    la t0, l0_pt
    srli t0, t0, 12
    slli t0, t0, 10
    ori t0, t0, 1
    la t1, l1_pt
    sd t0, 0(t1)

    la t0, user_page
    srli t0, t0, 12
    slli t0, t0, 10
    li t1, 0x97
    or t0, t0, t1
    la t1, l0_pt
    sd t0, 0(t1)

    sfence.vma

    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    li t0, 0x60000
    csrs mstatus, t0

    li t2, USER_VA
bad_load:
    ld t3, 0(t2)
    j fail

trap_handler:
    csrr t0, mcause
    li t1, 13
    bne t0, t1, fail
    csrr t0, mepc
    la t1, bad_load
    bne t0, t1, fail
    csrr t0, mtval
    li t1, USER_VA
    bne t0, t1, fail
    li t4, 0x60000
    csrc mstatus, t4
    csrwi satp, 0
    sfence.vma
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    li t4, 0x60000
    csrc mstatus, t4
    csrwi satp, 0
    sfence.vma
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .data
    .balign 4096
root_pt:
    .zero 4096
    .balign 4096
l1_pt:
    .zero 4096
    .balign 4096
l0_pt:
    .zero 4096
    .balign 4096
user_page:
    .dword 0x1122334455667788

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_MPRV_D_STORE_FAULT = r"""
    .option norvc
    .section .text.init
    .globl _start
    .equ USER_VA, 0x0000000040000000
_start:
    la t0, trap_handler
    csrw mtvec, t0

    la t0, root_pt
    srli t1, t0, 12
    li t2, 0x8000000000000000
    or t1, t1, t2
    csrw satp, t1

    la t0, l1_pt
    srli t0, t0, 12
    slli t0, t0, 10
    ori t0, t0, 1
    la t1, root_pt + 8
    sd t0, 0(t1)

    la t0, l0_pt
    srli t0, t0, 12
    slli t0, t0, 10
    ori t0, t0, 1
    la t1, l1_pt
    sd t0, 0(t1)

    la t0, user_page
    srli t0, t0, 12
    slli t0, t0, 10
    li t1, 0x57
    or t0, t0, t1
    la t1, l0_pt
    sd t0, 0(t1)

    sfence.vma

    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    li t0, 0x60000
    csrs mstatus, t0

    li t2, USER_VA
    li t3, 0x123456789abcdef0
bad_store:
    sd t3, 0(t2)
    j fail

trap_handler:
    csrr t0, mcause
    li t1, 15
    bne t0, t1, fail
    csrr t0, mepc
    la t1, bad_store
    bne t0, t1, fail
    csrr t0, mtval
    li t1, USER_VA
    bne t0, t1, fail
    li t4, 0x60000
    csrc mstatus, t4
    csrwi satp, 0
    sfence.vma
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    li t4, 0x60000
    csrc mstatus, t4
    csrwi satp, 0
    sfence.vma
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .data
    .balign 4096
root_pt:
    .zero 4096
    .balign 4096
l1_pt:
    .zero 4096
    .balign 4096
l0_pt:
    .zero 4096
    .balign 4096
user_page:
    .dword 0

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_NONCANONICAL_FETCH_FAULT = r"""
    .option norvc
    .section .text.init
    .globl _start
    .equ BAD_VA, 0x0000004000000000
_start:
    la t0, trap_handler
    csrw mtvec, t0

    la t0, root_pt
    srli t1, t0, 12
    li t2, 0x8000000000000000
    or t1, t1, t2
    csrw satp, t1
    sfence.vma

    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    li t0, BAD_VA
    csrw mepc, t0
    mret

trap_handler:
    csrr t0, mcause
    li t1, 12
    bne t0, t1, fail
    csrr t0, mepc
    li t1, BAD_VA
    bne t0, t1, fail
    csrr t0, mtval
    li t1, BAD_VA
    bne t0, t1, fail
    csrwi satp, 0
    sfence.vma
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    csrwi satp, 0
    sfence.vma
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .data
    .balign 4096
root_pt:
    .zero 4096

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_NONCANONICAL_LOAD_FAULT = r"""
    .option norvc
    .section .text.init
    .globl _start
    .equ BAD_VA, 0x0000004000000000
_start:
    la t0, trap_handler
    csrw mtvec, t0

    la t0, root_pt
    srli t1, t0, 12
    li t2, 0x8000000000000000
    or t1, t1, t2
    csrw satp, t1
    sfence.vma

    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    li t0, 0x60000
    csrs mstatus, t0

    li t2, BAD_VA
bad_load:
    ld t3, 0(t2)
    j fail

trap_handler:
    csrr t0, mcause
    li t1, 13
    bne t0, t1, fail
    csrr t0, mepc
    la t1, bad_load
    bne t0, t1, fail
    csrr t0, mtval
    li t1, BAD_VA
    bne t0, t1, fail
    li t4, 0x60000
    csrc mstatus, t4
    csrwi satp, 0
    sfence.vma
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    li t4, 0x60000
    csrc mstatus, t4
    csrwi satp, 0
    sfence.vma
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .data
    .balign 4096
root_pt:
    .zero 4096

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_NONCANONICAL_STORE_FAULT = r"""
    .option norvc
    .section .text.init
    .globl _start
    .equ BAD_VA, 0x0000004000000000
_start:
    la t0, trap_handler
    csrw mtvec, t0

    la t0, root_pt
    srli t1, t0, 12
    li t2, 0x8000000000000000
    or t1, t1, t2
    csrw satp, t1
    sfence.vma

    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    li t0, 0x60000
    csrs mstatus, t0

    li t2, BAD_VA
    li t3, 0x123456789abcdef0
bad_store:
    sd t3, 0(t2)
    j fail

trap_handler:
    csrr t0, mcause
    li t1, 15
    bne t0, t1, fail
    csrr t0, mepc
    la t1, bad_store
    bne t0, t1, fail
    csrr t0, mtval
    li t1, BAD_VA
    bne t0, t1, fail
    li t4, 0x60000
    csrc mstatus, t4
    csrwi satp, 0
    sfence.vma
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    li t4, 0x60000
    csrc mstatus, t4
    csrwi satp, 0
    sfence.vma
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .data
    .balign 4096
root_pt:
    .zero 4096

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_PMP_S_FETCH_NOMATCH_FAULT = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, trap_handler
    csrw mtvec, t0
    li t0, 0x20000000
    csrw pmpaddr0, t0
    li t0, 0x0f
    csrw pmpcfg0, t0
    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    la t0, s_entry
    csrw mepc, t0
    mret

s_entry:
    addi s0, s0, 1
    j fail

trap_handler:
    csrr t0, mcause
    li t1, 1
    bne t0, t1, fail
    csrr t0, mepc
    la t1, s_entry
    bne t0, t1, fail
    csrr t0, mtval
    la t1, s_entry
    bne t0, t1, fail
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_PMP_MPRV_LOAD_FAULT = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, trap_handler
    csrw mtvec, t0
    li t0, 0x400
    csrw pmpaddr0, t0
    li t0, 0x1c
    csrw pmpcfg0, t0
    li t0, 0x00001800
    csrc mstatus, t0
    li t0, 0x00020000
    csrs mstatus, t0

bad_load:
    li t0, 0x1000
bad_load_insn:
    ld t2, 0(t0)
    j fail

trap_handler:
    csrr t0, mcause
    li t1, 5
    bne t0, t1, fail
    csrr t0, mepc
    la t1, bad_load_insn
    bne t0, t1, fail
    csrr t0, mtval
    li t1, 0x1000
    bne t0, t1, fail
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_PMP_MPRV_STORE_FAULT = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, trap_handler
    csrw mtvec, t0
    li t0, 0x400
    csrw pmpaddr0, t0
    li t0, 0x1d
    csrw pmpcfg0, t0
    li t0, 0x00001800
    csrc mstatus, t0
    li t0, 0x00020000
    csrs mstatus, t0

bad_store:
    li t0, 0x1000
    li t2, 0x55
bad_store_insn:
    sd t2, 0(t0)
    j fail

trap_handler:
    csrr t0, mcause
    li t1, 7
    bne t0, t1, fail
    csrr t0, mepc
    la t1, bad_store_insn
    bne t0, t1, fail
    csrr t0, mtval
    li t1, 0x1000
    bne t0, t1, fail
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_PMP_LOCKED_M_LOAD_FAULT = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, trap_handler
    csrw mtvec, t0
    li t0, 0x400
    csrw pmpaddr0, t0
    li t0, 0x9c
    csrw pmpcfg0, t0
    csrwi pmpaddr0, 0
    csrwi pmpcfg0, 0

bad_load:
    li t0, 0x1000
bad_load_insn:
    ld t2, 0(t0)
    j fail

trap_handler:
    csrr t0, mcause
    li t1, 5
    bne t0, t1, fail
    csrr t0, mepc
    la t1, bad_load_insn
    bne t0, t1, fail
    csrr t0, mtval
    li t1, 0x1000
    bne t0, t1, fail
    csrr t0, pmpcfg0
    li t1, 0x9c
    bne t0, t1, fail
    csrr t0, pmpaddr0
    li t1, 0x400
    bne t0, t1, fail
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_WFI_U_LEGAL = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, fail_trap
    csrw mtvec, t0
    li t0, 0x1800
    csrc mstatus, t0
    la t0, user_entry
    csrw mepc, t0
    mret

user_entry:
    wfi
    addi s0, s0, 1
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail_trap:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_WFI_S_LEGAL = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, fail_trap
    csrw mtvec, t0
    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    la t0, s_entry
    csrw mepc, t0
    mret

s_entry:
    wfi
    addi s0, s0, 1
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail_trap:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_WFI_TIMER_WAKE = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, trap_handler
    csrw mtvec, t0
    li t0, 0x80
    csrw mie, t0
    li t0, 0x8
    csrs mstatus, t0

before_wfi:
    wfi
after_wfi:
    addi s0, s0, 1
    la t0, flag
    ld t1, 0(t0)
    beqz t1, fail
    la t0, saved_cause
    ld t1, 0(t0)
    li t2, 0x8000000000000007
    bne t1, t2, fail
    la t0, saved_epc
    ld t1, 0(t0)
    la t2, after_wfi
    bne t1, t2, fail
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

trap_handler:
    csrr t0, mcause
    la t1, saved_cause
    sd t0, 0(t1)
    csrr t0, mepc
    la t1, saved_epc
    sd t0, 0(t1)
    li t0, 1
    la t1, flag
    sd t0, 0(t1)
    csrwi mie, 0
    mret

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .bss
    .align 3
flag:
    .dword 0
saved_cause:
    .dword 0
saved_epc:
    .dword 0

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_MRET_MPRV_CLEAR = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, trap_handler
    csrw mtvec, t0
    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x20080
    csrs mstatus, t0
    la t0, user_entry
    csrw mepc, t0
    mret

user_entry:
user_ecall:
    ecall
    j fail

trap_handler:
    csrr t0, mcause
    li t1, 8
    bne t0, t1, fail
    csrr t0, mepc
    la t1, user_ecall
    bne t0, t1, fail
    csrr t0, mstatus
    li t1, 0x80
    and t2, t0, t1
    beqz t2, fail
    li t1, 0x20000
    and t2, t0, t1
    bnez t2, fail
    li t1, 0x1800
    and t2, t0, t1
    bnez t2, fail
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


ASM_SRET_STATE_RESTORE = r"""
    .option norvc
    .section .text.init
    .globl _start
_start:
    la t0, m_trap
    csrw mtvec, t0
    la t0, s_trap
    csrw stvec, t0
    li t0, 0x100
    csrw medeleg, t0
    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x20800
    csrs mstatus, t0
    la t0, s_entry
    csrw mepc, t0
    mret

s_entry:
    li t0, 0x22
    csrs sstatus, t0
    la t0, user_ecall
    csrw sepc, t0
    sret

user_ecall:
    ecall
    j fail

s_trap:
    csrr t0, scause
    li t1, 8
    bne t0, t1, fail
    csrr t0, sepc
    la t1, user_ecall
    bne t0, t1, fail
    la t0, user_break
    csrw sepc, t0
    sret

user_break:
    ebreak
    j fail

m_trap:
    csrr t0, mcause
    li t1, 3
    bne t0, t1, fail
    csrr t0, mepc
    la t1, user_break
    bne t0, t1, fail
    csrr t0, mstatus
    li t1, 0x2
    and t2, t0, t1
    beqz t2, fail
    li t1, 0x20
    and t2, t0, t1
    beqz t2, fail
    li t1, 0x100
    and t2, t0, t1
    bnez t2, fail
    li t1, 0x20000
    and t2, t0, t1
    bnez t2, fail
    la t0, tohost
    li t1, 1
    sd t1, 0(t0)
1:
    j 1b

fail:
    la t0, tohost
    li t1, 3
    sd t1, 0(t0)
2:
    j 2b

    .section .tohost,"aw",@progbits
    .align 3
    .globl tohost
tohost:
    .dword 0
"""


TESTS = [
    {
        "name": "machine_timer_irq",
        "asm": ASM_INTERRUPT,
        "irq_kind": "mtip",
        "irq_symbol": "irq_resume",
        "plusargs": lambda irq_pc: ["+irq_kind=2", f"+irq_pc={irq_pc:016x}"],
        "emu_args": lambda irq_pc: ["--irq-kind", "mtip", "--irq-pc", hex(irq_pc)],
    },
    {
        "name": "machine_external_irq",
        "asm": ASM_MACHINE_EXTERNAL_IRQ,
        "irq_kind": "meip",
        "irq_symbol": "irq_resume",
        "plusargs": lambda irq_pc: ["+irq_kind=3", f"+irq_pc={irq_pc:016x}"],
        "emu_args": lambda irq_pc: ["--irq-kind", "meip", "--irq-pc", hex(irq_pc)],
    },
    {
        "name": "s_mode_machine_timer_irq",
        "asm": ASM_S_MODE_MACHINE_TIMER_IRQ,
        "irq_kind": "mtip",
        "irq_symbol": "irq_resume",
        "plusargs": lambda irq_pc: ["+irq_kind=2", f"+irq_pc={irq_pc:016x}"],
        "emu_args": lambda irq_pc: ["--irq-kind", "mtip", "--irq-pc", hex(irq_pc)],
    },
    {
        "name": "s_mode_machine_external_irq",
        "asm": ASM_S_MODE_MACHINE_EXTERNAL_IRQ,
        "irq_kind": "meip",
        "irq_symbol": "irq_resume",
        "plusargs": lambda irq_pc: ["+irq_kind=3", f"+irq_pc={irq_pc:016x}"],
        "emu_args": lambda irq_pc: ["--irq-kind", "meip", "--irq-pc", hex(irq_pc)],
    },
    {
        "name": "supervisor_ecall_to_m",
        "asm": ASM_SUPERVISOR_ECALL_TO_M,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "delegated_breakpoint",
        "asm": ASM_DELEGATED_BREAKPOINT,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "delegated_user_ecall",
        "asm": ASM_DELEGATED_USER_ECALL,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "supervisor_softirq",
        "asm": ASM_SUPERVISOR_SOFTIRQ,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "u_mode_supervisor_timer_irq",
        "asm": ASM_U_MODE_SUPERVISOR_TIMER_IRQ,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "s_mode_supervisor_timer_masked",
        "asm": ASM_S_MODE_SUPERVISOR_TIMER_MASKED,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "supervisor_breakpoint_to_m",
        "asm": ASM_SUPERVISOR_BREAKPOINT_TO_M,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "supervisor_timer_irq",
        "asm": ASM_SUPERVISOR_TIMER_IRQ,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "supervisor_external_irq",
        "asm": ASM_SUPERVISOR_EXTERNAL_IRQ,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "tvm_sfence_illegal",
        "asm": ASM_TVM_SFENCE,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "tvm_satp_illegal",
        "asm": ASM_TVM_SATP,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "tsr_sret_illegal",
        "asm": ASM_TSR_SRET,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "wfi_u_legal",
        "asm": ASM_WFI_U_LEGAL,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "wfi_s_legal",
        "asm": ASM_WFI_S_LEGAL,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "wfi_timer_wake",
        "asm": ASM_WFI_TIMER_WAKE,
        "irq_kind": "mtip",
        "irq_symbol": "after_wfi",
        "plusargs": lambda irq_pc: ["+irq_kind=2", f"+irq_pc={irq_pc:016x}"],
        "emu_args": lambda irq_pc: ["--irq-kind", "mtip", "--irq-pc", hex(irq_pc)],
    },
    {
        "name": "mret_mprv_clear",
        "asm": ASM_MRET_MPRV_CLEAR,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "sret_state_restore",
        "asm": ASM_SRET_STATE_RESTORE,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "sret_pending_supervisor_irq",
        "asm": ASM_SRET_PENDING_SUPERVISOR_IRQ,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "s_page_fault_then_pending_supervisor_irq",
        "asm": ASM_S_PAGE_FAULT_THEN_PENDING_SUPERVISOR_IRQ,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "mprv_sum_user_load_fault",
        "asm": ASM_MPRV_SUM_LOAD_FAULT,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "mprv_sum_user_load_ok",
        "asm": ASM_MPRV_SUM_LOAD_OK,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "mprv_sum_user_store_fault",
        "asm": ASM_MPRV_SUM_STORE_FAULT,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "mprv_sum_user_store_ok",
        "asm": ASM_MPRV_SUM_STORE_OK,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "mxr_exec_load_fault",
        "asm": ASM_MXR_EXEC_LOAD_FAULT,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "mxr_exec_load_ok",
        "asm": ASM_MXR_EXEC_LOAD_OK,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "fetch_a_fault",
        "asm": ASM_FETCH_A_FAULT,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "mprv_a_load_fault",
        "asm": ASM_MPRV_A_LOAD_FAULT,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "mprv_d_store_fault",
        "asm": ASM_MPRV_D_STORE_FAULT,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "noncanonical_fetch_fault",
        "asm": ASM_NONCANONICAL_FETCH_FAULT,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "noncanonical_load_fault",
        "asm": ASM_NONCANONICAL_LOAD_FAULT,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "noncanonical_store_fault",
        "asm": ASM_NONCANONICAL_STORE_FAULT,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "pmp_s_fetch_nomatch_fault",
        "asm": ASM_PMP_S_FETCH_NOMATCH_FAULT,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "pmp_mprv_load_fault",
        "asm": ASM_PMP_MPRV_LOAD_FAULT,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "pmp_mprv_store_fault",
        "asm": ASM_PMP_MPRV_STORE_FAULT,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
    {
        "name": "pmp_locked_m_load_fault",
        "asm": ASM_PMP_LOCKED_M_LOAD_FAULT,
        "irq_kind": None,
        "irq_symbol": None,
        "plusargs": lambda irq_pc: [],
        "emu_args": lambda irq_pc: [],
    },
]


def filtered_mismatches(rtl_state: dict, emu_state: dict) -> list[str]:
    return [
        mismatch
        for mismatch in compare_states(rtl_state, emu_state)
        if not mismatch.startswith("csr ares_")
    ]


def build_elf(build_dir: Path, name: str, asm_text: str) -> Path:
    asm_path = build_dir / f"{name}.S"
    ld_path = build_dir / f"{name}.ld"
    elf_path = build_dir / f"{name}.elf"
    asm_path.write_text(textwrap.dedent(asm_text).strip() + "\n")
    ld_path.write_text(textwrap.dedent(LD).strip() + "\n")
    subprocess.run(
        [
            "riscv64-unknown-elf-gcc",
            "-nostdlib",
            "-nostartfiles",
            "-march=rv64imazicsr",
            "-mabi=lp64",
            "-Wl,-T",
            str(ld_path),
            "-Wl,--no-relax",
            "-Wl,--build-id=none",
            "-o",
            str(elf_path),
            str(asm_path),
        ],
        cwd=ROOT,
        check=True,
    )
    return elf_path


def read_symbol_addr(elf_path: Path, symbol: str) -> int:
    proc = subprocess.run(
        ["riscv64-unknown-elf-nm", "-n", str(elf_path)],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    for line in proc.stdout.splitlines():
        fields = line.strip().split()
        if len(fields) == 3 and fields[2] == symbol:
            return int(fields[0], 16)
    raise RuntimeError(f"symbol {symbol} not found in {elf_path}")


def run_rtl_state(elf_path: Path, sim_path: Path, plusargs: list[str]) -> dict:
    words, tohost_idx = elf_to_words(elf_path)
    run_args = ["+state_dump", *(plusargs or [])]
    if tohost_idx is not None:
        run_args.append(f"+tohost_idx={tohost_idx}")
    proc = run_vvp(sim_path, words, run_args)
    if proc.returncode != 0:
        raise RuntimeError(f"rtl failed for {elf_path.name}: {proc.stderr.strip()}")
    state = parse_state(proc.stdout)
    if state["meta"].get("tohost") != 1:
        raise RuntimeError(f"rtl tohost={state['meta'].get('tohost')} for {elf_path.name}")
    return state


def run_emu_state(elf_path: Path, extra_args: list[str]) -> dict:
    proc = subprocess.run(
        [str(EMU_DIR / "ares"), "--state-dump", *extra_args, str(elf_path)],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"emulator failed for {elf_path.name}: {proc.stderr.strip()}")
    state = parse_state(proc.stdout)
    if state["meta"].get("tohost") != 1:
        raise RuntimeError(f"emulator tohost={state['meta'].get('tohost')} for {elf_path.name}")
    return state


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="ares-priv-smoke-") as tmpdir:
        build_dir = Path(tmpdir)
        sim_path = build_sim()
        build_emulator()

        passed = 0
        failed = 0
        for spec in TESTS:
            elf_path = build_elf(build_dir, spec["name"], spec["asm"])
            irq_pc = read_symbol_addr(elf_path, spec["irq_symbol"]) if spec["irq_symbol"] else 0
            try:
                rtl_state = run_rtl_state(elf_path, sim_path, spec["plusargs"](irq_pc))
                emu_state = run_emu_state(elf_path, spec["emu_args"](irq_pc))
                mismatches = filtered_mismatches(rtl_state, emu_state)
                if mismatches:
                    failed += 1
                    print(f"FAIL {spec['name']}")
                    for mismatch in mismatches[:10]:
                        print(f"  {mismatch}")
                else:
                    passed += 1
                    print(f"PASS {spec['name']}")
            except Exception as exc:
                failed += 1
                print(f"ERROR {spec['name']} {exc}")

        print(f"SUMMARY pass={passed} fail={failed} total={len(TESTS)}")
        if failed:
            raise SystemExit(1)


if __name__ == "__main__":
    main()
