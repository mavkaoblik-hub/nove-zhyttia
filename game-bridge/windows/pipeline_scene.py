"""Reviewed preview pipeline. Read staged input; write only a fresh job output folder."""
import bpy,json,math,pathlib,sys
from mathutils import Vector
args=json.loads(pathlib.Path(sys.argv[sys.argv.index('--')+1]).read_text(encoding='utf-8-sig'))
source=pathlib.Path(args['input']);out=pathlib.Path(args['output']);angle=float(args.get('angle_degrees',0))
if not -180<=angle<=180:raise ValueError('camera angle')
bpy.ops.wm.open_mainfile(filepath=str(source),load_ui=False,use_scripts=False)
scene=bpy.context.scene
meshes=[o for o in scene.objects if o.type=='MESH' and not any(s in o.name.lower() for s in ['floor','ground','plane'])]
if not meshes:meshes=[o for o in scene.objects if o.type=='MESH']
if not meshes:raise ValueError('no mesh in input scene')
points=[o.matrix_world@Vector(v) for o in meshes for v in o.bound_box]
minimum=Vector(tuple(min(p[i] for p in points) for i in range(3)));maximum=Vector(tuple(max(p[i] for p in points) for i in range(3)))
center=(minimum+maximum)*.5;radius=max((maximum-minimum).length*.5,.1)
theta=math.radians(angle)
location=center+Vector((math.sin(theta)*radius*3.2,-math.cos(theta)*radius*3.2,radius*.9))
bpy.ops.object.camera_add(location=location);camera=bpy.context.object;camera.name='BridgePreviewCamera'
camera.rotation_euler=(center-location).to_track_quat('-Z','Y').to_euler();camera.data.lens=50;camera.data.clip_end=max(100,radius*20);scene.camera=camera
for offset,power,size in [((2,-3,4),1000,4),((-3,-1,2),500,3),((0,3,3),700,3)]:
 bpy.ops.object.light_add(type='AREA',location=center+Vector(offset)*radius)
 light=bpy.context.object;light.name='BridgePreviewLight';light.data.energy=power*max(radius*radius,.2);light.data.shape='DISK';light.data.size=size*radius
 light.rotation_euler=(center-light.location).to_track_quat('-Z','Y').to_euler()
if scene.world is None:scene.world=bpy.data.worlds.new('BridgePreviewWorld')
scene.world.color=(.08,.08,.08)
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8
scene.render.resolution_x=512;scene.render.resolution_y=512;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.filepath=str(out/'render.png')
bpy.ops.wm.save_as_mainfile(filepath=str(out/'model.blend'),copy=True)
bpy.ops.render.render(write_still=True)
bpy.ops.export_scene.gltf(filepath=str(out/'model.glb'),export_format='GLB')
(out/'scene-report.json').write_text(json.dumps({'blender':bpy.app.version_string,'mesh_count':len(meshes),'radius':radius,'camera_angle':angle,'geometry_modified':False,'input_preserved':True},indent=2),encoding='utf-8')
