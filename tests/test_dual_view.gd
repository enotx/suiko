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
    check(main.selected_cell == Vector2i(5, 5), "Building auto-selects the new farm")
    check(main.selection_label.text.contains("农田") and main.selection_label.text.contains("(5, 5)"),
        "Selection panel shows name and cell")
    check(main.map_2d.selected_cell == Vector2i(5, 5), "2D view shares the selection")
    check(main.map_3d.selection_mark.visible, "3D selection mark visible")
    # 边框四个部分必须完全落在选中格的一格范围内；此前轴向写反会产生越界横棒。
    var cell_bounds := AABB(Vector3(5.0, 0.0, 5.0), Vector3.ONE)
    for piece in main.map_3d.selection_mark.get_children():
        var mesh_instance := piece as MeshInstance3D
        var local_aabb: AABB = mesh_instance.mesh.get_aabb()
        var world_aabb := AABB(
            local_aabb.position + main.map_3d.selection_mark.position + mesh_instance.position,
            local_aabb.size
        )
        check(cell_bounds.encloses(world_aabb), "Selection border stays inside its cell")
    # 小屋顶面也必须指向该农田，而不是它后面的地块。
    var roof_point: Vector2 = main.map_3d.camera.unproject_position(Vector3(5.73, 0.55, 5.68))
    check(main.map_3d.cell_at_position(roof_point) == Vector2i(5, 5), "Pick visible roof")
    # 贴地高亮边框不能截获射线：点边框边缘视觉区域，仍要拾取到下方地块。
    var mark_point: Vector2 = main.map_3d.camera.unproject_position(Vector3(5.95, 0.03, 5.5))
    check(main.map_3d.cell_at_position(mark_point) == Vector2i(5, 5), "Selection mark must not break picking")
    await click_at(main.map_area.global_position + roof_point)
    check(main.town.wood == 90, "Duplicate 3D build must not charge")
    check(main.selected_cell == Vector2i(5, 5), "Roof click keeps selection on the farm")
    await click_map(Vector2i(1, 5))
    await click_at(main.map_area.global_position + Vector2(2, 2))
    check(main.town.wood == 90, "Water and background must not charge")
    check(main.selected_cell == Vector2i(5, 5), "Water and background clicks keep selection")

    await switch_view()
    check(not main.showing_3d and main.map_2d.visible and not main.world_image.visible, "Switch to 2D")
    check(main.world_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Hidden 3D stops rendering")
    check(main.town.wood == 90 and main.town.buildings.has(Vector2i(5, 5)), "Switch preserves state")
    check(main.map_2d.selected_cell == Vector2i(5, 5) and main.map_3d.selected_cell == Vector2i(5, 5),
        "View switch keeps the shared selection")
    await click_map(Vector2i(5, 5))
    check(main.selected_cell == Vector2i(5, 5), "2D click on farm selects it")
    await click_map(Vector2i(0, 0))
    check(main.selected_cell == Vector2i(5, 5), "Water click keeps selection")
    await click_map(Vector2i(8, 7))
    check(main.town.wood == 80 and main.town.buildings.size() == 2, "2D click builds exactly once")
    check(main.selected_cell == Vector2i(8, 7), "2D build auto-selects the new farm")
    await switch_view()
    check(main.showing_3d and main.map_3d.farms.get_child_count() == 12, "3D reflects both farms")
    check(main.map_3d.selection_mark.position == Vector3(8.5, 0.0, 7.5), "3D mark follows selection")
    check(main.resources_label.text.contains("80"), "Shared HUD reflects resources")

    for i in range(8):
        await click_map(Vector2i(4 + i, 9))
    check(main.town.wood == 0 and main.town.buildings.size() == 10, "Spend starting wood")
    check(main.selected_cell == Vector2i(11, 9), "Last built farm stays selected")
    await click_map(Vector2i(14, 10))
    check(main.town.wood == 0 and main.town.buildings.size() == 10, "Insufficient resources rejected")
    check(main.selected_cell == Vector2i(11, 9), "Rejected build keeps selection")
    await switch_view()
    await click_at(main.reset_button.get_global_rect().get_center())
    check(main.town.wood == 100 and main.town.buildings.is_empty(), "Reset in 2D clears state without click-through")
    check(main.selected_cell == TownState.INVALID_CELL, "Reset clears selection")
    check(main.selection_label.text.contains("未选中"), "Panel shows no selection after reset")
    await switch_view()
    check(main.map_3d.farms.get_child_count() == 0, "Reset clears 3D models")
    check(not main.map_3d.selection_mark.visible, "3D mark hidden after reset")
    await click_map(Vector2i(7, 4))
    check(main.selected_cell == Vector2i(7, 4), "3D build selects the farm")
    await click_at(main.reset_button.get_global_rect().get_center())
    check(main.town.wood == 100 and main.town.buildings.is_empty(), "Reset in 3D")
    check(main.selected_cell == TownState.INVALID_CELL, "Reset in 3D clears selection")

    await click_map(Vector2i(6, 3))
    check(main.selected_cell == Vector2i(6, 3), "Farm selected for deselect test")
    await click_at(main.deselect_button.get_global_rect().get_center())
    check(main.selected_cell == TownState.INVALID_CELL, "Deselect button clears selection")
    check(main.selection_label.text.contains("未选中"), "Panel cleared by deselect")
    check(not main.map_3d.selection_mark.visible, "3D mark hidden after deselect")

    # P03：阮小二分配、调岗、撤回与重置；全程不允许一人占两个工位。
    check(main.selection_label.text.contains("空闲"), "Panel shows worker idle when nothing selected")
    check(main.assign_button.disabled and main.withdraw_button.disabled,
        "Worker buttons disabled without a farm selected")
    await click_map(Vector2i(6, 3))
    await click_at(main.assign_button.get_global_rect().get_center())
    check(main.town.worker_cell == Vector2i(6, 3), "Assign puts worker on the selected farm")
    check(main.selection_label.text.contains("阮小二"), "Panel shows worker after assign")
    check(main.assign_button.disabled, "Assign disabled when worker is already there")
    check(not main.withdraw_button.disabled, "Withdraw enabled while worker on selected farm")
    await click_at(main.assign_button.get_global_rect().get_center())
    check(main.town.worker_cell == Vector2i(6, 3), "Repeated assign keeps the single workplace")
    await click_map(Vector2i(7, 6))
    check(main.town.buildings.size() == 2, "Second farm built for transfer test")
    await click_at(main.assign_button.get_global_rect().get_center())
    check(main.town.worker_cell == Vector2i(7, 6), "Assign to another farm moves the worker")
    var failed: String = main.town.assign_worker(Vector2i(9, 9))
    check(failed.contains("没有"), "Assign to a cell without farm is rejected")
    check(main.town.worker_cell == Vector2i(7, 6), "Failed assign keeps the old job")
    await click_at(main.withdraw_button.get_global_rect().get_center())
    check(main.town.worker_cell == TownState.INVALID_CELL, "Withdraw frees the worker")
    await click_at(main.withdraw_button.get_global_rect().get_center())
    check(main.town.worker_cell == TownState.INVALID_CELL, "Repeated withdraw is harmless")
    await click_map(Vector2i(7, 6))
    await click_at(main.assign_button.get_global_rect().get_center())
    check(main.town.worker_cell == Vector2i(7, 6), "Worker reassigned before reset")
    await click_at(main.reset_button.get_global_rect().get_center())
    check(main.town.worker_cell == TownState.INVALID_CELL, "Reset returns worker to idle")
    check(main.selection_label.text.contains("空闲"), "Panel shows idle after reset")

    # P04：实时产粮数值——用独立规则实例验证，避免运行帧时序影响断言。
    var sim := TownState.new()
    sim.try_build(Vector2i(3, 3))
    sim.advance_time(0.5)
    check(sim.grain == 0 and is_equal_approx(sim.farm_progress_ratio(Vector2i(3, 3)), 0.5),
        "Half a second yields half progress, no grain yet")
    sim.advance_time(0.5)
    check(sim.grain == 1, "Idle farm yields one grain per second")
    sim.assign_worker(Vector2i(3, 3))
    sim.advance_time(1.0)
    check(sim.grain == 3, "Worked farm yields two grains per second")
    # 相同总时间在不同时间步划分下产量一致（取值远离整数边界）。
    var stepped := TownState.new()
    stepped.try_build(Vector2i(3, 3))
    stepped.assign_worker(Vector2i(3, 3))
    for i in range(10):
        stepped.advance_time(0.31)
    var bulk := TownState.new()
    bulk.try_build(Vector2i(3, 3))
    bulk.assign_worker(Vector2i(3, 3))
    bulk.advance_time(3.1)
    check(stepped.grain == 6 and bulk.grain == 6, "Same total time must give same yield")
    bulk.withdraw_worker()
    bulk.advance_time(1.0)
    check(bulk.grain == 7, "After withdraw the farm yields one per second")
    bulk.advance_time(10.0)
    check(bulk.grain == 17, "Long timestep accumulates multiple cycles without loss")
    sim.reset()
    check(sim.grain == 0 and sim.farm_progress.is_empty(), "Reset clears grain and progress")

    # 暂停按钮与粮食 HUD。
    check(main.resources_label.text.contains("粮食"), "HUD shows grain")
    check(not main.paused and main.pause_button.text == "暂停经营", "Starts unpaused")
    await click_at(main.pause_button.get_global_rect().get_center())
    check(main.paused and main.pause_button.text == "继续经营", "Pause toggles state and label")
    await click_at(main.pause_button.get_global_rect().get_center())
    check(not main.paused and main.pause_button.text == "暂停经营", "Resume restores production")

    if "--capture" in OS.get_cmdline_user_args():
        for cell: Vector2i in [Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 5), Vector2i(10, 7)]:
            await click_map(cell)
        await click_map(Vector2i(5, 4))
        await click_at(main.assign_button.get_global_rect().get_center())
        DirAccess.make_dir_recursive_absolute("res://build/verification")
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png("res://build/verification/dual-view-3d.png")
        await switch_view()
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png("res://build/verification/dual-view-2d.png")

    if failures == 0:
        print("PASS: shared state, 192 projected cells, GUI clicks, selection across views, resources and resets")
    else:
        print("FAIL: %d checks" % failures)
    main.queue_free()
    await process_frame
    quit(0 if failures == 0 else 1)
