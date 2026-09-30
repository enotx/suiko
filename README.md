# Suiko · 梁山起家

以《水浒传》为背景的城镇经营与战斗原型。当前已实现**同一座城镇的 2D/3D 切换与点击建造**。
城镇将采用实时经营，战斗单独使用回合；目前没有生产和战斗。

## 本机打开与练习

1. 用 Godot **4.7.2 Standard** 导入本目录的 `project.godot`。已有项目直接打开，不要重新新建。
2. 如果游戏正在运行，先按 F8 停止；编辑器提示外部文件变化时重新加载磁盘版本。
3. 双击 `scenes/main/main.tscn`，按 **F5** 运行整个项目。
4. 默认显示 3D 城镇。点击绿色地块建农田，再点击右侧“切换到 2D”。
5. 确认同一块农田和剩余木材仍在；在 2D 再建一块，切回 3D 检查。
6. “重置城镇”同时清空两个视图，恢复 100 木材。关闭游戏会丢失进度。

第一次学习请按 [双视图操作练习](docs/dual-view-guide.md) 操作。

## 项目上下文入口

新会话先读 [AGENTS.md](AGENTS.md)，再按其中顺序了解上下文。

| 文档 | 内容 |
| --- | --- |
| [PLAN.md](PLAN.md) | 可执行任务、依赖、状态与验收交接台账 |
| [docs/WORKFLOW.md](docs/WORKFLOW.md) | 开工回滚点、实现提交、用户验收后提交 |
| [docs/windows-git-setup.md](docs/windows-git-setup.md) | Windows Git 与 SSH 操作说明 |
| [VISION.md](VISION.md) | 背景、体验、核心玩法与长期方向 |
| [docs/STATUS.md](docs/STATUS.md) | 已实现、未实现、验证与下一步 |
| [docs/DECISIONS.md](docs/DECISIONS.md) | 已确认规则、旧提案与待定问题 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 共享状态、视图、输入与验证 |
| [docs/learning-roadmap.md](docs/learning-roadmap.md) | 分阶段学习路线 |

## 文件结构

```text
core/town_state.gd        唯一城镇规则与状态对象的类型
scenes/main/             主控制器、共用 UI、视图切换
scenes/town/             2D 绘制、3D 场景与拾取
assets/                  后续地形、建筑、头像、字体
data/scenarios/          后续剧本数据
tests/test_dual_view.gd   无插件的双视图集成检查
docs/                    项目上下文和学习说明
```

先读 TownState，再读 main.gd，看清状态如何交给两个视图。无需一开始读懂全部三维代码。
3D 使用简单方块、固定正交相机与灯光，无外部素材和插件依赖。中文暂时依赖系统字体回退，分发前需加入可嵌入字体。

## 验证

手动检查水面、重复建造、资源不足、切换保留状态、两个视图中的重置。
自动检查命令（将 `godot` 替换为本机可执行文件）：

```sh
godot --headless --path . --editor --import
godot --headless --path . --script res://tests/test_dual_view.gd
```

真实图形检查与截图：

```sh
godot --path . --script res://tests/test_dual_view.gd -- --capture
```

后者会短暂打开测试窗口并写入 `build/verification/`。不要在 `--headless` 模式加 `--capture`。
具体覆盖范围和限制见 STATUS。

`.godot/` 与 `build/` 不提交，生成的 `.gd.uid` 随脚本保留。
已初始化 main 分支，原型回滚基线为 `7eaf05f`。目标远端为 `enotx/suiko`；首次推送进度见 PLAN 的 P01。未配置 VPS 或导出平台。
