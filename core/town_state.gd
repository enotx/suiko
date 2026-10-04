class_name TownState
extends RefCounted
## 城镇的规则和状态：只使用格子坐标，不依赖场景、鼠标或画面。

const WIDTH: int = 16
const HEIGHT: int = 12
const BUILD_COST: int = 10
const STARTING_WOOD: int = 100
const INVALID_CELL: Vector2i = Vector2i(-1, -1)
const BUILDING_NAMES: Dictionary = { "farm": "农田" }

var wood: int = STARTING_WOOD
var buildings: Dictionary = {}


func building_name(cell: Vector2i) -> String:
    return BUILDING_NAMES.get(buildings.get(cell, ""), "未知建筑")


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
    buildings.clear()
