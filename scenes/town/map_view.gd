extends Node2D
## 2D 视图只读取共享状态；点击由主场景统一处理。
## 地图尺寸不固定（D20）：把整张地图等比缩放到显示区域中央。

const AREA_SIZE := Vector2(512, 384)  # 与 main.tscn 的 MapArea 尺寸一致
const TERRAIN_COLORS := {
	&"plain": Color("769653"),
	&"grass": Color("6ca16e"),
	&"water": Color("427fa5"),
	&"highland": Color("a8b868"),
	&"forest": Color("3f6d43"),
	&"stone": Color("9a9a8f"),
	&"iron": Color("a0785c"),
}
const RESOURCE_GLYPHS := { &"forest": "林", &"stone": "石", &"iron": "铁" }

var town: TownState
var selected_cell: Vector2i = TownState.INVALID_CELL
var _cell_px := 32.0
var _origin := Vector2.ZERO


func setup(state: TownState) -> void:
	town = state
	refresh()


func refresh() -> void:
	queue_redraw()


func _recalc_metrics() -> void:
	if town == null:
		return
	_cell_px = maxf(4.0, floorf(minf(AREA_SIZE.x / town.map_size.x, AREA_SIZE.y / town.map_size.y)))
	_origin = ((AREA_SIZE - Vector2(town.map_size) * _cell_px) * 0.5).floor()


func cell_center(cell: Vector2i) -> Vector2:
	return _origin + (Vector2(cell) + Vector2.ONE * 0.5) * _cell_px


func cell_at_position(local_position: Vector2) -> Vector2i:
	if town == null:
		return TownState.INVALID_CELL
	var grid := (local_position - _origin) / _cell_px
	var cell := Vector2i(floori(grid.x), floori(grid.y))
	return cell if town.is_inside(cell) else TownState.INVALID_CELL


func _draw() -> void:
	if town == null:
		return
	_recalc_metrics()
	for y: int in range(town.map_size.y):
		for x: int in range(town.map_size.x):
			var cell := Vector2i(x, y)
			var rect := Rect2(_origin + Vector2(x, y) * _cell_px, Vector2.ONE * _cell_px)
			var color: Color = TERRAIN_COLORS.get(town.terrain_kind(cell), TERRAIN_COLORS[&"plain"])
			draw_rect(rect, color)
			if _cell_px >= 8.0:
				draw_rect(rect, Color("354635"), false, 1.0)
			var glyph: String = RESOURCE_GLYPHS.get(town.terrain_kind(cell), "")
			if glyph != "" and _cell_px >= 14.0:
				draw_string(ThemeDB.fallback_font, rect.position + Vector2(4.0, _cell_px - 4.0),
					glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_cell_px * 0.7), Color("1e2a1e"))
	# 建筑按锚点与占地绘制：多格建筑画一个整体轮廓，不再逐格重复。
	for origin: Vector2i in town.buildings:
		var def: BuildingDef = town.building_def(town.buildings[origin])
		if def == null:
			continue
		var rect := Rect2(_origin + Vector2(origin) * _cell_px, Vector2(def.footprint) * _cell_px)
		match town.buildings[origin]:
			&"farm":
				_draw_farm(rect)
			&"lumberyard":
				_draw_lumberyard(rect)
			&"house":
				_draw_house(rect)
			&"hq":
				_draw_hq(rect)
	var selected_def: BuildingDef = town.building_def(town.buildings.get(selected_cell, &""))
	if selected_def != null:
		var highlight := Rect2(
			_origin + Vector2(selected_cell) * _cell_px, Vector2(selected_def.footprint) * _cell_px)
		var inset := maxf(1.0, _cell_px * 0.08)
		draw_rect(highlight.grow(-inset), Color("ffd75e"), false, maxf(1.5, _cell_px * 0.12))


func _draw_farm(rect: Rect2) -> void:
	# 农田（2×2）：田块 + 三条垄线，按占地比例绘制。
	draw_rect(rect.grow(-2.0), Color("d7b36a"))
	for row in range(3):
		var y := rect.position.y + rect.size.y * (0.18 + 0.28 * row)
		draw_line(Vector2(rect.position.x + 3.0, y),
			Vector2(rect.end.x - 3.0, y), Color("896441"), 2.0)


func _draw_lumberyard(rect: Rect2) -> void:
	# 伐木场（2×2）：底色 + 两段料堆色块。
	draw_rect(rect.grow(-2.0), Color("8a6a3f"))
	draw_rect(Rect2(rect.position + rect.size * Vector2(0.15, 0.15),
		rect.size * Vector2(0.45, 0.28)), Color("c99a5b"))
	draw_rect(Rect2(rect.position + rect.size * Vector2(0.15, 0.55),
		rect.size * Vector2(0.45, 0.28)), Color("7c5a2c"))


func _draw_house(rect: Rect2) -> void:
	# 民居（2×2）：暖色墙体 + 深色屋顶带，格够大时画"居"字。
	draw_rect(rect.grow(-2.0), Color("c8a06a"))
	draw_rect(Rect2(rect.position + rect.size * Vector2(0.1, 0.14),
		rect.size * Vector2(0.8, 0.24)), Color("8a5a3c"))
	if _cell_px >= 12.0:
		var center := rect.get_center()
		var glyph_size := int(_cell_px * 0.8)
		draw_string(ThemeDB.fallback_font,
			center + Vector2(-glyph_size * 0.35, glyph_size * 0.35), "居",
			HORIZONTAL_ALIGNMENT_LEFT, -1, glyph_size, Color("5a3a20"))


func _draw_hq(rect: Rect2) -> void:
	# 大本营占地可以多于 1×1（E01.b）：按整个占地矩形画大院轮廓，字居中。
	var f := _cell_px / 32.0
	draw_rect(rect.grow(-3.0 * f), Color("5c6470"))
	draw_rect(rect.grow(-7.0 * f), Color("434a54"))
	if _cell_px >= 12.0 and rect.size.x >= _cell_px * 2.0 - 1.0:
		var center := rect.get_center()
		draw_string(ThemeDB.fallback_font, center + Vector2(-8.0, 6.0) * f, "营",
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(16.0 * f), Color("ffd75e"))
	elif _cell_px >= 14.0:
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(9.0, 21.0) * f, "营",
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(16.0 * f), Color("ffd75e"))
