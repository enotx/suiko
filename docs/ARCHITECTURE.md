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
| core/town_state.gd | RefCounted；格子规则、木材、建筑、人物分工、建造和重置 |
| scenes/main/main.gd | 创建并持有唯一状态；分发点击、调用规则、刷新两种显示、切换视图 |
| scenes/town/map_view.gd | 只读共享状态，2D 绘制与坐标换算 |
| scenes/town/map_view_3d.gd | 只读共享状态，创建方块模型，射线选格 |
| scenes/town/town_3d.tscn | 三维节点、相机、灯光和环境 |
| tests/test_dual_view.gd | 加载完整场景、分发 GUI 输入，检查双视图与规则联系 |

点击 → MapArea.gui_input → 当前视图把坐标转为格子 → Main 调用 TownState.try_build → 刷新两个视图和共用 UI。
WorldImage 忽略鼠标事件，WorldViewport 禁止自动 GUI 输入，避免子视口重复接收同一点击。
视图切换只改变可见性和子视口渲染状态，不创建第二份城镇、不重置进度。

## 三维坐标与拾取

逻辑格子 (x, y) 对应三维 X/Z 地面；三维 Y 是高度。当前土地与水面顶面统一在 Y=0。
使用真正 3D 的 BoxMesh 与固定正交 Camera3D。地块、水面、农田均由同一份状态决定。
拾取：相机射线与模型的轴对齐包围盒求交，选择最近表面的格子。现在模型全是轴对齐方块，因此不用物理引擎同步即可准确拾取，包括屋顶。
未来引入旋转模型、复杂地形时应调整拾取方式，不要假定此方案无条件覆盖所有模型。
当前地图最多十座农田，每次状态变化简单重建农田显示；内容规模增长后再按需局部刷新。

## 规则边界

- core 不依赖输入、场景树或画面；允许 Godot 数据类型和 RefCounted/Resource。
- 两个视图只读状态；Main 调用规则。不要在任一视图里单独推进生产或战斗。
- 人物分工只记录在人物一侧（`worker_cell`），建筑不反向存储工人，保证一人一工位；多人物时再拆分定义与实例。
- 2D 用于清晰观察规则，3D 用于空间表现；最终是否把 2D 打磨为完整战略视图另行决定。
- 数值暂用具名常量；内容增长后再选 Resource 或 JSON 定义体系。
- 当前 try_build 返回中文提示，未来需要程序区分结果时可改结构化返回值。
- 当前建筑字典含 Vector2i 键；存档须显式编码，不能假定直接 JSON 往返。
- 不提前引入 Autoload、通用命令框架或事件总线。

## 后续时间模型

实时经营由 Main 或专门的模拟控制器单独推进；视图切换不能造成加速、停产或重置。
模拟层接收游戏经过时间，按累计时间或固定步长处理生产，避免每帧加资源；较长更新时间应处理多个完整周期。
暂停不推进模拟。倍速、后台和离线行为仍待设计。
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
