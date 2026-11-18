import subprocess,datetime,time,pathlib,sys
root=pathlib.Path(__file__).resolve().parent.parent;dest=root/'signing-comparison'
pid,label,count=int(sys.argv[1]),sys.argv[2],int(sys.argv[3])
start=datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
for i in range(count):
 subprocess.run([str(root/'storage-host-recurrence/replay'),str(root/'3ping.jsonl'),'135.6','137.9','-350','20'],check=True,stdout=subprocess.DEVNULL)
 time.sleep(.4)
 print(f'{label} {i+1}/{count}',flush=True)
log=subprocess.check_output(['/usr/bin/log','show','--start',start,'--style','compact','--info','--predicate',f'processID == {pid}'],text=True,stderr=subprocess.DEVNULL)
(dest/(label+'.log')).write_text(log)
for tag in ['row writer:','pane drop accepted:','Canceling drag','CALayerInvalidGeometry','Drag reference does not have any info']:print(tag,log.count(tag))
