#!/usr/bin/env python3
"""Run every lazyc test end-to-end and verify exit code + stdout.

This uses nasm (real Intel-syntax assembler) and ld directly. It assumes
the compiler binary is at ./lazyc and runtime/runtime.o has been built.

Usage: python3 tools/run_all.py
"""
import sys, os, subprocess, pathlib, ast as pyast, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
TESTS = ROOT / 'tests'
MYLANG = ROOT / 'lazyc'
RUNTIME_O = ROOT / 'runtime' / 'runtime.o'

def need(p, what):
    if not p.exists():
        print(f"missing {what}: {p}")
        print("  did you run `make` first?")
        sys.exit(1)

need(MYLANG, "compiler binary (./lazyc)")
need(RUNTIME_O, "runtime object (runtime/runtime.o)")

def ml_compile(src_path):
    r = subprocess.run([str(MYLANG), str(src_path)],
                       capture_output=True, text=True)
    return r.returncode, r.stderr

def assemble_link_run(name):
    asm_path = TESTS / f"{name}.ml.asm"
    obj_path = pathlib.Path(tempfile.gettempdir()) / f"mlt_{name}.o"
    bin_path = pathlib.Path(tempfile.gettempdir()) / f"mlt_{name}"

    r = subprocess.run(['nasm', '-f', 'elf64', str(asm_path), '-o', str(obj_path)],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None, None, "assemble failed: " + r.stderr

    r = subprocess.run(['ld', str(obj_path), str(RUNTIME_O), '-o', str(bin_path)],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None, None, "link failed: " + r.stderr

    r = subprocess.run([str(bin_path)], capture_output=True, text=True, timeout=10)
    return r.returncode, r.stdout, None

# Read manifest.
expected_lines = (TESTS / 'expected.txt').read_text().splitlines()
expected_passing = {}
expected_failing = []

for line in expected_lines:
    parts = line.split(maxsplit=2)
    if not parts: continue
    if parts[0] == 'PASS':
        name = parts[1]
        rest = parts[2].split(maxsplit=1)
        exit_code = int(rest[0])
        stdout = pyast.literal_eval(rest[1]) if len(rest) > 1 else ''
        expected_passing[name] = (exit_code, stdout)
    elif parts[0] == 'FAIL':
        expected_failing.append(parts[1])

ok = bad = 0
failures = []

print("=== passing tests (verifying compile + assemble + link + run) ===")
for name, (exp_exit, exp_stdout) in sorted(expected_passing.items()):
    src = TESTS / f"{name}.ml"
    if not src.exists():
        failures.append((name, "missing .ml source"))
        bad += 1
        continue
    rc, err = ml_compile(src)
    if rc != 0:
        failures.append((name, f"compile: {err.strip()}"))
        bad += 1
        continue
    rc, out, err = assemble_link_run(name)
    if err is not None:
        failures.append((name, err))
        bad += 1
        continue
    problems = []
    if rc != exp_exit:
        problems.append(f"exit got={rc} want={exp_exit}")
    if out != exp_stdout:
        problems.append(f"stdout got={repr(out)} want={repr(exp_stdout)}")
    if problems:
        failures.append((name, " | ".join(problems)))
        bad += 1
    else:
        ok += 1

print(f"  {ok} ok, {bad} fail")

print("\n=== failing tests (expect lazyc to reject) ===")
ok2 = bad2 = 0
for name in sorted(expected_failing):
    src = TESTS / f"{name}.ml"
    if not src.exists():
        failures.append((name, "missing .ml source"))
        bad2 += 1
        continue
    rc, err = ml_compile(src)
    if rc != 0:
        if err and ('error' in err.lower() or 'expected' in err.lower()):
            ok2 += 1
        else:
            failures.append((name, f"rejected but odd output: {err.strip()}"))
            bad2 += 1
    else:
        failures.append((name, "expected rejection but compiler accepted"))
        bad2 += 1
print(f"  {ok2} ok, {bad2} fail")

if failures:
    print("\n=== failures ===")
    for name, why in failures:
        print(f"  {name}: {why}")

print(f"\nTOTAL: {ok+ok2} ok, {bad+bad2} fail")
sys.exit(0 if (bad+bad2) == 0 else 1)
