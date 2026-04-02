# gWSL

gWSL installs a full Ubuntu GNOME desktop on WSL and exposes it through xRDP for use with the Windows Remote Desktop client (`mstsc`). The project is built around a scripted install flow that imports an Ubuntu root filesystem, configures GNOME, xRDP, audio support, service startup, and generates the Windows-side shortcuts needed to launch the desktop and console sessions.

## What It Supports

- Ubuntu 20.04 (Focal)
- Ubuntu 22.04 (Jammy)
- Ubuntu 24.04 (Noble)
- Full GNOME desktop session over xRDP
- WSL2-based deployment with real systemd
- Audio redirection over RDP
- Per-distro Windows shortcuts for desktop and console access
- Multiple gWSL distros side by side with custom names and ports

The current project is GNOME-first. It no longer describes the older xWSL branding or the previous minimal/XFCE-oriented setup.

## How It Works

The main installer is [`gWSL.cmd`](./gWSL.cmd). It:

1. Downloads or reuses the selected Ubuntu rootfs image.
2. Imports the distro with `LxRunOffline`.
3. Converts the distro to WSL2.
4. Installs prerequisite packages and the GNOME desktop.
5. Installs and configures xRDP, Xorg integration, and session startup files.
6. Applies WSL-specific runtime fixes for systemd, dbus, PulseAudio, and xRDP startup.
7. Prompts for a primary Linux user and generates desktop/console launchers on Windows.

Installed distros are created under [`vms/`](./vms/) by default:

- `vms/gWSL20`
- `vms/gWSL24`
- `vms/<your custom distro name>`

The `vms` directory is intentionally ignored by Git except for [`vms/.gitkeep`](./vms/.gitkeep).

## Requirements

- Windows 10/11 with WSL enabled
- Administrative rights for the installer
- WSL2 support available on the machine
- Internet access for Ubuntu packages and project assets
- Microsoft Remote Desktop client (`mstsc.exe`)

## Install

Run from an elevated Command Prompt or PowerShell inside the project directory:

```powershell
.\gWSL.cmd
```

The installer asks for:

- Ubuntu version: `20.04`, `22.04`, or `24.04`
- Distro name
- xRDP port
- SSH port
- Display scale
- Optional Windows Defender exclusion

Example:

```text
[gWSL Installer 20260102]

Enter '0' for Ubuntu 20.04 (Focal), '2' for Ubuntu 22.04 (Jammy) or '4' for Ubuntu 24.04 (Noble) [4]: 0
Enter a unique name for your distro or hit Enter for default.
Keep this name simple, no space or underscore characters [gWSL]: gWSL20
Port number for xRDP traffic or hit Enter to use default [3399]:
Port number for SSHd traffic or hit Enter to use default [3322]:
Set a custom display scale or hit Enter for Windows default [1.5]:
Not recommended! Hit X to eXclude distro from Windows Defender:
```

At the end of the install, the script prompts for the primary Linux user and password, configures sudo access, and writes:

- `<distro> (<user>) Desktop.rdp`
- `<distro> (<user>) Console.cmd`

Those shortcuts are copied to the Windows desktop.

## Runtime Model

gWSL now uses real systemd inside the distro.

Relevant runtime pieces include:

- [`dist/etc/wsl.conf`](./dist/etc/wsl.conf)
- [`dist/usr/local/bin/initwsl`](./dist/usr/local/bin/initwsl)
- [`dist/etc/xrdp/startwm.sh`](./dist/etc/xrdp/startwm.sh)
- [`dist/usr/share/gnome-session/sessions/ubuntu-xrdp.session`](./dist/usr/share/gnome-session/sessions/ubuntu-xrdp.session)

The xRDP session is launched as a GNOME X11 session tailored for WSL and Remote Desktop. The session startup logic also strips incompatible WSLg environment variables so apps launched inside the RDP desktop stay in the same desktop session instead of appearing as separate Windows-hosted WSLg windows.

## Audio

The project supports RDP audio playback. The installer and runtime configuration include the xRDP PulseAudio integration required for audio inside the GNOME desktop.

## Project Layout

Important files:

- [`gWSL.cmd`](./gWSL.cmd): main Windows installer
- [`gWSL.rdp`](./gWSL.rdp): RDP template
- [`gWSL.xml`](./gWSL.xml): scheduled-task template
- [`dist/`](./dist/): files copied into the Linux distro
- [`vms/`](./vms/): local distro storage, ignored by Git

Important distro-side files under `dist/`:

- [`dist/etc/profile.d/gWSL.sh`](./dist/etc/profile.d/gWSL.sh)
- [`dist/etc/xrdp/xrdp.ini`](./dist/etc/xrdp/xrdp.ini)
- [`dist/etc/xrdp/startwm.sh`](./dist/etc/xrdp/startwm.sh)
- [`dist/usr/local/bin/initwsl`](./dist/usr/local/bin/initwsl)
- [`dist/usr/local/bin/restartwsl`](./dist/usr/local/bin/restartwsl)

## Notes

- New installs are intended to run on WSL2.
- The installer now checks whether xRDP actually starts before auto-launching the desktop shortcut.
- Kora icon theme setup is cosmetic only. GNOME and xRDP do not depend on it.
- The repository stores templates and runtime configuration, not the live VM contents.

## Uninstall

Each installed distro folder contains an uninstall script, for example:

- `Uninstall gWSL20.cmd`

You can also unregister a distro with WSL directly:

```powershell
wsl --terminate gWSL20
wsl --unregister gWSL20
```

## Git Notes

The repository keeps `vms/` as an empty placeholder in Git and ignores live distro contents. That allows the repo to track the installer and distro templates without committing large local VHDX files.
