class_name BuildingDef
extends Resource
## 建筑定义配表条目：只描述规则数值，不持有任何运行状态。

@export var id: StringName
@export var display_name: String
@export var wood_cost: int
@export var produces: StringName
@export var base_rate: float
@export var worked_rate: float
@export var worker_assignable: bool
@export var unique: bool
## 占地格数（宽, 高）：建筑从锚点格向 +X/+Y 扩展；锚点是玩家点击/预置的格子。
@export var footprint: Vector2i = Vector2i.ONE
## 住房容量：提供的人口上限。0 表示不提供住房。
@export var capacity: int = 0
## 岗位数：居民可自动填充的工作位。0 表示没有岗位。
@export var jobs: int = 0
## 每个已填岗位的产出加成（/秒）。产出 = base_rate + 已填岗位数 x job_rate。
@export var job_rate: float = 0.0
## 最高等级（E04）：1 表示不可升级。
@export var max_level: int = 1
## 各等级岗位数（下标 0 = Lv1）。为空时所有等级都用 jobs。
@export var jobs_per_level: Array[int] = []
## 各等级住房容量（下标 0 = Lv1）。为空时所有等级都用 capacity。
@export var capacity_per_level: Array[int] = []
## 新建工期（秒，游戏时间）。0 表示瞬成。
@export var build_seconds: float = 0.0
## 升级工期（秒，游戏时间）。
@export var upgrade_seconds: float = 0.0
## 每次升级的木材费用（临时统一值）。
@export var upgrade_wood_cost: int = 0


func jobs_at(level: int) -> int:
	if jobs_per_level.size() >= level and level >= 1:
		return jobs_per_level[level - 1]
	return jobs


func capacity_at(level: int) -> int:
	if capacity_per_level.size() >= level and level >= 1:
		return capacity_per_level[level - 1]
	return capacity
