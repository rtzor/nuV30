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
import re
from pathlib import Path
import shlex
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--msys-root', default='C:/msys64')
    parser.add_argument('--work', default='../work/bus-ownership')
    gate_choice = parser.add_mutually_exclusive_group()
    gate_choice.add_argument('--core', action='store_true', help='run real ucore integration harness')
    gate_choice.add_argument('--native-guard', action='store_true', help='run opt-in native-state exclusion guard harness')
    gate_choice.add_argument('--rqak', action='store_true', help='run standalone RQAK pulse frontend contract harness')
    gate_choice.add_argument('--rqak-core', action='store_true', help='run actual ucore and RQAK pulse frontend chain')
    gate_choice.add_argument('--biu-yield', action='store_true', help='experimental demux BIU-level yield contract')
    gate_choice.add_argument('--rqak-biu-yield', action='store_true', help='actual pulse frontend plus live-EU BIU yield chain')
    gate_choice.add_argument('--rqak-mux-yield', action='store_true', help='experimental multiplexed live-EU pulse/yield chain')
    parser.add_argument('--compiler', choices=['gcc', 'clang'], default='gcc')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    top = ('tb_rqak_mux_yield' if args.rqak_mux_yield else 'tb_rqak_biu_yield' if args.rqak_biu_yield else 'tb_biu_yield' if args.biu_yield else 'tb_rqak_core' if args.rqak_core else 'tb_rqak_frontend' if args.rqak else 'tb_bus_exclusion' if args.native_guard else
           'tb_bus_ownership_core' if args.core else 'tb_bus_ownership')
    sources = ['hdl/rtl/v30_bus_ownership.sv', f'hdl/tb/{top}.sv']
    if args.rqak or args.rqak_core or args.rqak_biu_yield or args.rqak_mux_yield:
        sources += ['hdl/rtl/v30_rqak_frontend.sv']
    extra = []
    declared = list(sources) + ['sw/bus_ownership_gate.py']
    if args.core or args.native_guard or args.rqak_core or args.biu_yield or args.rqak_biu_yield or args.rqak_mux_yield:
        ucore = root / 'hdl/rtl/ucore'
        sources += ['hdl/rtl/ucore/' + name for name in
                    ['v30u_ss_pkg.sv', 'v30_core.sv', 'v30u_biu.sv', 'v30u_ucrom.sv', 'v30u_eu.sv']]
        declared += [path.relative_to(root).as_posix() for path in ucore.iterdir()
                     if path.suffix in ('.sv', '.svh', '.hex')]
        extra = ['-Ihdl/rtl/ucore'] + ['-Wno-' + name for name in
                 ['UNUSEDSIGNAL', 'VARHIDDEN', 'TIMESCALEMOD', 'WIDTHEXPAND',
                  'BLKSEQ', 'DECLFILENAME', 'UNUSEDPARAM', 'MULTIDRIVEN',
                  'UNOPTFLAT', 'CASEINCOMPLETE', 'PROCASSINIT', 'PINCONNECTEMPTY']] + ['-DV30_BACKDOOR']
        if args.native_guard or args.rqak_core or args.biu_yield or args.rqak_biu_yield or args.rqak_mux_yield:
            extra += ['-DV30_BUS_OWNERSHIP']
        if args.biu_yield or args.rqak_biu_yield or args.rqak_mux_yield:
            extra += ['-DV30_BIU_YIELD']
        if args.rqak_mux_yield:
            extra += ['-DV30_MUXED_AD', '-DV30_MUXED_YIELD']
    if args.rqak_mux_yield:
        declared += ['hdl/tb/tb_mux_yield_handover.sv']
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
        if args.rqak_mux_yield:
            makeflags += ' OPT_FAST=-O0 OPT_SLOW=-O0'
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
    if args.native_guard:
        # Same harness must reject the opt-in pin when the macro is absent.
        probe = ['verilator', '--lint-only', '--timing', '--assert', '-Wall',
                 '--top-module', top,
                 *[option for option in extra if option != '-DV30_BUS_OWNERSHIP'],
                 *sources]
        if os.name == 'nt':
            probe_script = ('export PATH=' + compiler_path + '/ucrt64/bin:/usr/bin:$PATH; cd '
                            + shlex.quote(msys_path) + ' && ' + shlex.join(probe))
            probe_invocation = [str(Path(args.msys_root) / 'usr/bin/bash.exe'), '-lc', probe_script]
        else:
            probe_invocation = probe
        probe_result = subprocess.run(probe_invocation, cwd=root, text=True,
                                      capture_output=True, timeout=120)
        probe_log = probe_result.stdout + probe_result.stderr
        (build / 'default-port-probe.log').write_text(probe_log, encoding='utf-8')
        if (probe_result.returncode == 0 or 'PINNOTFOUND' not in probe_log or
                'BUS_EXCLUDE' not in probe_log):
            raise SystemExit('Default port absence control failed; see default-port-probe.log')
        with (build / 'gate.log').open('a', encoding='utf-8') as log:
            log.write('\nExpected default-port rejection:\n' + probe_log)
        print('PASS BUS_EXCLUDE absent without V30_BUS_OWNERSHIP')
    if args.biu_yield:
        for argument, marker in [('bad_owned_mode', 'owned mode transition is unsupported'),
                                 ('bad_ss_arbitration', 'SS mutation during arbitration')]:
            probe = [str(executable), '+' + argument]
            if os.name == 'nt':
                script = ('export PATH=' + compiler_path + '/ucrt64/bin:/usr/bin:$PATH; cd '
                          + shlex.quote(msys_path) + ' && ' + shlex.join(probe))
                invocation = [str(Path(args.msys_root) / 'usr/bin/bash.exe'), '-lc', script]
            else:
                invocation = probe
            control = subprocess.run(invocation, cwd=root, text=True, capture_output=True, timeout=120)
            output = control.stdout + control.stderr
            (build / (argument + '.log')).write_text(output, encoding='utf-8')
            if control.returncode == 0 or marker not in output:
                raise SystemExit('Runtime diagnostic failed: ' + argument)
            with (build / 'gate.log').open('a', encoding='utf-8') as log:
                log.write('\nExpected diagnostic ' + argument + ':\n' + output)
            print('PASS diagnosed ' + argument)
    if args.biu_yield:
        controls = [
            ('default-yield-port', [x for x in extra if x != '-DV30_BIU_YIELD'],
             'YIELD_READY'),
            ('missing-yield-guard', [x for x in extra if x != '-DV30_BUS_OWNERSHIP'],
             'V30_BIU_YIELD_REQUIRES_V30_BUS_OWNERSHIP'),
            ('unsupported-yield-mux', extra + ['-DV30_MUXED_AD'],
             'V30_BIU_YIELD_REJECTS_V30_MUXED_AD'),
        ]
        for label, options, marker in controls:
            probe_sources = sources if label=='default-yield-port' else [x for x in sources if x.startswith('hdl/rtl/ucore/')]
            probe_top = top if label=='default-yield-port' else 'v30_core'
            probe = ['verilator', '--lint-only', '--timing', '--assert', '-Wall',
                     '--top-module', probe_top, *options, *probe_sources]
            if os.name == 'nt':
                script = ('export PATH=' + compiler_path + '/ucrt64/bin:/usr/bin:$PATH; cd '
                          + shlex.quote(msys_path) + ' && ' + shlex.join(probe))
                invocation = [str(Path(args.msys_root) / 'usr/bin/bash.exe'), '-lc', script]
            else:
                invocation = probe
            control = subprocess.run(invocation, cwd=root, text=True, capture_output=True, timeout=120)
            output = control.stdout + control.stderr
            (build / (label + '.log')).write_text(output, encoding='utf-8')
            if control.returncode == 0 or marker not in output:
                raise SystemExit('Negative configuration probe failed: ' + label)
            with (build / 'gate.log').open('a', encoding='utf-8') as log:
                log.write('\nExpected rejection ' + label + ':\n' + output)
            print('PASS rejected ' + label)
    if args.biu_yield:
        lint_sets = {}
        for enabled in (False, True):
            options = [x for x in extra if x != '-Wno-UNOPTFLAT' and
                       (enabled or x != '-DV30_BIU_YIELD')]
            label = 'yield-on-unoptflat' if enabled else 'yield-off-unoptflat'
            probe = ['verilator', '--lint-only', '--timing', '--assert', '-Wall', '-Wno-fatal',
                     '--report-unoptflat', '--Mdir', (build / label).as_posix(),
                     '--top-module', 'v30_core', *options,
                     *[x for x in sources if x.startswith('hdl/rtl/ucore/')]]
            if os.name == 'nt':
                script = ('export PATH=' + compiler_path + '/ucrt64/bin:/usr/bin:$PATH; cd '
                          + shlex.quote(msys_path) + ' && ' + shlex.join(probe))
                invocation = [str(Path(args.msys_root) / 'usr/bin/bash.exe'), '-lc', script]
            else:
                invocation = probe
            control = subprocess.run(invocation, cwd=root, text=True, capture_output=True, timeout=120)
            output = control.stdout + control.stderr
            label = 'yield-on-unoptflat' if enabled else 'yield-off-unoptflat'
            (build / (label + '.log')).write_text(output, encoding='utf-8')
            with (build / 'gate.log').open('a', encoding='utf-8') as log:
                log.write('\nUNOPTFLAT unsuppressed control ' + label + ':\n' + output)
            if control.returncode:
                raise SystemExit('Core lint failed: ' + label)
            lint_sets[enabled] = set(re.findall(r"%Warning-UNOPTFLAT:[^\n]*logic: '([^']+)'", output))
        if lint_sets[True] - lint_sets[False]:
            raise SystemExit('New opt-in combinational feedback: ' + str(lint_sets[True] - lint_sets[False]))
        print('PASS unsuppressed UNOPTFLAT comparison OFF=' + str(len(lint_sets[False])) +
              ' ON=' + str(len(lint_sets[True])))
    if args.biu_yield:
        label = 'yield-integration-unoptflat'
        options = [x for x in extra if x != '-Wno-UNOPTFLAT']
        probe = ['verilator', '--lint-only', '--timing', '--assert', '-Wall', '-Wno-fatal',
                 '--report-unoptflat', '--Mdir', (build / label).as_posix(),
                 '--top-module', top, *options, *sources]
        if os.name == 'nt':
            script = ('export PATH=' + compiler_path + '/ucrt64/bin:/usr/bin:$PATH; cd '
                      + shlex.quote(msys_path) + ' && ' + shlex.join(probe))
            invocation = [str(Path(args.msys_root) / 'usr/bin/bash.exe'), '-lc', script]
        else:
            invocation = probe
        control = subprocess.run(invocation, cwd=root, text=True, capture_output=True, timeout=120)
        output = control.stdout + control.stderr
        (build / (label + '.log')).write_text(output, encoding='utf-8')
        with (build / 'gate.log').open('a', encoding='utf-8') as log:
            log.write('\nIntegration UNOPTFLAT unsuppressed paths/SCC review:\n' + output)
        if control.returncode:
            raise SystemExit('Integration lint failed: ' + label)
        print('PASS integration lint; unsuppressed paths/SCC artifacts retained for review')
    if args.rqak_biu_yield:
        label = 'rqak-biu-yield-unoptflat'
        options = [x for x in extra if x != '-Wno-UNOPTFLAT']
        probe = ['verilator', '--lint-only', '--timing', '--assert', '-Wall', '-Wno-fatal',
                 '--report-unoptflat', '--Mdir', (build / label).as_posix(),
                 '--top-module', top, *options, *sources]
        if os.name == 'nt':
            script = ('export PATH=' + compiler_path + '/ucrt64/bin:/usr/bin:$PATH; cd '
                      + shlex.quote(msys_path) + ' && ' + shlex.join(probe))
            invocation = [str(Path(args.msys_root) / 'usr/bin/bash.exe'), '-lc', script]
        else:
            invocation = probe
        control = subprocess.run(invocation, cwd=root, text=True, capture_output=True, timeout=120)
        output = control.stdout + control.stderr
        (build / (label + '.log')).write_text(output, encoding='utf-8')
        with (build / 'gate.log').open('a', encoding='utf-8') as log:
            log.write('\nFull-chain unsuppressed UNOPTFLAT lint:\n' + output)
        if control.returncode or '%Warning-UNOPTFLAT' in output:
            raise SystemExit('Full-chain UNOPTFLAT lint failed; see ' + label + '.log')
        print('PASS full-chain unsuppressed UNOPTFLAT warnings=0')
    additional_artifacts = {}
    additional_commands = {}
    if args.rqak_mux_yield:
        def invoke(label, argv, expected_marker=None, reject_unoptflat=False):
            if os.name == 'nt':
                script = ('export PATH=' + compiler_path + '/ucrt64/bin:/usr/bin:$PATH; cd '
                          + shlex.quote(msys_path) + ' && ' + shlex.join(argv))
                invocation = [str(Path(args.msys_root) / 'usr/bin/bash.exe'), '-lc', script]
            else:
                invocation = argv
            result = subprocess.run(invocation, cwd=root, text=True, capture_output=True, timeout=1800)
            output = result.stdout + result.stderr
            path = build / (label + '.log')
            path.write_text(output, encoding='utf-8')
            additional_artifacts[path.relative_to(build).as_posix()] = digest(path)
            additional_commands[label] = argv
            with (build / 'gate.log').open('a', encoding='utf-8') as log:
                log.write('\nMux yield control ' + label + ':\n' + output)
            if expected_marker:
                if result.returncode == 0 or expected_marker not in output:
                    raise SystemExit('Expected mux rejection missing: ' + label)
            elif result.returncode or (reject_unoptflat and '%Warning-UNOPTFLAT' in output):
                raise SystemExit('Mux control failed: ' + label)
            print('PASS mux control ' + label)
        handover_dir = build / 'handover'
        handover_command = ['verilator', '--binary', '--timing', '--assert', '-Wall',
                            '--compiler', args.compiler, '--top-module', 'tb_mux_yield_handover',
                            '--Mdir', handover_dir.as_posix(), '-DV30_MUXED_YIELD',
                            '-DV30_MUXED_AD', '-DV30_BIU_YIELD', '-DV30_BUS_OWNERSHIP',
                            'hdl/rtl/v30_bus_ownership.sv', 'hdl/tb/tb_mux_yield_handover.sv']
        if args.compiler == 'clang':
            handover_command += ['-CFLAGS', '-std=c++20', '-MAKEFLAGS', makeflags]
        invoke('disjoint-handover-build', handover_command)
        handover_executable = handover_dir / ('Vtb_mux_yield_handover' + ('.exe' if os.name == 'nt' else ''))
        invoke('disjoint-handover-run', [str(handover_executable)])
        additional_artifacts[handover_executable.relative_to(build).as_posix()] = digest(handover_executable)
        for label, marker in [('bad_ce_overlap', 'CONTRACT VIOLATED (C-a)'),
                              ('bad_no_half', 'REQUIREMENT VIOLATED (S-1)')]:
            invoke(label, [str(executable), '+' + label], expected_marker=marker)
        for label, omitted, marker in [
            ('missing-mux-yield-scheduler', '-DV30_BIU_YIELD', 'V30_MUXED_YIELD_REQUIRES_V30_BIU_YIELD'),
            ('missing-mux-yield-guard', '-DV30_BUS_OWNERSHIP', 'V30_MUXED_YIELD_REQUIRES_V30_BUS_OWNERSHIP'),
            ('missing-mux-yield-pins', '-DV30_MUXED_AD', 'V30_MUXED_YIELD_REQUIRES_V30_MUXED_AD'),
            ('missing-mux-yield-authorization', '-DV30_MUXED_YIELD', 'V30_BIU_YIELD_REJECTS_V30_MUXED_AD')]:
            options = [x for x in extra if x != omitted]
            invoke(label, ['verilator', '--lint-only', '--timing', '--assert', '-Wall',
                          # Exercise the BIU's named guard directly: an invalid core can
                          # report its missing conditional public port before elaborating guards.
                          '--top-module', 'v30u_biu', *options,
                          'hdl/rtl/ucore/v30u_ss_pkg.sv', 'hdl/rtl/ucore/v30u_biu.sv'], expected_marker=marker)
        for lint_top, label in [('v30_core', 'mux-core-unoptflat'), (top, 'mux-chain-unoptflat')]:
            options = [x for x in extra if x != '-Wno-UNOPTFLAT']
            selected = sources if lint_top == top else [x for x in sources if x.startswith('hdl/rtl/ucore/')]
            invoke(label, ['verilator', '--lint-only', '--timing', '--assert', '-Wall', '-Wno-fatal',
                          '--report-unoptflat', '--Mdir', (build / label).as_posix(),
                          '--top-module', lint_top, *options, *selected], reject_unoptflat=True)
            for report in (build / label).rglob('*'):
                if report.is_file():
                    additional_artifacts[report.relative_to(build).as_posix()] = digest(report)
        on_trace = build / 'inactive-on.trace'
        invoke('inactive-on-trace', [str(executable), '+trace_only=1', '+trace=' + on_trace.as_posix()])
        baseline_dir = build / 'baseline'
        baseline_command = [x for x in command if x not in ('-DV30_BUS_OWNERSHIP', '-DV30_BIU_YIELD', '-DV30_MUXED_YIELD')]
        baseline_command[baseline_command.index('--Mdir') + 1] = baseline_dir.as_posix()
        invoke('baseline-build', baseline_command)
        baseline_executable = baseline_dir / executable.name
        baseline_trace = build / 'baseline-off.trace'
        invoke('baseline-off-trace', [str(baseline_executable), '+trace_only=1', '+trace=' + baseline_trace.as_posix()])
        if on_trace.read_bytes() != baseline_trace.read_bytes():
            raise SystemExit('Mux inactive ON/baseline OFF full trace mismatch; traces retained')
        for output in [on_trace, baseline_trace, baseline_executable]:
            additional_artifacts[output.relative_to(build).as_posix()] = digest(output)
        print('PASS exact baseline OFF/inactive ON full trace rows=' + str(len(on_trace.read_bytes().splitlines())))
    if inputs != {name: digest(root / name) for name in declared}:
        raise SystemExit('Source changed during controls; no receipt issued')
    receipt = {'inputs': inputs, 'binary_sha256': digest(executable),
               'command': command, 'log_sha256': digest(build / 'gate.log'),
               'gate': top + ' contract simulation only'}
    if additional_artifacts:
        receipt['additional_artifacts'] = additional_artifacts
        receipt['additional_commands'] = additional_commands
    receipt_path = build / 'receipt.json'
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    print(f'Receipt: {receipt_path}')


if __name__ == '__main__':
    main()
