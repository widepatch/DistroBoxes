#!/bin/bash
set -e

CHAOTIC_AUR=(
    neovim
    pastel
    glow
)

PARU=(
    python-grip
)

EXPORT_BINS=(
    /usr/bin/nvim
    # GitHub CLI
    /usr/bin/gh
    # Wayland screenshot & OCR
    /usr/bin/grim
    /usr/bin/slurp
    /usr/bin/tesseract
    # Wayland clipboard
    /usr/bin/wl-copy
    /usr/bin/wl-paste
    # Desktop notifications
    /usr/bin/notify-send
    # Markdown preview (GitHub-Style)
    /usr/bin/grip
    # Markdown preview (Terminal, offline)
    /usr/bin/glow
    # Universal document converter
    /usr/bin/pandoc
    # LaTeX (LuaTeX-Engine, von pandoc als PDF-Engine genutzt)
    /usr/bin/lualatex
)

# Distrobox-pre-hook: wird von distrobox-enter erstellt, fehlt bei NixOS 1.8.0
# Das Hook-File wird von pacman bei jeder Transaktion erwartet
if [ ! -f /etc/distrobox-pre-hook.sh ]; then
    printf '#!/bin/sh\nexit 0\n' > /etc/distrobox-pre-hook.sh
    chmod +x /etc/distrobox-pre-hook.sh
fi

# Stale pacman lock entfernen (kann von abgebrochenem vorherigen Lauf stammen)
rm -f /var/lib/pacman/db.lck

# Setup Chaotic-AUR (idempotent)
pacman-key --init
pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
pacman-key --lsign-key 3056513887B78AEB
pacman -U --noconfirm \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

if ! grep -q '\[chaotic-aur\]' /etc/pacman.conf; then
    printf '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n' >> /etc/pacman.conf
fi

pacman -Sy --noconfirm paru

# Pakete installieren
[[ ${#CHAOTIC_AUR[@]} -gt 0 ]] && pacman -S --noconfirm "${CHAOTIC_AUR[@]}"
[[ ${#PARU[@]} -gt 0 ]] && sudo -u "$(getent passwd 1000 | cut -d: -f1)" -H paru -S --noconfirm "${PARU[@]}"


# Binaries auf den Host exportieren
# Desktop (UID 1000): distrobox-export nach ~/.local/bin
# Headless/root (kein UID 1000): Wrapper manuell nach /usr/local/bin
CONTAINER_NAME="arch-rolling-system"
USER_NAME="$(getent passwd 1000 2>/dev/null | cut -d: -f1)"
if [ -n "$USER_NAME" ]; then
    for bin in "${EXPORT_BINS[@]}"; do
        sudo -u "$USER_NAME" -H distrobox-export --bin "$bin"
    done
else
    # /root/.local/bin ist via distrobox home-mount auf Host und Container sichtbar
    mkdir -p /root/.local/bin
    for bin in "${EXPORT_BINS[@]}"; do
        bin_name="$(basename "$bin")"
        printf '#!/bin/sh\nexec distrobox-enter -n "%s" -- "%s" "$@"\n' \
            "$CONTAINER_NAME" "$bin" > "/root/.local/bin/$bin_name"
        chmod +x "/root/.local/bin/$bin_name"
    done
fi
