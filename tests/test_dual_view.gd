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


func click_build(cell: Vector2i, build_button: Button) -> void:
    # D16 交互：先点空地选中，再点对应建造按钮。
    await click_map(cell)
    await click_at(build_button.get_global_rect().get_center())


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

    # 配表自检：重复 id、缺失字段、非法产出都不允许上线。
    check(TownState.validate_defs().is_empty(), "Building defs must validate cleanly")
    # 大本营是预置建筑：开局即在场上。
    check(main.town.buildings.get(TownState.HQ_CELL, &"") == &"hq",
        "Headquarters must be preset on the map")

    # 每个空地块的屏幕中心都必须能反向定位，且完整落在地图显示区域。
    for y in range(TownState.HEIGHT):
        for x in range(TownState.WIDTH):
            var point: Vector2 = main.map_3d.camera.unproject_position(Vector3(x + 0.5, 0, y + 0.5))
            check(Rect2(Vector2.ZERO, Vector2(512, 384)).has_point(point), "3D tile clipped")
            check(main.map_3d.cell_at_position(point) == Vector2i(x, y), "3D tile picking mismatch")

    await click_build(Vector2i(5, 5), main.build_farm_button)
    check(main.town.wood == 90 and main.town.buildings.size() == 2, "3D click builds exactly once")
    check(main.selected_cell == Vector2i(5, 5), "Building auto-selects the new farm")
    check(main.selection_label.text.contains("农田") and main.selection_label.text.contains("(5, 5)"),
        "Selection panel shows name and cell")
    check(main.map_2d.selected_cell == Vector2i(5, 5), "2D view shares the selection")
    check(main.map_3d.selection_mark.visible, "3D selection mark visible")
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
    check(main.status_label.text.contains("水面"), "Water click explains itself")
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
    await click_build(Vector2i(8, 7), main.build_farm_button)
    check(main.town.wood == 80 and main.town.buildings.size() == 3, "2D click builds exactly once")
    check(main.selected_cell == Vector2i(8, 7), "2D build auto-selects the new farm")
    await switch_view()
    check(main.showing_3d and main.map_3d.buildings_root.get_child_count() == 16, "3D reflects both farms and HQ")
    check(main.map_3d.selection_mark.position == Vector3(8.5, 0.0, 7.5), "3D mark follows selection")
    check(main.resources_label.text.contains("80"), "Shared HUD reflects resources")

    for i in range(8):
        await click_build(Vector2i(4 + i, 9), main.build_farm_button)
    check(main.town.wood == 0 and main.town.buildings.size() == 11, "Spend starting wood")
    check(main.selected_cell == Vector2i(11, 9), "Last built farm stays selected")
    await click_map(Vector2i(14, 10))
    check(main.town.wood == 0 and main.town.buildings.size() == 11, "Outside map is not selected or built")
    await click_map(Vector2i(13, 8))
    check(main.build_farm_button.disabled and main.build_lumberyard_button.disabled,
        "Build buttons disabled without enough wood")
    await click_at(main.deselect_button.get_global_rect().get_center())
    await switch_view()
    await click_at(main.reset_button.get_global_rect().get_center())
    check(main.town.wood == 100 and main.town.buildings.size() == 1, "Reset keeps only the preset HQ")
    check(main.selected_cell == TownState.INVALID_CELL, "Reset clears selection")
    check(main.selection_label.text.contains("未选中"), "Panel shows no selection after reset")
    await switch_view()
    check(main.map_3d.buildings_root.get_child_count() == 4, "Reset leaves only HQ models")
    check(not main.map_3d.selection_mark.visible, "3D mark hidden after reset")
    await click_build(Vector2i(7, 4), main.build_farm_button)
    check(main.selected_cell == Vector2i(7, 4), "3D build selects the farm")
    await click_at(main.reset_button.get_global_rect().get_center())
    check(main.town.wood == 100 and main.town.buildings.size() == 1, "Reset in 3D")
    check(main.selected_cell == TownState.INVALID_CELL, "Reset in 3D clears selection")

    # P03：阮小二分配、调岗、撤回与重置；全程不允许一人占两个工位。
    check(main.selection_label.text.contains("空闲"), "Panel shows worker idle when nothing selected")
    check(main.assign_button.visible == false and main.withdraw_button.visible == false,
        "Worker buttons hidden when nothing is selected")
    await click_build(Vector2i(6, 3), main.build_farm_button)
    check(main.assign_button.visible and main.build_farm_button.visible == false,
        "Worker and build buttons switch by context")
    await click_at(main.assign_button.get_global_rect().get_center())
    check(main.town.worker_cell == Vector2i(6, 3), "Assign puts worker on the selected farm")
    check(main.selection_label.text.contains("阮小二"), "Panel shows worker after assign")
    check(main.assign_button.disabled, "Assign disabled when worker is already there")
    check(not main.withdraw_button.disabled, "Withdraw enabled while worker on selected farm")
    await click_at(main.assign_button.get_global_rect().get_center())
    check(main.town.worker_cell == Vector2i(6, 3), "Repeated assign keeps the single workplace")
    await click_build(Vector2i(7, 6), main.build_farm_button)
    check(main.town.buildings.size() == 3, "Second farm built for transfer test")
    await click_at(main.assign_button.get_global_rect().get_center())
    check(main.town.worker_cell == Vector2i(7, 6), "Assign to another farm moves the worker")
    var failed: String = main.town.assign_worker(Vector2i(9, 9))
    check(failed.contains("没有"), "Assign to a cell without building is rejected")
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

    # P07：大本营不可建第二座、不需要工人；伐木场产木材。
    await click_map(TownState.HQ_CELL)
    check(main.selection_label.text.contains("大本营"), "HQ can be selected and identified")
    check(main.assign_button.disabled, "Assign disabled on HQ")
    check(main.town.assign_worker(TownState.HQ_CELL).contains("不需要工人"), "HQ refuses workers")
    var duplicate_hq: String = main.town.try_build(Vector2i(4, 6), &"hq")
    check(duplicate_hq.contains("只能有一座"), "Second HQ rejected by unique rule")
    await click_map(Vector2i(4, 6))
    check(main.build_lumberyard_button.visible and not main.assign_button.visible,
        "Empty land shows build buttons")
    await click_build(Vector2i(4, 6), main.build_lumberyard_button)
    check(main.town.buildings.get(Vector2i(4, 6), &"") == &"lumberyard", "Lumberyard can be built")
    check(main.town.wood == 80, "Lumberyard costs 20 wood")
    var mill_ok := TownState.new()
    mill_ok.try_build(Vector2i(4, 4), &"lumberyard")
    mill_ok.assign_worker(Vector2i(4, 4))
    var wood_before: int = mill_ok.wood
    mill_ok.advance_time(1.0)
    check(mill_ok.wood == wood_before + 2, "Worked lumberyard yields two wood per second")
    mill_ok.withdraw_worker()
    mill_ok.advance_time(1.0)
    check(mill_ok.wood == wood_before + 3, "Idle lumberyard yields one wood per second")

    # P04：实时产粮数值——用独立规则实例验证，避免运行帧时序影响断言。
    # 无人工况 +1/秒：推进 0.5 秒得到真正的“半个周期”。
    var saver := TownState.new()
    saver.try_build(Vector2i(4, 4), &"farm")
    saver.advance_time(0.5)
    var save_data: Dictionary = saver.to_save_data()
    var loader := TownState.new()
    loader.try_build(Vector2i(9, 9), &"farm")
    check(loader.apply_save_data(save_data) == "", "Valid save applies cleanly")
    check(loader.wood == saver.wood and loader.grain == saver.grain
        and loader.worker_cell == TownState.INVALID_CELL and loader.buildings.size() == 2
        and is_equal_approx(loader.farm_progress_ratio(Vector2i(4, 4)), 0.5),
        "Save round-trip restores resources, worker, farm and progress")
    loader.advance_time(0.5)
    check(loader.grain == 1, "Continuing after load does not double-settle")
    var guard := TownState.new()
    guard.try_build(Vector2i(4, 4), &"farm")
    guard.assign_worker(Vector2i(4, 4))
    check(guard.apply_save_data("junk") != "", "Non-dictionary save rejected")
    check(guard.apply_save_data({"version": 0, "wood": 1, "grain": 1, "buildings": []}) != "",
        "Old version rejected")
    check(guard.apply_save_data({"version": 2, "wood": 50, "grain": 0,
        "worker_x": -1, "worker_y": -1,
        "buildings": [{"x": 0, "y": 0, "kind": "farm", "progress": 0.0}]}) != "",
        "Water-cell building rejected")
    check(guard.apply_save_data({"version": 2, "wood": 50, "grain": 0,
        "worker_x": 4, "worker_y": 4, "buildings": []}) != "",
        "Worker pointing at missing farm rejected")
    check(guard.apply_save_data({"version": 2, "wood": 50, "grain": 0,
        "worker_x": -1, "worker_y": -1,
        "buildings": [{"x": 4, "y": 4, "kind": "hq", "progress": 0.0},
            {"x": 5, "y": 4, "kind": "hq", "progress": 0.0}]}) != "",
        "Duplicate unique building rejected")
    var v1_data := {"version": 1, "wood": 55, "grain": 3, "worker_x": 5, "worker_y": 5,
        "buildings": [{"x": 5, "y": 5, "kind": "farm", "progress": 0.25}]}
    var migrated := TownState.new()
    check(migrated.apply_save_data(v1_data) == "", "V1 save migrates cleanly")
    check(migrated.buildings.size() == 2 and migrated.buildings.get(TownState.HQ_CELL, &"") == &"hq"
        and migrated.worker_cell == Vector2i(5, 5),
        "Migration plants HQ and keeps worker")
    check(guard.wood == 90 and guard.grain == 0 and guard.worker_cell == Vector2i(4, 4)
        and guard.buildings.size() == 2,
        "Rejected saves leave current state untouched")

    # P05/P04 UI：缺失存档提示；暂停后保存→重置→读取，数值必须精确恢复；损坏文件不破坏经营。
    DirAccess.remove_absolute("user://town_save.json")
    await click_at(main.load_button.get_global_rect().get_center())
    check(main.status_label.text.contains("还没有存档"), "Missing save reported")
    await click_build(Vector2i(8, 2), main.build_farm_button)
    check(main.town.buildings.get(Vector2i(8, 2), &"") == &"farm", "Farm built for save test")
    await click_at(main.assign_button.get_global_rect().get_center())
    await click_at(main.pause_button.get_global_rect().get_center())
    var saved_wood: int = main.town.wood
    var saved_grain: int = main.town.grain
    await click_at(main.save_button.get_global_rect().get_center())
    check(main.status_label.text.contains("已保存"), "Save reports success")
    await click_at(main.reset_button.get_global_rect().get_center())
    check(main.town.buildings.size() == 1 and main.town.wood == 100, "Reset clears before load")
    await click_at(main.load_button.get_global_rect().get_center())
    check(main.town.wood == saved_wood, "Load wood %d vs saved %d" % [main.town.wood, saved_wood])
    check(main.town.grain == saved_grain, "Load grain %d vs saved %d" % [main.town.grain, saved_grain])
    check(main.town.worker_cell == Vector2i(8, 2), "Load worker %s" % main.town.worker_cell)
    check(main.town.buildings.size() == 3, "Load buildings 3 (HQ, farm and lumberyard)")
    check(main.status_label.text.contains("已读取"), "Load reports success")
    var broken := FileAccess.open("user://town_save.json", FileAccess.WRITE)
    broken.store_string("not-json{{{")
    broken.close()
    await click_at(main.load_button.get_global_rect().get_center())
    check(main.status_label.text.contains("损坏"), "Corrupt save reported")
    check(main.town.wood == saved_wood and main.town.worker_cell == Vector2i(8, 2),
        "Corrupt load keeps current state")
    await click_at(main.pause_button.get_global_rect().get_center())
    check(not main.paused, "Back to running after save/load checks")
    DirAccess.remove_absolute("user://town_save.json")

    # P04 UI：暂停按钮与粮食 HUD。
    check(main.resources_label.text.contains("粮食"), "HUD shows grain")
    check(not main.paused and main.pause_button.text == "暂停经营", "Starts unpaused")
    await click_at(main.pause_button.get_global_rect().get_center())
    check(main.paused and main.pause_button.text == "继续经营", "Pause toggles state and label")
    await click_at(main.pause_button.get_global_rect().get_center())
    check(not main.paused and main.pause_button.text == "暂停经营", "Resume restores production")

    if "--capture" in OS.get_cmdline_user_args():
        for cell: Vector2i in [Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 5), Vector2i(10, 7)]:
            await click_build(cell, main.build_farm_button)
        await click_build(Vector2i(11, 4), main.build_lumberyard_button)
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
