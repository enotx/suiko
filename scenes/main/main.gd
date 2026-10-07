extends Node
## Main 拥有唯一的城镇状态；两个视图只读取状态和换算点击坐标。
## 必须与 main.tscn 的 Main 根节点类型匹配，不要换回旧版 Node2D 脚本。

const TownStateScript = preload("res://core/town_state.gd")
const SAVE_PATH := "user://town_save.json"
var town: TownState = TownStateScript.new()
var showing_3d: bool = true
var selected_cell: Vector2i = TownState.INVALID_CELL
# 暂停是交互状态：暂停时 Main 不再向规则层传入经过时间（D14 无离线补算）。
var paused: bool = false
var _last_shown_grain: int = -1

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
@onready var assign_button: Button = $UI/AssignButton
@onready var withdraw_button: Button = $UI/WithdrawButton
@onready var pause_button: Button = $UI/PauseButton
@onready var save_button: Button = $UI/SaveButton
@onready var load_button: Button = $UI/LoadButton


func _ready() -> void:
	map_2d.setup(town)
	map_3d.setup(town)
	world_image.texture = world_viewport.get_texture()
	map_area.gui_input.connect(_on_map_input)
	reset_button.pressed.connect(_reset_town)
	view_button.pressed.connect(_toggle_view)
	deselect_button.pressed.connect(_deselect_cell)
	assign_button.pressed.connect(_on_assign_pressed)
	withdraw_button.pressed.connect(_on_withdraw_pressed)
	pause_button.pressed.connect(_toggle_pause)
	save_button.pressed.connect(_save_town)
	load_button.pressed.connect(_load_town)
	$UI/Instructions.text = "蓝=水泊不可建；绿=土地可建；黄=农田可选中。\n农田自动产粮：无人 %0.0f/秒，有人 %0.0f/秒；可暂停。" % [
		TownState.GRAIN_RATE_IDLE, TownState.GRAIN_RATE_WORKED
	]
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
	_refresh_selection_panel()
	_update_action_buttons()


func _refresh_selection_panel() -> void:
	if town.buildings.has(selected_cell):
		var worker_text: String = TownState.WORKER_NAME if town.worker_is_at(selected_cell) else "无"
		selection_label.text = "选中：%s\n位置：(%d, %d)\n工作者：%s\n产出进度：%d%%" % [
			town.building_name(selected_cell), selected_cell.x, selected_cell.y,
			worker_text, int(town.farm_progress_ratio(selected_cell) * 100.0)
		]
	else:
		selection_label.text = "未选中建筑。\n阮小二：%s" % _worker_summary()
	_update_action_buttons()


func _worker_summary() -> String:
	if town.worker_cell == TownState.INVALID_CELL:
		return "空闲"
	return "正在农田 (%d, %d) 工作" % [town.worker_cell.x, town.worker_cell.y]


func _update_action_buttons() -> void:
	var farm_selected: bool = town.buildings.has(selected_cell)
	assign_button.disabled = not farm_selected or town.worker_is_at(selected_cell)
	withdraw_button.disabled = town.worker_cell == TownState.INVALID_CELL


func _on_assign_pressed() -> void:
	var message: String = town.assign_worker(selected_cell)
	_select_cell(selected_cell)
	_refresh_ui(message)


func _on_withdraw_pressed() -> void:
	var message: String = town.withdraw_worker()
	_select_cell(selected_cell)
	_refresh_ui(message)


func _toggle_pause() -> void:
	paused = not paused
	pause_button.text = "继续经营" if paused else "暂停经营"
	_refresh_ui("经营已暂停；生产停止，进度保留。" if paused else "继续经营；生产恢复。")


func _save_town() -> void:
	# 文件 IO 留在 Main；数据格式与校验在规则层（to_save_data / apply_save_data）。
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		_refresh_ui("保存失败（错误码 %d）。" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(town.to_save_data()))
	file.close()
	_refresh_ui("已保存城镇；之后可读取存档恢复到这一刻。")


func _load_town() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_refresh_ui("还没有存档；先点击保存城镇。")
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		_refresh_ui("存档无法打开（错误码 %d）。" % FileAccess.get_open_error())
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed == null:
		_refresh_ui("存档文件已损坏（不是有效 JSON）；当前经营未受影响。")
		return
	var result: String = town.apply_save_data(parsed)
	if result != "":
		_refresh_ui("%s 当前经营未受影响。" % result)
		return
	# 旧选中格可能不再有效：读取后清除选择并重建显示与按钮状态。
	_select_cell(TownState.INVALID_CELL)
	_refresh_ui("已读取存档；建筑、分工和生产进度已恢复。")


func _process(delta: float) -> void:
	# Main 是唯一模拟驱动者：视图切换、重绘都不推进时间；暂停时不传入经过时间。
	if paused:
		return
	town.advance_time(delta)
	if town.grain != _last_shown_grain:
		_last_shown_grain = town.grain
		_update_resources()
		_refresh_selection_panel()


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


func _update_resources() -> void:
	resources_label.text = "木材：%d    粮食：%d    农田：%d    建造花费：%d 木材" % [
		town.wood, town.grain, town.buildings.size(), TownState.BUILD_COST
	]


func _refresh_ui(message: String) -> void:
	_last_shown_grain = town.grain
	_update_resources()
	status_label.text = message
