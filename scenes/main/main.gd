extends Node
## Main 拥有唯一的城镇状态；两个视图只读取状态和换算点击坐标。
## 必须与 main.tscn 的 Main 根节点类型匹配，不要换回旧版 Node2D 脚本。

const TownStateScript = preload("res://core/town_state.gd")
var town: TownState = TownStateScript.new()
var showing_3d: bool = true
var selected_cell: Vector2i = TownState.INVALID_CELL

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
@onready var selection_label: Label = $UI/SelectionPanel
@onready var deselect_button: Button = $UI/DeselectButton


func _ready() -> void:
	map_2d.setup(town)
	map_3d.setup(town)
	world_image.texture = world_viewport.get_texture()
	map_area.gui_input.connect(_on_map_input)
	reset_button.pressed.connect(_reset_town)
	view_button.pressed.connect(_toggle_view)
	deselect_button.pressed.connect(_deselect_cell)
	$UI/Instructions.text = "蓝色：水泊，不能建造\n绿色：土地，可建造农田\n黄色：农田，点击选中查看\n\n点击空地建造，花费 %d 木材。\n选中在切换视图后保持。" % TownState.BUILD_COST
	_apply_view()
	_select_cell(TownState.INVALID_CELL)
	_refresh_ui("先建一块农田，再切到 2D 查看同一座城镇。")


func _on_map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var cell: Vector2i
			if showing_3d:
				cell = map_3d.cell_at_position(event.position)
			else:
				cell = map_2d.cell_at_position(event.position)
			var message: String
			if town.buildings.has(cell):
				message = "已选中 %s (%d, %d)。" % [town.building_name(cell), cell.x, cell.y]
				_select_cell(cell)
			else:
				message = town.try_build(cell)
				if town.buildings.has(cell):
					# 临时交互约定：建造成功后自动选中新农田，方便立即查看信息。
					message += " 已自动选中。"
					_select_cell(cell)
			map_2d.refresh()
			map_3d.refresh()
			_refresh_ui(message)
			map_area.accept_event()


func _select_cell(cell: Vector2i) -> void:
	# 选中身份是格子坐标，不引用任何视图里的模型节点。
	selected_cell = cell
	map_2d.selected_cell = cell
	map_2d.refresh()
	map_3d.selected_cell = cell
	map_3d.refresh()
	if town.buildings.has(cell):
		selection_label.text = "选中：%s\n位置：(%d, %d)\n状态：已建成，暂无工作者" % [
			town.building_name(cell), cell.x, cell.y
		]
	else:
		selection_label.text = "未选中建筑。\n点击已有农田查看信息。"


func _deselect_cell() -> void:
	_select_cell(TownState.INVALID_CELL)
	_refresh_ui("已取消选择；建筑和木材保持不变。")


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
	# 重置必须清除选择，面板不能再引用已被清空的建筑格。
	_select_cell(TownState.INVALID_CELL)
	_refresh_ui("已重置城镇；两个视图同步恢复。")


func _refresh_ui(message: String) -> void:
	resources_label.text = "木材：%d    农田：%d    建造花费：%d 木材" % [
		town.wood, town.buildings.size(), TownState.BUILD_COST
	]
	status_label.text = message
