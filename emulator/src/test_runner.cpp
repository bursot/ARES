#include <iostream>
#include <vector>
#include <filesystem>
#include "cpu.hpp"
#include "elf_loader.hpp"

namespace fs = std::filesystem;

bool run_test(const std::string& path) {
    CPU cpu;
    try {
        cpu.pc = load_elf(path, cpu.mem);
    } catch (const std::exception& e) {
        std::cout << "FAIL (load): " << e.what() << "\n";
        return false;
    }

    try {
        cpu.run(false); // trace disabled
    } catch (const std::exception& e) {
        std::cout << "FAIL (exception): " << fs::path(path).filename().string()
                  << " — " << e.what()
                  << " @ pc=0x" << std::hex << cpu.pc << std::dec << "\n";
        return false;
    }

    bool passed = (cpu.mem.tohost == 1);
    std::cout << (passed ? "PASS" : "FAIL")
              << " [tohost=" << cpu.mem.tohost << "] "
              << fs::path(path).filename().string() << "\n";
    return passed;
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: ./ares-test <test.elf> [test2.elf ...]\n";
        return 1;
    }

    int passed = 0, failed = 0;
    for (int i = 1; i < argc; i++) {
        std::string path = argv[i];
        if (path.ends_with(".dump")) continue; // skip dump files
        if (run_test(path)) passed++;
        else failed++;
    }

    std::cout << "\n=== Results: "
              << passed << " passed, "
              << failed << " failed ===\n";
    return failed > 0 ? 1 : 0;
}
