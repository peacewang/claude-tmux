# tmux 与 claude-tmux 实践指南

> 本文记录在 WSL（Ubuntu 22.04）环境下，搭建一套"多 Claude Code 会话统一管理 + 按目录/按终端切换模型 provider"的完整实践。
> 
> 目标：在多个业务目录里各开一个 Claude Code 会话，集中地**列出、预览、跳转、终止**，并让每个会话使用各自独立的模型 provider（通过 `sp` 命令切换）。

---

## 一、环境安装

### 1.1 前置条件

- WSL（Ubuntu 22.04 jammy，x86_64）
- Claude Code CLI（`claude` 命令）
- bash / zsh

### 1.2 安装 tmux（源码编译最新版）

Ubuntu 22.04 的 apt 仓库将 tmux 冻结在 3.2a，而本插件选择器的"弹窗套弹窗"功能需要 tmux **3.3+** 的 `display-popup -c` 参数。因此采用源码编译，装到 `/usr/local`（PATH 优先级高于 `/usr/bin`，自动覆盖旧版，旧版保留作回退）。

**第一步：安装编译依赖（需要 sudo，在自有终端执行）**

```sh
sudo apt update
sudo apt install -y build-essential libevent-dev libncurses-dev bison flex
```

- `libevent-dev` / `libncurses-dev`：tmux 运行时库
- `bison`（提供 `yacc`）/ `flex`：3.6b 的发行包需要 yacc/flex 生成语法解析器
- `build-essential`：gcc/make 等

**第二步：下载、编译、安装**

```sh
cd /tmp
curl -sL https://github.com/tmux/tmux/releases/download/3.6b/tmux-3.6b.tar.gz -o tmux-3.6b.tar.gz
rm -rf tmux-3.6b && tar xzf tmux-3.6b.tar.gz
cd tmux-3.6b
./configure --prefix=/usr/local
make
sudo make install
hash -r
```

**第三步：验证**

```sh
which -a tmux
# 期望输出（顺序很重要，/usr/local/bin 在前）：
#   /usr/local/bin/tmux
#   /usr/bin/tmux        <- 旧版 3.2a，作回退
tmux -V
# 期望输出：tmux 3.6b
```

> **要点**：`--prefix=/usr/local` 使二进制落到 `/usr/local/bin/tmux`，FHS 标准的"本地编译软件"专属位置，apt 永不触碰，因此不会被系统更新覆盖，也不与 apt 包冲突。`hash -r` 用于清掉 shell 缓存的旧命令路径。

### 1.3 安装 fzf（选择器依赖）

```sh
sudo apt install -y fzf
fzf --version
```

> fzf 是选择器（`prefix+u`）的 UI 依赖。不装也能用启动器（`prefix+a`）和 provider 注入，只是选择器会提示 "fzf is required"。

### 1.4 接入 claude-tmux 插件

采用**手动 clone + `run-shell`** 方式（而非 tpm），这样直接改 `scripts/` 下的源码即可生效，且不会被任何包管理器更新覆盖。

**第一步：clone 插件仓库**

```sh
git clone https://github.com/peacewang/claude-tmux \
  ~/code/peace/github/claude-tmux
```

> 实际路径以你的为准。本文后续以 `/home/peace/code/peace/github/claude-tmux` 为例。

**第二步：创建 tmux 配置**

新建 `~/.config/tmux/tmux.conf`：

```tmux
# ~/.config/tmux/tmux.conf
#
# prefix = Alt+1
# 插件键: prefix+a = 启动 claude,  prefix+u = 选择器
# 启动命令等价于个人 alias `ccd` (claude --dangerously-skip-permissions)

# --- prefix 改为 Alt+1 ---
unbind-key C-b
unbind-key C-f
unbind-key C-Space
set -g prefix M-1
bind-key M-1 send-prefix

# --- 插件选项（必须在 run-shell 加载插件之前设置）---
set -g @claude_launch_key 'a'                                    # prefix+a 启动
set -g @claude_list_key   'u'                                    # prefix+u 选择器
set -g @claude_command 'claude --dangerously-skip-permissions'   # 等价 ccd

# --- 加载插件 ---
run-shell '/home/peace/code/peace/github/claude-tmux/claude_session_manager.tmux'
```

> **关于 prefix 选择**：默认是 `Ctrl-b`。本文实践里先后试过 `Ctrl-f`、`Ctrl-Space`，最终定为 `Alt+1`（tmux 记作 `M-1`）。换 prefix 只需改 `set -g prefix <键>` 和对应的 `bind-key <键> send-prefix`，并把旧的解绑（`unbind-key`）。
>
> ⚠️ **`Alt+数字` 的潜在冲突**：Windows Terminal 默认用 `Alt+1..9` 切换标签页，会在终端层把按键拦截掉，传不到 tmux。若发现 `Alt+1` 没反应，去 Windows Terminal 设置 → 交互 → 关掉"Alt+数字切换标签页"，或改用其他 prefix。
>
> **关于启动键 `a` 与启动命令**：插件默认 `prefix+y` 启动、命令为裸 `claude`。这里把启动键改成 `a`，并把 `@claude_command` 设为 `claude --dangerously-skip-permissions`（等价于个人 alias `ccd`），让 `prefix+a` 起的 claude 自动跳过权限。注意：**alias 名（`ccd`）不能直接写进 `@claude_command`**——插件走非交互 shell 启动，alias 不展开，必须写展开后的真身命令。

**第三步：进入 tmux 自动加载**

直接运行 `tmux` 即会读取上述配置；若已在 tmux 内，可用 `prefix + r`（如已绑定）或手动 `tmux source ~/.config/tmux/tmux.conf` 重新加载。

---

## 二、改造点（让每个会话使用独立 provider）

### 2.1 背景：为什么需要改造

`sp` 命令（`~/.zshrc` 中的函数）本质是 `source ~/.claude/switch-provider.sh`，向**当前交互 shell** 里 `export` 一组 provider 环境变量：

- `ANTHROPIC_AUTH_TOKEN`
- `ANTHROPIC_BASE_URL`
- `ANTHROPIC_DEFAULT_HAIKU_MODEL` / `SONNET_MODEL` / `OPUS_MODEL`
- `CLAUDE_PROVIDER`

但插件的启动器走的是 tmux `run-shell`，由 **tmux server** 执行（而非交互 shell 的子进程），**无法继承**你交互式设好的环境变量。结果：插件启动的每个 claude 都会用默认 provider，`sp` 选择被无视。

因此需要搭一座"桥"：让 `sp` 把 provider 镜像到当前 tmux 会话，再让启动器从来源会话读取并注入到新建的 claude 进程。

### 2.2 改造点 A：`sp` 命令（`~/.claude/switch-provider.sh`）

**原则**：纯加法 + `$TMUX` 守卫，**绝不改动原有 export 逻辑**。非 tmux 终端里 `sp` 行为逐字节不变。

在 `switch-provider.sh` 末尾追加：

```bash
# --- claude-tmux integration ---------------------------------
# Mirror the chosen provider onto the current tmux session so the launcher can
# inherit it (see scripts/launch.sh). Strictly additive: a no-op whenever this
# shell is not inside tmux, so plain-terminal `sp` usage is byte-for-byte unchanged.
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

要点：

- `[ -n "$TMUX" ]`：`$TMUX` 仅在"当前 shell 处于 tmux 会话内"时才被设置，普通终端恒为空 → 守卫生效，外部零影响。
- 用 `printenv`（外部命令）读取变量值，bash/zsh 通用。
- 用 `set-environment -u` 标记未设置的变量，保证镜像状态与 shell 完全一致。

### 2.3 改造点 B：插件启动器（`scripts/launch.sh`）

将原来的"直接新建会话"逻辑，改为**从来源窗口所属会话读取 provider，并内联注入到 claude 进程**。

替换 `launch.sh` 中的：

```bash
tmux has-session -t "$session" 2>/dev/null ||
  tmux new-session -d -s "$session" -c "$path" "$cmd"

# Record which window launched it, so the picker can jump back here later.
[ -n "$window" ] && tmux set-option -t "$session" @claude_origin "$window"
```

为：

```bash
# Inherit the provider env (ANTHROPIC_*, CLAUDE_PROVIDER) from the session that
# owns the launching window — i.e. the terminal where `sp` was run. Mirrored onto
# tmux sessions by ~/.claude/switch-provider.sh (the `sp` command). We inject these
# INLINE so claude reads them at process start (creating the session and setting
# env afterwards would be too late).
provider_args=()
if [ -n "$window" ]; then
  origin_session="$(tmux display-message -t "$window" -p '#{session_name}' 2>/dev/null)" || origin_session=""
  if [ -n "$origin_session" ]; then
    for v in ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL \
             ANTHROPIC_DEFAULT_HAIKU_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL \
             ANTHROPIC_DEFAULT_OPUS_MODEL CLAUDE_PROVIDER; do
      line="$(tmux show-environment -t "$origin_session" "$v" 2>/dev/null)" || continue
      case "$line" in
        *=*) provider_args+=("$v=${line#*=}") ;;   # set: "VAR=value"
        # "-VAR" (unset) or anything else: skip -> simply absent in the new session
      esac
    done
  fi
fi

# Only a freshly created session starts claude; an existing one keeps whatever
# provider it was first launched with (shared-per-directory behaviour).
if ! tmux has-session -t "$session" 2>/dev/null; then
  if [ "${#provider_args[@]}" -gt 0 ]; then
    env_prefix=""
    for a in "${provider_args[@]}"; do
      env_prefix+=" $(printf '%q' "$a")"   # %q safely quotes token values
    done
    tmux new-session -d -s "$session" -c "$path" "env${env_prefix} $cmd"
  else
    tmux new-session -d -s "$session" -c "$path" "$cmd"
  fi
fi

# Record which window launched it, so the picker can jump back here later.
[ -n "$window" ] && tmux set-option -t "$session" @claude_origin "$window"
```

要点：

- **时序安全**：claude 启动那一刻就读环境，所以必须用 `env VAR=val claude` 内联注入，不能"先建会话再 set-environment"（那样 claude 拿到的是旧环境）。
- **`printf '%q'`**：安全转义 token 值中的特殊字符。
- **共享语义**：已存在的会话直接 attach，不重新注入 → 同目录多终端共享同一 provider。

> ⚠️ **注意**：`launch.sh` 是本地 clone 的修改。将来对该仓库 `git pull` 上游时会产生 merge 冲突，需手动解决（改动很小）。

### 2.4 改造点 C：Claude Code 配置（`~/.claude/settings.json`）

在 `settings.json` 顶层 `hooks` 字段中接入 `state.sh`，让选择器显示会话状态色（working/waiting/idle）：

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "/home/peace/code/peace/github/claude-tmux/scripts/state.sh working" }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt",
        "hooks": [
          { "type": "command", "command": "/home/peace/code/peace/github/claude-tmux/scripts/state.sh waiting" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "AskUserQuestion",
        "hooks": [
          { "type": "command", "command": "/home/peace/code/peace/github/claude-tmux/scripts/state.sh waiting" }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "/home/peace/code/peace/github/claude-tmux/scripts/state.sh idle" }
        ]
      }
    ]
  }
}
```

> 若已有 `hooks` 字段，合并进去即可；若没有，直接添加。Claude Code 动态重载 hooks，无需重启。

状态机对应：

| 事件                                                        | 状态      | 含义   | 选择器色 |
| --------------------------------------------------------- | ------- | ---- | ---- |
| `UserPromptSubmit`                                        | working | 正在忙  | 🔴 红 |
| `Notification`（permission）/ `PreToolUse`（AskUserQuestion） | waiting | 等你操作 | 🟡 黄 |
| `Stop`                                                    | idle    | 一轮结束 | 🟢 绿 |

---

## 三、使用指南

### 3.1 tmux 核心原理

tmux 采用 **server / client 分离**架构：

```
tmux server（常驻后台，1 个）
  ├─ session（会话）         ← 独立的工作空间
  │    └─ window（窗口）     ← 类似浏览器标签页
  │         └─ pane（窗格）  ← 窗口内的分割区域
  └─ session ...
client（显示端，可多个）      ← 你的终端窗口
```

- **server 持有所有 session**，client 只是"显示器"。一个 server 可以同时挂多个 client。
- `tmux` 命令启动时若 server 不存在则新建并 attach；`tmux attach` 则连到已有 server。
- 脱离（detach）= 把 client 从 session 上摘下，但 server 和 session 继续在后台跑。

**popup（弹窗）** 是盖在某个 client 上的临时浮层，per-client（只挡住触发它的那个 client）。本插件的 `prefix+a` / `prefix+u` 都用 popup 展示。

### 3.2 插件工作原理

插件由三部分协作：

| 组件   | 文件                              | 职责                                 |
| ---- | ------------------------------- | ---------------------------------- |
| 启动器  | `scripts/launch.sh`             | 为当前目录创建/重连 `claude-<hash>` 会话并弹窗挂载 |
| 选择器  | `scripts/picker.sh` + `list.sh` | 列出所有 `claude-*` 会话，预览、跳转、杀         |
| 状态钩子 | `scripts/state.sh`              | 由 Claude Code hooks 触发，把状态写到会话     |

**会话命名**：`claude-<md5(目录路径)前8位>`，保证"同一目录 = 同一会话"。

**键位**（本实践配置：prefix = `Alt+1`，启动键 = `a`）：

| 键            | 动作                     |
| ------------ | ---------------------- |
| `prefix + a` | 启动（或重连）当前目录的 claude 会话 |
| `prefix + u` | 打开会话选择器                |

选择器内：

| 键             | 动作     |
| ------------- | ------ |
| `enter`       | 跳转到该会话 |
| `ctrl-x`      | 杀掉高亮会话 |
| `↑/down`、输入过滤 | fzf 导航 |

### 3.3 三层位置模型

理解你在哪一层，是用好本插件的关键：

```
① WSL 终端（Windows Terminal / 你开的窗口）
   └─ ② tmux 会话（host）—— 普通 zsh shell，能跑 sp、能按 prefix
        └─ ③ claude 弹窗（prefix+a 打开）—— 直接是 claude 界面，不是 shell
```

| 层   | 是什么                 | 能做什么                      |
| --- | ------------------- | ------------------------- |
| ①   | 你的物理终端窗口            | 跑 tmux / tmux attach      |
| ②   | tmux host 会话的 shell | 跑 `sp`、按 prefix 触发插件、管理会话 |
| ③   | popup 里的 claude 界面  | 与 claude 对话、`/exit`       |

**关键认知**：

- `sp` 只能在 **②** 跑（它是 zsh 函数），在 ③ 的 claude 界面里没法跑。
- **"popup 关闭" ≠ "claude 退出"**：
  - `Alt+1，松开，d`（detach）= 收起浮层，claude **继续在后台跑**
  - claude 里 `/exit` = claude 进程结束，会话消亡
- claude 是 `claude-<hash>` 会话的唯一进程，它退出 → 该会话随之消亡。

### 3.4 prefix 操作详解

tmux 的所有命令都通过 **prefix 键** 触发：先按下 prefix（本实践为 `Alt+1`，即同时按 Alt 和 1），**松开**，再按下一个键。是两次独立按键，不是长按。

| 操作           | 按法              | 含义                        |
| ------------ | --------------- | ------------------------- |
| 启动 claude    | `Alt+1`，松开，`a` | 为当前目录起 claude 弹窗（等价 ccd）   |
| 打开选择器        | `Alt+1`，松开，`u` | 列出所有 claude 会话            |
| 收起浮层（detach） | `Alt+1`，松开，`d` | 回到 host shell，claude 后台继续 |
| 新建窗口         | `Alt+1`，松开，`c` | 在当前 session 开新窗口（类似新标签页）  |
| 切换窗口         | `Alt+1`，松开，数字  | 切到第 N 个窗口                 |
| 竖直分屏         | `Alt+1`，松开，`%` | 右边出新 pane                 |
| 水平分屏         | `Alt+1`，松开，`"` | 下面出新 pane                 |

> 在 popup（③）里按 `Alt+1, d`，是 detach 那个 claude 会话 → popup 关闭 → 回到 ② 的 host shell。

### 3.5 完整操作示例：不同目录启动不同 provider 的 claude

场景：有两个项目目录，分别要用 provider `p1` 和 `p2`（假设 `sp` 已配置好这两个 provider）。

#### 准备：确认 sp 可用

```sh
sp          # 不带参数，列出可用 provider 名字 + 当前用的那个
```

#### 步骤 1：进入 tmux

```sh
cd ~/projects/projectA
tmux                    # 进入 host 会话（位置②），自动加载插件
```

#### 步骤 2：在 projectA 用 p1 起 claude

```sh
# 仍在位置②的 shell
sp p1                   # 切换 provider，会打印 "✓ p1  https://...  sk-..."
# 按  Alt+1，松开，a     ← prefix+a，为 projectA 弹出 claude（用的是 p1）
```

此时 claude 进程拿到 `p1` 的 `ANTHROPIC_BASE_URL` 等。

#### 步骤 3：换到 projectB，用 p2 起 claude

在 popup（③）里按 `Alt+1, d`（detach，收起浮层，回到 ②），或者直接**新开一个 WSL 终端**：

```sh
cd ~/projects/projectB
tmux attach             # 连到同一个 server（成为第二个 client）
sp p2                   # 切换 provider
# 按  Alt+1，松开，a     ← 为 projectB 弹出 claude（用的是 p2）
```

> 用 `tmux attach` 而非再开一个 `tmux`，是为了连到**同一个 server**，这样所有 claude 会话都在一个 server 里，选择器才能统一列出。

#### 步骤 4：用选择器总览所有会话

```sh
# 按  Alt+1，松开，u     ← prefix+u 打开选择器
```

选择器里能看到：

```
🟢 ● idle     1m  ~/projects/projectA      (p1)
🔴 ● working  3m  ~/projects/projectB      (p2)
```

- 需要 you 关注的（waiting 黄、idle 绿）排在最上面
- `↑/down` + 输入过滤导航
- `enter` 跳转（切到该会话的来源窗口，再在其上恢复弹窗）
- `ctrl-x` 杀掉已完成的会话

#### 步骤 5：验证 provider 注入（从外部窥探）

另开一个 WSL 终端（不在 tmux 里），查看正在跑的 claude 进程**实际拿到**的 base url：

```sh
for pid in $(pgrep -f claude); do
  url=$(tr '\0' '\n' < /proc/$pid/environ 2>/dev/null | grep '^ANTHROPIC_BASE_URL=')
  [ -n "$url" ] && echo "pid $pid : $url"
done
```

应看到两个 claude 进程分别带 p1、p2 的 url。

#### 步骤 6："同目录共享 provider"语义

在 projectB 再开一个终端，`sp p3` 后 `prefix+a`：由于 `claude-<projectB的hash>` 已存在，launch.sh **直接 attach**，**不会**用 p3 重新注入——该会话仍保持 p2。这正是"同目录共享一个 provider"。

若要让 projectB 改用 p3：

```sh
# 方式 A：重新进入会话后 /exit
Alt+1, a     # 重连 projectB 的 claude
/exit        # 在 claude 里退出，会话消亡

sp p3
Alt+1, a     # 重新创建，这次用 p3

# 方式 B：从外部直接杀
tmux kill-session -t claude-<projectB的hash>
sp p3
Alt+1, a
```

---

## 四、常用命令速查

| 目的              | 命令 / 操作                                                           |
| --------------- | ----------------------------------------------------------------- |
| 进 tmux          | `tmux`                                                            |
| 连到已有 server     | `tmux attach`                                                     |
| 列出会话            | `tmux ls`                                                         |
| 看 claude 会话及状态  | `tmux ls -F '#{session_name}: #{t:claude_state}' \| grep claude-` |
| 杀会话             | `tmux kill-session -t <会话名>`                                      |
| 重载配置            | `tmux source ~/.config/tmux/tmux.conf`                            |
| 看某会话环境变量        | `tmux show-environment -t <会话> <变量>`                              |
| 看 claude 进程实际环境 | `tr '\0' '\n' < /proc/<pid>/environ \| grep ANTHROPIC`            |

## 五、注意事项

1. **launch.sh 是本地改动**：`git pull` 上游会冲突，手动解决即可（改动集中在 `launch.sh`）。
2. **`pgrep -f claude` 匹配过宽**：它会命中路径里含 "claude" 的任何进程（包括插件脚本、其他手动开的 claude）。判断某会话是否退出，用 `tmux ls \| grep claude-` 才权威。
3. **detach ≠ exit**：`Alt+1, d` 让 claude 后台继续跑；`/exit` 才真正结束。
4. **PATH 顺序**：`/usr/local/bin` 必须在 `/usr/bin` 之前，新版 tmux 才生效（Ubuntu 22.04 默认满足）。

---

## 六、状态感知：状态栏 + 桌面通知

插件本身只有"被动看板"——你 `prefix+u` 打开选择器才能看状态。本节加两块"主动感知"能力，互不冲突：

| 方案 | 形态 | 解决 |
|---|---|---|
| A 状态栏 | tmux 底部状态栏常驻一排彩色圆点 | 你**在 tmux 里**时瞥一眼就知道谁闲谁忙 |
| B 桌面通知 | 状态变化时弹 Windows toast | 你**离开 tmux**时被主动提醒 |

### 6.1 方案 A：tmux 状态栏常驻

新增 `scripts/statusbar.sh`：遍历 `claude-*` 会话，读 `@claude_state`，输出彩色圆点 + 目录名。输出用 **tmux 自家的 `#[...]` 样式码**（不是 ANSI，否则状态栏乱码），颜色与选择器一致：

- 🟡 waiting（黄）— 需要你，排最前
- 🟢 idle（绿）— 一轮完成，该你了
- ⚪ unknown（灰）— hook 还没触发
- 🔴 working（红）— 忙着，排最后

接入 `tmux.conf`：

```tmux
set -g status-interval 5                                      # 每 5 秒刷新
set -g status-right-length 100
set -g status-right '#(/home/peace/code/peace/github/claude-tmux/scripts/statusbar.sh) %H:%M'
```

效果：状态栏右侧始终有 `● productpy  ● groupbuy  14:30`，圆点颜色随状态实时变。

### 6.2 方案 B：桌面通知

**背景**：状态栏只在 tmux 里可见；切去浏览器/IDE 就看不到了。补一个 OS 级 push。

**通知器选择**（WSL → Windows toast）：
- `notify-send`（libnotify-bin）：依赖 D-Bus 会话总线 + 通知守护。WSLg **不内置通知守护**，本实践环境实测走不通（"Could not connect"）。
- **`wsl-notify-send.exe`**：专为 WSL→Windows toast 设计的单文件 exe，不依赖 D-Bus。**本方案采用它**。

安装 wsl-notify-send.exe（一次性，下载到 `~/bin/`）：

```sh
curl -fL --proxy http://172.19.16.1:7897 -o /tmp/wns.zip \
  https://github.com/stuartleeks/wsl-notify-send/releases/download/v0.1.871612270/wsl-notify-send_windows_amd64.zip
mkdir -p ~/bin && unzip -o /tmp/wns.zip -d /tmp/wns-extracted
cp /tmp/wns-extracted/wsl-notify-send.exe ~/bin/
~/bin/wsl-notify-send.exe "hello"          # 验证：Windows 弹 toast
```

> 若网络直连失败，加 `--proxy` 走你的代理。

**`scripts/notify.sh`**（统一入口，best-effort）：
1. 优先 `wsl-notify-send.exe`（查 PATH，再查 `$HOME/bin/`——hook 环境 PATH 可能不含 `~/bin`）
2. 退化 `notify-send`（有 D-Bus 守护时）
3. 最后终端铃声 `\a`

**`scripts/state.sh` 改造**（在原"写状态"逻辑后追加通知判断）：
- 读**旧状态**再写新状态。
- **转移边判断**（避免噪音）：只在 `waiting` 或 `working→idle` 这两条边上通知；`idle→idle` 等不响。
- **`session_attached` 门禁**：查目标会话当前有没有 client 在看（popup 开着 = attached>0 = 你在里面），>0 就**不弹**——你正盯着的会话不打扰你。
- 文案纯 ASCII：`[DONE] <项目名>` / `[NEEDS YOU] <项目名>`。

**ASCII 限制**（重要）：wsl-notify-send.exe 在"系统区域设置非 UTF-8"的中文 Windows 上会**乱码 emoji 和中文**（参数跨 WSL→Windows 边界时丢字节）。所以 toast 文案只用 ASCII；颜色信号留给状态栏。彻底修需开 Windows 的"Beta: UTF-8 全球语言支持"（系统级改动，不建议）。

**hooks 接线**（见 2.4）：`settings.json` 的 `Stop`/`Notification`/`PreToolUse` 等 hook 调 `state.sh`，state.sh 内部决定是否发 toast。无需额外接线。

### 6.3 两者分工与门禁语义

| 你的状态 | 状态栏（A） | toast（B） |
|---|---|---|
| 在某 session 的 popup 里作业 | 灯实时变色（瞥见） | **不发**（attached>0，门禁拦） |
| detach 了去干别的 / 切去别的应用 | 灯变色 | **发**（完成/要权限时） |

`★ Insight ─────────────────────────────────────`
`session_attached` 是"免费"的在场信号——它是 popup 开关的副产物（popup 开 = 一条 attach client 挂在该会话 = attached=1）。复用它做门禁，零额外状态、零竞态：你打开 popup = 你在场 = 不打扰；你 detach = 不在场 = 才 push。通知判的是**转移边**（working→idle）而非**稳态值**，所以 claude 反复 Stop 只在第一次从忙变闲时响一次。
`─────────────────────────────────────────────────`

### 6.4 弹窗全覆盖：消除双状态栏

**现象**：`prefix+a` 弹出的 claude 浮层比窗口小，且能看到**两条状态栏**，背景显得乱。

**原因**：
- 插件默认 `@claude_popup_width/height = 90%`，浮层只占九成，四周露出 host 的 shell 内容。
- 浮层 attach 的 `claude-<hash>` 会话自身也开着 `status`（状态栏配置是全局的），于是浮层内部画一条状态栏；host 底部又露一条 → 两条。

**修复**（三处）：

`tmux.conf` —— 浮层 100% 全屏（状态栏被盖住，detach 后恢复可见）：
```tmux
set -g @claude_popup_width '100%'
set -g @claude_popup_height '100%'
```

`scripts/launch.sh` —— 关掉浮层内部那条状态栏 + 无边框：
```bash
# claude-<hash> 会话关 status，浮层 attach 时不再画第二条栏
tmux set-option -t "$session" status off
# -B 无边框；100% 填满窗口，全屏体验（host 状态栏被覆盖，detach 后可见）
tmux display-popup -B -w "$w" -h "$h" -E "tmux attach-session -t $session"
```

`scripts/list.sh` —— picker 浮层同样加 `-B`。

**效果**：浮层全屏无边框，纯 claude 界面。状态栏（圆点）在 popup 内不可见——`detach`（`Alt+1, d`）回到 host 后状态栏恢复显示。取舍：全屏简洁优先，需要看其他会话状态时用选择器（`Alt+1, u`）或 detach 回 host。

`★ Insight ─────────────────────────────────────`
`display-popup` 的百分比是相对**整个 client 窗口**（含状态栏行），不是相对 pane。所以 `-h 100%` 会盖住状态栏。如果你需要 popup 里也能瞥见圆点，把 `@claude_popup_height` 调成 `96%` 即可。
`─────────────────────────────────────────────────`

---

## 七、跨设备配置（用 EnvSync 同步到另一台 WSL 机器）

本套配置分两部分同步到另一台机器：

- **插件脚本 + 本文档** → 在你的 fork `peacewang/claude-tmux` 里，`git clone` 即得，能正常 push。
- **个人 dotfile**（`tmux.conf`、`settings.json`、`switch-provider.sh`）→ 走 [EnvSync](https://github.com/peacetool/EnvSync)，同步到 `peacepc-wsl` 环境。

### 7.1 文件来源分两类

**A. 靠 `git clone` 你的 fork 获得**（在 fork 仓库里，无需 envsync）：

| 文件 | 内容 |
|---|---|
| `scripts/launch.sh` | provider 注入 + status off + 无边框弹窗 |
| `scripts/state.sh` | 状态写入 + 转移边 + 门禁 + 调通知 |
| `scripts/list.sh` | 选择器弹窗（无边框） |
| `scripts/statusbar.sh` | 状态栏圆点（方案 A） |
| `scripts/notify.sh` | 桌面通知派发器（方案 B） |
| `claude-tmux实践指南.md` | 本文档 |

**B. 靠 EnvSync 同步的个人 dotfile**：

| # | 仓库内路径 | 还原到 | 内容 |
|---|---|---|---|
| 5 | `common/switch-provider.sh` | `~/.claude/switch-provider.sh` | `sp` 的 tmux 镜像（common，mac/wsl 共享） |
| 9 | `settings.json` | `~/.claude/settings.json` | hooks（状态色 + 通知） |
| 10 | `tmux.conf` | `~/.config/tmux/tmux.conf` | tmux 配置（指向 fork 路径） |

> 这样分工的好处：脚本的迭代走 fork 的 git（有版本历史、能 PR、能 diff），envsync 只管"这台机器该用哪些 dotfile"，职责清晰，也避免了之前"envsync pull 覆盖插件脚本 + git pull 冲突"的耦合。

### 7.2 EnvSync 工作机制（速览）

- **身份判定**：读取 `~/.envsync-identity` 文件首行作为当前环境名。新机器需手动写入：`echo peacepc-wsl > ~/.envsync-identity`。
- **仓库结构**：`envs/<环境名>/` 存放该环境的跟踪文件副本；`envs/common/` 存放跨环境共享文件。
- **核心命令**：
  - `envsync add <路径>` —— 把文件加入当前环境跟踪
  - `envsync status` —— 查看哪些文件已修改未推送
  - `envsync push [<编号>]` —— 收集变更、提交并推送到远程（注意：多编号不可，需逐个推；新 add 的文件若内容已与仓库一致会漏提交，需手动 git 兜底）
  - `envsync pull [<编号>]` —— 从远程拉取并同步回本机（`-f` 强制镜像覆盖）

### 7.3 新机器完整搭建顺序

在另一台 Windows+WSL 机器上，**按以下顺序执行**（顺序很重要）：

**第一步：安装 tmux 3.6b + fzf**（见本文第一章 1.2、1.3）

**第二步：clone 并配置 EnvSync**

```sh
git clone <你的 EnvSync 仓库地址> ~/code/peace/github/peacetool/EnvSync
# 让 envsync 命令可用（确保该路径在 PATH 里，或按你现有方式加载）
echo peacepc-wsl > ~/.envsync-identity    # 设定本机环境身份
envsync whoami                            # 确认输出: peacepc-wsl
```

**第三步：clone 你的 fork**（拿到全部脚本 + 本文档）

```sh
git clone https://github.com/peacewang/claude-tmux \
  ~/code/peace/github/claude-tmux
```

**第四步：envsync pull**（还原个人 dotfile）

```sh
envsync pull            # 还原 tmux.conf / settings.json / switch-provider.sh
```

> ⚠️ `tmux.conf` 和 `settings.json` 里写死了 fork 路径 `/home/peace/code/peace/github/claude-tmux/...`，所以**必须先 clone fork（第三步）再 envsync pull（第四步）**，否则 `statusbar.sh` / `state.sh` 路径找不到。

**第五步：下载 `wsl-notify-send.exe`**（见 6.2，二进制不进任何仓库，每台机器单独下到 `~/bin/`）

**第六步：验证**

```sh
tmux -V                                   # tmux 3.6b
fzf --version                              # fzf 已装
which -a tmux                              # /usr/local/bin/tmux 在前
ls ~/code/peace/github/claude-tmux/scripts/statusbar.sh   # 脚本已就位
grep -q claude-tmux ~/.config/tmux/tmux.conf && echo "插件已接入"
grep -q TMUX ~/.claude/switch-provider.sh && echo "sp 镜像块已就位"
```

进入 tmux，按 `prefix+a` 起 claude，按 3.5 的流程验证 provider 注入。

### 7.4 跨设备注意事项

1. **路径必须一致**：`tmux.conf` 和 `settings.json` 写死了 `~/code/peace/github/claude-tmux` 路径。两台机器的 clone 路径要相同，否则插件加载不到、hooks 也找不到 `state.sh`。

2. **脚本更新走 fork**：改了 `scripts/` 后 `git push` 到 `peacewang/claude-tmux`；其他机器 `git pull` 即得。**不再用 envsync 管脚本**（避免了之前"envsync pull 覆盖 + 上游 git pull 冲突"的耦合）。

3. **identity 文件不进仓库**：`~/.envsync-identity` 是每台机器本地标识，不应同步。两台 WSL 都写 `peacepc-wsl`。

4. **`wsl-notify-send.exe` 不进任何仓库**：3.5MB 二进制，每台机器按 6.2 单独下。没装则 `notify.sh` 退化到终端铃声。

5. **通知文案必须 ASCII**：新机器若也是中文 Windows（系统区域非 UTF-8），toast 里 emoji/中文会乱码（见 6.2）。`state.sh` 文案已是 ASCII，别加 emoji 回去。

6. **新机器首跑**：第一次 `tmux` 进入时会自动加载 `~/.config/tmux/tmux.conf`，无需手动 source。

`★ Insight ─────────────────────────────────────`
EnvSync 用"环境名 + common 共享"的模型，优雅地处理了"多台机器、跨 OS、部分共享"的同步需求：`peacepc-wsl` 放 WSL 专属文件，`common/` 放所有环境共享的脚本（如 `switch-provider.sh`）。这样 mac 和 wsl 用同一套 sp 逻辑，但各自的 shell/tmux 配置互不污染。
`─────────────────────────────────────────────────`

---

*文档基于 2026-06-24 的实践整理。tmux 3.6b + claude-tmux（本地改造版）+ 状态栏/桌面通知增强 + EnvSync 跨设备同步。*
