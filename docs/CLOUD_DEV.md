# 云端 Linux 调试与部署环境

更新日期：2026-10-04。本机是云端 Ubuntu 24.04（无显示器），代码、测试、部署都在这台机器完成；用户通过 SSH/GitHub 和浏览器参与。

## 组件与路径

| 内容 | 位置 |
| --- | --- |
| Godot 4.7.2 可执行文件 | `~/tools/godot` |
| 导出模板 | `~/.local/share/godot/export_templates/4.7.2.stable/` |
| Web 导出产物（不提交） | `build/web/` |
| 云端虚拟显示脚本 | `scripts/cloud-dev.sh` |
| 静态伺服 systemd 服务 | `/etc/systemd/system/suiko-web.service`，端口 `172.17.0.1:8090` |
| noVNC 端口 | `172.17.0.1:6080`（websockify），VNC 只听本机 5900 |
| 截图输出（不提交） | `build/verification/` |

## 三层验证

1. 无头回归：`~/tools/godot --headless --path . --script res://tests/test_dual_view.gd`
2. 真实渲染截图：`DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 ~/tools/godot --path . --resolution 1280x800 --script res://tests/test_dual_view.gd -- --capture`（先 `scripts/cloud-dev.sh game` 或单独启动 Xvfb；llvmpipe 软渲染跑 Compatibility 渲染器）
3. 浏览器远程桌面 / 试玩：
   - `scripts/cloud-dev.sh game` → Xvfb + 游戏 + noVNC；`editor` 换成编辑器（内存紧，慎用）；`stop` 全停；`status` 查看。
   - noVNC 直连 `http://172.17.0.1:6080/vnc.html?autoconnect=true`（仅内网/容器可达），经 NPM 反代后用域名访问。
   - Web 导出：`mkdir -p build/web && ~/tools/godot --headless --path . --export-release "Web" build/web/index.html`；`suiko-web` 服务自动伺服最新导出。

## NPM（nginx proxy manager）配置指引

前提：在 Cloudflare 把 `suiko.enotx.com`（可选 `dev-suiko.enotx.com`）的 A 记录指向本机公网 IP。

1. 登录 NPM 管理界面（本机 9200 端口映射）。
2. Proxy Host → Add：
   - Domain：`suiko.enotx.com`；Forward：`http` → `172.17.0.1`，端口 `8090`；打开 **Websockets Support**（非线程版不需要，但打开无妨）。
   - SSL：申请 Let's Encrypt 证书并勾选 Force HTTPS。Godot Web 的 `user://` 存档依赖 HTTPS 下的 IndexedDB。
   - Advanced（可选，线程版必须，非线程版加了更稳）：
     ```nginx
     add_header Cross-Origin-Opener-Policy same-origin;
     add_header Cross-Origin-Embedder-Policy require-corp;
     ```
3. 远程桌面：再加一条 Proxy Host（如 `dev-suiko.enotx.com`）→ `http://172.17.0.1:6080`，打开 Websockets Support。
   **必须**在 Access List 里建一个 basic auth 列表并挂到这条 host 上：noVNC 等于桌面控制权，不能裸露公网。
4. 配好后浏览器访问 `https://suiko.enotx.com` 试玩、`https://dev-suiko.enotx.com/vnc.html` 操作云端桌面。

## 已知限制

- 内存 3.6G：同时跑编辑器 + 多个容器服务会紧张；云端编辑器只在需要时启动。
- llvmpipe 是 CPU 渲染，帧率不代表真机性能。
- `python3 -m http.server` 够用于原型伺服；P22 发布时再考虑更完整的方案。
- 导出模板约 1.4G 存在用户目录；升级 Godot 版本时同步换模板。
