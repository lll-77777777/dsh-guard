# dsh-guard — DeepSeek Harness 启动守卫

DSH 双击启动时崩（`Desktop renderer exited: crashed`）或卡在 `desktop welcome: Web authentication failed`，
大部分是两件事攒出来的：

1. **GPU 着色器缓存**在上一轮崩溃里被写坏/被残留进程锁住 → 渲染进程一起来就崩。
2. **`dsh-auth-*` cookie 越堆越多**（每次启动换随机端口、各留一枚、有效期 30 天、从不清理），
   积累到几十枚后 Cookie 请求头超长，host 直接回 **431**，应用侧报成 "Web authentication failed"。

守卫在启动前把这两样清掉，启动失败时自动加重清理并重试。

## 文件

| 文件 | 作用 |
| --- | --- |
| `dsh-guard.ps1` | 主逻辑。`-DryRun` 只看不做。 |
| `dsh-guard.vbs` | 无窗口启动器（快捷方式指向它）。 |
| `clean-auth-cookies.mjs` | 用 bundled node 的 `node:sqlite` 删 `dsh-auth-%` cookie。 |
| `install-guard.ps1` / `install-guard.vbs` | 一次性安装：把开始菜单 + 启动文件夹的 `DeepSeek Harness.lnk` 改指向守卫。 |
| `launcher/` | 已改好的快捷方式副本（安装脚本跑不了时手动拖过去用）。 |
| `backup/` | 改动前的原始快捷方式。 |
| `guard.log` | 每次启动干了什么。 |

## 流程

1. 已有一个带窗口的 DSH 在跑 → 让它聚焦，退出（不杀）。
2. 杀掉没有窗口的残留进程（崩溃留下的）。
3. 清 `GPUCache / ShaderCache / GrShaderCache / DawnGraphiteCache / DawnWebGPUCache / GPUPersistentCache`。
4. 删 `Network/Cookies` 里的 `dsh-auth-%`。
5. 启动 DSH，等窗口最多 90s。
6. 没等到 → 第 2 次多清 Code Cache 再试 → 第 3 次进 dsh-undo 安全模式再试 → 仍失败则退出（启动器会兜底裸启动一次）。

## 安装（一次性）

双击 `install-guard.vbs`，看到 `OK` 即完成。此后开始菜单 / 开机自启都先走守卫。

本机已经先把 `Startup\dsh-guard-launcher.vbs` 放好了（开机自启走守卫）；开始菜单那条因为
DSH 会话的文件沙箱写不了 AppData，需要双击一次上面的安装脚本。

## 卸载 / 回滚

把 `backup\` 里两个 `.lnk` 复制回：

- `%APPDATA%\Microsoft\Windows\Start Menu\Programs\DeepSeek Harness.lnk`
- `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\DeepSeek Harness.lnk`

## 排错

`guard.log` 里每次启动一行 `=== guard start ===`，后面跟着判定与动作。窗口没起来时先看这里，
再看 `%APPDATA%\@deepseek-ai\dsh-desktop\logs\crash-*.log`。
