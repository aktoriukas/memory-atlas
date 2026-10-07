#!/usr/bin/env python3
"""Memory Atlas local bridge. stdout is JSON; no listener or cloud service."""
import unicodedata, datetime, fcntl, hashlib, json, os, pathlib, re, shutil, sqlite3, subprocess, sys, tempfile, time, urllib.request, uuid

HOME = pathlib.Path.home()
STATE = HOME / 'Library/Application Support/Memory Atlas'
FIELDS = {'observation': ['title', 'subtitle', 'narrative', 'text', 'facts', 'concepts', 'files_read', 'files_modified'], 'summary': ['request', 'investigated', 'learned', 'completed', 'next_steps', 'notes']}
TABLES = {'observation': 'observations', 'summary': 'session_summaries'}
LISTS = {'facts', 'concepts', 'files_read', 'files_modified'}

def settings():
    path = HOME / '.claude-mem/settings.json'
    raw = json.loads(path.read_text()) if path.exists() else {}
    return raw.get('env', raw)

def data_dir():
    return pathlib.Path(os.path.expanduser(os.environ.get('CLAUDE_MEM_DATA_DIR') or settings().get('CLAUDE_MEM_DATA_DIR') or str(HOME / '.claude-mem')))

def db_path(): return data_dir() / 'claude-mem.db'

def connect(write=False, path=None):
    path = path or db_path()
    if not write and not pathlib.Path(path).is_file():raise ValueError('No claude-mem database found. Install and run claude-mem first; see the README installation guide.')
    c = sqlite3.connect(str(path) if write else 'file:' + str(path) + '?mode=ro', uri=not write, timeout=10)
    c.row_factory = sqlite3.Row
    c.execute('PRAGMA busy_timeout=10000')
    c.execute('PRAGMA foreign_keys=ON')
    return c

def api(path, body=None):
    port = int(settings().get('CLAUDE_MEM_WORKER_PORT') or 37777)
    url = f'http://127.0.0.1:{port}{path}'
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None, headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=12) as response: return json.load(response)

def soft_api(path):
    try: return api(path)
    except Exception as e: return {'error': str(e)}

def atomic(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temp = path.with_suffix('.tmp-' + uuid.uuid4().hex)
    with open(temp, 'x') as f:
        os.chmod(temp, 0o600)
        json.dump(value, f, ensure_ascii=False, indent=2); f.flush(); os.fsync(f.fileno())
    os.replace(temp, path)
    fd = os.open(path.parent, os.O_RDONLY)
    try: os.fsync(fd)
    finally: os.close(fd)

def list_value(raw):
    if isinstance(raw, list): return [str(v) for v in raw if isinstance(v, str) and v.strip()]
    if not raw: return []
    try:
        value = json.loads(raw)
        if isinstance(value, list): return [str(v) for v in value if isinstance(v, str) and v.strip()]
        if isinstance(value, str): return [value] if value.strip() else []
    except (ValueError, TypeError): pass
    return [str(raw)]

def fingerprint(row, kind):
    # Include provenance and reinforcement fields: never silently overwrite a changed row.
    return hashlib.sha256(json.dumps(dict(row), sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()

def record(c, kind, ident):
    if kind not in TABLES: raise ValueError('Unsupported memory type')
    row = c.execute(f'SELECT * FROM {TABLES[kind]} WHERE id=?', (int(ident),)).fetchone()
    if row is None: raise ValueError('Memory no longer exists')
    return dict(row)

def presented(c, row, kind):
    r = dict(row)
    source = c.execute("SELECT COALESCE(platform_source,'claude') FROM sdk_sessions WHERE memory_session_id=? LIMIT 1", (r['memory_session_id'],)).fetchone()
    r.update(kind=kind, key=f'{kind}:{r["id"]}', source=source[0] if source else 'claude', fingerprint=fingerprint(row, kind))
    r['display_title'] = r.get('title') or r.get('request') or 'Untitled memory'
    for key in LISTS: r[key] = list_value(r.get(key))
    return r

def where_clause(args, kind):
    clauses=[]; values=[]
    if args.get('project'):
        clauses.append('(m.project=? OR m.merged_into_project=?)'); values += [args['project']] * 2
    if args.get('source'):
        clauses.append("EXISTS(SELECT 1 FROM sdk_sessions s WHERE s.memory_session_id=m.memory_session_id AND COALESCE(s.platform_source,'claude')=?)");values.append(args['source'])
    if args.get('query'):
        # Plain text substring search accepts arbitrary user input without FTS syntax errors.
        cols = FIELDS[kind]
        clauses.append('('+' OR '.join(f"COALESCE(m.{col},'') LIKE ? ESCAPE '\\'" for col in cols)+')')
        q=args['query'].replace('\\','\\\\').replace('%','\\%').replace('_','\\_')
        values += ['%'+q+'%'] * len(cols)
    if args.get('days'):
        clauses.append('m.created_at_epoch >= ?'); values.append(int((time.time()-int(args['days'])*86400)*1000))
    return (' WHERE '+' AND '.join(clauses) if clauses else ''),values

def memories(args, unlimited=False):
    out=[]
    with connect() as c:
        c.execute("BEGIN")
        for kind, table in TABLES.items():
            if args.get('kind') and args['kind'] != kind: continue
            where, vals=where_clause(args,kind)
            rows=c.execute(f'SELECT m.* FROM {table} m{where} ORDER BY created_at_epoch DESC'+('' if unlimited else ' LIMIT ?'), vals+([] if unlimited else [int(args.get('limit',100))+int(args.get('offset',0))])).fetchall()
            out.extend(presented(c,r,kind) for r in rows)
    out.sort(key=lambda r:r['created_at_epoch'],reverse=True)
    if unlimited:return out
    start=int(args.get('offset',0));return out[start:start+int(args.get('limit',100))]

def metadata():
    with connect() as c:
        counts={kind:c.execute(f'SELECT count(*) FROM {table}').fetchone()[0] for kind,table in TABLES.items()}
        projects=[dict(r) for r in c.execute('SELECT project,count(*) count FROM (SELECT COALESCE(merged_into_project,project) project FROM observations UNION ALL SELECT COALESCE(merged_into_project,project) project FROM session_summaries) GROUP BY project ORDER BY count DESC')]
        sources=[dict(r) for r in c.execute("SELECT COALESCE(s.platform_source,'claude') source,count(*) count FROM (SELECT memory_session_id FROM observations UNION ALL SELECT memory_session_id FROM session_summaries) o LEFT JOIN sdk_sessions s ON s.memory_session_id=o.memory_session_id GROUP BY source")]
        activity=[dict(r) for r in c.execute("SELECT date(created_at_epoch/1000,'unixepoch') day,count(*) count FROM (SELECT created_at_epoch FROM observations UNION ALL SELECT created_at_epoch FROM session_summaries) WHERE created_at_epoch > ? GROUP BY day ORDER BY day",(int((time.time()-30*86400)*1000),))]
        counts['sessions']=c.execute('SELECT count(*) FROM sdk_sessions').fetchone()[0]
        counts['prompts']=c.execute('SELECT count(*) FROM user_prompts').fetchone()[0]
    health=soft_api('/api/health'); provider=health.get('ai',{}).get('provider')
    cooldown=data_dir()/'quota-cooldown.json'
    quotas=json.loads(cooldown.read_text()) if cooldown.exists() else []
    configured=settings();provider=configured.get('CLAUDE_MEM_PROVIDER','claude')
    effective_model=configured.get({'codex':'CLAUDE_MEM_CODEX_MODEL','claude':'CLAUDE_MEM_MODEL','gemini':'CLAUDE_MEM_GEMINI_MODEL','openrouter':'CLAUDE_MEM_OPENROUTER_MODEL','openai-compatible':'CLAUDE_MEM_OPENAI_COMPAT_MODEL'}.get(provider,''),'')
    if provider=='codex' and not effective_model:
        path=HOME/'.codex/config.toml'
        if path.exists():
            match=re.search(r'^model\s*=\s*"([^"\n]+)"',path.read_text(),re.MULTILINE)
            if match:effective_model=match[1]+' (CLI default)'
    return {'effective_model':effective_model or 'Provider default','counts':counts,'projects':projects,'sources':sources,'activity':activity,'bytes':db_path().stat().st_size,'health':health,'processing':soft_api('/api/processing-status'),'chroma':soft_api('/api/chroma/status'),'data_dir':str(data_dir()),'revisions':revisions(),'pending':pending(),'cooldowns':[q for q in quotas if q.get('provider')==provider]}

def links():
    p=STATE/'links.json';return json.loads(p.read_text()) if p.exists() else []

def graph(args):
    # ponytail: 240 memory nodes; narrow filters before adding neighborhood expansion.
    rows=memories(dict(args,limit=241,offset=0))
    nodes=[];edges=[];hubs={};entity_usage={}
    if not any(args.get(k) for k in ['project','query','source','kind','days']):
        with connect() as c:
            projects=c.execute('SELECT project,count(*) count FROM (SELECT project FROM observations UNION ALL SELECT project FROM session_summaries) GROUP BY project ORDER BY count DESC').fetchall()
        return {'nodes':[{'id':'project:'+p['project'],'label':p['project'],'type':'project','count':p['count']} for p in projects],'edges':[], 'limited':False, 'overview':True}
    for r in rows[:240]:
        key=r['key'];nodes.append({'id':key,'label':r['display_title'],'type':'summary' if r['kind']=='summary' else 'memory','count':1})
        entities=[('project',r.get('merged_into_project') or r['project'])]+[('concept',v) for v in r.get('concepts',[])]+[('file',v) for v in set(r.get('files_read',[])+r.get('files_modified',[]))]
        for typ,value in entities:
            if not value:continue
            ident=typ+':'+value
            hubs[ident]={'id':ident,'label':value.split('/')[-1] if typ=='file' else value,'type':typ,'count':0}
            entity_usage[ident]=entity_usage.get(ident,0)+1;edges.append({'from':key,'to':ident,'manual':False})
    keep=set(sorted(hubs,key=lambda k:entity_usage[k],reverse=True)[:45])
    for ident in sorted(keep):hubs[ident]['count']=entity_usage[ident];nodes.append(hubs[ident])
    ids={n['id'] for n in nodes};edges=[e for e in edges if e['to'] in keep]
    edges += [dict(e,manual=True) for e in links() if e['from'] in ids and e['to'] in ids]
    return {'nodes':nodes,'edges':edges,'limited':len(rows)>240,'overview':False}

def revisions(limit=100):
    root=STATE/'revisions'
    return sorted([{'file':p.name,**{k:d.get(k) for k in ['kind','id','title','time','status']}} for p in root.glob('*.json') if (d:=json.loads(p.read_text()))],key=lambda r:r['time'] or '',reverse=True)[:limit]

def pending(): return [r for r in revisions(None) if r['status'] not in ['complete','rolled_back','undone']]

def worker_script():
    paths=[]
    for base in [HOME/'.claude/plugins/cache/thedotmack/claude-mem', HOME/'.codex/plugins/cache/claude-mem-local/claude-mem']:
        for p in base.glob('*/scripts/worker-service.cjs'):
            try:version=tuple(int(x) for x in p.parents[1].name.split('.'))
            except ValueError:continue
            paths.append((version,p))
    if not paths:raise RuntimeError('claude-mem installation not found')
    return max(paths,key=lambda x:x[0])[1]

def worker(action):
    bun=next((p for p in [HOME/'.bun/bin/bun',pathlib.Path('/opt/homebrew/bin/bun'),pathlib.Path('/usr/local/bin/bun')] if p.is_file() and os.access(p,os.X_OK)),None)
    if bun is None:raise RuntimeError('Bun runtime not found. Install Bun and relaunch Atlas.')
    result=subprocess.run([str(bun),str(worker_script()),action],capture_output=True,text=True,timeout=65,env=dict(os.environ,CLAUDE_MEM_INTERNAL='1'))
    if result.returncode:raise RuntimeError('Worker '+action+' failed: '+result.stderr[-500:])
    if action=='start':
        deadline=time.monotonic()+30
        while time.monotonic()<deadline:
            health=soft_api('/api/health')
            if health.get('status')=='ok' and health.get('initialized'):return
            time.sleep(0.4)
        raise RuntimeError('Worker started but is not ready yet. Atlas will reconnect automatically.')

def chroma_python():
    # Reuse the installed chroma-mcp environment; no dependency installation during a save.
    candidates=sorted((HOME/'.cache/uv').glob('archive-v0/*/bin/chroma-mcp'),key=lambda p:p.stat().st_mtime,reverse=True)
    for script in candidates:
        interpreter=script.parent/'python'
        if interpreter.exists():
            test=subprocess.run([str(interpreter),'-c','import chromadb'],capture_output=True,timeout=20)
            if test.returncode==0:return interpreter
    raise RuntimeError('Installed Chroma Python environment unavailable. Run claude-mem repair.')

def mutate(args):
    STATE.mkdir(parents=True,exist_ok=True,mode=0o700)
    with open(STATE/'maintenance.lock','a') as f:
        fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)
        py=chroma_python()
        health=soft_api('/api/health')
        version=health.get('version') or worker_script().parents[1].name
        if version!='13.29.0':raise RuntimeError('Editing supports claude-mem 13.29.0; review compatibility before editing this version.')
        if settings().get('CLAUDE_MEM_CHROMA_EMBEDDING_FUNCTION','default')!='default':raise RuntimeError('Editing currently supports the default local embedding function only')
        if settings().get('CLAUDE_MEM_CLOUD_SYNC_TOKEN') or settings().get('CLAUDE_MEM_CHROMA_MODE','local')=='remote':raise RuntimeError('Editing currently requires local-only memory and local Chroma.')
        args=dict(args,_owner='memory-atlas:'+uuid.uuid4().hex)
        lock=data_dir()/'chroma/.claude-mem-chroma-writer.lock'
        worker('stop')
        try:
            child=subprocess.Popen([str(py),str(pathlib.Path(__file__).resolve()),'maintenance'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=dict(os.environ,CLAUDE_MEM_INTERNAL='1',ANONYMIZED_TELEMETRY='False'))
            try:stdout,stderr=child.communicate(json.dumps(args),timeout=180)
            except subprocess.TimeoutExpired:
                child.kill();child.communicate();raise RuntimeError('Editing timed out; recover the interrupted edit from History.')
            response=json.loads(stdout) if stdout.strip() else {'error':stderr[-1000:] or 'Maintenance helper failed'}
            if child.returncode or response.get('error'):raise RuntimeError(response.get('error','Maintenance failed'))
            return response
        finally:
            # Release only after the Chroma process has exited and closed all handles.
            if lock.exists() and json.loads(lock.read_text()).get('ownerId')==args['_owner']:lock.unlink()
            if not pending():worker('start')


def vector_documents(row,kind,source):
    meta={'sqlite_id':row['id'],'doc_type':'observation' if kind=='observation' else 'session_summary','memory_session_id':row['memory_session_id'],'project':row['project'],'platform_source':source,'created_at_epoch':row['created_at_epoch']}
    if row.get('merged_into_project'):meta['merged_into_project']=row['merged_into_project']
    docs=[]
    if kind=='observation':
        meta.update(type=row.get('type') or 'discovery',title=row.get('title') or 'Untitled')
        if row.get('subtitle'):meta['subtitle']=row['subtitle']
        for key in ['concepts','files_read','files_modified']:
            val=list_value(row.get(key))
            if val:meta[key]=','.join(val)
        for key in ['narrative','text']:
            if row.get(key):docs.append((f'obs_{row["id"]}_{key}',row[key],dict(meta,field_type=key)))
        for i,fact in enumerate(list_value(row.get('facts'))):docs.append((f'obs_{row["id"]}_fact_{i}',fact,dict(meta,field_type='fact',fact_index=i)))
    else:
        meta['prompt_number']=row.get('prompt_number') or 0
        for key in FIELDS['summary']:
            if row.get(key):docs.append((f'summary_{row["id"]}_{key}',row[key],dict(meta,field_type=key)))
    return docs

def vector_snapshot(collection,ident,kind):
    result=collection.get(where={'$and':[{'sqlite_id':int(ident)},{'doc_type':'observation' if kind=='observation' else 'session_summary'}]},include=['documents','metadatas','embeddings'])
    return {k:(v.tolist() if hasattr(v,'tolist') else v) for k,v in result.items() if k in ['ids','documents','metadatas','embeddings']}

def reconcile(collection,row,kind,source):
    old=vector_snapshot(collection,row['id'],kind)
    docs=vector_documents(row,kind,source)
    if docs:collection.upsert(ids=[d[0] for d in docs],documents=[d[1] for d in docs],metadatas=[d[2] for d in docs])
    obsolete=set(old['ids'])-{d[0] for d in docs}
    if obsolete:collection.delete(ids=sorted(obsolete))
    current=vector_snapshot(collection,row['id'],kind)
    actual=dict(zip(current['ids'],current['documents']))
    metadata=dict(zip(current['ids'],current['metadatas']))
    if actual!={d[0]:d[1] for d in docs} or metadata!={d[0]:d[2] for d in docs}:raise RuntimeError('Vector verification failed')

def restore_vectors(collection,snapshot,ident,kind):
    current=vector_snapshot(collection,ident,kind)
    if snapshot['ids']:collection.upsert(**snapshot)
    removed=set(current['ids'])-set(snapshot['ids'])
    if removed:collection.delete(ids=sorted(removed))

def write_fields(c,row,kind):
    fields=[f for f in FIELDS[kind] if f in row]
    if kind=='observation':fields += ['content_hash','title_norm_key']
    c.execute(f'UPDATE {TABLES[kind]} SET '+','.join(f'{key}=?' for key in fields)+' WHERE id=?',[row.get(k) for k in fields]+[row['id']])

def maintenance(args):
    import chromadb
    chroma_dir=data_dir()/'chroma';lock=chroma_dir/'.claude-mem-chroma-writer.lock'
    owner={'pid':os.getpid(),'ownerId':args.get('_owner','memory-atlas:'+uuid.uuid4().hex),'dataDir':str(chroma_dir),'acquiredAt':datetime.datetime.now(datetime.timezone.utc).isoformat()}
    token=subprocess.check_output(['ps','-p',str(os.getpid()),'-o','lstart='],text=True).strip();owner['startToken']=token
    # Never reap somebody else's lock. claude-mem's normal stop must release it first.
    if lock.exists():
        previous=lock.read_text();old=json.loads(previous)
        try:
            actual=subprocess.check_output(['ps','-p',str(int(old['pid'])),'-o','lstart='],text=True,stderr=subprocess.DEVNULL).strip()
        except subprocess.CalledProcessError:actual=''
        if actual and (not old.get('startToken') or actual==old['startToken']):raise RuntimeError('Another live process owns the Chroma writer lock')
        if lock.read_text()!=previous:raise RuntimeError('The Chroma writer lock changed; try again')
        lock.unlink()
    fd=os.open(lock,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as f:json.dump(owner,f);f.flush();os.fsync(f.fileno())
    try:
        client=chromadb.PersistentClient(path=str(chroma_dir),settings=chromadb.Settings(anonymized_telemetry=False))
        collections=client.list_collections()
        if len(collections)!=1:raise RuntimeError('Expected one claude-mem vector collection; refusing ambiguous edits')
        collection=client.get_collection(collections[0].name)
        with connect(write=True) as c:
            if args['op']=='recover':
                for item in pending():
                    p=STATE/'revisions'/item['file'];j=json.loads(p.read_text())
                    c.execute('BEGIN IMMEDIATE')
                    current=record(c,j['kind'],j['id'])
                    if not any(all(current.get(k)==candidate.get(k) for k in FIELDS[j['kind']]) for candidate in [j['before'],j['after']]):
                        c.rollback();raise RuntimeError('Content changed after the interrupted edit; manual recovery is required to preserve later changes')
                    restore_vectors(collection,j['vectors'],j['id'],j['kind'])
                    write_fields(c,j['before'],j['kind']);c.commit()
                    j['status']='rolled_back';atomic(p,j)
                return {'message':'Interrupted edits recovered'}
            if pending():raise RuntimeError('Recover the interrupted edit before saving another memory')
            kind=args['kind'];before=record(c,kind,args['id'])
            if before.get('origin_device_id'):raise RuntimeError('Remote memories cannot be edited by this local adapter')
            if c.execute('SELECT 1 FROM sync_entity_heads WHERE kind=? AND origin_local_id=? LIMIT 1',('observation' if kind=='observation' else 'summary',str(before['id']))).fetchone():raise RuntimeError('This memory has cloud-sync history; editing is blocked to preserve replicas')
            if fingerprint(before,kind)!=args['fingerprint']:raise RuntimeError('This memory changed while open. Reload before saving.')
            trigger=c.execute("SELECT sql FROM sqlite_master WHERE type='trigger' AND tbl_name=? AND sql LIKE '%AFTER UPDATE%'",(TABLES[kind],)).fetchall()
            if not any('_fts' in r[0] for r in trigger):raise RuntimeError('Required full-text update trigger is missing')
            after=dict(before)
            changes=args.get('changes',{})
            if not changes or set(changes)-set(FIELDS[kind]):raise ValueError('Only memory content fields can be edited')
            for key,value in changes.items():
                if key in LISTS:
                    if not isinstance(value,list) or any(not isinstance(v,str) for v in value):raise ValueError(key+' must be a list of text values')
                    value=json.dumps([v.strip() for v in value if v.strip()],ensure_ascii=False)
                if not isinstance(value,str) or len(value)>1_000_000:raise ValueError('Invalid field: '+key)
                after[key]=value
            if kind=='observation':
                if not (after.get('title') or '').strip():raise ValueError('A title is required')
                after['content_hash']=hashlib.sha256('\0'.join([after['memory_session_id'] or '',after.get('title') or '',after.get('narrative') or '']).encode()).hexdigest()[:16]
                normalized=' '.join(''.join(ch if ch.isspace() or unicodedata.category(ch)[0] in 'LN' else ' ' for ch in after['title'].lower()).split())
                source=presented(c,before,kind)['source']
                agent='subagent' if before.get('agent_id') and before.get('agent_type') else 'main'
                after['title_norm_key']=hashlib.sha256('\0'.join([after['project'],source,agent,normalized]).encode()).hexdigest()[:32] if normalized else None
            source=presented(c,before,kind)['source'];snapshot=vector_snapshot(collection,before['id'],kind)
            stamp=datetime.datetime.now(datetime.timezone.utc).isoformat();name=time.strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:8]
            backup=STATE/'backups'/f'{name}.db';backup.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
            with connect() as src,sqlite3.connect(backup) as dst:src.backup(dst)
            os.chmod(backup,0o600)
            journal={'kind':kind,'id':before['id'],'title':after.get('title') or after.get('request'),'time':stamp,'before':before,'after':after,'vectors':snapshot,'status':'prepared','backup':str(backup)}
            path=STATE/'revisions'/f'{name}.json';atomic(path,journal)
            committed=False
            try:
                c.execute('BEGIN IMMEDIATE')
                if fingerprint(record(c,kind,before['id']),kind)!=args['fingerprint']:raise RuntimeError('Concurrent edit detected')
                write_fields(c,after,kind)
                # Hold SQLite's write transaction while vectors change; hook-driven restarts cannot race this row.
                reconcile(collection,after,kind,source)
                c.commit();committed=True
                journal['status']='complete';atomic(path,journal)
            except Exception:
                c.rollback()
                if committed:
                    with c:write_fields(c,before,kind)
                restore_vectors(collection,snapshot,before['id'],kind)
                journal['status']='rolled_back';atomic(path,journal)
                raise
            # ponytail: retain three full database snapshots; every row revision remains available for undo.
            protected={json.loads((STATE/'revisions'/r['file']).read_text()).get('backup') for r in pending()}
            for old in sorted((STATE/'backups').glob('*.db'),reverse=True)[3:]:
                if str(old) not in protected:old.unlink()
            return {'message':'Memory saved; text and semantic indexes verified','revision':path.name}
    finally:
        pass  # Parent releases the writer lock only after this process exits.

def export_data(args):
    destination=pathlib.Path(args['destination']).expanduser()
    if not destination.is_dir():raise ValueError('Choose an existing export directory')
    folder=destination/('Memory Atlas '+time.strftime('%Y-%m-%d %H-%M-%S')+' '+uuid.uuid4().hex[:4]);folder.mkdir(mode=0o700)
    rows=memories(args,unlimited=True);all_links=links()
    archive={'format':'memory-atlas/1','exported_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'memories':rows,'links':all_links}
    atomic(folder/'memories.json',archive)
    if args.get('format')=='markdown':
        names={r['key']:r['kind']+'-'+str(r['id']) for r in rows}
        for r in rows:
            front={k:r.get(k) for k in ['id','kind','project','source','created_at','concepts','files_read','files_modified']}
            front['tags']=['concept/'+re.sub(r'[^\w/-]','-',v) for v in r.get('concepts',[])]
            hub='project-'+hashlib.sha256(r['project'].encode()).hexdigest()[:12]

            content='---\n'+'\n'.join(k+': '+json.dumps(v,ensure_ascii=False) for k,v in front.items())+'\n---\n\n# '+r['display_title'].replace('\n',' ')+'\n'
            content+='\nProject: [['+hub+']]\n'
            for key in FIELDS[r['kind']]:
                val=r.get(key)
                if val:content+='\n## '+key.replace('_',' ').title()+'\n\n'+('\n'.join('- '+v for v in val) if isinstance(val,list) else val)+'\n'
            related=[e['to'] if e['from']==r['key'] else e['from'] for e in all_links if r['key'] in [e['from'],e['to']]]
            if related:content+='\n## Linked memories\n\n'+'\n'.join('- [['+names[k]+']]' for k in related if k in names)+'\n'
            (folder/(names[r['key']]+'.md')).write_text(content)
        for project in {r['project'] for r in rows}:
            hub='project-'+hashlib.sha256(project.encode()).hexdigest()[:12]
            (folder/(hub+'.md')).write_text('# '+project+'\n\n'+'\n'.join('- [['+names[r['key']]+']]' for r in rows if r['project']==project))
        (folder/'README.md').write_text('# Memory Atlas export\n\nOpen this folder as an Obsidian vault. Shared concept tags and manual wiki links connect memories. `memories.json` contains the complete exported records.\n')
    return {'message':f'Exported {len(rows):,} memories','path':str(folder)}

def main(args):
    op=args.get('op')
    if op=='info':return metadata()
    if op=='list':return memories(args)
    if op=='graph':return graph(args)
    if op=='detail':
        with connect() as c:return presented(c,record(c,args['kind'],args['id']),args['kind'])
    if op=='settings':return api('/api/settings')
    if op=='save_settings':
        changes=args['changes'];response=api('/api/settings',changes)
        if response.get('error'):raise ValueError(response['error'])
        saved=settings()
        if any(str(saved.get(k,''))!=str(v) for k,v in changes.items()):raise RuntimeError('Settings verification failed; reload settings before retrying')
        return {'message':'Settings saved and verified'}
    if op=='restart':api('/api/admin/restart',{});return {'message':'Worker restart requested'}
    if op=='start':worker('start');return {'message':'Worker started'}
    if op in ['edit','recover']:return mutate(args)
    if op=='undo':
        filename=args['revision']
        if pathlib.Path(filename).name!=filename:raise ValueError('Invalid revision')
        j=json.loads((STATE/'revisions'/filename).read_text())
        with connect() as c:current=record(c,j['kind'],j['id'])
        if any(current.get(k)!=j['after'].get(k) for k in FIELDS[j['kind']]):raise ValueError('The memory has changed since this revision. Reload and edit explicitly.')
        response=mutate({'op':'edit','kind':j['kind'],'id':j['id'],'fingerprint':fingerprint(current,j['kind']),'changes':{k:list_value(j['before'].get(k)) if k in LISTS else j['before'].get(k) or '' for k in FIELDS[j['kind']] if j['before'].get(k)!=j['after'].get(k)}})
        j['status']='undone';atomic(STATE/'revisions'/filename,j);return response
    if op=='link':
        items=links();a=args['from'];b=args['to']
        if a==b or not all(re.fullmatch(r'(observation|summary):[1-9][0-9]*',v) for v in [a,b]):raise ValueError('Choose two different memory IDs, e.g. observation:123')
        with connect() as c:
            for key in [a,b]:kind,ident=key.split(':');record(c,kind,ident)
        edge={'from':min(a,b),'to':max(a,b)}
        if args.get('remove'):items=[e for e in items if e!=edge]
        elif edge not in items:items.append(edge)
        atomic(STATE/'links.json',items);return items
    if op=='links':return links()
    if op=='export':return export_data(args)
    raise ValueError('Unknown operation')

def demo_main(args):
    """Read-only synthetic dataset. Never reads the user's settings, database, or credentials."""
    global STATE, settings, api
    if args.get('op') not in ['info','list','graph','detail','settings','links']:
        raise ValueError('Demo mode is read-only. Relaunch without --demo to use your own memories.')
    resources=pathlib.Path(__file__).resolve().parent
    fixture=resources/'demo-schema.sql'
    if not fixture.exists():fixture=resources.parent/'scripts/fixtures/claude-mem-13.29.0.sql'
    dataset=json.loads((resources/'demo.json').read_text())
    with tempfile.TemporaryDirectory(prefix='memory-atlas-demo-') as temp:
        STATE=pathlib.Path(temp)/'state'
        os.environ['CLAUDE_MEM_DATA_DIR']=temp
        config={'CLAUDE_MEM_PROVIDER':'codex','CLAUDE_MEM_CODEX_MODEL':'demo-model','CLAUDE_MEM_CODEX_REASONING_EFFORT':'low','CLAUDE_MEM_CODEX_MAX_CONCURRENT_AGENTS':'2','CLAUDE_MEM_CONTEXT_OBSERVATIONS':'50','CLAUDE_MEM_CONTEXT_SESSION_COUNT':'10','CLAUDE_MEM_CONTEXT_SHOW_LAST_SUMMARY':'true','CLAUDE_MEM_SESSION_START_INCLUDE_ALL_SOURCES':'true'}
        settings=lambda:config
        def demo_api(path,body=None):
            return {'/api/settings':config,'/api/health':{'status':'ok','version':'13.29.0','initialized':True,'ai':{'provider':'codex','authMethod':'Demo · no account connected'}},'/api/processing-status':{'isProcessing':False,'queueDepth':0},'/api/chroma/status':{'status':'Demo dataset'}}.get(path,{})
        api=demo_api
        with connect(write=True) as c:
            c.executescript(fixture.read_text())
            for project in sorted({r['project'] for r in dataset['memories']}):
                c.execute('INSERT INTO sdk_sessions(content_session_id,memory_session_id,project,started_at,started_at_epoch,platform_source) VALUES (?,?,?,?,?,?)',('demo-'+project,'demo-'+project,project,'2026-01-01',0,'claude'))
            for item in dataset['memories']:
                row=dict(item);kind=row.pop('kind');source=row.pop('source');days=row.pop('days_ago');session=row['memory_session_id']+'-'+source;row['memory_session_id']=session
                c.execute('INSERT OR IGNORE INTO sdk_sessions(content_session_id,memory_session_id,project,started_at,started_at_epoch,platform_source) VALUES (?,?,?,?,?,?)',(session,session,row['project'],'2026-01-01',0,source))
                stamp=datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(days=days)
                row.update(created_at=stamp.isoformat(),created_at_epoch=int(stamp.timestamp()*1000))
                for key in LISTS:
                    if key in row:row[key]=json.dumps(row[key])
                c.execute('INSERT INTO '+TABLES[kind]+' ('+','.join(row)+') VALUES ('+','.join('?' for _ in row)+')',list(row.values()))
        atomic(STATE/'links.json',dataset['links'])
        result=main(args)
        if args['op']=='info':result.update(data_dir='Demo data · no local memories loaded',effective_model='demo-model · synthetic data')
        return result

if __name__=='__main__':
    try:
        request=json.load(sys.stdin)
        result=demo_main(request) if '--demo' in sys.argv else (maintenance(request) if len(sys.argv)>1 and sys.argv[1]=='maintenance' else main(request))
        print(json.dumps(result,ensure_ascii=False))
    except Exception as e:
        print(json.dumps({'error':str(e)},ensure_ascii=False));sys.exit(1)
