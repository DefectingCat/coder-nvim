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

# 克隆 dotfiles 仓库（获取 fish 配置）
RUN git clone --depth 1 https://github.com/DefectingCat/dotfiles.git /tmp/dotfiles

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
    wget git vim nano unzip zip tar gzip bzip2 xz make \
    sudo passwd openssh-server procps-ng htop net-tools bind-utils lsof strace \
    tmux screen fish \
    python3 python3-pip python3-devel \
    ripgrep fd-find fastfetch curl glibc-langpack-en \
    && dnf -y clean all \
    && rm -rf /var/cache/dnf

# 安装 fish 配置依赖的工具（EPEL 中不可用，从 GitHub 下载）
RUN curl --retry 3 --retry-delay 5 -fsSL https://github.com/starship/starship/releases/latest/download/starship-x86_64-unknown-linux-gnu.tar.gz \
    | tar -xz -C /usr/local/bin \
    && curl --retry 3 --retry-delay 5 -fsSL https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz \
    | tar -xz -C /usr/local/bin \
    && LSD_VER=$(curl -fsSL https://api.github.com/repos/Peltoche/lsd/releases/latest | grep '"tag_name"' | sed 's/.*"v\(.*\)".*/\1/') \
    && curl --retry 3 --retry-delay 5 -fsSL "https://github.com/Peltoche/lsd/releases/latest/download/lsd-v${LSD_VER}-x86_64-unknown-linux-gnu.tar.gz" \
    | tar -xz -C /usr/local/bin --strip-components=1 "lsd-v${LSD_VER}-x86_64-unknown-linux-gnu/lsd" \
    && BAT_VER=$(curl -fsSL https://api.github.com/repos/sharkdp/bat/releases/latest | grep '"tag_name"' | sed 's/.*"v\(.*\)".*/\1/') \
    && curl --retry 3 --retry-delay 5 -fsSL "https://github.com/sharkdp/bat/releases/latest/download/bat-v${BAT_VER}-x86_64-unknown-linux-gnu.tar.gz" -o /tmp/bat.tar.gz \
    && tar -xzf /tmp/bat.tar.gz -C /tmp \
    && cp /tmp/bat-v${BAT_VER}-x86_64-unknown-linux-gnu/bat /usr/local/bin/ \
    && rm -rf /tmp/bat* \
    && LG_VER=$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep '"tag_name"' | sed 's/.*"v\(.*\)".*/\1/') \
    && curl --retry 3 --retry-delay 5 -fsSL "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LG_VER}_linux_x86_64.tar.gz" \
    | tar -xz -C /usr/local/bin lazygit

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

# 从构建阶段复制 fish 配置
COPY --from=builder /tmp/dotfiles/fish /home/coder/.config/fish

# 添加 rustup/cargo 环境配置
RUN echo 'set -gx RUSTUP_HOME /home/coder/.rustup' > /home/coder/.config/fish/conf.d/rustup.fish \
    && echo 'set -gx CARGO_HOME /home/coder/.cargo' >> /home/coder/.config/fish/conf.d/rustup.fish \
    && echo 'set -gx RUSTUP_DIST_SERVER https://mirrors.ustc.edu.cn/rust-static' >> /home/coder/.config/fish/conf.d/rustup.fish \
    && echo 'set -gx RUSTUP_UPDATE_ROOT https://mirrors.ustc.edu.cn/rust-static/rustup' >> /home/coder/.config/fish/conf.d/rustup.fish \
    && echo 'set -gx PATH $PATH /home/coder/.cargo/bin' >> /home/coder/.config/fish/conf.d/rustup.fish

# 安装开发工具并设置权限
RUN mkdir -p /home/coder/.local/share/fnm \
    /home/coder/.rustup \
    /home/coder/.cargo \
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