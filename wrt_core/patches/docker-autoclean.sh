#!/bin/sh
# 每日自动清理：Docker 无用镜像/构建缓存 + 内存紧张时释放页缓存。
# 容器日志由 local 日志驱动自动轮转，无需在此处理。
TAG=docker-autoclean
if pgrep -x dockerd >/dev/null 2>&1; then
	img=$(docker image prune -f 2>/dev/null | tail -1)
	bld=$(docker builder prune -f 2>/dev/null | tail -1)
	logger -t $TAG "image prune: ${img:-none}; builder prune: ${bld:-none}"
fi
avail_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
if [ "${avail_kb:-0}" -lt 307200 ]; then
	sync && echo 1 > /proc/sys/vm/drop_caches
	logger -t $TAG "MemAvailable ${avail_kb}kB < 300MB, dropped page cache"
fi
