FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Shared Linux dev dependency list (comments / blanks stripped at install time)
COPY frontend/linux/dev-deps.apt.txt /tmp/dev-deps.apt.txt

# Install base packages + deps from list
# sed strips comments and blank lines before feeding to apt-get
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget xz-utils \
    git unzip zip jq \
    gh \
    nodejs npm \
    tmux dbus-x11 \
    $(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' /tmp/dev-deps.apt.txt | tr '\n' ' ') \
  && rm -rf /var/lib/apt/lists/*

# Install xpra from official repo (Ubuntu's 3.1.5 is too old for HTML5 client)
RUN wget -O /usr/share/keyrings/xpra.asc https://xpra.org/xpra.asc \
  && wget -O /etc/apt/sources.list.d/xpra.sources \
       https://raw.githubusercontent.com/Xpra-org/xpra/master/packaging/repos/noble/xpra.sources \
  && apt-get update && apt-get install -y --no-install-recommends xpra xpra-x11 xpra-html5 \
  && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash devuser \
  && mkdir -p /run/user/1001 && chown devuser:devuser /run/user/1001

USER devuser
ENV HOME=/home/devuser
ENV XDG_RUNTIME_DIR=/run/user/1001

ENV NPM_CONFIG_PREFIX=$HOME/.npm-global
ENV PATH=$HOME/.npm-global/bin:$HOME/.local/bin:$PATH
RUN mkdir -p "$HOME/.npm-global"

ARG FLUTTER_VERSION
ARG FLUTTER_CHANNEL=stable

RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" \
      https://github.com/flutter/flutter.git "$HOME/flutter"

ENV PATH=$HOME/flutter/bin:$PATH

RUN flutter config --no-analytics --enable-linux-desktop \
  && flutter precache --linux \
  && flutter doctor -v

# Rust toolchain - needed by super_native_extensions (no prebuilt aarch64-linux binaries)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
ENV PATH=$HOME/.cargo/bin:$PATH

RUN npm install -g @openai/codex

RUN curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh \
  && bash /tmp/claude-install.sh \
  && rm -f /tmp/claude-install.sh

COPY --chown=devuser:devuser dev-linux/internal-start.sh /internal-start.sh
RUN chmod +x /internal-start.sh

WORKDIR /workspace
EXPOSE 14500

CMD xpra start \
    --bind-tcp=0.0.0.0:14500 \
    --html=on \
    --daemon=no \
    --start-child="bash /internal-start.sh"
