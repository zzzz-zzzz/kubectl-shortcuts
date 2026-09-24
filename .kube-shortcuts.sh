#!/usr/bin/env bash
# ============================================
# kubectl 快捷指令 & 命名空间字典
# 由 ~/.bashrc 引入
#
# 命令回显：每条指令执行前会打印实际执行的 kubectl 命令（输出到 stderr，
# 不影响 stdout 的取值与管道）。默认开启。
# 关闭/开启：kctrace off / kctrace on，或设置环境变量 KCS_TRACE=0
# ============================================

# ---------- 命名空间字典 ----------
declare -A NS_MAP=(
    [ns1]="k8s-namespace1"
    [ns2]="k8s-namespace2"
    # 新增：直接加一行即可
)

# 命令回显开关（1=打印，0=安静）
KCS_TRACE="${KCS_TRACE:-1}"

# 自动发现缓存：简写不在 NS_MAP 里时，用 kubectl get ns 按关键字反查，
# 唯一命中就记下来，下次直接用。FIFO 上限 20 条（可用 KCS_NS_CACHE_MAX 调整）
KCS_NS_CACHE_MAX="${KCS_NS_CACHE_MAX:-20}"
declare -a NS_CACHE=()   # 只记录自动缓存的简写（按加入顺序），手写的不参与淘汰

# 解析简写为完整命名空间，结果写进全局变量 _NS_FULL
# 用法：_ns <ns_shortname> || return 1; ns="$_NS_FULL"
# 说明：必须在当前 shell 直接调用，不要写成 ns=$(_ns ...) —— 命令替换是子 shell，
#      自动缓存会写丢。先查 NS_MAP，没查到就用 kubectl get ns 按关键字反查，
#      唯一命中则缓存后返回；没匹配到、或匹配到多个都会报错并返回 1
_ns() {
    local key="$1"
    _NS_FULL=""

    # 1) 字典里已经有（手写的，或之前自动缓存的）
    if [ -n "${NS_MAP[$key]}" ]; then
        _NS_FULL="${NS_MAP[$key]}"
        return 0
    fi

    # 2) 没查到：去集群里按关键字反查命名空间
    local matches
    _trace kubectl get ns --no-headers
    matches=$(kubectl get ns --no-headers 2>/dev/null | grep "$key" | awk '{print $1}')

    local count
    count=$(echo "$matches" | grep -c .)

    if [ "$count" -eq 0 ]; then
        echo "❌ 未找到包含 '$key' 的命名空间" >&2
        echo "   已定义简写: ${!NS_MAP[*]}" >&2
        _run kubectl get ns >&2
        return 1
    fi

    if [ "$count" -gt 1 ]; then
        echo "❌ 简写 '$key' 匹配到 $count 个命名空间，无法自动选择" >&2
        echo "   全部匹配：" >&2
        echo "$matches" | sed 's/^/     - /' >&2
        echo "   请改用更精确的简写，或在 NS_MAP 里显式写死" >&2
        return 1
    fi

    # 3) 唯一命中：记住它，下次就不用再查集群了
    local ns
    ns=$(echo "$matches" | head -1)
    _ns_cache_add "$key" "$ns"
    echo "📌 已记住简写: $key → $ns" >&2
    _NS_FULL="$ns"
    return 0
}

# _ns_cache_add <ns_shortname> <ns_fullname>
# 说明：把自动发现的简写写进 NS_MAP，并记录到 FIFO 队列；超过上限就淘汰最早的一条
_ns_cache_add() {
    local key="$1"
    local ns="$2"

    NS_MAP[$key]="$ns"
    NS_CACHE+=("$key")

    local oldest
    while [ "${#NS_CACHE[@]}" -gt "$KCS_NS_CACHE_MAX" ]; do
        oldest="${NS_CACHE[0]}"
        unset "NS_MAP[$oldest]"
        if [ "${#NS_CACHE[@]}" -gt 1 ]; then
            NS_CACHE=("${NS_CACHE[@]:1}")
        else
            NS_CACHE=()
        fi
    done
}

# _ns_cache_mark <ns_shortname>  →  自动缓存的简写输出 " (自动发现)"，手写的输出空
_ns_cache_mark() {
    local key="$1"
    local c
    if [ "${#NS_CACHE[@]}" -gt 0 ]; then
        for c in "${NS_CACHE[@]}"; do
            if [ "$c" = "$key" ]; then
                printf ' (自动发现)'
                return 0
            fi
        done
    fi
}

# ---------- 内部函数 ----------

# 把参数按 shell 语法引用，拼成可直接复制执行的一行命令
_quote() {
    local arg
    local -a out=()
    for arg in "$@"; do
        if [[ -z "$arg" || "$arg" == *[!A-Za-z0-9_./:=@%+-]* ]]; then
            out+=("'${arg//\'/\'\\\'\'}'")
        else
            out+=("$arg")
        fi
    done
    printf '%s' "${out[*]}"
}

# 回显命令（走 stderr，不进入 stdout/管道）
_trace() {
    [ "${KCS_TRACE:-1}" = "0" ] && return 0
    printf '%s\n' "$(_quote "$@")" >&2
}

# 回显 + 执行
_run() {
    _trace "$@"
    "$@"
}

# _find_pod <pod_keyword> <ns_fullname>  →  输出第一个匹配的 <pod_fullname>
# 说明：在 kubectl get pod -n <ns_fullname> --no-headers 的结果里按关键字筛选
# 补充：匹配到多个时提示并列出全部候选；一个都没匹配到则报错、列出全部 pod 并返回 1
# 备注：kcl / kclf / kcex / kcdes 共用此逻辑
_find_pod() {
    local keyword="$1"
    local ns="$2"

    # 匹配的 pod 列表
    local matches
    _trace kubectl get pod -n "$ns" --no-headers
    matches=$(kubectl get pod -n "$ns" --no-headers 2>/dev/null \
              | grep "$keyword" | awk '{print $1}')

    local count
    count=$(echo "$matches" | grep -c .)

    if [ "$count" -eq 0 ]; then
        echo "❌ 未在 $ns 找到包含 '$keyword' 的 pod" >&2
        _run kubectl get pod -n "$ns" >&2
        return 1
    fi

    # 取第一个
    local pod
    pod=$(echo "$matches" | head -1)

    if [ "$count" -gt 1 ]; then
        echo "⚠️  匹配到 $count 个 pod，已选择第一个: $pod" >&2
        echo "   全部匹配：" >&2
        echo "$matches" | sed 's/^/     - /' >&2
    fi

    echo "$pod"
}

# _find_container <container_keyword> <pod_fullname> <ns_fullname>  →  输出第一个匹配的 <container_fullname>
# 说明：在 kubectl get pod <pod_fullname> -n <ns_fullname> -o jsonpath='{.spec.containers[*].name}' 里按关键字筛选
# 补充：匹配到多个时提示并列出全部候选；一个都没匹配到则报错、列出该 pod 的全部容器并返回 1
# 备注：kcex 在指定了 <container_keyword> 时使用
_find_container() {
    local keyword="$1"
    local pod="$2"
    local ns="$3"

    # 匹配的容器列表（jsonpath 输出以空格分隔，先拆成一行一个）
    local matches
    _trace kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[*].name}'
    matches=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null \
              | tr ' ' '\n' | grep "$keyword")

    local count
    count=$(echo "$matches" | grep -c .)

    if [ "$count" -eq 0 ]; then
        echo "❌ pod '$pod' 中未找到包含 '$keyword' 的容器" >&2
        echo "   该 pod 的全部容器：" >&2
        kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null \
            | tr ' ' '\n' | sed 's/^/     - /' >&2
        return 1
    fi

    # 取第一个
    local container
    container=$(echo "$matches" | head -1)

    if [ "$count" -gt 1 ]; then
        echo "⚠️  匹配到 $count 个容器，已选择第一个: $container" >&2
        echo "   全部匹配：" >&2
        echo "$matches" | sed 's/^/     - /' >&2
    fi

    echo "$container"
}

# 参数 <pod_keyword>[.<container_keyword>] 的解析工具，kcl / kclf / kcex 共用
# 说明：容器名不含点，故按最后一个点切分，这样 pod 名字里带点也能正确解析

# _split_pod_key <pod_keyword>[.<container_keyword>]  →  输出 <pod_keyword>（没有点时原样返回）
_split_pod_key() {
    printf '%s' "${1%.*}"
}

# _split_container_key <pod_keyword>[.<container_keyword>]  →  输出 <container_keyword>（没有点时输出空，即不指定容器）
_split_container_key() {
    if [[ "$1" == *.* ]]; then
        printf '%s' "${1##*.}"
    fi
}

# ---------- kubectl 快捷指令 ----------

# kcg <ns_shortname>  →  kubectl get pod -n <ns_fullname>
# 说明：列出 <ns_fullname> 下的所有 pod；不确定 pod 叫什么时先用它看一眼
# 例：kcg ns1
kcg() {
    _ns "$1" || return 1
    local ns="$_NS_FULL"
    _run kubectl get pod -n "$ns"
}

# kcgsv <ns_shortname>  →  kubectl get services -n <ns_fullname>
# 说明：列出 <ns_fullname> 下的所有 service（注意是 services，不是 pod）
# 例：kcgsv ns1
kcgsv() {
    _ns "$1" || return 1
    local ns="$_NS_FULL"
    _run kubectl get services -n "$ns"
}

# kcl <pod_keyword>[.<container_keyword>] <ns_shortname>  →  kubectl logs <pod_fullname> [-c <container_fullname>] -n <ns_fullname>
# 说明：按关键字定位 pod（匹配到多个时取第一个并列出全部候选），再打印它的完整日志；pod 内有多个容器时必须用 <pod_keyword>.<container_keyword> 指定
# 例：kcl pod1 ns1        # pod 内只有一个容器
# 例：kcl pod1.c1 ns1     # pod 内有多个容器，指定名字包含 c1 的那个
kcl() {
    local pod_key container_key
    pod_key=$(_split_pod_key "$1")
    container_key=$(_split_container_key "$1")

    _ns "$2" || return 1
    local ns="$_NS_FULL"

    local pod
    pod=$(_find_pod "$pod_key" "$ns") || return 1

    if [ -n "$container_key" ]; then
        local container
        container=$(_find_container "$container_key" "$pod" "$ns") || return 1

        echo "📄 日志: $pod / $container  (ns=$ns)"
        _run kubectl logs "$pod" -c "$container" -n "$ns"
    else
        echo "📄 日志: $pod  (ns=$ns)"
        _run kubectl logs "$pod" -n "$ns"
    fi
}

# kclf <pod_keyword>[.<container_keyword>] <ns_shortname>  →  kubectl logs -f <pod_fullname> [-c <container_fullname>] -n <ns_fullname>
# 说明：与 kcl 相同，但实时跟踪（follow）日志输出；pod 内有多个容器时必须用 <pod_keyword>.<container_keyword> 指定
# 例：kclf pod1 ns1        # pod 内只有一个容器
# 例：kclf pod1.c1 ns1     # pod 内有多个容器，指定名字包含 c1 的那个
kclf() {
    local pod_key container_key
    pod_key=$(_split_pod_key "$1")
    container_key=$(_split_container_key "$1")

    _ns "$2" || return 1
    local ns="$_NS_FULL"

    local pod
    pod=$(_find_pod "$pod_key" "$ns") || return 1

    if [ -n "$container_key" ]; then
        local container
        container=$(_find_container "$container_key" "$pod" "$ns") || return 1

        echo "📄 实时跟踪: $pod / $container  (ns=$ns)"
        _run kubectl logs -f "$pod" -c "$container" -n "$ns"
    else
        echo "📄 实时跟踪: $pod  (ns=$ns)"
        _run kubectl logs -f "$pod" -n "$ns"
    fi
}

# kcns  →  列出所有已定义的命名空间简写
# 说明：本地输出，不调用 kubectl；自动发现的简写会标出来
kcns() {
    echo "📋 命名空间字典："
    local k
    for k in "${!NS_MAP[@]}"; do
        printf "  %-6s → %s%s\n" "$k" "${NS_MAP[$k]}" "$(_ns_cache_mark "$k")"
    done
    echo "🧠 自动发现缓存：${#NS_CACHE[@]}/$KCS_NS_CACHE_MAX（先进先出）"
}

# kcuse <ns_shortname>  →  kubectl config set-context --current --namespace=<ns_fullname>
# 说明：把 kubectl 的默认命名空间切到 <ns_fullname>，影响之后所有未指定 -n 的命令
# 例：kcuse ns2
kcuse() {
    _ns "$1" || return 1
    local ns="$_NS_FULL"
    _run kubectl config set-context --current --namespace="$ns"
    echo "✅ 当前命名空间已切换为: $ns"
}

# kctrace [on|off]  →  开关命令回显
# 说明：本地操作，不调用 kubectl；不带参数则查看当前状态
# 例：kctrace off
kctrace() {
    case "${1:-}" in
        on)
            KCS_TRACE=1
            echo "🔊 命令回显：已开启"
            ;;
        off)
            KCS_TRACE=0
            echo "🔇 命令回显：已关闭"
            ;;
        "")
            if [ "${KCS_TRACE:-1}" = "0" ]; then
                echo "🔇 命令回显：关闭（kctrace on 可开启）"
            else
                echo "🔊 命令回显：开启（kctrace off 可关闭）"
            fi
            ;;
        *)
            echo "❌ 用法: kctrace [on|off]" >&2
            return 1
            ;;
    esac
}

# kcex <pod_keyword>[.<container_keyword>] <ns_shortname>  →  kubectl exec -it <pod_fullname> [-c <container_fullname>] -n <ns_fullname> -- /bin/sh
# 说明：进入容器，优先 bash，没有则退回 sh；pod 内有多个容器时必须用 <pod_keyword>.<container_keyword> 指定
# 例：kcex pod1 ns1       # pod 内只有一个容器
# 例：kcex pod1.c1 ns1    # pod 内有多个容器，指定名字包含 c1 的那个
kcex() {
    local pod_key container_key
    pod_key=$(_split_pod_key "$1")
    container_key=$(_split_container_key "$1")

    _ns "$2" || return 1
    local ns="$_NS_FULL"

    local pod
    pod=$(_find_pod "$pod_key" "$ns") || return 1

    # 进入容器后执行的 shell：有 bash 就用 bash，否则退回 sh
    local shell_cmd='command -v bash >/dev/null && exec bash || exec sh'

    if [ -n "$container_key" ]; then
        local container
        container=$(_find_container "$container_key" "$pod" "$ns") || return 1

        echo "🚪 进入容器: $pod / $container  (ns=$ns)"
        _run kubectl exec -it "$pod" -c "$container" -n "$ns" -- /bin/sh -c "$shell_cmd"
    else
        echo "🚪 进入容器: $pod  (ns=$ns)"
        _run kubectl exec -it "$pod" -n "$ns" -- /bin/sh -c "$shell_cmd"
    fi
}

# kcdes <pod_keyword> <ns_shortname>  →  kubectl describe pod <pod_fullname> -n <ns_fullname>
# 例：kcdes pod2 ns2
kcdes() {
    local keyword="$1"

    _ns "$2" || return 1
    local ns="$_NS_FULL"

    local pod
    pod=$(_find_pod "$keyword" "$ns") || return 1

    echo "🔍 describe: $pod  (ns=$ns)"
    _run kubectl describe pod "$pod" -n "$ns"
}
