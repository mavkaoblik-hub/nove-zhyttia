"""Reviewed fixture: factory scene only; CPU rendering until GPU verification."""
import bpy, math, pathlib, sys
out=pathlib.Path(sys.argv[sys.argv.index('--')+1]).resolve()
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, location=(0,0,1))
obj=bpy.context.object;obj.name='BridgeFixture_NotRobotRef';obj.scale=(0.7,0.7,1)
mat=bpy.data.materials.new('FixtureWhite');mat.diffuse_color=(0.8,0.85,0.9,1);obj.data.materials.append(mat)
bpy.ops.object.camera_add(location=(4,-6,3),rotation=(math.radians(70),0,math.radians(33)))
scene=bpy.context.scene;scene.camera=bpy.context.object
bpy.ops.object.light_add(type='AREA',location=(2,-3,5));bpy.context.object.data.energy=700
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8
scene.render.resolution_x=512;scene.render.resolution_y=512;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.filepath=str(out/'smoke.png')
bpy.ops.render.render(write_still=True)
bpy.ops.export_scene.gltf(filepath=str(out/'smoke.glb'),export_format='GLB')
