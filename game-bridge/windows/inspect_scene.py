"""Fixed scene inspector; no autoexec and no external scene script invocation."""
import bpy,json,pathlib,sys
args=sys.argv[sys.argv.index('--')+1:]
scene=pathlib.Path(args[0]);out=pathlib.Path(args[1])
bpy.ops.wm.open_mainfile(filepath=str(scene),load_ui=False,use_scripts=False)
report={'blender_version':bpy.app.version_string,'objects':[{'name':o.name,'type':o.type,'location':list(o.location)} for o in bpy.data.objects],'scenes':[s.name for s in bpy.data.scenes]}
(out/'scene.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
