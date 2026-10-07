extends Node2D
## 2D 视图只读取共享状态；点击由主场景统一处理。

const CELL_SIZE: int = 32
var town: TownState
var selected_cell: Vector2i = TownState.INVALID_CELL


func setup(state: TownState) -> void:
    town = state
    refresh()


func refresh() -> void:
    queue_redraw()


func cell_at_position(local_position: Vector2) -> Vector2i:
    return Vector2i(
        floori(local_position.x / CELL_SIZE),
        floori(local_position.y / CELL_SIZE)
    )


func _draw() -> void:
    if town == null:
        return
    for y in range(TownState.HEIGHT):
        for x in range(TownState.WIDTH):
            var cell := Vector2i(x, y)
            var rect := Rect2(Vector2(x, y) * CELL_SIZE, Vector2.ONE * CELL_SIZE)
            var color := Color("769653")
            if town.is_water(cell):
                color = Color("427fa5")
            draw_rect(rect, color)
            draw_rect(rect, Color("354635"), false, 1.0)
            match town.buildings.get(cell, &""):
                &"farm":
                    _draw_farm(rect)
                &"lumberyard":
                    _draw_lumberyard(rect)
                &"hq":
                    _draw_hq(rect)
    if town.buildings.has(selected_cell):
        var highlight := Rect2(Vector2(selected_cell) * CELL_SIZE, Vector2.ONE * CELL_SIZE)
        draw_rect(highlight.grow(-2.0), Color("ffd75e"), false, 4.0)


func _draw_farm(rect: Rect2) -> void:
    draw_rect(rect.grow(-6.0), Color("d7b36a"))
    for row in range(3):
        var start := rect.position + Vector2(9, 10 + row * 6)
        draw_line(start, start + Vector2(14, 0), Color("896441"), 2.0)


func _draw_lumberyard(rect: Rect2) -> void:
    draw_rect(rect.grow(-6.0), Color("8a6a3f"))
    for row in range(3):
        var start := rect.position + Vector2(8, 12 + row * 7)
        draw_rect(Rect2(start, Vector2(16, 4)), Color("c99a5b"))
        draw_line(start + Vector2(0, 2), start + Vector2(16, 2), Color("6d5027"), 1.0)


func _draw_hq(rect: Rect2) -> void:
    draw_rect(rect.grow(-3.0), Color("5c6470"))
    draw_rect(rect.grow(-7.0), Color("434a54"))
    var font := ThemeDB.fallback_font
    draw_string(font, rect.position + Vector2(9, 21), "营",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("ffd75e"))
