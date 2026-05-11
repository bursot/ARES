#include <iostream>
#include <fstream>
#include <vector>
#include "cpu.hpp"
#include "elf_loader.hpp"

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: ./ares [--trace] [--state-dump] [--irq-kind msip|mtip|meip] [--irq-cycle N] <binary-or-elf>\n";
        return 1;
    }

    bool trace = false;
    bool state_dump = false;
    uint64_t irq_cycle = 0;
    uint64_t irq_mask = 0;
    uint64_t irq_pc = 0;
    bool has_irq_pc = false;
    std::string path;
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "--trace") {
            trace = true;
            continue;
        }
        if (arg == "--state-dump") {
            state_dump = true;
            continue;
        }
        if (arg == "--irq-kind") {
            if (i + 1 >= argc) {
                std::cerr << "missing value for --irq-kind\n";
                return 1;
            }
            std::string kind = argv[++i];
            if (kind == "msip") irq_mask = CPU::MIP_MSIP;
            else if (kind == "mtip") irq_mask = CPU::MIP_MTIP;
            else if (kind == "meip") irq_mask = CPU::MIP_MEIP;
            else {
                std::cerr << "unsupported --irq-kind: " << kind << "\n";
                return 1;
            }
            continue;
        }
        if (arg == "--irq-cycle") {
            if (i + 1 >= argc) {
                std::cerr << "missing value for --irq-cycle\n";
                return 1;
            }
            irq_cycle = std::stoull(argv[++i]);
            continue;
        }
        if (arg == "--irq-pc") {
            if (i + 1 >= argc) {
                std::cerr << "missing value for --irq-pc\n";
                return 1;
            }
            irq_pc = std::stoull(argv[++i], nullptr, 0);
            has_irq_pc = true;
            continue;
        }
        if (!path.empty()) {
            std::cerr << "Usage: ./ares [--trace] [--state-dump] [--irq-kind msip|mtip|meip] [--irq-cycle N] <binary-or-elf>\n";
            return 1;
        }
        path = arg;
    }

    if (path.empty()) {
        std::cerr << "Usage: ./ares [--trace] [--state-dump] [--irq-kind msip|mtip|meip] [--irq-cycle N] <binary-or-elf>\n";
        return 1;
    }

    std::ifstream file(path, std::ios::binary);
    if (!file) {
        std::cerr << "Failed to open file: " << path << "\n";
        return 1;
    }

    CPU cpu;
    if (irq_mask != 0) {
        if (has_irq_pc) cpu.schedule_interrupt_once_at_pc(irq_pc, irq_mask);
        else            cpu.schedule_interrupt_once(irq_cycle, irq_mask);
    }

    try {
        uint8_t magic[4] = {};
        file.read(reinterpret_cast<char*>(magic), sizeof(magic));
        file.close();
        if (magic[0] == 0x7f && magic[1] == 'E' && magic[2] == 'L' && magic[3] == 'F') {
            cpu.pc = load_elf(path, cpu.mem);
        } else {
            std::ifstream raw_file(path, std::ios::binary);
            auto program = std::vector<uint8_t>(
                std::istreambuf_iterator<char>(raw_file),
                std::istreambuf_iterator<char>{}
            );
            cpu.mem.load(program.data(), program.size());
        }
        cpu.run(trace);
    } catch (const std::exception& e) {
        std::cerr << "Exception: " << e.what() << "\n";
        cpu.dump_regs();
        return 1;
    }

    if (state_dump) {
        cpu.dump_arch_state(std::cout);
    } else {
        cpu.dump_regs();
    }
    return 0;
}
