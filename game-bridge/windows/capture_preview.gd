extends SceneTree

func _initialize() -> void:
	call_deferred("capture_preview")

func capture_preview() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		push_error("Bridge capture output argument missing")
		quit(2)
		return
	var output := arguments[0]
	var scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if scene.is_empty() or change_scene_to_file(scene) != OK:
		push_error("Bridge main scene could not be loaded")
		quit(3)
		return
	for frame in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Bridge viewport returned no image")
		quit(4)
		return
	if image.get_width() > 1280 or image.get_height() > 1280:
		image.resize(960, 540, Image.INTERPOLATE_LANCZOS)
	if image.save_png(output.path_join("godot-preview.png")) != OK:
		push_error("Bridge could not save preview")
		quit(5)
		return
	var report := {"schema": 1, "capture": "game_viewport", "frames_waited": 30,
		"width": image.get_width(), "height": image.get_height(),
		"scene": scene, "engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"visual_quality_passed": false, "visual_review_required": true}
	var file := FileAccess.open(output.path_join("godot-feedback.json"), FileAccess.WRITE)
	if file == null:
		push_error("Bridge could not save feedback")
		quit(6)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("MAVKA_CAPTURE_OK")
	quit(0)
