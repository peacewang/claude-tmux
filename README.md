# claude-tmux

> 在多个项目目录里各开一个 Claude Code 会话，集中地**列出、预览、跳转、终止**，并让每个会话使用各自独立的模型 provider。
>
> **出处**：本仓库 fork 自 [craftzdog/tmux-claude-session-manager](https://github.com/craftzdog/tmux-claude-session-manager)（上游作者 [@craftzdog](https://github.com/craftzdog) / Takuya Matsuyama），在其基础上做了本地改造：**provider 环境注入**、**状态栏常驻圆点**、**桌面通知**、**无边框全屏弹窗**。上游原生功能与问题请到原仓库反馈；以上 fork 改动的问题请在此反馈。

每个会话运行在独立的 tmux session 里（`claude-<目录哈希>`）。一旦你开了十几个会话，不逐一打开就分不清谁完成了、谁在等你。这个插件给你：

- 🔢 **中央选择器**（`prefix` + `u`）：列出所有正在运行的 Claude 会话
- 🟢 **实时状态**：`working` / `waiting` / `idle`，由 Claude Code hooks 驱动
- 👁️ **实时预览**：在选择器中直接预览每个会话的屏幕内容
- 🎯 **智能跳转**：选中后切到它启动时的窗口，在其上方以弹窗恢复会话
- 🚀 **启动器**（`prefix` + `a`）：为当前目录打开/附加一个 Claude 会话
- ❌ **快速关闭**（`ctrl-x`）：从选择器中关闭已完成的会话
- 🎨 **状态栏圆点**：tmux 底部状态栏常驻一排彩色圆点，瞥一眼就知道谁闲谁忙
- 🔔 **桌面通知**：会话完成 / 需要你时弹 toast（WSL → Windows / macOS → 原生通知中心）
- 🔌 **provider 注入**：每个会话用各自独立的模型 provider（通过 `sp` 切换）

状态、状态栏、通知功能都是**可选**的：不配置 hooks 也能列出、预览、跳转、关闭会话，只是状态显示 `?` 而非彩色。

---

## 前置条件

- **tmux ≥ 3.3**（`display-popup -c`、`-B` 无边框等需要 3.3+；Ubuntu 22.04 apt 冻结在 3.2a，需源码编译 3.6b；macOS 上 brew 可能因 Monterey 兼容性问题编译失败，同样可走源码编译）
- **[fzf](https://github.com/junegunn/fzf)** —— 选择器界面
- **[Claude Code](https://claude.com/claude-code)** CLI（`claude` 命令）
- bash / zsh；**Linux（含 WSL）、macOS** 均可用

## 安装

### 方式一：tpm

```tmux
set -g @plugin 'peacewang/claude-tmux'
```

按 `prefix` + <kbd>I</kbd> 安装。

### 方式二：手动 clone + run-shell（推荐，便于直接改 `scripts/`）

```sh
git clone https://github.com/peacewang/claude-tmux ~/code/peace/github/claude-tmux
```

在 `~/.config/tmux/tmux.conf`（或 `~/.tmux.conf`）里加载：

```tmux
run-shell '$HOME/code/peace/github/claude-tmux/claude_session_manager.tmux'
```

> 路径以你的 clone 位置为准。手动 clone 的好处：改 `scripts/` 源码立即生效，且不会被任何包管理器覆盖；代价是 `git pull` 上游时需手动解决冲突（改动集中在 `scripts/launch.sh`）。

---

## 配置

下面是一份**完整的个人实践配置**，把 prefix 改成 `Alt+1`、启动键改成 `a`、启动命令设为 `claude --dangerously-skip-permissions`（等价个人 alias `ccd`）、弹窗全屏无边框，并接入状态栏。

```tmux
# ~/.config/tmux/tmux.conf

# --- prefix 改为 Alt+1 ---
unbind-key C-b
unbind-key C-f
unbind-key C-Space
set -g prefix M-1
bind-key M-1 send-prefix

# --- 鼠标：滚轮滚动 scrollback、点击切 pane、拖拽调分隔线 ---
set -g mouse on

# --- 插件选项（必须在 run-shell 加载插件之前设置）---
set -g @claude_launch_key 'a'                                    # prefix+a 启动
set -g @claude_list_key   'u'                                    # prefix+u 选择器
set -g @claude_command 'claude --dangerously-skip-permissions'   # 等价 ccd
set -g @claude_popup_width '100%'                                # 浮层全屏
set -g @claude_popup_height '100%'

# --- 状态栏：常驻显示各 claude 会话状态 ---
set -g status-interval 5
set -g status-right-length 100
set -g status-right '#($HOME/code/peace/github/claude-tmux/scripts/statusbar.sh) %H:%M'

# --- 加载插件 ---
run-shell '$HOME/code/peace/github/claude-tmux/claude_session_manager.tmux'
```

> ⚠️ **关于 prefix 选 `Alt+1`**：
> - **WSL / Windows Terminal**：Windows Terminal 默认用 `Alt+1..9` 切换标签页，会在终端层拦截按键。若 `Alt+1` 没反应，去 Windows Terminal 设置 → 交互 → 关掉"Alt+数字切换标签页"，或改用其他 prefix。
> - **macOS / iTerm2**：iTerm2 默认把 Option+数字解释为特殊字符。只需在 Preferences → Profiles → Keys → Key Mappings 里添加一条：Keyboard Shortcut 按 `Option+1` → Action 选 "Send Escape Sequence" → Esc+ 填 `1`。**其他 Option 组合键不受影响**，特殊字符、单词跳转等照常用。
>
> ⚠️ **alias 不能写进 `@claude_command`**：插件走非交互 shell 启动，alias 不展开。`ccd` 必须写成展开后的真身 `claude --dangerously-skip-permissions`。

> ⚠️ **鼠标滚轮滚动的是历史命令？** 那是 `mouse` 没开。tmux 默认 `mouse off`，此时终端把滚轮翻译成 ↑/↓ 方向键发给 pane 内的 shell，zsh 把 ↑/↓ 解释为历史命令导航——看起来就像"滚轮滚的是输入框历史"。`set -g mouse on` 后滚轮被 tmux 拦截，转成 scrollback 滚动（进入 copy-mode），才是预期的"窗口滚动"。
>
> 开启 `mouse on` 的配套行为：滚轮滚动 scrollback、左键点击切 pane、拖拽分隔线调 pane 大小。代价是左键拖拽选文本会被 tmux 拦截进 copy-mode 选区——**想用终端原生的复制，按住 `Shift` 再拖拽**即可绕过 tmux（WSL / Windows Terminal、macOS / iTerm2、Linux 通用约定）。

> ⚠️ **macOS 源码安装后需额外配置**：Homebrew 在 macOS Monterey 上可能编译失败（bottle 不可用 + Ruby 兼容性问题），此时可手动源码编译 tmux 3.6b（编译命令见下文）。源码编译后需在 `tmux.conf` 顶部加一行 `set -g default-terminal "screen-256color"`——macOS 缺少 `tmux-256color` 的 terminfo 条目，不设的话退格键和字母输入会错乱。

`tmux source ~/.config/tmux/tmux.conf` 重载即生效。

---

## provider 注入：让每个会话用独立 provider

### 背景

`sp` 命令本质是 `source ~/.claude/switch-provider.sh`，向**当前交互 shell** export 一组 provider 环境变量：

- `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_BASE_URL`
- `ANTHROPIC_DEFAULT_HAIKU_MODEL` / `SONNET_MODEL` / `OPUS_MODEL`
- `CLAUDE_PROVIDER`

但插件启动器走 tmux `run-shell`，由 tmux server 执行，**无法继承**交互 shell 的环境变量。因此需要搭一座"桥"：让 `sp` 把 provider 镜像到当前 tmux 会话，启动器再从来源会话读取并内联注入。

### 第一步：`sp` 镜像 provider 到 tmux 会话

在 `~/.claude/switch-provider.sh` 末尾追加（纯加法 + `$TMUX` 守卫，非 tmux 终端里 `sp` 行为逐字节不变）：

```bash
# --- claude-tmux integration ---------------------------------
if [ -n "$TMUX" ]; then
  sess="$(tmux display-message -p '#{session_name}' 2>/dev/null)" || sess=""
  if [ -n "$sess" ]; then
    for v in ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL \
             ANTHROPIC_DEFAULT_HAIKU_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL \
             ANTHROPIC_DEFAULT_OPUS_MODEL CLAUDE_PROVIDER; do
      val="$(printenv "$v" 2>/dev/null)" || true
      if [ -n "$val" ]; then
        tmux set-environment -t "$sess" "$v" "$val"
      else
        tmux set-environment -t "$sess" -u "$v" 2>/dev/null || true
      fi
    done
  fi
fi
```

### 第二步：启动器自动注入（已内置，无需配置）

`scripts/launch.sh` 已实现：从来源窗口所属会话读取上述变量，用 `env VAR=val ... claude` **内联注入**到新 claude 进程（claude 启动那一刻就读环境，所以必须内联，不能"先建会话再 set-environment"）。

语义：

- **新建会话**：注入来源会话的 provider。
- **已存在的会话**：直接 attach，不重新注入 → **同目录多终端共享同一 provider**。要让某目录换 provider，需先 `/exit` 或 `tmux kill-session` 掉旧会话再重启。

---

## 状态配置（hooks）

在 `~/.claude/settings.json` 顶层 `hooks` 字段接入 `state.sh`，让选择器显示状态色、并在转移边触发桌面通知：

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "$HOME/code/peace/github/claude-tmux/scripts/state.sh working" }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt",
        "hooks": [
          { "type": "command", "command": "$HOME/code/peace/github/claude-tmux/scripts/state.sh waiting" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "AskUserQuestion",
        "hooks": [
          { "type": "command", "command": "$HOME/code/peace/github/claude-tmux/scripts/state.sh waiting" }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "$HOME/code/peace/github/claude-tmux/scripts/state.sh idle" }
        ]
      }
    ]
  }
}
```

> 路径替换成你的 clone 位置。Claude Code 动态重载 hooks，无需重启。已运行的会话在下一个事件触发时开始报告状态。

状态机：

| 事件 | 状态 | 含义 | 选择器色 / 状态栏 |
| --- | --- | --- | --- |
| `UserPromptSubmit` | 🔴 `working` | 正在忙 | 红 |
| `Notification`（权限）/ `PreToolUse`（AskUserQuestion） | 🟡 `waiting` | 等你操作 | 黄 |
| `Stop` | 🟢 `idle` | 一轮结束 | 绿 |
| （hook 未触发） | ⚪ `unknown` | 未知 | 灰 |

`state.sh` 用 `$TMUX_PANE` 守卫——**不在 tmux 里启动的 claude，hook 静默 no-op**，不会报 "no server" 之类错误。

---

## 桌面通知（可选）

状态栏只在 tmux 里可见；切去浏览器/IDE 就看不到了。`scripts/notify.sh` 是统一通知派发器，`state.sh` 会在转移边自动调用：

- **何时发**：只在 `waiting` 或 `working→idle` 这两条转移边上发（避免 claude 反复 Stop 刷屏）。
- **门禁**：`session_attached > 0`（你正盯着的会话 / popup 开着）时**不发**——不打扰你正在看的会话。
- **文案**：项目名 + 状态动作（`⏸ 需要你的输入` / `✓ 本轮已完成`），中文 emoji。WSL 走 PowerShell toast 时中文/emoji 经 UTF-8 XML 文件传递，不乱码；macOS 原生 UTF-8。
- **点击直达（WSL / macOS）**：通知带"恢复会话"动作，点击即在 host 终端以全屏 popup attach 到对应 claude 会话（对标 `prefix+a`），并自动把终端窗口提到最前。`prefix+d` 收起回 host，claude 后台继续。

派发器优先级（first that works wins）：

1. `powershell.exe` + `notify.ps1` —— WSL 原生 toast（PowerShell 5.1 自带，零依赖），支持点击直达
2. `wsl-notify-send.exe` —— WSL toast 兜底（无点击动作，非 UTF-8 中文 Windows 上 emoji/中文可能乱码）
3. `terminal-notifier` —— macOS 原生，`-execute` 点击恢复 popup
4. `osascript` —— macOS 原生通知中心，系统内置零依赖
5. `notify-send` —— Linux 路线，需要 D-Bus 通知守护
6. 终端铃声 `\a` —— 最终兜底

### 安装 WSL 点击直达（一次性）

```sh
bash scripts/install-wsl-notify.sh
```

做两件事：注册 `claudetmux://` URL 协议到 `HKCU`（无需管理员），协议处理器为 `wsl.exe … scripts/restore.sh`；点击 toast 的"恢复会话"即触发 `restore.sh`——它用 `$TMUX` 身份（host client 的 socket/server-pid/client-pid）在 host client 上 `display-popup` attach 目标会话（tmux 3.6b 在 WSL 下 `display-popup -c <其他 client>` 会立即关闭，故改用 TMUX 身份不带 `-c`），并后台调 `activate-wt.ps1` 把终端窗口提到最前。PowerShell 5.1 系统自带，不装任何东西。仓库搬家后重跑一次即可（注册的路径指向当前位置）。

> **WSL 已知限制**：
> - toast action 的协议激活只能直接启动 `wsl.exe`（隐藏启动器如 wscript/powershell 不会被 toast action 启动），所以点击时 `wsl.exe` 会闪一个控制台窗口约 0.5 秒——`restore.sh` 后台发完 `display-popup` 即退出，使该窗口只闪一下而非常驻。
> - `activate-wt.ps1` 把"最早启动的终端进程"（Windows Terminal 或 powershell）当作 host 提到最前。若你的 host 终端不是最早启动的，或用 cmd/其他终端，需调整该脚本。
> - 通知停留时间由 Windows 系统设置控制；toast XML 设了 `duration="long"`（约 25 秒），之后进通知中心仍可点击。
>
> 卸载：删注册表项 `HKCU\Software\Classes\claudetmux`。

### 安装 wsl-notify-send.exe（WSL 可选兜底）

PowerShell toast 不可用时退到 `wsl-notify-send.exe`（无点击动作）：

```sh
curl -fL -o /tmp/wns.zip \
  https://github.com/stuartleeks/wsl-notify-send/releases/download/v0.1.871612270/wsl-notify-send_windows_amd64.zip
mkdir -p ~/bin && unzip -o /tmp/wns.zip -d /tmp/wns-extracted
cp /tmp/wns-extracted/wsl-notify-send.exe ~/bin/
~/bin/wsl-notify-send.exe --appId claude-tmux "hello"   # 验证：Windows 弹 toast
```

> 网络直连失败加 `--proxy http://<你的代理地址>`。`notify.sh` 会先查 PATH 再查 `$HOME/bin/`（hook 环境 PATH 可能不含 `~/bin`）。不装则退化到 `notify-send` 或终端铃声。

---

## 使用方法

| 按键 | 操作 |
| --- | --- |
| `prefix` + `a` | 为当前目录启动（或重连）Claude 会话，以弹窗打开 |
| `prefix` + `u` | 打开会话选择器 |
| `prefix` + `d` | 收起浮层（detach），claude 后台继续跑 |
| 在 claude 里 `/exit` | claude 进程结束，会话消亡 |

> `prefix` = `Alt+1`：先按下 Alt+1，**松开**，再按下一个键。是两次独立按键，不是长按。
>
> **detach ≠ exit**：`Alt+1, d` 让 claude 后台继续跑；`/exit` 才真正结束。

选择器内：

| 按键 | 操作 |
| --- | --- |
| `enter` | 跳转到会话（切到其原始窗口，在弹窗中恢复） |
| `ctrl-x` | 关闭高亮的会话 |
| `↑` / `↓`、输入文字过滤 | fzf 导航 |

需要你关注的会话（`waiting` 黄、`idle` 绿）排在列表顶部。

---

## 工作原理

- **启动器**（`launch.sh`）：为当前目录创建/重连 `claude-<md5前8位>` 会话，从来源会话内联注入 provider 环境变量，关掉浮层内部状态栏（`status off`），以 `-B` 无边框弹窗 attach。
- **选择器**（`list.sh` + `picker.sh`）：列出匹配前缀的会话，读取状态和实时 `capture-pane` 预览，选中后把客户端切到会话的原始窗口，再在弹窗中恢复。picker 弹窗同样无边框。
- **状态钩子**（`state.sh`）：由 Claude Code hooks 触发，把状态写到会话 `@claude_state` / `@claude_state_at`，并在转移边按门禁规则派发桌面通知。
- **状态栏**（`statusbar.sh`）：遍历 `claude-*` 会话，输出彩色圆点 + 目录名，用 tmux 自家 `#[...]` 样式码（不是 ANSI）。
- 从会话弹窗**内部**按 `prefix` + `u` 会先分离该弹窗，再在外部宿主客户端上全尺寸重开选择器——不会出现弹窗套弹窗。

### 三层位置模型

```
① 物理终端（Windows Terminal / iTerm2 / Terminal.app）
   └─ ② tmux 会话（host）—— 普通 shell，能跑 sp、能按 prefix
        └─ ③ claude 弹窗（prefix+a 打开）—— 直接是 claude 界面
```

- `sp` 只能在 **②** 跑（它是 shell 函数），在 ③ 的 claude 界面里没法跑。
- popup 关闭 ≠ claude 退出：detach 收起浮层，claude 后台继续；`/exit` 才结束。

---

## 选项

在插件加载之前设置（显示的是默认值）：

```tmux
set -g @claude_launch_key     'y'        # prefix 按键：启动/打开会话
set -g @claude_list_key       'u'        # prefix 按键：打开选择器
set -g @claude_command        'claude'   # 新会话中运行的命令
set -g @claude_session_prefix 'claude-'  # tmux session 名称前缀
set -g @claude_popup_width     '90%'     # 弹窗宽度
set -g @claude_popup_height    '90%'     # 弹窗高度
```

> 本实践的 `100%` 全屏 + 无边框是**代码内置**的（`launch.sh` / `list.sh` 硬编码 `-B` 和 `status off`），不受上面两个 popup 选项的默认值影响——但把宽高设成 `100%` 才能真正盖住 host 状态栏。

---

## macOS 特别说明

### 安装 tmux

Homebrew 在新版 macOS 上直接可用，但在 **macOS Monterey 及更早版本**上可能失败（bottle 不可用，Ruby 兼容性问题）。此时可源码编译：

```sh
# 依赖库确保已装（brew install libevent ncurses 即可）
cd /tmp
curl -sL https://github.com/tmux/tmux/releases/download/3.6b/tmux-3.6b.tar.gz -o tmux-3.6b.tar.gz
rm -rf tmux-3.6b && tar xzf tmux-3.6b.tar.gz && cd tmux-3.6b
CPPFLAGS="-I/usr/local/opt/ncurses/include -I/usr/local/include" \
  LDFLAGS="-L/usr/local/opt/ncurses/lib -L/usr/local/lib" \
  ./configure --prefix=/usr/local --disable-utf8proc
make -j4 && sudo make install
tmux -V   # tmux 3.6b
```

> `ncurses` 在 brew 下是 keg-only，需显式指定 `CPPFLAGS`/`LDFLAGS` 路径。`--disable-utf8proc` 是因为 macOS 上 utf8proc 非必须（tmux 自带 UTF-8 处理）。

### terminfo 修复（关键）

源码编译后缺少 `tmux-256color` 的 terminfo 条目，进 tmux 后退格键和字母输入会错乱。在 `tmux.conf` 顶部加一行：

```tmux
set -g default-terminal "screen-256color"
```

`screen-256color` 是 macOS 系统自带的 terminfo，功能与 `tmux-256color` 几乎相同。

### prefix 键设置

macOS 终端（iTerm2 / Terminal.app）默认不把 Option 当作 Meta 键。**无需全局改动 Option 键**，只需为 `Option+1` 这一个组合键添加映射：

**iTerm2**：Preferences → Profiles → Keys → Key Mappings → `+`

| 字段 | 值 |
|------|-----|
| Keyboard Shortcut | 按 `Option+1` |
| Action | Send Escape Sequence |
| Esc+ | `1` |

其他 Option 组合键（特殊字符 `é`、单词跳转 `Option+←`/`→` 等）不受影响。

### 桌面通知

macOS 原生支持：`notify.sh` 内置 `osascript display notification` 分支，零额外依赖。且 macOS 是原生 UTF-8，通知文案可以正常使用中文（不受 WSL 的 ASCII 限制）。

### 验证 provider 注入

macOS 上没有 `/proc` 文件系统，改用 `ps` 查看 claude 进程的环境：

```sh
ps aux | grep -i claude | grep -v grep
# 查看某进程的环境变量：
ps eww <pid> | tr ' ' '\n' | grep ANTHROPIC
```

### 跨设备同步

本仓库插件脚本通过 git 同步；个人 dotfile（`tmux.conf`、`settings.json`、`switch-provider.sh`）建议走 [EnvSync](https://github.com/peacetool/EnvSync) 按环境隔离——macOS 和 WSL 各自维护独立的 `tmux.conf` / `settings.json`，`switch-provider.sh` 放 `common/` 跨环境共享。详见项目 Wiki。

---

## 许可证

[MIT](LICENSE) © Takuya Matsuyama（上游）；fork 改动同样以 MIT 发布。
