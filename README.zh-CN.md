# ccauth

一条命令在多个 Claude Code 账号之间切换，不用每次都跑 `/login`。也管理 Gemini CLI 账号、Antigravity 的第三方中转、Codex 的模型分流与公益站每日签到，并附带一个 macOS 软件。

[English](README.md)

```console
$ ccauth list
  work         alice@example.com          保存于 2026-09-05T20:08:53+08:00
* personal     bob@example.com            保存于 2026-09-05T20:06:46+08:00

$ ccauth work
（已把当前登录态回存到 personal）
已切换到账号 work -> alice@example.com
  access token 还剩 7.8 小时
```

## 解决什么问题

Claude Code 同一时刻只保存一份凭据。登录第二个账号会覆盖第一个，所以同时有工作账号和个人账号的人，每天要重复跑 `/login` 并在浏览器里重新授权好几次。

凭据本身只是两份状态。`ccauth` 把这两份存成一个命名 profile，需要时整体写回。其余东西全部共用，包括 settings、skills、agents、MCP 服务、memory 和会话历史。

## 安装

```sh
curl -fsSL https://raw.githubusercontent.com/qzkinhit/ccauth/main/install.sh | sh
```

或者手动装。

```sh
curl -fsSL https://raw.githubusercontent.com/qzkinhit/ccauth/main/ccauth -o ~/.local/bin/ccauth
chmod +x ~/.local/bin/ccauth
```

依赖只有 Python 3.8 或更高版本，以及 Claude Code 本身，不引入任何第三方库。如果 `~/.local/bin` 不在 `PATH` 里，加进去。

```sh
export PATH="$HOME/.local/bin:$PATH"
```

## 首次配置

第一步，保存现在已经登录的账号。

```sh
ccauth save work
```

第二步，登录另一个账号。

```sh
claude
# 在 claude 里执行
/login
# 走完浏览器授权，然后退出 claude
```

第三步，把它也保存下来。

```sh
ccauth save personal
```

两个账号都存好了。之后切换只需要一条命令。

## 用法

```
ccauth save <名字> [--force]   把当前登录的账号存成一个 profile
ccauth use <名字>              切换到该账号，简写 ccauth <名字>
ccauth list                    列出已保存的账号，* 标记当前
ccauth status                  显示当前账号
ccauth rm <名字>               删除一个 profile
ccauth path                    显示凭据与 profile 的存放位置
ccauth version                 打印版本号
```

不带参数的 `ccauth` 等同于 `ccauth status`。直接给一个名字等同于 `ccauth use <名字>`，所以 `ccauth work` 就是切到 `work`。

**切完要重启 `claude`。** 已经在运行的会话仍然使用它启动时的账号，退出时还可能把旧身份写回配置文件。`ccauth` 检测到 `claude` 仍在运行时会打印提示。

## 原理

Claude Code 把账号信息放在两个地方。

| | macOS | Linux |
|---|---|---|
| 凭据 | 登录钥匙串，通用密码条目 `Claude Code-credentials` | `~/.claude/.credentials.json` |
| 身份 | `~/.claude.json` 的 `oauthAccount` 字段 | 同左 |

凭据是一个小 JSON 对象。

```json
{"claudeAiOauth": {"accessToken": "...", "refreshToken": "...",
  "expiresAt": 1788637711000, "refreshTokenExpiresAt": 1791229711000,
  "scopes": ["user:inference", "user:profile"],
  "subscriptionType": "pro", "rateLimitTier": "default_claude_ai"}}
```

`ccauth save` 把这两份一起复制到 `~/.ccauth/<名字>.json`。`ccauth use` 把它们写回去，然后删掉配置文件里缓存上一个账号订阅额度和模型权限的那批键，下次启动 `claude` 会按新账号重新拉取。

有三个实现细节值得知道。

1. **切走之前会刷新旧 profile。** access token 大约每 8 小时轮换一次。切换前 `ccauth` 会把当前这份活凭据写回它所属的 profile，所以几周没用过的 profile 里仍然是可用的 refresh token。refresh token 的有效期大约 30 天，所以一个月内切回去的 profile 能自行续期，不需要重新登录。
2. **token 不会出现在 `argv` 里。** macOS 上写钥匙串通过 `security -i` 的标准输入完成，`ps` 看不到 token。
3. **每次写配置文件前都会备份**，备份路径是 `~/.ccauth/claude.json.bak`。

`ccauth` 还复现了 CLI 自己的钥匙串条目名推导规则。设置了 `CLAUDE_CONFIG_DIR` 时，条目名会附加 `sha256(CLAUDE_CONFIG_DIR)` 的前 8 位十六进制。所以在隔离的配置目录下 `ccauth` 同样可用，见下一节。

## 让两个账号同时在线

`ccauth` 切换的是全局账号，这对大多数场景够用。如果需要两个账号在两个终端里同时在线，Claude Code 本身通过 `CLAUDE_CONFIG_DIR` 直接支持。

```sh
CLAUDE_CONFIG_DIR=~/.claude-work claude
```

这个目录会有自己的一份凭据和自己的钥匙串条目。代价是 settings、skills、agents、MCP 服务和会话历史也一并分家。可以用软链接把需要共用的部分链回去。

```sh
mkdir -p ~/.claude-work
for f in settings.json skills agents commands output-styles CLAUDE.md; do
  ln -sfn ~/.claude/"$f" ~/.claude-work/"$f"
done
```

`ccauth` 在这种目录下也能工作。带上同样的 `CLAUDE_CONFIG_DIR` 运行，它会指向那个目录对应的凭据存储。

## Gemini CLI

`ccauth` 同样支持为 [Gemini CLI](https://github.com/google-gemini/gemini-cli) 切换多个 Google 账号，只需加上 `gemini` 子命令（原有的 Claude Code 命令和逻辑完全不变）：

```sh
ccauth gemini save work            # 保存当前登录的 Gemini 账号
# 在 gemini 里切换账号（运行 /auth 登录）后：
ccauth gemini save personal

ccauth gemini work                 # 一键切回 work
ccauth gemini list                 # 列出已保存的 Gemini 账号
ccauth gemini status               # 显示当前 Gemini 账号
ccauth gemini rm personal          # 删除一个 Gemini profile
ccauth gemini path                 # 显示 Gemini 凭据与 profile 路径
```

Gemini 的 profile 单独保存在 `~/.ccauth/gemini/<名字>.json`（权限 `600`），和 Claude Code 的 profile 互不冲突，可以用相同的名字（比如 `work`、`personal`）。脚本会自动处理 `~/.gemini/oauth_creds.json`、`~/.gemini/google_accounts.json` 以及 macOS 钥匙串条目（`gemini-cli-oauth` / `main-account`），并在切走前自动回存当前活跃凭据。

如果想要更短的命令，可以建一个 `gauth` 软链接：

```sh
ln -s ~/.local/bin/ccauth ~/.local/bin/gauth
gauth work
```

## Antigravity

`ccauth agy` 让 Antigravity（命令行 `agy` 与桌面版）在官方 Google 登录和第三方 Gemini 兼容中转站之间切换。

```sh
ccauth agy save work                             # 把当前登录的 Google 账号存为 work
ccauth agy accounts                              # 列出已保存的官方账号
ccauth agy use official work                     # 切回官方并换成 work 账号
ccauth agy models                                # 立即更新中转站的可用模型（后台每 15 分钟也会更新）
ccauth agy add relay --url https://relay.example.com --key sk-xxxx
ccauth agy use relay                             # 切到中转站
ccauth agy use official                          # 切回官方登录
ccauth agy list                                  # * 标记当前模式
ccauth agy status
ccauth agy rm relay
```

`add` 会请求中转站的 `/v1/models`，记下所有 `gemini` 开头的模型。中转站的模型名带固定的思考档位后缀（如 `gemini-4-argon-high`）时，本地桥会把 Antigravity 请求的模型名（如 `gemini-4-argon-low`）映射到同一系列里可用的那一个。也可以用 `--models a,b` 手动指定列表，用 `--default` 指定兜底模型。

切换后要重启 `agy` 与桌面版。已经打开的终端先执行 `exec $SHELL`。

### 第三方模式做了什么

| 部分 | 做法 |
|---|---|
| `agy` | 设置文件写入 `modelProvider: "gemini"`，shell 里的 `agy` 函数带上本地桥地址启动，`agy` 进入 API key 模式，不使用 Google 登录 |
| 桌面版 | 桌面版没有 API key 模式。`launchctl setenv CLOUD_CODE_URL` 把它的后端地址指向本地桥 |
| 本地桥 | 一个常驻在 `127.0.0.1:18765` 的 LaunchAgent。生成请求转给中转站，账号类请求（模型列表、配额等）用本地缓存应答 |
| installation_id | 每个中转站使用自己的一份，切回官方时恢复原值 |
| 官方登录态 | 不删除。第一次切走时自动备份钥匙串条目，切回时若条目缺失则用备份恢复 |

发给中转站的只有对话内容、生成参数和中转站自己的 key。Google 的 OAuth token、项目号和 installation_id 不会发给中转站。生成请求也不会发给 Google。本地缓存中没有的账号类请求会原样转发给 Google 一次并写入缓存，之后不再转发。

桌面版的模型列表在第三方模式下会被改写。中转站提供 Carbon 时解除 Carbon 的锁定，配额显示为满，中转站不提供的 Claude 与 GPT 模型不显示。

### 按次计费的中转站怎么省调用

Agent 每调用一次工具（读文件、跑命令），都要把工具结果发回模型再请求一次，所以一个问题通常会产生多次请求。按次计费时，可以用下面两个开关。

```sh
ccauth agy cheap relay gemini-4-hydrogen-xhigh   # 带工具结果的步骤改用便宜模型
ccauth agy hint relay on                         # 在系统提示末尾追加省调用提示词
ccauth agy cheap relay off                       # 关闭
ccauth agy hint relay off
```

`cheap` 开启后，本地桥按最后一条消息区分请求。最后一条是你的提问时用你选的模型，最后一条是工具结果时用便宜模型。所以每个问题的第一次调用（决定怎么做）仍由强模型完成，后续执行步骤由便宜模型完成。问题以 `@h` 开头时，这个问题的全部调用都用便宜模型，适合简单任务。以 `@m` 开头时全部调用都用所选模型。`ccauth agy writing relay on` 会让含写作类关键词（润色、改写、论文、.tex 等）的问题全程用所选模型，默认关闭。

`hint` 开启后，本地桥要求模型把互不依赖的工具调用合并到同一轮，路径已知时直接读取，先完成全部调研再一次写完，信息足够时直接回答。也可以把自定义文本作为第三个参数传入。

`ccauth agy writer relay gemini-4-argon-high` 开启写作模型。本地桥在系统提示里说明分工：模型在下一步要动笔写文档、报告、讲稿或长篇回答时，在回复开头写 `【写作】`，写作期间每轮保留这个标记，写完去掉。本地桥看到上一轮回复带有标记，就把这一步交给写作模型，其余工具步骤仍用便宜模型。第一次调用的主模型在计划里写明哪些步骤是写作。模型漏写标记时，这一步按普通工具步骤处理，不会额外发起调用。

Antigravity 只把用户输入的内容包在 `<USER_REQUEST>` 标签里。后台命令结束等应用自己插入的消息没有这个标签，本地桥把它们当作工具步骤，不当作新的提问。

两个模型的历史里带有思维签名。中转站因为签名拒绝请求时，本地桥把签名替换为 Gemini 文档给出的跳过校验值后重试一次。countTokens 请求在本地估算，不发给中转站。

### 多个 key 自动切换

```sh
ccauth agy fallback relay relay2     # relay 的 key 用完或失效时改用 relay2
ccauth agy fallback relay2 relay     # 反过来也设上，两个 key 互为备用
ccauth agy fallback relay off        # 关闭
```

中转站以额度用完、余额不足、key 过期或无效拒绝请求时，本地桥用备用 key 重发同一个请求，并把用完的 key 标记到当天零点。标记期间的请求直接从备用 key 开始，不再先试用完的那个。零点后标记解除，按每天刷新额度的中转站正好恢复。中转站上游号池冷却（报错含 cooling down 或无可用渠道）不触发切换，因为同一站点换 key 也会失败。手动切换仍用 `ccauth agy use <名字>`。`ccauth agy status` 末尾和 `ccauth agy quota` 都会列出每个 key 所属账户的剩余额度与已用额度，查询走中转站的令牌用量接口，不消耗模型调用。

### 每日签到

开启签到功能的 NewAPI 中转站（v1.0 版，登录后用短期令牌加 30 天刷新凭证）可以自动签到。

```sh
ccauth agy login relay 用户名          # 登录 key 所属的账户，提示输入密码
ccauth agy checkin                    # 立即为所有已登录账户签到，已签过的跳过
ccauth agy checkin --install          # 每天 00:10、12:10 及开机登录时自动签到
ccauth agy checkin --uninstall        # 取消自动签到
```

平时用刷新凭证换取短期令牌，刷新凭证在登录 30 天后过期，届时用保存的密码自动重新登录。密码与凭证保存在 `~/.ccauth/agy/providers/<名字>.json`，权限 600。一天内多次运行只会签到一次，当天已成功的账户不再发请求，同一站点的多个账户之间间隔 30 到 60 秒。结果写入 `~/.ccauth/agy/checkin.log`，`ccauth agy status` 显示每个账户今天是否已签到和领取的额度。站点开启人机验证时无法自动签到。

有些老版 NewAPI 站点不提供签到按钮，而是在每天第一次登录时发放额度。`ccauth agy site <名字> <地址> <用户名> <用户ID> [系统访问令牌]` 添加这类站点。签到时先用系统访问令牌读取额度日志，今天已有签到记录就跳过，没有才用账号密码登录一次，再读日志确认领取的额度。通过第三方登录注册的账户需要先在站点设置密码。

第三方模式目前只支持 macOS。

## Codex：主代理用 Gemini，子代理用 CC Switch 的服务商

Codex 同一会话里的主代理和子代理共用一个服务商，角色配置也改不了服务商。`ccauth codex` 在本机启动一个分流服务，按请求里的模型名分发：`gemini-` 开头的请求发往 `ccauth agy add` 保存的 Gemini 中转站，其余模型发往 CC Switch 最近写入 `~/.codex/config.toml` 的服务商，并沿用请求自带的认证头。

```sh
ccauth codex on                       # 开启，先备份 ~/.codex/config.toml
ccauth codex subagent gpt-6.1-sol     # 子代理模型，默认 gpt-6.1-sol
ccauth codex subagent follow          # 子代理跟随 CC Switch 当前选中的模型
ccauth codex main gemini-4-neon-xhigh # 主代理模型
ccauth codex status
ccauth codex log -f                   # 实时查看请求：模型、去向、成败、耗时、token
ccauth codex off                      # 恢复 CC Switch 写入的配置
```

开启后，配置里服务商的 `base_url` 指向本地分流，`model` 改为主代理模型，`[agents]` 写入 `default_subagent_model`。一个 LaunchAgent 监视配置文件，CC Switch 每次切换服务商重写文件后，它记下新的上游地址和模型并重新应用这些修改。

有些中转站会拒绝自称 Codex 的系统提示，返回 429。发往 Gemini 中转站的请求中，developer、system 消息和 instructions 里的 Codex、OpenAI 字样会被替换为中性说法。主代理模型冷却或下架时依次改用 `gemini-4-hydrogen-xhigh`、`gemini-3.8-flash-high`，中转站 key 额度用完时沿用 `ccauth agy fallback` 的设置换 key。设置对新开的 Codex 会话生效。

## macOS 软件

`mac/` 目录是一个原生 SwiftUI 软件，覆盖 ccauth 的全部功能：Antigravity 官方与第三方切换、中转站设置与余额、Codex 分流、每日签到、Claude 与 Gemini CLI 多账号。软件里的每个操作都调用 `ccauth` 命令，窗口内容来自 `ccauth state` 输出的 JSON，所以命令行与软件的功能一致。

```sh
cd mac
./build.sh            # 生成 mac/build/ccauth.app（同时支持 Apple 芯片与 Intel）
./build.sh --install  # 同时复制到 /Applications
```

构建需要 Xcode Command Line Tools（`xcode-select --install`），运行需要 macOS 14 或更高版本。软件优先使用 `~/.local/bin/ccauth`，找不到时使用打包在软件里的副本。

## Windows

Windows 包包含 `ccauth-gui.exe`（窗口程序）与 `ccauth.exe`（命令行），由 GitHub Actions 在 Windows 上用 PyInstaller 编译，并在发布前自动运行冒烟测试。Windows 上可用 Claude 与 Gemini CLI 多账号、中转站管理与余额、每日签到（任务计划程序在 00:10 与 12:10 运行）。Antigravity 第三方模式与 Codex 分流只在 macOS 上提供。

## 文件位置

| 路径 | 内容 |
|---|---|
| `~/.ccauth/<名字>.json` | 一个已保存的账号，权限 `600` |
| `~/.ccauth/claude.json.bak` | 上一次写入前的全局配置备份 |
| `~/.local/bin/ccauth` | 脚本本身 |

用 `CCAUTH_HOME` 可以改 profile 目录。用 `CCAUTH_LANG=en` 或 `CCAUTH_LANG=zh` 可以强制输出语言，不设置时按 locale 自动判断。

## 安全说明

profile 里存的是可用的 OAuth token。文件权限是 `600`，目录权限是 `700`，与 SSH 私钥同级，但它们在磁盘上而不在钥匙串里。这是换取免交互切换所付出的代价。

macOS 钥匙串条目用 `security add-generic-password -A` 写入，含义是以你的身份运行的任何程序都能免提示读取。Claude Code 本身就是这样存这个条目的，所以并没有降低原有的门槛。

不要把 `~/.ccauth` 放进同步文件夹、会离开本机的备份，或者 git 仓库。如果 profile 泄露，去 [claude.ai](https://claude.ai/settings) 吊销会话并重新登录。

## 常见问题

**提示 `没有找到凭据`。** 当前没有登录。启动 `claude`，执行 `/login`，然后重试。

**提示 `写入钥匙串后校验不一致`。** 登录钥匙串处于锁定状态。在钥匙串访问里解锁，或者运行 `security unlock-keychain`。

**切换成功了但 `claude` 里还是旧账号。** 切换时有 `claude` 进程在运行，它退出时把旧身份写了回去。退出全部会话，重新执行 `ccauth use <名字>`，再启动 `claude`。

**切换后 `claude` 要求重新登录。** 该 profile 的 refresh token 已过期，大约一个月没用过那个账号就会出现这种情况。对那个账号执行 `/login`，然后用 `ccauth save <名字> --force` 覆盖已存的凭据。

## 兼容性

在 macOS 15 上针对 Claude Code 2.1.259 开发。Linux 分支依据 CLI 中相同的代码路径实现，但测试较少，欢迎反馈。

`ccauth` 读写的是 Claude Code 自己的文件，这些格式不是公开接口，未来版本可能变化。脚本在异常时直接报错退出，不会静默写坏状态，并且每次写配置前都会备份。

## 许可

MIT
