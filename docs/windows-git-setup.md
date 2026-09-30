# Windows 本机 Git 与 SSH

仓库目标：[enotx/suiko](https://github.com/enotx/suiko)。Git 提交署名是 `zhidong.xia`，邮箱是 `enotxtone@gmail.com`；它们与用于认证的 GitHub 账号登录名是不同概念。

## 工具

本轮为用户安装了官方 Windows 命令行版 Git（MinGit），以及 GitHub CLI；均校验了官方发布的 SHA256，加入用户级 PATH。重新打开 PowerShell 后：

```powershell
git --version
gh --version
```

安装位置分别在 `$env:LOCALAPPDATA\Programs\MinGit` 和 `$env:LOCALAPPDATA\Programs\GitHubCLI`。GitHub CLI 尚未登录也不影响 SSH 推送；不需要为此启动浏览器授权流程。
当前会话 Linux 执行环境另有 Git，工作目录映射到 `/mnt/e/Lab/Suiko`。不要混淆 Windows 与 Linux 各自的 SSH 目录、agent 和凭据。

## 本机当前认证

用户已生成并登记 `$env:USERPROFILE\.ssh\id_ed25519`，认证账号为 enotx。仓库远端使用 `git@github.com:enotx/suiko.git`。
`.git/config` 已配置 Windows OpenSSH 和该密钥，严格校验 GitHub 主机公钥。当前本机不需要再次生成密钥。
Windows Git 可直接推送。若 agent 运行在 Linux/WSL，普通 Git 可做本地操作；此机器的网络操作应调用 Windows Git，避免把 Windows 的 core.sshCommand 当成 Linux 路径执行。

## 在新机器上手动生成并登记密钥

在 PowerShell 中运行（如果提示覆盖已有密钥，选 n 并先检查已有文件）：

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.ssh"
ssh-keygen -t ed25519 -C "enotxtone@gmail.com" -f "$env:USERPROFILE\.ssh\id_ed25519_suiko"
Get-Content "$env:USERPROFILE\.ssh\id_ed25519_suiko.pub" | Set-Clipboard
```

用户自行将公钥登记到有权限访问目标仓库的 GitHub 账号，类型选 Authentication Key。私钥不发到聊天、不放进项目。
是否设置密钥密码由用户决定；有密码时，通过本机 ssh-agent 解锁后再执行无人值守推送，不把密码写进脚本。

验证可使用 Windows OpenSSH（GitHub 的 SSH 用户固定是 git）：

```powershell
ssh -i "$env:USERPROFILE\.ssh\id_ed25519_suiko" -o IdentitiesOnly=yes -T git@github.com
```

首次连接核实 GitHub 公布的主机指纹后再接受；不要通过关闭主机校验来消除提示。成功通常显示 `Hi <账号>! You've successfully authenticated...`，但 GitHub 不提供 shell，退出码可能是 1。

远端设置为 SSH 后，使用本机可用的 SSH 身份进行 push。机器专属 `core.sshCommand` 配置放 `.git/config`，不写入可移植的运行代码。

本机已有密钥的检查命令为：

```powershell
ssh -i "$env:USERPROFILE\.ssh\id_ed25519" -o IdentitiesOnly=yes -T git@github.com
```

## 本地版本与远端

项目的工作流程见 [WORKFLOW](WORKFLOW.md)。`.git/config` 记录本地署名和远端，不会随提交上传；新机器需要自行配置身份和认证。
使用 PLAN 中的稳定标签和提交号恢复/比较版本，避免依赖聊天中的临时说明。
