ARES
====

ARES is a RISC-V processor project with:

- RTL implementation under `rtl/`
- C++ emulator under `emulator/`
- Formal verification harnesses under `formal/`
- Python tooling under `tools/`
- Small local test fixtures under `tests/`

Repository Layout
-----------------

```text
rtl/       Verilog core, pipeline stages, and testbench
emulator/  C++ emulator and test runner
formal/    SymbiYosys property files and formal wrappers
tests/     Small binary fixtures used by local RTL tests
tools/     Regression, differential-test, smoke-test, and helper scripts
```

Prerequisites
-------------

Install the tools needed for the workflows you use:

- C++20 compiler, for example `clang++`
- Python 3
- Icarus Verilog and/or Verilator
- SymbiYosys, Yosys, and Boolector for formal checks
- Optional: Spike and the RISC-V GNU toolchain for differential tests

Some scripts expect a local `riscv-tests/` checkout at the repository root. It is intentionally ignored by Git because it is third-party source plus generated binaries.

Quick Start
-----------

Build the emulator:

```sh
make -C emulator
```

Run emulator tests against local `riscv-tests` artifacts:

```sh
python3 tools/run_emulator_tests.py
```

Run RTL tests against the checked-in small binary fixtures:

```sh
python3 tools/run_rtl_tests.py
```

Run formal checks:

```sh
python3 tools/run_formal_checks.py
```

Clean generated files:

```sh
make -C emulator clean
rm -rf obj_dir rtl/obj_dir* rtl/ares_sim* rtl/ares_vvp_* formal/*/
rm -f ares_sim rtl/test_sim rtl/*.vcd rtl/*.log rtl/program.hex rtl/results*.txt
```
