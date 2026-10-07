#!/usr/bin/env python3
"""One integration check. Synthetic rows and a temporary Chroma store only."""
import importlib.util,json,os,pathlib,sqlite3,subprocess,sys,tempfile,time
ROOT=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('atlas',ROOT/'Resources/atlas.py');atlas=importlib.util.module_from_spec(spec);spec.loader.exec_module(atlas)

def child(root,op,args):
    atlas.STATE=pathlib.Path(root)/'state'
    os.environ['CLAUDE_MEM_DATA_DIR']=root
    if op in ['seed','verify']:
        import chromadb
        client=chromadb.PersistentClient(path=root+'/chroma',settings=chromadb.Settings(anonymized_telemetry=False))
        collection=client.get_or_create_collection('cm__claude-mem')
        with atlas.connect() as c:r=atlas.record(c,args.get('kind','observation'),1)
        if op=='seed':atlas.reconcile(collection,r,'observation','codex')
        else:
            kind=args.get('kind','observation');expected=atlas.vector_documents(r,kind,'codex');snap=atlas.vector_snapshot(collection,1,kind)
            assert dict(zip(snap['ids'],snap['documents']))=={d[0]:d[1] for d in expected}
            if expected:
                found=collection.query(query_texts=[expected[0][1]],n_results=1)
                assert found['ids'][0][0] in {d[0] for d in expected}
        return {'ok':True}
    if op in ['fail','crash']:
        original=atlas.reconcile
        def interrupted(*items):
            original(*items)
            if op=='crash':os._exit(77)
            raise RuntimeError('Injected interruption')
        atlas.reconcile=interrupted
    return atlas.maintenance(args)

if len(sys.argv)>1:
    try:print(json.dumps(child(sys.argv[1],sys.argv[2],json.loads(sys.argv[3]))))
    except Exception as e:print(json.dumps({'error':str(e)}));sys.exit(1)
    sys.exit()

with tempfile.TemporaryDirectory(prefix='memory-atlas-check-') as temp:
    root=pathlib.Path(temp);atlas.STATE=root/'state';os.environ['CLAUDE_MEM_DATA_DIR']=temp
    c=sqlite3.connect(root/'claude-mem.db');c.execute('PRAGMA journal_mode=WAL')
    c.executescript((ROOT/'scripts/fixtures/claude-mem-13.29.0.sql').read_text())
    c.execute("INSERT INTO sdk_sessions(content_session_id,memory_session_id,project,started_at,started_at_epoch,platform_source) VALUES ('test','test','atlas-check','2026-10-07',?,'codex')",(int(time.time()*1000),))
    c.execute("INSERT INTO observations(memory_session_id,project,type,title,narrative,facts,concepts,created_at,created_at_epoch) VALUES ('test','atlas-check','discovery','Original title','Original narrative','[\"first fact\",\"second fact\"]','[\"memory\"]','2026-10-07',?)",(int(time.time()*1000),))
    c.execute("INSERT INTO session_summaries(memory_session_id,project,request,learned,created_at,created_at_epoch) VALUES ('test','atlas-check','Original request','Original summary','2026-10-07',?)",(int(time.time()*1000),));c.commit();c.close()
    py=pathlib.Path(os.environ.get('CHROMA_PYTHON') or atlas.chroma_python())
    def run(op,args={},error=None):
        p=subprocess.run([str(py),__file__,temp,op,json.dumps(args)],capture_output=True,text=True,timeout=150,env=dict(os.environ,ANONYMIZED_TELEMETRY='False'))
        lock=root/'chroma/.claude-mem-chroma-writer.lock'
        if lock.exists():lock.unlink() # Child has exited; all persistent Chroma handles are closed.
        if error=='crash':assert p.returncode==77,(p.stdout,p.stderr)
        elif error:assert p.returncode!=0 and error in p.stdout,(p.stdout,p.stderr)
        else:assert p.returncode==0,(p.stdout,p.stderr);return json.loads(p.stdout)
    def raw(kind='observation'):
        with atlas.connect() as c:return atlas.record(c,kind,1)
    run('seed');before=raw()
    result=run('edit',{'op':'edit','kind':'observation','id':1,'fingerprint':atlas.fingerprint(before,'observation'),'changes':{'title':'Edited title','narrative':'Atlasuniqueterm durable knowledge','facts':['remaining fact']}})
    after=raw();assert after['created_at']==before['created_at'] and after['memory_session_id']==before['memory_session_id']
    with atlas.connect() as c:assert c.execute("SELECT rowid FROM observations_fts WHERE observations_fts MATCH 'Atlasuniqueterm'").fetchone()[0]==1
    run('verify');run('edit',{'op':'edit','kind':'observation','id':1,'fingerprint':atlas.fingerprint(before,'observation'),'changes':{'title':'Stale'}},error='changed while open')
    run('fail',{'op':'edit','kind':'observation','id':1,'fingerprint':atlas.fingerprint(after,'observation'),'changes':{'title':'Must roll back'}},error='Injected interruption');assert raw()==after;run('verify')
    # Exercise the actual undo handler while keeping lifecycle isolated from the live worker.
    atlas.mutate=lambda args:run('edit',args)
    atlas.main({'op':'undo','revision':result['revision']});run('verify')
    restored=raw()
    assert all(atlas.list_value(restored.get(k))==atlas.list_value(before.get(k)) if k in atlas.LISTS else (restored.get(k) or '')==(before.get(k) or '') for k in atlas.FIELDS['observation'])
    summary=raw('summary');run('edit',{'op':'edit','kind':'summary','id':1,'fingerprint':atlas.fingerprint(summary,'summary'),'changes':{'learned':'Updated summary'}});run('verify',{'kind':'summary'})
    with atlas.connect() as c:assert c.execute("SELECT rowid FROM session_summaries_fts WHERE session_summaries_fts MATCH 'Updated'").fetchone()[0]==1
    # Real process termination after vector writes: SQLite rolls back; recovery restores vectors.
    current=raw()
    run('crash',{'op':'edit','kind':'observation','id':1,'fingerprint':atlas.fingerprint(current,'observation'),'changes':{'narrative':'Interrupted vector change'}},error='crash')
    assert atlas.pending() and raw()==current
    run('recover',{'op':'recover'});assert not atlas.pending();run('verify')
    atlas.main({'op':'link','from':'observation:1','to':'summary:1'})
    graph=atlas.graph({'project':'atlas-check'});assert any(e.get('manual') for e in graph['edges'])
    exported=atlas.export_data({'destination':temp,'format':'markdown'});folder=pathlib.Path(exported['path']);archive=json.loads((folder/'memories.json').read_text());assert len(archive['memories'])==2
    assert '[[summary-1]]' in (folder/'observation-1.md').read_text()
    assert '# atlas-check' in next(folder.glob('project-*.md')).read_text()
    assert atlas.memories({'query':'Updated','kind':'summary'})[0]['id']==1
    lock=root/'chroma/.claude-mem-chroma-writer.lock'
    atlas.atomic(lock,{'pid':99999999,'ownerId':'dead','startToken':'old'})
    current=raw('summary');run('edit',{'op':'edit','kind':'summary','id':1,'fingerprint':atlas.fingerprint(current,'summary'),'changes':{'notes':'Stale lock recovered'}})
    token=subprocess.check_output(['ps','-p',str(os.getpid()),'-o','lstart='],text=True).strip()
    atlas.atomic(lock,{'pid':os.getpid(),'ownerId':'live','startToken':token})
    current=raw('summary');run('edit',{'op':'edit','kind':'summary','id':1,'fingerprint':atlas.fingerprint(current,'summary'),'changes':{'notes':'Must refuse live owner'}},error='live process')
print('PASS: edit, FTS, semantic documents/query, stale protection, rollback, undo pipeline, summary, crash recovery, graph links, JSON/Markdown export.')
