FROM rockylinux:9 AS builder

# 代理设置 - 构建时从宿主机继承
ARG http_proxy
ARG https_proxy
ARG no_proxy

ENV http_proxy=${http_proxy} \
    https_proxy=${https_proxy}

# 配置 USTC 镜像源
RUN sed -e 's|^mirrorlist=|#mirrorlist=|g' \
        -e 's|^#baseurl=http://dl.rockylinux.org/$contentdir|baseurl=https://mirrors.ustc.edu.cn/rocky|g' \
        -i.bak \
        /etc/yum.repos.d/rocky.repo \
        /etc/yum.repos.d/rocky-extras.repo \
    && dnf makecache

# 安装编译依赖
RUN dnf -y install epel-release && \
    dnf -y config-manager --set-enabled crb && \
    sed -e 's|^metalink=|#metalink=|g' \
        -e 's|^#baseurl=https\?://download.fedoraproject.org/pub/epel/|baseurl=https://mirrors.ustc.edu.cn/epel/|g' \
        -e 's|^#baseurl=https\?://download.example/pub/epel/|baseurl=https://mirrors.ustc.edu.cn/epel/|g' \
        -i.bak /etc/yum.repos.d/epel{,-testing}.repo \
    && dnf makecache \
    && dnf -y --allowerasing install git cmake ninja-build gcc gcc-c++ make gettext curl glibc-gconv-extra

# 编译 Neovim v0.12.1 (使用 tarball 下载，更稳定)
RUN curl --retry 5 --retry-delay 3 -fsSL https://github.com/neovim/neovim/archive/refs/tags/v0.12.1.tar.gz -o /tmp/neovim.tar.gz \
    && tar -xzf /tmp/neovim.tar.gz -C /tmp \
    && cd /tmp/neovim-0.12.1 \
    && make CMAKE_BUILD_TYPE=Release \
    && make install \
    && rm -rf /tmp/neovim-0.12.1 /tmp/neovim.tar.gz

# 下载 Go
RUN curl --retry 3 --retry-delay 5 -fsSL https://go.dev/dl/go1.26.2.linux-amd64.tar.gz -o /tmp/go.tar.gz

# ============ 运行阶段 ============
FROM rockylinux:9

# 代理设置
ARG http_proxy
ARG https_proxy
ARG no_proxy

# 设置环境变量
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    http_proxy=${http_proxy} \
    https_proxy=${https_proxy} \
    no_proxy=${no_proxy}

# 配置 USTC 镜像源
RUN sed -e 's|^mirrorlist=|#mirrorlist=|g' \
        -e 's|^#baseurl=http://dl.rockylinux.org/$contentdir|baseurl=https://mirrors.ustc.edu.cn/rocky|g' \
        -i.bak \
        /etc/yum.repos.d/rocky.repo \
        /etc/yum.repos.d/rocky-extras.repo \
    && dnf makecache

# 安装运行时依赖
RUN dnf -y install epel-release && \
    dnf -y config-manager --set-enabled crb && \
    sed -e 's|^metalink=|#metalink=|g' \
        -e 's|^#baseurl=https\?://download.fedoraproject.org/pub/epel/|baseurl=https://mirrors.ustc.edu.cn/epel/|g' \
        -e 's|^#baseurl=https\?://download.example/pub/epel/|baseurl=https://mirrors.ustc.edu.cn/epel/|g' \
        -i.bak /etc/yum.repos.d/epel{,-testing}.repo \
    && dnf makecache \
    && dnf -y --allowerasing install \
    wget git vim nano unzip zip tar gzip bzip2 xz \
    sudo passwd openssh-server procps-ng htop net-tools bind-utils lsof strace \
    tmux screen fish \
    python3 python3-pip python3-devel \
    ripgrep fd-find fastfetch curl \
    && dnf -y clean all \
    && rm -rf /var/cache/dnf

# 从构建阶段复制 Neovim
COPY --from=builder /usr/local/bin/nvim /usr/local/bin/nvim
COPY --from=builder /usr/local/share/nvim /usr/local/share/nvim

# 从构建阶段复制并安装 Go
COPY --from=builder /tmp/go.tar.gz /tmp/go.tar.gz
RUN rm -rf /usr/local/go \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm /tmp/go.tar.gz

ENV PATH=$PATH:/usr/local/go/bin

# 安装 fnm
RUN curl --retry 3 --retry-delay 5 -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir /usr/local/fnm --skip-shell \
    && ln -s /usr/local/fnm/fnm /usr/local/bin/fnm

# 创建 coder 用户
RUN useradd -m -s /usr/bin/fish coder && \
    echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/coder && \
    chmod 0440 /etc/sudoers.d/coder

# 配置 coder 用户环境和安装开发工具
RUN mkdir -p /home/coder/.config/fish/conf.d \
    /home/coder/.local/share/fnm \
    /home/coder/.rustup \
    /home/coder/.cargo \
    && echo 'alias fd=fd-find' >> /home/coder/.config/fish/config.fish \
    && echo 'fnm env --use-on-cd --shell fish | source' > /home/coder/.config/fish/conf.d/fnm.fish \
    && echo 'set -gx RUSTUP_HOME /home/coder/.rustup' > /home/coder/.config/fish/conf.d/rustup.fish \
    && echo 'set -gx CARGO_HOME /home/coder/.cargo' >> /home/coder/.config/fish/conf.d/rustup.fish \
    && echo 'set -gx RUSTUP_DIST_SERVER https://mirrors.ustc.edu.cn/rust-static' >> /home/coder/.config/fish/conf.d/rustup.fish \
    && echo 'set -gx RUSTUP_UPDATE_ROOT https://mirrors.ustc.edu.cn/rust-static/rustup' >> /home/coder/.config/fish/conf.d/rustup.fish \
    && echo 'set -gx PATH $PATH /home/coder/.cargo/bin' >> /home/coder/.config/fish/conf.d/rustup.fish \
    && FNM_DIR=/home/coder/.local/share/fnm fnm install 'lts/*' \
    # 全局安装 claude-code
    && FNM_DIR=/home/coder/.local/share/fnm fnm exec --using=lts/latest -- npm i -g @anthropic-ai/claude-code \
    && RUSTUP_HOME=/home/coder/.rustup CARGO_HOME=/home/coder/.cargo RUSTUP_DIST_SERVER=https://mirrors.ustc.edu.cn/rust-static RUSTUP_UPDATE_ROOT=https://mirrors.ustc.edu.cn/rust-static/rustup curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | RUSTUP_HOME=/home/coder/.rustup CARGO_HOME=/home/coder/.cargo RUSTUP_DIST_SERVER=https://mirrors.ustc.edu.cn/rust-static RUSTUP_UPDATE_ROOT=https://mirrors.ustc.edu.cn/rust-static/rustup sh -s -- -y --no-modify-path \
    && printf '[source.crates-io]\nreplace-with = "ustc"\n\n[source.ustc]\nregistry = "sparse+https://mirrors.ustc.edu.cn/crates.io-index/"\n\n[registries.ustc]\nindex = "sparse+https://mirrors.ustc.edu.cn/crates.io-index/"\n' > /home/coder/.cargo/config.toml \
    && chown -R coder:coder /home/coder/.config /home/coder/.local /home/coder/.rustup /home/coder/.cargo

# 克隆 nvim 配置并安装插件
RUN mkdir -p /home/coder/.local/share/nvim \
    /home/coder/.local/state/nvim \
    /home/coder/.cache/nvim \
    && git clone --depth 1 https://github.com/DefectingCat/nvim /home/coder/.config/nvim \
    && chown -R coder:coder /home/coder/.config /home/coder/.local /home/coder/.cache \
    && su - coder -c "nvim --headless -c 'quit'" || true \
    && su - coder -c "nvim --headless '+Lazy! sync' +qa" || true

WORKDIR /home/coder
USER coder
ENTRYPOINT ["fish"]