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
