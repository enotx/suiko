class_name TownState
extends RefCounted
## 城镇的规则和状态：只使用格子坐标，不依赖场景、鼠标或画面。

const WIDTH: int = 16
const HEIGHT: int = 12
const BUILD_COST: int = 10
const STARTING_WOOD: int = 100
const INVALID_CELL: Vector2i = Vector2i(-1, -1)
const BUILDING_NAMES: Dictionary = { "farm": "农田" }
const WORKER_NAME: String = "阮小二"
# 临时产出数值（D13）：无人田 +1 粮/秒，有人田 +2 粮/秒；进度累计满 1.0 产 1 粮。
const GRAIN_RATE_IDLE: float = 1.0
const GRAIN_RATE_WORKED: float = 2.0
const PROGRESS_PER_GRAIN: float = 1.0
const SAVE_FORMAT_VERSION: int = 1

var wood: int = STARTING_WOOD
var grain: int = 0
var buildings: Dictionary = {}
# 唯一人物的教学占位：worker_cell 为 INVALID_CELL 表示空闲。
# 分工只记录在人物一侧（此处），建筑不反向存储工人，天然保证一人只能占一个工位。
var worker_cell: Vector2i = INVALID_CELL
# 每块农田各自的生产进度（0..PROGRESS_PER_GRAIN），调岗保留在田上、不跟人走。
var farm_progress: Dictionary = {}


func building_name(cell: Vector2i) -> String:
    return BUILDING_NAMES.get(buildings.get(cell, ""), "未知建筑")


func farm_progress_ratio(cell: Vector2i) -> float:
    return clampf(farm_progress.get(cell, 0.0) / PROGRESS_PER_GRAIN, 0.0, 1.0)


func advance_time(delta: float) -> void:
    # 唯一模拟入口：接收游戏经过的秒数。长时间步通过 while 累计多个完整周期，不丢产量。
    for cell: Vector2i in buildings:
        var rate: float = GRAIN_RATE_WORKED if worker_cell == cell else GRAIN_RATE_IDLE
        var progress: float = farm_progress.get(cell, 0.0) + rate * delta
        while progress >= PROGRESS_PER_GRAIN:
            progress -= PROGRESS_PER_GRAIN
            grain += 1
        farm_progress[cell] = progress


func worker_is_at(cell: Vector2i) -> bool:
    return worker_cell == cell


func assign_worker(cell: Vector2i) -> String:
    # 只在目标确认有效后才改动 worker_cell；失败不影响现有工作（调岗原子性）。
    if not buildings.has(cell):
        return "那里没有农田，不能分配。"
    if worker_cell == cell:
        return "阮小二已经在这块农田工作了。"
    worker_cell = cell
    return "阮小二已到 (%d, %d) 农田工作。" % [cell.x, cell.y]


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
            "kind": buildings[cell],
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
    if int(data.get("version", -1)) != SAVE_FORMAT_VERSION:
        return "存档版本不兼容。"
    if typeof(data.get("buildings")) != TYPE_ARRAY:
        return "存档缺少建筑数据。"
    var loaded_buildings: Dictionary = {}
    var loaded_progress: Dictionary = {}
    for entry: Variant in data["buildings"]:
        if typeof(entry) != TYPE_DICTIONARY:
            return "存档中的建筑数据损坏。"
        var cell := Vector2i(int(entry.get("x", -99)), int(entry.get("y", -99)))
        var kind := str(entry.get("kind", ""))
        var progress := float(entry.get("progress", -1.0))
        if not is_inside(cell) or is_water(cell) or not BUILDING_NAMES.has(kind) \
                or loaded_buildings.has(cell) \
                or progress < 0.0 or progress >= PROGRESS_PER_GRAIN:
            return "存档中的建筑数据损坏。"
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


func try_build(cell: Vector2i) -> String:
    # 验证全部通过后才扣资源；失败只返回原因。
    if not is_inside(cell):
        return "请在地图范围内建造。"
    if is_water(cell):
        return "水面不能建造农田。"
    if buildings.has(cell):
        return "这一格已经有农田了。"
    if wood < BUILD_COST:
        return "木材不足，点击重置可以重新练习。"

    buildings[cell] = "farm"
    wood -= BUILD_COST
    return "已在 (%d, %d) 建造农田。" % [cell.x, cell.y]


func reset() -> void:
    wood = STARTING_WOOD
    grain = 0
    buildings.clear()
    farm_progress.clear()
    worker_cell = INVALID_CELL
