[English](README.md) | **中文**

# ProvingPod

**一个用完即弃的沙箱，让 AI Agent 用一条命令证明代码真的能跑起来。**

```bash
ssh 3f2a9c@<你的服务器> -p 6901 'npm install && npm test'
```

这就是全部准备工作。连上的那一刻，你就拥有一个属于自己的、全新的隔离沙箱：

| 你立刻得到 | 具体是什么 |
|---|---|
| **完整工具链** | Node 22、npm、git、build-essential —— `npm install && npm test` 直接可用 |
| **一个运行结论** | 远端命令的退出码会原样返回：`0` 就代表它跑起来了 |
| **专属沙箱** | 独立的容器与网络命名空间，2 GB / 2 CPU，端口永不冲突 |
| **浏览器里的桌面** | XFCE + Chrome，经 noVNC 访问；想用鼠标点就用鼠标点 |
| **无需清理** | 用完就走，3 天后自动回收 |

不用注册、不用配密钥、不用开云账号、不产生任何账单。

> 用户名可随意取 6 位十六进制（如 `3f2a9c`）；用同一个名字再次登录会回到同一台机器。
> 还没有服务器？在任何一台 **x86_64 Linux** 机器上跑一条命令即可 —— 见[自己部署](#自己部署)。

[![build](https://github.com/yctech2026/ProvingPod/actions/workflows/build.yml/badge.svg)](https://github.com/yctech2026/ProvingPod/actions/workflows/build.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![status: experimental](https://img.shields.io/badge/status-experimental-orange.svg)](#项目状态)

## 沙箱、Agent、结论

AI 会写出大量「看起来对」的代码。要确认它究竟能不能**跑起来**，唯一的办法就是丢到一台干净的机器上真正执行一次 —— 而麻烦之处从来都是：去哪儿找这台机器，以及用完怎么清理。

ProvingPod 就是那台机器，并且可以被 Agent 用一次 SSH 调用驱动。它是一台**用于验证的沙箱**，不是开发机：你不需要维护它，它不保存你在意的状态，用完就把自己扔掉。

| 项目 | 一句话 |
|---|---|
| DevPod | 把我的开发环境装进容器（长期属于我） |
| RunPod | 按需租用 GPU（付费云） |
| **ProvingPod** | 把代码丢进来、证明它能跑 —— 一次性、隔离、零成本（自托管） |

## 为 Agent 循环而设计

- **一条命令，零准备。** 不用注册、不用 API Key、不用云账号、不用装 SDK。只要你的 Agent 会执行 `ssh`，它就能用。
- **默认非交互。** 直接传命令即可执行 —— 不需要 TTY，不需要回答任何提示。
- **退出码就是结论。** `ssh <hex>@<host> -p 6901 'npm test'` 会把命令自身的退出码原样带回，Agent 可以直接据此分支，不必去解析输出文本。
- **按需获得干净机器。** 换一个新的 hex 名字就是一台全新沙箱，这正是「验证可复现」的前提；用同一个名字则回到同一台机器，直到 TTL 回收。
- **用完即弃。** 闲置 pod 在 3 天后自动回收，不会留下任何需要 Agent 记录或清理的东西。
- **与你的机器隔离。** 独立的容器、网络命名空间与端口空间，上限 2 GB / 2 CPU —— 构建失败也碰不到你的笔记本。
- **自托管。** 生成的代码留在你自己的基础设施内，不会交给第三方云。

```text
   Agent 写出代码
          │
          ▼
   ssh <hex6>@<host> -p 6901 'npm install && npm test'
          │
          ├── 退出码 0  ──▶  验证通过：它跑起来了
          └── 退出码 ≠0 ──▶  失败输出原样返回
          │
          ▼
   pod 自行回收（TTL 3 天）—— 无需清理
```

### 在脚本里驱动它

```bash
POD=$(openssl rand -hex 3)                    # 每次运行都开一台全新沙箱
TARGET="$POD@<你的服务器>"

# 把工作目录传进去并跑测试（sftp/scp 不可用 —— 用 tar 管道）
tar czf - . | sshpass -p 123456 ssh -o StrictHostKeyChecking=accept-new \
    "$TARGET" -p 6901 'mkdir -p ~/src && tar xzf - -C ~/src && cd ~/src && npm install && npm test'

echo "verdict: $?"                            # 0 = 跑起来了
```

网关**关闭了公钥认证**（`PubkeyAuthentication no`），因此无人值守的运行需要提交默认密码 —— 即上面的 `sshpass`，或你的 Agent 本身已有的机制。

## 那些「在别处很难跑」的验证

验证之所以难，很少是因为 `npm test`，而是因为有些检查需要一台**机器**，而不只是一个脚本：

| 麻烦的检查 | 为什么在别处难做 | 在 proving pod 里 |
|---|---|---|
| **需要重启** | CI 任务一结束机器就被销毁，没有「重启之后」可以回头看 | pod 是长期存在的机器：启动、杀掉、再启动 —— 之后还能再登录回来，看什么状态留了下来 |
| **需要肉眼看** | 无头环境没有显示器，而你自己的笔记本恰恰是最不想被弄脏的那台 | 一个真实的 X 桌面（XFCE，1280x800），在浏览器里经 noVNC 观察并点击 |
| **需要被驱动** | 你没法连上一个根本没在运行的浏览器 | 镜像里自带 Chrome —— 打开 DevTools Protocol，用你自己的脚本驱动它 |

### 重启与生命周期

```bash
ssh 3f2a9c@<host> -p 6901 '
  cd ~/src && nohup node server.js > /tmp/app.log 2>&1 &   # 启动
  sleep 2 && curl -sf localhost:3000/health                # 有响应
  pkill -f server.js && sleep 1                            # 杀掉
  nohup node server.js > /tmp/app.log 2>&1 &               # 再启动
  sleep 2 && curl -sf localhost:3000/health                # 状态留下来了吗？
'
```

容器的文件系统与 pod 同寿命，因此应用写到磁盘上的东西在重启之后依然在 —— 这正是「重启验证」需要的。注意 pod 内**没有 init 系统**（没有 `systemd`），所以这是进程级重启验证，`systemctl` 不可用。

### 用眼睛看（GUI）

每个 pod 的桌面发布在随机主机端口上，从网关读取：

```bash
docker exec provingpod-gateway cat /data/ephemeral-users/3f2a9c.ports
# 6901/tcp =0.0.0.0:32769    <- 浏览器打开 http://<host>:32769/vnc.html
```

桌面属于用户 `dev`（你的 SSH shell 是 root），因此以该用户启动应用：

```bash
ssh 3f2a9c@<host> -p 6901 'nohup su - dev -c "DISPLAY=:0 google-chrome http://localhost:3000" &'
```

现在你可以看着窗口渲染出来、亲手点一遍 —— 这是纯文本日志给不了的结论。桌面密码默认为 `vncpass`。

### 驱动它（CDP）

Chrome 已经装好了，于是 pod 同时也是一个浏览器验证运行时：

```bash
ssh 3f2a9c@<host> -p 6901 '
  nohup google-chrome --headless=new --no-sandbox --remote-debugging-port=9222 \
    --user-data-dir=/tmp/cdp about:blank > /tmp/chrome.log 2>&1 &
  sleep 3
  curl -s localhost:9222/json/version          # DevTools 端点已就绪
'
```

该端点监听在 pod **内部**，所以驱动脚本也放在 pod 里跑 —— 在 pod 里装 puppeteer/playwright，或用 WebSocket 直接发 `Runtime.evaluate`。然后对控制台报错、失败请求或最终截图做断言，返回的是结论，而不是一大堆日志。

## 「沙箱」在这里意味着什么，不意味着什么

**意味着：** 每个 proving pod 都是独立容器，拥有自己的文件系统、网络命名空间、端口空间，以及 2 GB / 2 CPU 的上限。它与**你的**机器隔离，也不会被其它 pod 的意外干扰波及，并且会自行消失。

**不意味着：** 它不是对抗恶意代码的加固边界。网关挂载了宿主机 Docker socket（≈ 宿主机 root），且自带固定的公开默认密码。请用 ProvingPod 验证你大体信任的代码 —— 而不是用它关押对手。把任何不可信的东西指向它之前，请先读 **[SECURITY.md](SECURITY.md)**。

## 自己部署

ProvingPod 是自托管的，而只有一条约束决定它能跑在哪：pod 镜像是 **`linux/amd64` 专用**的，因为 Chrome 没有 arm64 的 `.deb`。其余一切由此推导：

| 宿主机 | 可用？ | 怎么做 |
|---|---|---|
| Linux x86_64 | ✅ | 本地构建两个镜像 —— 项目就是在这条路径上开发测试的 |
| Linux arm64（Graviton、树莓派等） | ✅ | 拉取预构建的 amd64 镜像；不构建，于是构建阶段没有任何模拟 |
| macOS（Apple Silicon） | ⚠️ | 预构建镜像去掉了构建环节，但网关还需要 Linux 侧的 daemon socket —— 见下 |
| Windows | ⚠️ | 未验证 |

```bash
sudo ./deploy/deploy.sh
```

在 x86_64 上这会构建两个镜像。在其他架构上，同一条命令会改为拉取本项目在 x86_64 runner 上发布好的镜像：

```bash
sudo ./deploy/deploy.sh --from-registry                            # 强制使用预构建镜像
PROVINGPOD_VERSION=v0.2.0 sudo ./deploy/deploy.sh --from-registry  # 指定某个版本
```

之所以要有这条路，是因为在 arm64 上构建 amd64 镜像意味着模拟 x86_64，而 QEMU 做这件事并不可靠 —— 它不会立刻报错，而是在构建到十分钟时才失败。完整的部署、配置与卸载说明见 **[docs/operations.md](docs/operations.md)**（英文）。

### 如果你在 Apple Silicon 上

用拉取代替构建，就绕开了 QEMU 的问题，但还有第二个前提：网关是以「兄弟容器」的方式创建 pod 的，因此需要宿主 Docker daemon 位于 `/var/run/docker.sock`。这个路径能否解析，取决于你的 Docker 虚拟机：

| | 虚拟机内的 `/var/run/docker.sock` | 能否挂载 |
|---|---|---|
| colima | 就是该虚拟机自己的 daemon socket | ✅ 已实测 —— 容器通过它驱动了 daemon |
| Docker Desktop | 是一个目录；宿主路径不在其虚拟机的命名空间里 | ❌ |

所以在 colima 下，`deploy.sh --from-registry` 在 macOS 上应当可用 —— socket 能解析，也能驱动 daemon。但自带的 `demo.sh` 仍然拒绝非 Linux 宿主，对 colima 来说这比实际需要更严。这最后一公里尚未做过端到端验证。

如果你宁愿在本地构建而不是拉取，那就用 Rosetta —— 在真实的 pod 构建中，QEMU 那条路挂了，Rosetta 那条路跑完了（3 分 58 秒，589 MB）：

```bash
# colima
colima start --arch aarch64 --vm-type=vz --vz-rosetta

# Docker Desktop：设置 → General → Apple Virtualization，
# 然后勾选 "Use Rosetta for x86_64/amd64 emulation on Apple Silicon"
```

`--arch` 必须保持 `aarch64`。若写成 `--arch x86_64`，colima 会**静默忽略** `--vz-rosetta` 并退回全系统 QEMU 模拟 —— 那正是你要避开的那种失败。

## 疑难排查（已知问题）

**`Exception: ('python3.12', '-c', 'import importlib.util; print(importlib.util.MAGIC_NUMBER)') failed with status code -11`** —— 常常在几行之后表现为 `dpkg: error processing package python3-oslo.serialization`，再往后是 `novnc` / `python3-novnc` 报错。这说明你正在用 QEMU 用户态模拟构建 amd64 的 pod 镜像，而 QEMU 在被模拟的进程里触发了段错误。它是**间歇性**的：只在一轮沉重的 `apt` 跑到几分钟时才出现，所以短循环压测未必能复现。这是**上游 QEMU 的 bug，不是 ProvingPod 的 bug** —— 同样的报错串在 `uv`、`rustc`、`.NET` 以及普通 `apt` 构建里都有报告。别再模拟了：

```bash
sudo ./deploy/deploy.sh --from-registry   # 用 x86_64 runner 构建好的镜像，全程无模拟
```

或者启用 Rosetta（[见上](#如果你在-apple-silicon-上)），或改在 x86_64 上构建、用 `--skip-build` 复用那些镜像。背景见 [docker/setup-qemu-action#188](https://github.com/docker/setup-qemu-action/issues/188)、[docker/desktop-feedback#382](https://github.com/docker/desktop-feedback/issues/382)、[qemu-project/qemu#3130](https://gitlab.com/qemu-project/qemu/-/work_items/3130)。

**`no matching manifest for linux/arm64/v8 in the manifest list entries`** —— 你让一台 arm64 宿主机去拉一个 amd64 专用的镜像。Docker 会按宿主平台匹配 manifest，而对于 manifest list，它**不会**退回到唯一可用的那个平台。`deploy.sh` 已替你加上 `--platform linux/amd64`；若你手工拉取，请照做。用 compose 时请设 `DOCKER_DEFAULT_PLATFORM=linux/amd64`（`demo.sh` 就是这么做的）。

**`/opt/gateway/provision.sh: /usr/bin/docker: cannot execute: required file not found`** —— 网关过去会挂载宿主机的 Docker CLI，而这只在宿主机与镜像架构一致时成立。现在 CLI 已内置在网关镜像里；如果你是从旧部署沿用了 volume 或 compose 文件，请去掉 `/usr/bin/docker` 那个挂载。

**密码正确却立刻 `Connection closed by remote host`** —— 认证通过了，但 PAM 的 *account* 钩子失败，于是登录被拒。开户就发生在那一步，所以 `sudo -n docker` 出错、pod 镜像不存在、或触发了 `LIMIT_REACHED` 配额，看起来都是这个现象。先看 `docker logs provingpod-gateway`。

## 项目状态

**实验性 / 早期。** 一个可用的、单人维护的原型。它的职责是*证明代码能跑*，而不是承载生产负载；接口可能随时变化。

> ⚠️ **未对公网做加固。** 网关挂载了宿主机 Docker socket（≈ 宿主机 root），且默认密码固定不变。请只在局域网内使用，或先阅读加固清单 —— 见 **[SECURITY.md](SECURITY.md)**（英文）。

## 常见问题

- **`sftp` / `scp` 用不了** —— 这是设计使然：每次登录都会直接跳进 pod。用 git 传文件，或通过 SSH 管道传 tar 包。
- **交互式登录需要 `-tt`** —— 使用 `ssh -tt <hex>@<host> -p 6901`；一次性命令则不需要，这正是沙箱可被脚本化的原因。
- **桌面在哪？** 每个 pod 的端口是随机的，网关会记录下来。见 [docs/operations.md](docs/operations.md#ports)（英文）。
- **碰到上限了？** 默认最多 8 个并发 pod，闲置的会被自动回收。
- **我的运行可复现吗？** 可以，如果你想的话：每次都取一个新的 hex 名字，你拿到的就是一台从未运行过任何东西的机器。

## 深入了解

> 以下文档目前均为英文。

- **底层原理** —— [docs/architecture.md](docs/architecture.md)
- **部署、配置、卸载** —— [docs/operations.md](docs/operations.md)
- **日常使用** —— [docs/service-usage.md](docs/service-usage.md)
- **安全模型与加固** —— [SECURITY.md](SECURITY.md)
- **迁移与设计历史** —— [docs/migration-notes.md](docs/migration-notes.md)
- **参与贡献** —— [CONTRIBUTING.md](CONTRIBUTING.md)

## 许可证

[MIT](LICENSE)。
