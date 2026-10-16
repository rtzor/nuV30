"""Balanced generated-C++ fatal/STOP pairing. No compiler or DUT invocation."""
from pathlib import Path
import ast
import json
import re


def check(value, message):
    if not value: raise AssertionError(message)


# Preserve offsets. Quotes/comments cannot introduce executable calls/braces.
LEX = re.compile(r'\s+|//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|'
                 r"'(?:\\.|[^'\\])*'|[A-Za-z_$][\w$]*|[0-9][\w.]*|[^\w\s]", re.S)


def lex(text):
    result = []; pos = 0
    for match in LEX.finditer(text):
        check(match.start() == pos, 'C++ lexical gap'); pos = match.end()
        value = match.group()
        if value.isspace() or value.startswith(('//', '/*')): continue
        check(not (value == '/' and text[match.start():match.start() + 2] == '/*'), 'unclosed block comment')
        check(value not in ('"', "'"), 'unclosed quote')
        result.append((value, match.start(), match.end()))
    check(pos == len(text), 'C++ lexical EOF')
    return result


def structure(tokens):
    stack = []; pairs = {}; blocks = {}; active_blocks = []
    enclosing = {}
    for i, (value, _, _) in enumerate(tokens):
        enclosing[i] = tuple(active_blocks)
        if value in ('(', '[', '{'):
            if value == '{':
                condition = ()
                if i and tokens[i - 1][0] == ')':
                    op = pairs.get(i - 1)
                    if op is not None and op and tokens[op - 1][0] == 'if':
                        condition = tuple(t[0] for t in tokens[op + 1:i - 1])
                blocks[i] = condition; active_blocks.append(i)
            stack.append((value, i))
        elif value in (')', ']', '}'):
            check(stack and stack[-1][0] == {')': '(', ']': '[', '}': '{'}[value], 'unbalanced generated C++')
            _, opening = stack.pop(); pairs[opening] = i; pairs[i] = opening
            if value == '}': check(active_blocks.pop() == opening, 'brace scope')
    check(not stack, 'C++ truncated structure')
    return pairs, blocks, enclosing


def arguments(tokens, start, pairs):
    check(tokens[start + 1][0] == '(', 'expected function call')
    end = pairs[start + 1]; args = []; begin = start + 2; i = begin
    while i < end:
        value = tokens[i][0]
        if value in ('(', '[', '{'): i = pairs[i] + 1; continue
        if value == ',': args.append(tokens[begin:i]); begin = i + 1
        i += 1
    args.append(tokens[begin:end])
    check(end + 1 < len(tokens) and tokens[end + 1][0] == ';', 'call is not a complete statement')
    return args, end + 2


def quoted(tokens):
    check(tokens and all(t[0].startswith('"') for t in tokens), 'expected literal string only')
    values = [ast.literal_eval(t[0]) for t in tokens]
    check(all(isinstance(x, str) for x in values), 'non-string literal')
    return ''.join(values)


def canonical(path):
    return str(path).replace('\\', '/').casefold()


def source_sites(source):
    sites = set()
    # This instrument handles the pinned single-literal $fatal form only.
    for match in re.finditer(r'\$fatal\s*\(\s*1\s*,\s*"([A-Z0-9_]+)"\s*\)', source):
        sites.add((match[1], source.count('\n', 0, match.start()) + 1))
    check(sites, 'no source fatal sites')
    return sites


def audit_texts(cpp_files, source_path, source_text, required_families):
    expected = source_sites(source_text)
    check(sorted(set(m for m, _ in expected)) == sorted(required_families), 'exact SOURCE fatal-family set')
    expected_path = canonical(source_path); basename = Path(str(source_path).replace('\\', '/')).name
    counts = {site: 0 for site in expected}; occurrences = []; owned_strings = set(); owned_stops = set()
    family_re = re.compile(r'\b(?:' + '|'.join(re.escape(x) for x in required_families) + r')\b')
    for cpp_path, text in sorted(cpp_files.items()):
        tokens = lex(text); pairs, blocks, enclosing = structure(tokens)
        for index, token in enumerate(tokens):
            if token[0] != 'VL_WRITEF_NX' or index + 1 >= len(tokens) or tokens[index + 1][0] != '(':
                continue
            args, after_write = arguments(tokens, index, pairs)
            # Nonfatal tracing uses the same writer and is outside this audit.
            if not args or not args[0] or not all(t[0].startswith('"') for t in args[0]): continue
            fmt = quoted(args[0]); markers = family_re.findall(fmt)
            if not markers: continue
            check(len(markers) == 1, 'ambiguous fatal markers in one writer')
            marker = markers[0]
            check(re.search(r'%+Fatal:\s*' + re.escape(basename) + r':(\d+):\s*Assertion failed[^\n]*:\s*' + re.escape(marker) + r'\b', fmt), 'marker is not an actual formatted fatal')
            diagnostic = re.search(re.escape(basename) + r':(\d+):\s*Assertion failed', fmt)
            line = int(diagnostic[1]); site = (marker, line)
            check(site in expected, 'fatal has no exact SOURCE site')
            check(after_write < len(tokens) and tokens[after_write][0] == 'VL_STOP_MT', 'STOP must be immediately next executable statement')
            stop_args, after_stop = arguments(tokens, after_write, pairs)
            check(len(stop_args) in (3, 4), 'STOP signature')
            check(canonical(quoted(stop_args[0])) == expected_path, 'STOP wrong source path')
            check(len(stop_args[1]) == 1 and re.fullmatch(r'\d+[uUlL]*', stop_args[1][0][0]), 'STOP line must be literal')
            stop_line = int(re.sub(r'[uUlL]+$', '', stop_args[1][0][0]))
            check(stop_line == line, 'STOP wrong source line')
            check(enclosing[index] == enclosing[after_write], 'fatal and STOP guard differ')
            guards = [(b, blocks[b]) for b in enclosing[index] if blocks[b]]
            check(guards and 'VL_UNLIKELY' in guards[-1][1], 'fatal not in emitted conditional guard')
            for string in args[0]: owned_strings.add((cpp_path, string[1]))
            owned_stops.add((cpp_path, after_write))
            counts[site] += 1
            occurrences.append({'cpp': cpp_path, 'cpp_offset': token[1], 'family': marker,
                                'source': str(source_path), 'line': line,
                                'writer_to_STOP_characters': tokens[after_write][1] - token[1],
                                'guard_offset': tokens[guards[-1][0]][1]})
        # Every executable string occurrence must be audited, not just one per family.
        for token in tokens:
            if token[0].startswith('"') and family_re.search(quoted([token])):
                check((cpp_path, token[1]) in owned_strings, 'unpaired marker string occurrence')
        for index, token in enumerate(tokens):
            if token[0] == 'VL_STOP_MT' and index + 1 < len(tokens) and tokens[index + 1][0] == '(':
                stop_args, _ = arguments(tokens, index, pairs)
                check(stop_args, 'empty STOP')
                if canonical(quoted(stop_args[0])) == expected_path:
                    check((cpp_path, index) in owned_stops, 'unpaired TB STOP occurrence')
    check(all(counts.values()), 'missing compiled SOURCE fatal site')
    return {'status': 'STRUCTURAL_CPP_FATAL_COVERAGE_PASS',
            'source_sites': len(expected), 'families': len(required_families),
            'occurrence_count': len(occurrences),
            'site_counts': [{'family': marker, 'line': line, 'compiled_occurrences': counts[marker, line]}
                            for marker, line in sorted(expected)],
            'occurrences': occurrences,
            'scope': 'Balanced literal writer call then immediate STOP in same emitted conditional guard, exact source path/line and all occurrences/sites. No character-distance waiver.'}


def audit_cpp(cpp_files, source_path, required_families):
    return audit_texts(cpp_files, str(source_path), Path(source_path).read_text(encoding='utf8'), required_families)


def pure_tests():
    source = 'if(x)$fatal(1,"TEST_FATAL");\n'
    path = 'C:/pure/tb.sv'; fmt = '"[%%Fatal: tb.sv:1: Assertion failed in %%m: TEST_FATAL\\n]"'
    longargs = ','.join('nested(%d,"VL_STOP_MT(fake)")' % i for i in range(160))
    writer = 'VL_WRITEF_NX(' + fmt + ',' + longargs + ');'
    stop = 'VL_STOP_MT("C:/pure/tb.sv",1,"",false);'
    good = 'void f(){if(VL_UNLIKELY(bad)){' + writer + stop + '}}'
    result = audit_texts({'pure.cpp': good}, path, source, ['TEST_FATAL'])
    check(result['occurrence_count'] == 1 and result['occurrences'][0]['writer_to_STOP_characters'] > 500, 'long positive')
    audit_texts({'a.cpp': good, 'b.cpp': good}, path, source, ['TEST_FATAL'])
    bad = [good.replace(stop, ''), good.replace('"C:/pure/tb.sv",1', '"C:/other/tb.sv",1'),
           good.replace('"C:/pure/tb.sv",1', '"C:/pure/tb.sv",2'),
           good.replace(stop, 'unrelated();' + stop), good.replace(stop, '/*' + stop + '*/'),
           good.replace(stop, '"VL_STOP_MT(fake)";'),
           'void f(){' + writer + stop + '}',
           'void f(){if(VL_UNLIKELY(bad)){}' + writer + stop + '}',
           good.replace('if(VL_UNLIKELY(bad))', 'if(1)'),
           'void f(){/* ' + writer + stop + ' */}',
           good + '\nvoid g(){' + writer + '}', good[:-2],
           good.replace(fmt, '"TEST_FATAL VL_STOP_MT(fake)"'),
           good.replace(stop, '/* ' + stop)]
    rejected = 0
    for text in bad:
        try: audit_texts({'bad.cpp': text}, path, source, ['TEST_FATAL'])
        except (AssertionError, ValueError, SyntaxError): rejected += 1
        else: raise AssertionError('structural falsifier accepted')
    try: audit_texts({'pure.cpp': good}, path, source + 'if(y)$fatal(1,"TEST_FATAL");\n', ['TEST_FATAL'])
    except AssertionError: rejected += 1
    else: raise AssertionError('missing second SOURCE site accepted')
    try: audit_texts({'a.cpp': good, 'b.cpp': good.replace(writer, '')}, path, source, ['TEST_FATAL'])
    except AssertionError: rejected += 1
    else: raise AssertionError('unpaired second compiled STOP accepted')
    return {'positive': 2, 'rejected': rejected, 'actual_CPP_audits': 0}


if __name__ == '__main__':
    print(json.dumps(pure_tests()))
