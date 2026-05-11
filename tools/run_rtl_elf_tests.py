#!/usr/bin/env python3

import argparse
import os
import struct
import subprocess
import tempfile
from pathlib import Path
from typing import List, Optional


ROOT = Path(__file__).resolve().parents[1]
RTL_DIR = ROOT / "rtl"
MEM_BASE = 0x80000000
MEM_WORDS = 65536
VERILATOR_TOP = "tb_ares"
SIM_SOURCES = [
    "tb_ares.v",
    "ares_core.v",
    "csr_unit.v",
    "ex_stage.v",
    "id_stage.v",
    "if_stage.v",
    "mem_stage.v",
    "wb_stage.v",
]


def default_sim_path() -> Path:
    return RTL_DIR / f"obj_dir_{os.getpid()}" / "ares_sim"


def read_elf(path: Path):
    data = path.read_bytes()
    if data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1:
        raise ValueError(f"{path} is not a supported ELF64 little-endian file")

    e_phoff = struct.unpack_from("<Q", data, 32)[0]
    e_phentsize = struct.unpack_from("<H", data, 54)[0]
    e_phnum = struct.unpack_from("<H", data, 56)[0]
    e_shoff = struct.unpack_from("<Q", data, 40)[0]
    e_shentsize = struct.unpack_from("<H", data, 58)[0]
    e_shnum = struct.unpack_from("<H", data, 60)[0]
    e_shstrndx = struct.unpack_from("<H", data, 62)[0]

    segments = []
    for index in range(e_phnum):
        off = e_phoff + index * e_phentsize
        p_type = struct.unpack_from("<I", data, off)[0]
        if p_type != 1:
            continue
        p_offset, p_vaddr, _, p_filesz, p_memsz, _ = struct.unpack_from("<QQQQQQ", data, off + 8)
        segments.append(
            {
                "index": index,
                "vaddr": p_vaddr,
                "filesz": p_filesz,
                "memsz": p_memsz,
                "data": data[p_offset : p_offset + p_filesz],
            }
        )

    shstr_off = e_shoff + e_shstrndx * e_shentsize
    shstr_offset = struct.unpack_from("<Q", data, shstr_off + 24)[0]
    shstr_size = struct.unpack_from("<Q", data, shstr_off + 32)[0]
    shstr = data[shstr_offset : shstr_offset + shstr_size]

    sections = []
    for index in range(e_shnum):
        off = e_shoff + index * e_shentsize
        name_off = struct.unpack_from("<I", data, off)[0]
        sh_addr = struct.unpack_from("<Q", data, off + 16)[0]
        sh_size = struct.unpack_from("<Q", data, off + 32)[0]
        end = shstr.find(b"\x00", name_off)
        name = shstr[name_off:end].decode() if name_off < len(shstr) else ""
        sections.append({"name": name, "addr": sh_addr, "size": sh_size})
    return segments, sections


def elf_to_words(path: Path):
    segments, sections = read_elf(path)
    image = bytearray(MEM_WORDS * 4)
    for segment in segments:
        start = segment["vaddr"] - MEM_BASE
        if start < 0:
            raise ValueError(f"segment below MEM_BASE in {path}")
        end = start + segment["memsz"]
        if end > len(image):
            raise ValueError(f"segment exceeds testbench memory in {path}")
        image[start : start + segment["filesz"]] = segment["data"]
    words = []
    for i in range(0, len(image), 4):
        words.append(image[i : i + 4][::-1].hex())
    tohost_idx = None
    for section in sections:
        if section["name"] == ".tohost":
            tohost_idx = (section["addr"] - MEM_BASE) >> 2
            break
    return words, tohost_idx


def build_sim(sim_path: Optional[Path] = None) -> Path:
    sim_path = sim_path or default_sim_path()
    sim_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "verilator",
            "-Wno-fatal",
            "--binary",
            "--top-module",
            VERILATOR_TOP,
            "--Mdir",
            str(sim_path.parent),
            "-o",
            sim_path.name,
            *[str(RTL_DIR / source) for source in SIM_SOURCES],
        ],
        cwd=ROOT,
        check=True,
    )
    return sim_path


def run_vvp(sim_path: Path, words: List[str], plusargs: Optional[List[str]] = None) -> subprocess.CompletedProcess:
    with tempfile.TemporaryDirectory(prefix="ares_sim_", dir=RTL_DIR) as temp_dir:
        temp_path = Path(temp_dir)
        (temp_path / "program.hex").write_text("\n".join(words) + "\n")
        cmd = [str(sim_path), *(plusargs or [])]
        proc = subprocess.run(cmd, cwd=temp_path, capture_output=True, text=True, check=False)
    return proc


def run_one(elf_path: Path, sim_path: Path):
    words, tohost_idx = elf_to_words(elf_path)
    plusargs = [f"+tohost_idx={tohost_idx}"] if tohost_idx is not None else []
    proc = run_vvp(sim_path, words, plusargs)
    summary = "ERROR no-summary"
    for line in proc.stdout.splitlines():
        if line.startswith("PASS after") or line.startswith("FAIL ") or line.startswith("TIMEOUT"):
            summary = line
            if not line.startswith("TIMEOUT"):
                break
    return summary


def main():
    parser = argparse.ArgumentParser(description="Run RTL simulation on ELF tests with real section layout.")
    parser.add_argument(
        "--pattern",
        default="riscv-tests/isa/rv64ui-p-*",
        help="Glob under repo root (default: riscv-tests/isa/rv64ui-p-*)",
    )
    args = parser.parse_args()

    tests = sorted(path for path in ROOT.glob(args.pattern) if path.is_file())
    if not tests:
        raise SystemExit(f"no ELF tests matched {args.pattern}")

    sim_path = build_sim()
    passed = 0
    failed = 0
    total = 0
    for elf_path in tests:
        try:
            summary = run_one(elf_path, sim_path)
        except ValueError:
            continue
        total += 1
        if summary.startswith("PASS"):
            passed += 1
        else:
            failed += 1
        print(f"{summary} {elf_path.relative_to(ROOT)}")
    if total == 0:
        raise SystemExit(f"no ELF tests matched {args.pattern}")
    print(f"SUMMARY pass={passed} fail={failed} total={total}")


if __name__ == "__main__":
    main()
