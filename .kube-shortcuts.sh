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

# 解析简写为完整命名空间
# 用法：_ns <ns_shortname>  →  输出 <ns_fullname>；未定义则报错并返回 1
_ns() {
    local key="$1"
    if [ -n "${NS_MAP[$key]}" ]; then
        echo "${NS_MAP[$key]}"
    else
        echo "❌ 未定义的命名空间简写: '$key'" >&2
        echo "   已定义: ${!NS_MAP[*]}" >&2
        return 1
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

# ---------- kubectl 快捷指令 ----------

# kcg <ns_shortname>  →  kubectl get pod -n <ns_fullname>
# 说明：列出 <ns_fullname> 下的所有 pod；不确定 pod 叫什么时先用它看一眼
# 例：kcg ns1
kcg() {
    local ns
    ns=$(_ns "$1") || return 1
    _run kubectl get pod -n "$ns"
}

# kcgsv <ns_shortname>  →  kubectl get services -n <ns_fullname>
# 说明：列出 <ns_fullname> 下的所有 service（注意是 services，不是 pod）
# 例：kcgsv ns1
kcgsv() {
    local ns
    ns=$(_ns "$1") || return 1
    _run kubectl get services -n "$ns"
}

# kcl <pod_keyword> <ns_shortname>  →  kubectl logs <pod_fullname> -n <ns_fullname>
# 说明：按关键字定位 pod（匹配到多个时取第一个并列出全部候选），再打印它的完整日志
# 例：kcl pod1 ns1
kcl() {
    local keyword="$1"
    local ns
    ns=$(_ns "$2") || return 1

    local pod
    pod=$(_find_pod "$keyword" "$ns") || return 1

    echo "📄 日志: $pod  (ns=$ns)"
    _run kubectl logs "$pod" -n "$ns"
}

# kclf <pod_keyword> <ns_shortname>  →  kubectl logs -f <pod_fullname> -n <ns_fullname>
# 说明：与 kcl 相同，但实时跟踪（follow）日志输出
# 例：kclf pod1 ns1
kclf() {
    local keyword="$1"
    local ns
    ns=$(_ns "$2") || return 1

    local pod
    pod=$(_find_pod "$keyword" "$ns") || return 1

    echo "📄 实时跟踪: $pod  (ns=$ns)"
    _run kubectl logs -f "$pod" -n "$ns"
}

# kcns  →  列出所有已定义的命名空间简写
# 说明：本地输出，不调用 kubectl
kcns() {
    echo "📋 命名空间字典："
    for k in "${!NS_MAP[@]}"; do
        printf "  %-6s → %s\n" "$k" "${NS_MAP[$k]}"
    done
}

# kcuse <ns_shortname>  →  kubectl config set-context --current --namespace=<ns_fullname>
# 说明：把 kubectl 的默认命名空间切到 <ns_fullname>，影响之后所有未指定 -n 的命令
# 例：kcuse ns2
kcuse() {
    local ns
    ns=$(_ns "$1") || return 1
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

# kcex <pod_keyword> <ns_shortname>  →  kubectl exec -it <pod_fullname> -n <ns_fullname> -- /bin/sh
# 说明：进入容器，优先 bash，没有则退回 sh
# 例：kcex pod1 ns1
kcex() {
    local keyword="$1"
    local ns
    ns=$(_ns "$2") || return 1

    local pod
    pod=$(_find_pod "$keyword" "$ns") || return 1

    echo "🚪 进入容器: $pod  (ns=$ns)"
    _run kubectl exec -it "$pod" -n "$ns" -- /bin/sh -c 'command -v bash >/dev/null && exec bash || exec sh'
}

# kcdes <pod_keyword> <ns_shortname>  →  kubectl describe pod <pod_fullname> -n <ns_fullname>
# 例：kcdes pod2 ns2
kcdes() {
    local keyword="$1"
    local ns
    ns=$(_ns "$2") || return 1

    local pod
    pod=$(_find_pod "$keyword" "$ns") || return 1

    echo "🔍 describe: $pod  (ns=$ns)"
    _run kubectl describe pod "$pod" -n "$ns"
}
