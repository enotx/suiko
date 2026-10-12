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
var _last_shown_wood: int = -1
# 左键拖动平移 vs 点击选中：按下先记为“待定点击”，位移超过阈值才算拖拽；
# 松手时没超过阈值就当作一次普通点击。阈值放宽可减少触摸板的误拖拽。
const DRAG_THRESHOLD_PX: float = 8.0
var _left_press_pending: bool = false
var _left_drag_panning: bool = false
var _left_press_position: Vector2 = Vector2.ZERO

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
@onready var build_farm_button: Button = $UI/BuildFarmButton
@onready var build_lumberyard_button: Button = $UI/BuildLumberyardButton


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
	build_farm_button.pressed.connect(_on_build_pressed.bind(&"farm"))
	build_lumberyard_button.pressed.connect(_on_build_pressed.bind(&"lumberyard"))
	var farm_def: BuildingDef = TownState.building_def(&"farm")
	var lumber_def: BuildingDef = TownState.building_def(&"lumberyard")
	build_farm_button.text = "建%s（%d木）" % [farm_def.display_name, farm_def.wood_cost]
	build_lumberyard_button.text = "建%s（%d木）" % [lumber_def.display_name, lumber_def.wood_cost]
	$UI/Instructions.text = "蓝=水泊 灰绿=草地 黄绿=高地 深绿/灰/棕=林地/石料/铁砂（暂不可建）。\n3D：滚轮缩放，按住左键拖动平移（轻点即选中），右键同样平移；点空地选中后建造，伐木场产木、农田产粮。"
	_apply_view()
	_select_cell(TownState.INVALID_CELL)
	_refresh_ui("先选一块空地，建一座伐木场，木材就不再是死水。")


func _on_map_input(event: InputEvent) -> void:
	if showing_3d and _handle_camera_input(event):
		map_area.accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and not event.pressed and not _left_drag_panning:
		# 点击在左键松开时结算：按住并拖动过的释放不当作点击（见 _handle_camera_input）。
		var cell: Vector2i
		if showing_3d:
			cell = map_3d.cell_at_position(event.position)
		else:
			cell = map_2d.cell_at_position(event.position)
		var message: String
		var origin: Vector2i = town.building_origin_at(cell)
		if origin != TownState.INVALID_CELL:
			message = "已选中 %s (%d, %d)。" % [town.building_name(origin), origin.x, origin.y]
			_select_cell(origin)
		elif not town.is_inside(cell):
			message = "请在地图范围内操作。"
		elif town.is_water(cell):
			message = "水面不能建造。"
		elif town.is_resource(cell):
			message = "%s资源区块暂时不能建造，采集玩法接入后开放。" % _resource_name(cell)
		else:
			# D16：点空地只是选中，建造由右侧按钮决定建筑种类。
			message = "已选择空地 (%d, %d)；在右侧选择要建造的建筑。" % [cell.x, cell.y]
			_select_cell(cell)
		map_2d.refresh()
		map_3d.refresh()
		_refresh_ui(message)
		map_area.accept_event()


func _handle_camera_input(event: InputEvent) -> bool:
	# 3D 视图的相机控制：滚轮缩放；左键按住拖动平移（触摸板友好），右键/中键同样平移。
	# 左键按下先记为“待定点击”，移动超过阈值才转入平移；松手时若拖过就不当作点击。
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					map_3d.zoom_step(1.0)
					return true
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					map_3d.zoom_step(-1.0)
					return true
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_left_press_pending = true
					_left_drag_panning = false
					_left_press_position = event.position
					return true
				else:
					var was_dragging: bool = _left_drag_panning
					var was_pending: bool = _left_press_pending
					_left_press_pending = false
					_left_drag_panning = false
					if was_dragging:
						map_3d.end_pan()
						return true
					return not was_pending
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				if event.pressed:
					map_3d.begin_pan()
				else:
					map_3d.end_pan()
				return true
	elif event is InputEventMouseMotion:
		if _left_press_pending:
			if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
				# 左键已在地图外松开：放弃这次待定点击。
				_left_press_pending = false
				_left_drag_panning = false
				return false
			if not _left_drag_panning \
					and event.position.distance_to(_left_press_position) > DRAG_THRESHOLD_PX:
				_left_drag_panning = true
				map_3d.begin_pan()
			if _left_drag_panning:
				map_3d.pan_by(event.relative)
				return true
		return map_3d.is_panning()
	return false


func _resource_name(cell: Vector2i) -> String:
	match town.terrain_kind(cell):
		&"forest":
			return "林地"
		&"stone":
			return "石料"
		&"iron":
			return "铁砂"
	return ""


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
		var def: BuildingDef = TownState.building_def(town.buildings[selected_cell])
		var worker_text: String = TownState.WORKER_NAME if town.worker_is_at(selected_cell) else "无"
		var progress_text: String = "产出进度：%d%%" % int(town.farm_progress_ratio(selected_cell) * 100.0) \
			if def.produces != &"" else "不产出"
		selection_label.text = "选中：%s\n位置：(%d, %d)　占地：%d×%d\n工作者：%s\n%s" % [
			def.display_name, selected_cell.x, selected_cell.y,
			def.footprint.x, def.footprint.y, worker_text, progress_text
		]
	elif _is_buildable_cell(selected_cell):
		selection_label.text = "空地 (%d, %d)\n阮小二：%s\n在下方选择要建造的建筑；多格建筑从锚点向右下扩展。" % [
			selected_cell.x, selected_cell.y, _worker_summary()
		]
	else:
		selection_label.text = "未选中建筑。\n阮小二：%s" % _worker_summary()
	_update_action_buttons()


func _is_buildable_cell(cell: Vector2i) -> bool:
	return town.can_build_on(cell)


func _worker_summary() -> String:
	if town.worker_cell == TownState.INVALID_CELL:
		return "空闲"
	var def: BuildingDef = TownState.building_def(town.buildings.get(town.worker_cell, &""))
	var place: String = def.display_name if def != null else "外出"
	return "正在%s (%d, %d) 工作" % [place, town.worker_cell.x, town.worker_cell.y]


func _update_action_buttons() -> void:
	var def: BuildingDef = TownState.building_def(town.buildings.get(selected_cell, &""))
	var building_selected: bool = def != null
	var assignable: bool = building_selected and def.worker_assignable
	assign_button.visible = building_selected
	withdraw_button.visible = building_selected
	assign_button.disabled = not assignable or town.worker_is_at(selected_cell)
	withdraw_button.disabled = town.worker_cell == TownState.INVALID_CELL
	build_farm_button.visible = not building_selected
	build_lumberyard_button.visible = not building_selected
	build_farm_button.disabled = not town.can_build_at(selected_cell, &"farm") \
		or town.wood < TownState.building_def(&"farm").wood_cost
	build_lumberyard_button.disabled = not town.can_build_at(selected_cell, &"lumberyard") \
		or town.wood < TownState.building_def(&"lumberyard").wood_cost


func _on_assign_pressed() -> void:
	var message: String = town.assign_worker(selected_cell)
	_select_cell(selected_cell)
	_refresh_ui(message)


func _on_withdraw_pressed() -> void:
	var message: String = town.withdraw_worker()
	_select_cell(selected_cell)
	_refresh_ui(message)


func _on_build_pressed(def_id: StringName) -> void:
	var message: String = town.try_build(selected_cell, def_id)
	if town.buildings.get(selected_cell, &"") == def_id:
		# 临时交互约定：建造成功后自动选中新建筑，方便立即查看信息。
		message += " 已自动选中。"
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
	# 存档可能来自不同地图（如旧 16×12 存档）：重建地形显示，清除旧选择。
	map_3d.rebuild_all()
	_select_cell(TownState.INVALID_CELL)
	_refresh_ui("已读取存档「%s」；建筑、分工和生产进度已恢复。" % town.map_name)


func _process(delta: float) -> void:
	# Main 是唯一模拟驱动者：视图切换、重绘都不推进时间；暂停时不传入经过时间。
	if paused:
		return
	town.advance_time(delta)
	if town.grain != _last_shown_grain or town.wood != _last_shown_wood:
		_last_shown_grain = town.grain
		_last_shown_wood = town.wood
		_update_resources()
		_refresh_selection_panel()
		_update_action_buttons()


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
	# 重置会恢复默认地图：地形重建，选择清空，面板不再引用旧建筑格。
	map_3d.rebuild_all()
	_select_cell(TownState.INVALID_CELL)
	_refresh_ui("已重置城镇「%s」；两个视图同步恢复。" % town.map_name)


func _update_resources() -> void:
	var farm_count: int = 0
	for kind: StringName in town.buildings.values():
		if kind == &"farm":
			farm_count += 1
	resources_label.text = "木材：%d    粮食：%d    农田：%d    大本营：%s" % [
		town.wood, town.grain, farm_count,
		"已建立" if town.buildings.values().has(&"hq") else "无"
	]


func _refresh_ui(message: String) -> void:
	_last_shown_grain = town.grain
	_last_shown_wood = town.wood
	_update_resources()
	status_label.text = message
