extends Node2D
## 2D 视图只读取共享状态；点击由主场景统一处理。

const CELL_SIZE: int = 32
var town: TownState


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
            if town.buildings.has(cell):
                draw_rect(rect.grow(-6.0), Color("d7b36a"))
                for row in range(3):
                    var start := rect.position + Vector2(9, 10 + row * 6)
                    draw_line(start, start + Vector2(14, 0), Color("896441"), 2.0)
