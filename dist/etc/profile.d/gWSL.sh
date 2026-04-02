#!/bin/bash

system32_path="/mnt/c/Windows/System32"
if [ -n "${PATH##*${system32_path}}" -a -n "${PATH##*${system32_path}:*}" ]; then
    export PATH=$PATH:${system32_path}
fi

games_path="/usr/games"
if [ -n "${PATH##*${games_path}}" -a -n "${PATH##*${games_path}:*}" ]; then
    export PATH=$PATH:${games_path}
fi

# Ensure base distro defaults xdg path are set if nothing filed up some
# defaults yet.
if [ -z "$XDG_DATA_DIRS" ]; then
    export XDG_DATA_DIRS="/usr/local/share:/usr/share"
fi

export RUNLEVEL=2
export NO_AT_BRIDGE=1
export GTK2_RC_FILES=$HOME/.config/gtkrc-2.0
export QT_QPA_PLATFORMTHEME=gtk2
export QT_X11_NO_MITSHM=1
export QT_ACCESSIBILITY=0
export DESKTOP_SESSION=ubuntu
export XDG_SESSION_TYPE=x11
export XDG_SESSION_DESKTOP=ubuntu
export XDG_CURRENT_DESKTOP=ubuntu:GNOME
export GDMSESSION=ubuntu
export GNOME_SHELL_SESSION_MODE=ubuntu
export XDG_MENU_PREFIX=gnome-
export XDG_CONFIG_HOME=$HOME/.config
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export XDG_CACHE_HOME=$HOME/.cache
export XDG_DATA_HOME=$HOME/.local/share
unset WAYLAND_DISPLAY
unset WAYLAND_SOCKET
unset XDG_ACTIVATION_TOKEN
unset PULSE_SERVER
unset PULSE_COOKIE
export GDK_BACKEND=x11
export QT_QPA_PLATFORM=xcb
export SDL_VIDEODRIVER=x11
export MOZ_FORCE_DISABLE_E10S=1
export MOZ_LAYERS_ALLOW_SOFTWARE_GL=1
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
export LIBGL_DRI2_DISABLE=true
export LIBGL_DRI3_DISABLE=true
export QTWEBENGINE_CHROMIUM_FLAGS="--single-process"
export GVFS_REMOTE_VOLUME_MONITOR_IGNORE=1
