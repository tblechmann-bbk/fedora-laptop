FROM quay.io/fedora-ostree-desktops/xfce-atomic:45

RUN set -euxo pipefail && \
    mkdir -p /usr/lib/bootc/kargs.d && \
    printf 'kargs = ["nomodeset"]\n' > /usr/lib/bootc/kargs.d/10-hp-probook.toml && \
    rpm --import https://packages.microsoft.com/keys/microsoft.asc && \
    printf "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n" > /etc/yum.repos.d/vscode.repo && \
    curl -fsSL https://download.docker.com/linux/fedora/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo && \
    dnf install -y \
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
    dnf clean all && \
    (systemctl disable docker.service docker.socket || true) && \
    printf '%s\n' \
        '' \
        '# Rootless Docker socket configuration' \
        'if [ -n "$XDG_RUNTIME_DIR" ]; then' \
        '    export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/docker.sock"' \
        'fi' \
        '' \
        '# Enable Zsh autosuggestions & syntax highlighting' \
        '[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ] && source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh' \
        '[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' \
        >> /etc/zshrc && \
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -euo pipefail' \
        '' \
        'STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"' \
        'STAMP_FILE="$STATE_DIR/user-env-initialized"' \
        '' \
        'mkdir -p "$STATE_DIR"' \
        '' \
        'if ! systemctl --user is-enabled docker.service >/dev/null 2>&1; then' \
        '    dockerd-rootless-setuptool.sh install' \
        '    systemctl --user enable --now docker.service' \
        'fi' \
        '' \
        'CURRENT_SHELL=$(getent passwd "$USER" | cut -d: -f7)' \
        'if [ "$CURRENT_SHELL" != "/usr/bin/zsh" ]; then' \
        '    pkexec usermod -s /usr/bin/zsh "$USER" || chsh -s /usr/bin/zsh || true' \
        'fi' \
        '' \
        'touch "$STAMP_FILE"' \
        > /usr/bin/setup-user-env && \
    chmod +x /usr/bin/setup-user-env && \
    printf '%s\n' \
        '[Unit]' \
        'Description=One-time user environment setup (Rootless Docker & Zsh)' \
        'ConditionPathExists=!%h/.local/state/user-env-initialized' \
        'After=graphical-session.target default.target' \
        '' \
        '[Service]' \
        'Type=oneshot' \
        'ExecStart=/usr/bin/setup-user-env' \
        'RemainAfterExit=yes' \
        '' \
        '[Install]' \
        'WantedBy=default.target' \
        > /usr/lib/systemd/user/setup-user-env.service && \
    systemctl --global enable setup-user-env.service
