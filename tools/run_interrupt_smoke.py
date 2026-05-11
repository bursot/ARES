#!/usr/bin/env python3

import re
import subprocess
import tempfile
import textwrap
from pathlib import Path

from run_emulator_tests import EMU_DIR, build_emulator
from run_rtl_elf_tests import ROOT, build_sim, elf_to_words, run_vvp
from run_state_diff import compare_states, parse_state


ASM = r"""
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


PASS_RE = re.compile(r"^PASS after ")


def filtered_mismatches(rtl_state: dict, emu_state: dict) -> list[str]:
    return [
        mismatch
        for mismatch in compare_states(rtl_state, emu_state)
        if not mismatch.startswith("csr ares_")
    ]


def build_interrupt_elf(build_dir: Path) -> Path:
    asm_path = build_dir / "interrupt_smoke.S"
    ld_path = build_dir / "interrupt_smoke.ld"
    elf_path = build_dir / "interrupt_smoke.elf"
    asm_path.write_text(textwrap.dedent(ASM).strip() + "\n")
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


def run_rtl(elf_path: Path, irq_pc: int) -> tuple[str, dict]:
    words, tohost_idx = elf_to_words(elf_path)
    cmd = [
        "+state_dump",
        "+irq_kind=2",
        f"+irq_pc={irq_pc:016x}",
    ]
    if tohost_idx is not None:
        cmd.append(f"+tohost_idx={tohost_idx}")
    proc = run_vvp(build_sim(), words, cmd)
    if proc.returncode != 0:
        raise RuntimeError(f"rtl interrupt smoke failed: {proc.stderr.strip()}")
    summary = next((line.strip() for line in proc.stdout.splitlines() if PASS_RE.match(line.strip())), "")
    if not summary:
        raise RuntimeError(f"rtl interrupt smoke did not pass\n{proc.stdout}")
    return summary, parse_state(proc.stdout)


def run_emu(elf_path: Path, irq_pc: int) -> dict:
    proc = subprocess.run(
        [
            str(EMU_DIR / "ares"),
            "--state-dump",
            "--irq-kind",
            "mtip",
            "--irq-pc",
            hex(irq_pc),
            str(elf_path),
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"emulator interrupt smoke failed: {proc.stderr.strip()}")
    state = parse_state(proc.stdout)
    if state["meta"].get("tohost") != 1:
        raise RuntimeError(f"emulator interrupt smoke tohost={state['meta'].get('tohost')}")
    return state


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="ares-interrupt-smoke-") as tmpdir:
        build_dir = Path(tmpdir)
        elf_path = build_interrupt_elf(build_dir)
        irq_pc = read_symbol_addr(elf_path, "irq_resume")
        build_sim()
        build_emulator()
        rtl_summary, rtl_state = run_rtl(elf_path, irq_pc=irq_pc)
        emu_state = run_emu(elf_path, irq_pc=irq_pc)
        mismatches = filtered_mismatches(rtl_state, emu_state)
        if mismatches:
            print("FAIL interrupt_smoke")
            for mismatch in mismatches:
                print(f"  {mismatch}")
            raise SystemExit(1)
        print(rtl_summary)
        print("PASS interrupt_smoke")


if __name__ == "__main__":
    main()
