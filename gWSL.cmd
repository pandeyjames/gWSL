@ECHO OFF
NET SESSION >NUL 2>&1
IF %ERRORLEVEL% NEQ 0 (
  ECHO Requesting administrative rights...
  > "%TEMP%\gWSL-elevated.cmd" ECHO @CD /D "%CD%"
  >> "%TEMP%\gWSL-elevated.cmd" ECHO @CALL "%~f0"
  >> "%TEMP%\gWSL-elevated.cmd" ECHO @ECHO.
  >> "%TEMP%\gWSL-elevated.cmd" ECHO @ECHO Elevated session finished. Press any key to close this window.
  >> "%TEMP%\gWSL-elevated.cmd" ECHO @PAUSE ^>NUL
  POWERSHELL -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:ComSpec -Verb RunAs -ArgumentList @('/k', '\"%TEMP%\\gWSL-elevated.cmd\"')"
  GOTO ENDSCRIPT
)
ECHO Administrator check passed...

REM ============================================================================
REM CONFIGURATION SECTION
REM ============================================================================
COLOR 1F
SET WSLREV=20260102
SET DISTRO=gWSL
SET GITORG=DesktopECHO
SET GITPRJ=gWSL
SET BRANCH=master
SET BASE=https://github.com/%GITORG%/%GITPRJ%/raw/%BRANCH%
SET RDPPRT_DEFAULT=3399
SET SSHPRT_DEFAULT=3322
SET XRDP_VER=v0.10.5
SET XORGXRDP_VER=v0.10.5

REM ============================================================================
REM INITIALIZATION
REM ============================================================================
REM Enable WSL if required
POWERSHELL -Command "$WSL = Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Windows-Subsystem-Linux' ; if ($WSL.State -eq 'Disabled') {Enable-WindowsOptionalFeature -FeatureName $WSL.FeatureName -Online}"

REM Find system DPI setting
IF NOT EXIST "%TEMP%\windpi.ps1" COPY /Y ".\windpi.ps1" "%TEMP%\windpi.ps1" > NUL
FOR /f "delims=" %%a in ('powershell -ExecutionPolicy bypass -command "%TEMP%\windpi.ps1" ') do set "WINDPI=%%a"

REM ============================================================================
REM USER INPUT SECTION
REM ============================================================================
:DI
CLS && SET RUNSTART=%date% @ %time:~0,5%

REM Prevent installation to System32
IF EXIST .\CMD.EXE CD ..\..
SET REPOFULL=%CD%
FOR /f "delims=" %%a in ('powershell -NoProfile -Command "'%REPOFULL:~0,1%'.ToLower()"') do set "REPODRIVE=%%a"
SET REPOPATH=%REPOFULL:~2%
SET REPOPATH=%REPOPATH:\=/%
SET REPOWSL=/mnt/%REPODRIVE%%REPOPATH%

ECHO [gWSL Installer %WSLREV%]
ECHO:

REM Get Ubuntu version choice
SET UBUVER=4
SET /p UBUVER=Enter '0' for Ubuntu 20.04 (Focal), '2' for Ubuntu 22.04 (Jammy) or '4' for Ubuntu 24.04 (Noble) [4]: 
IF "%UBUVER%"=="" SET UBUVER=4
IF NOT "%UBUVER%"=="0" IF NOT "%UBUVER%"=="2" IF NOT "%UBUVER%"=="4" (
  ECHO. & ECHO Invalid Ubuntu version selection. Choose 0, 2, or 4.
  PAUSE & GOTO DI
)

REM Get custom distro name
ECHO: & ECHO Enter a unique name for your distro or hit Enter for default.
SET /p DISTRO=Keep this name simple, no space or underscore characters [gWSL]: 

REM Validate distro name doesn't already exist
IF EXIST "%DISTRO%" (
  ECHO. & ECHO Folder exists with that name, choose a new folder name. & PAUSE & GOTO DI
)

REM Check if distro is already registered with WSL
WSL.EXE -d %DISTRO% -e . > "%TEMP%\InstCheck.tmp"
FOR /f %%i in ("%TEMP%\InstCheck.tmp") do set CHKIN=%%~zi 
IF %CHKIN% == 0 (
  ECHO. & ECHO There is a WSL distribution registered with that name; uninstall it or choose a new name.
  PAUSE & GOTO DI
)

REM Get DNS settings from system
FOR /f "tokens=2" %%a in ('nslookup . 2^>nul ^| findstr /C:"Address:"') do (set "DNS=nameserver %%a")

REM Get port numbers for services
ECHO:
SET RDPPRT=%RDPPRT_DEFAULT%
SET /p RDPPRT=    Port number for xRDP traffic or hit Enter to use default [%RDPPRT_DEFAULT%]: 

SET SSHPRT=%SSHPRT_DEFAULT%
SET /p SSHPRT=Port number for SSHd traffic or hit Enter to use default [%SSHPRT_DEFAULT%]: 

REM Get DPI scale setting
SET /p WINDPI=Set a custom display scale or hit Enter for Windows default [%WINDPI%]: 

REM Calculate Linux DPI values (96 DPI base for X11, 32 for panel height)
FOR /f "delims=" %%a in ('PowerShell -Command 96 * "%WINDPI%" ') do set "LINDPI=%%a"
FOR /f "delims=" %%a in ('PowerShell -Command 32 * "%WINDPI%" ') do set "PANEL=%%a"

REM Windows Defender exclusion option
SET DEFEXL=NONO
SET /p DEFEXL=Not recommended!  Hit X to eXclude distro from Windows Defender: 

REM ============================================================================
REM SETUP DISTRO PATH
REM ============================================================================
SET DISTROFULL=%CD%\vms\%DISTRO%
SET _rlt=%DISTROFULL:~2,2%
IF "%_rlt%"=="\\" SET DISTROFULL=%CD%%DISTRO%
SET GO="%DISTROFULL%\LxRunOffline.exe" r -n "%DISTRO%" -c
SET UBUIMG=https://github.com/DesktopECHO/wsl-images/releases/latest/download/ubuntu-2%UBUVER%.04-amd64.tar.gz
SET LDAP_PKG=/tmp/gWSL/deb/libldap-2.5-0_*.deb
SET XRDP_AUDIO_PKG=/tmp/gWSL/deb/pulseaudio-module-xrdp_0.6-1prebuild0~0xwsl%UBUVER%_amd64.deb
SET PKGINSTALL=apt-fast -qqy install
SET EXTRA_PREREQ_PKGS=libfdk-aac2 libisl23 xcvt
IF "%UBUVER%"=="0" SET UBUIMG=https://cdimages.ubuntu.com/ubuntu-base/focal/daily/current/focal-base-amd64.tar.gz
IF "%UBUVER%"=="0" SET LDAP_PKG=libldap-2.4-2
IF "%UBUVER%"=="0" SET XRDP_AUDIO_PKG=
IF "%UBUVER%"=="0" SET PKGINSTALL=apt-get -qqy install
IF "%UBUVER%"=="0" SET EXTRA_PREREQ_PKGS=libfdk-aac1 libisl22

REM ============================================================================
REM DOWNLOAD AND PREPARE UBUNTU IMAGE
REM ============================================================================
:GETIMG
IF NOT EXIST "%TEMP%\Ubuntu2%UBUVER%04.tar.gz" (
  POWERSHELL.EXE -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri '%UBUIMG%' -OutFile '%TEMP%\Ubuntu2%UBUVER%04.tar.gz'"
)
IF NOT EXIST "%TEMP%\Ubuntu2%UBUVER%04.tar.gz" (
  ECHO. & ECHO Failed to download Ubuntu rootfs from:
  ECHO   %UBUIMG%
  PAUSE & GOTO ENDSCRIPT
)

REM Create distro directory structure
%DISTROFULL:~0,1%: 
MKDIR "%CD%\vms" > NUL 2>&1
MKDIR "%DISTROFULL%"
CD "%DISTROFULL%"
MKDIR logs > NUL

REM Log installation inputs
(
  ECHO [gWSL Inputs]
  ECHO.
  ECHO.   Distro: %DISTRO%
  ECHO.     Path: %DISTROFULL%
  ECHO. RDP Port: %RDPPRT%
  ECHO. SSH Port: %SSHPRT%
  ECHO.DPI Scale: %WINDPI%
  ECHO.
) > ".\logs\%TIME:~0,2%%TIME:~3,2%%TIME:~6,2% gWSL Inputs.log"

REM Download LxRunOffline tool if needed
IF NOT EXIST "%TEMP%\LxRunOffline.exe" (
  COPY /Y ".\LxRunOffline.exe" "%TEMP%\LxRunOffline.exe" > NUL
)

REM ============================================================================
REM CREATE UNINSTALL SCRIPT
REM ============================================================================
SETLOCAL ENABLEDELAYEDEXPANSION
(
  ECHO @COLOR 1F
  ECHO @ECHO Ensure you are running this command with elevated rights.  Uninstall %DISTRO%?
  ECHO @PAUSE
  ECHO @COPY /Y "%DISTROFULL%\LxRunOffline.exe" "%APPDATA%"
  ECHO @POWERSHELL -Command "Remove-Item ([Environment]::GetFolderPath('Desktop')+'\%DISTRO% (*) Console.cmd')"
  ECHO @POWERSHELL -Command "Remove-Item ([Environment]::GetFolderPath('Desktop')+'\%DISTRO% (*) Desktop.rdp')"
  ECHO @SCHTASKS /Delete /TN:%DISTRO% /F
  ECHO @CLS
  ECHO @ECHO Uninstalling %DISTRO%, please wait...
  ECHO @CD ..
  ECHO @WSLCONFIG.EXE /t %DISTRO% ^&^& WSL.EXE --unregister %DISTRO%
  ECHO @"%APPDATA%\LxRunOffline.exe" ur -n %DISTRO%
  ECHO @NETSH AdvFirewall Firewall del rule name="%DISTRO% xRDP"
  ECHO @NETSH AdvFirewall Firewall del rule name="%DISTRO% Secure Shell"
  ECHO @NETSH AdvFirewall Firewall del rule name="%DISTRO% Avahi Multicast DNS"
  ECHO @RD /S /Q "%DISTROFULL%"
) > "%DISTROFULL%\Uninstall %DISTRO%.cmd"
ENDLOCAL
ECHO:

REM ============================================================================
REM INSTALL WSL DISTRIBUTION
REM ============================================================================
ECHO Installing gWSL Distro [%DISTRO%] to "%DISTROFULL%"
ECHO This will take a few minutes, please wait...

REM Add Windows Defender exclusions if requested
IF %DEFEXL%==X (
  COPY /Y ".\excludeWSL.ps1" "%DISTROFULL%\excludeWSL.ps1" > NUL
  ECHO [%TIME:~0,8%] Windows Defender exclusion
  POWERSHELL.EXE -ExecutionPolicy Bypass -Command ".\excludeWSL.ps1" "%DISTROFULL%"
  DEL ".\excludeWSL.ps1"
)

ECHO: & ECHO [%TIME:~0,8%] Installing Ubuntu             (~0m45s)
"%TEMP%\LxRunOffline.exe" "i" "-n" "%DISTRO%" "-f" "%TEMP%\Ubuntu2%UBUVER%04.tar.gz" "-d" "%DISTROFULL%" "-v" "2"

REM Set permissions and finalize installation
(FOR /F "usebackq delims=" %%v IN (`PowerShell -Command "whoami"`) DO set "WAI=%%v")
ICACLS "%DISTROFULL%" /grant "%WAI%":(CI)(OI)F > NUL
COPY /Y "%TEMP%\LxRunOffline.exe" "%DISTROFULL%" > NUL
"%DISTROFULL%\LxRunOffline.exe" sd -n "%DISTRO%" 

REM LxRunOffline imports the distro as WSL2 directly; avoid a noisy follow-up
REM conversion step here because the new distro may not yet be visible to
REM wsl.exe even though LxRunOffline can already run it.
ECHO [%TIME:~0,8%] Imported distro as WSL2

REM ============================================================================
REM PACKAGE INSTALLATION SECTION
REM ============================================================================

REM Remove unnecessary packages
ECHO [%TIME:~0,8%] Remove un-needed packages
%GO% "echo 'exit 0' > /etc/init.d/udev ; PKGS='' ; for PAT in needrestart apparmor* bc* bcache-tools* bolt* btrfs-progs* busybox-initramfs* cloud-guest-utils* cloud-init* cloud-initramfs-copymods* cloud-initramfs-dyn-netconf* lvm2* lxd-agent-loader* mdadm* modemmanager* multipath-tools* netplan.io* open-iscsi* open-vm-tools* overlayroot* plymouth* plymouth-theme-ubuntu-text* sbsigntool* secureboot-db* sg3-utils* snapd* sosreport* squashfs-tools* thin-provisioning-tools* tpm-udev* ubuntu-minimal* ubuntu-server* usb-modeswitch* usb-modeswitch-data* zerofree* ; do for P in $(dpkg-query -W -f='${Package}\n' \"$PAT\" 2>/dev/null); do PKGS=\"$PKGS $P\" ; done ; done ; if [ -n \"$PKGS\" ]; then SUDO_FORCE_REMOVE=yes DEBIAN_FRONTEND=noninteractive apt-get -qqy purge --autoremove $PKGS ; fi"

REM Setup apt-fast package manager and clone gWSL repository
ECHO [%TIME:~0,8%] Setup apt-fast and clone repo (~1m00s)
%GO% "rm -rf /etc/apt/apt.conf.d/20snapd.conf /etc/systemd/system/snap* /var/cache/snapd /etc/rc2.d/S01whoopsie /etc/init.d/console-setup.sh ; echo 'echo 1' > /usr/sbin/runlevel ; mkdir -p /tmp/gWSL ; cp -Rp '%REPOWSL%'/deb /tmp/gWSL/ ; cp -Rp '%REPOWSL%'/dist /tmp/gWSL/ ; cp -p '%REPOWSL%'/gWSL.rdp '%REPOWSL%'/gWSL.xml '%REPOWSL%'/kora-1.6.0.zip /tmp/gWSL/ ; sed -i 's/\r$//' /tmp/gWSL/dist/usr/local/bin/apt-fast /tmp/gWSL/dist/usr/local/bin/initwsl /tmp/gWSL/dist/usr/local/bin/restartwsl /tmp/gWSL/dist/etc/profile.d/gWSL.sh /tmp/gWSL/dist/etc/xrdp/startwm.sh /tmp/gWSL/dist/etc/init.d/xrdp /tmp/gWSL/dist/etc/systemctl3.py /tmp/gWSL/dist/etc/skel/.profile /tmp/gWSL/dist/etc/skel/.bashrc /tmp/gWSL/dist/etc/skel/.bash_logout /tmp/gWSL/dist/etc/skel/.xsession ; if [ '%UBUVER%' != '0' ]; then dpkg -i /tmp/gWSL/deb/aria2_*.deb /tmp/gWSL/deb/libaria2-0_*.deb /tmp/gWSL/deb/libc-ares2_*.deb /tmp/gWSL/deb/libssh2-1_*.deb ; chmod +x /tmp/gWSL/dist/usr/local/bin/apt-fast ; cp -p /tmp/gWSL/dist/usr/local/bin/apt-fast /usr/local/bin ; fi ; mv /tmp/gWSL/dist/etc/dpkg/dpkg.cfg.d/01_nodoc /etc/dpkg/dpkg.cfg.d ; apt-get update ; DEBIAN_FRONTEND=noninteractive apt-get -qqy install adduser sudo openssh-server wget ca-certificates locales fonts-dejavu-core systemd gnupg2 dirmngr git >/dev/null 2>&1 ; cd /bin ; if [ '%UBUVER%' == '0' ] && [ -e systemd-sysusers ]; then mv -f systemd-sysusers systemd-sysusers.org 2>/dev/null ; ln -sf echo systemd-sysusers ; fi ; apt-get -fy install > /dev/null 2>&1 ; if [ '%UBUVER%' == '0' ] && [ -e /bin/systemd-sysusers.org ]; then mv -f /bin/systemd-sysusers.org /bin/systemd-sysusers ; fi ; locale-gen en_US.UTF-8 >/dev/null 2>&1 ; update-locale LANG=en_US.UTF-8 >/dev/null 2>&1 ; mkdir -p /usr/share/fonts/truetype ; # bootstrap complete"

REM Install prerequisite components
ECHO [%TIME:~0,8%] Prerequisite components       (~1m45s)
%GO% "LEGACY_DEBS=$(find /tmp/gWSL/deb -maxdepth 1 -type f \( -name '*gconf*.deb' -o -name '*gksu*.deb' -o -name '*keyring*.deb' -o -name 'multiarch-support_*.deb' \) -printf '%p ' 2>/dev/null) ; DEBIAN_FRONTEND=noninteractive %PKGINSTALL% $LEGACY_DEBS %LDAP_PKG% software-properties-common acl accountsservice apt-config-icons apt-config-icons-hidpi apt-config-icons-large apt-config-icons-large-hidpi arc-theme arj avahi-daemon base-files binutils cairo-5c dbus-x11 dconf-gsettings-backend dconf-service dialog distro-info-data dumb-init fonts-cascadia-code gir1.2-ibus-1.0 gstreamer1.0-tools ibus ibus-data ibus-gtk ibus-gtk3 inetutils-syslogd lhasa libcairo-5c0 libdbus-glib-1-2 libde265-0 libdrm-intel1 libegl-mesa0 libegl1 %EXTRA_PREREQ_PKGS% libfs6 libgbm1 libgif7 libgl1 libglu1-mesa libglx-mesa0 libglx0 libgstreamer1.0-0 libgtk-3-bin libgtk-3-common libgtkd-3-0 libheif1 libice6 libid3tag0 libimlib2 liblhasa0 libmpc3 libnspr4 libnss-mdns libnss3 libopengl0 libpackagekit-glib2-18 libpolkit-agent-1-0 libpolkit-gobject-1-0 libsecret-1-0 libsm6 libvte-2.91-0 libvte-2.91-common libvted-3-0 libwayland-server0 libx11-xcb1 libxatracker2 libxaw7 libxcb-randr0 libxcb-shape0 libxcomposite1 libxcursor1 libxdamage1 libxfixes3 libxfont2 libxft2 libxi6 libxinerama1 libxkbfile1 libxmu6 libxmuu1 libxpm4 libxrandr2 libxss1 libxtst6 libxv1 libxvmc1 libxxf86dga1 libxxf86vm1 mesa-vulkan-drivers moreutils nickle packagekit packagekit-tools policykit-1 putty putty-tools python3-distupgrade python3-packaging python3-psutil python3-xdg ssh ssl-cert sudo openssh-server ubuntu-release-upgrader-core unace unzip upower wget x11-apps x11-common x11-session-utils x11-utils x11-xfs-utils x11-xkb-utils x11-xserver-utils x264 xauth xbase-clients xdg-utils xfonts-100dpi xfonts-base xfonts-encodings xfonts-scalable xfonts-utils xinit xinput xorg xserver-common xserver-xorg xserver-xorg-core xserver-xorg-input-all xserver-xorg-input-libinput xserver-xorg-legacy xserver-xorg-video-dummy xvfb zip --no-install-recommends ; echo 'exit 0' > /bin/setfacl"

REM Install Kora icon theme
ECHO [%TIME:~0,8%] Kora icon theme
%GO% "if command -v unzip >/dev/null 2>&1 && [ -f /tmp/gWSL/kora-1.6.0.zip ]; then cd /tmp ; unzip -q /tmp/gWSL/kora-1.6.0.zip ; mv kora-1.6.0/kora* /usr/share/icons/ ; rm -rf kora-* ; fi"

REM Install GNOME desktop environment
ECHO [%TIME:~0,8%] GNOME desktop environment     (~3m00s)
%GO% "SEAMONKEY_DEB=$(find /tmp/gWSL/deb -maxdepth 1 -type f -name 'seamonkey*.deb' -printf '%p ' 2>/dev/null) ; XRDP_DEBS=$(find /tmp/gWSL/deb -maxdepth 1 -type f \( -name 'xrdp*.deb' -o -name 'xorgxrdp*.deb' -o -name 'libx264*.deb' \) -printf '%p ' 2>/dev/null) ; export DEBIAN_FRONTEND=noninteractive ; export UCF_FORCE_CONFFOLD=1 ; export NEEDRESTART_MODE=a ; DEBIAN_FRONTEND=noninteractive %PKGINSTALL% $SEAMONKEY_DEB adwaita-icon-theme dmz-cursor-theme evince file-roller gedit gnome-control-center gnome-session gnome-shell gnome-shell-extension-appindicator gnome-shell-extensions gnome-terminal gvfs-fuse libaacs0 libconfig9 libnotify-bin libosmesa6 librsvg2-common libwebrtc-audio-processing1 lrzip lzip lzop mesa-utils mesa-va-drivers mesa-vdpau-drivers nautilus ncompress pavucontrol pulseaudio synaptic ubuntu-desktop ubuntu-session wslu xarchiver yaru-theme-gnome-shell ; echo 'exit 0' > /usr/bin/lspci ; if [ '%UBUVER%' = '0' ]; then cd /tmp ; rm -rf xrdp-src xorgxrdp-src pa-src pulseaudio-module-xrdp-src ; git clone --depth 1 --branch %XRDP_VER% --recursive https://github.com/neutrinolabs/xrdp.git xrdp-src ; git clone --depth 1 --branch %XORGXRDP_VER% https://github.com/neutrinolabs/xorgxrdp.git xorgxrdp-src ; git clone --depth 1 --branch v0.8 https://github.com/neutrinolabs/pulseaudio-module-xrdp.git pulseaudio-module-xrdp-src ; sed -i \"s/^\\s*apt-get upgrade$/DEBIAN_FRONTEND=noninteractive apt-get -yq -o Dpkg::Options::=--force-confold upgrade/\" /tmp/xrdp-src/scripts/install_xrdp_build_dependencies_with_apt.sh ; sed -i \"s/^\\s*apt-get -yq /DEBIAN_FRONTEND=noninteractive apt-get -yq -o Dpkg::Options::=--force-confold /\" /tmp/xrdp-src/scripts/install_xrdp_build_dependencies_with_apt.sh ; sed -i \"s/^\\s*apt-get -yq /DEBIAN_FRONTEND=noninteractive apt-get -yq -o Dpkg::Options::=--force-confold /\" /tmp/xorgxrdp-src/scripts/install_xorgxrdp_build_dependencies_with_apt.sh ; /tmp/xrdp-src/scripts/install_xrdp_build_dependencies_with_apt.sh min ; /tmp/xorgxrdp-src/scripts/install_xorgxrdp_build_dependencies_with_apt.sh ; DEBIAN_FRONTEND=noninteractive apt-get -yq -o Dpkg::Options::=--force-confold install dpkg-dev devscripts equivs intltool libfuse3-dev ; sed -i 's/^# deb-src /deb-src /' /etc/apt/sources.list ; apt-get update ; DEBIAN_FRONTEND=noninteractive apt-get -yq -o Dpkg::Options::=--force-confold build-dep pulseaudio ; mkdir -p /tmp/pa-src ; cd /tmp/pa-src ; apt-get source pulseaudio ; PULSE_DIR=$(find /tmp/pa-src -maxdepth 1 -type d -name 'pulseaudio-*' | head -n1) ; cd \"$PULSE_DIR\" ; ./configure ; cd /tmp/xrdp-src ; ./bootstrap ; ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --with-sysconfsubdir=xrdp --with-systemdsystemunitdir=/lib/systemd/system --enable-fuse ; make -j\"$(nproc)\" ; make install ; cd /tmp/xorgxrdp-src ; ./bootstrap ; ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var ; make -j\"$(nproc)\" ; make install ; cd /tmp/pulseaudio-module-xrdp-src ; ./bootstrap ; PULSE_DIR=\"$PULSE_DIR\" PULSE_CONFIG_DIR=\"$PULSE_DIR\" ./configure ; make -j\"$(nproc)\" ; make install ; ldconfig ; rm -rf /tmp/xrdp-src /tmp/xorgxrdp-src /tmp/pa-src /tmp/pulseaudio-module-xrdp-src ; else DEBIAN_FRONTEND=noninteractive %PKGINSTALL% $XRDP_DEBS --no-install-recommends ; if [ -n '%XRDP_AUDIO_PKG%' ]; then DEBIAN_FRONTEND=noninteractive %PKGINSTALL% %XRDP_AUDIO_PKG% --no-install-recommends ; fi ; fi ; DEBIAN_FRONTEND=noninteractive %PKGINSTALL% falkon qt5-gtk-platformtheme qt5-gtk2-platformtheme ; for unitdir in /usr/lib/systemd/system /lib/systemd/system; do if [ -f \"$unitdir/xrdp.service\" ]; then perl -0pi -e 's/Type=forking/Type=exec/g; s/^PIDFile=.*\\n//mg; s/^User=.*\\n//mg; s/^Group=.*\\n//mg; s/^PermissionsStartOnly=.*\\n//mg; s/^ExecStartPre=.*\\n//mg; s#^ExecStart=.*#ExecStart=/usr/sbin/xrdp $XRDP_OPTIONS --nodaemon#mg; s#^ExecStop=.*\\n##mg;' \"$unitdir/xrdp.service\"; fi; if [ -f \"$unitdir/xrdp-sesman.service\" ]; then perl -0pi -e 's/Type=forking/Type=exec/g; s/^PIDFile=.*\\n//mg; s#^ExecStart=.*#ExecStart=/usr/sbin/xrdp-sesman $SESMAN_OPTIONS --nodaemon#mg; s#^ExecStop=.*\\n##mg; s#^ExecReload=.*#ExecReload=/usr/bin/kill -HUP $MAINPID#mg;' \"$unitdir/xrdp-sesman.service\"; fi; done ; systemctl daemon-reload 2>/dev/null ; rm -f /etc/X11/Xsession.d/10enforce-single-graphical-session"

REM Retrieve Mozilla keys for Seamonkey repository
ECHO [%TIME:~0,8%] Mozilla keys
%GO% "echo 'deb http://downloads.sourceforge.net/project/ubuntuzilla/mozilla/apt all main' > /etc/apt/sources.list.d/seamonkey.list ; apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 2667CA5C ; apt-key export 2667CA5C | gpg --dearmour -o /etc/apt/trusted.gpg.d/seamonkey.gpg --batch --yes"

REM Final cleanup and configuration
ECHO [%TIME:~0,8%] Post-install clean-up
%GO% "apt-get -qqy purge --autoremove ; apt-get clean"

REM Get scheduler path for restart script
%GO% "which schtasks.exe" > "%TEMP%\SCHT.tmp" & set /p SCHT=<"%TEMP%\SCHT.tmp"

REM Configure distro-specific settings
%GO% "sed -i 's#SCHT#%SCHT%#g' /tmp/gWSL/dist/usr/local/bin/restartwsl ; sed -i 's#DISTRO#%DISTRO%#g' /tmp/gWSL/dist/usr/local/bin/restartwsl"

%GO% "sed -i 's/port=3389/port=%RDPPRT%/g' /tmp/gWSL/dist/etc/xrdp/xrdp.ini"
%GO% "sed -i 's/\\h/%DISTRO%/g' /tmp/gWSL/dist/etc/skel/.bashrc ; sed -i 's/\\h/%DISTRO%/g' /root/.bashrc"
%GO% "sed -i 's/#Port 22/Port %SSHPRT%/g' /etc/ssh/sshd_config"
%GO% "sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config"
%GO% "sed -i 's/WSLINSTANCENAME/%DISTRO%/g' /tmp/gWSL/dist/usr/local/bin/initwsl"
%GO% "if [ -f /etc/avahi/avahi-daemon.conf ]; then sed -i 's/#enable-dbus=yes/enable-dbus=no/g' /etc/avahi/avahi-daemon.conf ; sed -i 's/#host-name=foo/host-name=%DISTRO%/g' /etc/avahi/avahi-daemon.conf ; sed -i 's/use-ipv4=yes/use-ipv4=no/g' /etc/avahi/avahi-daemon.conf ; fi"
%GO% "mkdir -p /usr/share/fonts/truetype ; cp /mnt/c/Windows/Fonts/*.ttf /usr/share/fonts/truetype 2>/dev/null || true ; ssh-keygen -A ; id -u xrdp >/dev/null 2>&1 || useradd -r -M -d /var/run/xrdp -s /usr/sbin/nologin xrdp ; adduser xrdp ssl-cert" > NUL
%GO% "chmod 644 /tmp/gWSL/dist/etc/wsl.conf"
%GO% "chmod 755 /tmp/gWSL/dist/etc/profile.d/gWSL.sh /tmp/gWSL/dist/usr/local/bin/restartwsl /tmp/gWSL/dist/usr/local/bin/initwsl /tmp/gWSL/dist/etc/init.d/xrdp /tmp/gWSL/dist/etc/xrdp/startwm.sh /tmp/gWSL/dist/etc/skel/.xsession ; chmod -R 700 /tmp/gWSL/dist/etc/skel/.config ; chmod -R 700 /tmp/gWSL/dist/etc/skel/.local ; chmod 700 /tmp/gWSL/dist/etc/skel/.mozilla"
%GO% "cp -Rp /tmp/gWSL/dist/* / ; cp -Rp /tmp/gWSL/dist/etc/skel/.config /root ; cp -Rp /tmp/gWSL/dist/etc/skel/.local /root ; chown -R xrdp:root /etc/xrdp ; update-rc.d xrdp defaults"
%GO% "if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then systemctl daemon-reload ; systemctl enable xrdp-sesman xrdp ; systemctl restart xrdp-sesman xrdp ; fi"

REM ============================================================================
REM POST-INSTALLATION CONFIGURATION
REM ============================================================================
SET RUNEND=%date% @ %time:~0,5%
CD %DISTROFULL% 
ECHO:
REM Create user account and set password
SET /p XU=Enter name of primary user for %DISTRO%: 
POWERSHELL -Command $prd = read-host "Enter password for %XU%" -AsSecureString ; $BSTR=[System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($prd) ; [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR) > .tmp & set /p PWO=<.tmp

REM Add user and configure sudo privileges
%GO% "useradd -m -p nulltemp -s /bin/bash %XU%"
%GO% "(echo '%XU%:%PWO%') | chpasswd"
%GO% "echo '%XU% ALL=(ALL:ALL) ALL' >> /etc/sudoers"

REM Create RDP connection file with user credentials
%GO% "sed -i 's/PLACEHOLDER/%XU%/g' /tmp/gWSL/gWSL.rdp"
%GO% "sed -i 's/COMPY/localhost/g' /tmp/gWSL/gWSL.rdp"
%GO% "sed -i 's/RDPPRT/%RDPPRT%/g' /tmp/gWSL/gWSL.rdp"
%GO% "cp /tmp/gWSL/gWSL.rdp ./gWSL._"

REM Encrypt and embed password in RDP file
ECHO $prd = Get-Content .tmp > .tmp.ps1
ECHO ($prd ^| ConvertTo-SecureString -AsPlainText -Force) ^| ConvertFrom-SecureString ^| Out-File .tmp >> .tmp.ps1
POWERSHELL -ExecutionPolicy Bypass -Command ./.tmp.ps1
POWERSHELL -NoProfile -ExecutionPolicy Bypass -Command "$blob=(Get-Content '.tmp' -Raw).Trim(); $lines=Get-Content '.\gWSL._' | Where-Object { $_ -notmatch '^password 51:b:' }; $lines += ('password 51:b:' + $blob); [System.IO.File]::WriteAllLines('%DISTROFULL%\%DISTRO% (%XU%) Desktop.rdp', $lines, [System.Text.Encoding]::ASCII)"
DEL /Q gWSL._ .tmp*.* > NUL

REM Configure Windows Firewall for services
ECHO:
ECHO Open Windows Firewall Ports for xRDP, SSH, mDNS...

GOTO POSTRUNCONTINUE

:POSTRUNCONTINUE
NETSH AdvFirewall Firewall add rule name="%DISTRO% xRDP" dir=in action=allow protocol=TCP localport=%RDPPRT% > NUL
NETSH AdvFirewall Firewall add rule name="%DISTRO% Secure Shell" dir=in action=allow protocol=TCP localport=%SSHPRT% > NUL
NETSH AdvFirewall Firewall add rule name="%DISTRO% Avahi Multicast DNS" dir=in action=allow program="%DISTROFULL%\rootfs\usr\sbin\avahi-daemon" enable=yes > NUL

REM Initialize services
ECHO Building Scheduled Task...
POWERSHELL -C "$WAI = (whoami) ; (Get-Content .\rootfs\tmp\gWSL\gWSL.xml).replace('AAAA', $WAI) | Set-Content .\rootfs\tmp\gWSL\gWSL.xml"
POWERSHELL -C "$WAC = (pwd)    ; (Get-Content .\rootfs\tmp\gWSL\gWSL.xml).replace('QQQQ', $WAC) | Set-Content .\rootfs\tmp\gWSL\gWSL.xml"
SCHTASKS /Create /TN:%DISTRO% /XML .\rootfs\tmp\gWSL\gWSL.xml /F
WSL ~ -u root -d %DISTRO% -e initwsl 2
SET XRDPREADY=0
SET XRDPSTATUS=unknown
FOR /L %%I IN (1,1,30) DO (
  FOR /F "usebackq delims=" %%R IN (`POWERSHELL -NoProfile -Command "(Test-NetConnection localhost -Port %RDPPRT% -WarningAction SilentlyContinue).TcpTestSucceeded"`) DO SET XRDPREADY=%%R
  IF /I "!XRDPREADY!"=="True" GOTO XRDPREADY
  PING -n 2 LOCALHOST > NUL
)
:XRDPREADY
IF /I NOT "%XRDPREADY%"=="True" (
  %GO% "if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then systemctl --no-pager --full status xrdp xrdp-sesman 2>&1 ; else ps -ef | grep -E 'xrdp|sesman' | grep -v grep 2>&1 || true ; fi" > "%DISTROFULL%\logs\%TIME:~0,2%%TIME:~3,2%%TIME:~6,2% xrdp startup status.log" 2>&1
)
ECHO Building RDP Connection file, Console link, Init system...
REM Create init script to restart services on system boot
ECHO @ECHO OFF > "%DISTROFULL%\Init.cmd"
ECHO IF EXIST "%PROGRAMFILES%\WSL\WSL.EXE" ( >> "%DISTROFULL%\Init.cmd"
ECHO   @START /MIN "%DISTRO%" "%PROGRAMFILES%\WSL\WSL.EXE" ~ -u root -d %DISTRO% -e initwsl 2 >> "%DISTROFULL%\Init.cmd"
ECHO   @EXIT >> "%DISTROFULL%\Init.cmd"
ECHO ) ELSE ( >> "%DISTROFULL%\Init.cmd"
ECHO   @START /MIN "%DISTRO%" "WSL.EXE" ~ -u root -d %DISTRO% -e initwsl 2 >> "%DISTROFULL%\Init.cmd"
ECHO   @EXIT >> "%DISTROFULL%\Init.cmd"
ECHO ) >> "%DISTROFULL%\Init.cmd"

REM Create console shortcut
ECHO @WSL ~ -u %XU% -d %DISTRO% > "%DISTROFULL%\%DISTRO% (%XU%) Console.cmd"

REM Set default user UID
%GO% "id -u %XU%" > .tmpuid
SET /p XUID=<.tmpuid
DEL /Q .tmpuid > NUL 2>&1
"%DISTROFULL%\LxRunOffline.exe" su -n %DISTRO% -v %XUID%

REM Copy shortcuts to desktop
POWERSHELL -Command "Copy-Item '%DISTROFULL%\%DISTRO% (%XU%) Console.cmd' ([Environment]::GetFolderPath('Desktop'))"
POWERSHELL -Command "Copy-Item '%DISTROFULL%\%DISTRO% (%XU%) Desktop.rdp' ([Environment]::GetFolderPath('Desktop'))"

REM Display installation summary
ECHO:
ECHO:      Start: %RUNSTART%
ECHO:        End: %RUNEND%
%GO%  "echo -ne '   Packages:'\   ; dpkg-query -l | grep "^ii" | wc -l "
ECHO: 
IF /I "%XRDPREADY%"=="True" (
  ECHO:  - xRDP Server listening on port %RDPPRT% and SSHd on port %SSHPRT%.
) ELSE (
  ECHO:  - WARNING: xRDP did not start on port %RDPPRT%.
  ECHO:    The install may be incomplete. Check the distro state before using the RDP shortcut.
)
ECHO: 
ECHO:  - Links for GUI and Console sessions have been placed on your desktop.
ECHO: 
ECHO:  - (Re)launch init from the Task Scheduler or by running the following command: 
ECHO:    schtasks /run /tn %DISTRO%
ECHO: 
IF /I "%XRDPREADY%"=="True" (
  ECHO: %DISTRO% Installation Complete!  GUI will start in a few seconds...  
  PING -n 6 LOCALHOST > NUL 
  START "Remote Desktop Connection" "MSTSC.EXE" "/V" "%DISTROFULL%\%DISTRO% (%XU%) Desktop.rdp"
) ELSE (
  ECHO: %DISTRO% Installation finished with errors. GUI launch skipped.
)
CD ..
ECHO: 
:ENDSCRIPT
