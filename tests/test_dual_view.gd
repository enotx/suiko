extends SceneTree
## 无外部插件的集成检查。通过真实 GUI 输入验证双视图，不能替代人工美术验收。
## E01.a：60×60 调色板地图、新地形区块、3D 相机平移/缩放、存档 v4 与旧档迁移。

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
        local_position = main.map_2d.cell_center(cell)
    await click_at(main.map_area.global_position + local_position)


func click_build(cell: Vector2i, build_button: Button) -> void:
    # D16 交互：先点空地选中，再点对应建造按钮。
    await click_map(cell)
    await click_at(build_button.get_global_rect().get_center())


func drag_on_map(from: Vector2, to: Vector2) -> void:
    # 模拟按住左键拖动：按下 → 多段位移（带按键掩码）→ 松开。
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = from
    press.global_position = from
    root.push_input(press, true)
    for i: int in range(8):
        var motion := InputEventMouseMotion.new()
        motion.position = from.lerp(to, (i + 1) / 8.0)
        motion.global_position = from.lerp(to, (i + 1) / 8.0)
        motion.relative = (to - from) / 8.0
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        root.push_input(motion, true)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    release.position = to
    release.global_position = to
    root.push_input(release, true)
    await process_frame


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
    # E01.a：新游戏默认加载 60×60 测试城镇布局图。
    var town: TownState = main.town
    check(town.map_size == Vector2i(60, 60), "Default map is the 60x60 test town")
    check(town.map_name == "测试城镇", "Map name comes from the sidecar file")
    check(town.hq_cell == Vector2i(30, 30) and town.buildings.get(town.hq_cell, &"") == &"hq",
        "HQ preset sits on the marker cell")
    check(town.is_water(Vector2i(13, 13)), "North-west lake is water")
    check(town.terrain_kind(Vector2i(30, 26)) == &"grass", "Grass meadow around HQ")
    check(town.is_highland(Vector2i(47, 12)) and town.terrain_height(Vector2i(47, 12)) == 0.5,
        "North-east plateau is one level up")
    check(town.terrain_height(Vector2i(40, 30)) == 0.0, "HQ plain sits at ground level")
    check(town.terrain_kind(Vector2i(16, 30)) == &"forest"
        and town.terrain_kind(Vector2i(44, 21)) == &"stone"
        and town.terrain_kind(Vector2i(48, 23)) == &"iron",
        "Forest, stone and iron resource blocks exist")
    # 建造限制：水面照旧拒绝；资源区块在采集玩法接入前拒绝（临时规则）。
    check(town.try_build(Vector2i(13, 13), &"farm").contains("水面"), "Water rejects building")
    check(town.try_build(Vector2i(16, 30), &"farm").contains("资源区块"), "Forest rejects building")
    check(town.try_build(Vector2i(44, 21), &"farm").contains("资源区块"), "Stone rejects building")
    check(town.try_build(Vector2i(48, 23), &"farm").contains("资源区块"), "Iron rejects building")
    check(town.wood == TownState.STARTING_WOOD, "Rejected builds never charge")
    var grass_probe := TownState.new()
    check(grass_probe.try_build(Vector2i(30, 26), &"farm").contains("已")
        and grass_probe.wood == 90, "Grass accepts farms like plain")

    # E01.b：多格占地——大本营 2×2，锚点是标记格，覆盖格的点击与建造都归属锚点。
    check(town.building_origin_at(Vector2i(31, 31)) == Vector2i(30, 30)
        and town.building_origin_at(Vector2i(30, 31)) == Vector2i(30, 30),
        "HQ covers the cells right and down of the marker")
    check(town.building_def_at(Vector2i(31, 31)) == TownState.building_def(&"hq"),
        "Covered cell resolves to the HQ def")
    check(town.can_build_on(Vector2i(31, 31)) == false, "Covered cell is not buildable")
    check(town.try_build(Vector2i(31, 31), &"farm").contains("重叠"), "Covered cell rejects building")
    check(town.try_build(Vector2i(30, 31), &"farm").contains("重叠"), "Second covered cell rejects too")
    check(town.wood == TownState.STARTING_WOOD, "Overlap rejections never charge")

    # 布局解析：合法小图、大本营占地越界、缺标记、非法颜色、多标记都要有明确中文原因。
    var tiny := Image.create_empty(3, 3, false, Image.FORMAT_RGBA8)
    tiny.fill(Color("769653"))
    tiny.set_pixel(2, 2, Color("ff00ff"))
    var edge := TownState.parse_layout(ImageTexture.create_from_image(tiny))
    check(edge.has("error") and str(edge["error"]).contains("超出"),
        "HQ footprint must fit inside the layout image")
    tiny.set_pixel(1, 1, Color("ff00ff"))
    tiny.set_pixel(2, 2, Color("769653"))
    var parsed := TownState.parse_layout(ImageTexture.create_from_image(tiny), {"name": "小图"})
    check(not parsed.has("error") and parsed["size"] == Vector2i(3, 3)
        and parsed["hq_cell"] == Vector2i(1, 1) and parsed["name"] == "小图",
        "Tiny layout parses with marker and sidecar name")
    tiny.set_pixel(1, 1, Color("769653"))
    var no_hq := TownState.parse_layout(ImageTexture.create_from_image(tiny))
    check(no_hq.has("error") and str(no_hq["error"]).contains("大本营"), "Missing HQ marker reported")
    tiny.set_pixel(0, 0, Color("123456"))
    var bad_color := TownState.parse_layout(ImageTexture.create_from_image(tiny))
    check(bad_color.has("error") and str(bad_color["error"]).contains("调色板")
        and str(bad_color["error"]).contains("(0, 0)"), "Off-palette color reports the cell")
    tiny.set_pixel(0, 0, Color("427fa5"))
    tiny.set_pixel(1, 1, Color("ff00ff"))
    tiny.set_pixel(2, 2, Color("ff00ff"))
    var two_hq := TownState.parse_layout(ImageTexture.create_from_image(tiny))
    check(two_hq.has("error") and str(two_hq["error"]).contains("只能有一个"),
        "Two HQ markers rejected")
    var loader_state := TownState.new()
    tiny.set_pixel(2, 2, Color("769653"))
    check(loader_state.load_layout_texture(ImageTexture.create_from_image(tiny), {"name": "小图"}) == "",
        "Valid layout loads")
    check(loader_state.map_size == Vector2i(3, 3) and loader_state.hq_cell == Vector2i(1, 1)
        and loader_state.terrain_kind(Vector2i(0, 0)) == &"water",
        "Loaded layout drives terrain and HQ")
    loader_state.reset()
    check(loader_state.map_size == Vector2i(60, 60) and loader_state.map_name == "测试城镇",
        "Reset returns to the built-in test town")

    # 全景后做投影与拾取抽查：每 4 格取一个样本，含边缘与高地。
    main.map_3d.frame_map()
    await process_frame
    var seen := 0
    for y: int in range(0, 60, 4):
        for x: int in range(0, 60, 4):
            var point: Vector2 = main.map_3d.camera.unproject_position(Vector3(x + 0.5, 0, y + 0.5))
            check(Rect2(Vector2.ZERO, Vector2(512, 384)).has_point(point),
                "Sampled tile %s must project inside the viewport" % Vector2i(x, y))
            check(main.map_3d.cell_at_position(point) == Vector2i(x, y),
                "Sampled tile picking mismatch at %s" % Vector2i(x, y))
            seen += 1
    check(seen == 225, "Sampling loop covers 225 tiles")

    # 相机：缩放夹在范围内、拖动方向符合“抓住地图”、越界平移被夹住。
    main.map_3d.zoom_step(100.0)
    check(main.map_3d.zoom_size == main.map_3d.ZOOM_MIN, "Zoom clamps at the minimum")
    var center_point: Vector2 = main.map_3d.camera.unproject_position(Vector3(30.5, 0, 30.5))
    check(main.map_3d.cell_at_position(center_point) == Vector2i(30, 30),
        "Picking survives extreme zoom-in")
    main.map_3d.zoom_step(-200.0)
    check(main.map_3d.zoom_size == main.map_3d.ZOOM_MAX, "Zoom clamps at the maximum")
    main.map_3d.frame_map()
    main.map_3d.begin_pan()
    main.map_3d.pan_by(Vector2(300, 0))
    check(main.map_3d.cam_target.x < 30.0, "Dragging right moves the map right")
    main.map_3d.pan_by(Vector2(-99999, 0))
    check(main.map_3d.cam_target.x >= -2.0 and main.map_3d.cam_target.x <= 62.0
        and main.map_3d.cam_target.z >= -2.0 and main.map_3d.cam_target.z <= 62.0,
        "Pan clamps to the map bounds")
    main.map_3d.end_pan()
    check(not main.map_3d.is_panning(), "Pan ends cleanly")
    main.map_3d.frame_map()
    await process_frame

    # E01.b 交互修改：按住左键拖动即平移；几乎没动的松手仍是点击（触摸板友好）。
    var drag_from: Vector2 = main.map_area.global_position + Vector2(300, 200)
    var target_before: Vector3 = main.map_3d.cam_target
    var wood_before_drag: int = main.town.wood
    await drag_on_map(drag_from, drag_from + Vector2(90, -60))
    check(main.map_3d.cam_target.x < target_before.x and main.map_3d.cam_target.z > target_before.z,
        "Left-drag pans the camera")
    check(main.town.wood == wood_before_drag and main.selected_cell == TownState.INVALID_CELL,
        "Drag release must not count as a click")
    main.map_3d.frame_map()
    main.map_3d.zoom_step(6.0)
    var tap_point: Vector2 = main.map_area.global_position \
        + main.map_3d.camera.unproject_position(Vector3(40.5, 0.0, 30.5))
    await drag_on_map(tap_point, tap_point + Vector2(4, 2))
    check(main.selected_cell == Vector2i(40, 30), "Tap with small jitter still selects")
    main.map_3d.frame_map()
    await process_frame

    # 3D GUI：点空地建农田，信息面板、双视图共享选择、屋顶拾取、重复点击不重复扣费。
    await click_build(Vector2i(40, 30), main.build_farm_button)
    check(main.town.wood == 90 and main.town.buildings.size() == 2, "3D click builds exactly once")
    check(main.selected_cell == Vector2i(40, 30), "Building auto-selects the new farm")
    check(main.selection_label.text.contains("农田") and main.selection_label.text.contains("(40, 30)"),
        "Selection panel shows name and cell")
    check(main.map_2d.selected_cell == Vector2i(40, 30), "2D view shares the selection")
    check(main.map_3d.selection_mark.visible, "3D selection mark visible")
    var roof_point: Vector2 = main.map_3d.camera.unproject_position(Vector3(40.73, 0.55, 30.68))
    check(main.map_3d.cell_at_position(roof_point) == Vector2i(40, 30), "Pick visible roof")
    var mark_point: Vector2 = main.map_3d.camera.unproject_position(Vector3(40.95, 0.03, 30.5))
    check(main.map_3d.cell_at_position(mark_point) == Vector2i(40, 30),
        "Selection mark must not break picking")
    await click_at(main.map_area.global_position + roof_point)
    check(main.town.wood == 90, "Duplicate 3D build must not charge")
    check(main.selected_cell == Vector2i(40, 30), "Roof click keeps selection on the farm")
    await click_map(Vector2i(13, 13))
    check(main.status_label.text.contains("水面"), "Water click explains itself")
    await click_map(Vector2i(16, 30))
    check(main.status_label.text.contains("资源区块"), "Resource click explains itself")
    check(main.selected_cell == Vector2i(40, 30), "Water and resource clicks keep selection")
    await click_at(main.map_area.global_position + Vector2(2, 2))
    check(main.town.wood == 90, "Background click must not charge")
    check(main.selected_cell == Vector2i(40, 30), "Background click keeps selection")

    await switch_view()
    check(not main.showing_3d and main.map_2d.visible and not main.world_image.visible, "Switch to 2D")
    check(main.world_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Hidden 3D stops rendering")
    check(main.town.wood == 90 and main.town.buildings.has(Vector2i(40, 30)), "Switch preserves state")
    check(main.map_2d.selected_cell == Vector2i(40, 30) and main.map_3d.selected_cell == Vector2i(40, 30),
        "View switch keeps the shared selection")
    await click_map(Vector2i(40, 30))
    check(main.selected_cell == Vector2i(40, 30), "2D click on farm selects it")
    await click_map(Vector2i(13, 13))
    check(main.selected_cell == Vector2i(40, 30), "2D water click keeps selection")
    await click_build(Vector2i(20, 51), main.build_farm_button)
    check(main.town.wood == 80 and main.town.buildings.size() == 3, "2D click builds exactly once")
    check(main.selected_cell == Vector2i(20, 51), "2D build auto-selects the new farm")
    await switch_view()
    check(main.showing_3d and main.map_3d.buildings_root.get_child_count() == 16,
        "3D reflects both farms and HQ")
    check(main.map_3d.selection_mark.position == Vector3(20.5, 0.0, 51.5), "3D mark follows selection")
    check(main.resources_label.text.contains("80"), "Shared HUD reflects resources")

    for i in range(8):
        await click_build(Vector2i(20 + 2 * i, 53), main.build_farm_button)
    check(main.town.wood == 0 and main.town.buildings.size() == 11, "Spend starting wood")
    check(main.selected_cell == Vector2i(34, 53), "Last built farm stays selected")
    await click_map(Vector2i(36, 53))
    check(main.build_farm_button.disabled and main.build_lumberyard_button.disabled,
        "Build buttons disabled without enough wood")
    await click_at(main.deselect_button.get_global_rect().get_center())
    await switch_view()
    await click_at(main.reset_button.get_global_rect().get_center())
    check(main.town.wood == 100 and main.town.buildings.size() == 1, "Reset keeps only the preset HQ")
    check(main.town.map_size == Vector2i(60, 60), "Reset restores the built-in map")
    check(main.selected_cell == TownState.INVALID_CELL, "Reset clears selection")
    check(main.selection_label.text.contains("未选中"), "Panel shows no selection after reset")
    var terrain_children: int = main.map_3d.terrain.get_child_count()
    check(terrain_children > 3600, "Terrain models cover the whole 60x60 map")
    check(not main.map_3d.selection_mark.visible, "3D mark hidden after reset")
    await click_build(Vector2i(22, 51), main.build_farm_button)
    check(main.selected_cell == Vector2i(22, 51) and main.town.wood == 90,
        "3D build selects the farm")
    await click_at(main.reset_button.get_global_rect().get_center())
    check(main.town.wood == 100 and main.town.buildings.size() == 1, "Reset in 3D")
    check(main.selected_cell == TownState.INVALID_CELL, "Reset in 3D clears selection")

    # P03：阮小二分配、调岗、撤回与重置；全程不允许一人占两个工位。
    check(main.selection_label.text.contains("空闲"), "Panel shows worker idle when nothing selected")
    check(main.assign_button.visible == false and main.withdraw_button.visible == false,
        "Worker buttons hidden when nothing is selected")
    await click_build(Vector2i(22, 51), main.build_farm_button)
    check(main.assign_button.visible and main.build_farm_button.visible == false,
        "Worker and build buttons switch by context")
    await click_at(main.assign_button.get_global_rect().get_center())
    check(main.town.worker_cell == Vector2i(22, 51), "Assign puts worker on the selected farm")
    check(main.selection_label.text.contains("阮小二"), "Panel shows worker after assign")
    check(main.assign_button.disabled, "Assign disabled when worker is already there")
    check(not main.withdraw_button.disabled, "Withdraw enabled while worker on selected farm")
    await click_at(main.assign_button.get_global_rect().get_center())
    check(main.town.worker_cell == Vector2i(22, 51), "Repeated assign keeps the single workplace")
    await click_build(Vector2i(24, 51), main.build_farm_button)
    check(main.town.buildings.size() == 3, "Second farm built for transfer test")
    await click_at(main.assign_button.get_global_rect().get_center())
    check(main.town.worker_cell == Vector2i(24, 51), "Assign to another farm moves the worker")
    var failed: String = main.town.assign_worker(Vector2i(26, 51))
    check(failed.contains("没有"), "Assign to a cell without building is rejected")
    check(main.town.worker_cell == Vector2i(24, 51), "Failed assign keeps the old job")
    await click_at(main.withdraw_button.get_global_rect().get_center())
    check(main.town.worker_cell == TownState.INVALID_CELL, "Withdraw frees the worker")
    await click_at(main.withdraw_button.get_global_rect().get_center())
    check(main.town.worker_cell == TownState.INVALID_CELL, "Repeated withdraw is harmless")
    await click_map(Vector2i(24, 51))
    await click_at(main.assign_button.get_global_rect().get_center())
    check(main.town.worker_cell == Vector2i(24, 51), "Worker reassigned before reset")
    await click_at(main.reset_button.get_global_rect().get_center())
    check(main.town.worker_cell == TownState.INVALID_CELL, "Reset returns worker to idle")
    check(main.selection_label.text.contains("空闲"), "Panel shows idle after reset")

    # P07：大本营不可建第二座、不需要工人；点击任意覆盖格都选中锚点；伐木场产木材。
    await click_map(town.hq_cell)
    check(main.selection_label.text.contains("大本营")
        and main.selection_label.text.contains("占地 2×2"),
        "HQ panel shows footprint")
    check(main.assign_button.disabled, "Assign disabled on HQ")
    check(main.town.assign_worker(town.hq_cell).contains("不需要工人"), "HQ refuses workers")
    var duplicate_hq: String = main.town.try_build(Vector2i(34, 50), &"hq")
    check(duplicate_hq.contains("只能有一座"), "Second HQ rejected by unique rule")
    await click_map(Vector2i(31, 31))
    check(main.selected_cell == Vector2i(30, 30)
        and main.selection_label.text.contains("大本营"),
        "Clicking a covered cell selects the HQ anchor")
    check(main.map_3d.selection_mark.position == Vector3(30.5, 0.0, 30.5),
        "Selection mark sits on the anchor cell")
    await click_map(Vector2i(34, 50))
    check(main.build_lumberyard_button.visible and not main.assign_button.visible,
        "Empty land shows build buttons")
    await click_build(Vector2i(34, 50), main.build_lumberyard_button)
    check(main.town.buildings.get(Vector2i(34, 50), &"") == &"lumberyard", "Lumberyard can be built")
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

    # E02：人口与民居——迁入、上限、耗粮与粮尽软失败（独立实例，避免帧时序干扰）。
    var pop_town := TownState.new()
    check(pop_town.population_cap() == 0 and pop_town.population == 0,
        "No housing keeps population at zero")
    check(pop_town.try_build(Vector2i(4, 4), &"house").contains("已")
        and pop_town.population_cap() == 5, "House provides housing capacity")
    pop_town.grain = 50
    pop_town.advance_time(25.0)
    check(pop_town.population == 5 and pop_town.grain == 45,
        "Population moves in one per five seconds and eats on the way")
    pop_town.advance_time(30.0)
    check(pop_town.population == 5, "Move-in stops at the cap")
    var fed_grain: int = pop_town.grain
    pop_town.advance_time(2.0)
    check(pop_town.grain == fed_grain - 1, "Five residents eat 0.5 grain per second")
    pop_town.grain = 0
    pop_town.advance_time(10.0)
    check(pop_town.population == 5, "Out of grain stops move-in but starves nobody")

    # 开局帮扶：前 10 名居民无条件迁入，只要求有空房（用户反馈的第一轮循环问题）。
    var founding := TownState.new()
    check(founding.try_build(Vector2i(4, 4), &"house").contains("已"), "House for founding test")
    founding.advance_time(25.0)
    check(founding.population == 5 and founding.grain == 0,
        "Founding residents move in without any grain")

    # E03：岗位与自动填岗——居民按类别优先序填充岗位，产出按已填岗位叠加。
    var job_town := TownState.new()
    check(job_town.try_build(Vector2i(4, 4), &"farm").contains("已")
        and job_town.try_build(Vector2i(7, 4), &"lumberyard").contains("已")
        and job_town.try_build(Vector2i(4, 6), &"house").contains("已"), "Job town prepared")
    job_town.grain = 100
    job_town.advance_time(25.0)
    check(job_town.population == 5, "Residents arrive for job test")
    var assignment: Dictionary = job_town.job_assignment()
    check(assignment.get(Vector2i(4, 4), 0) == 2 and assignment.get(Vector2i(7, 4), 0) == 2,
        "Farming fills first, then lumber")
    check(job_town.staffed_population() == 4, "Four residents employed, one idle")
    job_town.grain = 0
    var job_wood: int = job_town.wood
    job_town.advance_time(2.0)
    check(job_town.wood == job_wood + 6, "Fully staffed lumberyard yields three wood per second")

    # 阮小二占一个岗位位：他在时居民只能补另一岗；他撤走居民顶上（D21 兼容桥）。
    var ruan_town := TownState.new()
    ruan_town.try_build(Vector2i(4, 4), &"farm")
    ruan_town.try_build(Vector2i(7, 4), &"house")
    ruan_town.assign_worker(Vector2i(4, 4))
    ruan_town.grain = 20
    ruan_town.advance_time(5.0)
    check(ruan_town.population == 1, "One resident arrives for the Ruan test")
    check(ruan_town.building_jobs_filled(Vector2i(4, 4)) == 2,
        "Ruan and the resident share the two farm slots")
    var ruan_grain: int = ruan_town.grain
    ruan_town.advance_time(2.0)
    check(ruan_town.grain == ruan_grain + 6, "Ruan plus resident make the farm yield three per second")
    ruan_town.withdraw_worker()
    check(ruan_town.building_jobs_filled(Vector2i(4, 4)) == 1,
        "Resident keeps his slot but the empty slot stays open")
    ruan_grain = ruan_town.grain
    ruan_town.advance_time(2.0)
    check(ruan_town.grain == ruan_grain + 4, "Rate drops back to two per second")

    # P08：高地上建造——建筑基准抬升到地形高度，且可被拾取；高格选中高亮可见。
    await click_build(Vector2i(45, 10), main.build_farm_button)
    check(main.town.buildings.get(Vector2i(45, 10), &"") == &"farm", "Highland accepts farms (D18)")
    var elevated := false
    for piece in main.map_3d.buildings_root.get_children():
        if is_equal_approx(piece.position.x, 46.0) and is_equal_approx(piece.position.z, 11.0) \
                and is_equal_approx(piece.position.y, 0.555):
            elevated = true
    check(elevated, "Highland farm model sits on the raised terrain")
    var high_roof: Vector2 = main.map_3d.camera.unproject_position(Vector3(46.66, 0.95, 11.66))
    check(main.map_3d.cell_at_position(high_roof) == Vector2i(45, 10),
        "Highland building picking uses raised origin")
    await click_map(Vector2i(45, 10))
    check(main.map_3d.selection_mark.visible
        and is_equal_approx(main.map_3d.selection_mark.position.y, 0.5),
        "Selection mark sits on the highland surface")
    check(main.town.wood == 70, "Highland farm costs the same 10 wood")

    # E02 GUI：民居建造与人口 HUD。
    await click_map(Vector2i(36, 50))
    check(main.build_house_button.visible and not main.build_house_button.disabled,
        "House button shows on affordable empty land")
    await click_at(main.build_house_button.get_global_rect().get_center())
    check(main.town.buildings.get(Vector2i(36, 50), &"") == &"house", "House can be built")
    check(main.town.wood == 40, "House costs 30 wood")
    check(main.resources_label.text.contains("人口：0/5"), "HUD shows population and cap")

    # P04/P05：实时产粮与存档数值——用独立规则实例验证，避免运行帧时序影响断言。
    var saver := TownState.new()
    saver.try_build(Vector2i(4, 4), &"farm")
    saver.advance_time(0.5)
    var save_data: Dictionary = saver.to_save_data()
    check(save_data["version"] == 5 and save_data["map_size"] == [60, 60]
        and save_data["map_name"] == "测试城镇", "Save v4 records map size and name")
    var loader := TownState.new()
    loader.try_build(Vector2i(5, 5), &"farm")
    check(loader.apply_save_data(save_data) == "", "Valid save applies cleanly")
    check(loader.wood == saver.wood and loader.grain == saver.grain
        and loader.worker_cell == TownState.INVALID_CELL and loader.buildings.size() == 2
        and is_equal_approx(loader.farm_progress_ratio(Vector2i(4, 4)), 0.5),
        "Save round-trip restores resources, worker, farm and progress")
    check(loader.map_size == Vector2i(60, 60) and loader.map_name == "测试城镇"
        and loader.hq_cell == Vector2i(30, 30), "Save round-trip restores the map identity")
    check(loader.terrain_kind(Vector2i(16, 30)) == &"forest"
        and loader.terrain_kind(Vector2i(44, 21)) == &"stone"
        and loader.terrain_kind(Vector2i(48, 23)) == &"iron"
        and loader.terrain_kind(Vector2i(30, 26)) == &"grass",
        "Save round-trip restores resource and grass terrain")
    loader.advance_time(0.5)
    check(loader.grain == 1, "Continuing after load does not double-settle")

    # 占地扩张迁移：旧档 1×1 时代的相邻建筑，按 2×2 重算后后到的让位。
    var v5_overlap: Dictionary = save_data.duplicate(true)
    v5_overlap["buildings"].append({ "x": 5, "y": 5, "kind": "farm", "progress": 0.0 })
    var from_v5_overlap := TownState.new()
    check(from_v5_overlap.apply_save_data(v5_overlap) == "",
        "V5 save with 1x1-era overlap migrates")
    check(from_v5_overlap.buildings.size() == 2
        and not from_v5_overlap.buildings.has(Vector2i(5, 5)),
        "Expanded 2x2 footprints drop the later overlapping building")

    # 损坏存档逐项拒绝，且不破坏当前状态。
    var guard := TownState.new()
    guard.try_build(Vector2i(4, 4), &"farm")
    guard.assign_worker(Vector2i(4, 4))
    check(guard.apply_save_data("junk") != "", "Non-dictionary save rejected")
    check(guard.apply_save_data({"version": 0, "wood": 1, "grain": 1, "buildings": []}) != "",
        "Old version rejected")
    check(guard.apply_save_data({"version": 2, "wood": 50, "grain": 0,
        "worker_x": -1, "worker_y": -1,
        "buildings": [{"x": 0, "y": 0, "kind": "farm", "progress": 0.0}]}) != "",
        "Water-cell building rejected on the legacy map")
    check(guard.apply_save_data({"version": 2, "wood": 50, "grain": 0,
        "worker_x": 4, "worker_y": 4, "buildings": []}) != "",
        "Worker pointing at missing farm rejected")
    check(guard.apply_save_data({"version": 2, "wood": 50, "grain": 0,
        "worker_x": -1, "worker_y": -1,
        "buildings": [{"x": 4, "y": 4, "kind": "hq", "progress": 0.0},
            {"x": 5, "y": 4, "kind": "hq", "progress": 0.0}]}) != "",
        "Duplicate unique building rejected")
    var no_hq_data: Dictionary = save_data.duplicate(true)
    no_hq_data["buildings"] = no_hq_data["buildings"].filter(func(entry: Variant) -> bool:
        return str(entry["kind"]) != "hq")
    check(guard.apply_save_data(no_hq_data) != "", "Save without HQ rejected")
    var resource_build_data: Dictionary = save_data.duplicate(true)
    resource_build_data["buildings"] = [
        {"x": 30, "y": 30, "kind": "hq", "progress": 0.0},
        {"x": 16, "y": 30, "kind": "farm", "progress": 0.0},
    ]
    check(guard.apply_save_data(resource_build_data) != "", "Building on forest rejected")
    var bad_size_data: Dictionary = save_data.duplicate(true)
    bad_size_data["map_size"] = [0, 60]
    check(guard.apply_save_data(bad_size_data) != "", "Invalid map size rejected")
    var bad_terrain_data: Dictionary = save_data.duplicate(true)
    bad_terrain_data["terrain"] = bad_terrain_data["terrain"]
    bad_terrain_data["terrain"].append({"x": 59, "y": 59, "t": "X"})
    check(guard.apply_save_data(bad_terrain_data) != "", "Unknown terrain code rejected")
    check(guard.wood == 90 and guard.grain == 0 and guard.worker_cell == Vector2i(4, 4)
        and guard.buildings.size() == 2 and guard.map_size == Vector2i(60, 60),
        "Rejected saves leave current state untouched")

    # 旧档迁移：v1/v2 补旧 16×12 地形，v3 按原地形载入，重置回到新默认图。
    var v1_data := {"version": 1, "wood": 55, "grain": 3, "worker_x": 5, "worker_y": 5,
        "buildings": [{"x": 5, "y": 5, "kind": "farm", "progress": 0.25}]}
    var migrated := TownState.new()
    check(migrated.apply_save_data(v1_data) == "", "V1 save migrates cleanly")
    check(migrated.buildings.size() == 2 and migrated.buildings.get(Vector2i(8, 5), &"") == &"hq"
        and migrated.worker_cell == Vector2i(5, 5) and migrated.hq_cell == Vector2i(8, 5),
        "Migration plants legacy HQ and keeps worker")
    check(migrated.map_size == Vector2i(16, 12) and migrated.terrain_height(Vector2i(13, 2)) == 0.5
        and migrated.is_water(Vector2i(1, 1)), "V1 migration gains legacy terrain")
    check(migrated.population == 0, "V1 migration starts without population")
    var v2_data := {"version": 2, "wood": 30, "grain": 1, "worker_x": -1, "worker_y": -1,
        "buildings": [{"x": 6, "y": 6, "kind": "lumberyard", "progress": 0.1},
            {"x": 8, "y": 5, "kind": "hq", "progress": 0.0}]}
    var from_v2 := TownState.new()
    check(from_v2.apply_save_data(v2_data) == "", "V2 save migrates cleanly")
    check(from_v2.terrain_height(Vector2i(13, 2)) == 0.5 and from_v2.is_water(Vector2i(1, 1)),
        "V2 migration gains legacy terrain")
    # E01.b：大本营扩到 2×2 后，旧档里落在大本营占地内的建筑让位。
    var v2_overlap := {"version": 2, "wood": 30, "grain": 1, "worker_x": -1, "worker_y": -1,
        "buildings": [{"x": 9, "y": 6, "kind": "farm", "progress": 0.0},
            {"x": 8, "y": 5, "kind": "hq", "progress": 0.0}]}
    var from_v2_overlap := TownState.new()
    check(from_v2_overlap.apply_save_data(v2_overlap) == "",
        "V2 save with a building inside the HQ footprint migrates")
    check(from_v2_overlap.buildings.size() == 1 and from_v2_overlap.buildings.has(Vector2i(8, 5)),
        "Building under the 2x2 HQ is dropped")
    var v2_dropped_worker := {"version": 2, "wood": 30, "grain": 1, "worker_x": 9, "worker_y": 6,
        "buildings": [{"x": 9, "y": 6, "kind": "farm", "progress": 0.0},
            {"x": 8, "y": 5, "kind": "hq", "progress": 0.0}]}
    check(TownState.new().apply_save_data(v2_dropped_worker) != "",
        "Worker pointing at a dropped building is rejected")
    var v3_data := {"version": 3, "wood": 30, "grain": 1, "worker_x": -1, "worker_y": -1,
        "buildings": [{"x": 6, "y": 6, "kind": "lumberyard", "progress": 0.1},
            {"x": 8, "y": 5, "kind": "hq", "progress": 0.0}],
        "terrain": [{"x": 1, "y": 1, "t": "w"}, {"x": 13, "y": 2, "t": "h"}]}
    var from_v3 := TownState.new()
    check(from_v3.apply_save_data(v3_data) == "", "V3 save migrates cleanly")
    check(from_v3.map_size == Vector2i(16, 12) and from_v3.is_water(Vector2i(1, 1))
        and from_v3.terrain_height(Vector2i(13, 2)) == 0.5 and from_v3.hq_cell == Vector2i(8, 5),
        "V3 save keeps its own 16x12 terrain")
    from_v3.reset()
    check(from_v3.map_size == Vector2i(60, 60) and from_v3.hq_cell == Vector2i(30, 30),
        "Reset after legacy load returns to the test town")

    # P05/P04 UI：缺失存档提示；暂停后保存→重置→读取，数值必须精确恢复；损坏文件不破坏经营。
    DirAccess.remove_absolute("user://town_save.json")
    await click_at(main.load_button.get_global_rect().get_center())
    check(main.status_label.text.contains("还没有存档"), "Missing save reported")
    await click_build(Vector2i(28, 53), main.build_farm_button)
    check(main.town.buildings.get(Vector2i(28, 53), &"") == &"farm", "Farm built for save test")
    await click_at(main.assign_button.get_global_rect().get_center())
    await click_at(main.pause_button.get_global_rect().get_center())
    var saved_wood: int = main.town.wood
    var saved_grain: int = main.town.grain
    await click_at(main.save_button.get_global_rect().get_center())
    check(main.status_label.text.contains("已保存"), "Save reports success")
    await click_at(main.reset_button.get_global_rect().get_center())
    check(main.town.buildings.size() == 1 and main.town.wood == 100, "Reset clears before load")
    check(main.map_3d.terrain.get_child_count() == terrain_children,
        "Reset rebuilds identical terrain")
    await click_at(main.load_button.get_global_rect().get_center())
    check(main.town.wood == saved_wood, "Load wood %d vs saved %d" % [main.town.wood, saved_wood])
    check(main.town.grain == saved_grain, "Load grain %d vs saved %d" % [main.town.grain, saved_grain])
    check(main.town.worker_cell == Vector2i(28, 53), "Load worker %s" % main.town.worker_cell)
    check(main.town.buildings.size() == 5,
        "Load buildings 5 (HQ, lumberyard, highland farm, house and saved farm)")
    check(main.town.terrain_height(Vector2i(45, 10)) == 0.5, "Load restores highland terrain")
    check(main.town.map_size == Vector2i(60, 60), "Load keeps the 60x60 map")
    check(main.map_3d.terrain.get_child_count() == terrain_children,
        "Load rebuilds terrain for the saved map")
    check(main.status_label.text.contains("已读取"), "Load reports success")
    var broken := FileAccess.open("user://town_save.json", FileAccess.WRITE)
    broken.store_string("not-json{{{")
    broken.close()
    await click_at(main.load_button.get_global_rect().get_center())
    check(main.status_label.text.contains("损坏"), "Corrupt save reported")
    check(main.town.wood == saved_wood and main.town.worker_cell == Vector2i(28, 53),
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
        if not main.showing_3d:
            await switch_view()
        await click_build(Vector2i(34, 52), main.build_farm_button)
        await click_build(Vector2i(36, 52), main.build_farm_button)
        await click_build(Vector2i(38, 54), main.build_farm_button)
        await click_build(Vector2i(40, 50), main.build_lumberyard_button)
        await click_map(Vector2i(34, 52))
        await click_at(main.assign_button.get_global_rect().get_center())
        DirAccess.make_dir_recursive_absolute("res://build/verification")
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png("res://build/verification/dual-view-3d.png")
        await switch_view()
        check(not main.showing_3d, "Capture switches to 2D before the second shot")
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png("res://build/verification/dual-view-2d.png")

    if failures == 0:
        print("PASS: palette map, multi-cell HQ, camera pan/zoom, terrain rules, saves and migrations")
    else:
        print("FAIL: %d checks" % failures)
    main.queue_free()
    await process_frame
    quit(0 if failures == 0 else 1)
