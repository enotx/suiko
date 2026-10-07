class_name TownState
extends RefCounted
## 城镇的规则和状态：只使用格子坐标，不依赖场景、鼠标或画面。
## 建筑种类来自 defs/*.tres 配表（D17），本类只管理运行实例。

const WIDTH: int = 16
const HEIGHT: int = 12
const STARTING_WOOD: int = 100
const INVALID_CELL: Vector2i = Vector2i(-1, -1)
const WORKER_NAME: String = "阮小二"
const PROGRESS_UNIT: float = 1.0
const SAVE_FORMAT_VERSION: int = 2
const SAVE_FORMAT_VERSION_V1: int = 1
const HQ_CELL: Vector2i = Vector2i(8, 5)

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
        "wood": wood,
        "grain": grain,
        "worker_x": worker_cell.x if worker_cell != INVALID_CELL else -1,
        "worker_y": worker_cell.y if worker_cell != INVALID_CELL else -1,
        "buildings": buildings_data,
    }


func apply_save_data(data: Variant) -> String:
    # 全部校验通过后才整体替换状态；任何失败返回中文原因，且不改动当前经营。
    if typeof(data) != TYPE_DICTIONARY:
        return "存档内容无法识别。"
    var version := int(data.get("version", -1))
    if version == SAVE_FORMAT_VERSION_V1:
        # v1 → v2 迁移：补种预置大本营；旧档若占用预置格，该格建筑在迁移中让位。
        data = data.duplicate(true)
        var entries: Array = data["buildings"]
        entries = entries.filter(func(entry: Variant) -> bool:
            return not (int(entry.get("x", -99)) == HQ_CELL.x and int(entry.get("y", -99)) == HQ_CELL.y))
        entries.append({ "x": HQ_CELL.x, "y": HQ_CELL.y, "kind": "hq", "progress": 0.0 })
        data["buildings"] = entries
        data["version"] = SAVE_FORMAT_VERSION
    elif version != SAVE_FORMAT_VERSION:
        return "存档版本不兼容。"
    if typeof(data.get("buildings")) != TYPE_ARRAY:
        return "存档缺少建筑数据。"
    var loaded_buildings: Dictionary = {}
    var loaded_progress: Dictionary = {}
    var unique_seen: Dictionary = {}
    for entry: Variant in data["buildings"]:
        if typeof(entry) != TYPE_DICTIONARY:
            return "存档中的建筑数据损坏。"
        var cell := Vector2i(int(entry.get("x", -99)), int(entry.get("y", -99)))
        var kind := StringName(str(entry.get("kind", "")))
        var progress := float(entry.get("progress", -1.0))
        var def := building_def(kind)
        if not is_inside(cell) or is_water(cell) or def == null \
                or loaded_buildings.has(cell) \
                or progress < 0.0 or progress >= PROGRESS_UNIT:
            return "存档中的建筑数据损坏。"
        if def.unique and unique_seen.has(kind):
            return "存档中的建筑数据损坏。"
        unique_seen[kind] = true
        loaded_buildings[cell] = kind
        loaded_progress[cell] = progress
    var loaded_wood := int(data.get("wood", -1))
    var loaded_grain := int(data.get("grain", -1))
    if loaded_wood < 0 or loaded_grain < 0:
        return "存档中的资源数据损坏。"
    var loaded_worker := Vector2i(int(data.get("worker_x", -99)), int(data.get("worker_y", -99)))
    if loaded_worker != INVALID_CELL and not loaded_buildings.has(loaded_worker):
        return "存档中的分工数据损坏。"
    wood = loaded_wood
    grain = loaded_grain
    buildings = loaded_buildings
    farm_progress = loaded_progress
    worker_cell = loaded_worker
    return ""


func is_inside(cell: Vector2i) -> bool:
    return cell.x >= 0 and cell.x < WIDTH and cell.y >= 0 and cell.y < HEIGHT


func is_water(cell: Vector2i) -> bool:
    return cell.x < 3


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
    # 大本营是预置核心（D15），不属于任何存档/重置后消失的内容。
    buildings = { HQ_CELL: &"hq" }
    farm_progress = {}
