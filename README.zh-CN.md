# ccauth

一条命令在多个 Claude Code 账号之间切换，不用每次都跑 `/login`。

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
