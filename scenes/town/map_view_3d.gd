extends Node3D
## 同一格 (x, y) 在三维中落到 (X=x, Z=y)，三维 Y 是高度。
## 方块模型与拾取包围盒在同一处创建，保证显示和点击不错位。
## 地图尺寸不固定（D20）：地面、相机距离都按 town.map_size 计算。

const INVALID_CELL := Vector2i(-1, -1)
const CAM_OFFSET := Vector3(13, 18, 16)  # 固定斜俯视方向（P08 起沿用）
const DEFAULT_ZOOM := 24.0
const ZOOM_MIN := 6.0
const ZOOM_MAX := 68.0  # 60×60 全景：对角格中心也要完整落在视口内

var town: TownState
var pick_boxes: Array[Dictionary] = []
var terrain_pick_count: int = 0
var selected_cell: Vector2i = TownState.INVALID_CELL
var selection_mark: Node3D
var cam_target := Vector3.ZERO
var zoom_size := DEFAULT_ZOOM
var _panning := false
var _material_cache: Dictionary = {}
var _mesh_cache: Dictionary = {}

@onready var terrain: Node3D = $Terrain
@onready var buildings_root: Node3D = $Buildings
@onready var camera: Camera3D = $Camera3D


func setup(state: TownState) -> void:
	town = state
	_rebuild_terrain()
	cam_target = Vector3(town.hq_cell.x + 0.5, 0.0, town.hq_cell.y + 0.5)
	zoom_size = DEFAULT_ZOOM
	_apply_camera()
	_create_selection_mark()
	refresh()


func _material(color: Color) -> StandardMaterial3D:
	if not _material_cache.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 1.0
		_material_cache[color] = material
	return _material_cache[color]


func _mesh(size: Vector3) -> BoxMesh:
	# 3600 格共享少量网格：只有尺寸不同的方块才需要新 BoxMesh。
	if not _mesh_cache.has(size):
		var mesh := BoxMesh.new()
		mesh.size = size
		_mesh_cache[size] = mesh
	return _mesh_cache[size]


func _box(parent: Node3D, center: Vector3, size: Vector3,
		material: Material, cell: Vector2i = INVALID_CELL) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh(size)
	instance.material_override = material
	instance.position = center
	parent.add_child(instance)
	if cell != INVALID_CELL:
		pick_boxes.append({ "bounds": AABB(center - size * 0.5, size), "cell": cell })


func _clear_children(node: Node3D) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _rebuild_terrain() -> void:
	# 整个地图（含预置地形装饰）重建：地图尺寸/内容变化或首次进入时调用。
	_clear_children(terrain)
	pick_boxes.clear()
	var half := Vector3(town.map_size.x * 0.5, -0.4, town.map_size.y * 0.5)
	_box(terrain, half, Vector3(town.map_size.x + 0.2, 0.5, town.map_size.y + 0.2),
		_material(Color("384f3d")))
	for y: int in range(town.map_size.y):
		for x: int in range(town.map_size.x):
			var cell := Vector2i(x, y)
			var height: float = town.terrain_height(cell)
			var kind: StringName = town.terrain_kind(cell)
			var material: Material
			match kind:
				&"water":
					material = _material(Color("427fa5"))
				&"highland":
					material = _material(Color("a8b868"))
				&"grass":
					material = _material(Color("6ca16e") if (x + y) % 2 == 0 else Color("75a878"))
				&"forest":
					material = _material(Color("4c7146") if (x + y) % 2 == 0 else Color("527a4b"))
				&"stone":
					material = _material(Color("85847b"))
				&"iron":
					material = _material(Color("7f7b6d"))
				_:
					material = _material(Color("769653") if (x + y) % 2 == 0 else Color("809e5c"))
			# 盒子从 -0.2 顶到地形高度：高地边缘是实心侧壁，不是悬浮薄板。
			_box(terrain, Vector3(x + 0.5, (height - 0.2) * 0.5, y + 0.5),
				Vector3(0.97, height + 0.2, 0.97), material, cell)
			_resource_decoration(cell, kind, height)
	terrain_pick_count = pick_boxes.size()


func _resource_decoration(cell: Vector2i, kind: StringName, height: float) -> void:
	# 资源区块的示意小模型，参与拾取（点击选中所在格）。
	var origin := Vector3(cell.x, height, cell.y)
	match kind:
		&"forest":
			_box(terrain, origin + Vector3(0.5, 0.12, 0.5), Vector3(0.1, 0.24, 0.1),
				_material(Color("6d5433")), cell)
			_box(terrain, origin + Vector3(0.5, 0.38, 0.5), Vector3(0.5, 0.3, 0.5),
				_material(Color("2f5d38")), cell)
		&"stone":
			_box(terrain, origin + Vector3(0.5, 0.18, 0.5), Vector3(0.46, 0.36, 0.46),
				_material(Color("b3b2a6")), cell)
		&"iron":
			_box(terrain, origin + Vector3(0.5, 0.15, 0.5), Vector3(0.4, 0.3, 0.4),
				_material(Color("a3765a")), cell)


func _map_diagonal() -> float:
	return Vector2(town.map_size).length()


func _apply_camera() -> void:
	# 相机距离随地图对角线拉远：否则 60×60 地图的近角会落到相机平面之后被裁掉。
	# 正交投影下距离不影响视野大小，只影响近远裁剪面。
	var distance := 30.0 + _map_diagonal()
	camera.size = zoom_size
	camera.far = distance + _map_diagonal() + 10.0
	camera.position = cam_target + CAM_OFFSET.normalized() * distance
	camera.look_at(cam_target)


func zoom_step(steps: float) -> void:
	# steps > 0 放大（视野变小）。缩放围绕画面中心。
	zoom_size = clampf(zoom_size * pow(0.9, steps), ZOOM_MIN, ZOOM_MAX)
	_apply_camera()


func begin_pan() -> void:
	_panning = true


func end_pan() -> void:
	_panning = false


func is_panning() -> bool:
	return _panning


func pan_by(screen_delta: Vector2) -> void:
	if not _panning or town == null:
		return
	# 抓住地图拖动：目标点沿屏幕位移的反方向移动。
	var viewport_height: float = camera.get_viewport().get_visible_rect().size.y
	var world_per_px: float = zoom_size / maxf(1.0, viewport_height)
	var right := camera.global_transform.basis.x
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	cam_target += (-right * screen_delta.x + forward * screen_delta.y) * world_per_px
	cam_target.x = clampf(cam_target.x, -2.0, town.map_size.x + 2.0)
	cam_target.z = clampf(cam_target.z, -2.0, town.map_size.y + 2.0)
	_apply_camera()


func frame_map() -> void:
	# 全景：居中并缩放到整张地图可见。
	cam_target = Vector3(town.map_size.x * 0.5, 0.0, town.map_size.y * 0.5)
	zoom_size = ZOOM_MAX
	_apply_camera()


func _create_selection_mark() -> void:
	# 选中高亮是贴地边框：沿选中格子边缘一圈，与地块重叠显示，不悬浮、不与建筑穿插。
	# 长条覆盖整边，短条填补两侧，避免半透明材质在四角叠加变亮。
	selection_mark = Node3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.84, 0.35, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var long_mesh := BoxMesh.new()
	long_mesh.size = Vector3(0.98, 0.04, 0.08)
	var short_mesh := BoxMesh.new()
	# 东/西两条边沿 Z 方向延伸；X/Z 尺寸不能与长条写反，否则变成横穿格子的棒。
	short_mesh.size = Vector3(0.08, 0.04, 0.82)
	var pieces := [
		[long_mesh, Vector3(0.0, 0.03, 0.45)],
		[long_mesh, Vector3(0.0, 0.03, -0.45)],
		[short_mesh, Vector3(0.45, 0.03, 0.0)],
		[short_mesh, Vector3(-0.45, 0.03, 0.0)],
	]
	for piece: Array in pieces:
		var instance := MeshInstance3D.new()
		instance.mesh = piece[0]
		instance.material_override = material
		instance.position = piece[1]
		selection_mark.add_child(instance)
	selection_mark.visible = false
	add_child(selection_mark)


func _update_selection_mark() -> void:
	if town != null and town.buildings.has(selected_cell):
		# 边框贴着该格地形顶面：高格上的建筑高亮同样可见。
		selection_mark.position = Vector3(
			selected_cell.x + 0.5, town.terrain_height(selected_cell), selected_cell.y + 0.5)
		selection_mark.visible = true
	else:
		selection_mark.visible = false


func refresh() -> void:
	# 建筑数量少，先简单重建；地形不动，避免整图重建。
	_clear_children(buildings_root)
	pick_boxes.resize(terrain_pick_count)
	for cell: Vector2i in town.buildings:
		match town.buildings[cell]:
			&"farm":
				_build_farm(cell)
			&"lumberyard":
				_build_lumberyard(cell)
			&"house":
				_build_house(cell)
			&"hq":
				_build_hq(cell)
	# 工地：基座板 + 随进度伸长的绿色进度条（E04）。
	for entry: Dictionary in town.construction_queue:
		var site_def: BuildingDef = town.building_def(entry["def_id"])
		if site_def == null:
			continue
		var site_origin: Vector2i = entry["origin"]
		var site_size := _footprint_size_for(site_def)
		var site_origin_v := Vector3(site_origin.x, town.terrain_height(site_origin), site_origin.y)
		var site_center := Vector3(site_size.x * 0.5, 0.0, site_size.y * 0.5)
		var fill: Color = Color(0.85, 0.7, 0.25) if entry["active"] else Color(0.5, 0.5, 0.55)
		_box(buildings_root, site_origin_v + site_center + Vector3(0.0, 0.03, 0.0),
			Vector3(site_size.x - 0.1, 0.06, site_size.y - 0.1), _material(fill), site_origin)
		var span: float = site_size.x - 0.2
		var bar_w: float = maxf(0.1, span * clampf(float(entry["progress"]), 0.05, 1.0))
		_box(buildings_root,
			site_origin_v + Vector3(site_size.x * 0.5 - span * 0.5 + bar_w * 0.5, 0.08, site_size.y - 0.12),
			Vector3(bar_w, 0.06, 0.12), _material(Color("7ec97e")), site_origin)
	# 等级小块：Lv≥2 的建筑在前缘摆 (level-1) 个金色小方块。
	for origin: Vector2i in town.buildings:
		var level: int = town.building_level(origin)
		if level < 2:
			continue
		var bdef: BuildingDef = town.building_def(town.buildings[origin])
		var bsize := _footprint_size_for(bdef)
		var borigin := Vector3(origin.x, town.terrain_height(origin), origin.y)
		for i: int in range(level - 1):
			_box(buildings_root,
				borigin + Vector3(0.35 + i * 0.22, 0.08, bsize.y - 0.12),
				Vector3(0.14, 0.14, 0.14), _material(Color("ffd75e")), origin)
	_update_selection_mark()


func rebuild_all() -> void:
	_rebuild_terrain()
	refresh()


func _footprint_size_for(def: BuildingDef) -> Vector2:
	return Vector2(def.footprint) if def != null else Vector2.ONE


func _footprint_size(cell: Vector2i) -> Vector2:
	var def := building_def_of(cell)
	return Vector2(def.footprint) if def != null else Vector2.ONE


func building_def_of(cell: Vector2i) -> BuildingDef:
	return town.building_def(town.buildings.get(cell, &""))


func _build_farm(cell: Vector2i) -> void:
	# 农田（E03 反馈后 2×2）：整块田垄 + 三条作物带 + 角上小屋；高度不遮挡邻格射线。
	var origin := Vector3(cell.x, town.terrain_height(cell), cell.y)
	var size := _footprint_size(cell)
	var center := Vector3(size.x * 0.5, 0.0, size.y * 0.5)
	var earth := _material(Color("b99258"))
	var crop := _material(Color("d9bb66"))
	var wall := _material(Color("e4d2ac"))
	var roof := _material(Color("985947"))
	_box(buildings_root, origin + center + Vector3(0.0, 0.055, 0.0),
		Vector3(size.x - 0.06, 0.11, size.y - 0.06), earth, cell)
	for row in range(3):
		_box(buildings_root,
			origin + center + Vector3((row - 1) * size.x * 0.24, 0.15, -size.y * 0.12),
			Vector3(size.x * 0.16, 0.08, size.y * 0.5), crop, cell)
	_box(buildings_root, origin + center + Vector3(size.x * 0.3, 0.25, size.y * 0.3),
		Vector3(size.x * 0.24, 0.3, size.y * 0.24), wall, cell)
	_box(buildings_root, origin + center + Vector3(size.x * 0.3, 0.44, size.y * 0.3),
		Vector3(size.x * 0.3, 0.07, size.y * 0.3), roof, cell)


func _build_lumberyard(cell: Vector2i) -> void:
	# 伐木场（2×2）：两层料堆 + 两根立柱。
	var origin := Vector3(cell.x, town.terrain_height(cell), cell.y)
	var size := _footprint_size(cell)
	var center := Vector3(size.x * 0.5, 0.0, size.y * 0.5)
	var log_mat := _material(Color("a97e42"))
	var log_dark := _material(Color("7c5a2c"))
	var post := _material(Color("5f4520"))
	_box(buildings_root, origin + center + Vector3(-size.x * 0.12, 0.07, -size.y * 0.15),
		Vector3(size.x * 0.42, 0.14, size.y * 0.2), log_mat, cell)
	_box(buildings_root, origin + center + Vector3(-size.x * 0.12, 0.07, size.y * 0.15),
		Vector3(size.x * 0.42, 0.14, size.y * 0.2), log_dark, cell)
	_box(buildings_root, origin + center + Vector3(-size.x * 0.12, 0.21, 0.0),
		Vector3(size.x * 0.42, 0.14, size.y * 0.2), log_mat, cell)
	_box(buildings_root, origin + center + Vector3(size.x * 0.28, 0.16, -size.y * 0.2),
		Vector3(0.08, 0.32, 0.08), post, cell)
	_box(buildings_root, origin + center + Vector3(size.x * 0.28, 0.16, size.y * 0.2),
		Vector3(0.08, 0.32, 0.08), post, cell)


func _build_house(cell: Vector2i) -> void:
	# 民居（2×2）：墙体 + 双层坡屋顶 + 门，高度压在 0.45 内，不遮挡邻格射线。
	var origin := Vector3(cell.x, town.terrain_height(cell), cell.y)
	var size := _footprint_size(cell)
	var center := Vector3(size.x * 0.5, 0.0, size.y * 0.5)
	var wall := _material(Color("c8a06a"))
	var roof := _material(Color("8a5a3c"))
	var door := _material(Color("6d4a30"))
	_box(buildings_root, origin + center + Vector3(0.0, 0.14, 0.0),
		Vector3(size.x - 0.3, 0.28, size.y - 0.3), wall, cell)
	_box(buildings_root, origin + center + Vector3(0.0, 0.31, 0.0),
		Vector3(size.x - 0.06, 0.06, size.y - 0.06), roof, cell)
	_box(buildings_root, origin + center + Vector3(0.0, 0.39, 0.0),
		Vector3(size.x * 0.55, 0.1, size.y * 0.55), roof, cell)
	_box(buildings_root, origin + center + Vector3(0.0, 0.1, size.y * 0.5 - 0.02),
		Vector3(0.16, 0.2, 0.05), door, cell)


func _build_hq(cell: Vector2i) -> void:
	# 大本营占地 2×2（E01.b）：整块低平台 + 居中主体。边缘压在 0.15 内，
	# 保证斜俯视相机下相邻格心的拾取射线不被遮挡；主体抬高也不越过 0.6。
	var def: BuildingDef = TownState.building_def(&"hq")
	var footprint: Vector2i = def.footprint if def != null else Vector2i.ONE
	var width := float(footprint.x)
	var depth := float(footprint.y)
	var origin := Vector3(cell.x, town.terrain_height(cell), cell.y)
	var center := Vector3(width * 0.5, 0.0, depth * 0.5)
	var stone := _material(Color("77808c"))
	var stone_dark := _material(Color("525a64"))
	var roof := _material(Color("8c4a3c"))
	var flag := _material(Color("ffd75e"))
	_box(buildings_root, origin + center + Vector3(0.0, 0.075, 0.0),
		Vector3(width - 0.06, 0.15, depth - 0.06), stone, cell)
	_box(buildings_root, origin + center + Vector3(0.0, 0.35, 0.0),
		Vector3(width * 0.45, 0.4, depth * 0.45), stone_dark, cell)
	_box(buildings_root, origin + center + Vector3(0.0, 0.575, 0.0),
		Vector3(width * 0.55, 0.05, depth * 0.55), roof, cell)
	_box(buildings_root, origin + center + Vector3(0.0, 0.66, 0.0),
		Vector3(0.05, 0.09, 0.05), flag, cell)


func cell_at_position(local_position: Vector2) -> Vector2i:
	var origin := camera.project_ray_origin(local_position)
	var direction := camera.project_ray_normal(local_position)
	var nearest_distance: float = INF
	var nearest_cell := INVALID_CELL
	# 当前全是轴对齐方块，射线与包围盒求交即可，不依赖物理帧或碰撞插件。
	# 总是取最近的表面，点击农田的小屋也会选中该农田。
	for entry: Dictionary in pick_boxes:
		var bounds: AABB = entry["bounds"]
		var hit: Variant = bounds.intersects_ray(origin, direction)
		if hit is Vector3:
			var distance: float = origin.distance_squared_to(hit)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_cell = entry["cell"]
	return nearest_cell
