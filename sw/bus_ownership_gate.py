#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Fresh standalone Verilator contract gate. No synthesis/hardware claim.

Windows: run with a Python interpreter; MSYS2 defaults to C:/msys64.
Build output and source/binary SHA-256 receipt stay in a fresh work directory.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--msys-root', default='C:/msys64')
    parser.add_argument('--work', default='../work/bus-ownership')
    parser.add_argument('--core', action='store_true', help='run real ucore integration harness')
    parser.add_argument('--compiler', choices=['gcc', 'clang'], default='gcc')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    top = 'tb_bus_ownership_core' if args.core else 'tb_bus_ownership'
    sources = ['hdl/rtl/v30_bus_ownership.sv', f'hdl/tb/{top}.sv']
    extra = []
    declared = list(sources) + ['sw/bus_ownership_gate.py']
    if args.core:
        ucore = root / 'hdl/rtl/ucore'
        sources += ['hdl/rtl/ucore/' + name for name in
                    ['v30u_ss_pkg.sv', 'v30_core.sv', 'v30u_biu.sv', 'v30u_ucrom.sv', 'v30u_eu.sv']]
        declared += [path.relative_to(root).as_posix() for path in ucore.iterdir()
                     if path.suffix in ('.sv', '.svh', '.hex')]
        extra = ['-Ihdl/rtl/ucore'] + ['-Wno-' + name for name in
                 ['UNUSEDSIGNAL', 'VARHIDDEN', 'TIMESCALEMOD', 'WIDTHEXPAND',
                  'BLKSEQ', 'DECLFILENAME', 'UNUSEDPARAM', 'MULTIDRIVEN',
                  'UNOPTFLAT', 'CASEINCOMPLETE', 'PROCASSINIT', 'PINCONNECTEMPTY']] + ['-DV30_BACKDOOR']
    work = (root / args.work).resolve()
    work.mkdir(parents=True, exist_ok=True)
    build = Path(tempfile.mkdtemp(prefix='bus_ownership_', dir=work))
    digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    inputs = {name: digest(root / name) for name in declared}
    command = ['verilator', '--binary', '--timing', '--assert', '-Wall',
               '--compiler', args.compiler,
               '--top-module', top, '--Mdir', build.as_posix(), *extra, *sources]
    executable = build / ('V' + top + ('.exe' if os.name == 'nt' else ''))
    if args.compiler == 'clang':
        makeflags = ("CXX=clang++ LINK='env -u LINK clang++' CFG_LDLIBS_THREADS=-pthread"
                     if os.name == 'nt' else 'CXX=clang++ LINK=clang++')
        command += ['-CFLAGS', '-std=c++20', '-MAKEFLAGS', makeflags]
    if os.name == 'nt':
        # MSYS translates /c/... for native tools and supplies compiler/runtime.
        windows_root = root.as_posix()
        msys_path = '/' + windows_root[0].lower() + windows_root[2:]
        compiler_path = '/clang64/bin:' if args.compiler == 'clang' else ''
        script = ('export PATH=' + compiler_path + '/ucrt64/bin:/usr/bin:$PATH; '
                  + 'verilator --version; ' + ('clang++' if args.compiler == 'clang' else 'g++')
                  + ' --version; cd ' + shlex.quote(msys_path)
                  + ' && ' + shlex.join(command) + ' && '
                  + shlex.quote(executable.as_posix()))
        invocation = [str(Path(args.msys_root) / 'usr/bin/bash.exe'), '-lc', script]
    else:
        invocation = command
    result = subprocess.run(invocation, cwd=root, text=True, capture_output=True, timeout=1800)
    (build / 'gate.log').write_text(result.stdout + result.stderr, encoding='utf-8')
    print(result.stdout, end='')
    print(result.stderr, end='')
    if result.returncode:
        raise SystemExit(result.returncode)
    if os.name != 'nt':
        simulation = subprocess.run([str(executable)], cwd=root, text=True,
                                    capture_output=True, timeout=120)
        versions = subprocess.run(['verilator', '--version'], text=True, capture_output=True)
        versions_compiler = subprocess.run(['clang++' if args.compiler == 'clang' else 'g++',
                                           '--version'], text=True, capture_output=True)
        with (build / 'gate.log').open('a', encoding='utf-8') as log:
            log.write(versions.stdout + versions_compiler.stdout + simulation.stdout + simulation.stderr)
        print(simulation.stdout + simulation.stderr, end='')
        if simulation.returncode:
            raise SystemExit(simulation.returncode)
    if inputs != {name: digest(root / name) for name in declared}:
        raise SystemExit('Source changed during build; no receipt issued')
    receipt = {'inputs': inputs, 'binary_sha256': digest(executable),
               'command': command, 'log_sha256': digest(build / 'gate.log'),
               'gate': top + ' contract simulation only'}
    receipt_path = build / 'receipt.json'
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    print(f'Receipt: {receipt_path}')


if __name__ == '__main__':
    main()
