# kubectl-shortcuts

一组 kubectl 快捷指令，用「命名空间简写 + pod 关键字」代替每次敲完整命令，日常排查只需要敲很短的一段。

```console
$ kcg ns1                                  # 这个命名空间里有哪些 pod
kubectl get pod -n k8s-namespace1
NAME                        READY   STATUS      RESTARTS   AGE
pod1-7d9f8c4b5-abcde        2/2     Running     0          2d
pod2-6b8c7d9f4-fghij        1/1     Running     0          5h
batch-job-28145600-x7k2p    0/1     Completed   0          3h

$ kcgsv ns1                                # service 同理
kubectl get services -n k8s-namespace1
NAME        TYPE        CLUSTER-IP     PORT(S)   AGE
pod1-svc    ClusterIP   10.96.12.34    80/TCP    12d

$ kcl pod2 ns1                             # pod 里只有一个容器，直接看日志
kubectl get pod -n k8s-namespace1 --no-headers
📄 日志: pod2-6b8c7d9f4-fghij  (ns=k8s-namespace1)
kubectl logs pod2-6b8c7d9f4-fghij -n k8s-namespace1
2026-09-23 09:00:01 INFO  app started
2026-09-23 09:00:02 INFO  connected to db

$ kcl pod1.c1 ns1                          # pod 里有多个容器，用 .容器名 指定
kubectl get pod -n k8s-namespace1 --no-headers
kubectl get pod pod1-7d9f8c4b5-abcde -n k8s-namespace1 -o 'jsonpath={.spec.containers[*].name}'
📄 日志: pod1-7d9f8c4b5-abcde / c1  (ns=k8s-namespace1)
kubectl logs pod1-7d9f8c4b5-abcde -c c1 -n k8s-namespace1
2026-09-23 09:00:01 INFO  app started

$ kclf pod1.c2 ns1                         # 实时跟踪（Ctrl+C 退出）
kubectl get pod -n k8s-namespace1 --no-headers
kubectl get pod pod1-7d9f8c4b5-abcde -n k8s-namespace1 -o 'jsonpath={.spec.containers[*].name}'
📄 实时跟踪: pod1-7d9f8c4b5-abcde / c2  (ns=k8s-namespace1)
kubectl logs -f pod1-7d9f8c4b5-abcde -c c2 -n k8s-namespace1
2026-09-23 09:00:03 INFO  request handled
^C

$ kcex pod1.c1 ns1                         # 进容器排查（优先 bash，没有则退回 sh）
kubectl get pod -n k8s-namespace1 --no-headers
kubectl get pod pod1-7d9f8c4b5-abcde -n k8s-namespace1 -o 'jsonpath={.spec.containers[*].name}'
🚪 进入容器: pod1-7d9f8c4b5-abcde / c1  (ns=k8s-namespace1)
kubectl exec -it pod1-7d9f8c4b5-abcde -c c1 -n k8s-namespace1 -- /bin/sh -c 'command -v bash >/dev/null && exec bash || exec sh'
root@pod1-7d9f8c4b5-abcde:/usr/local/app#   # 已经在容器里了

$ kcdes pod2 ns1                           # 看 pod 详情
kubectl get pod -n k8s-namespace1 --no-headers
🔍 describe: pod2-6b8c7d9f4-fghij  (ns=k8s-namespace1)
kubectl describe pod pod2-6b8c7d9f4-fghij -n k8s-namespace1
Name:         pod2-6b8c7d9f4-fghij
Namespace:    k8s-namespace1
Status:       Running
```

## 特性

- **命名空间简写**：`ns1` → `k8s-namespace1`，一串字典搞定，不用记全名。
- **没配过的简写也能用**：不在字典里的简写会拿 `kubectl get ns` 反查一次，唯一命中就记住（FIFO 上限 20 条），下次直接用；匹配到 0 个或多个都会明确报错，不瞎猜。
- **pod 关键字**：不用复制粘贴 pod 全名，给个关键字（如 `kcl job xw`）即可，匹配到多个会提示并列出候选。
- **多容器支持**：`<pod_keyword>.<container_keyword>` 语法，pod 里有多个容器时自动补 `-c`，不再报 `a container name must be specified`。
- **命令回显**：每条指令执行前打印真正跑的那条 kubectl 命令，方便学习、复制、贴给别人排查（可用 `kctrace off` 关掉）。
- **只做包装**：所有命令都只是把参数拼成一条 kubectl 命令，不会额外改动集群；唯一会改本地状态的是 `kcuse`（切换 kubeconfig 默认命名空间）。

## 安装

```bash
# 1. 把脚本放到家目录
cp .kube-shortcuts.sh ~/.kube-shortcuts.sh

# 2. 让 ~/.bashrc 引入它
echo '[ -f ~/.kube-shortcuts.sh ] && source ~/.kube-shortcuts.sh' >> ~/.bashrc

# 3. 生效
source ~/.bashrc
```

环境要求：**bash 4.0+**（用到关联数组 `declare -A`）。Linux、WSL、Git Bash 自带版本都满足；macOS 自带的 bash 3.2 不支持，需要 `brew install bash`。

## 配置命名空间字典

编辑脚本顶部的 `NS_MAP`，加一行就是一个新简写：

```bash
declare -A NS_MAP=(
    [ns1]="k8s-namespace1"
    [ns2]="k8s-namespace2"
    # 新增：直接加一行即可
)
```

改完 `source ~/.kube-shortcuts.sh` 生效，用 `kcns` 可以列出当前所有简写。

### 简写没配过也能用：自动发现

`NS_MAP` 里没有的简写，会拿它去 `kubectl get ns` 的结果里做一次子串匹配：

- **唯一命中** → 记进缓存（`NS_MAP`），本次命令接着往下执行；
- **一个都没匹配到** → 报错并列出全部命名空间，返回 `1`；
- **匹配到两个及以上** → 报错并列出候选，返回 `1`。

```console
$ kcg prod                                  # prod 不在字典里，但只有 k8s-prod 匹配
kubectl get ns --no-headers
📌 已记住简写: prod → k8s-prod
kubectl get pod -n k8s-prod
NAME                        READY   STATUS      RESTARTS   AGE
pod1-7d9f8c4b5-abcde        2/2     Running     0          2d

$ kcg prod                                  # 第二次直接用缓存，不再查 ns
kubectl get pod -n k8s-prod
NAME                        READY   STATUS      RESTARTS   AGE
pod1-7d9f8c4b5-abcde        2/2     Running     0          2d

$ kcg dev                                   # dev 同时匹配 k8s-dev-app 和 k8s-dev-db
kubectl get ns --no-headers
❌ 简写 'dev' 匹配到 2 个命名空间，无法自动选择
   全部匹配：
     - k8s-dev-app
     - k8s-dev-db
   请改用更精确的简写，或在 NS_MAP 里显式写死
```

缓存按**先进先出**淘汰，最多 20 条，超出就丢弃最早记下的那条（可用 `KCS_NS_CACHE_MAX` 调整）；手写在 `NS_MAP` 里的条目永远不会被淘汰。`kcns` 会把自动发现的条目标出来：

```console
$ kcns
📋 命名空间字典：
  prod   → k8s-prod (自动发现)
  ns1    → k8s-namespace1
  ns2    → k8s-namespace2
🧠 自动发现缓存：1/20（先进先出）
```

注意缓存只活在当前 shell 会话里，新开终端会重新查一次；想永久生效就把它写进 `NS_MAP`。

## 命令一览

`<ns_shortname>` 是命名空间简写，会被换成 `<ns_fullname>`；字典里没有的简写会先自动反查（见上文「自动发现」），查不到或匹配到多个则报错退出。

| 命令 | 作用 | 实际执行的命令 |
| --- | --- | --- |
| `kcg <ns_shortname>` | 列出 pod | `kubectl get pod -n <ns_fullname>` |
| `kcgsv <ns_shortname>` | 列出 service | `kubectl get services -n <ns_fullname>` |
| `kcl <pod_keyword>[.<container_keyword>] <ns_shortname>` | 查看日志 | `kubectl logs <pod_fullname> [-c <container_fullname>] -n <ns_fullname>` |
| `kclf <pod_keyword>[.<container_keyword>] <ns_shortname>` | 实时跟踪日志 | `kubectl logs -f <pod_fullname> [-c <container_fullname>] -n <ns_fullname>` |
| `kcex <pod_keyword>[.<container_keyword>] <ns_shortname>` | 进入容器 | `kubectl exec -it <pod_fullname> [-c <container_fullname>] -n <ns_fullname> -- /bin/sh` |
| `kcdes <pod_keyword> <ns_shortname>` | 查看 pod 详情 | `kubectl describe pod <pod_fullname> -n <ns_fullname>` |
| `kcns` | 列出已定义的命名空间简写 | 不调用 kubectl |
| `kcuse <ns_shortname>` | 切换 kubectl 默认命名空间 | `kubectl config set-context --current --namespace=<ns_fullname>` |
| `kctrace [on\|off]` | 开关命令回显 | 不调用 kubectl |

## 用法示例

```bash
kcg ns1                 # 这个命名空间里有哪些 pod（不确定 pod 叫什么时先看它）
kcgsv ns1               # 有哪些 service

kcl pod1 ns1            # pod 内只有一个容器：直接看日志
kcl pod1.c1 ns1         # pod 内有多个容器：指定名字包含 c1 的那个
kclf pod1.c1 ns1        # 同上，但实时跟踪（follow）

kcex pod1 ns1           # 进容器（优先 bash 交互，没有则退回 sh）
kcex pod1.c1 ns1        # 指定容器进入

kcdes pod1 ns1          # 看 pod 详情
kcns                    # 有哪些命名空间简写
kctrace off             # 关掉命令回显
```

## 关键字匹配规则

pod 和容器都是**子串匹配**（底层是 `grep`，属于基本正则），不是精确匹配：

- 关键字 `job` 能匹配到 `job-alpha-6f9c8d7b4-k2m4p`。
- 因为走的是正则，关键字里的 `.`、`*`、`[` 等元字符会有特殊含义，需要精确匹配时请写完整名字。
- **匹配到多个**：取第一个，并在 stderr 提示匹配到几个、列出全部候选。
- **一个都没匹配到**：报错，并列出该命名空间下全部 pod（或该 pod 的全部容器），返回码 `1`。

实际长这样：

```console
$ kcl pod ns1                              # pod 同时匹配到 pod1-… 和 pod2-…
kubectl get pod -n k8s-namespace1 --no-headers
⚠️  匹配到 2 个 pod，已选择第一个: pod1-7d9f8c4b5-abcde
   全部匹配：
     - pod1-7d9f8c4b5-abcde
     - pod2-6b8c7d9f4-fghij
📄 日志: pod1-7d9f8c4b5-abcde  (ns=k8s-namespace1)
kubectl logs pod1-7d9f8c4b5-abcde -n k8s-namespace1
2026-09-23 09:00:01 INFO  app started

$ kcl nope ns1                             # 一个都没匹配到：报错 + 列出全部 pod，返回码 1
kubectl get pod -n k8s-namespace1 --no-headers
❌ 未在 k8s-namespace1 找到包含 'nope' 的 pod
kubectl get pod -n k8s-namespace1
NAME                        READY   STATUS      RESTARTS   AGE
pod1-7d9f8c4b5-abcde        2/2     Running     0          2d
pod2-6b8c7d9f4-fghij        1/1     Running     0          5h
batch-job-28145600-x7k2p    0/1     Completed   0          3h

$ kcex pod1.zzz ns1                        # 容器关键字没匹配到：列出该 pod 的全部容器
kubectl get pod -n k8s-namespace1 --no-headers
kubectl get pod pod1-7d9f8c4b5-abcde -n k8s-namespace1 -o 'jsonpath={.spec.containers[*].name}'
❌ pod 'pod1-7d9f8c4b5-abcde' 中未找到包含 'zzz' 的容器
   该 pod 的全部容器：
     - c1
     - c2
```

## 多容器 pod

pod 里跑多个容器时，`kubectl logs` / `kubectl exec` 不带 `-c` 会直接报错。这时把参数写成 `<pod_keyword>.<container_keyword>` 即可：

```bash
kcex pod1.c1 ns1        # → kubectl exec -it <pod_fullname> -c <container_fullname> -n <ns_fullname> -- /bin/sh
```

解析规则是**按最后一个点切分**——容器名本身不允许含点，所以最后一个点之后一定是容器关键字；这样即使 pod 名字里带点也能正确解析：

```bash
kcex my.pod-1.main ns1  # pod 关键字 = my.pod-1，容器关键字 = main
```

不写点号时行为和以前完全一致（不加 `-c`）。

## 命令回显

默认开启：每条指令执行前，把真正执行的 kubectl 命令打印出来。回显走 **stderr**，所以不会污染标准输出：

```bash
kcl pod1 ns1 > app.log                  # app.log 里只有 📄 提示行和日志正文，混不进回显的命令行
pod=$(_find_pod pod1 k8s-namespace1)    # 变量里只有 pod 名
```

开关：

```bash
kctrace off     # 关掉回显（排查完可以安静地用）
kctrace on      # 打开
kctrace         # 查看当前状态
```

关掉之后，输出里就只剩结果本身：

```console
$ kctrace off
🔇 命令回显：已关闭
$ kcg ns1
NAME                        READY   STATUS      RESTARTS   AGE
pod1-7d9f8c4b5-abcde        2/2     Running     0          2d
pod2-6b8c7d9f4-fghij        1/1     Running     0          5h
batch-job-28145600-x7k2p    0/1     Completed   0          3h
```

也可以在 `~/.bashrc` 里永久设定：`export KCS_TRACE=0`。

## 设计要点

- **回显走 stderr**：`_trace` 只负责打印，`_run` 负责「打印 + 执行」，两者分开才能让 `$(...)` 取值和管道不被回显打扰。
- **失败时给足上下文**：`_find_pod` / `_find_container` 在找不到匹配时会顺手把候选列表打出来，省得再敲一条命令去查。
- **共用查找逻辑**：`kcl` / `kclf` / `kcex` / `kcdes` 都走同一个 `_find_pod`，所以匹配规则、提示文案、退出码完全一致。

## 内部函数

对外命令之外，脚本里还有一组以下划线开头的内部函数（`kc*` 命令都建立在它们之上）：

| 函数 | 作用 |
| --- | --- |
| `_ns <ns_shortname>` | 简写 → 全名，结果写进全局 `_NS_FULL`；字典没有就反向查 `kubectl get ns` 并缓存 |
| `_ns_cache_add <ns_shortname> <ns_fullname>` | 写入自动发现缓存，超过 `KCS_NS_CACHE_MAX` 就 FIFO 淘汰 |
| `_ns_cache_mark <ns_shortname>` | 自动发现的简写输出 ` (自动发现)`，手写的输出空 |
| `_quote <args...>` | 把参数按 shell 语法引用成一行可直接复制的命令 |
| `_trace <args...>` | 回显命令（走 stderr，受 `KCS_TRACE` 控制） |
| `_run <args...>` | 回显 + 执行 |
| `_find_pod <pod_keyword> <ns_fullname>` | 输出第一个匹配的 pod 全名 |
| `_find_container <container_keyword> <pod_fullname> <ns_fullname>` | 输出第一个匹配的容器名 |
| `_split_pod_key <pod_keyword>[.<container_keyword>]` | 取出 pod 关键字 |
| `_split_container_key <pod_keyword>[.<container_keyword>]` | 取出容器关键字（没有点时输出空） |

## 目录结构

```
.kube-shortcuts.sh        # 脚本本体，版本管理的是这份（示例命名空间）
prod/.kube-shortcuts.sh   # 本地实际使用的那份，含真实命名空间，已被 .gitignore 排除
README.md
```

## 已知限制

- 脚本没有 `set -u` 防护：如果你的 shell 开启了 `set -u`，`_ns` 在遇到未定义的简写时可能先抛 `unbound variable` 而不是友好提示。
- 自动发现缓存只存在于当前 shell 会话，新开终端会重新查一次 `kubectl get ns`；永久生效请写进 `NS_MAP`。
- 简写不在字典里时会多一次 `kubectl get ns`（命中缓存后不再查询）。反查同样是 `grep` 子串语义，`dev` 会同时匹配 `k8s-dev-app` 和 `k8s-dev-db`。
- 关键字是 `grep` 语义，含正则元字符时会按正则解释（见上文「关键字匹配规则」）。
- 依赖 `kubectl` 在 `PATH` 中，以及 `grep` / `awk` / `sed` / `head` / `tr` 等基础工具（Windows 下建议在 Git Bash 或 WSL 中使用）。
