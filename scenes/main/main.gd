extends Node
## Main 拥有唯一的城镇状态；两个视图只读取状态和换算点击坐标。
## 必须与 main.tscn 的 Main 根节点类型匹配，不要换回旧版 Node2D 脚本。

const TownStateScript = preload("res://core/town_state.gd")
var town: TownState = TownStateScript.new()
var showing_3d: bool = true

@onready var map_area: Control = $MapArea
@onready var map_2d = $MapArea/Map2D
@onready var map_3d = $MapArea/WorldViewport/Town3D
@onready var world_viewport: SubViewport = $MapArea/WorldViewport
@onready var world_image: TextureRect = $MapArea/WorldImage
@onready var resources_label: Label = $UI/Resources
@onready var status_label: Label = $UI/Status
@onready var view_label: Label = $UI/ViewLabel
@onready var reset_button: Button = $UI/ResetButton
@onready var view_button: Button = $UI/ViewButton


func _ready() -> void:
	map_2d.setup(town)
	map_3d.setup(town)
	world_image.texture = world_viewport.get_texture()
	map_area.gui_input.connect(_on_map_input)
	reset_button.pressed.connect(_reset_town)
	view_button.pressed.connect(_toggle_view)
	$UI/Instructions.text = "蓝色：水泊，不能建造\n绿色：土地，可建造农田\n黄色：已建造的农田\n\n点击土地，花费 %d 木材。\n切换视图不会重置建筑或资源。\n\n当前还没有生产、战斗和存档。" % TownState.BUILD_COST
	_apply_view()
	_refresh_ui("先建一块农田，再切到 2D 查看同一座城镇。")


func _on_map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var cell: Vector2i
			if showing_3d:
				cell = map_3d.cell_at_position(event.position)
			else:
				cell = map_2d.cell_at_position(event.position)
			var message := town.try_build(cell)
			map_2d.refresh()
			map_3d.refresh()
			_refresh_ui(message)
			map_area.accept_event()


func _toggle_view() -> void:
	showing_3d = not showing_3d
	_apply_view()
	_refresh_ui("已切换视图；农田和木材保持不变。")


func _apply_view() -> void:
	map_2d.visible = not showing_3d
	world_image.visible = showing_3d
	world_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if showing_3d else SubViewport.UPDATE_DISABLED
	)
	view_label.text = "当前视图：3D · 立体城镇" if showing_3d else "当前视图：2D · 格子地图"
	view_button.text = "切换到 2D" if showing_3d else "切换到 3D"


func _reset_town() -> void:
	town.reset()
	map_2d.refresh()
	map_3d.refresh()
	_refresh_ui("已重置城镇；两个视图同步恢复。")


func _refresh_ui(message: String) -> void:
	resources_label.text = "木材：%d    农田：%d    建造花费：%d 木材" % [
		town.wood, town.buildings.size(), TownState.BUILD_COST
	]
	status_label.text = message
