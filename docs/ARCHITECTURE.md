# 架构与验证

## 当前节点与职责

```text
Main (Node, main.gd；持有唯一 TownState)
├── MapArea (Control；统一接收地图点击)
│   ├── Map2D (Node2D；绘制平面网格)
│   ├── WorldViewport (SubViewport；独立 3D 世界)
│   │   └── Town3D (town_3d.tscn 实例)
│   │       ├── Terrain / Farms (运行时创建模型)
│   │       ├── Camera3D (固定正交相机)
│   │       ├── Sun (DirectionalLight3D)
│   │       └── WorldEnvironment
│   └── WorldImage (TextureRect；显示三维视口画面)
└── UI (CanvasLayer；资源、提示、切换与重置按钮)
```

| 文件 | 职责 |
| --- | --- |
| core/town_state.gd | RefCounted；地图尺寸与地形、格子规则、资源、建筑运行实例、人物分工、生产、建造、布局解析和重置 |
| core/building_def.gd | BuildingDef Resource：建筑配表条目（id/名称/造价/产出/速率/可分配/唯一/占地 footprint） |
| defs/*.tres | 建筑配表：farm、lumberyard、hq；TownState.BUILDING_DEFS 登记，`validate_defs()` 启动自检 |
| defs/maps/*.png | 调色板地图布局（D26）：1 像素 = 1 格，颜色 = 地形，见下文"地图布局"；可选同名 .json 只写 `{"name": ...}` |
| scenes/main/main.gd | 创建并持有唯一状态；分发点击与相机输入、调用规则、刷新两种显示、切换视图、暂停与存档 IO |
| scenes/town/map_view.gd | 只读共享状态；整图等比缩放居中绘制，`cell_center`/`cell_at_position` 互转 |
| scenes/town/map_view_3d.gd | 只读共享状态；按 town.map_size 建方块模型（网格/材质缓存），射线选格，正交相机平移/缩放 |
| scenes/town/town_3d.tscn | 三维节点、相机、灯光和环境（相机参数运行时按地图尺寸覆盖） |
| tests/test_dual_view.gd | 加载完整场景、分发 GUI 输入，检查双视图、布局、相机与规则联系 |

点击 → MapArea.gui_input → 当前视图把坐标转为格子 → Main 调用 TownState 规则 → 刷新两个视图和共用 UI。
3D 视图下滚轮缩放；左键按住拖动即平移（按下先记为待定点击，位移超过 8px 转入平移，松手未超阈值视为一次点击），右键/中键拖动同样平移，全部由 Main 转发给 map_3d；点击在左键松开时结算，选中/建造不受拖动影响。
WorldImage 忽略鼠标事件，WorldViewport 禁止自动 GUI 输入，避免子视口重复接收同一点击。
视图切换只改变可见性和子视口渲染状态，不创建第二份城镇、不重置进度。

## 地图布局（D26）

城镇布局是手工绘制的调色板图片：`defs/maps/*.png`，1 像素 = 1 格，颜色 = 地形。
调色板定义在 `TownState.MAP_PALETTE`（平地/草地/高地/水面/林地/石料/铁砂 + 品红大本营标记）；
作画必须用无抗锯齿铅笔，加载时逐像素精确比对（容差 ±2/8bit），非法颜色报出格子坐标。
大本营标记格按平地处理并预置大本营；可选同名 `.json` 提供 `name`。
`parse_layout` 只解析校验不碰状态；`load_layout_texture`/`apply_layout` 才替换地图，
重置（`reset`）恢复内置 `test_town.png`（60×60）。存档 v4 记录 `map_size`、`map_name` 与逐格地形短码。

## 三维坐标与拾取

逻辑格子 (x, y) 对应三维 X/Z 地面；三维 Y 是高度。地块与建筑顶面高度来自 `terrain_height`（高格 +0.5）。
使用真正 3D 的 BoxMesh 与正交 Camera3D。相机距离随地图对角线拉远，否则 60×60 地图的近角会落到相机平面后被裁掉；
平移/缩放只改 `cam_target` 与 `zoom_size` 并夹在地图范围内，`frame_map()` 一键全景。
拾取：相机射线与模型的轴对齐包围盒求交，选择最近表面的格子。模型全是轴对齐方块，因此不用物理引擎同步即可准确拾取，包括屋顶与资源区块小模型。
未来引入旋转模型、复杂地形时应调整拾取方式，不要假定此方案无条件覆盖所有模型。
地形与建筑模型在地图变化时整图重建（`rebuild_all`），建筑变化只重建建筑层；3600 格共享少量 Mesh/Material 缓存。

## 规则边界

- core 不依赖输入、场景树或画面；允许 Godot 数据类型和 RefCounted/Resource。
- 两个视图只读状态；Main 调用规则。不要在任一视图里单独推进生产或战斗。
- 人物分工只记录在人物一侧（`worker_cell`），建筑不反向存储工人，保证一人一工位；多人物时再拆分定义与实例。
- 建筑种类经 `defs/*.tres` 配表（D17）；大本营为预置唯一建筑（位置在 `town_state.hq_cell`，来自布局图标记，reset 保留、不需工人、不可建第二座）；3D 大本营边缘压在约 0.15 格内、主体不越过 0.6，避免斜俯视相机遮挡相邻格心的拾取射线。
- 多格占地（E01.b/D28）：`BuildingDef.footprint` 描述占地，建筑从锚点格向 +X/+Y 扩展；农田/伐木场/民居/大本营统一 2×2 起步。`building_origin_at` 把任意覆盖格映射回锚点（点击/建造/选中一律以锚点为准）；建造与存档校验都按整块占地逐格判定；旧档按旧占地记录，读档时按当前占地重算并让位冲突建筑。
- 大本营扩位迁移：旧档按 1×1 记录，读档时若旧建筑落在大本营当前占地内则让位（幂等，与 v1 迁移同语义）；工位指向被让位建筑的存档整体拒载。
- 地形种类与可建性由 `TownState` 决定：水面禁建照旧；资源区块（林地/石料/铁砂）在采集玩法接入前暂禁建造（临时规则，用户验收可改）；高格按 D18 暂可建一切建筑。
- 2D 用于清晰观察规则，3D 用于空间表现；最终是否把 2D 打磨为完整战略视图另行决定。
- 数值暂用具名常量；内容增长后再选 Resource 或 JSON 定义体系。
- 当前 try_build 返回中文提示，未来需要程序区分结果时可改结构化返回值。
- 当前建筑字典含 Vector2i 键；存档须显式编码，不能假定直接 JSON 往返。已实现：`to_save_data`/`apply_save_data` 在规则层编码与校验（版本+逐项），文件 IO 在 Main（`user://town_save.json`）。
- 不提前引入 Autoload、通用命令框架或事件总线。

## 后续时间模型

实时经营由 Main 的 `_process` 单独推进：每帧把经过时间交给 `TownState.advance_time`（唯一模拟入口），视图切换与重绘不推进时间。暂停是 Main 的交互标志，暂停期间不向规则层传时间（无离线补算，D14）。
生产按建筑累计进度（`farm_progress`），满一个周期产 1 单位；产出速率 = 已填岗位 × `job_rate`（D30：无岗位填充不生产；base_rate 字段保留、当前配表为 0），岗位分配由 `job_assignment()` 派生（阮小二占一岗、居民按类别优先序自动填充，优先序与每类居民上限可由玩家调整（上限 -1=不限、0=禁止、正数=居民数，只约束居民，右栏 SpinBox 直接输入）），不落存档、状态变化即生效。`advance_time` 以迁入事件为切片边界，段内速率恒定，长时间步与逐帧推进一致。速率等数值暂用具名常量（D13/E02/E03 占位）。
人口与施工（E02/E04）在同一模拟入口内按事件切片推进：切片边界是下一次迁入或工地完工时刻，保证长时间步与逐帧推进结果一致；前 10 名居民无条件迁入（D29），此后需要余粮；每人每秒耗粮与迁入间隔、建筑工期与升级费用是临时数值，粮尽软失败为停止迁入、人口不减少。民居容量来自 `BuildingDef.capacity_at(level)`，人口上限是全部建筑容量之和；建造/升级经 `construction_queue` 排队，`BUILDERS` 限制并行，工地占格但不产出、不提供容量岗位。
战斗回合与指令/结算阶段独立建模，内部 tick 不是经营用的“旬”。战斗与生产时间如何衔接仍待确认。

## 验证

使用本机 Godot 可执行文件，示例 godot 命令名需按机器替换：

```sh
godot --headless --path . --editor --import
godot --headless --path . --script res://tests/test_dual_view.gd
godot --path . --script res://tests/test_dual_view.gd -- --capture
```

最后一条需要真实图形环境，截图写到忽略的 build/verification/；不要与 --headless 合用。
集成检查覆盖共享状态、全部格子拾取、真实 GUI 点击、建造拒绝、切换和重置。截图需要实际查看，不能仅凭无头测试宣称画面正确。
当前没有 GUT 等外部测试框架；后续为新规则增加必要的行为验证即可。

## 资源与跨平台

.godot/、build/ 不提交，.gd.uid 随脚本保留。路径与大小写一致，不在运行代码写入本机可执行文件路径。
中文已嵌入 Noto Sans SC（OFL，`assets/fonts/`，经 `gui/theme/custom_font` 全局生效），Web 导出可直接显示；新增界面文本无需额外配置。正式素材记录来源和许可。
Compatibility 和 GDScript 是多端起点，不代表已完成跨平台验证。
