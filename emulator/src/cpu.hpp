#pragma once

#include <cstdint>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include "memory.hpp"

// ARES — Adaptive Radiation-hardened Execution System
// Functional RV64IMA reference model aligned with the current RTL scope.

struct CPU {
    uint64_t regs[32] = {};
    uint64_t pc = 0x80000000ULL;
    Memory mem;
    bool running = true;
    uint8_t current_priv = 3;
    bool mstatus_tsr = false;

    uint64_t csr[4096] = {};
    bool reservation_valid = false;
    uint64_t reservation_addr = 0;
    uint64_t cycle = 0;
    uint64_t instret = 0;
    bool suppress_instret_increment = false;
    uint64_t scheduled_irq_cycle = ~0ULL;
    uint64_t scheduled_irq_mask = 0;
    bool scheduled_irq_armed = false;
    bool scheduled_irq_use_pc = false;
    uint64_t scheduled_irq_pc = 0;

    static constexpr uint32_t CSR_MSTATUS = 0x300;
    static constexpr uint32_t CSR_MISA = 0x301;
    static constexpr uint32_t CSR_MEDELEG = 0x302;
    static constexpr uint32_t CSR_MIDELEG = 0x303;
    static constexpr uint32_t CSR_MIE = 0x304;
    static constexpr uint32_t CSR_MTVEC = 0x305;
    static constexpr uint32_t CSR_MCOUNTEREN = 0x306;
    static constexpr uint32_t CSR_SSTATUS = 0x100;
    static constexpr uint32_t CSR_SIE = 0x104;
    static constexpr uint32_t CSR_MSCRATCH = 0x340;
    static constexpr uint32_t CSR_MEPC = 0x341;
    static constexpr uint32_t CSR_MCAUSE = 0x342;
    static constexpr uint32_t CSR_MTVAL = 0x343;
    static constexpr uint32_t CSR_MIP = 0x344;
    static constexpr uint32_t CSR_SCOUNTEREN = 0x106;
    static constexpr uint32_t CSR_SSCRATCH = 0x140;
    static constexpr uint32_t CSR_SEPC = 0x141;
    static constexpr uint32_t CSR_SCAUSE = 0x142;
    static constexpr uint32_t CSR_STVAL = 0x143;
    static constexpr uint32_t CSR_SIP = 0x144;
    static constexpr uint32_t CSR_SATP = 0x180;
    static constexpr uint32_t CSR_PMPCFG0 = 0x3A0;
    static constexpr uint32_t CSR_PMPADDR0 = 0x3B0;
    static constexpr uint32_t CSR_MCYCLE = 0xB00;
    static constexpr uint32_t CSR_MINSTRET = 0xB02;
    static constexpr uint32_t CSR_STVEC = 0x105;
    static constexpr uint32_t CSR_MVENDORID = 0xF11;
    static constexpr uint32_t CSR_MARCHID = 0xF12;
    static constexpr uint32_t CSR_MIMPID = 0xF13;
    static constexpr uint32_t CSR_MHARTID = 0xF14;
    static constexpr uint64_t PRV_U = 0;
    static constexpr uint64_t PRV_S = 1;
    static constexpr uint64_t PRV_M = 3;
    static constexpr uint64_t MSTATUS_SIE = 1ULL << 1;
    static constexpr uint64_t MSTATUS_MIE = 1ULL << 3;
    static constexpr uint64_t MSTATUS_SPIE = 1ULL << 5;
    static constexpr uint64_t MSTATUS_MPIE = 1ULL << 7;
    static constexpr uint64_t MSTATUS_SPP = 1ULL << 8;
    static constexpr uint64_t MSTATUS_MPP_MASK = 3ULL << 11;
    static constexpr uint64_t MSTATUS_MPRV = 1ULL << 17;
    static constexpr uint64_t MSTATUS_SUM = 1ULL << 18;
    static constexpr uint64_t MSTATUS_MXR = 1ULL << 19;
    static constexpr uint64_t MSTATUS_TVM = 1ULL << 20;
    static constexpr uint64_t MSTATUS_TSR = 1ULL << 22;
    static constexpr uint64_t MSTATUS_MPP_M = 3ULL << 11;
    static constexpr uint64_t MSTATUS_UXL = 2ULL << 32;
    static constexpr uint64_t SSTATUS_MASK = MSTATUS_UXL | MSTATUS_SUM | MSTATUS_MXR |
                                             MSTATUS_SPP | MSTATUS_SPIE | MSTATUS_SIE;
    static constexpr uint64_t MIP_SSIP = 1ULL << 1;
    static constexpr uint64_t MIP_MSIP = 1ULL << 3;
    static constexpr uint64_t MIP_STIP = 1ULL << 5;
    static constexpr uint64_t MIP_MTIP = 1ULL << 7;
    static constexpr uint64_t MIP_SEIP = 1ULL << 9;
    static constexpr uint64_t MIP_MEIP = 1ULL << 11;
    static constexpr uint64_t MIP_S_MASK = MIP_SSIP | MIP_STIP | MIP_SEIP;

    static constexpr uint64_t MISA_VALUE = (2ULL << 62) | 0x141101ULL;
    static constexpr uint64_t MVENDORID_VALUE = 0;
    static constexpr uint64_t MARCHID_VALUE = 0x0000000041524553ULL;
    static constexpr uint64_t MIMPID_VALUE = 1;
    static constexpr uint64_t MHARTID_VALUE = 0;
    static constexpr uint64_t CAUSE_FETCH_MISALIGNED = 0;
    static constexpr uint64_t CAUSE_FETCH_ACCESS_FAULT = 1;
    static constexpr uint64_t CAUSE_ILLEGAL_INSTR = 2;
    static constexpr uint64_t CAUSE_BREAKPOINT = 3;
    static constexpr uint64_t CAUSE_LOAD_MISALIGNED = 4;
    static constexpr uint64_t CAUSE_LOAD_ACCESS_FAULT = 5;
    static constexpr uint64_t CAUSE_STORE_MISALIGNED = 6;
    static constexpr uint64_t CAUSE_STORE_ACCESS_FAULT = 7;
    static constexpr uint64_t CAUSE_ECALL_UMODE = 8;
    static constexpr uint64_t CAUSE_ECALL_SMODE = 9;
    static constexpr uint64_t CAUSE_ECALL_MMODE = 11;
    static constexpr uint64_t CAUSE_FETCH_PAGE_FAULT = 12;
    static constexpr uint64_t CAUSE_LOAD_PAGE_FAULT = 13;
    static constexpr uint64_t CAUSE_STORE_PAGE_FAULT = 15;
    static constexpr uint64_t INTERRUPT_FLAG = 1ULL << 63;
    static constexpr uint64_t CAUSE_SSIP = INTERRUPT_FLAG | 1ULL;
    static constexpr uint64_t CAUSE_MSIP = INTERRUPT_FLAG | 3ULL;
    static constexpr uint64_t CAUSE_STIP = INTERRUPT_FLAG | 5ULL;
    static constexpr uint64_t CAUSE_MTIP = INTERRUPT_FLAG | 7ULL;
    static constexpr uint64_t CAUSE_SEIP = INTERRUPT_FLAG | 9ULL;
    static constexpr uint64_t CAUSE_MEIP = INTERRUPT_FLAG | 11ULL;
    static constexpr uint8_t ACCESS_FETCH = 0;
    static constexpr uint8_t ACCESS_LOAD = 1;
    static constexpr uint8_t ACCESS_STORE = 2;
    static constexpr uint64_t PMP_R = 1ULL << 0;
    static constexpr uint64_t PMP_W = 1ULL << 1;
    static constexpr uint64_t PMP_X = 1ULL << 2;
    static constexpr uint64_t PMP_A_MASK = 3ULL << 3;
    static constexpr uint64_t PMP_L = 1ULL << 7;

    CPU() {
        csr[CSR_MSTATUS] = MSTATUS_UXL | MSTATUS_MPP_M | MSTATUS_MPIE;
    }

    static uint64_t sign_extend(uint64_t value, unsigned bits) {
        const uint64_t mask = (bits == 64) ? ~0ULL : ((1ULL << bits) - 1);
        value &= mask;
        const uint64_t sign_bit = 1ULL << (bits - 1);
        return (value ^ sign_bit) - sign_bit;
    }

    static std::string hex64(uint64_t value) {
        std::ostringstream oss;
        oss << std::hex << value;
        return oss.str();
    }

    void set_reg(uint32_t rd, uint64_t value) {
        if (rd != 0) regs[rd] = value;
    }

    static uint64_t access_fault_cause(uint8_t access_type) {
        switch (access_type) {
        case ACCESS_FETCH: return CAUSE_FETCH_ACCESS_FAULT;
        case ACCESS_LOAD:  return CAUSE_LOAD_ACCESS_FAULT;
        default:           return CAUSE_STORE_ACCESS_FAULT;
        }
    }

    static uint64_t canonical_mstatus(uint64_t value) {
        return (value & (MSTATUS_SIE | MSTATUS_MIE |
                         MSTATUS_SPIE | MSTATUS_MPIE |
                         MSTATUS_SPP | MSTATUS_MPP_MASK |
                         MSTATUS_MPRV | MSTATUS_SUM | MSTATUS_MXR |
                         MSTATUS_TVM)) |
               MSTATUS_UXL;
    }

    static uint64_t canonical_pmpcfg0(uint64_t value) {
        uint64_t cfg = value & 0x9FULL;
        if ((cfg & PMP_W) && !(cfg & PMP_R)) {
            cfg &= ~PMP_W;
        }
        return cfg;
    }

    static uint8_t csr_privilege(uint32_t addr) {
        return static_cast<uint8_t>((addr >> 8) & 0x3);
    }

    static bool csr_is_read_only(uint32_t addr) {
        return ((addr >> 10) & 0x3) == 0x3;
    }

    bool should_delegate_exception(uint64_t cause) const {
        if (current_priv == PRV_M || (cause & INTERRUPT_FLAG)) return false;
        return ((read_csr(CSR_MEDELEG) >> (cause & 0x3F)) & 1ULL) != 0;
    }

    bool should_delegate_interrupt(uint64_t cause) const {
        if (current_priv == PRV_M || (cause & INTERRUPT_FLAG) == 0) return false;
        return ((read_csr(CSR_MIDELEG) >> (cause & 0x3F)) & 1ULL) != 0;
    }

    bool pmp_range(uint64_t& start, uint64_t& end) const {
        const uint64_t cfg = read_csr(CSR_PMPCFG0);
        const uint64_t a = (cfg & PMP_A_MASK) >> 3;
        const uint64_t addr = read_csr(CSR_PMPADDR0);

        switch (a) {
        case 0:
            return false;
        case 1:
            start = 0;
            end = addr << 2;
            return true;
        case 2:
            start = addr << 2;
            end = start + 4;
            return true;
        case 3: {
            unsigned trailing_ones = 0;
            while (trailing_ones < 63 && ((addr >> trailing_ones) & 1ULL)) {
                trailing_ones++;
            }
            const uint64_t low_mask =
                (trailing_ones >= 63) ? ~0ULL : ((1ULL << (trailing_ones + 1)) - 1);
            const uint64_t size =
                (trailing_ones >= 61) ? ~0ULL : (1ULL << (trailing_ones + 3));
            start = (addr & ~low_mask) << 2;
            end = (size == ~0ULL || start > (~0ULL - size)) ? ~0ULL : (start + size);
            return true;
        }
        default:
            return false;
        }
    }

    bool pmp_allows(uint64_t paddr, unsigned size, uint8_t access_type,
                    uint8_t eff_priv, uint64_t curr_pc, uint64_t fault_tval) {
        uint64_t range_start = 0;
        uint64_t range_end = 0;
        if (!pmp_range(range_start, range_end)) {
            return true;
        }

        const uint64_t last_byte = paddr + static_cast<uint64_t>(size - 1);
        const bool overflowed = last_byte < paddr;
        const bool fully_matched = !overflowed && paddr >= range_start && last_byte < range_end;
        const uint64_t cfg = read_csr(CSR_PMPCFG0);

        if (!fully_matched) {
            if (eff_priv == PRV_M) {
                return true;
            }
            raise_trap(access_fault_cause(access_type), curr_pc, fault_tval);
            return false;
        }

        if (eff_priv == PRV_M && !(cfg & PMP_L)) {
            return true;
        }

        const bool allowed =
            (access_type == ACCESS_FETCH) ? ((cfg & PMP_X) != 0) :
            (access_type == ACCESS_LOAD)  ? ((cfg & PMP_R) != 0) :
                                            ((cfg & PMP_W) != 0);
        if (!allowed) {
            raise_trap(access_fault_cause(access_type), curr_pc, fault_tval);
            return false;
        }
        return true;
    }

    uint64_t read_mstatus() const {
        return canonical_mstatus(csr[CSR_MSTATUS]);
    }

    uint64_t read_sstatus() const {
        return read_mstatus() & SSTATUS_MASK;
    }

    uint64_t read_mip() const {
        return csr[CSR_MIP];
    }

    uint64_t read_sip() const {
        return read_mip() & MIP_S_MASK;
    }

    uint64_t read_sie() const {
        return read_csr(CSR_MIE) & MIP_S_MASK;
    }

    void write_mstatus(uint64_t value) {
        mstatus_tsr = (value & MSTATUS_TSR) != 0;
        csr[CSR_MSTATUS] = canonical_mstatus(value);
    }

    void store_mstatus_visible(uint64_t value) {
        csr[CSR_MSTATUS] = canonical_mstatus(value);
    }

    void write_sstatus(uint64_t value) {
        const uint64_t next = (read_mstatus() & ~SSTATUS_MASK) | (value & SSTATUS_MASK);
        store_mstatus_visible(next);
    }

    uint64_t trap_vector_base(bool to_supervisor) const {
        return to_supervisor ? (read_csr(CSR_STVEC) & ~0x3ULL)
                             : (read_csr(CSR_MTVEC) & ~0x3ULL);
    }

    void schedule_interrupt_once(uint64_t at_cycle, uint64_t mip_mask) {
        scheduled_irq_cycle = at_cycle;
        scheduled_irq_mask = mip_mask;
        scheduled_irq_armed = (mip_mask != 0);
        scheduled_irq_use_pc = false;
    }

    void schedule_interrupt_once_at_pc(uint64_t at_pc, uint64_t mip_mask) {
        scheduled_irq_pc = at_pc;
        scheduled_irq_mask = mip_mask;
        scheduled_irq_armed = (mip_mask != 0);
        scheduled_irq_use_pc = true;
    }

    uint64_t read_csr(uint32_t addr) const {
        switch (addr) {
        case CSR_MSTATUS: return read_mstatus();
        case CSR_MISA: return MISA_VALUE;
        case CSR_MEDELEG: return csr[addr];
        case CSR_MIDELEG: return csr[addr];
        case CSR_MIE: return csr[addr];
        case CSR_MTVEC: return csr[addr];
        case CSR_MCOUNTEREN: return csr[addr];
        case CSR_MSCRATCH: return csr[addr];
        case CSR_MEPC: return csr[addr];
        case CSR_MCAUSE: return csr[addr];
        case CSR_MTVAL: return csr[addr];
        case CSR_MIP: return read_mip();
        case CSR_SSTATUS: return read_sstatus();
        case CSR_SIE: return read_sie();
        case CSR_STVEC: return csr[addr];
        case CSR_SCOUNTEREN: return csr[addr];
        case CSR_SSCRATCH: return csr[addr];
        case CSR_SEPC: return csr[addr];
        case CSR_SCAUSE: return csr[addr];
        case CSR_STVAL: return csr[addr];
        case CSR_SIP: return read_sip();
        case CSR_SATP: return csr[addr];
        case CSR_PMPCFG0: return csr[addr];
        case CSR_PMPADDR0: return csr[addr];
        case CSR_MVENDORID: return MVENDORID_VALUE;
        case CSR_MARCHID: return MARCHID_VALUE;
        case CSR_MIMPID: return MIMPID_VALUE;
        case CSR_MHARTID: return MHARTID_VALUE;
        case 0x102: return 0;            // sedeleg stub
        case 0x103: return 0;            // sideleg stub
        case 0x744: return 0;            // mnstatus stub
        case 0x7C0:
        case 0x7C1:
        case 0x7C2:
        case 0x7C3: return 0;            // ARES custom CSRs not modeled yet
        case 0x7A0: return 0;            // tselect stubbed to slot 0 only, matching RTL
        case 0x7A1:
        case 0x7A2:
        case 0x7A3:
        case 0x7A5: return 0;            // debug trigger CSRs stubbed
        case CSR_MCYCLE: return cycle;
        case CSR_MINSTRET: return instret;
        default: return csr[addr];
        }
    }

    void write_csr(uint32_t addr, uint64_t value) {
        switch (addr) {
        case CSR_MISA:
        case CSR_MVENDORID:
        case CSR_MARCHID:
        case CSR_MIMPID:
        case CSR_MHARTID:
        case 0x744:
        case 0x7C0:
        case 0x7A0:
        case 0x7A1:
        case 0x7A2:
        case 0x7A3:
        case 0x7A5:
            return;
        case 0x102:
        case 0x103:
            return;
        case CSR_MCYCLE:
            cycle = value;
            suppress_instret_increment = true;
            return;
        case CSR_MINSTRET:
            instret = value;
            suppress_instret_increment = true;
            return;
        case CSR_MSTATUS:
            write_mstatus(value);
            return;
        case CSR_SSTATUS:
            write_sstatus(value);
            return;
        case CSR_MTVEC:
        case CSR_STVEC:
            csr[addr] = value & ~0x3ULL;
            return;
        case CSR_MEPC:
        case CSR_SEPC:
            csr[addr] = value & ~1ULL;
            return;
        case CSR_PMPCFG0:
            if ((read_csr(CSR_PMPCFG0) & PMP_L) == 0) {
                csr[addr] = canonical_pmpcfg0(value);
            }
            return;
        case CSR_PMPADDR0:
            if ((read_csr(CSR_PMPCFG0) & PMP_L) == 0) {
                csr[addr] = value;
            }
            return;
        case CSR_SIE:
            csr[CSR_MIE] = (csr[CSR_MIE] & ~MIP_S_MASK) | (value & MIP_S_MASK);
            return;
        case CSR_SIP:
            csr[CSR_MIP] = (csr[CSR_MIP] & ~MIP_S_MASK) | (value & MIP_S_MASK);
            return;
        default:
            csr[addr] = value;
            return;
        }
    }

    void raise_trap(uint64_t cause, uint64_t fault_pc, uint64_t tval) {
        const uint64_t mstatus = read_mstatus();
        if (should_delegate_exception(cause)) {
            csr[CSR_SEPC] = fault_pc & ~1ULL;
            csr[CSR_SCAUSE] = cause;
            csr[CSR_STVAL] = tval;
            uint64_t next = mstatus;
            if (mstatus & MSTATUS_SIE) next |= MSTATUS_SPIE;
            else                      next &= ~MSTATUS_SPIE;
            next &= ~MSTATUS_SIE;
            if (current_priv == PRV_S) next |= MSTATUS_SPP;
            else                       next &= ~MSTATUS_SPP;
            store_mstatus_visible(next);
            current_priv = PRV_S;
            pc = trap_vector_base(true);
        } else {
            csr[CSR_MEPC] = fault_pc & ~1ULL;
            csr[CSR_MCAUSE] = cause;
            csr[CSR_MTVAL] = tval;
            uint64_t next = mstatus;
            if (mstatus & MSTATUS_MIE) next |= MSTATUS_MPIE;
            else                      next &= ~MSTATUS_MPIE;
            next &= ~MSTATUS_MIE;
            next = (next & ~MSTATUS_MPP_MASK) | (static_cast<uint64_t>(current_priv) << 11);
            store_mstatus_visible(next);
            current_priv = PRV_M;
            pc = trap_vector_base(false);
        }
        reservation_valid = false;
    }

    void raise_illegal(uint64_t fault_pc) {
        raise_trap(CAUSE_ILLEGAL_INSTR, fault_pc, 0);
    }

    uint64_t pending_interrupt_cause() const {
        const uint64_t mstatus = read_mstatus();
        const uint64_t pending_machine = read_csr(CSR_MIE) & read_csr(CSR_MIP) & (MIP_MSIP | MIP_MTIP | MIP_MEIP);
        const uint64_t pending_supervisor = read_csr(CSR_MIE) & read_csr(CSR_MIP) & MIP_S_MASK;
        const uint64_t pending_machine_targets =
            (current_priv != PRV_M)
                ? (pending_machine & ~read_csr(CSR_MIDELEG))
                : pending_machine;
        const uint64_t pending_supervisor_targets =
            (current_priv != PRV_M)
                ? (pending_supervisor & read_csr(CSR_MIDELEG))
                : 0;
        const bool machine_interrupts_enabled =
            (current_priv != PRV_M) || ((mstatus & MSTATUS_MIE) != 0);
        const bool supervisor_interrupts_enabled =
            (current_priv == PRV_U) ||
            ((current_priv == PRV_S) && ((mstatus & MSTATUS_SIE) != 0));
        const uint64_t pending =
            (machine_interrupts_enabled ? pending_machine_targets : 0) |
            (supervisor_interrupts_enabled ? pending_supervisor_targets : 0);

        if (pending & MIP_MEIP) return CAUSE_MEIP;
        if (pending & MIP_SEIP) return CAUSE_SEIP;
        if (pending & MIP_MTIP) return CAUSE_MTIP;
        if (pending & MIP_STIP) return CAUSE_STIP;
        if (pending & MIP_MSIP) return CAUSE_MSIP;
        if (pending & MIP_SSIP) return CAUSE_SSIP;
        return 0;
    }

    void take_interrupt(uint64_t cause) {
        const uint64_t mstatus = read_mstatus();
        if (should_delegate_interrupt(cause)) {
            csr[CSR_SEPC] = pc & ~1ULL;
            csr[CSR_SCAUSE] = cause;
            csr[CSR_STVAL] = 0;
            uint64_t next = mstatus;
            if (mstatus & MSTATUS_SIE) next |= MSTATUS_SPIE;
            else                      next &= ~MSTATUS_SPIE;
            next &= ~MSTATUS_SIE;
            if (current_priv == PRV_S) next |= MSTATUS_SPP;
            else                       next &= ~MSTATUS_SPP;
            store_mstatus_visible(next);
            current_priv = PRV_S;
            pc = trap_vector_base(true);
        } else {
            csr[CSR_MEPC] = pc & ~1ULL;
            csr[CSR_MCAUSE] = cause;
            csr[CSR_MTVAL] = 0;
            uint64_t next = mstatus;
            if (mstatus & MSTATUS_MIE) next |= MSTATUS_MPIE;
            else                      next &= ~MSTATUS_MPIE;
            next &= ~MSTATUS_MIE;
            next = (next & ~MSTATUS_MPP_MASK) | (static_cast<uint64_t>(current_priv) << 11);
            store_mstatus_visible(next);
            current_priv = PRV_M;
            pc = trap_vector_base(false);
        }
        reservation_valid = false;
    }

    bool check_alignment(uint64_t addr, unsigned size, uint64_t cause, uint64_t fault_pc) {
        if ((addr & (size - 1)) != 0) {
            raise_trap(cause, fault_pc, addr);
            return false;
        }
        return true;
    }

    uint64_t csr_next(uint64_t old_value, uint64_t write_value, uint32_t op) const {
        switch (op) {
        case 0x1:
        case 0x5: return write_value;
        case 0x2:
        case 0x6: return old_value | write_value;
        case 0x3:
        case 0x7: return old_value & ~write_value;
        default: return old_value;
        }
    }

    uint8_t effective_data_priv() const {
        const uint64_t mstatus = read_mstatus();
        if (current_priv == PRV_M && (mstatus & MSTATUS_MPRV)) {
            return static_cast<uint8_t>((mstatus & MSTATUS_MPP_MASK) >> 11);
        }
        return current_priv;
    }

    bool translate_address(uint64_t vaddr, uint8_t eff_priv, uint8_t access_type,
                           unsigned access_size, uint64_t curr_pc, uint64_t& paddr) {
        constexpr uint64_t SATP_MODE_SV39 = 8ULL;
        constexpr uint64_t PTE_V = 1ULL << 0;
        constexpr uint64_t PTE_R = 1ULL << 1;
        constexpr uint64_t PTE_W = 1ULL << 2;
        constexpr uint64_t PTE_X = 1ULL << 3;
        constexpr uint64_t PTE_U = 1ULL << 4;
        constexpr uint64_t PTE_A = 1ULL << 6;
        constexpr uint64_t PTE_D = 1ULL << 7;

        paddr = vaddr;
        const uint64_t satp = read_csr(CSR_SATP);
        if (((satp >> 60) != SATP_MODE_SV39) || eff_priv == PRV_M) {
            return pmp_allows(paddr, access_size, access_type, eff_priv, curr_pc, vaddr);
        }

        uint64_t table_addr = (satp & ((1ULL << 44) - 1)) << 12;
        const uint64_t vpn[3] = {
            (vaddr >> 12) & 0x1FF,
            (vaddr >> 21) & 0x1FF,
            (vaddr >> 30) & 0x1FF,
        };
        const uint64_t page_fault_cause =
            (access_type == ACCESS_FETCH) ? CAUSE_FETCH_PAGE_FAULT :
            (access_type == ACCESS_LOAD)  ? CAUSE_LOAD_PAGE_FAULT :
                                            CAUSE_STORE_PAGE_FAULT;
        const uint64_t canonical_upper = (vaddr >> 38) & 1ULL ? ((1ULL << 25) - 1) : 0;
        if ((vaddr >> 39) != canonical_upper) {
            raise_trap(page_fault_cause, curr_pc, vaddr);
            return false;
        }

        for (int level = 2; level >= 0; --level) {
            const uint64_t pte_addr = table_addr + vpn[level] * 8;
            if (!pmp_allows(pte_addr, 8, access_type, PRV_S, curr_pc, vaddr)) {
                return false;
            }
            const uint64_t pte = mem.read64(pte_addr);
            if ((pte & PTE_V) == 0 || ((pte & PTE_R) == 0 && (pte & PTE_W) != 0)) {
                raise_trap(page_fault_cause, curr_pc, vaddr);
                return false;
            }

            if ((pte & (PTE_R | PTE_X)) == 0) {
                if (level == 0) {
                    raise_trap(page_fault_cause, curr_pc, vaddr);
                    return false;
                }
                table_addr = ((pte >> 10) & ((1ULL << 44) - 1)) << 12;
                continue;
            }

            const uint64_t pte_ppn = (pte >> 10) & ((1ULL << 44) - 1);
            if ((level == 2 && (pte_ppn & ((1ULL << 18) - 1)) != 0) ||
                (level == 1 && (pte_ppn & ((1ULL << 9) - 1)) != 0)) {
                raise_trap(page_fault_cause, curr_pc, vaddr);
                return false;
            }

            if (access_type == ACCESS_FETCH) {
                if ((pte & PTE_X) == 0 || (eff_priv == PRV_S && (pte & PTE_U)) ||
                    (eff_priv == PRV_U && (pte & PTE_U) == 0) ||
                    (pte & PTE_A) == 0) {
                    raise_trap(page_fault_cause, curr_pc, vaddr);
                    return false;
                }
            } else if (access_type == ACCESS_LOAD) {
                const bool load_permitted = ((pte & PTE_R) != 0) ||
                                            (((read_mstatus() & MSTATUS_MXR) != 0) && ((pte & PTE_X) != 0));
                if (!load_permitted ||
                    (eff_priv == PRV_S && (pte & PTE_U) && ((read_mstatus() & MSTATUS_SUM) == 0)) ||
                    (eff_priv == PRV_U && (pte & PTE_U) == 0) ||
                    (pte & PTE_A) == 0) {
                    raise_trap(page_fault_cause, curr_pc, vaddr);
                    return false;
                }
            } else {
                if ((pte & PTE_W) == 0 ||
                    (eff_priv == PRV_S && (pte & PTE_U) && ((read_mstatus() & MSTATUS_SUM) == 0)) ||
                    (eff_priv == PRV_U && (pte & PTE_U) == 0) ||
                    (pte & PTE_A) == 0 || (pte & PTE_D) == 0) {
                    raise_trap(page_fault_cause, curr_pc, vaddr);
                    return false;
                }
            }

            const uint64_t page_mask = (level == 2) ? 0x3FFFFFFFULL :
                                       (level == 1) ? 0x1FFFFFULL :
                                                      0xFFFULL;
            paddr = ((pte_ppn << 12) & ~page_mask) | (vaddr & page_mask);
            return pmp_allows(paddr, access_size, access_type, eff_priv, curr_pc, vaddr);
        }

        raise_trap(page_fault_cause, curr_pc, vaddr);
        return false;
    }

    bool execute_system(uint64_t curr_pc, uint32_t instr, uint32_t rd, uint32_t rs1, uint32_t funct3) {
        const uint32_t csr_addr = instr >> 20;
        if (funct3 == 0x0) {
            if (instr == 0x00000073U) {
                const uint64_t cause =
                    (current_priv == PRV_U) ? CAUSE_ECALL_UMODE :
                    (current_priv == PRV_S) ? CAUSE_ECALL_SMODE :
                                              CAUSE_ECALL_MMODE;
                raise_trap(cause, curr_pc, 0);
                return false;
            }
            if (instr == 0x00100073U) {
                raise_trap(CAUSE_BREAKPOINT, curr_pc, 0);
                return false;
            }
            if (instr == 0x10200073U) {
                if (current_priv == PRV_U || ((current_priv == PRV_S) && mstatus_tsr)) {
                    raise_illegal(curr_pc);
                    return false;
                }
                uint64_t mstatus = read_mstatus();
                current_priv = (mstatus & MSTATUS_SPP) ? PRV_S : PRV_U;
                if (mstatus & MSTATUS_SPIE) mstatus |= MSTATUS_SIE;
                else                        mstatus &= ~MSTATUS_SIE;
                mstatus |= MSTATUS_SPIE;
                mstatus &= ~MSTATUS_SPP;
                mstatus &= ~MSTATUS_MPRV;
                store_mstatus_visible(mstatus);
                pc = read_csr(CSR_SEPC);
                return true;
            }
            if (instr == 0x10500073U) {
                return true;
            }
            if ((instr & 0xFE007FFFU) == 0x12000073U) {
                if (current_priv == PRV_S && (read_mstatus() & MSTATUS_TVM)) {
                    raise_illegal(curr_pc);
                    return false;
                }
                return true;
            }
            if (instr == 0x30200073U) {
                if (current_priv != PRV_M) {
                    raise_illegal(curr_pc);
                    return false;
                }
                uint64_t mstatus = read_mstatus();
                current_priv = static_cast<uint8_t>((mstatus & MSTATUS_MPP_MASK) >> 11);
                if (mstatus & MSTATUS_MPIE) mstatus |= MSTATUS_MIE;
                else                        mstatus &= ~MSTATUS_MIE;
                mstatus |= MSTATUS_MPIE;
                mstatus &= ~MSTATUS_MPP_MASK;
                if (current_priv != PRV_M) {
                    mstatus &= ~MSTATUS_MPRV;
                }
                store_mstatus_visible(mstatus);
                pc = read_csr(CSR_MEPC);
                return true;
            }
            raise_illegal(curr_pc);
            return false;
        }

        const bool csr_write =
            (funct3 == 0x1) || (funct3 == 0x5) ||
            (((funct3 == 0x2) || (funct3 == 0x3) || (funct3 == 0x6) || (funct3 == 0x7)) && (rs1 != 0));
        if (current_priv < csr_privilege(csr_addr)) {
            raise_illegal(curr_pc);
            return false;
        }
        if (current_priv == PRV_S && (read_mstatus() & MSTATUS_TVM) && csr_addr == CSR_SATP) {
            raise_illegal(curr_pc);
            return false;
        }
        if (csr_write && csr_is_read_only(csr_addr)) {
            raise_illegal(curr_pc);
            return false;
        }
        const uint64_t old_value = read_csr(csr_addr);
        const uint64_t write_value = (funct3 >= 0x5) ? rs1 : regs[rs1];
        set_reg(rd, old_value);
        if (csr_write) {
            write_csr(csr_addr, csr_next(old_value, write_value, funct3));
        }
        return true;
    }

    bool execute_atomic(uint64_t curr_pc, uint32_t instr, uint32_t rd, uint32_t rs1, uint32_t rs2, uint32_t funct3) {
        const uint32_t funct5 = instr >> 27;
        const bool is_word = (funct3 == 0x2);
        const bool is_dword = (funct3 == 0x3);
        const unsigned size = is_word ? 4 : 8;
        const uint64_t addr = regs[rs1];
        uint64_t phys_addr = addr;

        if (!is_word && !is_dword) {
            raise_illegal(curr_pc);
            return false;
        }
        if (!check_alignment(addr, size, CAUSE_STORE_MISALIGNED, curr_pc)) {
            return false;
        }
        if (!translate_address(addr, effective_data_priv(), ACCESS_STORE, size, curr_pc, phys_addr)) {
            return false;
        }

        const auto read_old = [&]() -> uint64_t {
            return is_word ? static_cast<uint64_t>(static_cast<int64_t>(static_cast<int32_t>(mem.read32(phys_addr))))
                           : mem.read64(phys_addr);
        };

        if (funct5 == 0x02) { // LR
            if (rs2 != 0) {
                raise_illegal(curr_pc);
                return false;
            }
            const uint64_t old_value = read_old();
            reservation_valid = true;
            reservation_addr = addr;
            set_reg(rd, old_value);
            return true;
        }

        if (funct5 == 0x03) { // SC
            const bool success = reservation_valid && (reservation_addr == addr);
            if (success) {
                if (is_word) mem.write32(phys_addr, static_cast<uint32_t>(regs[rs2]));
                else mem.write64(phys_addr, regs[rs2]);
            }
            reservation_valid = false;
            reservation_addr = 0;
            set_reg(rd, success ? 0 : 1);
            return true;
        }

        const uint64_t old_value = read_old();
        uint64_t new_value = regs[rs2];
        if (is_word) {
            const uint32_t old_w = static_cast<uint32_t>(old_value);
            const uint32_t rs2_w = static_cast<uint32_t>(regs[rs2]);
            switch (funct5) {
            case 0x01: new_value = rs2_w; break; // amoswap.w
            case 0x00: new_value = static_cast<uint32_t>(old_w + rs2_w); break;
            case 0x04: new_value = old_w ^ rs2_w; break;
            case 0x0C: new_value = old_w & rs2_w; break;
            case 0x08: new_value = old_w | rs2_w; break;
            case 0x10: new_value = (static_cast<int32_t>(old_w) < static_cast<int32_t>(rs2_w)) ? old_w : rs2_w; break;
            case 0x14: new_value = (static_cast<int32_t>(old_w) > static_cast<int32_t>(rs2_w)) ? old_w : rs2_w; break;
            case 0x18: new_value = (old_w < rs2_w) ? old_w : rs2_w; break;
            case 0x1C: new_value = (old_w > rs2_w) ? old_w : rs2_w; break;
            default:
                raise_illegal(curr_pc);
                return false;
            }
            mem.write32(phys_addr, static_cast<uint32_t>(new_value));
            set_reg(rd, static_cast<uint64_t>(static_cast<int64_t>(static_cast<int32_t>(old_w))));
        } else {
            const int64_t old_s = static_cast<int64_t>(old_value);
            const int64_t rs2_s = static_cast<int64_t>(regs[rs2]);
            switch (funct5) {
            case 0x01: new_value = regs[rs2]; break; // amoswap.d
            case 0x00: new_value = old_value + regs[rs2]; break;
            case 0x04: new_value = old_value ^ regs[rs2]; break;
            case 0x0C: new_value = old_value & regs[rs2]; break;
            case 0x08: new_value = old_value | regs[rs2]; break;
            case 0x10: new_value = (old_s < rs2_s) ? old_value : regs[rs2]; break;
            case 0x14: new_value = (old_s > rs2_s) ? old_value : regs[rs2]; break;
            case 0x18: new_value = (old_value < regs[rs2]) ? old_value : regs[rs2]; break;
            case 0x1C: new_value = (old_value > regs[rs2]) ? old_value : regs[rs2]; break;
            default:
                raise_illegal(curr_pc);
                return false;
            }
            mem.write64(phys_addr, new_value);
            set_reg(rd, old_value);
        }

        reservation_valid = false;
        reservation_addr = 0;
        return true;
    }

    bool execute(uint64_t curr_pc, uint32_t instr) {
        const uint32_t opcode = instr & 0x7F;
        const uint32_t rd = (instr >> 7) & 0x1F;
        const uint32_t funct3 = (instr >> 12) & 0x07;
        const uint32_t rs1 = (instr >> 15) & 0x1F;
        const uint32_t rs2 = (instr >> 20) & 0x1F;
        const uint32_t funct7 = instr >> 25;
        const uint64_t rs1v = regs[rs1];
        const uint64_t rs2v = regs[rs2];
        const uint64_t imm_i = sign_extend(instr >> 20, 12);
        const uint64_t imm_s = sign_extend(((instr >> 25) << 5) | ((instr >> 7) & 0x1F), 12);
        const uint64_t imm_b = sign_extend(
            (((instr >> 31) & 0x1) << 12) |
            (((instr >> 7) & 0x1) << 11) |
            (((instr >> 25) & 0x3F) << 5) |
            (((instr >> 8) & 0xF) << 1), 13);
        const uint64_t imm_u = static_cast<uint64_t>(static_cast<int64_t>(static_cast<int32_t>(instr & 0xFFFFF000U)));
        const uint64_t imm_j = sign_extend(
            (((instr >> 31) & 0x1) << 20) |
            (((instr >> 12) & 0xFF) << 12) |
            (((instr >> 20) & 0x1) << 11) |
            (((instr >> 21) & 0x3FF) << 1), 21);

        switch (opcode) {
        case 0x33: {
            if (funct7 == 0x01) {
                const __int128 sa = static_cast<int64_t>(rs1v);
                const __int128 sb = static_cast<int64_t>(rs2v);
                const unsigned __int128 ua = rs1v;
                const unsigned __int128 ub = rs2v;
                switch (funct3) {
                case 0x0: set_reg(rd, rs1v * rs2v); break; // MUL
                case 0x1: set_reg(rd, static_cast<uint64_t>((sa * sb) >> 64)); break; // MULH
                case 0x2: set_reg(rd, static_cast<uint64_t>((sa * static_cast<__int128>(ub)) >> 64)); break; // MULHSU
                case 0x3: set_reg(rd, static_cast<uint64_t>((ua * ub) >> 64)); break; // MULHU
                case 0x4:
                    if (rs2v == 0) set_reg(rd, ~0ULL);
                    else if (rs1v == 0x8000000000000000ULL && rs2v == ~0ULL) set_reg(rd, rs1v);
                    else set_reg(rd, static_cast<uint64_t>(static_cast<int64_t>(rs1v) / static_cast<int64_t>(rs2v)));
                    break;
                case 0x5: set_reg(rd, rs2v == 0 ? ~0ULL : rs1v / rs2v); break;
                case 0x6:
                    if (rs2v == 0) set_reg(rd, rs1v);
                    else if (rs1v == 0x8000000000000000ULL && rs2v == ~0ULL) set_reg(rd, 0);
                    else set_reg(rd, static_cast<uint64_t>(static_cast<int64_t>(rs1v) % static_cast<int64_t>(rs2v)));
                    break;
                case 0x7: set_reg(rd, rs2v == 0 ? rs1v : rs1v % rs2v); break;
                default:
                    raise_illegal(curr_pc);
                    return false;
                }
                return true;
            }

            switch (funct3) {
            case 0x0:
                if (funct7 == 0x00) set_reg(rd, rs1v + rs2v);
                else if (funct7 == 0x20) set_reg(rd, rs1v - rs2v);
                else { raise_illegal(curr_pc); return false; }
                break;
            case 0x1:
                if (funct7 != 0x00) { raise_illegal(curr_pc); return false; }
                set_reg(rd, rs1v << (rs2v & 0x3F));
                break;
            case 0x2:
                if (funct7 != 0x00) { raise_illegal(curr_pc); return false; }
                set_reg(rd, static_cast<int64_t>(rs1v) < static_cast<int64_t>(rs2v) ? 1 : 0);
                break;
            case 0x3:
                if (funct7 != 0x00) { raise_illegal(curr_pc); return false; }
                set_reg(rd, rs1v < rs2v ? 1 : 0);
                break;
            case 0x4:
                if (funct7 != 0x00) { raise_illegal(curr_pc); return false; }
                set_reg(rd, rs1v ^ rs2v);
                break;
            case 0x5:
                if (funct7 == 0x00) set_reg(rd, rs1v >> (rs2v & 0x3F));
                else if (funct7 == 0x20) set_reg(rd, static_cast<uint64_t>(static_cast<int64_t>(rs1v) >> (rs2v & 0x3F)));
                else { raise_illegal(curr_pc); return false; }
                break;
            case 0x6:
                if (funct7 != 0x00) { raise_illegal(curr_pc); return false; }
                set_reg(rd, rs1v | rs2v);
                break;
            case 0x7:
                if (funct7 != 0x00) { raise_illegal(curr_pc); return false; }
                set_reg(rd, rs1v & rs2v);
                break;
            default:
                raise_illegal(curr_pc);
                return false;
            }
            return true;
        }

        case 0x3B: {
            const uint32_t a = static_cast<uint32_t>(rs1v);
            const uint32_t b = static_cast<uint32_t>(rs2v);
            uint32_t result = 0;
            if (funct7 == 0x01) {
                switch (funct3) {
                case 0x0: result = static_cast<uint32_t>(static_cast<int64_t>(static_cast<int32_t>(a)) * static_cast<int64_t>(static_cast<int32_t>(b))); break;
                case 0x4:
                    if (b == 0) result = 0xFFFFFFFFU;
                    else if (a == 0x80000000U && b == 0xFFFFFFFFU) result = 0x80000000U;
                    else result = static_cast<uint32_t>(static_cast<int32_t>(a) / static_cast<int32_t>(b));
                    break;
                case 0x5: result = (b == 0) ? 0xFFFFFFFFU : (a / b); break;
                case 0x6:
                    if (b == 0) result = a;
                    else if (a == 0x80000000U && b == 0xFFFFFFFFU) result = 0;
                    else result = static_cast<uint32_t>(static_cast<int32_t>(a) % static_cast<int32_t>(b));
                    break;
                case 0x7: result = (b == 0) ? a : (a % b); break;
                default:
                    raise_illegal(curr_pc);
                    return false;
                }
            } else {
                switch (funct3) {
                case 0x0:
                    if (funct7 == 0x00) result = a + b;
                    else if (funct7 == 0x20) result = a - b;
                    else { raise_illegal(curr_pc); return false; }
                    break;
                case 0x1:
                    if (funct7 != 0x00) { raise_illegal(curr_pc); return false; }
                    result = a << (b & 0x1F);
                    break;
                case 0x5:
                    if (funct7 == 0x00) result = a >> (b & 0x1F);
                    else if (funct7 == 0x20) result = static_cast<uint32_t>(static_cast<int32_t>(a) >> (b & 0x1F));
                    else { raise_illegal(curr_pc); return false; }
                    break;
                default:
                    raise_illegal(curr_pc);
                    return false;
                }
            }
            set_reg(rd, static_cast<uint64_t>(static_cast<int64_t>(static_cast<int32_t>(result))));
            return true;
        }

        case 0x13: {
            const uint32_t shamt = (instr >> 20) & 0x3F;
            switch (funct3) {
            case 0x0: set_reg(rd, rs1v + imm_i); break;
            case 0x1:
                if ((funct7 >> 1) != 0x00) { raise_illegal(curr_pc); return false; }
                set_reg(rd, rs1v << shamt);
                break;
            case 0x2: set_reg(rd, static_cast<int64_t>(rs1v) < static_cast<int64_t>(imm_i) ? 1 : 0); break;
            case 0x3: set_reg(rd, rs1v < imm_i ? 1 : 0); break;
            case 0x4: set_reg(rd, rs1v ^ imm_i); break;
            case 0x5:
                if ((funct7 >> 1) == 0x00) set_reg(rd, rs1v >> shamt);
                else if ((funct7 >> 1) == 0x10) set_reg(rd, static_cast<uint64_t>(static_cast<int64_t>(rs1v) >> shamt));
                else { raise_illegal(curr_pc); return false; }
                break;
            case 0x6: set_reg(rd, rs1v | imm_i); break;
            case 0x7: set_reg(rd, rs1v & imm_i); break;
            default:
                raise_illegal(curr_pc);
                return false;
            }
            return true;
        }

        case 0x1B: {
            const uint32_t shamt = (instr >> 20) & 0x1F;
            uint32_t result = 0;
            switch (funct3) {
            case 0x0: result = static_cast<uint32_t>(rs1v + imm_i); break;
            case 0x1:
                if (funct7 != 0x00) { raise_illegal(curr_pc); return false; }
                result = static_cast<uint32_t>(rs1v) << shamt;
                break;
            case 0x5:
                if (funct7 == 0x00) result = static_cast<uint32_t>(rs1v) >> shamt;
                else if (funct7 == 0x20) result = static_cast<uint32_t>(static_cast<int32_t>(rs1v) >> shamt);
                else { raise_illegal(curr_pc); return false; }
                break;
            default:
                raise_illegal(curr_pc);
                return false;
            }
            set_reg(rd, static_cast<uint64_t>(static_cast<int64_t>(static_cast<int32_t>(result))));
            return true;
        }

        case 0x03: {
            const uint64_t addr = rs1v + imm_i;
            uint64_t phys_addr = addr;
            switch (funct3) {
            case 0x0:
            case 0x4:
                if (!translate_address(addr, effective_data_priv(), ACCESS_LOAD, 1, curr_pc, phys_addr)) {
                    return false;
                }
                break;
            case 0x1:
            case 0x5:
                if (!translate_address(addr, effective_data_priv(), ACCESS_LOAD, 2, curr_pc, phys_addr)) {
                    return false;
                }
                break;
            case 0x2:
            case 0x6:
                if (!translate_address(addr, effective_data_priv(), ACCESS_LOAD, 4, curr_pc, phys_addr)) {
                    return false;
                }
                break;
            case 0x3:
                if (!translate_address(addr, effective_data_priv(), ACCESS_LOAD, 8, curr_pc, phys_addr)) {
                    return false;
                }
                break;
            default:
                raise_illegal(curr_pc);
                return false;
            }
            switch (funct3) {
            case 0x0: set_reg(rd, static_cast<uint64_t>(static_cast<int64_t>(static_cast<int8_t>(mem.read8(phys_addr))))); break;
            case 0x1: set_reg(rd, static_cast<uint64_t>(static_cast<int64_t>(static_cast<int16_t>(mem.read16(phys_addr))))); break;
            case 0x2: set_reg(rd, static_cast<uint64_t>(static_cast<int64_t>(static_cast<int32_t>(mem.read32(phys_addr))))); break;
            case 0x3: set_reg(rd, mem.read64(phys_addr)); break;
            case 0x4: set_reg(rd, mem.read8(phys_addr)); break;
            case 0x5: set_reg(rd, mem.read16(phys_addr)); break;
            case 0x6: set_reg(rd, mem.read32(phys_addr)); break;
            default:
                raise_illegal(curr_pc);
                return false;
            }
            return true;
        }

        case 0x23: {
            const uint64_t addr = rs1v + imm_s;
            uint64_t phys_addr = addr;
            switch (funct3) {
            case 0x0:
                if (!translate_address(addr, effective_data_priv(), ACCESS_STORE, 1, curr_pc, phys_addr)) {
                    return false;
                }
                break;
            case 0x1:
                if (!translate_address(addr, effective_data_priv(), ACCESS_STORE, 2, curr_pc, phys_addr)) {
                    return false;
                }
                break;
            case 0x2:
                if (!translate_address(addr, effective_data_priv(), ACCESS_STORE, 4, curr_pc, phys_addr)) {
                    return false;
                }
                break;
            case 0x3:
                if (!translate_address(addr, effective_data_priv(), ACCESS_STORE, 8, curr_pc, phys_addr)) {
                    return false;
                }
                break;
            default:
                raise_illegal(curr_pc);
                return false;
            }
            switch (funct3) {
            case 0x0: mem.write8(phys_addr, static_cast<uint8_t>(rs2v)); break;
            case 0x1: mem.write16(phys_addr, static_cast<uint16_t>(rs2v)); break;
            case 0x2: mem.write32(phys_addr, static_cast<uint32_t>(rs2v)); break;
            case 0x3: mem.write64(phys_addr, rs2v); break;
            default:
                raise_illegal(curr_pc);
                return false;
            }
            reservation_valid = false;
            reservation_addr = 0;
            return true;
        }

        case 0x63: {
            bool taken = false;
            switch (funct3) {
            case 0x0: taken = (rs1v == rs2v); break;
            case 0x1: taken = (rs1v != rs2v); break;
            case 0x4: taken = (static_cast<int64_t>(rs1v) < static_cast<int64_t>(rs2v)); break;
            case 0x5: taken = (static_cast<int64_t>(rs1v) >= static_cast<int64_t>(rs2v)); break;
            case 0x6: taken = (rs1v < rs2v); break;
            case 0x7: taken = (rs1v >= rs2v); break;
            default:
                raise_illegal(curr_pc);
                return false;
            }
            if (taken) {
                const uint64_t target = curr_pc + imm_b;
                if ((target & 0x3) != 0) {
                    raise_trap(CAUSE_FETCH_MISALIGNED, curr_pc, target);
                    return false;
                }
                pc = target;
            }
            return true;
        }

        case 0x37: set_reg(rd, imm_u); return true;
        case 0x17: set_reg(rd, curr_pc + imm_u); return true;

        case 0x6F: {
            const uint64_t target = curr_pc + imm_j;
            if ((target & 0x3) != 0) {
                raise_trap(CAUSE_FETCH_MISALIGNED, curr_pc, target);
                return false;
            }
            set_reg(rd, pc);
            pc = target;
            return true;
        }

        case 0x67: {
            if (funct3 != 0x0) {
                raise_illegal(curr_pc);
                return false;
            }
            const uint64_t target = (rs1v + imm_i) & ~1ULL;
            if ((target & 0x3) != 0) {
                raise_trap(CAUSE_FETCH_MISALIGNED, curr_pc, target);
                return false;
            }
            const uint64_t ret = pc;
            pc = target;
            set_reg(rd, ret);
            return true;
        }

        case 0x0F:
            return true; // fence/fence.i no-op in the functional model

        case 0x73:
            return execute_system(curr_pc, instr, rd, rs1, funct3);

        case 0x2F:
            return execute_atomic(curr_pc, instr, rd, rs1, rs2, funct3);

        default:
            raise_illegal(curr_pc);
            return false;
        }
    }

    bool step() {
        if (scheduled_irq_armed &&
            ((scheduled_irq_use_pc && (pc == scheduled_irq_pc)) ||
             (!scheduled_irq_use_pc && (cycle >= scheduled_irq_cycle)))) {
            csr[CSR_MIP] |= scheduled_irq_mask;
            scheduled_irq_armed = false;
        }

        const uint64_t interrupt_cause = pending_interrupt_cause();
        if (interrupt_cause != 0) {
            take_interrupt(interrupt_cause);
            cycle++;
            regs[0] = 0;
            if (mem.tohost != 0) {
                running = false;
            }
            return false;
        }

        if ((pc & 0x3) != 0) {
            raise_trap(CAUSE_FETCH_MISALIGNED, pc, pc);
            cycle++;
            return false;
        }

        const uint64_t curr_pc = pc;
        uint64_t fetch_pc = pc;
        if (!translate_address(pc, current_priv, ACCESS_FETCH, 4, curr_pc, fetch_pc)) {
            cycle++;
            regs[0] = 0;
            return false;
        }
        const uint32_t instr = mem.read32(fetch_pc);
        pc += 4;
        suppress_instret_increment = false;
        const bool retired = execute(curr_pc, instr);
        cycle++;
        if (retired && !suppress_instret_increment) {
            instret++;
        }
        regs[0] = 0;
        if (mem.tohost != 0) {
            running = false;
        }
        return retired;
    }

    void run(bool trace = false) {
        while (running) {
            if (trace && cycle < 500) {
                const uint32_t instr = ((pc & 0x3) == 0) ? mem.read32(pc) : 0;
                std::cout << "[" << cycle << "] pc=0x" << std::hex << pc
                          << " instr=0x" << instr << std::dec << "\n";
            }
            step();
            if (cycle > 10000000) {
                throw std::runtime_error("Timeout @ pc=0x" + hex64(pc));
            }
        }
    }

    void dump_arch_state(std::ostream& os) const {
        os << "STATE kind=emu\n";
        os << std::hex << std::setfill('0');
        for (int i = 0; i < 32; i++) {
            os << "STATE reg x" << std::dec << i << "="
               << std::hex << std::setw(16) << regs[i] << "\n";
        }
        os << "STATE csr mstatus=" << std::setw(16) << read_csr(CSR_MSTATUS) << "\n";
        os << "STATE csr mtvec=" << std::setw(16) << read_csr(CSR_MTVEC) << "\n";
        os << "STATE csr mscratch=" << std::setw(16) << read_csr(CSR_MSCRATCH) << "\n";
        os << "STATE csr mepc=" << std::setw(16) << read_csr(CSR_MEPC) << "\n";
        os << "STATE csr mcause=" << std::setw(16) << read_csr(CSR_MCAUSE) << "\n";
        os << "STATE csr mtval=" << std::setw(16) << read_csr(CSR_MTVAL) << "\n";
        os << "STATE csr mie=" << std::setw(16) << read_csr(CSR_MIE) << "\n";
        os << "STATE csr mip=" << std::setw(16) << read_csr(CSR_MIP) << "\n";
        os << "STATE csr medeleg=" << std::setw(16) << read_csr(CSR_MEDELEG) << "\n";
        os << "STATE csr mideleg=" << std::setw(16) << read_csr(CSR_MIDELEG) << "\n";
        os << "STATE csr sstatus=" << std::setw(16) << read_csr(CSR_SSTATUS) << "\n";
        os << "STATE csr stvec=" << std::setw(16) << read_csr(CSR_STVEC) << "\n";
        os << "STATE csr sscratch=" << std::setw(16) << read_csr(CSR_SSCRATCH) << "\n";
        os << "STATE csr sepc=" << std::setw(16) << read_csr(CSR_SEPC) << "\n";
        os << "STATE csr scause=" << std::setw(16) << read_csr(CSR_SCAUSE) << "\n";
        os << "STATE csr stval=" << std::setw(16) << read_csr(CSR_STVAL) << "\n";
        os << "STATE csr sie=" << std::setw(16) << read_csr(CSR_SIE) << "\n";
        os << "STATE csr sip=" << std::setw(16) << read_csr(CSR_SIP) << "\n";
        os << "STATE csr pmpcfg0=" << std::setw(16) << read_csr(CSR_PMPCFG0) << "\n";
        os << "STATE csr pmpaddr0=" << std::setw(16) << read_csr(CSR_PMPADDR0) << "\n";
        os << "STATE csr ares_status=" << std::setw(16) << 0ULL << "\n";
        os << "STATE csr ares_fault_count=" << std::setw(16) << 0ULL << "\n";
        os << "STATE csr ares_fault_info=" << std::setw(16) << 0ULL << "\n";
        os << "STATE csr priv=" << std::setw(16) << static_cast<uint64_t>(current_priv) << "\n";
        os << "STATE tohost=" << std::setw(16) << mem.tohost << "\n";
        os << "STATE cycle=" << std::setw(16) << cycle << "\n";
        os << "STATE end\n";
        os << std::dec << std::setfill(' ');
    }

    void dump_regs() const {
        static const char* names[] = {
            "zero","ra","sp","gp","tp","t0","t1","t2",
            "s0","s1","a0","a1","a2","a3","a4","a5",
            "a6","a7","s2","s3","s4","s5","s6","s7",
            "s8","s9","s10","s11","t3","t4","t5","t6"
        };
        std::cout << "=== ARES Register Dump ===\n";
        for (int i = 0; i < 32; i++) {
            std::cout << std::setw(4) << names[i]
                      << " (x" << std::setw(2) << std::setfill('0') << i << ") = "
                      << std::setfill(' ') << std::setw(20) << static_cast<int64_t>(regs[i])
                      << "  (0x" << std::hex << std::setw(16)
                      << std::setfill('0') << regs[i] << ")\n"
                      << std::dec << std::setfill(' ');
        }
        std::cout << "  pc = 0x" << std::hex << pc << std::dec << "\n";
    }
};
