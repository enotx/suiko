class_name TownState
extends RefCounted
## 城镇的规则和状态：只使用格子坐标，不依赖场景、鼠标或画面。
## 建筑种类来自 defs/*.tres 配表（D17），本类只管理运行实例。
## 地图布局来自调色板图片（D26）：1 像素 = 1 格，颜色 = 地形，见 MAP_PALETTE。

const STARTING_WOOD: int = 100
const INVALID_CELL: Vector2i = Vector2i(-1, -1)
const WORKER_NAME: String = "阮小二"
const PROGRESS_UNIT: float = 1.0
const SAVE_FORMAT_VERSION: int = 4
const SAVE_FORMAT_VERSION_V3: int = 3
const SAVE_FORMAT_VERSION_V2: int = 2
const SAVE_FORMAT_VERSION_V1: int = 1

# 旧 16×12 默认地图（v1/v2 存档迁移专用），不再是新游戏默认。
const LEGACY_MAP_SIZE: Vector2i = Vector2i(16, 12)
const LEGACY_HQ_CELL: Vector2i = Vector2i(8, 5)
# 存档与布局图的安全上限：只防异常数据撑爆内存，不是内容上限（D20 不写死玩法尺寸）。
const MAX_MAP_SIDE: int = 512
# 布局图逐像素比色的每通道容差；无损导入下真实误差应为 0。
const COLOR_TOLERANCE: int = 2

# 地形（D18 三态 + E01 新区块）：高度与可建性都由地形决定。
const TERRAIN_WATER: StringName = &"water"
const TERRAIN_PLAIN: StringName = &"plain"
const TERRAIN_GRASS: StringName = &"grass"
const TERRAIN_HIGHLAND: StringName = &"highland"
const TERRAIN_FOREST: StringName = &"forest"
const TERRAIN_STONE: StringName = &"stone"
const TERRAIN_IRON: StringName = &"iron"
const HIGHLAND_HEIGHT: float = 0.5
# 资源区块：表达资源所在，采集玩法接入前暂不可建造。
const RESOURCE_TERRAINS: Dictionary = {
	TERRAIN_FOREST: true, TERRAIN_STONE: true, TERRAIN_IRON: true,
}

# 存档地形短码（v3 起使用；大小写敏感）。
const TERRAIN_CODES: Dictionary = {
	"w": TERRAIN_WATER, "p": TERRAIN_PLAIN, "g": TERRAIN_GRASS, "h": TERRAIN_HIGHLAND,
	"F": TERRAIN_FOREST, "S": TERRAIN_STONE, "I": TERRAIN_IRON,
}

# 调色板地图（D26）：颜色 → 地形；品红是大本营标记（该格按平地处理，不是地形）。
const HQ_MARKER: StringName = &"@hq"
const MAP_PALETTE: Dictionary = {
	Color("769653"): TERRAIN_PLAIN,
	Color("6ca16e"): TERRAIN_GRASS,
	Color("a8b868"): TERRAIN_HIGHLAND,
	Color("427fa5"): TERRAIN_WATER,
	Color("3f6d43"): TERRAIN_FOREST,
	Color("9a9a8f"): TERRAIN_STONE,
	Color("a0785c"): TERRAIN_IRON,
	Color("ff00ff"): HQ_MARKER,
}

const DEFAULT_MAP_TEXTURE: Texture2D = preload("res://defs/maps/test_town.png")
const DEFAULT_MAP_SIDECAR: JSON = preload("res://defs/maps/test_town.json")

# 配表入口：键是建筑 id，值是 BuildingDef 资源。新增建筑在这里登记。
const BUILDING_DEFS: Dictionary = {
	&"farm": preload("res://defs/farm.tres"),
	&"lumberyard": preload("res://defs/lumberyard.tres"),
	&"hq": preload("res://defs/hq.tres"),
}

var wood: int = STARTING_WOOD
var grain: int = 0
# 运行实例：格子 → 建筑 id（StringName）。预置大本营占一格。
var buildings: Dictionary = {}
# 地图地形：格子 → TERRAIN_*。来自布局图，随存档保存（v3 起记录，v4 带尺寸）。
var terrain: Dictionary = {}
# 地图数据：尺寸与名称来自布局文件，大本营预置格随布局。
var map_size: Vector2i = LEGACY_MAP_SIZE
var map_name: String = "无名城镇"
var hq_cell: Vector2i = LEGACY_HQ_CELL
# 唯一人物的教学占位：worker_cell 为 INVALID_CELL 表示空闲。
# 分工只记录在人物一侧（此处），建筑不反向存储工人，天然保证一人只能占一个工位。
var worker_cell: Vector2i = INVALID_CELL
# 每块有产出建筑各自的生产进度（0..PROGRESS_UNIT），调岗保留在建筑上、不跟人走。
var farm_progress: Dictionary = {}


func _init() -> void:
	_reset_preset()


static func building_def(id: StringName) -> BuildingDef:
	return BUILDING_DEFS.get(id)


static func validate_defs() -> Array[String]:
	# 启动期自检：重复 id、缺失字段、非法产出类型都算配表错误。
	var problems: Array[String] = []
	var seen := {}
	for id: StringName in BUILDING_DEFS:
		var def: BuildingDef = BUILDING_DEFS[id]
		if def == null:
			problems.append("建筑 %s 缺少定义资源" % id)
			continue
		if seen.has(def.id) or def.id != id:
			problems.append("建筑 id 不一致或重复：%s / %s" % [id, def.id])
		seen[def.id] = true
		if def.display_name.is_empty():
			problems.append("建筑 %s 缺少显示名称" % id)
		if def.produces != &"" and def.produces != &"grain" and def.produces != &"wood":
			problems.append("建筑 %s 的产出类型无效：%s" % [id, def.produces])
		if def.base_rate < 0.0 or def.worked_rate < 0.0:
			problems.append("建筑 %s 的产出速率为负" % id)
		if not def.unique and def.wood_cost <= 0:
			problems.append("可建造建筑 %s 的造价必须大于 0" % id)
	return problems


## 解析调色板布局图。返回 { "error": 原因 } 或
## { "name", "size", "terrain", "hq_cell" }；不触碰任何运行状态。
static func parse_layout(texture: Texture2D, sidecar: Variant = null) -> Dictionary:
	if texture == null:
		return { "error": "布局图片缺失。" }
	var image: Image = texture.get_image()
	if image.is_compressed():
		var decompress_error: int = image.decompress()
		if decompress_error != OK:
			return { "error": "布局图片无法解压（错误码 %d）。" % decompress_error }
	var width := image.get_width()
	var height := image.get_height()
	if width < 1 or height < 1 or width > MAX_MAP_SIDE or height > MAX_MAP_SIDE:
		return { "error": "布局图片尺寸 %dx%d 超出范围（1..%d）。" % [width, height, MAX_MAP_SIDE] }
	var terrain_result := {}
	var hq_cells: Array[Vector2i] = []
	for y: int in range(height):
		for x: int in range(width):
			var pixel := image.get_pixel(x, y)
			if pixel.a8 < 250:
				return { "error": "布局图第 (%d, %d) 格不是不透明像素。" % [x, y] }
			var kind := _match_palette(pixel)
			if kind == &"":
				return { "error": "布局图第 (%d, %d) 格颜色 #%s 不在调色板中。" % [
					x, y, pixel.to_html(false),
				] }
			if kind == HQ_MARKER:
				hq_cells.append(Vector2i(x, y))
				kind = TERRAIN_PLAIN
			terrain_result[Vector2i(x, y)] = kind
	if hq_cells.is_empty():
		return { "error": "布局图缺少大本营标记（品红 #ff00ff）。" }
	if hq_cells.size() > 1:
		return { "error": "布局图的大本营标记（品红）只能有一个，找到 %d 个。" % hq_cells.size() }
	var name_text := "无名城镇"
	if sidecar is Dictionary and typeof(sidecar.get("name")) == TYPE_STRING \
			and not str(sidecar["name"]).is_empty():
		name_text = str(sidecar["name"])
	return {
		"name": name_text,
		"size": Vector2i(width, height),
		"terrain": terrain_result,
		"hq_cell": hq_cells[0],
	}


static func _match_palette(pixel: Color) -> StringName:
	for color: Color in MAP_PALETTE:
		if absi(pixel.r8 - color.r8) <= COLOR_TOLERANCE \
				and absi(pixel.g8 - color.g8) <= COLOR_TOLERANCE \
				and absi(pixel.b8 - color.b8) <= COLOR_TOLERANCE:
			return MAP_PALETTE[color]
	return &""


## 用解析结果整体替换地图与大本营预置；只应传入 parse_layout 的成功结果。
func apply_layout(layout: Dictionary) -> void:
	map_size = layout["size"]
	map_name = layout["name"]
	terrain = layout["terrain"]
	hq_cell = layout["hq_cell"]
	buildings = { hq_cell: &"hq" }
	farm_progress = {}


func load_default_layout() -> String:
	return load_layout_texture(DEFAULT_MAP_TEXTURE, DEFAULT_MAP_SIDECAR.data)


func load_layout_texture(texture: Texture2D, sidecar: Variant = null) -> String:
	var layout := parse_layout(texture, sidecar)
	if layout.has("error"):
		return layout["error"]
	apply_layout(layout)
	return ""


func building_name(cell: Vector2i) -> String:
	var def := building_def(buildings.get(cell, &""))
	return def.display_name if def != null else "未知建筑"


func farm_progress_ratio(cell: Vector2i) -> float:
	return clampf(farm_progress.get(cell, 0.0) / PROGRESS_UNIT, 0.0, 1.0)


func advance_time(delta: float) -> void:
	# 唯一模拟入口：接收游戏经过的秒数。长时间步通过 while 累计多个完整周期，不丢产量。
	for cell: Vector2i in buildings:
		var def := building_def(buildings[cell])
		if def == null or def.produces == &"":
			continue
		var rate: float = def.worked_rate if worker_cell == cell else def.base_rate
		var progress: float = farm_progress.get(cell, 0.0) + rate * delta
		while progress >= PROGRESS_UNIT:
			progress -= PROGRESS_UNIT
			if def.produces == &"grain":
				grain += 1
			elif def.produces == &"wood":
				wood += 1
		farm_progress[cell] = progress


func worker_is_at(cell: Vector2i) -> bool:
	return worker_cell == cell


func assign_worker(cell: Vector2i) -> String:
	# 只在目标确认有效后才改动 worker_cell；失败不影响现有工作（调岗原子性）。
	var def := building_def(buildings.get(cell, &""))
	if def == null:
		return "那里没有可工作的建筑。"
	if not def.worker_assignable:
		return "%s不需要工人。" % def.display_name
	if worker_cell == cell:
		return "阮小二已经在这里工作了。"
	worker_cell = cell
	return "阮小二已到 (%d, %d) %s工作。" % [cell.x, cell.y, def.display_name]


func withdraw_worker() -> String:
	if worker_cell == INVALID_CELL:
		return "阮小二本来就是空闲的。"
	worker_cell = INVALID_CELL
	return "阮小二已撤回，当前空闲。"


func to_save_data() -> Dictionary:
	# 显式编码格子坐标与进度，不序列化任何节点或资源引用；Vector2i 不作字典键。
	var buildings_data: Array = []
	for cell: Vector2i in buildings:
		buildings_data.append({
			"x": cell.x,
			"y": cell.y,
			"kind": String(buildings[cell]),
			"progress": farm_progress.get(cell, 0.0),
		})
	return {
		"version": SAVE_FORMAT_VERSION,
		"map_size": [map_size.x, map_size.y],
		"map_name": map_name,
		"wood": wood,
		"grain": grain,
		"worker_x": worker_cell.x if worker_cell != INVALID_CELL else -1,
		"worker_y": worker_cell.y if worker_cell != INVALID_CELL else -1,
		"buildings": buildings_data,
		"terrain": _terrain_data(),
	}


func _terrain_data() -> Array:
	var entries: Array = []
	for cell: Vector2i in terrain:
		entries.append({
			"x": cell.x, "y": cell.y, "t": terrain_code(terrain[cell]),
		})
	return entries


## 旧 16×12 默认地形（西三列水面 + 东北角高地），仅供 v1/v2 存档迁移。
static func _legacy_terrain_data() -> Array:
	var entries: Array = []
	for y: int in range(LEGACY_MAP_SIZE.y):
		for x: int in range(LEGACY_MAP_SIZE.x):
			var kind := TERRAIN_PLAIN
			if x < 3:
				kind = TERRAIN_WATER
			elif x >= 12 and y <= 4:
				kind = TERRAIN_HIGHLAND
			entries.append({ "x": x, "y": y, "t": terrain_code(kind) })
	return entries


static func terrain_code(kind: StringName) -> String:
	for code: String in TERRAIN_CODES:
		if TERRAIN_CODES[code] == kind:
			return code
	return "p"


## 逐项校验地形数据；缺失格子按平地补齐。返回 { "error" } 或 { "data" }。
static func _parse_terrain_data(entries: Variant, size: Vector2i) -> Dictionary:
	if typeof(entries) != TYPE_ARRAY:
		return { "error": "存档缺少地形数据。" }
	var loaded := {}
	for entry: Variant in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			return { "error": "存档中的地形数据损坏。" }
		var cell := Vector2i(int(entry.get("x", -99)), int(entry.get("y", -99)))
		var kind: StringName = TERRAIN_CODES.get(str(entry.get("t", "")), &"")
		if not _in_bounds(cell, size) or kind == &"" or loaded.has(cell):
			return { "error": "存档中的地形数据损坏。" }
		loaded[cell] = kind
	for y: int in range(size.y):
		for x: int in range(size.x):
			loaded[Vector2i(x, y)] = loaded.get(Vector2i(x, y), TERRAIN_PLAIN)
	return { "data": loaded }


static func _parse_map_size(raw: Variant) -> Dictionary:
	# 缺省按旧 16×12 处理；异常值报错，不静默放大。
	if raw == null:
		return { "data": LEGACY_MAP_SIZE }
	if typeof(raw) != TYPE_ARRAY or raw.size() != 2:
		return { "error": "存档中的地图尺寸损坏。" }
	var width := int(raw[0])
	var height := int(raw[1])
	if width < 1 or height < 1 or width > MAX_MAP_SIDE or height > MAX_MAP_SIDE:
		return { "error": "存档中的地图尺寸超出范围。" }
	return { "data": Vector2i(width, height) }


func apply_save_data(data: Variant) -> String:
	# 全部校验通过后才整体替换状态；任何失败返回中文原因，且不改动当前经营。
	if typeof(data) != TYPE_DICTIONARY:
		return "存档内容无法识别。"
	if typeof(data.get("buildings")) != TYPE_ARRAY:
		return "存档缺少建筑数据。"
	var version := int(data.get("version", -1))
	data = data.duplicate(true)
	if version == SAVE_FORMAT_VERSION_V1:
		# v1 → v4：补种预置大本营与旧默认地形；旧档若占用预置格，该格建筑让位。
		var entries: Array = data["buildings"]
		entries = entries.filter(func(entry: Variant) -> bool:
			return not (int(entry.get("x", -99)) == LEGACY_HQ_CELL.x
				and int(entry.get("y", -99)) == LEGACY_HQ_CELL.y))
		entries.append({ "x": LEGACY_HQ_CELL.x, "y": LEGACY_HQ_CELL.y, "kind": "hq", "progress": 0.0 })
		data["buildings"] = entries
		data["terrain"] = _legacy_terrain_data()
		data["map_size"] = [LEGACY_MAP_SIZE.x, LEGACY_MAP_SIZE.y]
		data["version"] = SAVE_FORMAT_VERSION
	elif version == SAVE_FORMAT_VERSION_V2:
		# v2 → v4：补旧默认地形与尺寸（旧档没有地形/尺寸概念）。
		data["terrain"] = _legacy_terrain_data()
		data["map_size"] = [LEGACY_MAP_SIZE.x, LEGACY_MAP_SIZE.y]
		data["version"] = SAVE_FORMAT_VERSION
	elif version == SAVE_FORMAT_VERSION_V3:
		# v3 → v4：v3 阶段地图固定 16×12，地形已随档。
		data["map_size"] = [LEGACY_MAP_SIZE.x, LEGACY_MAP_SIZE.y]
		data["version"] = SAVE_FORMAT_VERSION
	elif version != SAVE_FORMAT_VERSION:
		return "存档版本不兼容。"
	var size_result := _parse_map_size(data.get("map_size"))
	if size_result.has("error"):
		return size_result["error"]
	var size: Vector2i = size_result["data"]
	var terrain_result := _parse_terrain_data(data.get("terrain"), size)
	if terrain_result.has("error"):
		return terrain_result["error"]
	var parsed_terrain: Dictionary = terrain_result["data"]
	var loaded_buildings: Dictionary = {}
	var loaded_progress: Dictionary = {}
	var unique_seen: Dictionary = {}
	var hq_count: int = 0
	for entry: Variant in data["buildings"]:
		if typeof(entry) != TYPE_DICTIONARY:
			return "存档中的建筑数据损坏。"
		var cell := Vector2i(int(entry.get("x", -99)), int(entry.get("y", -99)))
		var kind := StringName(str(entry.get("kind", "")))
		var progress := float(entry.get("progress", -1.0))
		var def := building_def(kind)
		if not _in_bounds(cell, size) or not _cell_buildable(cell, parsed_terrain, size) or def == null \
				or loaded_buildings.has(cell) \
				or progress < 0.0 or progress >= PROGRESS_UNIT:
			return "存档中的建筑数据损坏。"
		if def.unique:
			if unique_seen.has(kind):
				return "存档中的建筑数据损坏。"
			if kind == &"hq":
				hq_count += 1
		unique_seen[kind] = true
		loaded_buildings[cell] = kind
		loaded_progress[cell] = progress
	if hq_count < 1:
		return "存档缺少大本营数据。"
	var loaded_wood := int(data.get("wood", -1))
	var loaded_grain := int(data.get("grain", -1))
	if loaded_wood < 0 or loaded_grain < 0:
		return "存档中的资源数据损坏。"
	var loaded_worker := Vector2i(int(data.get("worker_x", -99)), int(data.get("worker_y", -99)))
	if loaded_worker != INVALID_CELL and not loaded_buildings.has(loaded_worker):
		return "存档中的分工数据损坏。"
	var loaded_name := "无名城镇"
	if data.has("map_name"):
		if typeof(data["map_name"]) != TYPE_STRING or str(data["map_name"]).is_empty():
			return "存档中的地图名称损坏。"
		loaded_name = str(data["map_name"])
	wood = loaded_wood
	grain = loaded_grain
	buildings = loaded_buildings
	farm_progress = loaded_progress
	worker_cell = loaded_worker
	terrain = parsed_terrain
	map_size = size
	map_name = loaded_name
	hq_cell = _find_hq_cell(loaded_buildings)
	return ""


static func _find_hq_cell(loaded_buildings: Dictionary) -> Vector2i:
	for cell: Vector2i in loaded_buildings:
		if loaded_buildings[cell] == &"hq":
			return cell
	return LEGACY_HQ_CELL


static func _in_bounds(cell: Vector2i, size: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < size.x and cell.y >= 0 and cell.y < size.y


func is_inside(cell: Vector2i) -> bool:
	return _in_bounds(cell, map_size)


func terrain_kind(cell: Vector2i) -> StringName:
	return terrain.get(cell, TERRAIN_PLAIN)


func is_water(cell: Vector2i) -> bool:
	return terrain_kind(cell) == TERRAIN_WATER


func is_highland(cell: Vector2i) -> bool:
	return terrain_kind(cell) == TERRAIN_HIGHLAND


func is_resource(cell: Vector2i) -> bool:
	return RESOURCE_TERRAINS.has(terrain_kind(cell))


func terrain_height(cell: Vector2i) -> float:
	# 唯一高度事实来源：3D 渲染抬升与建筑基准都从这里取值。
	return HIGHLAND_HEIGHT if is_highland(cell) else 0.0


## 地形是否允许建造（不含占用判断）。terrain_map/size 作为参数传入，
## 存档校验可以在整体替换之前用存档自己的地形数据做同样判定。
static func _cell_buildable(cell: Vector2i, terrain_map: Dictionary, size: Vector2i) -> bool:
	if not _in_bounds(cell, size):
		return false
	var kind: StringName = terrain_map.get(cell, TERRAIN_PLAIN)
	return kind != TERRAIN_WATER and not RESOURCE_TERRAINS.has(kind)


func can_build_on(cell: Vector2i) -> bool:
	# 当前地图上该格是否可建：范围内、非水面、非资源区块且无建筑。
	return _cell_buildable(cell, terrain, map_size) and not buildings.has(cell)


func try_build(cell: Vector2i, def_id: StringName) -> String:
	# 验证全部通过后才扣资源；失败只返回原因，不改任何状态。
	var def := building_def(def_id)
	if def == null:
		return "未知建筑类型。"
	if def.unique and buildings.values().has(def_id):
		return "%s全图只能有一座。" % def.display_name
	if not is_inside(cell):
		return "请在地图范围内建造。"
	if is_water(cell):
		return "水面不能建造%s。" % def.display_name
	if is_resource(cell):
		return "资源区块暂时不能建造%s。" % def.display_name
	if buildings.has(cell):
		return "这一格已经有建筑了。"
	if wood < def.wood_cost:
		return "木材不足，点击重置可以重新练习。"

	buildings[cell] = def_id
	wood -= def.wood_cost
	return "已在 (%d, %d) 建造%s。" % [cell.x, cell.y, def.display_name]


func reset() -> void:
	wood = STARTING_WOOD
	grain = 0
	worker_cell = INVALID_CELL
	_reset_preset()


func _reset_preset() -> void:
	# 大本营与地形都来自默认布局图（D15/D18/D26）：重置恢复内置测试城镇。
	var error := load_default_layout()
	if error != "":
		# 内置资源损坏属于开发期错误：保留现状并显著报告。
		push_error("默认地图布局损坏：%s" % error)
