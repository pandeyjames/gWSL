#!/bin/sh

if [ -r /etc/profile ]; then
    . /etc/profile
fi
if [ -r "$HOME/.bash_profile" ]; then
    . "$HOME/.bash_profile"
elif [ -r "$HOME/.bash_login" ]; then
    . "$HOME/.bash_login"
elif [ -r "$HOME/.profile" ]; then
    . "$HOME/.profile"
fi

unset DBUS_SESSION_BUS_ADDRESS
unset SESSION_MANAGER
unset PULSE_SERVER
unset PULSE_COOKIE
unset WAYLAND_DISPLAY
unset WAYLAND_SOCKET
unset XDG_ACTIVATION_TOKEN
export GDK_BACKEND=x11
export QT_QPA_PLATFORM=xcb
export SDL_VIDEODRIVER=x11

export DESKTOP_SESSION=ubuntu-xrdp
export XDG_SESSION_DESKTOP=ubuntu-xrdp
export XDG_CURRENT_DESKTOP=ubuntu:GNOME
export XDG_SESSION_TYPE=x11
export GDMSESSION=ubuntu-xrdp
export GNOME_SHELL_SESSION_MODE=ubuntu
export XDG_MENU_PREFIX=gnome-
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export XAUTHORITY=${XAUTHORITY:-$HOME/.Xauthority}

if [ ! -d "$XDG_RUNTIME_DIR" ]; then
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
fi

SYSTEMD_MODE=false
if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    SYSTEMD_MODE=true
fi

# Under real systemd, user-activated services need the X11/xRDP environment
# imported early, otherwise GNOME session helpers can start without DISPLAY.
if [ "$SYSTEMD_MODE" = true ]; then
    mkdir -p "$XDG_RUNTIME_DIR/pulse"
    rm -f "$XDG_RUNTIME_DIR/pulse/native" "$XDG_RUNTIME_DIR/pulse/pid"
    export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
    export PULSE_SCRIPT=/etc/xrdp/pulse/default.pa

    if systemctl --user show-environment >/dev/null 2>&1; then
        systemctl --user import-environment \
            DISPLAY XAUTHORITY XDG_RUNTIME_DIR XDG_SESSION_TYPE \
            XDG_SESSION_DESKTOP XDG_CURRENT_DESKTOP DESKTOP_SESSION \
            GDMSESSION GNOME_SHELL_SESSION_MODE XDG_MENU_PREFIX \
            GTK2_RC_FILES QT_QPA_PLATFORMTHEME QT_X11_NO_MITSHM \
            QT_ACCESSIBILITY MOZ_FORCE_DISABLE_E10S \
            MOZ_LAYERS_ALLOW_SOFTWARE_GL WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS \
            LIBGL_DRI2_DISABLE LIBGL_DRI3_DISABLE QTWEBENGINE_CHROMIUM_FLAGS \
            GVFS_REMOTE_VOLUME_MONITOR_IGNORE XRDP_SESSION XRDP_SOCKET_PATH \
            XRDP_PULSE_SINK_SOCKET XRDP_PULSE_SOURCE_SOCKET PULSE_SCRIPT \
            XRDP_USE_HELPER XRDP_USE_MULTISESSION >/dev/null 2>&1 || true
    fi

    if command -v dbus-update-activation-environment >/dev/null 2>&1; then
        dbus-update-activation-environment --systemd \
            DISPLAY XAUTHORITY XDG_RUNTIME_DIR XDG_SESSION_TYPE \
            XDG_SESSION_DESKTOP XDG_CURRENT_DESKTOP DESKTOP_SESSION \
            GDMSESSION GNOME_SHELL_SESSION_MODE XDG_MENU_PREFIX \
            GTK2_RC_FILES QT_QPA_PLATFORMTHEME QT_X11_NO_MITSHM \
            QT_ACCESSIBILITY MOZ_FORCE_DISABLE_E10S \
            MOZ_LAYERS_ALLOW_SOFTWARE_GL WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS \
            LIBGL_DRI2_DISABLE LIBGL_DRI3_DISABLE QTWEBENGINE_CHROMIUM_FLAGS \
            GVFS_REMOTE_VOLUME_MONITOR_IGNORE XRDP_SESSION XRDP_SOCKET_PATH \
            XRDP_PULSE_SINK_SOCKET XRDP_PULSE_SOURCE_SOCKET PULSE_SCRIPT \
            XRDP_USE_HELPER XRDP_USE_MULTISESSION >/dev/null 2>&1 || true
    fi

    # WSLg can leave behind unusable PulseAudio runtime state. For xRDP
    # sessions, start a clean user PulseAudio instance with the xRDP profile.
    systemctl --user stop pulseaudio.service pulseaudio.socket >/dev/null 2>&1 || true
    systemctl --user reset-failed pulseaudio.service pulseaudio.socket >/dev/null 2>&1 || true
    rm -f "$XDG_RUNTIME_DIR/pulse/native" "$XDG_RUNTIME_DIR/pulse/pid"
    if [ -f "$PULSE_SCRIPT" ] && ! pgrep -u "$(id -u)" -x pulseaudio >/dev/null 2>&1; then
        pulseaudio --start -nF "$PULSE_SCRIPT" >/dev/null 2>&1 || true
    fi

    # GNOME over xRDP on WSL needs a direct launch here. Going through the
    # distro Xsession wrapper under systemd causes helpers to come up before
    # the xRDP/X11 environment is fully visible.
    exec gnome-session --session=ubuntu-xrdp --disable-acceleration-check
fi

if [ -x /etc/X11/Xsession ]; then
    exec /etc/X11/Xsession
fi

if command -v dbus-run-session >/dev/null 2>&1; then
    exec dbus-run-session -- gnome-session --session=ubuntu-xrdp
fi

exec gnome-session --session=ubuntu-xrdp
