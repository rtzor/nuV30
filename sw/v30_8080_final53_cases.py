"""Finite independent instruction laws and selected-case records; no DUT imports."""
from collections import Counter

D5=0xD5
PAIRS=[0x0000,0xFFFF,0x00FF,0xFF00,0x7FFF,0x8000,0xA55A,0x5AA5]
PAIRS_H=[0x0101,0xFEFE,0x1357,0x2468,0x55AA,0xAA55,0x0F0F,0xF0F0]
SP=[0,0xFFFE,0x00FE,0x0100,0x7FFE,0x8000,0x0200,0xF000]
COND=[0xC0,0xC2,0xC4,0xC8,0xCA,0xCC,0xD0,0xD2,0xD4,0xD8,0xDA,0xDC,
      0xE0,0xE2,0xE4,0xE8,0xEA,0xEC,0xF0,0xF2,0xF4,0xF8,0xFA,0xFC]
UNCOND=[0xC3,0xC9,0xCD,0xC7,0xCF,0xD7,0xDF,0xE7,0xEF,0xF7,0xFF]
STACK=[0xC1,0xD1,0xE1,0xC5,0xD5,0xE5,0xE3,0xE9,0xF9,0xF1,0xF5]
FORMS=sorted([0x00,0x27,0x76,0xD3,0xDB,0xF3,0xFB]+COND+UNCOND+STACK)
assert len(FORMS)==len(set(FORMS))==53


def szp(a):
    return (a&0x80)|(0x40 if a==0 else 0)|(4 if a.bit_count()%2==0 else 0)


def daa(a,ac,cy):
    correction=(6 if (a&15)>9 or ac else 0)+(0x60 if a>0x99 or cy else 0)
    result=(a+correction)&255
    aux=int(bool(correction&6) and (a&15)+6>15)
    carry=int(bool(cy) or a>0x99)
    return result,szp(result)|(aux<<4)|carry


def predicate(op,flags):
    selector=(op>>3)&7;bit=[0x40,0x40,1,1,4,4,0x80,0x80][selector]
    return bool(flags&bit)==bool(selector&1)


def status(bits):
    return ((bits&8)<<4)|((bits&4)<<4)|(bits&2)<<1|(bits&1)


def word_bytes(value):
    return [value&255,(value>>8)&255]


def make_case(pop,cid,op,vector,parity,waits,flagbits=None,daa_input=None,event_context=None):
    """One public reset/BRKEM/test/RETEM lifetime, with literal owning byte groups."""
    nc,ec,ni,ei,ds,ss,es,sp,marker=(0x100,0x200,0x100,0x300,0x1000,0,0x30,0x800,0x700) if pop==0 else (0x300,0x400,0x500,0x700,0x3000,0x200,0x340,0xC00,0xD00)
    vals=PAIRS if pop==0 else PAIRS_H
    if op in UNCOND and vector==3:ei=(0xFFFE if pop==0 else 0xFFFC)+parity
    if op in COND and vector==15:ei=(0xFFFE if pop==0 else 0xFFFD)+parity
    if op==0 and vector==7:ei=0xFFFF if pop==0 else 0xFFFE
    flags=(status(vector&15)|((vector>>1)&0x10)) if flagbits is None else flagbits
    flags&=D5;incoming_if=0;event=0;point=0;irq=False;restart=0;reset_case=False
    ov=int(not predicate(op,flags)) if op in COND else (vector+pop)&1
    a=(0x5A+vector*17+(0x31 if pop else 0))&255
    g=[(0x1200 if pop==0 else 0xE100)|a,vals[vector%8],vals[(vector+3)%8],vals[(vector+5)%8],sp,(SP[vector%8]+parity)&65535,0x1357 if pop==0 else 0xAD31,0x2468 if pop==0 else 0x72C6]
    if event_context is not None:
        incoming_if=[0,1,0,1,0,1,0,1][event_context]
    if op==0x27:
        a,ac,cy=daa_input;g[0]=(g[0]&0xFF00)|a;flags=(flags&~0x11)|(ac<<4)|cy
    native=0xF002|flags|(int(ov)<<11)|(incoming_if<<9);entry=native&0x7FFF
    ef=flags;final=list(g);patch={};owned=[];reads=[];writes=[]
    def put(physical,value):
        physical&=0xFFFFF;assert 0<=value<=255
        assert physical not in patch or patch[physical]==value,(physical,patch.get(physical),value)
        patch[physical]=value
    def code(pc,data,execute=True):
        for i,b in enumerate(data):
            at=(pc+i)&65535;put(ec*16+at,b)
            if execute:owned.append([at,b])
    def memword(offset,value):
        for i,b in enumerate(word_bytes(value)):put(ds*16+((offset+i)&65535),b)
    def group(space,offset,value,width=2,phase=1,segment=None):
        seg=ds if segment is None else segment
        addresses=[((offset+i)&65535) if space else (seg*16+((offset+i)&65535))&0xFFFFF for i in range(width)]
        return {'space':space,'addresses':addresses,'bytes':word_bytes(value)[:width],'phase':phase}
    target=(0x520+vector*0x13) if pop==0 else (0x960+vector*0x17)
    if op==0xE9 and vector==7:target=0xFFFF if pop==0 else 0xFFFE
    bp=g[5];value=vals[vector%8];length=1;take=False;family=0
    # Stack-neighbor canaries are independent of expected target writes.
    for off,val in zip([bp-2,bp-1,bp,bp+1,bp+2,bp+3],[0xC7,0x58,0xA6,0x3D,0xE9,0x4B]):put(ds*16+(off&65535),val)
    def seedword(offset,val):
        # Replace the declared initial canary, never derive expected data from RAM.
        for i,b in enumerate(word_bytes(val)):patch[ds*16+((offset+i)&65535)]=b
    if op in COND or op in UNCOND:
        family=1;take=predicate(op,flags) if op in COND else True
        kind=op&7
        if op==0xC3:kind=2
        if op==0xCD:kind=4
        if op==0xC9:kind=0
        if kind in (2,4):length=3;code(ei,[op,*word_bytes(target)])
        else:code(ei,[op])
        if kind==7:target=op&0x38
        if kind==0:
            seedword(bp,target)
            if take:reads.append(group(0,bp,target));final[5]=(bp+2)&65535
        if take and kind in (4,7):
            final[5]=(bp-2)&65535;writes.append(group(0,final[5],(ei+length)&65535))
        end=target if take else (ei+length)&65535
        code(end,[0xED,0xFD])
        # Initialize the unexecuted alternate landing site too: stale-prefetch is observable.
        alternate=(ei+length)&65535 if take else target
        if alternate!=end:
            for i,b in enumerate([0xED,0xFD]):
                at=ec*16+((alternate+i)&65535)
                if at not in patch:put(at,b)
    elif op in STACK:
        family=2
        if op in (0xE9,0xF9):g[3]=target if op==0xE9 else value;final[3]=g[3]
        code(ei,[op]);end=target if op==0xE9 else ei+1
        if op in (0xC1,0xD1,0xE1):
            reg={0xC1:1,0xD1:2,0xE1:3}[op];seedword(bp,value);reads.append(group(0,bp,value));final[reg]=value;final[5]=(bp+2)&65535
        elif op in (0xC5,0xD5,0xE5):
            reg={0xC5:1,0xD5:2,0xE5:3}[op];final[5]=(bp-2)&65535;writes.append(group(0,final[5],g[reg]))
        elif op==0xE3:
            seedword(bp,value);reads.append(group(0,bp,value));writes.append(group(0,bp,g[3]));final[3]=value
        elif op==0xF9:final[5]=g[3]
        elif op==0xF1:
            psw_index=(pop*16+vector*2+parity)&31
            ef=((psw_index&16)<<3)|((psw_index&8)<<3)|((psw_index&4)<<2)|((psw_index&2)<<1)|(psw_index&1)
            packed=(value&0xFF00)|ef|([0,0x2A,0x08,0x20][vector%4])
            seedword(bp,packed);reads.append(group(0,bp,packed));final[0]=(g[0]&0xFF00)|(packed>>8);final[5]=(bp+2)&65535
        elif op==0xF5:
            final[5]=(bp-2)&65535;writes.append(group(0,final[5],((g[0]&255)<<8)|flags|2))
        code(end,[0xED,0xFD])
    elif op in (0xD3,0xDB):
        family=3;port=([0,1,0x7E,0x7F,0x80,0x81,0xFE,0xFF,0x12,0x13,0x54,0x55,0xAA,0xAB,0xC6,0xC7][vector])
        # Populations use disjoint port/data tuples, even when repeating boundary ports.
        data=(0xA5^(vector*23)^(0x6D if pop else 0))&255
        code(ei,[op,port]);end=ei+2
        if op==0xDB:reads.append(group(1,port,data,1));final[0]=(g[0]&0xFF00)|data
        else:writes.append(group(1,port,g[0]&255,1))
        code(end,[0xED,0xFD])
    elif op==0x27:
        family=4;result,ef=daa(*daa_input);final[0]=(g[0]&0xFF00)|result;code(ei,[op]);end=ei+1;code(end,[0xED,0xFD])
    elif op in (0xF3,0xFB):
        family=5;ctx=event_context
        event=[0,0,1,1,1,1,2,2][ctx];point=[0,0,1,1,2,3,2,3][ctx]
        final_if=int(op==0xFB)
        irq=event==2 or bool(event==1 and final_if)
        restart=ei+(2 if event==1 or point==3 else 1)
        # EI blocks INT until the immediately following single NOP finishes; NMI is independent.
        following=16 if event!=0 else 2
        code(ei,[op]+[0]*following);end=ei+1+following;code(end,[0xED,0xFD])
    elif op==0x76:
        family=6;ctx=event_context
        incoming_if=[0,1,0,1,0,1,0,1][ctx]
        native=(native&~0x200)|(incoming_if<<9);entry=native&0x7FFF
        event=[1,1,2,2,3,3,1,1][ctx];point=4;reset_case=event==3
        irq=event==2 or event==1 and bool(incoming_if);restart=ei+1
        code(ei,[op]);end=ei+1
        if event==1 and not irq:code(end,[0]*16);end+=16
        if not reset_case:code(end,[0xED,0xFD])
    else:
        family=7;assert op==0;code(ei,[op]);end=ei+1;code(end,[0xED,0xFD])
    end&=65535
    final_if=int(op==0xFB) if op in (0xF3,0xFB) else incoming_if
    expected_flags=ef|(final_if<<9)
    # Generate native preparation without a flag stack access: OF is seeded by AL arithmetic,
    # then SAHF restores every defined low flag; MOVs preserve OF/IF and all final canaries.
    packet=[]
    for v,m in ((ds,0xD8),(ss,0xD0),(es,0xC0)):packet += [0xB8,*word_bytes(v),0x8E,m]
    packet += [0xB0,0x7F,0x04,0x01] if ov else [0x30,0xC0]
    packet += [0xB4,flags|2,0x9E,0xFB if incoming_if else 0xFA]
    for reg in (4,5,1,2,3,6,7,0):packet += [0xB8+reg,*word_bytes(g[reg])]
    packet += [0x0F,0xFF,0x60];return_ip=ni+len(packet)
    packet += [0xA3,*word_bytes(marker),0xF4]
    assert len(packet)<=64
    frame=sp-6
    wr0=[group(0,frame+4,native,phase=0,segment=ss),group(0,frame+2,nc,phase=0,segment=ss),group(0,frame,return_ip,phase=0,segment=ss)]
    rd0=[group(0,0x180,ei,phase=0,segment=0),group(0,0x182,ec,phase=0,segment=0)]
    for at,val in ((0xFFFF0,0xEA),(0xFFFF1,ni&255),(0xFFFF2,ni>>8),(0xFFFF3,nc&255),(0xFFFF4,nc>>8),(0x180,ei&255),(0x181,ei>>8),(0x182,ec&255),(0x183,ec>>8)):put(at,val)
    if irq:
        isrcs=0x600 if pop==0 else 0x800;isrip=0x50 if pop==0 else 0x90
        vector_address=8 if event==2 else 0x80
        saved_ie=final_if
        saved_flags=(entry&~0x200)|(saved_ie<<9)
        irqwr=[group(0,frame-2,saved_flags,phase=2,segment=ss),group(0,frame-4,ec,phase=2,segment=ss),group(0,frame-6,restart,phase=2,segment=ss)]
        writes += irqwr
        reads += [group(0,vector_address,isrip,phase=2,segment=0),group(0,vector_address+2,isrcs,phase=2,segment=0)]
        reads += [group(0,frame-6,restart,phase=3,segment=ss),group(0,frame-4,ec,phase=3,segment=ss),group(0,frame-2,saved_flags,phase=3,segment=ss)]
        for off,val in ((vector_address,isrip),(vector_address+2,isrcs)):
            for i,b in enumerate(word_bytes(val)):put(off+i,b)
        put(isrcs*16+isrip,0xCF)
    if not reset_case:
        reads += [group(0,frame,return_ip,phase=4,segment=ss),group(0,frame+2,nc,phase=4,segment=ss),group(0,frame+4,native,phase=4,segment=ss)]
        writes += [group(0,marker,final[0],phase=5)]
    reads=rd0+reads;writes=wr0+writes
    for v in reads:
        v['requires_other_groups']=len(writes)-1 if v['phase']==4 else 6 if v['phase']==3 else 3 if v['phase'] in (1,2) else 0
    for v in writes:v['requires_other_groups']=len(reads) if v['phase']==5 else 3 if op==0xE3 and v['phase']==1 else 4 if v['phase']==2 else 2 if v['phase']==1 else 0
    assert len(owned)<=32 and len(patch)<=85 and len(reads)<=24 and len(writes)<=24
    c={'population':pop,'id':cid,'opcode':op,'form':FORMS.index(op),'family':family,'vector':vector,'parity':parity,'waits':waits,'flags':flags,'native_PSW':native,'entry_PSW':entry,'expected_flags':expected_flags,'expected_flags_mask':D5|0x200,'initial_GPR':g,'final_GPR':final,'native_SREG':[es,nc,ss,ds],'emu_SREG':[es,ec,ss,ds],'native_IP':ni,'emu_IP':ei,'native_return_IP':return_ip,'native_final_PC':return_ip+4,'frame_SP':frame,'pre_RETEM_PC':end,'owned_bytes':owned,'read_groups':reads,'write_groups':writes,'patches':sorted(patch.items()),'event':event,'event_point':point,'expected_IRQ':int(irq),'expected_INTA':2 if irq and event==1 else 0,'expected_reset':int(reset_case),'halt_cycles':32+16*(vector&1),'restart_PC':restart,'DAA_input':daa_input,'taken':take,'instruction_length':length,'native_packet':packet,'io_read_byte':data if op==0xDB else 0}
    # The key excludes population/id, wait-state timing and ignored canaries.
    if op==0x27:key=[op,*daa_input]
    elif op in (0xD3,0xDB):key=[op,port,data if op==0xDB else g[0]&255,flags]
    else:key=[op,ei,target,g[5],g[1],g[2],g[3],flags,incoming_if,event,point]
    c['effective_key']=key
    if op in (0xF3,0xFB) and irq:
        c['restart_PC_policy']='FROZEN_CURSOR_AT_IRQ_BOUNDARY'
        c['restart_PC']=0
        for gg in c['write_groups']+c['read_groups']:
            if (gg['phase']==2 and gg in c['write_groups'] and gg['addresses']==[ss*16+frame-6,ss*16+frame-5]) or (gg['phase']==3 and gg['addresses']==[ss*16+frame-6,ss*16+frame-5]):gg['bytes']=[0,0]
    if op==0:c['effective_key']=[op,ei,flags,incoming_if]
    c['halt_resume_PC']=(ei+1)&65535 if op==0x76 else 0
    c['word_boundary_inferred']=any(v['space']==0 and v['phase']==1 and len(v['addresses'])==2 and v['addresses'][1]<v['addresses'][0] for v in reads+writes)
    return c


def populations():
    pops=[]
    for pop in (0,1):
        cases=[]
        def add(op,v,p,w,**kw):cases.append(make_case(pop,len(cases),op,v,p,w,**kw))
        for op in COND:
            for fl in range(16):
                for p in (0,1):
                    for w in (0,1,3):add(op,fl,p,w,flagbits=status(fl))
        for op in UNCOND:
            for v in range(4):
                for p in (0,1):
                    for w in (0,1,3):add(op,v,p,w)
        for op in STACK:
            for v in range(8):
                for p in (0,1):
                    for w in (0,1,3):add(op,v,p,w)
        for op in (0xD3,0xDB):
            for v in range(16):
                for w in (0,1,3):add(op,v,0,w)
        for op in (0xF3,0xFB,0,0x76):
            for v in range(8):
                for w in (0,1,3):add(op,v,v&1,w,event_context=v)
        for a in range(256):
            for ac in (0,1):
                for cy in (0,1):
                    if (a^ac^cy).bit_count()%2==pop:
                        for w in (0,1,3):add(0x27,a,0,w,daa_input=(a,ac,cy))
        assert len(cases)==4824
        pops.append(cases)
    return pops


def interactions(pop):
    cases=[]
    labels=['CALL_RET','RST_RET','NESTED_CALL_RET','PUSH_B_POP_D','PSW_POP_B',
            'XTHL_TWICE','SPHL_PUSH_POP','PCHL_REDIRECT','IN_ADI_OUT','EI_DI_HALT_MASKED',
            'BCD_ADD_DAA','BCD_ADC_DAA']
    for idx,label in enumerate(labels):
        base=make_case(pop,idx,0x76 if idx==9 else 0x27 if idx>=10 else 0,idx,idx&1,1,
                       daa_input=(0x45 if pop==0 else 0x27,0,idx&1) if idx>=10 else None,
                       event_context=0 if idx==9 else None)
        patches=dict(base['patches']);ec=base['emu_SREG'][1];ds=base['native_SREG'][3]
        for pc,b in base['owned_bytes']:patches.pop(ec*16+pc,None)
        owned=[];reads=[v for v in base['read_groups'] if v['phase']==0]
        writes=[v for v in base['write_groups'] if v['phase']==0]
        marker=next(v for v in base['write_groups'] if v['phase']==5)
        retreads=[v for v in base['read_groups'] if v['phase']==4]
        g=base['initial_GPR'];f=list(g);flags=base['flags'];ei=base['emu_IP'];bp=g[5];t=(ei+0x40)&65535;u=(ei+0x60)&65535
        def ins(pc,bs):
            for i,b in enumerate(bs):patches[ec*16+((pc+i)&65535)]=b;owned.append([(pc+i)&65535,b])
        def grp(off,value,phase=1,space=0,width=2):
            return {'space':space,'addresses':[((off+i)&65535) if space else ds*16+((off+i)&65535) for i in range(width)],'bytes':word_bytes(value)[:width],'phase':phase}
        def seed(off,val):
            for i,b in enumerate(word_bytes(val)):patches[ds*16+((off+i)&65535)]=b
        end=ei+1
        if idx==0:
            base['opcode']=0xCD;ins(ei,[0xCD,*word_bytes(t)]);ins(t,[0xC9]);end=ei+3
            writes.append(grp(bp-2,end));reads.append(grp(bp-2,end))
        elif idx==1:
            base['opcode']=0xCF;ins(ei,[0xCF]);ins(8,[0xC9]);end=ei+1
            writes.append(grp(bp-2,end));reads.append(grp(bp-2,end))
        elif idx==2:
            base['opcode']=0xCD;ins(ei,[0xCD,*word_bytes(t)]);ins(t,[0xCD,*word_bytes(u)]);ins(u,[0xC9]);ins(t+3,[0xC9]);end=ei+3
            writes += [grp(bp-2,end),grp(bp-4,t+3)];reads += [grp(bp-4,t+3),grp(bp-2,end)]
        elif idx==3:
            base['opcode']=0xC5;ins(ei,[0xC5,0xD1]);end=ei+2;f[2]=g[1]
            writes.append(grp(bp-2,g[1]));reads.append(grp(bp-2,g[1]))
        elif idx==4:
            base['opcode']=0xF5;ins(ei,[0xF5,0xC1]);end=ei+2;packed=((g[0]&255)<<8)|flags|2;f[1]=packed
            writes.append(grp(bp-2,packed));reads.append(grp(bp-2,packed))
        elif idx==5:
            base['opcode']=0xE3;ins(ei,[0xE3,0xE3]);end=ei+2;value=0xB6C9 if pop==0 else 0x294E;seed(bp,value)
            reads += [grp(bp,value),grp(bp,g[3])];writes += [grp(bp,g[3]),grp(bp,value)]
        elif idx==6:
            base['opcode']=0xF9;ins(ei,[0xF9,0xC5,0xC1]);end=ei+3;f[5]=g[3]
            writes.append(grp(g[3]-2,g[1]));reads.append(grp(g[3]-2,g[1]))
        elif idx==7:
            base['opcode']=0xE9;g[3]=t;f[3]=t;ins(ei,[0xE9]);end=t
        elif idx==8:
            base['opcode']=0xDB;port=0x32 if pop==0 else 0x65;outport=port+2;value=0x47 if pop==0 else 0xA6;imm=0x39 if pop==0 else 0x71
            ins(ei,[0xDB,port,0xC6,imm,0xD3,outport]);end=ei+6
            total=value+imm;result=total&255;flags=szp(result)|(0x10 if (value&15)+(imm&15)>15 else 0)|(1 if total>255 else 0);f[0]=(g[0]&0xFF00)|result
            base['io_read_byte']=value;reads.append(grp(port,value,space=1,width=1));writes.append(grp(outport,result,space=1,width=1))
        elif idx==9:
            base['opcode']=0x76;ins(ei,[0xFB,0,0xF3,0x76]+[0]*16);end=ei+20;base['halt_resume_PC']=ei+4
        else:
            base['opcode']=0x27;g[1]=0x3834 if pop==0 else 0x4619;f[1]=g[1]
            operand=(g[1]>>8) if idx==10 else (g[1]&255);cy=base['flags']&1 if idx==11 else 0;a=g[0]&255
            total=a+operand+cy;raw=total&255;ac=int((a&15)+(operand&15)+cy>15)
            result,flags=daa(raw,ac,int(total>255));f[0]=(g[0]&0xFF00)|result
            ins(ei,[0x80 if idx==10 else 0x89,0x27]);end=ei+2
        end&=65535;ins(end,[0xED,0xFD]);base['pre_RETEM_PC']=end;base['owned_bytes']=owned
        # Re-encode the eight literal MOV register immediates in the unchanged native packet layout.
        packet=base['native_packet'];start=len(packet)-31
        for i,reg in enumerate((4,5,1,2,3,6,7,0)):
            assert packet[start+i*3]==0xB8+reg;packet[start+i*3+1:start+i*3+3]=word_bytes(g[reg])
        marker=dict(marker);marker['bytes']=word_bytes(f[0]);writes.append(marker);reads+=retreads
        base.update(population=pop+2,id=idx,form=FORMS.index(base['opcode']),family=8,final_GPR=f,
                    expected_flags=flags,patches=sorted(patches.items()),read_groups=reads,write_groups=writes,
                    interaction=label,effective_key=[base['opcode'],ei,label,*g,base['flags']])
        for j,v in enumerate(reads):v['requires_other_groups']=len(writes)-1 if v['phase']==4 else (4 if idx==5 and j==3 else 3) if v['phase']==1 else 0
        for j,v in enumerate(writes):v['requires_other_groups']=len(reads) if v['phase']==5 else (4 if j==4 else 3) if idx==5 and v['phase']==1 else 2 if v['phase']==1 else 0
        base['word_boundary_inferred']=any(v['space']==0 and v['phase']==1 and len(v['addresses'])==2 and v['addresses'][1]<v['addresses'][0] for v in reads+writes)
        assert len(patches)<=85 and len(owned)<=32
        cases.append(base)
    return cases


def record(c):
    """One 2KiB record selected before process launch; no whole-population read."""
    g=c['initial_GPR'];s=c['native_SREG'];ec=c['emu_SREG'][1]
    words=[0]*1024
    words[:38]=[0xF053,1,c['population'],c['id'],c['opcode'],c['family'],c['waits'],c['event'],c['event_point'],c['expected_IRQ'],c['expected_INTA'],c['expected_reset'],c['native_IP'],c['emu_IP'],s[1],ec,s[3],s[2],s[0],g[4],c['frame_SP'],c['native_PSW'],c['entry_PSW'],c['expected_flags_mask'],c['expected_flags'],c['pre_RETEM_PC'],len(c['owned_bytes']),len(c['read_groups']),len(c['write_groups']),len(c['patches']),len(c['native_packet']),c['native_return_IP'],c['native_return_IP']+3,c['native_final_PC'],c['halt_cycles'],c['restart_PC'],c['io_read_byte'],int(bool(c['native_PSW']&0x200))]
    words[40:48]=g;words[48:56]=c['final_GPR'];words[56:60]=s;words[60:64]=c['emu_SREG'];words[64:64+len(c['native_packet'])]=c['native_packet']
    words[38]=c['halt_resume_PC'];words[39]=int(c['word_boundary_inferred'])
    for i,(pc,b) in enumerate(c['owned_bytes']):words[128+i*2:130+i*2]=[pc,b]
    for i,(addr,b) in enumerate(c['patches']):words[192+i*3:195+i*3]=[addr&65535,addr>>16,b]
    for base,kind in ((448,'read_groups'),(672,'write_groups')):
        for i,v in enumerate(c[kind]):
            adr=v['addresses']+[0];val=v['bytes']+[0]
            words[base+i*9:base+i*9+9]=[v['space'],adr[0]&65535,adr[0]>>16,adr[1]&65535,adr[1]>>16,val[0],val[1],len(v['bytes']),v['phase']|(v.get('requires_other_groups',0)<<8)]
    words[1023]=0xF35A;assert all(0<=w<=65535 for w in words)
    return ''.join('%04x'%w for w in reversed(words))+'\n'
