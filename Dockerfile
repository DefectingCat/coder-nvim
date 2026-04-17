FROM rockylinux:9

# 代理设置 - 构建时从宿主机继承
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

# 安装基础工具和开发环境
# 启用 EPEL 和 CRB 仓库以获取更多工具
RUN dnf -y update && \
    dnf -y install epel-release && \
    dnf -y config-manager --set-enabled crb && \
    # 配置 EPEL 镜像源
    sed -e 's|^metalink=|#metalink=|g' \
        -e 's|^#baseurl=https\?://download.fedoraproject.org/pub/epel/|baseurl=https://mirrors.ustc.edu.cn/epel/|g' \
        -e 's|^#baseurl=https\?://download.example/pub/epel/|baseurl=https://mirrors.ustc.edu.cn/epel/|g' \
        -i.bak /etc/yum.repos.d/epel{,-testing}.repo \
    && dnf makecache \
    && dnf -y --allowerasing install \
    # 基础工具
    wget \
    git \
    vim \
    nano \
    unzip \
    zip \
    tar \
    gzip \
    bzip2 \
    xz \
    # 开发工具
    gcc \
    gcc-c++ \
    make \
    autoconf \
    automake \
    libtool \
    pkg-config \
    # 系统工具
    sudo \
    passwd \
    openssh-server \
    procps-ng \
    htop \
    net-tools \
    bind-utils \
    lsof \
    strace \
    tmux \
    screen \
    fish \
    # Python
    python3 \
    python3-pip \
    python3-devel \
    # 开发工具 (从 EPEL)
    ripgrep \
    fd-find \
    # Neovim 编译依赖
    ninja-build \
    cmake \
    gettext \
    curl \
    glibc-gconv-extra

# 从源码编译安装 Neovim v0.12.1 (独立步骤，便于重试)
RUN git config --global http.version HTTP/1.1 \
    && git config --global http.postBuffer 524288000 \
    && git clone --depth 1 --branch v0.12.1 https://github.com/neovim/neovim /tmp/neovim \
    && cd /tmp/neovim \
    && make CMAKE_BUILD_TYPE=RelWithDebInfo \
    && make install \
    && rm -rf /tmp/neovim

# 安装 fnm (Fast Node Manager)
RUN curl --retry 3 --retry-delay 5 -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir /usr/local/fnm --skip-shell \
    && ln -s /usr/local/fnm/fnm /usr/local/bin/fnm \
    # 清理
    && dnf -y clean all \
    && rm -rf /var/cache/dnf

# 创建 coder 用户，使用 fish 作为默认 shell
RUN useradd -m -s /usr/bin/fish coder && \
    echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/coder && \
    chmod 0440 /etc/sudoers.d/coder

# 为 coder 用户创建 fd 别名 (EPEL 的 fd-find 命令是 fd-find 而非 fd)
# 并安装 Node.js lts via fnm
RUN mkdir -p /home/coder/.config/fish/conf.d \
    /home/coder/.local/share/fnm \
    && echo 'alias fd=fd-find' >> /home/coder/.config/fish/config.fish \
    && echo 'fnm env --use-on-cd --shell fish | source' > /home/coder/.config/fish/conf.d/fnm.fish \
    && FNM_DIR=/home/coder/.local/share/fnm fnm install 'lts/*' \
    && chown -R coder:coder /home/coder/.config /home/coder/.local

# 设置工作目录
WORKDIR /home/coder

# 设置默认用户
USER coder

# 入口点 (Coder agent 将覆盖)
ENTRYPOINT ["fish"]
