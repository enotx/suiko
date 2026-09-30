extends SceneTree
## 无外部插件的集成检查。通过真实 GUI 输入验证双视图，不能替代人工美术验收。

var failures: int = 0
var main: Node


func _initialize() -> void:
    call_deferred("_run")


func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error(message)


func click_at(position: Vector2) -> void:
    var motion := InputEventMouseMotion.new()
    motion.position = position
    motion.global_position = position
    root.push_input(motion, true)
    for pressed: bool in [true, false]:
        var event := InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = pressed
        event.position = position
        event.global_position = position
        root.push_input(event, true)
    await process_frame


func click_map(cell: Vector2i) -> void:
    var local_position: Vector2
    if main.showing_3d:
        local_position = main.map_3d.camera.unproject_position(
            Vector3(cell.x + 0.5, 0.0, cell.y + 0.5)
        )
    else:
        local_position = (Vector2(cell) + Vector2.ONE * 0.5) * 32.0
    await click_at(main.map_area.global_position + local_position)


func switch_view() -> void:
    await click_at(main.view_button.get_global_rect().get_center())


func _run() -> void:
    var scene: PackedScene = load("res://scenes/main/main.tscn")
    main = scene.instantiate()
    # 原生节点类型与脚本不匹配时，Godot 仍可能返回无脚本节点。
    # 立即失败退出，避免后续访问 town 等属性时只报错却不结束测试。
    if main.get_script() == null:
        check(false, "Main script failed to attach; check scene/script native types")
        main.free()
        quit(1)
        return
    root.add_child(main)
    await process_frame
    await process_frame
    check(main.map_2d.town == main.town and main.map_3d.town == main.town,
        "Both views must reference the same state")
    check(main.showing_3d, "Start in 3D")

    # 每个空地块的屏幕中心都必须能反向定位，且完整落在地图显示区域。
    for y in range(TownState.HEIGHT):
        for x in range(TownState.WIDTH):
            var point: Vector2 = main.map_3d.camera.unproject_position(Vector3(x + 0.5, 0, y + 0.5))
            check(Rect2(Vector2.ZERO, Vector2(512, 384)).has_point(point), "3D tile clipped")
            check(main.map_3d.cell_at_position(point) == Vector2i(x, y), "3D tile picking mismatch")

    await click_map(Vector2i(5, 5))
    check(main.town.wood == 90 and main.town.buildings.size() == 1, "3D click builds exactly once")
    # 小屋顶面也必须指向该农田，而不是它后面的地块。
    var roof_point: Vector2 = main.map_3d.camera.unproject_position(Vector3(5.73, 0.55, 5.68))
    check(main.map_3d.cell_at_position(roof_point) == Vector2i(5, 5), "Pick visible roof")
    await click_at(main.map_area.global_position + roof_point)
    check(main.town.wood == 90, "Duplicate 3D build must not charge")
    await click_map(Vector2i(1, 5))
    await click_at(main.map_area.global_position + Vector2(2, 2))
    check(main.town.wood == 90, "Water and background must not charge")

    await switch_view()
    check(not main.showing_3d and main.map_2d.visible and not main.world_image.visible, "Switch to 2D")
    check(main.world_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Hidden 3D stops rendering")
    check(main.town.wood == 90 and main.town.buildings.has(Vector2i(5, 5)), "Switch preserves state")
    await click_map(Vector2i(5, 5))
    await click_map(Vector2i(0, 0))
    check(main.town.wood == 90, "2D duplicate and water must not charge")
    await click_map(Vector2i(8, 7))
    check(main.town.wood == 80 and main.town.buildings.size() == 2, "2D click builds exactly once")
    await switch_view()
    check(main.showing_3d and main.map_3d.farms.get_child_count() == 12, "3D reflects both farms")
    check(main.resources_label.text.contains("80"), "Shared HUD reflects resources")

    for i in range(8):
        await click_map(Vector2i(4 + i, 9))
    check(main.town.wood == 0 and main.town.buildings.size() == 10, "Spend starting wood")
    await click_map(Vector2i(14, 10))
    check(main.town.wood == 0 and main.town.buildings.size() == 10, "Insufficient resources rejected")
    await switch_view()
    await click_at(main.reset_button.get_global_rect().get_center())
    check(main.town.wood == 100 and main.town.buildings.is_empty(), "Reset in 2D clears state without click-through")
    await switch_view()
    check(main.map_3d.farms.get_child_count() == 0, "Reset clears 3D models")
    await click_map(Vector2i(7, 4))
    await click_at(main.reset_button.get_global_rect().get_center())
    check(main.town.wood == 100 and main.town.buildings.is_empty(), "Reset in 3D")

    if "--capture" in OS.get_cmdline_user_args():
        for cell: Vector2i in [Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 5), Vector2i(10, 7)]:
            await click_map(cell)
        DirAccess.make_dir_recursive_absolute("res://build/verification")
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png("res://build/verification/dual-view-3d.png")
        await switch_view()
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png("res://build/verification/dual-view-2d.png")

    if failures == 0:
        print("PASS: shared state, 192 projected cells, GUI clicks, both views, resources and resets")
    else:
        print("FAIL: %d checks" % failures)
    main.queue_free()
    await process_frame
    quit(0 if failures == 0 else 1)
