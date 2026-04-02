#!/bin/sh
unset WAYLAND_DISPLAY
unset WAYLAND_SOCKET
export GDK_BACKEND=x11
export QT_QPA_PLATFORM=xcb
export SDL_VIDEODRIVER=x11
exec gnome-session --session=ubuntu-xrdp --disable-acceleration-check
