#pragma once
#include <cstdint>
#include <fstream>
#include <string>
#include <vector>
#include <stdexcept>
#include "memory.hpp"

// Minimal ELF64 loader — loads PT_LOAD segments into memory
#pragma pack(push, 1)
struct ELF64Header {
    uint8_t  ident[16];
    uint16_t type, machine;
    uint32_t version;
    uint64_t entry, phoff, shoff;
    uint32_t flags, ehsize;
    uint16_t phentsize, phnum;
    uint16_t shentsize, shnum, shstrndx;
};

struct ELF64ProgramHeader {
    uint32_t type, flags;
    uint64_t offset, vaddr, paddr, filesz, memsz, align;
};
#pragma pack(pop)

static constexpr uint32_t PT_LOAD = 1;

inline uint64_t load_elf(const std::string& path, Memory& mem) {
    std::ifstream f(path, std::ios::binary);
    if (!f) throw std::runtime_error("Cannot open: " + path);

    // Read ELF header byte by byte to avoid struct padding issues
    uint8_t hdr_buf[64];
    f.read(reinterpret_cast<char*>(hdr_buf), 64);

    if (hdr_buf[0] != 0x7f || hdr_buf[1] != 'E' ||
        hdr_buf[2] != 'L'  || hdr_buf[3] != 'F')
        throw std::runtime_error("Not an ELF file");

    auto read16 = [](const uint8_t* p) -> uint16_t {
        return (uint16_t)(p[0] | (p[1] << 8));
    };
    auto read32 = [](const uint8_t* p) -> uint32_t {
        return (uint32_t)(p[0] | (p[1]<<8) | (p[2]<<16) | (p[3]<<24));
    };
    auto read64 = [](const uint8_t* p) -> uint64_t {
        uint64_t v = 0;
        for (int i = 0; i < 8; i++) v |= (uint64_t)p[i] << (i*8);
        return v;
    };

    uint64_t entry   = read64(hdr_buf + 24);
    uint64_t phoff   = read64(hdr_buf + 32);
    uint64_t shoff   = read64(hdr_buf + 40);
    uint16_t phentsize = read16(hdr_buf + 54);
    uint16_t phnum     = read16(hdr_buf + 56);
    uint16_t shentsize = read16(hdr_buf + 58);
    uint16_t shnum     = read16(hdr_buf + 60);
    uint16_t shstrndx  = read16(hdr_buf + 62);

    for (int i = 0; i < phnum; i++) {
        uint8_t ph_buf[56];
        f.seekg(phoff + i * phentsize);
        f.read(reinterpret_cast<char*>(ph_buf), 56);

        uint32_t type   = read32(ph_buf + 0);
        uint64_t offset = read64(ph_buf + 8);
        uint64_t vaddr  = read64(ph_buf + 16);
        uint64_t filesz = read64(ph_buf + 32);

        if (type != PT_LOAD || filesz == 0) continue;

        std::vector<uint8_t> seg(filesz);
        f.seekg(offset);
        f.read(reinterpret_cast<char*>(seg.data()), filesz);
        mem.load(seg.data(), seg.size(), vaddr);
        if (read64(ph_buf + 40) > filesz) {
            std::vector<uint8_t> zeros(read64(ph_buf + 40) - filesz, 0);
            mem.load(zeros.data(), zeros.size(), vaddr + filesz);
        }
    }

    if (shnum != 0 && shstrndx < shnum) {
        const uint64_t shstr_off = shoff + static_cast<uint64_t>(shstrndx) * shentsize;
        uint8_t sh_buf[64];
        f.seekg(shstr_off);
        f.read(reinterpret_cast<char*>(sh_buf), shentsize);
        const uint64_t strtab_offset = read64(sh_buf + 24);
        const uint64_t strtab_size = read64(sh_buf + 32);
        std::vector<char> strtab(strtab_size, 0);
        f.seekg(strtab_offset);
        f.read(strtab.data(), strtab_size);

        for (int i = 0; i < shnum; i++) {
            const uint64_t sec_off = shoff + static_cast<uint64_t>(i) * shentsize;
            f.seekg(sec_off);
            f.read(reinterpret_cast<char*>(sh_buf), shentsize);
            const uint32_t name_off = read32(sh_buf + 0);
            const uint64_t sec_addr = read64(sh_buf + 16);
            if (name_off >= strtab.size()) continue;
            const std::string name(&strtab[name_off]);
            if (name == ".tohost") {
                mem.set_tohost_addr(sec_addr);
                break;
            }
        }
    }

    return entry;
}
