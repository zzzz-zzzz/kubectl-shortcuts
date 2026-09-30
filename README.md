[English](README.md) | [中文](README_CN.md)

# kubectl-shortcuts

A handful of kubectl shortcuts that replace full commands with a **namespace shorthand + pod keyword**, so everyday troubleshooting is just a few keystrokes.

```console
$ kcg ns1                                  # what pods live in this namespace?
kubectl get pod -n k8s-namespace1
NAME                        READY   STATUS      RESTARTS   AGE
pod1-7d9f8c4b5-abcde        2/2     Running     0          2d
pod2-6b8c7d9f4-fghij        1/1     Running     0          5h
batch-job-28145600-x7k2p    0/1     Completed   0          3h

$ kcgsv ns1                                # same for services
kubectl get services -n k8s-namespace1
NAME        TYPE        CLUSTER-IP     PORT(S)   AGE
pod1-svc    ClusterIP   10.96.12.34    80/TCP    12d

$ kcl pod2 ns1                             # single-container pod: just show the log
kubectl get pod -n k8s-namespace1 --no-headers
📄 日志: pod2-6b8c7d9f4-fghij  (ns=k8s-namespace1)
kubectl logs pod2-6b8c7d9f4-fghij -n k8s-namespace1
2026-09-23 09:00:01 INFO  app started
2026-09-23 09:00:02 INFO  connected to db

$ kcl pod1.c1 ns1                          # multi-container pod: pick one with .container
kubectl get pod -n k8s-namespace1 --no-headers
kubectl get pod pod1-7d9f8c4b5-abcde -n k8s-namespace1 -o 'jsonpath={.spec.containers[*].name}'
📄 日志: pod1-7d9f8c4b5-abcde / c1  (ns=k8s-namespace1)
kubectl logs pod1-7d9f8c4b5-abcde -c c1 -n k8s-namespace1
2026-09-23 09:00:01 INFO  app started

$ kclf pod1.c2 ns1                         # follow the log (Ctrl+C to stop)
kubectl get pod -n k8s-namespace1 --no-headers
kubectl get pod pod1-7d9f8c4b5-abcde -n k8s-namespace1 -o 'jsonpath={.spec.containers[*].name}'
📄 实时跟踪: pod1-7d9f8c4b5-abcde / c2  (ns=k8s-namespace1)
kubectl logs -f pod1-7d9f8c4b5-abcde -c c2 -n k8s-namespace1
2026-09-23 09:00:03 INFO  request handled
^C

$ kcex pod1.c1 ns1                         # get a shell inside the container (bash, else sh)
kubectl get pod -n k8s-namespace1 --no-headers
kubectl get pod pod1-7d9f8c4b5-abcde -n k8s-namespace1 -o 'jsonpath={.spec.containers[*].name}'
🚪 进入容器: pod1-7d9f8c4b5-abcde / c1  (ns=k8s-namespace1)
kubectl exec -it pod1-7d9f8c4b5-abcde -c c1 -n k8s-namespace1 -- /bin/sh -c 'command -v bash >/dev/null && exec bash || exec sh'
root@pod1-7d9f8c4b5-abcde:/usr/local/app#   # you are inside the container now

$ kcdes pod2 ns1                           # pod details
kubectl get pod -n k8s-namespace1 --no-headers
🔍 describe: pod2-6b8c7d9f4-fghij  (ns=k8s-namespace1)
kubectl describe pod pod2-6b8c7d9f4-fghij -n k8s-namespace1
Name:         pod2-6b8c7d9f4-fghij
Namespace:    k8s-namespace1
Status:       Running
```

The script's own messages (`📄 日志: ...`, `🚪 进入容器: ...`) are printed in Chinese; the commands it runs are plain kubectl.

## Features

- **Namespace shorthands**: `ns1` → `k8s-namespace1`, kept in one dictionary, no more typing full names.
- **Shorthands you never configured still work**: a shorthand missing from the dictionary is looked up once with `kubectl get ns`; a unique hit is remembered (FIFO, max 20 entries) and reused. Zero or multiple matches fail loudly instead of guessing.
- **Pod keywords**: no more copy-pasting pod names — give a keyword (e.g. `kcl job xw`); when several match, all candidates are listed.
- **Multi-container support**: the `<pod_keyword>.<container_keyword>` syntax adds `-c` for you, no more `a container name must be specified`.
- **Command echo**: the real kubectl command is printed before it runs, handy for learning, copying, or pasting into a ticket (`kctrace off` silences it).
- **Thin wrapper only**: every command just assembles a kubectl command; the only one that changes local state is `kcuse` (switching the kubeconfig default namespace).

## Installation

```bash
# 1. put the script in your home directory
cp .kube-shortcuts.sh ~/.kube-shortcuts.sh

# 2. source it from ~/.bashrc
echo '[ -f ~/.kube-shortcuts.sh ] && source ~/.kube-shortcuts.sh' >> ~/.bashrc

# 3. reload
source ~/.bashrc
```

Requires **bash 4.0+** (associative arrays). Linux, WSL and Git Bash are fine; macOS ships bash 3.2, so `brew install bash` is needed there.

## Configuring the namespace dictionary

Edit `NS_MAP` at the top of the script — one line per shorthand:

```bash
declare -A NS_MAP=(
    [ns1]="k8s-namespace1"
    [ns2]="k8s-namespace2"
    # To add one: just append a line
)
```

Run `source ~/.kube-shortcuts.sh` to apply, and `kcns` to list every shorthand.

### Auto-discovery for shorthands that are not in the dictionary

A shorthand missing from `NS_MAP` is matched as a substring against the output of `kubectl get ns`:

- **exactly one match** → it is cached into `NS_MAP` and the command continues;
- **no match** → error plus the full namespace list, exit code `1`;
- **two or more matches** → error plus the candidates, exit code `1`.

```console
$ kcg prod                                  # prod is not configured, only k8s-prod matches
kubectl get ns --no-headers
📌 已记住简写: prod → k8s-prod
kubectl get pod -n k8s-prod
NAME                        READY   STATUS      RESTARTS   AGE
pod1-7d9f8c4b5-abcde        2/2     Running     0          2d

$ kcg prod                                  # second time: straight from the cache, no ns lookup
kubectl get pod -n k8s-prod
NAME                        READY   STATUS      RESTARTS   AGE
pod1-7d9f8c4b5-abcde        2/2     Running     0          2d

$ kcg dev                                   # dev matches both k8s-dev-app and k8s-dev-db
kubectl get ns --no-headers
❌ 简写 'dev' 匹配到 2 个命名空间，无法自动选择
   全部匹配：
     - k8s-dev-app
     - k8s-dev-db
   请改用更精确的简写，或在 NS_MAP 里显式写死
```

The cache is **FIFO**, capped at 20 entries: the oldest auto-discovered entry is dropped first (tune with `KCS_NS_CACHE_MAX`). Entries you wrote into `NS_MAP` yourself are never evicted. `kcns` marks what came from auto-discovery:

```console
$ kcns
📋 命名空间字典：
  prod   → k8s-prod (自动发现)
  ns1    → k8s-namespace1
  ns2    → k8s-namespace2
🧠 自动发现缓存：1/20（先进先出）
```

Note the cache lives in the current shell session only — a new terminal looks the namespace up again. Write it into `NS_MAP` if you want it to stick.

## Command reference

`<ns_shortname>` is a namespace shorthand and is replaced by `<ns_fullname>`; a shorthand that is not in the dictionary is auto-discovered first (see above) and fails when it matches nothing or several namespaces.

| Command | What it does | Command actually run |
| --- | --- | --- |
| `kcg <ns_shortname>` | list pods | `kubectl get pod -n <ns_fullname>` |
| `kcgsv <ns_shortname>` | list services | `kubectl get services -n <ns_fullname>` |
| `kcl <pod_keyword>[.<container_keyword>] <ns_shortname>` | show logs | `kubectl logs <pod_fullname> [-c <container_fullname>] -n <ns_fullname>` |
| `kclf <pod_keyword>[.<container_keyword>] <ns_shortname>` | follow logs | `kubectl logs -f <pod_fullname> [-c <container_fullname>] -n <ns_fullname>` |
| `kcex <pod_keyword>[.<container_keyword>] <ns_shortname>` | open a shell in a container | `kubectl exec -it <pod_fullname> [-c <container_fullname>] -n <ns_fullname> -- /bin/sh` |
| `kcdes <pod_keyword> <ns_shortname>` | describe a pod | `kubectl describe pod <pod_fullname> -n <ns_fullname>` |
| `kcns` | list defined shorthands | no kubectl call |
| `kcuse <ns_shortname>` | switch kubectl's default namespace | `kubectl config set-context --current --namespace=<ns_fullname>` |
| `kctrace [on\|off]` | toggle command echo | no kubectl call |

## Usage examples

```bash
kcg ns1                 # what pods exist here (use it first when you don't know the name)
kcgsv ns1               # what services exist

kcl pod1 ns1            # single-container pod: read the log
kcl pod1.c1 ns1         # multi-container pod: pick the one whose name contains c1
kclf pod1.c1 ns1        # same, but follow the stream

kcex pod1 ns1           # open a shell (bash if available, otherwise sh)
kcex pod1.c1 ns1        # open a shell in a specific container

kcdes pod1 ns1          # pod details
kcns                    # what shorthands are defined
kctrace off             # silence the command echo
```

## Keyword matching rules

Pods and containers are matched as **substrings** (`grep`, basic regex), not exactly:

- the keyword `job` matches `job-alpha-6f9c8d7b4-k2m4p`;
- because it is a regex, metacharacters like `.`, `*`, `[` are special — spell the whole name out when you need an exact hit;
- **several matches**: the first one wins, and stderr tells you how many matched plus the full candidate list;
- **no match**: an error plus every pod in the namespace (or every container in the pod), exit code `1`.

In practice:

```console
$ kcl pod ns1                              # matches both pod1-… and pod2-…
kubectl get pod -n k8s-namespace1 --no-headers
⚠️  匹配到 2 个 pod，已选择第一个: pod1-7d9f8c4b5-abcde
   全部匹配：
     - pod1-7d9f8c4b5-abcde
     - pod2-6b8c7d9f4-fghij
📄 日志: pod1-7d9f8c4b5-abcde  (ns=k8s-namespace1)
kubectl logs pod1-7d9f8c4b5-abcde -n k8s-namespace1
2026-09-23 09:00:01 INFO  app started

$ kcl nope ns1                             # nothing matched: error + full pod list, exit code 1
kubectl get pod -n k8s-namespace1 --no-headers
❌ 未在 k8s-namespace1 找到包含 'nope' 的 pod
kubectl get pod -n k8s-namespace1
NAME                        READY   STATUS      RESTARTS   AGE
pod1-7d9f8c4b5-abcde        2/2     Running     0          2d
pod2-6b8c7d9f4-fghij        1/1     Running     0          5h
batch-job-28145600-x7k2p    0/1     Completed   0          3h

$ kcex pod1.zzz ns1                        # container keyword not found: list the pod's containers
kubectl get pod -n k8s-namespace1 --no-headers
kubectl get pod pod1-7d9f8c4b5-abcde -n k8s-namespace1 -o 'jsonpath={.spec.containers[*].name}'
❌ pod 'pod1-7d9f8c4b5-abcde' 中未找到包含 'zzz' 的容器
   该 pod 的全部容器：
     - c1
     - c2
```

## Multi-container pods

When a pod runs several containers, `kubectl logs` / `kubectl exec` without `-c` fails outright. Write the argument as `<pod_keyword>.<container_keyword>`:

```bash
kcex pod1.c1 ns1        # → kubectl exec -it <pod_fullname> -c <container_fullname> -n <ns_fullname> -- /bin/sh
```

The argument is split at the **last dot** — container names cannot contain a dot, so everything after the last dot is the container keyword. That also keeps pod names containing dots working:

```bash
kcex my.pod-1.main ns1  # pod keyword = my.pod-1, container keyword = main
```

With no dot the behaviour is exactly as before (no `-c` is added).

## Command echo

On by default: the real kubectl command is printed before it runs. It goes to **stderr**, so it never pollutes stdout:

```bash
kcl pod1 ns1 > app.log                  # app.log holds the 📄 line and the log body, never the echoed commands
pod=$(_find_pod pod1 k8s-namespace1)    # the variable holds the pod name only
```

Toggle it with:

```bash
kctrace off     # silence the echo
kctrace on      # turn it back on
kctrace         # show the current state
```

With the echo off, only the result is left:

```console
$ kctrace off
🔇 命令回显：已关闭
$ kcg ns1
NAME                        READY   STATUS      RESTARTS   AGE
pod1-7d9f8c4b5-abcde        2/2     Running     0          2d
pod2-6b8c7d9f4-fghij        1/1     Running     0          5h
batch-job-28145600-x7k2p    0/1     Completed   0          3h
```

You can also make it permanent from `~/.bashrc`: `export KCS_TRACE=0`.

## Design notes

- **Echo goes to stderr**: `_trace` only prints, `_run` prints and executes. Keeping them apart is what lets `$(...)` and pipes stay clean.
- **Failures come with context**: `_find_pod` / `_find_container` list the candidates when nothing matches, so you rarely need a second command to find out why.
- **One lookup path**: `kcl` / `kclf` / `kcex` / `kcdes` all go through the same `_find_pod`, so matching rules, messages and exit codes stay identical.

## Internal helpers

Besides the public commands there is a set of underscore-prefixed helpers (every `kc*` command is built on them):

| Helper | Purpose |
| --- | --- |
| `_ns <ns_shortname>` | shorthand → full name, result goes into the global `_NS_FULL`; falls back to `kubectl get ns` and caches the hit |
| `_ns_cache_add <ns_shortname> <ns_fullname>` | add to the auto-discovery cache, FIFO-evicting past `KCS_NS_CACHE_MAX` |
| `_ns_cache_mark <ns_shortname>` | prints ` (自动发现)` for auto-discovered keys, empty otherwise |
| `_quote <args...>` | shell-quote the arguments into a copy-pasteable one-liner |
| `_trace <args...>` | echo the command (stderr, controlled by `KCS_TRACE`) |
| `_run <args...>` | echo, then execute |
| `_find_pod <pod_keyword> <ns_fullname>` | print the first matching pod name |
| `_find_container <container_keyword> <pod_fullname> <ns_fullname>` | print the first matching container name |
| `_split_pod_key <pod_keyword>[.<container_keyword>]` | extract the pod keyword |
| `_split_container_key <pod_keyword>[.<container_keyword>]` | extract the container keyword (empty when there is no dot) |

Note that `_ns` writes its result into `_NS_FULL` instead of echoing it, and must be called directly in the current shell — `ns=$(_ns ...)` would run in a subshell and the auto-discovery cache would be lost.

## Layout

```
.kube-shortcuts.sh        # the script itself; this is the tracked copy (sample namespaces)
prod/.kube-shortcuts.sh   # the copy actually used locally, real namespaces, excluded by .gitignore
README.md                 # this file (English)
README_CN.md              # Chinese version
```

## Known limitations

- The script has no `set -u` protection: with `set -u` in your shell, `_ns` may raise `unbound variable` for an unknown shorthand instead of the friendly message.
- The auto-discovery cache only exists for the current shell session; a new terminal looks the namespace up again. Put it in `NS_MAP` to make it permanent.
- A shorthand that is missing from the dictionary costs one extra `kubectl get ns` (nothing once it is cached). That lookup is a `grep` substring match too, so `dev` matches both `k8s-dev-app` and `k8s-dev-db`.
- Keywords are `grep` semantics: regex metacharacters are interpreted (see "Keyword matching rules").
- Requires `kubectl` on `PATH` plus `grep` / `awk` / `sed` / `head` / `tr` (on Windows, use Git Bash or WSL).
- The script's own output messages are in Chinese; only the commands it runs are plain kubectl.
