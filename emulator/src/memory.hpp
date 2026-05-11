#pragma once
#include <cstdint>
#include <cstring>
#include <stdexcept>
#include <string>
#include <vector>

struct Memory {
    // Single flat region covering both low (0x0) and main (0x80000000) areas
    // riscv-tests uses 0x1000 for data segment and 0x80000000 for code
    static constexpr uint64_t MAIN_BASE = 0x80000000ULL;
    static constexpr uint64_t MAIN_SIZE = 1024ULL * 1024 * 64; // 64MB
    static constexpr uint64_t LOW_BASE  = 0x0ULL;
    static constexpr uint64_t LOW_SIZE  = 1024ULL * 64;        // 64KB

    std::vector<uint8_t> main_mem;
    std::vector<uint8_t> low_mem;
    uint64_t tohost_addr = 0x80001000ULL;
    uint64_t tohost = 0;

    Memory() : main_mem(MAIN_SIZE, 0), low_mem(LOW_SIZE, 0) {}

    uint8_t* ptr(uint64_t addr) const {
        if (addr >= MAIN_BASE && addr < MAIN_BASE + MAIN_SIZE)
            return const_cast<uint8_t*>(&main_mem[addr - MAIN_BASE]);
        if (addr < LOW_SIZE)
            return const_cast<uint8_t*>(&low_mem[addr]);
        throw std::runtime_error("Address out of bounds: 0x" + to_hex(addr));
    }

    void load(const uint8_t* program, size_t len, uint64_t addr = MAIN_BASE) {
        ptr(addr);
        if (len != 0) {
            ptr(addr + len - 1);
        }
        memcpy(ptr(addr), program, len);
    }

    uint8_t  read8 (uint64_t addr) const { return *ptr(addr); }
    uint16_t read16(uint64_t addr) const { uint16_t v; memcpy(&v, ptr(addr), 2); return v; }
    uint32_t read32(uint64_t addr) const { uint32_t v; memcpy(&v, ptr(addr), 4); return v; }
    uint64_t read64(uint64_t addr) const { uint64_t v; memcpy(&v, ptr(addr), 8); return v; }

    void set_tohost_addr(uint64_t addr) { tohost_addr = addr; }

    void write8 (uint64_t addr, uint8_t  v) { memcpy(ptr(addr), &v, 1); }
    void write16(uint64_t addr, uint16_t v) { memcpy(ptr(addr), &v, 2); }
    void write32(uint64_t addr, uint32_t v) {
        if (addr == tohost_addr) { tohost = v; return; }
        memcpy(ptr(addr), &v, 4);
    }
    void write64(uint64_t addr, uint64_t v) {
        if (addr == tohost_addr) { tohost = v; return; }
        memcpy(ptr(addr), &v, 8);
    }

private:
    static std::string to_hex(uint64_t v) {
        char buf[20];
        snprintf(buf, sizeof(buf), "%016llx", (unsigned long long)v);
        return buf;
    }
};
