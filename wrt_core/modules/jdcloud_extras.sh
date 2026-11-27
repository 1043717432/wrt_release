#!/usr/bin/env bash
# JDCloud RE-CS-07 专属增强：Docker 数据盘自动挂载/清理、OpenClash 内置 Mihomo 内核。
# 仅在 WRT_BUILD_DEVICE=jdcloud_ipq60xx_immwrt 时生效，其他设备直接跳过。

_jdcloud_extras_enabled() {
    [ "${WRT_BUILD_DEVICE:-}" = "jdcloud_ipq60xx_immwrt" ]
}

install_jdcloud_docker_runtime() {
    _jdcloud_extras_enabled || return 0

    local base_files="$BUILD_DIR/package/base-files/files"
    local src="$BASE_PATH/patches"

    install -Dm755 "$src/jdcloud-docker-loop.init" "$base_files/etc/init.d/docker-loop" || return 1
    install -Dm755 "$src/docker-autoclean.sh" "$base_files/usr/bin/docker-autoclean.sh" || return 1
    install -Dm755 "$src/99-jdcloud-docker-defaults" "$base_files/etc/uci-defaults/99-jdcloud-docker-defaults" || return 1
    echo "已安装 JDCloud Docker 数据盘自动挂载、日志轮转与每日清理。"
}

# 下载 MetaCubeX/mihomo 最新稳定版 arm64 内核，放到 OpenClash 的 Meta 内核路径。
bundle_openclash_core() {
    _jdcloud_extras_enabled || return 0

    local core_dir="$BUILD_DIR/files/etc/openclash/core"
    local api="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
    local auth=()
    local release_json tag asset_name asset_url asset_digest tmp_gz

    [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")

    release_json=$(curl -fsSL --retry 3 "${auth[@]}" "$api") || {
        echo "错误：获取 mihomo 最新版本信息失败" >&2
        return 1
    }
    tag=$(jq -r '.tag_name' <<<"$release_json")
    asset_name="mihomo-linux-arm64-${tag}.gz"
    asset_url=$(jq -r --arg n "$asset_name" '.assets[] | select(.name == $n) | .browser_download_url' <<<"$release_json")
    asset_digest=$(jq -r --arg n "$asset_name" '.assets[] | select(.name == $n) | .digest // empty' <<<"$release_json")

    if [ -z "$asset_url" ] || [ "$asset_url" = "null" ]; then
        echo "错误：mihomo $tag 中找不到 $asset_name" >&2
        return 1
    fi

    tmp_gz=$(mktemp) || return 1
    curl -fsSL --retry 3 -o "$tmp_gz" "$asset_url" || { rm -f "$tmp_gz"; echo "错误：下载 $asset_name 失败" >&2; return 1; }

    if [ -n "$asset_digest" ]; then
        if [ "sha256:$(sha256sum "$tmp_gz" | cut -d' ' -f1)" != "$asset_digest" ]; then
            rm -f "$tmp_gz"
            echo "错误：$asset_name SHA256 校验失败" >&2
            return 1
        fi
    fi

    mkdir -p "$core_dir"
    gzip -dc "$tmp_gz" > "$core_dir/clash_meta" || { rm -f "$tmp_gz"; return 1; }
    rm -f "$tmp_gz"
    chmod 0755 "$core_dir/clash_meta"

    if ! file "$core_dir/clash_meta" 2>/dev/null | grep -q "ARM aarch64"; then
        echo "错误：clash_meta 不是 aarch64 可执行文件" >&2
        rm -f "$core_dir/clash_meta"
        return 1
    fi
    echo "已内置 OpenClash Meta 内核：mihomo $tag (${asset_digest:-no-digest})"
}
