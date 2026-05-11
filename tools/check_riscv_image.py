#!/usr/bin/env python3

import argparse
import struct
from pathlib import Path


TOHOST_ADDR = 0x80001000


def parse_u64(text: str) -> int:
    return int(text, 0)


def read_elf_load_segments(path: Path):
    data = path.read_bytes()
    if data[:4] != b"\x7fELF":
        raise ValueError(f"{path} is not an ELF file")
    if data[4] != 2:
        raise ValueError("Only ELF64 is supported")
    if data[5] != 1:
        raise ValueError("Only little-endian ELF is supported")

    e_phoff = struct.unpack_from("<Q", data, 32)[0]
    e_phentsize = struct.unpack_from("<H", data, 54)[0]
    e_phnum = struct.unpack_from("<H", data, 56)[0]
    entry = struct.unpack_from("<Q", data, 24)[0]

    segments = []
    for index in range(e_phnum):
        off = e_phoff + index * e_phentsize
        p_type, p_flags = struct.unpack_from("<II", data, off)
        if p_type != 1:
            continue
        p_offset, p_vaddr, _, p_filesz, p_memsz, p_align = struct.unpack_from(
            "<QQQQQQ", data, off + 8
        )
        segment = {
            "index": index,
            "offset": p_offset,
            "vaddr": p_vaddr,
            "filesz": p_filesz,
            "memsz": p_memsz,
            "align": p_align,
            "flags": p_flags,
            "data": data[p_offset : p_offset + p_filesz],
        }
        segments.append(segment)
    e_shoff = struct.unpack_from("<Q", data, 40)[0]
    e_shentsize = struct.unpack_from("<H", data, 58)[0]
    e_shnum = struct.unpack_from("<H", data, 60)[0]
    e_shstrndx = struct.unpack_from("<H", data, 62)[0]

    shstr_off = e_shoff + e_shstrndx * e_shentsize
    shstr_offset = struct.unpack_from("<Q", data, shstr_off + 24)[0]
    shstr_size = struct.unpack_from("<Q", data, shstr_off + 32)[0]
    shstr = data[shstr_offset : shstr_offset + shstr_size]

    sections = []
    for index in range(e_shnum):
        off = e_shoff + index * e_shentsize
        name_off = struct.unpack_from("<I", data, off)[0]
        sh_addr = struct.unpack_from("<Q", data, off + 16)[0]
        sh_offset = struct.unpack_from("<Q", data, off + 24)[0]
        sh_size = struct.unpack_from("<Q", data, off + 32)[0]
        name_end = shstr.find(b"\x00", name_off)
        name = shstr[name_off:name_end].decode() if name_off < len(shstr) else ""
        sections.append(
            {
                "index": index,
                "name": name,
                "addr": sh_addr,
                "offset": sh_offset,
                "size": sh_size,
            }
        )
    return entry, segments, sections


def read_flat_binary(path: Path, base: int):
    return path.read_bytes(), base


def bytes_at(image: bytes, base: int, addr: int, size: int) -> bytes:
    start = addr - base
    if start < 0:
        return b""
    end = start + size
    if end > len(image):
        return image[start:]
    return image[start:end]


def main():
    parser = argparse.ArgumentParser(
        description="Inspect ARES test images and verify tohost/data layout."
    )
    parser.add_argument("image", help="Path to ELF or flat binary image")
    parser.add_argument(
        "--base",
        default="0x80000000",
        help="Base address for flat binaries (default: 0x80000000)",
    )
    args = parser.parse_args()

    path = Path(args.image)
    if not path.exists():
        raise SystemExit(f"missing file: {path}")

    data = path.read_bytes()
    if data[:4] == b"\x7fELF":
        entry, segments, sections = read_elf_load_segments(path)
        print(f"type=elf64 entry=0x{entry:016x}")
        for seg in segments:
            segment_tohost = bytes_at(seg["data"], seg["vaddr"], TOHOST_ADDR, 8)
            print(
                "segment"
                f" index={seg['index']}"
                f" vaddr=0x{seg['vaddr']:016x}"
                f" filesz=0x{seg['filesz']:x}"
                f" memsz=0x{seg['memsz']:x}"
                f" tohost_bytes={segment_tohost.hex() or 'n/a'}"
            )
        for section in sections:
            if section["name"] in {".text.init", ".tohost", ".data"}:
                print(
                    "section"
                    f" name={section['name']}"
                    f" addr=0x{section['addr']:016x}"
                    f" size=0x{section['size']:x}"
                )
    else:
        base = parse_u64(args.base)
        image, base = read_flat_binary(path, base)
        print(f"type=flat base=0x{base:016x} size=0x{len(image):x}")
        for addr in (base, TOHOST_ADDR, 0x80002000, 0x80003000):
            chunk = bytes_at(image, base, addr, 16)
            print(
                f"addr=0x{addr:016x}"
                f" offset=0x{addr - base:x}"
                f" bytes={chunk.hex() or 'n/a'}"
            )


if __name__ == "__main__":
    main()
