extends Node3D
## Lingerie try-on pilot: a stylized 3D mannequin with body-shape sliders.
## Load a photo of a bra / panty, the app removes the plain background
## and wraps the garment around the mannequin. Godot 4.5+.

const PRESETS := {
	"Average": [1.0, 1.0, 1.0, 1.0],
	"Petite": [0.9, 0.9, 0.85, 0.9],
	"Slim": [1.0, 0.85, 0.8, 0.85],
	"Athletic": [1.03, 0.9, 0.85, 0.95],
	"Curvy": [1.0, 1.2, 0.9, 1.25],
	"Plus size": [1.0, 1.3, 1.35, 1.4],
	"Tall": [1.1, 1.0, 0.95, 1.05],
}
const SLOTS := ["bra", "panty"]
const MAX_SIDE := 400

const AVATAR_TEXTURE_PATH := "res://assets/avatar_3d.png"

# scene parts
var figure: Node3D
var cam: Camera3D
var avatar_sprite: MeshInstance3D

# shape state
var height_k := 1.0
var bust_k := 1.0
var waist_k := 1.0
var hips_k := 1.0
var tol := 0.2
var sizes := {"bra": 1.0, "panty": 1.0}
var shifts := {"bra": 0.0, "panty": 0.0}
var garments := {}
var pending_slot := "bra"
var auto_turn := false
var t := 0.0

# ui
var status: Label
var panel: PanelContainer
var file_dialog: FileDialog
var sl_height: HSlider
var sl_bust: HSlider
var sl_waist: HSlider
var sl_hips: HSlider
var tol_slider: HSlider


func _ready() -> void:
	if OS.get_name() == "Android":
		OS.request_permissions()

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("2b2630")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.9, 0.9, 0.95)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 25, 0)
	light.light_energy = 1.1
	add_child(light)

	cam = Camera3D.new()
	cam.fov = 40.0
	add_child(cam)

	build_mannequin()
	build_garments()
	build_ui()
	apply_shape()
	_set_zoom(0.0)


# ---------------------------------------------------------------- mannequin

func mat(c: Color, rough := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func ell(parent: Node3D, radii: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 24
	s.rings = 12
	mi.mesh = s
	mi.scale = radii
	mi.position = pos
	mi.material_override = m
	parent.add_child(mi)
	return mi


func limb(pivot: Node3D, r: float, h: float, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 16
	c.rings = 6
	mi.mesh = c
	mi.position = Vector3(0, -h / 2.0, 0)
	mi.material_override = m
	pivot.add_child(mi)


func build_mannequin() -> void:
	# Transparent image-based avatar displayed on a 3D quad.
	figure = Node3D.new()
	add_child(figure)
	avatar_sprite = MeshInstance3D.new()
	var avatar_quad := QuadMesh.new()
	avatar_quad.size = Vector2(0.92, 1.62)
	avatar_sprite.mesh = avatar_quad
	var avatar_texture := load(AVATAR_TEXTURE_PATH) as Texture2D
	var avatar_material := StandardMaterial3D.new()
	avatar_material.albedo_texture = avatar_texture
	avatar_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	avatar_material.alpha_scissor_threshold = 0.05
	avatar_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	avatar_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	avatar_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	avatar_sprite.material_override = avatar_material
	avatar_sprite.position = Vector3(0, 0.88, 0)
	figure.add_child(avatar_sprite)


func apply_shape() -> void:
	# Height scales the complete image-based avatar. Fit controls resize garments.
	figure.scale = Vector3.ONE * height_k
	for slot in SLOTS:
		update_garment(slot)


# ---------------------------------------------------------------- garments

func build_garments() -> void:
	for slot in SLOTS:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var mi := MeshInstance3D.new()
		mi.visible = false
		mi.material_override = m
		figure.add_child(mi)
		garments[slot] = {"mi": mi, "mat": m, "orig": null, "aspect": 1.0, "has": false}


func _vert(st: SurfaceTool, p: Vector3, a: float, u: float, v: float) -> void:
	st.set_normal(Vector3(sin(a), 0.0, cos(a)))
	st.set_uv(Vector2(u, v))
	st.add_vertex(p)


## A flat picture bent around a cylinder so it wraps the body.
func curved_quad(w: float, h: float, radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 18
	var span := clampf(w / radius, 0.2, 2.6)
	for i in segs:
		var u0 := float(i) / segs
		var u1 := float(i + 1) / segs
		var a0 := (u0 - 0.5) * span
		var a1 := (u1 - 0.5) * span
		var x0 := radius * sin(a0)
		var x1 := radius * sin(a1)
		var z0 := radius * (cos(a0) - 1.0)
		var z1 := radius * (cos(a1) - 1.0)
		_vert(st, Vector3(x0, h * 0.5, z0), a0, u0, 0.0)
		_vert(st, Vector3(x1, h * 0.5, z1), a1, u1, 0.0)
		_vert(st, Vector3(x1, -h * 0.5, z1), a1, u1, 1.0)
		_vert(st, Vector3(x0, h * 0.5, z0), a0, u0, 0.0)
		_vert(st, Vector3(x1, -h * 0.5, z1), a1, u1, 1.0)
		_vert(st, Vector3(x0, -h * 0.5, z0), a0, u0, 1.0)
	return st.commit()


func update_garment(slot: String) -> void:
	var g: Dictionary = garments[slot]
	var mi: MeshInstance3D = g["mi"]
	if not g["has"]:
		mi.visible = false
		return
	var w: float
	var cy: float
	var zf: float
	var r: float
	if slot == "bra":
		w = 0.34 * (0.75 + 0.25 * bust_k) * float(sizes[slot])
		cy = 1.31 + float(shifts[slot])
		zf = 0.085 + 0.055 * bust_k + 0.012
		r = 0.16
	else:
		w = 0.33 * hips_k * float(sizes[slot])
		cy = 0.93 + float(shifts[slot])
		zf = 0.115 * lerpf(1.0, hips_k, 0.6) + 0.012
		r = 0.17 * hips_k
	var h := w * float(g["aspect"])
	mi.mesh = curved_quad(w, h, r)
	mi.position = Vector3(0, cy, zf)
	mi.visible = true


# ---------------------------------------------------------------- loading photos

func pick_image(slot: String) -> void:
	pending_slot = slot
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show("Choose a cloth photo", "", "", false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
			PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp;Images"]), _on_native_file)
	else:
		file_dialog.popup_centered(Vector2i(900, 1300))


func _on_native_file(ok: bool, paths: PackedStringArray, _filter: int) -> void:
	if ok and paths.size() > 0:
		_load_path(paths[0])


func _load_path(path: String) -> void:
	var bytes := FileAccess.get_file_as_bytes(path)
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes.size() > 12:
		if bytes[0] == 0x89 and bytes[1] == 0x50:
			err = img.load_png_from_buffer(bytes)
		elif bytes[0] == 0xFF and bytes[1] == 0xD8:
			err = img.load_jpg_from_buffer(bytes)
		elif bytes[0] == 0x52 and bytes[1] == 0x49:
			err = img.load_webp_from_buffer(bytes)
	if err != OK or img.is_empty():
		status.text = "Could not open that image. Use PNG, JPG or WEBP."
		return
	garments[pending_slot]["orig"] = img
	await process_garment(pending_slot)


func process_garment(slot: String) -> void:
	status.text = "Removing background..."
	await get_tree().process_frame
	await get_tree().process_frame
	var src: Image = garments[slot]["orig"]
	var out := remove_background(src.duplicate(), tol)
	if out == null:
		status.text = "Could not find the garment. Use a photo on a plain background."
		return
	var g: Dictionary = garments[slot]
	var m: StandardMaterial3D = g["mat"]
	m.albedo_texture = ImageTexture.create_from_image(out)
	g["aspect"] = float(out.get_height()) / float(out.get_width())
	g["has"] = true
	update_garment(slot)
	status.text = "Done. Adjust size and position with the sliders."


func _is_bg(data: PackedByteArray, idx: int, r0: float, g0: float, b0: float, thr2: float) -> bool:
	var o := idx * 4
	if data[o + 3] < 16:
		return true
	var dr := data[o] - r0
	var dg := data[o + 1] - g0
	var db := data[o + 2] - b0
	return dr * dr + dg * dg + db * db <= thr2


## Flood-fills the plain background from the photo edges and makes it transparent.
## Works best on a plain, evenly lit background that differs from the garment color.
@warning_ignore("integer_division")
func remove_background(img: Image, tolerance: float) -> Image:
	img.convert(Image.FORMAT_RGBA8)
	var longest := maxi(img.get_width(), img.get_height())
	if longest > MAX_SIDE:
		var k := float(MAX_SIDE) / float(longest)
		img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_BILINEAR)
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()

	var border: Array[int] = []
	for x in w:
		border.append(x)
		border.append((h - 1) * w + x)
	for y in h:
		border.append(y * w)
		border.append(y * w + w - 1)

	# average colour of the opaque border pixels = background colour
	var r0 := 0.0
	var g0 := 0.0
	var b0 := 0.0
	var n := 0
	for bi in border:
		var o := bi * 4
		if data[o + 3] >= 16:
			r0 += data[o]
			g0 += data[o + 1]
			b0 += data[o + 2]
			n += 1
	if n > 0:
		r0 /= n
		g0 /= n
		b0 /= n
	else:
		r0 = -10000.0
	var thr2 := pow(tolerance * 255.0, 2.0)

	var removed := PackedByteArray()
	removed.resize(w * h)
	var stack: Array[int] = []
	for bi in border:
		if removed[bi] == 0 and _is_bg(data, bi, r0, g0, b0, thr2):
			removed[bi] = 1
			stack.append(bi)
	while not stack.is_empty():
		var cur: int = stack.pop_back()
		var cx := cur % w
		var cy := cur / w
		var j := 0
		if cx > 0:
			j = cur - 1
			if removed[j] == 0 and _is_bg(data, j, r0, g0, b0, thr2):
				removed[j] = 1
				stack.append(j)
		if cx < w - 1:
			j = cur + 1
			if removed[j] == 0 and _is_bg(data, j, r0, g0, b0, thr2):
				removed[j] = 1
				stack.append(j)
		if cy > 0:
			j = cur - w
			if removed[j] == 0 and _is_bg(data, j, r0, g0, b0, thr2):
				removed[j] = 1
				stack.append(j)
		if cy < h - 1:
			j = cur + w
			if removed[j] == 0 and _is_bg(data, j, r0, g0, b0, thr2):
				removed[j] = 1
				stack.append(j)

	# write alpha, soften the edge a little, find the garment bounds
	var minx := w
	var maxx := -1
	var miny := h
	var maxy := -1
	var removed_count := 0
	for y in h:
		for x in w:
			var i := y * w + x
			if removed[i] == 1:
				data[i * 4 + 3] = 0
				removed_count += 1
				continue
			var edge := false
			if x > 0 and removed[i - 1] == 1:
				edge = true
			elif x < w - 1 and removed[i + 1] == 1:
				edge = true
			elif y > 0 and removed[i - w] == 1:
				edge = true
			elif y < h - 1 and removed[i + w] == 1:
				edge = true
			if edge:
				data[i * 4 + 3] = 150
			if data[i * 4 + 3] > 0:
				minx = mini(minx, x)
				maxx = maxi(maxx, x)
				miny = mini(miny, y)
				maxy = maxi(maxy, y)

	if maxx < 0 or removed_count > int(0.97 * w * h):
		return null
	var out := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	return out.get_region(Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1))


func reprocess_all() -> void:
	for s in SLOTS:
		if garments[s]["orig"] != null:
			await process_garment(s)


# ---------------------------------------------------------------- ui

func add_slider(parent: Control, text: String, lo: float, hi: float, val: float, cb: Callable) -> HSlider:
	var l := Label.new()
	l.text = text
	parent.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.01
	s.value = val
	s.custom_minimum_size = Vector2(0, 48)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(cb)
	parent.add_child(s)
	return s


func build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var th := Theme.new()
	for cls in ["Label", "Button", "OptionButton"]:
		th.set_font_size("font_size", cls, 30)

	status = Label.new()
	status.theme = th
	status.text = "Pick a body type, then load a cloth photo."
	status.position = Vector2(20, 20)
	status.custom_minimum_size = Vector2(760, 0)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(status)

	var hide_btn := Button.new()
	hide_btn.theme = th
	hide_btn.text = "Panel"
	layer.add_child(hide_btn)
	hide_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	hide_btn.offset_left -= 20
	hide_btn.offset_right -= 20
	hide_btn.offset_top += 20
	hide_btn.offset_bottom += 20
	hide_btn.pressed.connect(_toggle_panel)

	panel = PanelContainer.new()
	panel.theme = th
	layer.add_child(panel)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 640)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(box)

	var l1 := Label.new()
	l1.text = "Body type"
	box.add_child(l1)
	var presets := OptionButton.new()
	for k in PRESETS:
		presets.add_item(k)
	presets.item_selected.connect(_on_preset)
	box.add_child(presets)

	var avatar_info := Label.new()
	avatar_info.text = "3D photo avatar (reference-based)"
	avatar_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(avatar_info)

	sl_height = add_slider(box, "Height", 0.85, 1.15, 1.0, _set_height)
	sl_bust = add_slider(box, "Bust / bra fit", 0.7, 1.4, 1.0, _set_bust)
	sl_waist = add_slider(box, "Waist fit", 0.7, 1.5, 1.0, _set_waist)
	sl_hips = add_slider(box, "Hips / panty fit", 0.7, 1.5, 1.0, _set_hips)

	var b_bra := Button.new()
	b_bra.text = "Load bra photo"
	b_bra.pressed.connect(pick_image.bind("bra"))
	box.add_child(b_bra)
	add_slider(box, "Bra size", 0.6, 1.6, 1.0, _set_size.bind("bra"))
	add_slider(box, "Bra up / down", -0.12, 0.12, 0.0, _set_shift.bind("bra"))

	var b_pan := Button.new()
	b_pan.text = "Load panty photo"
	b_pan.pressed.connect(pick_image.bind("panty"))
	box.add_child(b_pan)
	add_slider(box, "Panty size", 0.6, 1.6, 1.0, _set_size.bind("panty"))
	add_slider(box, "Panty up / down", -0.12, 0.12, 0.0, _set_shift.bind("panty"))

	tol_slider = add_slider(box, "Background removal strength (release to apply)", 0.05, 0.5, tol, _set_tol)
	tol_slider.drag_ended.connect(_on_tol_released)

	add_slider(box, "Zoom", 0.0, 1.0, 0.0, _set_zoom)

	var b_turn := Button.new()
	b_turn.text = "Auto turn"
	b_turn.toggle_mode = true
	b_turn.button_pressed = false
	b_turn.toggled.connect(_on_turn)
	box.add_child(b_turn)

	var b_front := Button.new()
	b_front.text = "Front view"
	b_front.pressed.connect(_front_view)
	box.add_child(b_front)

	var b_clear := Button.new()
	b_clear.text = "Remove garments"
	b_clear.pressed.connect(_clear_garments)
	box.add_child(b_clear)

	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)

	# fallback picker for devices without a native file dialog
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
	if OS.get_name() == "Android":
		file_dialog.current_dir = "/storage/emulated/0/Pictures"
	file_dialog.file_selected.connect(_load_path)
	add_child(file_dialog)


func _toggle_panel() -> void:
	panel.visible = not panel.visible


func _on_preset(idx: int) -> void:
	var key: String = PRESETS.keys()[idx]
	var v: Array = PRESETS[key]
	sl_height.value = v[0]
	sl_bust.value = v[1]
	sl_waist.value = v[2]
	sl_hips.value = v[3]


func _set_height(v: float) -> void:
	height_k = v
	apply_shape()


func _set_bust(v: float) -> void:
	bust_k = v
	apply_shape()


func _set_waist(v: float) -> void:
	waist_k = v
	apply_shape()


func _set_hips(v: float) -> void:
	hips_k = v
	apply_shape()


func _set_size(v: float, slot: String) -> void:
	sizes[slot] = v
	update_garment(slot)


func _set_shift(v: float, slot: String) -> void:
	shifts[slot] = v
	update_garment(slot)


func _set_tol(v: float) -> void:
	tol = v


func _on_tol_released(changed: bool) -> void:
	if changed:
		reprocess_all()


func _set_zoom(v: float) -> void:
	cam.position = Vector3(0.0, lerpf(0.45, 1.0, v), lerpf(3.9, 1.5, v))


func _on_turn(on: bool) -> void:
	auto_turn = on


func _front_view() -> void:
	figure.rotation.y = 0.0


func _clear_garments() -> void:
	for s in SLOTS:
		garments[s]["has"] = false
		garments[s]["orig"] = null
		update_garment(s)
	status.text = "Garments removed."


# ---------------------------------------------------------------- loop / input

func _process(delta: float) -> void:
	t += delta
	if auto_turn:
		figure.rotation.y += delta * 0.6


func _unhandled_input(ev: InputEvent) -> void:
	# drag on the 3D area to rotate (touch drag arrives as emulated mouse motion)
	if ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		figure.rotation.y += ev.relative.x * 0.01
