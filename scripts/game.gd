extends Node3D

# Self-contained procedural prototype. No external assets or plugins required.
const SAVE_PATH := "user://colony.save"
const SURFACE_Z := 0.0
const NEST_Z := 22.0
const QUEEN_POS := Vector3(0, 0.28, NEST_Z + 5)
const FUNGUS_POS := Vector3(-5, 0.25, NEST_Z + 1)
const EXIT_POS := Vector3(0, 0, NEST_Z - 8)
const LEAF_POS := Vector3(0, 0, -6)
var ant: Node3D
var camera: Camera3D
var workers: Array[Node3D] = []
var worker_tasks: Array[int] = []
var task_counts := [0, 0, 0]
var leaves := 0
var fungus := 0
var eggs := 0
var carried := ""
var in_nest := false
var fungus_timer := 0.0
var egg_timer := 0.0
var worker_timer := 0.0
var time_to_save := 0.0
var move_vector := Vector2.ZERO
var joystick_touch := -1
var joystick_origin := Vector2.ZERO
var camera_yaw := 0.0
var dragging_camera := false
var camera_touch := -1
var last_drag := Vector2.ZERO
var ui: CanvasLayer
var status_label: Label
var action_button: Button
var task_panel: PanelContainer
var task_labels: Array[Label] = []
var rng := RandomNumberGenerator.new()
var leaf_nodes: Array[Node3D] = []
var message := ""
var message_time := 0.0
var hint_label: Label
var nest_marker: Node3D
var surface_marker: Node3D

func _ready() -> void:
	rng.randomize()
	build_world()
	build_ui()
	load_game()
	show_message("Colete folhas na superfície e leve-as ao cultivo!")

func mat(color: Color, rough: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m

func mesh_box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	n.mesh = m
	n.material_override = mat(color)
	n.position = pos
	parent.add_child(n)
	return n

func sphere(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	n.mesh = m
	n.material_override = mat(color, 0.85)
	n.scale = size
	n.position = pos
	parent.add_child(n)
	return n

func make_ant(parent: Node3D, pos: Vector3, queen: bool = false) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	var factor := 1.75 if queen else 1.0
	var dark := Color("3c2017") if queen else Color("5b2d19")
	var brown := Color("7b3c20") if queen else Color("8c4b26")
	sphere(root, Vector3(0.72, 0.65, 0.85) * factor, Vector3(0, 0.36, 0.53) * factor, dark)
	sphere(root, Vector3(0.47, 0.5, 0.52) * factor, Vector3(0, 0.35, 0) * factor, brown)
	sphere(root, Vector3(0.62, 0.55, 0.6) * factor, Vector3(0, 0.4, -0.55) * factor, dark)
	for side in [-1.0, 1.0]:
		for j in range(3):
			var leg := mesh_box(root, Vector3(0.65, 0.055, 0.06) * factor, Vector3(side * 0.48, 0.20, (j - 1) * 0.4) * factor, dark)
			leg.rotation.z = side * 0.35
		var antenna := mesh_box(root, Vector3(0.045, 0.045, 0.55) * factor, Vector3(side * 0.18, 0.77, -0.91) * factor, dark)
		antenna.rotation.x = -0.5
	return root

func build_world() -> void:
	var sky := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("9ab5ae")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e8dfce")
	env.ambient_light_energy = 0.75
	sky.environment = env
	add_child(sky)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.2
	add_child(sun)
	mesh_box(self, Vector3(70, 0.4, 38), Vector3(0, -0.25, -3), Color("6d8050"))
	mesh_box(self, Vector3(34, 0.4, 33), Vector3(0, -0.25, NEST_Z + 2), Color("6b4931"))
	# Soil wall outlines make the subterranean rooms visually distinct.
	for z in [NEST_Z - 10, NEST_Z + 12]:
		mesh_box(self, Vector3(34, 2.1, 0.5), Vector3(0, 0.8, z), Color("4d3326"))
	for x in [-17.0, 17.0]:
		mesh_box(self, Vector3(0.5, 2.1, 22), Vector3(x, 0.8, NEST_Z + 1), Color("4d3326"))
	# Raised soil mounds and grass tufts.
	for i in range(110):
		var x := rng.randf_range(-31, 31)
		var z := rng.randf_range(-19, 12)
		if abs(x) < 2.8 and z > -2 and z < 3:
			continue
		var blade := mesh_box(self, Vector3(0.11, rng.randf_range(0.4, 1.1), 0.11), Vector3(x, 0.3, z), Color("466b32"))
		blade.rotation.z = rng.randf_range(-0.4, 0.4)
	for i in range(22):
		var x := rng.randf_range(-25, 25)
		var z := rng.randf_range(-16, -3)
		var leaf := Node3D.new()
		leaf.position = Vector3(x, 0.12, z)
		add_child(leaf)
		mesh_box(leaf, Vector3(0.8, 0.07, 1.25), Vector3.ZERO, Color("51913b"))
		leaf.rotation.y = rng.randf_range(0, TAU)
		leaf_nodes.append(leaf)
	# Chambers: decorative colored floors, fungus bed, queen room.
	mesh_box(self, Vector3(8, 0.08, 7), Vector3(-5, 0.01, NEST_Z + 1), Color("82603a"))
	mesh_box(self, Vector3(8, 0.08, 7), Vector3(0, 0.015, NEST_Z + 5), Color("8b6547"))
	for i in range(14):
		sphere(self, Vector3(0.7, 0.45, 0.8), FUNGUS_POS + Vector3(rng.randf_range(-2.3, 2.3), 0, rng.randf_range(-1.8, 1.8)), Color("c2c69b"))
	make_ant(self, QUEEN_POS, true)
	ant = make_ant(self, Vector3(0, 0.15, 0))
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 65
	add_child(camera)
	# Entrance markers.
	nest_marker = Node3D.new()
	nest_marker.position = Vector3(0, 0, 1.7)
	add_child(nest_marker)
	sphere(nest_marker, Vector3(2.5, 0.16, 2.5), Vector3.ZERO, Color("33251a"))
	surface_marker = Node3D.new()
	surface_marker.position = EXIT_POS
	add_child(surface_marker)
	sphere(surface_marker, Vector3(2.5, 0.16, 2.5), Vector3.ZERO, Color("33251a"))

func make_label(parent: Node, value: String, font_size: int = 20) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("fff5df"))
	parent.add_child(label)
	return label

func build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	var top := PanelContainer.new()
	top.position = Vector2(15, 12)
	top.custom_minimum_size = Vector2(520, 88)
	root.add_child(top)
	var v := VBoxContainer.new()
	top.add_child(v)
	status_label = make_label(v, "", 21)
	hint_label = make_label(v, "", 16)
	var right := VBoxContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.position = Vector2(-215, 15)
	right.custom_minimum_size = Vector2(200, 100)
	root.add_child(right)
	var menu := Button.new()
	menu.text = "Tarefas das formigas"
	menu.custom_minimum_size = Vector2(205, 56)
	right.add_child(menu)
	menu.pressed.connect(func(): task_panel.visible = not task_panel.visible)
	task_panel = PanelContainer.new()
	task_panel.visible = false
	right.add_child(task_panel)
	var panel_v := VBoxContainer.new()
	task_panel.add_child(panel_v)
	make_label(panel_v, "Distribuir operárias", 19)
	for i in range(3):
		var h := HBoxContainer.new()
		panel_v.add_child(h)
		var name := ["Folhas", "Fungos", "Rainha"][i]
		var label := make_label(h, name + ": 0", 17)
		label.custom_minimum_size.x = 115
		task_labels.append(label)
		var minus := Button.new()
		minus.text = "−"
		minus.custom_minimum_size.x = 35
		h.add_child(minus)
		minus.pressed.connect(change_task.bind(i, -1))
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size.x = 35
		h.add_child(plus)
		plus.pressed.connect(change_task.bind(i, 1))
	var bottom := Control.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	var joy := Label.new()
	joy.text = "◉  MOVER"
	joy.add_theme_font_size_override("font_size", 26)
	joy.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	joy.position = Vector2(40, -95)
	bottom.add_child(joy)
	action_button = Button.new()
	action_button.text = "INTERAGIR"
	action_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	action_button.position = Vector2(-235, -110)
	action_button.custom_minimum_size = Vector2(210, 78)
	bottom.add_child(action_button)
	action_button.pressed.connect(interact)
	var save_btn := Button.new()
	save_btn.text = "Salvar"
	save_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	save_btn.position = Vector2(-140, -172)
	bottom.add_child(save_btn)
	save_btn.pressed.connect(func(): save_game(); show_message("Progresso salvo"))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < get_viewport().get_visible_rect().size.x * 0.42 and event.position.y > get_viewport().get_visible_rect().size.y * 0.42 and joystick_touch == -1:
				joystick_touch = event.index
				joystick_origin = event.position
			elif camera_touch == -1:
				camera_touch = event.index
				last_drag = event.position
		else:
			if event.index == joystick_touch:
				joystick_touch = -1
				move_vector = Vector2.ZERO
			if event.index == camera_touch:
				camera_touch = -1
	elif event is InputEventScreenDrag:
		if event.index == joystick_touch:
			move_vector = ((event.position - joystick_origin) / 85.0).limit_length(1)
		elif event.index == camera_touch:
			camera_yaw -= event.relative.x * 0.006
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		camera_yaw -= event.relative.x * 0.006
	elif event is InputEventKey and event.pressed and event.keycode == KEY_E:
		interact()

func _process(delta: float) -> void:
	var keyboard := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := keyboard if keyboard.length() > 0.05 else move_vector
	if direction.length() > 0.06:
		var movement := Vector3(direction.x, 0, direction.y).rotated(Vector3.UP, camera_yaw)
		ant.position += movement * delta * 5.0
		ant.rotation.y = atan2(-movement.x, -movement.z)
	if in_nest:
		ant.position.x = clampf(ant.position.x, -15, 15)
		ant.position.z = clampf(ant.position.z, NEST_Z - 8, NEST_Z + 11)
	else:
		ant.position.x = clampf(ant.position.x, -32, 32)
		ant.position.z = clampf(ant.position.z, -20, 12)
	var offset := Vector3(0, 5.8, 9.0).rotated(Vector3.UP, camera_yaw)
	camera.position = camera.position.lerp(ant.position + offset, minf(1, delta * 6))
	camera.look_at(ant.position + Vector3(0, 0.7, 0), Vector3.UP)
	fungus_timer += delta
	if leaves > 0 and fungus_timer >= 8:
		fungus_timer = 0
		leaves -= 1
		fungus += 2
	if eggs > 0:
		egg_timer += delta
		if egg_timer >= 18:
			egg_timer = 0
			eggs -= 1
			spawn_worker()
			show_message("Uma nova operária nasceu!")
	worker_timer += delta
	if worker_timer >= 9:
		worker_timer = 0
		if task_counts[0] > 0:
			leaves += task_counts[0]
		if task_counts[1] > 0 and leaves > 0:
			var produced: int = mini(leaves, task_counts[1])
			leaves -= produced
			fungus += produced * 2
		if task_counts[2] > 0 and fungus > 0:
			var fed: int = mini(fungus, task_counts[2])
			fungus -= fed
			eggs += fed
	for i in range(workers.size()):
		var worker := workers[i]
		var center := FUNGUS_POS if worker_tasks[i] == 1 else (QUEEN_POS if worker_tasks[i] == 2 else EXIT_POS)
		var target := center + Vector3(sin(Time.get_ticks_msec() * 0.001 + i) * 1.5, 0, cos(Time.get_ticks_msec() * 0.001 + i) * 1.5)
		worker.position = worker.position.lerp(target, minf(1, delta * 0.8))
		worker.look_at(Vector3(target.x, worker.position.y, target.z - 0.01), Vector3.UP)
	if message_time > 0:
		message_time -= delta
	status_label.text = "Folhas: %d   Fungos: %d   Ovos: %d   Operárias: %d   Carga: %s" % [leaves, fungus, eggs, workers.size(), carried if carried != "" else "vazia"]
	hint_label.text = message if message_time > 0 else ("Ninho • aproxime-se do cultivo, rainha ou saída" if in_nest else "Superfície • procure folhas ou entrada")
	for i in range(3):
		task_labels[i].text = ["Folhas", "Fungos", "Rainha"][i] + ": %d" % task_counts[i]
	time_to_save += delta
	if time_to_save >= 30:
		time_to_save = 0
		save_game()

func interact() -> void:
	if in_nest:
		if ant.position.distance_to(EXIT_POS) < 3.5:
			in_nest = false
			ant.position = Vector3(0, 0.15, 3.8)
			show_message("Você saiu do formigueiro")
		elif ant.position.distance_to(FUNGUS_POS) < 4:
			if carried == "folha":
				leaves += 1
				carried = ""
				show_message("Folha depositada. Fungos crescerão em alguns segundos!")
			elif carried == "" and fungus > 0:
				fungus -= 1
				carried = "fungo"
				show_message("Fungo coletado. Leve-o à rainha!")
			else:
				show_message("Cultivo: deposite folhas ou pegue fungos disponíveis")
		elif ant.position.distance_to(QUEEN_POS) < 4:
			if carried == "fungo":
				carried = ""
				eggs += 1
				show_message("Rainha alimentada! Ovo gerado. Aguarde a eclosão.")
			else:
				show_message("A rainha precisa de fungos para produzir ovos")
		else:
			show_message("Aproxime-se da câmara de fungos, da rainha ou da saída")
	else:
		if ant.position.distance_to(nest_marker.position) < 3.5:
			in_nest = true
			ant.position = EXIT_POS + Vector3(0, 0.15, 2)
			show_message("Você entrou no formigueiro")
		elif carried == "":
			var closest: Node3D = null
			var distance := 2.7
			for leaf in leaf_nodes:
				if not is_instance_valid(leaf):
					continue
				var d := ant.position.distance_to(leaf.position)
				if d < distance:
					distance = d
					closest = leaf
			if closest != null:
				leaf_nodes.erase(closest)
				closest.queue_free()
				carried = "folha"
				show_message("Folha coletada! Leve-a ao cultivo no ninho")
			else:
				show_message("Aproxime-se de uma folha verde")
		else:
			show_message("Leve a folha até o formigueiro")
	save_game()

func spawn_worker() -> void:
	var worker := make_ant(self, QUEEN_POS + Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2)))
	workers.append(worker)
	worker_tasks.append(-1)

func change_task(task: int, amount: int) -> void:
	if amount > 0:
		var index := worker_tasks.find(-1)
		if index == -1:
			show_message("Sem operárias livres. Aguarde novos ovos!")
			return
		worker_tasks[index] = task
		task_counts[task] += 1
	else:
		var index := worker_tasks.find(task)
		if index == -1:
			return
		worker_tasks[index] = -1
		task_counts[task] -= 1
	save_game()

func show_message(value: String) -> void:
	message = value
	message_time = 5.0

func save_game() -> void:
	var data := {"leaves": leaves, "fungus": fungus, "eggs": eggs, "carried": carried, "in_nest": in_nest, "workers": worker_tasks, "ant_pos": [ant.position.x, ant.position.y, ant.position.z]}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	leaves = int(parsed.get("leaves", 0))
	fungus = int(parsed.get("fungus", 0))
	eggs = int(parsed.get("eggs", 0))
	carried = str(parsed.get("carried", ""))
	in_nest = bool(parsed.get("in_nest", false))
	var p: Array = parsed.get("ant_pos", [0, 0.15, 0])
	if p.size() == 3:
		ant.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	for t in parsed.get("workers", []):
		spawn_worker()
		var task := int(t)
		if task >= 0 and task < 3:
			worker_tasks[-1] = task
			task_counts[task] += 1
