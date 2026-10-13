class_name TownState
extends RefCounted
## 城镇的规则和状态：只使用格子坐标，不依赖场景、鼠标或画面。
## 建筑种类来自 defs/*.tres 配表（D17），本类只管理运行实例。
## 地图布局来自调色板图片（D26）：1 像素 = 1 格，颜色 = 地形，见 MAP_PALETTE。

const STARTING_WOOD: int = 100
const INVALID_CELL: Vector2i = Vector2i(-1, -1)
const WORKER_NAME: String = "阮小二"
const PROGRESS_UNIT: float = 1.0
const SAVE_FORMAT_VERSION: int = 5
const SAVE_FORMAT_VERSION_V4: int = 4
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
	&"house": preload("res://defs/house.tres"),
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
# 人口（E02）：住在民居里的居民，尚未参与工作（岗位自动填岗属 E03）。
# 迁入与耗粮速率是临时数值，用户验收可调；粮尽即停止迁入（软失败，不饿死人）。
var population: int = 0
var move_in_progress: float = 0.0
var food_buffer: float = 0.0

# 人口速率占位值（E02）：每 5 秒迁入 1 人，每人每秒耗 0.1 粮。
const MOVE_IN_SECONDS: float = 5.0
const FOOD_PER_PERSON: float = 0.1

# 开局帮扶（用户 2026-10-12 反馈）：前 N 名居民无条件迁入，只需有空房、不要求余粮。
const FOUNDING_POPULATION: int = 10

# 岗位（E03.a）：建筑种类 → 岗位类别；类别优先序当前固定（临时规则，界面化留 E03.b）。
const JOB_CATEGORIES: Dictionary = { &"farm": &"farming", &"lumberyard": &"lumber" }
const JOB_CATEGORY_ORDER: Array[StringName] = [&"farming", &"lumber"]


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
		if def.footprint.x < 1 or def.footprint.y < 1:
			problems.append("建筑 %s 的占地必须至少 1×1" % id)
		if def.capacity < 0:
			problems.append("建筑 %s 的住房容量不能为负" % id)
		if def.jobs < 0 or def.job_rate < 0.0:
			problems.append("建筑 %s 的岗位数或岗位产出不能为负" % id)
	return problems


## 建筑从锚点 origin 向 +X/+Y 占用 footprint 的全部格子。
static func covered_cells(origin: Vector2i, footprint: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dy: int in range(footprint.y):
		for dx: int in range(footprint.x):
			cells.append(Vector2i(origin.x + dx, origin.y + dy))
	return cells


static func _def_covered_cells(origin: Vector2i, kind: StringName) -> Array[Vector2i]:
	var def := building_def(kind)
	return covered_cells(origin, def.footprint if def != null else Vector2i.ONE)


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
	var hq_def := building_def(&"hq")
	var hq_footprint: Vector2i = hq_def.footprint if hq_def != null else Vector2i.ONE
	if hq_cells[0].x + hq_footprint.x > width or hq_cells[0].y + hq_footprint.y > height:
		return { "error": "大本营标记 (%d, %d) 的占地 %d×%d 超出布局图边缘。" % [
			hq_cells[0].x, hq_cells[0].y, hq_footprint.x, hq_footprint.y,
		] }
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
	var def := building_def_at(cell)
	return def.display_name if def != null else "未知建筑"


## 覆盖此格的建筑锚点；没有则 INVALID_CELL。建筑数量少，线性查找足够。
func building_origin_at(cell: Vector2i) -> Vector2i:
	for origin: Vector2i in buildings:
		if cell in _def_covered_cells(origin, buildings[origin]):
			return origin
	return INVALID_CELL


func building_def_at(cell: Vector2i) -> BuildingDef:
	var origin := building_origin_at(cell)
	if origin == INVALID_CELL:
		return null
	return building_def(buildings.get(origin, &""))


func farm_progress_ratio(cell: Vector2i) -> float:
	return clampf(farm_progress.get(cell, 0.0) / PROGRESS_UNIT, 0.0, 1.0)


func advance_time(delta: float) -> void:
	# 唯一模拟入口。以迁入事件为切片边界：段内岗位 staffing 不变，
	# 生产与耗粮按段积分，长时间步与逐帧推进结果一致（ECONOMY 确定性要求）。
	var remaining: float = delta
	while remaining > 0.0000001:
		var segment: float = minf(remaining, _time_to_next_arrival())
		_produce(segment)
		_arrive(segment)
		remaining -= segment


func _can_move_in() -> bool:
	# 迁入条件：有空房，且（前 N 名开局居民无条件；之后需要有余粮）。
	return population < population_cap() \
		and (population < FOUNDING_POPULATION or grain > 0)


func _time_to_next_arrival() -> float:
	if _can_move_in():
		return (1.0 - move_in_progress) * MOVE_IN_SECONDS
	return INF


func _produce(segment: float) -> void:
	var assignment := job_assignment()
	for cell: Vector2i in buildings:
		var def := building_def(buildings[cell])
		if def == null or def.produces == &"":
			continue
		var rate: float = def.base_rate + assignment.get(cell, 0) * def.job_rate
		var progress: float = farm_progress.get(cell, 0.0) + rate * segment
		while progress >= PROGRESS_UNIT:
			progress -= PROGRESS_UNIT
			if def.produces == &"grain":
				grain += 1
			elif def.produces == &"wood":
				wood += 1
		farm_progress[cell] = progress
	# 人口耗粮：粮尽软失败——把剩余粮食吃光为止，不饿人（E02 临时规则）。
	if population > 0 and grain > 0:
		var consumption: float = population * FOOD_PER_PERSON * segment
		if consumption <= float(grain):
			food_buffer += consumption
			var eaten := int(food_buffer)
			if eaten > 0:
				food_buffer -= eaten
				grain -= eaten
		else:
			grain = 0


func _arrive(segment: float) -> void:
	if _can_move_in():
		move_in_progress += segment / MOVE_IN_SECONDS
		if move_in_progress >= 1.0 - 0.0000001:
			move_in_progress = 0.0
			population += 1
	else:
		move_in_progress = 0.0


## 岗位分配（E03.a，派生值不落存档）：阮小二占一个岗位，居民按类别优先序与
## 格子顺序自动填充剩余岗位。类别优先序当前固定，界面化留 E03.b。
func job_assignment() -> Dictionary:
	var entries: Array = []
	for origin: Vector2i in buildings:
		var kind: StringName = buildings[origin]
		if JOB_CATEGORIES.has(kind):
			var rank: int = JOB_CATEGORY_ORDER.find(JOB_CATEGORIES[kind])
			entries.append([rank if rank >= 0 else 999, origin.y, origin.x, origin])
	entries.sort()
	var assignment: Dictionary = {}
	var pool := population
	for entry: Array in entries:
		var def := building_def(buildings[entry[3]])
		var jobs: int = def.jobs if def != null else 0
		var filled := 0
		if worker_cell == entry[3] and jobs > 0:
			filled += 1
		var take: int = mini(pool, jobs - filled)
		filled += take
		pool -= take
		assignment[entry[3]] = filled
	return assignment


func staffed_population() -> int:
	# 就业居民数（阮小二不计入，他不是人口）。
	var total := 0
	var assignment := job_assignment()
	for origin: Vector2i in assignment:
		total += assignment[origin]
	return total


func building_jobs_filled(origin: Vector2i) -> int:
	# 该建筑已占岗位数（居民 + 阮小二）。
	var def := building_def(buildings.get(origin, &""))
	if def == null or def.jobs <= 0:
		return 0
	var filled: int = job_assignment().get(origin, 0)
	if worker_is_at(origin):
		filled += 1
	return mini(filled, def.jobs)


func population_cap() -> int:
	# 人口上限 = 全部建筑住房容量之和（当前只有民居提供）。
	var cap: int = 0
	for kind: StringName in buildings.values():
		var def := building_def(kind)
		if def != null:
			cap += def.capacity
	return cap


func _advance_population(delta: float) -> void:
	# 按迁入事件切片推进：与逐帧推进在相同总时长下得到相同结果（ECONOMY 一致性要求）。
	# 粮尽的软失败（E02 临时规则）：停止迁入、人口不减少，把剩余粮食吃光为止。
	var remaining: float = delta
	while remaining > 0.0:
		var cap := population_cap()
		var has_grain: bool = grain > 0
		var can_move_in: bool = population < cap and has_grain
		var segment: float = remaining
		if can_move_in:
			segment = minf(segment, (1.0 - move_in_progress) * MOVE_IN_SECONDS)
		if population > 0 and has_grain:
			var consumption: float = population * FOOD_PER_PERSON * segment
			if consumption <= float(grain):
				food_buffer += consumption
				var eaten := int(food_buffer)
				if eaten > 0:
					food_buffer -= eaten
					grain -= eaten
			else:
				# 剩余粮食撑不完这一段：吃光后人口活动停止。
				grain = 0
				segment = remaining
				remaining = 0.0
		if can_move_in and remaining > 0.0:
			move_in_progress += segment / MOVE_IN_SECONDS
			if move_in_progress >= 1.0 - 0.0000001:
				move_in_progress = 0.0
				population += 1
		elif not can_move_in:
			move_in_progress = 0.0
		remaining -= segment


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
		"population": population,
		"move_in_progress": move_in_progress,
		"food_buffer": food_buffer,
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
		version = SAVE_FORMAT_VERSION_V4
		data["version"] = SAVE_FORMAT_VERSION_V4
	elif version == SAVE_FORMAT_VERSION_V2:
		# v2 → v4：补旧默认地形与尺寸（旧档没有地形/尺寸概念）。
		data["terrain"] = _legacy_terrain_data()
		data["map_size"] = [LEGACY_MAP_SIZE.x, LEGACY_MAP_SIZE.y]
		version = SAVE_FORMAT_VERSION_V4
		data["version"] = SAVE_FORMAT_VERSION_V4
	elif version == SAVE_FORMAT_VERSION_V3:
		# v3 → v4：v3 阶段地图固定 16×12，地形已随档。
		data["map_size"] = [LEGACY_MAP_SIZE.x, LEGACY_MAP_SIZE.y]
		version = SAVE_FORMAT_VERSION_V4
		data["version"] = SAVE_FORMAT_VERSION_V4
	elif version != SAVE_FORMAT_VERSION_V4 and version != SAVE_FORMAT_VERSION:
		return "存档版本不兼容。"
	if version == SAVE_FORMAT_VERSION_V4:
		# v4 → v5：补人口字段（旧档还没有人口概念，迁移后从零开始）。
		data["population"] = 0
		data["move_in_progress"] = 0.0
		data["food_buffer"] = 0.0
		data["version"] = SAVE_FORMAT_VERSION
	var size_result := _parse_map_size(data.get("map_size"))
	if size_result.has("error"):
		return size_result["error"]
	var size: Vector2i = size_result["data"]
	# 建筑占地可能随配表扩张（E01.b 大本营、E03 反馈后农田/伐木场/民居均 2×2）：
	# 旧档按旧占地记录，读档时按当前占地重算，与已保留建筑重叠的条目让位
	#（大本营优先保留，其余按存档顺序；幂等，任何版本档都安全）。
	var drop_result := _drop_overlapping_entries(data["buildings"], size)
	if drop_result != "":
		return drop_result
	var terrain_result := _parse_terrain_data(data.get("terrain"), size)
	if terrain_result.has("error"):
		return terrain_result["error"]
	var parsed_terrain: Dictionary = terrain_result["data"]
	var loaded_buildings: Dictionary = {}
	var loaded_progress: Dictionary = {}
	var occupied: Dictionary = {}
	var unique_seen: Dictionary = {}
	var hq_count: int = 0
	for entry: Variant in data["buildings"]:
		if typeof(entry) != TYPE_DICTIONARY:
			return "存档中的建筑数据损坏。"
		var cell := Vector2i(int(entry.get("x", -99)), int(entry.get("y", -99)))
		var kind := StringName(str(entry.get("kind", "")))
		var progress := float(entry.get("progress", -1.0))
		var def := building_def(kind)
		if def == null or not _in_bounds(cell, size) \
				or progress < 0.0 or progress >= PROGRESS_UNIT:
			return "存档中的建筑数据损坏。"
		if def.unique:
			if unique_seen.has(kind):
				return "存档中的建筑数据损坏。"
			if kind == &"hq":
				hq_count += 1
		unique_seen[kind] = true
		for covered: Vector2i in covered_cells(cell, def.footprint):
			if not _in_bounds(covered, size) or not _cell_buildable(covered, parsed_terrain, size) \
					or occupied.has(covered):
				return "存档中的建筑数据损坏。"
			occupied[covered] = cell
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
	var loaded_population := int(data.get("population", -1))
	var loaded_move_in := float(data.get("move_in_progress", -1.0))
	var loaded_food_buffer := float(data.get("food_buffer", -1.0))
	if loaded_population < 0 or loaded_population > loaded_buildings.size() * 1000 \
			or loaded_move_in < 0.0 or loaded_move_in >= 1.0 or loaded_food_buffer < 0.0:
		return "存档中的人口数据损坏。"
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
	population = loaded_population
	move_in_progress = loaded_move_in
	food_buffer = loaded_food_buffer
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


## 占地扩张让位：按当前 footprint 重算占地，与已保留建筑重叠（或越界）的
## 条目从 entries 原地移除。大本营必须保留且不得越界；返回中文错误或空串。
static func _drop_overlapping_entries(entries: Array, size: Vector2i) -> String:
	var hq_index := -1
	var hq_origin := Vector2i.ZERO
	for i: int in range(entries.size()):
		var entry: Variant = entries[i]
		if typeof(entry) != TYPE_DICTIONARY:
			return "存档中的建筑数据损坏。"
		if str(entry.get("kind", "")) == "hq":
			if hq_index >= 0:
				return "存档中的建筑数据损坏。"
			hq_index = i
			hq_origin = Vector2i(int(entry.get("x", -99)), int(entry.get("y", -99)))
	var occupied: Dictionary = {}
	if hq_index >= 0:
		var hq_def := building_def(&"hq")
		var hq_footprint: Vector2i = hq_def.footprint if hq_def != null else Vector2i.ONE
		var hq_covered := covered_cells(hq_origin, hq_footprint)
		for covered: Vector2i in hq_covered:
			if not _in_bounds(covered, size):
				return "存档中的大本营占地超出地图。"
			occupied[covered] = hq_origin
	var kept: Array = []
	for i: int in range(entries.size()):
		if i == hq_index:
			kept.append(entries[i])
			continue
		var entry: Dictionary = entries[i]
		var origin := Vector2i(int(entry.get("x", -99)), int(entry.get("y", -99)))
		var kind := StringName(str(entry.get("kind", "")))
		var overlaps := false
		for covered: Vector2i in _def_covered_cells(origin, kind):
			if not _in_bounds(covered, size) or occupied.has(covered):
				overlaps = true
				break
		if overlaps:
			continue
		kept.append(entry)
		for covered: Vector2i in _def_covered_cells(origin, kind):
			occupied[covered] = origin
	entries.clear()
	entries.append_array(kept)
	return ""




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
	# 当前地图上该格是否可作建筑锚点：地形可建且没有被任何建筑的占地覆盖。
	return _cell_buildable(cell, terrain, map_size) and building_origin_at(cell) == INVALID_CELL


## 完整建造预检（不扣资源）：占地全部格子的地形、边界与占用都合法。
func can_build_at(cell: Vector2i, def_id: StringName) -> bool:
	var def := building_def(def_id)
	if def == null:
		return false
	if def.unique and buildings.values().has(def_id):
		return false
	for covered: Vector2i in covered_cells(cell, def.footprint):
		if not _cell_buildable(covered, terrain, map_size) \
				or building_origin_at(covered) != INVALID_CELL:
			return false
	return true


func try_build(cell: Vector2i, def_id: StringName) -> String:
	# 验证全部通过后才扣资源；失败只返回原因，不改任何状态。
	var def := building_def(def_id)
	if def == null:
		return "未知建筑类型。"
	if def.unique and buildings.values().has(def_id):
		return "%s全图只能有一座。" % def.display_name
	for covered: Vector2i in covered_cells(cell, def.footprint):
		if not is_inside(covered):
			return "请在地图范围内建造。"
		if is_water(covered):
			return "水面不能建造%s。" % def.display_name
		if is_resource(covered):
			return "资源区块暂时不能建造%s。" % def.display_name
		if building_origin_at(covered) != INVALID_CELL:
			return "该位置与已有建筑重叠。"
	if wood < def.wood_cost:
		return "木材不足，点击重置可以重新练习。"

	buildings[cell] = def_id
	wood -= def.wood_cost
	return "已在 (%d, %d) 建造%s（占地 %d×%d）。" % [
		cell.x, cell.y, def.display_name, def.footprint.x, def.footprint.y,
	]


func reset() -> void:
	wood = STARTING_WOOD
	grain = 0
	worker_cell = INVALID_CELL
	population = 0
	move_in_progress = 0.0
	food_buffer = 0.0
	_reset_preset()


func _reset_preset() -> void:
	# 大本营与地形都来自默认布局图（D15/D18/D26）：重置恢复内置测试城镇。
	var error := load_default_layout()
	if error != "":
		# 内置资源损坏属于开发期错误：保留现状并显著报告。
		push_error("默认地图布局损坏：%s" % error)
