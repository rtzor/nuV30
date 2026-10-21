"""Finite engineering checks for 53 NEC8080AF instruction forms and 24 interactions.

Explicit prepare/lint/build/run phases; no implicit CPU rebuild or retry.
The literal instruction laws are an engineering oracle, not measured silicon.
This fixture compiles the staged-LOCK macro OFF; it does not qualify that profile.
"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import argparse,gzip,hashlib,json,os,re,shutil,subprocess,sys,tempfile,threading,time
from datetime import datetime,timezone
sys.dont_write_bytecode=True
import v30_8080_final53_cases as law
import v30_8080_final53_cpp_fatal as cpp_guard
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
load=lambda p:json.loads(Path(p).read_text(encoding='utf8'))

HDL_INPUTS = ['hdl/rtl/nec_bus.sv', 'hdl/rtl/ucore/pla3_tables.svh', 'hdl/rtl/ucore/v30_core.sv', 'hdl/rtl/ucore/v30u_biu.sv', 'hdl/rtl/ucore/v30u_eu.sv', 'hdl/rtl/ucore/v30u_eu_1bl.svh', 'hdl/rtl/ucore/v30u_eu_cond.svh', 'hdl/rtl/ucore/v30u_eu_iend_late.svh', 'hdl/rtl/ucore/v30u_eu_poste.svh', 'hdl/rtl/ucore/v30u_eu_row.svh', 'hdl/rtl/ucore/v30u_eu_ss_read.svh', 'hdl/rtl/ucore/v30u_eu_ss_write.svh', 'hdl/rtl/ucore/v30u_eu_step.svh', 'hdl/rtl/ucore/v30u_eu_wd1.svh', 'hdl/rtl/ucore/v30u_ss_pkg.sv', 'hdl/rtl/ucore/v30u_ucrom.sv', 'hdl/tb/tb_8080_final53.sv']
CORE_FILES = ['pla3_tables.svh', 'ucdecode.hex', 'ucdecode_8080.hex', 'ucrom.hex', 'v30u_biu.sv', 'v30u_eu.sv', 'v30u_eu_1bl.svh', 'v30u_eu_cond.svh', 'v30u_eu_iend_late.svh', 'v30u_eu_poste.svh', 'v30u_eu_row.svh', 'v30u_eu_ss_read.svh', 'v30u_eu_ss_write.svh', 'v30u_eu_step.svh', 'v30u_eu_wd1.svh', 'v30u_ss_pkg.sv', 'v30u_staged_lock_pkg.svh', 'v30u_staged_lock_unit.svh', 'v30u_ucrom.sv', 'v30_core.sv']
FATAL_FAMILIES = ['F53_ORACLE_BOUNDED_TIMEOUT', 'F53_ORACLE_BUS_BYTE', 'F53_ORACLE_BUS_COVERAGE', 'F53_ORACLE_BUS_OWNING_ADDRESS', 'F53_ORACLE_EVENT_ELIGIBILITY', 'F53_ORACLE_EXECUTION_COVERAGE', 'F53_ORACLE_FINAL_GPR', 'F53_ORACLE_FINAL_SREG', 'F53_ORACLE_FULL_RAM_MIRROR', 'F53_ORACLE_HALT_PARKED_STATE', 'F53_ORACLE_IRET_PHASE', 'F53_ORACLE_IRQ_BOUNDARY_COVERAGE', 'F53_ORACLE_IRQ_BOUNDARY_PC', 'F53_ORACLE_IRQ_BUS_PHASE', 'F53_ORACLE_IRQ_IRET_RESUMPTION', 'F53_ORACLE_MARKER_PHASE', 'F53_ORACLE_MASKED_HALT_RESTART', 'F53_ORACLE_MEMORY_IO_CLASS', 'F53_ORACLE_NATIVE_ISR_FRAME', 'F53_ORACLE_NATIVE_RETURN', 'F53_ORACLE_OPERAND_PHASE', 'F53_ORACLE_OWNED_PC_BYTE', 'F53_ORACLE_PRE_RETEM_COVERAGE', 'F53_ORACLE_PRE_RETEM_FLAGS_MODE', 'F53_ORACLE_PRE_RETEM_GPR', 'F53_ORACLE_PRE_RETEM_SREG', 'F53_ORACLE_PUBLIC_HALT', 'F53_ORACLE_READ_BEFORE_REQUIRED_WRITE', 'F53_ORACLE_RESET_NATIVE', 'F53_ORACLE_RETEM_READ_PHASE', 'F53_ORACLE_UNEXPECTED_BUS_GROUP', 'F53_ORACLE_UNEXPECTED_INTA', 'F53_ORACLE_UNEXPECTED_READ_KIND', 'F53_ORACLE_WRITE_BEFORE_REQUIRED_READ', 'F53_PROTO_CASE_ARGS', 'F53_PROTO_ENTRY_FRAME_STATE', 'F53_PROTO_ENTRY_GPR', 'F53_PROTO_ENTRY_SREG', 'F53_PROTO_HALT_ANNOUNCE_OWNER', 'F53_PROTO_HALT_END_OWNER', 'F53_PROTO_HALT_LITERAL_OWNER', 'F53_PROTO_IRQ_BOUNDARY_OWNER', 'F53_PROTO_IRQ_PC_WITHOUT_BOUNDARY', 'F53_PROTO_IVT_NATIVE_GPR', 'F53_PROTO_IVT_NATIVE_PHASE', 'F53_PROTO_IVT_NATIVE_SREG', 'F53_PROTO_LITERAL_BINDING', 'F53_PROTO_LITERAL_LIMIT', 'F53_PROTO_MASKED_HALT_INT_PULSE', 'F53_PROTO_MASKED_HALT_SUCCESSOR_CURSOR', 'F53_PROTO_MASKED_INT_NOT_WITHDRAWN', 'F53_PROTO_MASKED_INT_STIMULUS_DURATION', 'F53_PROTO_NATIVE_PREP_FLAGS_PC', 'F53_PROTO_NATIVE_PREP_GPR', 'F53_PROTO_NATIVE_PREP_SREG', 'F53_PROTO_PUBLIC_WRITE_CLASS', 'F53_PROTO_RAM_WRITE_CLASS', 'F53_PROTO_READ_BUS_CLASS', 'FIXTURE_CORE_T2_READ_LATCH_FAIL', 'FIXTURE_PUBLIC_ADDRESS_SAMPLE_FAIL', 'FIXTURE_PUBLIC_READ_DATA_FAIL', 'FIXTURE_READ_OWNING_ADDRESS_FAIL', 'FIXTURE_RIG_ADDRESS_LATCH_FAIL']
TRACE_MARKERS = ['F53_BUS_GROUP', 'F53_BUS_MISMATCH', 'F53_CASE', 'F53_ENTRY_FRAME', 'F53_EVENT', 'F53_FLUSH', 'F53_HALT_STABLE', 'F53_HLT_ANNOUNCE', 'F53_HLT_INT_WITHDRAW', 'F53_HLT_MON', 'F53_HLT_PARKED', 'F53_HLT_SUCCESSOR_COMPLETE', 'F53_INTA', 'F53_INT_WITHDRAW', 'F53_IRQ_BOUNDARY', 'F53_IRQ_RESUME', 'F53_ISR', 'F53_NATIVE_PREP', 'F53_OWNED', 'F53_PASS', 'F53_PRE_RETEM', 'F53_SYS_POST', 'F53_SYS_PRE', 'F53_TARGET', 'F53_WAKE_EMU', 'PUBLIC_ADDRESS_ANCHOR', 'PUBLIC_READ_ANCHOR']

def claim_storage(state,added,cap):
    assert added>=0
    state['bytes']+=added
    if state['bytes']>=cap:state['stop']=True
    return not state['stop']

def protocol_text(raw):
    normalized=raw.replace(b'\r\n',b'\n')
    assert b'\r' not in normalized,'unpaired CR in protocol stream'
    return normalized.decode('utf8',errors='strict')

def halt_protocol(text, c):
    marks = re.findall(r'^F53_HLT_MON sys=(\d+) CE=([01]) T=(\d+) NEXT=(\d+) BSQ=(\d+) BS=(\d+) RD=([01]) UBE=([01]) INT=([01]) RESET=([01]) owned=(\d+) OWNER=(\d+) SEQ=(\d+)$', text, re.M)
    assert text.count('F53_HLT_MON ') == len(marks), 'all HLT monitor rows must parse'
    if c['opcode'] != 0x76:
        assert not marks and not re.search(r'^F53_HLT_(?:ANNOUNCE|PARKED|SUCCESSOR_COMPLETE|INT_WITHDRAW) ', text, re.M)
        return
    assert marks
    locations = [i for i,(pc,byte) in enumerate(c['owned_bytes']) if pc == ((c['halt_resume_PC']-1)&65535) and byte == 0x76]
    assert len(locations) == 1
    halt_count = locations[0]+1
    marks = [tuple(map(int, row)) for row in marks]
    assert [row[0] for row in marks] == list(range(marks[0][0], marks[-1][0] + 1))
    pres = {}
    for line in text.splitlines():
        if line.startswith('F53_SYS_PRE '):
            fields = dict(re.findall(r'(\w+)=([^ ]+)', line))
            pres[int(fields['n'])] = fields
    owner = 0
    for line in text.splitlines():
        if line.startswith('F53_OWNED '): owner += 1
        elif line.startswith('F53_HLT_MON '):
            fields = dict(re.findall(r'(\w+)=([^ ]+)', line)); assert int(fields['owned']) == owner
    for row in marks:
        n, ce, ts, nxt, bsq, bs, rd, ube, irq, reset, owned, kind, seq = row
        pre = pres[n]
        assert (ce, bs, rd, ube, irq, reset) == tuple(int(pre[k]) for k in ('CE','BS','RD','UBE','INT','RESET'))
        assert n - 1 in pres and bsq == int(pres[n - 1]['BS']), 'registered public status must be one SYS old'
    announcements = re.findall(r'^F53_HLT_ANNOUNCE sys=(\d+) seq=(\d+)$', text, re.M)
    parked = re.findall(r'^F53_HLT_PARKED sys=(\d+) seq=(\d+)$', text, re.M)
    assert len(announcements) == len(parked) == 1
    announce, seq = map(int, announcements[0]); park, parkseq = map(int, parked[0]); assert announce < park and seq == parkseq
    by_n = {row[0]: row for row in marks}; ann = by_n[announce]; end = by_n[park]
    assert ann[1] == 1 and ann[3] == 1 and ann[4] == 3 and ann[9] == 0 and ann[10] == halt_count and ann[12] + 1 == seq
    assert end[1:4] == (1, 5, 0) and end[9] == 0 and end[11:13] == (3, seq)
    assert sum(row[1] and row[3] == 1 and row[4] == 3 for row in marks if row[0] <= park) == 1
    assert not any(row[1] and row[3] == 1 for row in marks if announce < row[0] <= park)
    event_lines = re.findall(r'^F53_EVENT type=(\d+) point=(\d+) PC=([0-9a-f]+) FLAGS=([0-9a-f]+) owned=(\d+)$', text, re.M | re.I)
    assert len(event_lines) == 1 and tuple(map(int,event_lines[0][:2])) == (c['event'], 4)
    event_pos = text.index('F53_EVENT ')
    event_pre = re.findall(r'^F53_SYS_PRE n=(\d+) ', text[:event_pos], re.M)
    event = int(event_pre[-1]); assert event > park
    window = [row for row in marks if park < row[0] <= event]
    assert [row[0] for row in window] == list(range(park + 1, event + 1))
    assert sum(row[1] for row in window) == c['halt_cycles'], 'complete32/48CPU standby clocks after HALT transaction'
    for row in window:
        assert row[2:4] == (0,0) and row[5:8] == (7,1,1) and row[9:11] == (0,halt_count), 'every SYS of parked window'
        pre = pres[row[0]]
        assert pre['st'] == '30' and int(pre['PC'],16) == c['halt_resume_PC'] and pre['MODE'] == pre['SESSION'] == '1'
    stable = re.findall(r'^F53_HALT_STABLE cycles=(\d+) PC=([0-9a-f]+) FLAGS=([0-9a-f]+) BS=(\d+)$', text, re.M | re.I)
    assert len(stable) == 1 and int(stable[0][0]) == c['halt_cycles'] and int(stable[0][1],16) == c['halt_resume_PC'] and stable[0][3] == '7'
    assert text.index('F53_HLT_PARKED ') < text.index('F53_HALT_STABLE ') < event_pos
    successor = re.findall(r'^F53_HLT_SUCCESSOR_COMPLETE sys=(\d+) owned=(\d+)$', text, re.M)
    withdrawn = re.findall(r'^F53_HLT_INT_WITHDRAW sys=(\d+) CPU=(\d+) TW=(\d+) successor=([01]) owned=(\d+)$', text, re.M)
    if c['event'] == 1 and c['expected_IRQ'] == 0:
        assert len(successor) == len(withdrawn) == 1
        done, owned = map(int,successor[0]); stop, cpu, tw, first, count = map(int,withdrawn[0])
        assert event < done <= stop and owned == halt_count+3 and first == 1 and count >= len(c['owned_bytes']) - 2
        assert [b for pc,b in c['owned_bytes'][halt_count:halt_count+3]] == [0,0,0]
        before_done = text[:text.index('F53_HLT_SUCCESSOR_COMPLETE ')]
        assert len(re.findall(r'^F53_OWNED ',before_done,re.M)) == halt_count+3
        period = [row for row in marks if event < row[0] <= stop]
        assert [row[0] for row in period] == list(range(event + 1,stop + 1)) and all(row[8] == 1 and row[9] == 0 for row in period)
        assert cpu == sum(row[1] for row in period) and tw == sum(row[1] and row[2] == 4 for row in period)
        assert stop - event >= 75 and cpu >= 15 + tw
        assert any(row[0] > stop and row[8] == 0 for row in marks), 'INT visibly withdrawn before RETEM'
        assert text.index('F53_HLT_SUCCESSOR_COMPLETE ') < text.index('F53_HLT_INT_WITHDRAW ') < text.index('F53_PRE_RETEM ')
    else:
        assert not successor and not withdrawn

def observed_protocol(raw,c,rc,timed_out):
    text=protocol_text(raw);lines=text.splitlines()
    pre=[int(v)for v in re.findall(r'^F53_SYS_PRE n=(\d+) ',text,re.M)]
    post=[int(v)for v in re.findall(r'^F53_SYS_POST n=(\d+) ',text,re.M)]
    fatals=[x for x in lines if '%Fatal:' in x or '%Error:' in x]
    assert pre==list(range(len(pre))) and pre,'all SYS_PRE rows required'
    assert post==list(range(1,len(post)+1)),'all SYS_POST rows required'
    assert len(pre)==len(post) or (len(pre)==len(post)+1 and rc!=0 and bool(fatals)), 'Only fatal abort may leave final PRE unmatched'
    assert re.findall(r'^F53_CASE population=(\d+) id=(\d+) opcode=([0-9a-f]+) family=(\d+) waits=(\d+) event=(\d+) point=(\d+) expected_owned=(\d+) reads=(\d+) writes=(\d+) reset=(\d+)$',text,re.M|re.I)==[
        tuple(str(x) for x in (c['population'],c['id']))+(format(c['opcode'],'02x'),)+tuple(str(x)for x in (c['family'],c['waits'],c['event'],c['event_point'],len(c['owned_bytes']),len(c['read_groups']),len(c['write_groups']),c['expected_reset']))], 'exact frozen case binding'
    if re.search(r'(?im)(?:%Warning|warning:|cannot open|failed to open|readmem[^\n]*(?:error|not found)|uninitialized)',text):return 'BLOCK_STARTUP_WARNING',fatals
    if timed_out:return 'BLOCK_TIMEOUT',fatals
    if rc!=0 or fatals:
        category='FUNCTIONAL_FAIL'if any('F53_ORACLE_'in x for x in fatals)else'BLOCK_INSTRUMENT'
        if category=='FUNCTIONAL_FAIL'and c.get('word_boundary_inferred')and any('F53_ORACLE_BUS_'in x for x in fatals):category='ENGINEERING_BOUNDARY_FAIL'
        return category,fatals
    assert not re.search(r'(?im)(?:%Warning|warning:)',text),'unexpected startup warning retained'
    footer=re.findall(r'^F53_PASS population=(\d+) id=(\d+) reset=(\d+) owned=(\d+) targetrows=(\d+) INTA=(\d+) ISR=(\d+)$',text,re.M)
    assert len(footer)==1
    p,i,z,owned,target,inta,isr=map(int,footer[0])
    assert (p,i,z,owned,inta,isr)==(c['population'],c['id'],c['expected_reset'],len(c['owned_bytes']),c['expected_INTA'],c['expected_IRQ']) and target>0
    target_rows=re.findall(r'^F53_TARGET opcode=([0-9a-f]+) ',text,re.M|re.I)
    assert len(target_rows)==target and all(int(x,16)==c['opcode']for x in target_rows)
    owned_rows=re.findall(r'^F53_OWNED index=(\d+) PC=([0-9a-f]+) byte=([0-9a-f]+)$',text,re.M|re.I)
    assert [int(x[0])for x in owned_rows]==list(range(len(owned_rows)))
    actual_owned=[(int(pc,16),int(b,16))for idx,pc,b in owned_rows]
    assert actual_owned==[tuple(x)for x in c['owned_bytes']]
    boundaries=re.findall(r'^F53_IRQ_BOUNDARY next_owned=(\d+) restart=([0-9a-f]+)$',text,re.M|re.I)
    resumes=re.findall(r'^F53_IRQ_RESUME next_owned=(\d+) restart=([0-9a-f]+)$',text,re.M|re.I)
    if c.get('restart_PC_policy')=='FROZEN_CURSOR_AT_IRQ_BOUNDARY':
        assert len(boundaries)==1 and resumes==boundaries
        cursor,pc=boundaries[0];cursor=int(cursor);pc=int(pc,16)
        assert 1<=cursor<len(c['owned_bytes'])-2 and c['owned_bytes'][cursor]==[pc,0]
        assert c['opcode']!=0xFB or c['event']!=1 or cursor>=2,'EI must finish following NOP before INT'
        before=text[:text.index('F53_IRQ_BOUNDARY ')];between=text[text.index('F53_IRQ_BOUNDARY '):text.index('F53_IRQ_RESUME ')]
        assert len(re.findall(r'^F53_OWNED ',before,re.M))==cursor and not re.search(r'^F53_OWNED ',between,re.M)
        assert len(re.findall(r'^F53_ISR ',between,re.M))==1
        c=dict(c)
        for direction in ('read_groups','write_groups'):
            c[direction]=[dict(g,bytes=list(g['bytes'])) for g in c[direction]]
        c['write_groups'][5]['bytes']=[pc&255,pc>>8]
        c['read_groups'][4]['bytes']=[pc&255,pc>>8]
    else:assert not boundaries and not resumes
    halt_protocol(text,c)
    stages={(r,p):[0,set()]for r in (0,1)for p in (0,1)}
    rows=re.findall(r'^F53_BUS_GROUP read=([01]) public=([01]) space=(\d+) addr=([0-9a-f]+) data=([0-9a-f]+) lanes=([01]{2}) next=(\d+) mask=(\d+) phase=(\d+)$',text,re.M|re.I)
    for rd,pub,space,address,data,lanes,nxt,mask,phase in rows:
        rd,pub,space,nxt,mask,phase=map(int,(rd,pub,space,nxt,mask,phase));address=int(address,16);data=int(data,16)
        stage,seen=stages[rd,pub];groups=c['read_groups']if rd else c['write_groups'];assert stage<len(groups)
        g=groups[stage];assert space==g['space'] and phase==g['phase']
        for lane in (0,1):
            if int(lanes,2)&(1<<lane):
                at=(address&~1)+lane;assert at in g['addresses'];k=g['addresses'].index(at)
                assert k not in seen and ((data>>(lane*8))&255)==g['bytes'][k];seen.add(k)
        if len(seen)==len(g['bytes']):stage+=1;seen=set()
        assert stage==nxt and sum(1<<v for v in seen)==mask;stages[rd,pub]=[stage,seen]
    for (rd,pub),(stage,seen)in stages.items():assert not seen and stage==len(c['read_groups']if rd else c['write_groups'])
    assert text.count('F53_NATIVE_PREP ')==text.count('F53_ENTRY_FRAME ')==1
    events=re.findall(r'^F53_EVENT type=(\d+) point=(\d+) ',text,re.M)
    assert events==([]if not c['event']else[(str(c['event']),str(c['event_point']))])
    assert len(re.findall(r'^F53_INTA ',text,re.M))==c['expected_INTA']
    assert len(re.findall(r'^F53_ISR ',text,re.M))==c['expected_IRQ']
    if c['expected_reset']:
        assert 'F53_PRE_RETEM 'not in text and len(re.findall(r'^F53_HALT_STABLE ',text,re.M))==1
    else:
        snaps=re.findall(r'^F53_PRE_RETEM PC=([0-9a-f]+) FLAGS=([0-9a-f]+) GPR=([^ ]+) SREG=([^ ]+) reads=(\d+),(\d+) writes=(\d+),(\d+)$',text,re.M|re.I)
        assert len(snaps)==1;pc,flags,gpr,seg,rr,pr,rw,pw=snaps[0];flags=int(flags,16)
        eg=list(c['final_GPR']);eg[4]=c['frame_SP']
        assert int(pc,16)==(c['pre_RETEM_PC']+2)&65535 and [int(x,16)for x in gpr.split(',')]==eg
        assert [int(x,16)for x in seg.split(',')]==c['emu_SREG']
        assert flags&c['expected_flags_mask']==c['expected_flags'] and flags&0x802A==2
        assert list(map(int,(rr,pr,rw,pw)))==[len(c['read_groups'])-3]*2+[len(c['write_groups'])-1]*2
        ends=re.findall(r'^F53_SYS_POST n=\d+ PC=([0-9a-f]+) st=(\d+) FLAGS=([0-9a-f]+) MODE=([01]) SESSION=([01]) GPR=([^ ]+) SREG=([^\r\n ]+)',text,re.M|re.I)
        pc,st,fl,mode,session,gpr,seg=ends[-1]
        assert (int(pc,16),int(st),int(fl,16),int(mode),int(session))==(c['native_final_PC'],30,c['native_PSW'],0,0)
        assert [int(x,16)for x in gpr.split(',')]==c['final_GPR'] and [int(x,16)for x in seg.split(',')]==c['native_SREG']
    return 'PASS_FULL_LITERAL_AND_PUBLIC_ORACLES',fatals

SUITES = ('baseline', 'holdout', 'smoke-baseline', 'smoke-holdout')
COUNTS = (4824, 4824, 12, 12)


def digest_bytes(raw):
    return hashlib.sha256(raw).hexdigest()


def write_new(path, value):
    raw = value if isinstance(value, bytes) else (json.dumps(value, indent=2) + '\n').encode()
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('xb') as stream:
        stream.write(raw)
    return digest_bytes(raw)


def frozen_populations():
    populations = law.populations() + [law.interactions(0), law.interactions(1)]
    assert tuple(map(len, populations)) == COUNTS
    return populations


def prepare(a):
    """Generate the same finite literals, with no CPU or compiler invocation."""
    populations = frozen_populations()
    records = {}
    expected = {}
    for pop, cases in enumerate(populations):
        for case in cases:
            relative = 'records/p%d-%04d.hex' % (pop, case['id'])
            raw = law.record(case).encode('ascii')
            expected[relative] = raw
            records[relative] = digest_bytes(raw)
            case['record_path'] = relative
        expected['population-%d.json' % pop] = (json.dumps({'population': pop, 'cases': cases}, indent=2) + '\n').encode()
    expected['records-manifest.json'] = (json.dumps({'records': records, 'population_counts': list(COUNTS),
        'encoding': 'One4096hexline representing1024little-index16bitwords; word0rightmost. Selected2KiB only perDUT.'}, indent=2) + '\n').encode()
    if a.verify:
        for relative, raw in expected.items():
            assert (a.out / relative).read_bytes() == raw, relative
        assert {p.relative_to(a.out / 'records').as_posix() for p in (a.out / 'records').iterdir()} == {p.split('/', 1)[1] for p in records}
    else:
        assert not a.out.exists(), 'prepare requires a fresh output directory'
        for relative, raw in expected.items():
            write_new(a.out / relative, raw)
    print(json.dumps({'status': 'PREPARED_RECORDS_VERIFIED' if a.verify else 'PREPARED_RECORDS',
                      'population_counts': list(COUNTS), 'record_count': len(records),
                      'scope': 'Finite engineering literals only; no CPU execution.'}))
    return 0


def public_sources(project):
    files = [project / relative for relative in HDL_INPUTS]
    core = project / 'hdl/rtl/ucore'
    # Extracted EU arms are compiler inputs too. Bind every include, including
    # new arm files, rather than silently leaving them outside custody checks.
    files = list(dict.fromkeys(files + sorted(core.glob('*.svh'))))
    return files, list(dict.fromkeys([core / name for name in CORE_FILES] + sorted(core.glob('*.svh'))))


def tool_path(value):
    found = shutil.which(value)
    path = Path(found if found else value).resolve()
    assert path.is_file(), 'tool not found: ' + value
    return path


def check_inputs(mapping):
    for path, expected in mapping.items():
        assert sha(path) == expected, path


def compile_fixture(a, lint):
    """Explicit strict build. Never invoked implicitly by run."""
    assert __debug__, 'Python optimization disables required checks'
    tool = tool_path(a.verilator)
    tool_root = a.verilator_root.resolve() if a.verilator_root else tool.parent.parent / 'share/verilator'
    tool_binary = tool
    if not tool.name.startswith('verilator_bin'):
        choices = [p for p in (tool.parent / 'verilator_bin.exe', tool.parent / 'verilator_bin') if p.is_file()]
        assert len(choices) == 1, 'provide the exact Verilator binary with --verilator'
        tool_binary = choices[0]
    tool_sources = [tool_binary, tool_root / 'include/verilated_std.sv', tool_root / 'include/verilated_std_waiver.vlt']
    files, core_files = public_sources(a.project)
    source_inputs = files + core_files + tool_sources + [Path(__file__).resolve(),
        Path(law.__file__).resolve(), Path(cpp_guard.__file__).resolve(), Path(sys.executable).resolve(), tool]
    for candidate in (tool.parent / 'verilator_bin.exe', tool.parent / 'verilator_bin'):
        if candidate.is_file() and candidate not in source_inputs:
            source_inputs.append(candidate)
    inputs = {str(path.resolve()): sha(path) for path in source_inputs}
    for name in ('records-manifest.json',):
        path = a.out / name
        inputs[str(path)] = sha(path)
    target = a.out / ('lint' if lint else 'build')
    assert not target.exists(), 'preserve the previous result; use a fresh --out'
    target.mkdir()
    command = [str(tool), '--lint-only' if lint else '--binary', '--timing', '--assert',
        '--compiler', a.compiler, '--top-module', 'tb_8080_final53', '-Wall',
        '-Wno-UNUSEDSIGNAL', '-Wno-VARHIDDEN', '-Wno-TIMESCALEMOD', '-Wno-BLKSEQ',
        '-Wno-DECLFILENAME', '-Wno-UNUSEDPARAM', '-Mdir', target.as_posix(),
        '-CFLAGS', '-std=c++20', '-I' + (a.project / 'hdl/rtl/ucore').as_posix(),
        '-I' + (a.project / 'hdl/tb').as_posix()]
    if a.make_flags:
        command += ['-MAKEFLAGS', a.make_flags]
    command += [(a.project / p).as_posix() for p in ('hdl/rtl/ucore/v30u_ss_pkg.sv',
        'hdl/rtl/ucore/v30u_ucrom.sv', 'hdl/rtl/ucore/v30u_eu.sv',
        'hdl/rtl/ucore/v30u_biu.sv', 'hdl/rtl/ucore/v30_core.sv',
        'hdl/rtl/nec_bus.sv', 'hdl/tb/tb_8080_final53.sv')]
    rc = None
    error = None
    binary = target / ('Vtb_8080_final53.exe' if os.name == 'nt' else 'Vtb_8080_final53')
    try:
        with (target / 'build.log').open('xb') as log:
            process = subprocess.run(command, cwd=a.project, stdout=log, stderr=subprocess.STDOUT, timeout=1800)
        rc = process.returncode
        assert rc == 0, 'compiler exit ' + str(rc)
        text = (target / 'build.log').read_text(encoding='utf-8', errors='strict')
        assert '%Warning' not in text, 'strict RTL warning retained'
        if not lint:
            assert binary.is_file(), 'compiled binary missing'
            dat = (target / 'Vtb_8080_final53__verFiles.dat').read_text(encoding='utf-8')
            compiled = {str((Path(p) if Path(p).is_absolute() else a.project / p).resolve())
                for p in re.findall(r'^S[^\n]*"([^"\n]+)"\s*$', dat, re.M)}
            expected = {str(p.resolve()) for p in files + tool_sources}
            # Optional staged-lock includes are not elaborated in macro-OFF
            # builds; they are hashed above, but must not appear as compiled.
            expected -= {str((a.project / 'hdl/rtl/ucore' / n).resolve()) for n in
                         ('v30u_staged_lock_pkg.svh', 'v30u_staged_lock_unit.svh')}
            assert len(expected) >= 20 and compiled == expected, {'missing': sorted(expected - compiled), 'undeclared': sorted(compiled - expected)}
            write_new(target / 'compiled-sources.json', sorted(compiled))
            cpp_files = {str(p): p.read_text(encoding='utf-8', errors='strict') for p in target.glob('*.cpp')}
            audit = cpp_guard.audit_cpp(cpp_files, a.project / 'hdl/tb/tb_8080_final53.sv', FATAL_FAMILIES)
            write_new(target / 'structural-fatal-audit.json', audit)
            cpp = '\n'.join(cpp_files.values())
            assert 'assertCtlGet' in cpp and all(marker in cpp for marker in TRACE_MARKERS)
    except Exception as exc:
        error = str(exc)
    post = {path: sha(path) if Path(path).is_file() else None for path in inputs}
    if inputs != post:
        error = (error or '') + ' input custody changed'
    log_text = (target / 'build.log').read_text(encoding='utf-8', errors='replace') if (target / 'build.log').is_file() else ''
    write_new(target / 'cpp-warning-classification.json', {'warning_lines': [line for line in log_text.splitlines()
        if 'warning:' in line and not line.startswith('%Warning')],
        'scope': 'Retained host compiler diagnostics; strict RTL warning check remains separate.'})
    receipt = {'schema': '8080_FINAL53_PUBLIC_BUILD_V1', 'status': 'FAIL' if error else 'PASS',
        'error': error, 'compiler_rc': rc, 'lint_only': lint, 'command': command,
        'binary': str(binary), 'binary_sha256': sha(binary) if binary.is_file() else None,
        'project': str(a.project), 'inputs': inputs, 'post_inputs': post,
        'outputs': {str(p): sha(p) for p in target.rglob('*') if p.is_file()},
        'scope': 'Macro-OFF finite engineering final53 instrument; no CPU execution or silicon claim.'}
    path = target / 'receipt.json'
    write_new(path, receipt)
    print(json.dumps({'receipt': str(path), 'sha256': sha(path), 'status': receipt['status']}))
    return 0 if receipt['status'] == 'PASS' else 1


def run_suite(a):
    assert __debug__, 'Python optimization disables required checks'
    br = load(a.build)
    assert br['schema'] == '8080_FINAL53_PUBLIC_BUILD_V1' and br['status'] == 'PASS'
    assert br['compiler_rc'] == 0 and not br['lint_only'] and br['inputs'] == br['post_inputs']
    assert Path(br['project']).resolve() == a.project
    assert '--assert' in br['command'] and not any('STAGED' in token for token in br['command'])
    assert br['inputs'][str(Path(__file__).resolve())] == sha(__file__)
    check_inputs(br['inputs'])
    check_inputs(br['outputs'])
    assert sha(br['binary']) == br['binary_sha256']
    pop = SUITES.index(a.suite)
    if a.suite == 'holdout':
        assert a.baseline, 'holdout requires this build\'s full PASS baseline receipt'
        base = load(a.baseline)
        assert base['status'] == 'PASS' and base['population'] == 0 and base['registered_cases'] == 4824
        assert base['build_receipt_sha256'] == sha(a.build)
    cases_path = a.out / ('population-%d.json' % pop)
    manifest_path = a.out / 'records-manifest.json'
    cases = load(cases_path)['cases']
    assert len(cases) == COUNTS[pop] and [case['id'] for case in cases] == list(range(COUNTS[pop]))
    frozen = json.loads(json.dumps(frozen_populations()[pop]))
    assert [{k: v for k, v in c.items() if k != 'record_path'} for c in cases] == frozen
    manifest = load(manifest_path)
    assert manifest['population_counts'] == list(COUNTS)
    records = {str((a.out / p).resolve()): h for p, h in manifest['records'].items()}
    inputs = dict(br['inputs'])
    for path, digest in br['outputs'].items():
        assert path not in inputs or inputs[path] == digest
        inputs[path] = digest
    for c in cases:
        assert c['record_path'] == 'records/p%d-%04d.hex' % (pop, c['id'])
        c['record_path'] = str((a.out / c['record_path']).resolve())
        path = Path(c['record_path'])
        assert path.read_bytes() == law.record(c).encode('ascii') and sha(path) == records[str(path)]
        inputs[str(path)] = records[str(path)]
    for path in [cases_path, manifest_path, a.build.resolve()] + ([a.baseline.resolve()] if a.baseline else []):
        inputs[str(path)] = sha(path)
    check_inputs(inputs)
    r = {'population': pop, 'cwd': str(a.project), 'minimum_free_reserve_bytes': 4294967296,
         'producer_compressed_bytes_cap': 4294967296, 'raw_bytes_cap_per_case': 268435456,
         'compressed_bytes_cap_per_case': 67108864, 'timeout_seconds_per_case': 180}
    assert shutil.disk_usage(a.out).free >= 8589934592
    O = Path(tempfile.mkdtemp(prefix='f53-' + a.suite + '-', dir=a.out))
    storage={'bytes':0,'stop':False};storage_lock=threading.Lock()
    env=dict(os.environ)
    def one(c):
        path=Path(c['record_path']);assert sha(path)==records[str(path)]
        cmd=[br['binary'],'+population='+str(c['population']),'+case_id='+str(c['id']),'+record='+path.as_posix()]
        log=O/('case-%04d.log.gz'%c['id']);start=time.monotonic();utcstart=datetime.now(timezone.utc).isoformat();rc=None;timed=False;error=None;capture={};fatals=[];category='BLOCK_INSTRUMENT'
        proc=None
        try:
            assert shutil.disk_usage(O).free>=r['minimum_free_reserve_bytes']
            with storage_lock:assert not storage['stop'],'BLOCK_PRODUCER_STORAGE_CAP_NO_DUT'
            proc=subprocess.Popen(cmd,cwd=r['cwd'],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
            def pump():
                h=hashlib.sha256();total=0;lines=0;eof=False;accounted=0
                try:
                    with log.open('xb')as f,gzip.GzipFile(filename='',mode='wb',fileobj=f,compresslevel=1,mtime=0)as z:
                        while True:
                            b=proc.stdout.read(65536)
                            if not b:eof=True;break
                            z.write(b);h.update(b);total+=len(b);lines+=b.count(b'\n')
                            with storage_lock:
                                now=f.tell();exhausted=not claim_storage(storage,now-accounted,r['producer_compressed_bytes_cap']);accounted=now
                            if exhausted or total>r['raw_bytes_cap_per_case']or f.tell()>r['compressed_bytes_cap_per_case']:
                                capture['error']='BLOCK_RAW_CAP';proc.kill();break
                except Exception as exc:
                    capture['error']=repr(exc)
                    if proc.poll()is None:proc.kill()
                finally:
                    with storage_lock:
                        if log.exists():claim_storage(storage,log.stat().st_size-accounted,r['producer_compressed_bytes_cap'])
                    capture.update(uncompressed_sha256=h.hexdigest(),uncompressed_bytes=total,uncompressed_lines=lines,pipe_EOF=eof);proc.stdout.close()
            t=threading.Thread(target=pump);t.start()
            try:rc=proc.wait(timeout=r['timeout_seconds_per_case'])
            except subprocess.TimeoutExpired:timed=True;proc.kill();rc=proc.wait()
            t.join();assert capture.get('pipe_EOF')and'error'not in capture
            raw=gzip.decompress(log.read_bytes());assert hashlib.sha256(raw).hexdigest()==capture['uncompressed_sha256']
            category,fatals=observed_protocol(raw,c,rc,timed)
            assert sha(path)==records[str(path)]
        except Exception as exc:error=str(exc)
        finally:
            if proc is not None and proc.poll()is None:proc.kill();proc.wait()
            if proc is not None:rc=proc.returncode
        row={'population':c['population'],'id':c['id'],'opcode':c['opcode'],'status':'PASS'if category.startswith('PASS_')and not error else'FAIL'if category in('FUNCTIONAL_FAIL','ENGINEERING_BOUNDARY_FAIL')and not error else'BLOCK','category':category,'error':error,'observed_RC':rc,'timed_out':timed,'command':cmd,'DUT_started':proc is not None,'raw_gzip':str(log),'raw_gzip_sha256':sha(log)if log.exists()else None,'raw_gzip_bytes':log.stat().st_size if log.exists()else None,'capture':capture,'instrument_fatals':fatals,'seconds':time.monotonic()-start,'start_utc':utcstart,'end_utc':datetime.now(timezone.utc).isoformat()}
        print(json.dumps({k:row[k]for k in ('population','id','opcode','status','category','observed_RC')},separators=(',',':')),flush=True)
        return row
    start=time.monotonic()
    with ThreadPoolExecutor(max_workers=a.workers)as pool:rows=list(pool.map(one,cases))
    rows.sort(key=lambda x:x['id']);post={path:sha(path)if Path(path).exists()else None for path in inputs}
    counts={s:sum(v['status']==s for v in rows)for s in ('PASS','FAIL','BLOCK')}
    receipt={'schema':'8080_FINAL53_FIXED_POPULATION_RECEIPT_V1','status':'PASS'if counts['PASS']==len(cases)and inputs==post else'FAIL','population':r['population'],'suite':a.suite,'registered_cases':len(cases),'counts':counts,'inputs':inputs,'post_inputs':post,'build_receipt':str(a.build.resolve()),'build_receipt_sha256':sha(a.build),'rows':rows,'seconds':time.monotonic()-start,'storage':storage,'gzip_scope':'Lossless full original DUT stdout+stderr, all EOF/RC and SHA of both compressed/uncompressed bytes; no rows removed.','scope':'Finite engineering final53 population; no silicon/fullCPU qualification claim'}
    out=O/'receipt.json'
    with out.open('x',encoding='utf8',newline='\n')as f:json.dump(receipt,f,indent=2);f.write('\n')
    print(json.dumps({'receipt':str(out),'sha256':sha(out),'status':receipt['status'],'counts':counts}),flush=True)
    return 0 if receipt['status']=='PASS'else 1


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[1])
    p.add_argument('--out', type=Path, required=True)
    sub = p.add_subparsers(dest='action', required=True)
    prepare_parser = sub.add_parser('prepare', help='create frozen literals; no DUT/compiler')
    prepare_parser.add_argument('--verify', action='store_true')
    for action in ('lint', 'build'):
        compiler_parser = sub.add_parser(action, help='explicit strict macro-OFF compiler invocation')
        compiler_parser.add_argument('--verilator', default='verilator')
        compiler_parser.add_argument('--verilator-root', type=Path)
        compiler_parser.add_argument('--compiler', choices=['clang', 'gcc'], default='clang')
        compiler_parser.add_argument('--make-flags', default='', help='explicit platform make variables; no shell wrapper is added')
    run_parser = sub.add_parser('run', help='execute one complete frozen population; never builds implicitly')
    run_parser.add_argument('--suite', choices=SUITES, required=True)
    run_parser.add_argument('--build', type=Path, required=True)
    run_parser.add_argument('--baseline', type=Path)
    run_parser.add_argument('--workers', type=int, choices=[1, 2], default=2)
    a = p.parse_args()
    a.project, a.out = a.project.resolve(), a.out.resolve()
    assert __debug__, 'run without Python -O'
    if a.action == 'prepare':
        return prepare(a)
    if a.action in ('lint', 'build'):
        return compile_fixture(a, a.action == 'lint')
    return run_suite(a)


if __name__ == '__main__':
    sys.exit(main())
