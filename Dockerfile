# 最小化wrk Docker镜像构建
# 基于多阶段构建，最终使用scratch镜像

# 阶段1: 编译层
FROM alpine:latest AS builder

# 安装构建依赖（包括OpenSSL静态库和命令行工具）
RUN set -eux \
    && FILENAME=wrk3 \
    && mkdir -p /tmp \
    && cd /tmp \
    && apk add --no-cache --no-scripts --virtual .build-deps \
    git \
    # strip
    binutils \
    zig \
    # 尝试安装 upx，如果不可用则继续（某些架构可能不支持）
    \
    && apk add --no-cache --no-scripts --virtual .upx-deps \
        upx 2>/dev/null || echo "upx not available, skipping compression" \
    \
    # && \
    # 克隆wrk源码（使用static分支）并编译
    # set -eux \
    && git clone https://github.com/cyoab/wrk3.git --recursive --branch main --depth 1 \
    && cd wrk3 \
    # 显示环境信息用于调试
    && echo "=== 构建环境信息 ===" \
    && pwd \
    && ls -la \
    # && echo "=== OpenSSL 版本信息 ===" \
    # && openssl version \
    # && echo "=== 开始动态编译 wrk ===" \
    # && make -j$(nproc) STATIC=1 WITH_OPENSSL=/usr \
    # && echo "=== 静态编译成功，生成二进制文件 ===" \
    # The binary is at zig-out/bin/wrk3.
    # 多核编译 (wrk3 的 build.zig 只支持 -Doptimize)
    && ZIG_GLOBAL_CACHE_DIR=/tmp/zig-cache zig build \
        -Doptimize=ReleaseFast \
        -j$(nproc) \
    # 使用系统OpenSSL库进行动态编译
    # && make -j$(nproc) STATIC=0 WITH_OPENSSL=/usr \
    # && echo "=== 动态编译成功，生成二进制文件 ===" \
    && du -b ./zig-out/bin/wrk3 \
    && echo "=== 剥离调试信息 ===" \
    && strip -v --strip-all ./zig-out/bin/wrk3 \
    && du -b ./zig-out/bin/wrk3 \
    && echo "剥离调试信息后:" \
    && echo "=== 编译完成，已启用 LTO 和 strip ===" \
    # && echo "=== 剥离调试信息 ===" \
    # && strip -v --strip-all ./zig-out/bin/wrk3 \
    # && du -b ./zig-out/bin/wrk3 \
    # && echo "剥离调试信息后:" \
    # && upx --best --lzma ./wrk \
    && (upx --best --lzma ./zig-out/bin/wrk3 2>/dev/null || echo "upx compression skipped") \
    && du -b ./zig-out/bin/wrk3 \
    && echo "=== 剥离后文件信息 ===" \
    && du -b ./zig-out/bin/wrk3 \
    && echo "=== 剥离库文件调试信息 ===" \
    # && find /usr/lib -name "*.so*" -type f -exec strip -v --strip-all {} \; \
    # && find /lib -name "*.so*" -type f -exec strip -v --strip-all {} \;
    # && find / -name "*.*" -type f -exec strip -v --strip-all {} \;
    # && find / -name "*" -type f -exec strip -v --strip-all {} \; 2>/dev/null || true \
    && echo "====Done==="


# 阶段2: 运行层

# FROM alpine:3.19
# # 安装运行时依赖 - libgcc提供libgcc_s.so.1共享库
# RUN apk add --no-cache libgcc

# # 从编译层复制wrk二进制文件
# COPY --from=builder /wrk/wrk /usr/local/bin/wrk

# # 设置入口点
# ENTRYPOINT ["/usr/local/bin/wrk"]    # 阶段2: 运行层 - 使用scratch镜像（最小化）
FROM scratch AS final
# 还是要给开发者调试的
# FROM busybox:musl AS runpod

# # 复制动态链接所需的库文件
# # musl libc 加载器
# COPY --from=builder /lib/ld-musl-x86_64.so.1 /lib/
# # GCC 运行时库
# COPY --from=builder /usr/lib/libgcc_s.so.1 /usr/lib/
# # OpenSSL 库（Alpine 使用 OpenSSL 3.x）
# COPY --from=builder /usr/lib/libssl.so.3 /usr/lib/
# COPY --from=builder /usr/lib/libcrypto.so.3 /usr/lib/

# 复制/etc/services文件用于服务名解析 DNS解析要用
COPY --from=builder /etc/services /etc/services
# 复制/etc/nsswitch.conf文件用于DNS解析 host模式忽略
# COPY --from=builder /etc/nsswitch.conf /etc/nsswitch.conf

# 复制wrk二进制文件
COPY --from=builder /tmp/wrk3/zig-out/bin/wrk3 /wrk3

# 在Dockerfile的scratch阶段添加复制Lua脚本的指令
# COPY --from=builder /wrk/scripts/ /scripts/
# COPY --from=builder /wrk/src/wrk.lua /wrk.lua

# 设置入口点
ENTRYPOINT ["/wrk3"]
