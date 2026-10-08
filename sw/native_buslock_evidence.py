#!/usr/bin/env python3
"""Offline retained BUSLOCK pin custody and strict comparison; no hardware access."""
import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sys
import tempfile

SCHEMA = 'native-buslock-evidence-v1'
PROBES = ('v_lock', 'nop', 'addrr')
SOURCES = ('tf0f', 'iret-tf')
HEX64 = re.compile(r'[0-9a-f]{64}\Z')
WORD = re.compile(r'[0-9a-fA-F]{16}\Z')
STAMP = re.compile(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z\Z')
HISTORICAL = 'docs/notes/native_buslock_iret_derivation_manifest_2026-10-08.json'


class EvidenceError(ValueError):
    pass


def sha(data):
    return hashlib.sha256(data).hexdigest()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise EvidenceError('duplicate JSON key: ' + key)
        result[key] = value
    return result


def parse_json(data):
    try:
        return json.loads(data, object_pairs_hook=unique_object)
    except (ValueError, UnicodeError) as exc:
        raise EvidenceError('invalid JSON: ' + str(exc)) from exc


def repo_path(root, name):
    if not isinstance(name, str) or '\\' in name:
        raise EvidenceError('input path must be a relative POSIX path')
    path = PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts or ':' in name:
        raise EvidenceError('input path escapes repository: ' + name)
    resolved = (root / name).resolve()
    if not resolved.is_relative_to(root.resolve()):
        raise EvidenceError('input symlink escapes repository: ' + name)
    return resolved


def expected_cells():
    cells = []
    for source in SOURCES:
        for geometry in (('',) if source == 'tf0f' else ('I0', 'P1')):
            for probe in PROBES:
                leg = geometry + '_' + probe if geometry else probe
                for waits in range(4):
                    for align in range(4):
                        cells.append({'source': source, 'geometry': geometry,
                                      'probe': probe, 'waits': waits, 'align': align,
                                      'cell': f'{leg}_w{waits}_a{align}',
                                      'image_key': f'{leg}_a{align}',
                                      'raw': f'sw/testdata/{source}/board/{leg}_w{waits}.raw.json.gz'})
    return cells


def validate_manifest(manifest, source):
    if not isinstance(manifest, dict) or manifest.get('use_core') is not False:
        raise EvidenceError('socket source requires explicit boolean use_core=false')
    if type(manifest.get('div')) is not int or manifest['div'] != 8:
        raise EvidenceError('capture divider must be integer8')
    if manifest.get('tool') != source.replace('-', '_') + '_cell run':
        raise EvidenceError('ambiguous source tool')
    flash = manifest.get('flash')
    if not isinstance(flash, dict) or not isinstance(flash.get('tail'), dict):
        raise EvidenceError('malformed flash provenance')
    tail = flash['tail']
    for value in (manifest.get('ts'), tail.get('ts')):
        if not isinstance(value, str) or not STAMP.fullmatch(value):
            raise EvidenceError('missing/invalid source timestamp')
        try:
            datetime.fromisoformat(value.replace('Z', '+00:00'))
        except ValueError as exc:
            raise EvidenceError('invalid source timestamp') from exc
    if tail.get('verify') != 'OK' or not HEX64.fullmatch(str(tail.get('sha256', ''))):
        raise EvidenceError('missing verified flash provenance')
    if not tail.get('sof_path') or not tail.get('git_describe'):
        raise EvidenceError('incomplete recorded flash provenance')
    if not isinstance(manifest.get('images'), dict):
        raise EvidenceError('missing image inventory')


def table_index(table):
    if not isinstance(table, list):
        raise EvidenceError('capture table must be a list')
    result = {}
    for row in table:
        if not isinstance(row, dict) or not isinstance(row.get('cell'), str):
            raise EvidenceError('malformed capture table cell')
        if row['cell'] in result:
            raise EvidenceError('duplicate capture table cell: ' + row['cell'])
        result[row['cell']] = row
    return result


def decode_words(words):
    if not isinstance(words, list) or not words:
        raise EvidenceError('capture requires a nonempty word list')
    rows = []
    for index, word in enumerate(words):
        if not isinstance(word, str) or not WORD.fullmatch(word):
            raise EvidenceError(f'malformed 64-bit capture word at index{index}')
        value = int(word, 16)
        rows.append({'idx': index, 'lock_n': (value >> 50) & 1,
                     'reset': (value >> 55) & 1})
    return rows


def canonical_words(words):
    decode_words(words)
    return (''.join(f'{int(word, 16):016x}\n' for word in words)).encode('ascii')


def validate_cell(spec, words, table, manifest):
    if table.get('cell') != spec['cell']:
        raise EvidenceError('capture cell identity mismatch')
    for name in ('probe', 'waits', 'align'):
        if type(table.get(name)) is not type(spec[name]) or table[name] != spec[name]:
            raise EvidenceError('capture experimental axis mismatch: ' + name)
    if spec['geometry'] and table.get('geom') != spec['geometry']:
        raise EvidenceError('capture geometry mismatch')
    rows = decode_words(words)
    if type(table.get('n_words')) is not int or len(rows) != table['n_words']:
        raise EvidenceError('capture word count mismatch')
    if type(table.get('ncap')) is not int or len(rows) != table['ncap']:
        raise EvidenceError('capture requested length mismatch')
    if sha(canonical_words(words)) != table.get('sha256'):
        raise EvidenceError('canonical word-stream SHA-256 disagreement')
    image = manifest['images'].get(spec['image_key'])
    if image is None:
        raise EvidenceError('source manifest missing image: ' + spec['image_key'])
    if not isinstance(image, str) or not HEX64.fullmatch(image) or image != table.get('image_sha256'):
        raise EvidenceError('image SHA-256 disagreement')
    return rows


def validate_pin_rows(rows):
    if not isinstance(rows, list) or not rows:
        raise EvidenceError('pin comparison requires complete nonempty rows')
    for index, row in enumerate(rows):
        if not isinstance(row, dict) or type(row.get('idx')) is not int or row['idx'] != index:
            raise EvidenceError('missing/duplicate/shifted clock index at row' + str(index))
        if type(row.get('lock_n')) is not int or row['lock_n'] not in (0, 1):
            raise EvidenceError('missing/nonbinary lock_n at row' + str(index))


def compare_pin_rows(expected, actual):
    validate_pin_rows(expected)
    validate_pin_rows(actual)
    if len(expected) != len(actual):
        raise EvidenceError('pin row-count mismatch')
    return [{'idx': e['idx'], 'expected': e['lock_n'], 'actual': a['lock_n']}
            for e, a in zip(expected, actual) if e['lock_n'] != a['lock_n']]


def legacy_pin(row):
    if isinstance(row, list) and len(row) == 11:
        return None
    raise EvidenceError('only legacy11-column cycles are recognized as pin-unknown')


def low_spans(rows):
    spans = []
    start = None
    for row in rows:
        if row['lock_n'] == 0 and start is None:
            start = row['idx']
        elif row['lock_n'] == 1 and start is not None:
            spans.append([start, row['idx'] - 1])
            start = None
    if start is not None:
        spans.append([start, rows[-1]['idx']])
    return spans


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n', encoding='utf-8')


def write_rows(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w', encoding='utf-8', newline='\n') as output:
        for row in rows:
            output.write(json.dumps(row, sort_keys=True, separators=(',', ':')) + '\n')


def read_pin_rows(path):
    try:
        return [parse_json(line) for line in path.read_text(encoding='utf-8').splitlines()]
    except OSError as exc:
        raise EvidenceError(str(exc)) from exc


def verify_seal(root, inputs, variants=None):
    if not isinstance(inputs, dict) or not inputs:
        raise EvidenceError('inventory requires sealed inputs')
    variants = {} if variants is None else variants
    if not isinstance(variants, dict) or not variants.keys() <= inputs.keys():
        raise EvidenceError('invalid checkout variant inventory')
    chosen = {}
    for name, digest in inputs.items():
        if not isinstance(digest, str) or not HEX64.fullmatch(digest):
            raise EvidenceError('malformed inventory hash: ' + name)
        allowed = [digest]
        if name in variants:
            variant = variants[name]
            if not isinstance(variant, dict):
                raise EvidenceError('malformed checkout variants')
            allowed = variant.get('allowed_sha256')
            expected = [variant.get('git_lf_sha256'), variant.get('exact_lf_to_crlf_sha256')]
            if (not isinstance(allowed, list) or len(allowed) != 2 or allowed != expected or
                    any(not isinstance(h, str) or not HEX64.fullmatch(h) for h in allowed) or
                    digest not in allowed or name.endswith('.gz')):
                raise EvidenceError('checkout identities must be two presealed exact text hashes')
        actual = sha(repo_path(root, name).read_bytes())
        if actual not in allowed:
            raise EvidenceError('sealed input SHA-256 disagreement: ' + name)
        chosen[name] = actual
    return chosen


def validate_inventory(inventory, specs):
    if not isinstance(inventory, dict) or inventory.get('schema') != 'native-buslock-evidence-inventory-v1':
        raise EvidenceError('malformed inventory schema')
    if type(inventory.get('population')) is not int or inventory['population'] != 144:
        raise EvidenceError('inventory population must be exactly144')
    rows = inventory.get('cells')
    if not isinstance(rows, list) or len(rows) != 144:
        raise EvidenceError('inventory cell count must be exactly144')
    cells = {}
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get('source'), str) or not isinstance(row.get('cell'), str):
            raise EvidenceError('malformed inventory cell')
        key = (row['source'], row['cell'])
        if key in cells:
            raise EvidenceError('duplicate inventory cell')
        cells[key] = row
    if set(cells) != {(s['source'], s['cell']) for s in specs}:
        raise EvidenceError('inventory differs from closed144-cell population')
    for spec in specs:
        row = cells[(spec['source'], spec['cell'])]
        for field in ('probe', 'waits', 'align'):
            if type(row.get(field)) is not type(spec[field]) or row[field] != spec[field]:
                raise EvidenceError('inventory experimental axis mismatch')
        if row.get('raw_path') != spec['raw']:
            raise EvidenceError('inventory raw path mismatch')
        original = HISTORICAL if spec['source'] == 'iret-tf' and spec['probe'] != 'v_lock' else f"sw/testdata/{spec['source']}/board/manifest.json"
        if row.get('image_manifest') != original:
            raise EvidenceError('inventory acquisition source differs from preregistered leg map')
    return cells


def require_sealed_sources(inventory, specs):
    required = {s['raw'] for s in specs} | {HISTORICAL}
    required |= {f'sw/testdata/{source}/board/{file}' for source in SOURCES
                 for file in ('manifest.json', 'table.json', 'SHA256SUMS')}
    if not isinstance(inventory.get('inputs'), dict) or not required <= inventory['inputs'].keys():
        raise EvidenceError('inventory does not seal every selected raw/manifest/table/index/historical input')


def validate_history(root, inventory, tables):
    history = inventory.get('historical_manifest')
    if not isinstance(history, dict) or history.get('commit') != '22151f64c7151120472c0be90591a18fa41964a1':
        raise EvidenceError('missing/conflicting historical acquisition commit')
    if (history.get('blob') != 'facf358a9e434a86e1839b4013e922a3fe2de117' or
            history.get('original_path') != 'sw/testdata/iret-tf/board/manifest.json' or
            history.get('derived_exact_copy_path') != HISTORICAL):
        raise EvidenceError('conflicting historical manifest identity')
    controls = {s['cell'] for s in expected_cells() if s['source'] == 'iret-tf' and s['probe'] != 'v_lock'}
    rows = history.get('cells')
    if not isinstance(rows, list) or len(rows) != 64 or {r.get('cell') for r in rows} != controls:
        raise EvidenceError('historical table population differs from fixed64controls')
    for row in rows:
        current = tables['iret-tf'][row['cell']]
        if (row.get('current_table_and_raw_match') is not True or
                row.get('historical_table_words_sha256') != current['sha256'] or
                row.get('word_count') != current['n_words'] or
                row.get('image_sha256') != current['image_sha256']):
            raise EvidenceError('historical/current table identity disagreement')
    shards = history.get('raw_files')
    expected = {s['raw'] for s in expected_cells() if s['source'] == 'iret-tf' and s['probe'] != 'v_lock'}
    if not isinstance(shards, list) or len(shards) != 16 or {s.get('path') for s in shards} != expected:
        raise EvidenceError('historical raw population differs from fixed16shards')
    for shard in shards:
        data = repo_path(root, shard['path']).read_bytes()
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode('ascii') + b'\0' + data).hexdigest()
        if (shard.get('byte_equal') is not True or shard.get('historical_blob') != blob or
                shard.get('historical_sha256') != sha(data) or shard.get('current_sha256') != sha(data)):
            raise EvidenceError('historical/current compressed raw identity disagreement')


def audit(root, inventory_path, attempt, latest_only=False):
    inventory = parse_json(inventory_path.read_text(encoding='utf-8'))
    specs = expected_cells()
    inventory_cells = validate_inventory(inventory, specs)
    require_sealed_sources(inventory, specs)
    chosen = verify_seal(root, inventory.get('inputs'), inventory.get('checkout_variants'))
    summary = {'schema': SCHEMA, 'status': 'FAIL', 'population': 144, 'cells': [], 'errors': [],
               'scope': 'retained socket pin evidence; native RTL implementation pending',
               'constant_high': 'prediction of current literal pin assignment; not executed RTL',
               'source_policy': 'latest-only refuted interpretation' if latest_only else 'registered original acquisition map',
               'chosen_source_identities': chosen}
    manifests, tables, raw_files = {}, {}, {}
    for source in SOURCES:
        directory = root / 'sw/testdata' / source / 'board'
        manifests[source] = parse_json((directory / 'manifest.json').read_text(encoding='utf-8'))
        tables[source] = table_index(parse_json((directory / 'table.json').read_text(encoding='utf-8')))
        try:
            validate_manifest(manifests[source], source)
        except EvidenceError as exc:
            summary['errors'].append({'source': source, 'error': str(exc)})
    historical = parse_json((root / HISTORICAL).read_text(encoding='utf-8'))
    validate_manifest(historical, 'iret-tf')
    validate_history(root, inventory, tables)
    mismatch_path = attempt / 'constant-high-mismatches.jsonl'
    with mismatch_path.open('w', encoding='utf-8', newline='\n') as mismatches:
        for spec in specs:
            cell = dict(spec)
            try:
                if spec['raw'] not in raw_files:
                    raw = parse_json(gzip.decompress((root / spec['raw']).read_bytes()).decode('utf-8'))
                    keys = {s['cell'] for s in specs if s['raw'] == spec['raw']}
                    if not isinstance(raw, dict) or set(raw) != keys:
                        raise EvidenceError('raw shard cell set mismatch')
                    raw_files[spec['raw']] = raw
                table = tables[spec['source']].get(spec['cell'])
                if table is None:
                    raise EvidenceError('missing capture table cell')
                sealed_cell = inventory_cells[(spec['source'], spec['cell'])]
                if (sealed_cell.get('n_words') != table['n_words'] or
                        sealed_cell.get('canonical_words_sha256') != table['sha256'] or
                        sealed_cell.get('image_sha256_table') != table['image_sha256']):
                    raise EvidenceError('sealed cell/table identity disagreement')
                manifest = manifests[spec['source']]
                historical_cell = spec['source'] == 'iret-tf' and spec['probe'] != 'v_lock'
                if historical_cell and not latest_only:
                    manifest = historical
                rows = validate_cell(spec, raw_files[spec['raw']][spec['cell']], table, manifest)
                output = f"rows/{spec['source']}/{spec['cell']}.jsonl"
                write_rows(attempt / output, rows)
                low = [r for r in rows if r['lock_n'] == 0]
                cell.update(status='PASS', row_file=output, rows=len(rows),
                            reset_rows=sum(r['reset'] for r in rows), low_rows=len(low),
                            reset_low_rows=sum(r['reset'] for r in low), low_spans=low_spans(rows),
                            word_sha256=table['sha256'], image_sha256=table['image_sha256'],
                            acquisition_manifest=sealed_cell['image_manifest'] if not latest_only else f"sw/testdata/{spec['source']}/board/manifest.json",
                            acquisition_timestamp=manifest['ts'])
                for row in low:
                    mismatches.write(json.dumps({'source': spec['source'], 'cell': spec['cell'],
                                                'idx': row['idx'], 'reset': row['reset'],
                                                'predicted_literal_lock_n': 1, 'observed_lock_n': 0},
                                               sort_keys=True, separators=(',', ':')) + '\n')
            except (EvidenceError, OSError, KeyError, EOFError) as exc:
                cell.update(status='FAIL', error=str(exc))
                summary['errors'].append({'source': spec['source'], 'cell': spec['cell'], 'error': str(exc)})
            summary['cells'].append(cell)
    if len(summary['cells']) == 144 and not summary['errors']:
        summary['status'] = 'PASS'
    summary['audited_cells'] = len(summary['cells'])
    summary['passed_cells'] = sum(c['status'] == 'PASS' for c in summary['cells'])
    summary['decoded_rows'] = sum(c.get('rows', 0) for c in summary['cells'])
    summary['constant_high_mismatches'] = sum(c.get('low_rows', 0) for c in summary['cells'])
    write_json(attempt / 'summary.json', summary)
    return summary


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, default=Path('../work/native-buslock-evidence/attempts'))
    commands = parser.add_subparsers(dest='command', required=True)
    audit_parser = commands.add_parser('audit', help='audit the preregistered144 retained cells')
    audit_parser.add_argument('--inventory', type=Path, default=Path('docs/notes/native_buslock_evidence_inventory_2026-10-08.json'))
    audit_parser.add_argument('--latest-only', action='store_true', help='retain refuted latest-manifest-only custody interpretation')
    comparator = commands.add_parser('compare', help='strict complete-index binary pin comparison')
    comparator.add_argument('expected', type=Path)
    comparator.add_argument('actual', type=Path)
    args = parser.parse_args(argv)
    root = Path(__file__).resolve().parents[1]
    work = (root / args.work).resolve()
    work.mkdir(parents=True, exist_ok=True)
    attempt = Path(tempfile.mkdtemp(prefix=args.command + '_', dir=work))
    inputs = {}
    status = 'FAIL'
    error = None
    try:
        names = ['sw/native_buslock_evidence.py', 'sw/test_native_buslock_evidence.py',
                 'docs/notes/native_buslock_evidence_prereg_2026-10-08.md',
                 'docs/notes/native_buslock_custody_addendum_2026-10-08.md',
                 'hdl/rtl/ucore/v30_core.sv', 'hdl/rtl/nec_bus.sv']
        for name in names:
            data = (root / name).read_bytes()
            inputs[name] = sha(data)
            if name.startswith(('sw/native_buslock', 'sw/test_native_buslock', 'docs/notes/')):
                snapshot = attempt / 'input-snapshot' / name
                snapshot.parent.mkdir(parents=True, exist_ok=True)
                snapshot.write_bytes(data)
        if args.command == 'audit':
            inventory_path = (root / args.inventory).resolve()
            inputs[str(inventory_path)] = sha(inventory_path.read_bytes())
            snapshot = attempt / 'input-snapshot' / 'inventory.json'
            snapshot.write_bytes(inventory_path.read_bytes())
            inventory = parse_json(inventory_path.read_text(encoding='utf-8'))
            if not isinstance(inventory, dict):
                raise EvidenceError('inventory must be a JSON object')
            for name in inventory.get('inputs', {}):
                inputs[name] = sha(repo_path(root, name).read_bytes())
            source = (root / 'hdl/rtl/ucore/v30_core.sv').read_text(encoding='utf-8')
            if not re.search(r"assign\s+BUSLOCK_N\s*=\s*1'b1\s*;", source):
                raise EvidenceError('current literal-high assignment absent; diagnostic is not applicable')
            summary = audit(root, inventory_path, attempt, args.latest_only)
            status = summary['status']
        else:
            for path in (args.expected, args.actual):
                inputs[str(path.resolve())] = sha(path.read_bytes())
            expected, actual = read_pin_rows(args.expected), read_pin_rows(args.actual)
            mismatches = compare_pin_rows(expected, actual)
            write_json(attempt / 'comparison.json', {'rows': len(expected), 'mismatches': mismatches,
                                                    'status': 'FAIL' if mismatches else 'PASS',
                                                    'scope': 'pin comparator; self-comparison is tool validation only'})
            status = 'FAIL' if mismatches else 'PASS'
        for name, digest in inputs.items():
            path = Path(name) if Path(name).is_absolute() else root / name
            if sha(path.read_bytes()) != digest:
                raise EvidenceError('input moved during audit/comparison: ' + name)
    except (EvidenceError, OSError, EOFError, KeyError, TypeError, AttributeError) as exc:
        error = str(exc)
        status = 'FAIL'
        write_json(attempt / 'failure.json', {'status': status, 'error': error})
    outputs = {p.relative_to(attempt).as_posix(): sha(p.read_bytes())
               for p in attempt.rglob('*') if p.is_file()}
    write_json(attempt / 'receipt.json', {'schema': SCHEMA, 'status': status, 'error': error,
                                       'command': [sys.executable, *sys.argv], 'inputs': inputs,
                                       'outputs': outputs, 'python': sys.version,
                                       'created_utc': datetime.now(timezone.utc).isoformat(),
                                       'scope': 'offline evidence/tool acceptance only; no native RTL match'})
    print(status + ' ' + str(attempt / 'receipt.json'))
    return 0 if status == 'PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
