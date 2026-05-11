CXX      = clang++
CXXFLAGS = -std=c++20 -O2 -Wall -Wextra -Isrc

all: ares ares-test

ares: src/main.cpp src/cpu.hpp src/memory.hpp src/elf_loader.hpp
	$(CXX) $(CXXFLAGS) src/main.cpp -o ares

ares-test: src/test_runner.cpp src/cpu.hpp src/memory.hpp src/elf_loader.hpp
	$(CXX) $(CXXFLAGS) src/test_runner.cpp -o ares-test

clean:
	rm -f ares ares-test
