extends Node3D
## 同一格 (x, y) 在三维中落到 (X=x, Z=y)。三维 Y 表示高度。
## 方块模型与拾取包围盒在同一处创建，避免显示和点击位置错位。

const INVALID_CELL := Vector2i(-1, -1)
var town: TownState
var pick_boxes: Array[Dictionary] = []
var terrain_pick_count: int = 0
var selected_cell: Vector2i = TownState.INVALID_CELL
var selection_mark: Node3D

@onready var terrain: Node3D = $Terrain
@onready var buildings_root: Node3D = $Buildings
@onready var camera: Camera3D = $Camera3D


func setup(state: TownState) -> void:
    town = state
    camera.look_at(Vector3(8.0, 0.0, 6.0))
    _create_terrain()
    _create_selection_mark()
    refresh()


func _material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 1.0
    return material


func _box(parent: Node3D, center: Vector3, size: Vector3,
        material: Material, cell: Vector2i = INVALID_CELL) -> void:
    var mesh := BoxMesh.new()
    mesh.size = size
    var instance := MeshInstance3D.new()
    instance.mesh = mesh
    instance.material_override = material
    instance.position = center
    parent.add_child(instance)
    if cell != INVALID_CELL:
        pick_boxes.append({"bounds": AABB(center - size * 0.5, size), "cell": cell})


func _create_terrain() -> void:
    var land := _material(Color("769653"))
    var land_alternate := _material(Color("809e5c"))
    var water := _material(Color("427fa5"))
    var base := _material(Color("384f3d"))
    _box(terrain, Vector3(8, -0.4, 6), Vector3(16.2, 0.5, 12.2), base)
    for y in range(TownState.HEIGHT):
        for x in range(TownState.WIDTH):
            var cell := Vector2i(x, y)
            var material: Material = land if (x + y) % 2 == 0 else land_alternate
            if town.is_water(cell):
                material = water
            # 格子顶面统一为 Y=0；格子间细缝仅作视觉分隔。
            _box(terrain, Vector3(x + 0.5, -0.1, y + 0.5),
                Vector3(0.97, 0.2, 0.97), material, cell)
    terrain_pick_count = pick_boxes.size()


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
        # 边框贴着地块顶面（三维 Y 由子盒子承担，父节点落在地面高度）。
        selection_mark.position = Vector3(selected_cell.x + 0.5, 0.0, selected_cell.y + 0.5)
        selection_mark.visible = true
    else:
        selection_mark.visible = false


func refresh() -> void:
    # 原型建筑数量很少，先采用简单重建，避免引入同步缓存。
    for child in buildings_root.get_children():
        buildings_root.remove_child(child)
        child.queue_free()
    pick_boxes.resize(terrain_pick_count)
    for cell: Vector2i in town.buildings:
        match town.buildings[cell]:
            &"farm":
                _build_farm(cell)
            &"lumberyard":
                _build_lumberyard(cell)
            &"hq":
                _build_hq(cell)
    _update_selection_mark()


func _build_farm(cell: Vector2i) -> void:
    var origin := Vector3(cell.x, 0, cell.y)
    var earth := _material(Color("b99258"))
    var crop := _material(Color("d9bb66"))
    var wall := _material(Color("e4d2ac"))
    var roof := _material(Color("985947"))
    _box(buildings_root, origin + Vector3(0.5, 0.055, 0.5), Vector3(0.8, 0.11, 0.8), earth, cell)
    for row in range(3):
        _box(buildings_root, origin + Vector3(0.39, 0.15, 0.28 + row * 0.22),
            Vector3(0.42, 0.08, 0.065), crop, cell)
    _box(buildings_root, origin + Vector3(0.73, 0.29, 0.68), Vector3(0.24, 0.36, 0.28), wall, cell)
    _box(buildings_root, origin + Vector3(0.73, 0.51, 0.68), Vector3(0.32, 0.08, 0.36), roof, cell)


func _build_lumberyard(cell: Vector2i) -> void:
    var origin := Vector3(cell.x, 0, cell.y)
    var log_mat := _material(Color("a97e42"))
    var log_dark := _material(Color("7c5a2c"))
    var post := _material(Color("5f4520"))
    # 底层两根横木 + 上层一根，旁边立两根柱子示意伐木场料堆。
    _box(buildings_root, origin + Vector3(0.38, 0.07, 0.35), Vector3(0.6, 0.14, 0.22), log_mat, cell)
    _box(buildings_root, origin + Vector3(0.38, 0.07, 0.65), Vector3(0.6, 0.14, 0.22), log_dark, cell)
    _box(buildings_root, origin + Vector3(0.38, 0.21, 0.5), Vector3(0.6, 0.14, 0.22), log_mat, cell)
    _box(buildings_root, origin + Vector3(0.78, 0.16, 0.28), Vector3(0.08, 0.32, 0.08), post, cell)
    _box(buildings_root, origin + Vector3(0.78, 0.16, 0.72), Vector3(0.08, 0.32, 0.08), post, cell)


func _build_hq(cell: Vector2i) -> void:
    # 主体压在 0.6 高以内：斜俯视相机下不遮挡相邻格心的射线，192 格拾取检查才稳定。
    var origin := Vector3(cell.x, 0, cell.y)
    var stone := _material(Color("77808c"))
    var stone_dark := _material(Color("525a64"))
    var roof := _material(Color("8c4a3c"))
    var flag := _material(Color("ffd75e"))
    _box(buildings_root, origin + Vector3(0.5, 0.15, 0.5), Vector3(0.9, 0.3, 0.9), stone, cell)
    _box(buildings_root, origin + Vector3(0.5, 0.425, 0.5), Vector3(0.65, 0.25, 0.65), stone_dark, cell)
    _box(buildings_root, origin + Vector3(0.5, 0.58, 0.5), Vector3(0.75, 0.06, 0.75), roof, cell)
    _box(buildings_root, origin + Vector3(0.5, 0.655, 0.5), Vector3(0.05, 0.09, 0.05), flag, cell)


func cell_at_position(local_position: Vector2) -> Vector2i:
    var origin := camera.project_ray_origin(local_position)
    var direction := camera.project_ray_normal(local_position)
    var nearest_distance: float = INF
    var nearest_cell := INVALID_CELL
    # 当前全是轴对齐方块，射线与方块求交即可，不依赖物理帧或碰撞插件。
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
