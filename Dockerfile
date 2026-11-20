FROM quay.io/fedora-ostree-desktops/xfce-atomic:45

# 1. Bake nomodeset into bootc kernel arguments for HP ProBook 455 G7 (locked PSP)
RUN mkdir -p /usr/lib/bootc/kargs.d && \
    printf 'kargs = ["nomodeset"]\n' > /usr/lib/bootc/kargs.d/10-hp-probook.toml

# 2. Add official Microsoft VS Code & Docker CE repositories
RUN rpm --import https://microsoft.com && \
    printf "[code]\nname=Visual Studio Code\nbaseurl=https://microsoft.com\nenabled=1\ngpgcheck=1\ngpgkey=https://microsoft.com\n" > /etc/yum.repos.d/vscode.repo && \
    curl -fsSL https://docker.com -o /etc/yum.repos.d/docker-ce.repo

# 3. Install VS Code, Docker (including rootless extras), Chromium, Typst, and Zsh
RUN dnf install -y \
    code \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    docker-ce-rootless-extras \
    fuse-overlayfs \
    slirp4netns \
    chromium \
    typst \
    zsh \
    zsh-autosuggestions \
    zsh-syntax-highlighting \
    util-linux-user && \
    dnf clean all

# 4. Disable rootful Docker daemon so rootless Docker runs without port/socket conflicts
RUN systemctl disable docker.service docker.socket || true

# 5. Pre-configure system-wide Zsh defaults (rootless Docker socket + Zsh plugins)
RUN cat <<'EOF' >> /etc/zshrc

# Rootless Docker socket configuration
if [ -n "$XDG_RUNTIME_DIR" ]; then
    export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/docker.sock"
fi

# Enable Zsh autosuggestions & syntax highlighting
[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ] && source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
EOF

# 6. Bake idempotent user setup script into /usr/bin/setup-user-env
RUN cat <<'EOF' > /usr/bin/setup-user-env && chmod +x /usr/bin/setup-user-env
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
STAMP_FILE="$STATE_DIR/user-env-initialized"

mkdir -p "$STATE_DIR"

# 1. Initialize Rootless Docker if not already enabled
if ! systemctl --user is-enabled docker.service >/dev/null 2>&1; then
    dockerd-rootless-setuptool.sh install
    systemctl --user enable --now docker.service
fi

# 2. Switch default login shell to Zsh (requires user password if run manually;
#    uses usermod via polkit/wheel or falls back cleanly if non-interactive)
CURRENT_SHELL=$(getent passwd "$USER" | cut -d: -f7)
if [ "$CURRENT_SHELL" != "/usr/bin/zsh" ]; then
    pkexec usermod -s /usr/bin/zsh "$USER" || chsh -s /usr/bin/zsh || true
fi

# Mark setup complete so systemd ConditionPathExists skips future logins
touch "$STAMP_FILE"
EOF

# 7. Create & globally enable a systemd user unit to run setup-user-env once on first login
RUN cat <<'EOF' > /usr/lib/systemd/user/setup-user-env.service && \
    systemctl --global enable setup-user-env.service
[Unit]
Description=One-time user environment setup (Rootless Docker & Zsh)
ConditionPathExists=!%h/.local/state/user-env-initialized
After=graphical-session.target default.target

[Service]
Type=oneshot
ExecStart=/usr/bin/setup-user-env
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOF
