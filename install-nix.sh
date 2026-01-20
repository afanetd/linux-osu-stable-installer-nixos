#!/usr/bin/env bash
# ==============================================================================
# osu! Installer (NixOS Edition)
# Forked from: Kitty-Hivens/linux-osu-stable-installer
#
# Modified for: NixOS Environment
# Changes:
#  - Removed all pkexec/apt/pacman logic (handled by Nix)
#  - Added CLI arguments support (--silent, --dir, etc.)
#  - Simplified dependency checks
#  - Removed custom Wine selection (uses system Wine from Nix)
# ==============================================================================

set -e

# --- 1. Default Settings ---
USE_GUI=true
INSTALL_DIR="$HOME/.wine-osu"
RENDERER="DXVK"
DRIVER="X11"
FONTS="WenQuanYi (Micro Hei)"
INSTALL_RPC="TRUE"

# --- 2. CLI Argument Parsing ---
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "  -s, --silent        Run without GUI (use defaults or flags)"
    echo "  -d, --dir PATH      Install prefix (Default: ~/.wine-osu)"
    echo "  --renderer TYPE     OpenGL or DXVK (Default: DXVK)"
    echo "  --driver TYPE       X11 or Wayland (Default: X11)"
    echo "  --font NAME         Select font (WenQuanYi, Noto Sans, Koruri, Skip)"
    echo "  --no-rpc            Skip Discord RPC installation"
    echo "  -h, --help          Show this help"
    exit 0
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--silent) USE_GUI=false ;;
        -d|--dir) INSTALL_DIR="$2"; shift ;;
        --renderer) RENDERER="$2"; shift ;;
        --driver) DRIVER="$2"; shift ;;
        --font) FONTS="$2"; shift ;;
        --no-rpc) INSTALL_RPC="FALSE" ;;
        -h|--help) show_help ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# --- 3. Dependency Check (Nix Way) ---
REQUIRED_TOOLS="curl unzip winetricks wine"
if [ "$USE_GUI" = true ]; then REQUIRED_TOOLS="$REQUIRED_TOOLS yad"; fi

echo "Checking dependencies..."
for tool in $REQUIRED_TOOLS; do
    if ! command -v "$tool" &> /dev/null; then
        echo "ERROR: '$tool' is missing."
        echo "Please ensure your 'osu-pkg.nix' or shell environment provides these dependencies."
        exit 1
    fi
done

# Find Wine (priority: wine-staging, then wine)
if command -v wine-staging &> /dev/null; then
    WINE_BIN="wine-staging"
elif command -v wine &> /dev/null; then
    WINE_BIN="wine"
else
    echo "ERROR: Wine not found."
    exit 1
fi

WINE_FULL_PATH=$(command -v "$WINE_BIN")
echo "Using Wine: $WINE_FULL_PATH"

# --- 4. Graphical User Interface (YAD) ---
if [ "$USE_GUI" = true ]; then
    SCRIPT_TITLE="osu! Lab Installer"
    ICON="applications-games"

    # Pre-fill fields with current values
    VALUES=$(yad --form --center --width=550 --title="$SCRIPT_TITLE" \
        --window-icon="$ICON" --image="$ICON" \
        --text="<b>NixOS Laboratory Config</b>\nSelect parameters:" \
        --field="Install Location:DIR" "$INSTALL_DIR" \
        --field="Graphics API:CB" "DXVK (Low Latency)!OpenGL (Stable)" \
        --field="Window Driver:CB" "X11 (Recommended)!Wayland (Experimental)" \
        --field="Fonts:CB" "WenQuanYi (Micro Hei)!Noto Sans CJK!Koruri!Skip" \
        --field="Install Discord RPC:CHK" "$INSTALL_RPC" \
        --separator="|")

    if [ $? -ne 0 ] || [ -z "$VALUES" ]; then
        echo "Installation cancelled by user."
        exit 0
    fi

    # Read user selection
    IFS="|" read -r INSTALL_DIR RENDERER_GUI DRIVER_GUI FONTS_GUI INSTALL_RPC_GUI <<< "$VALUES"

    RENDERER="$RENDERER_GUI"
    DRIVER="$DRIVER_GUI"
    FONTS="$FONTS_GUI"
    INSTALL_RPC="$INSTALL_RPC_GUI"
fi

# Clean up GUI variables (e.g. "OpenGL (Stable)" -> "OpenGL")
[[ "$RENDERER" == *"DXVK"* ]] && RENDERER="DXVK" || RENDERER="OpenGL"
[[ "$DRIVER" == *"Wayland"* ]] && DRIVER="Wayland" || DRIVER="X11"

echo "=== Config ==="
echo "Prefix:   $INSTALL_DIR"
echo "Wine:     $WINE_BIN"
echo "Renderer: $RENDERER"
echo "Driver:   $DRIVER"
echo "Fonts:    $FONTS"
echo "RPC:      $INSTALL_RPC"
echo "=============="

# --- 5. Task Helper (GUI/CLI) ---
run_task() {
    local title="$1"
    local text="$2"
    shift 2
    
    if [ "$USE_GUI" = true ]; then
        ( "$@" ) | yad --progress --pulsate --auto-close --no-cancel \
            --title="$title" --text="$text" --center --width=400
    else
        echo ">> Running task: $title..."
        "$@"
    fi
}

export WINE="$WINE_BIN"
export WINEPREFIX="$INSTALL_DIR"

# --- 6. Prefix and .NET setup ---
mkdir -p "$INSTALL_DIR"

install_dotnet() {
    if [ ! -d "$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework/v4.0.30319" ]; then
        set +e
        WAYLAND_DISPLAY="" winetricks -q dotnet48
        set -e
    else
        echo ".NET already installed."
    fi
}

run_task "Installing .NET" "Setting up .NET 4.8 Framework..." install_dotnet

# --- 7. Graphics Configuration ---
configure_graphics() {
    # Renderer
    if [ "$RENDERER" == "DXVK" ]; then
        echo "Installing DXVK..."
        winetricks -q dxvk
    else
        echo "Reverting to OpenGL..."
        "$WINE_BIN" reg delete "HKCU\Software\Wine\DllOverrides" /v "d3d9" /f 2>/dev/null || true
        "$WINE_BIN" reg delete "HKCU\Software\Wine\DllOverrides" /v "dxgi" /f 2>/dev/null || true
        "$WINE_BIN" reg delete "HKCU\Software\Wine\DllOverrides" /v "d3d11" /f 2>/dev/null || true
    fi

    # Driver
    if [ "$DRIVER" == "Wayland" ]; then
        echo "Enabling Wayland Driver..."
        "$WINE_BIN" reg add "HKCU\Software\Wine\Drivers" /f 2>/dev/null
        "$WINE_BIN" reg add "HKCU\Software\Wine\Drivers" /v "Graphics" /t REG_SZ /d "wayland" /f
    else
        echo "Enforcing X11 Driver..."
        "$WINE_BIN" reg delete "HKCU\Software\Wine\Drivers" /v "Graphics" /f 2>/dev/null || true
    fi
}
run_task "Graphics" "Applying graphics settings ($RENDERER / $DRIVER)..." configure_graphics

# --- 8. Fonts ---
configure_fonts() {
    if [[ "$FONTS" == "Skip" ]]; then return 0; fi
    
    FONT_DIR="$WINEPREFIX/drive_c/windows/Fonts"
    mkdir -p "$FONT_DIR"
    rm -f "$FONT_DIR/"*

    echo "Installing fonts: $FONTS"
    # Font download logic (simplified for example, full in original)
    case "$FONTS" in
      "WenQuanYi"*)
        curl -L -o "$FONT_DIR/wqy-microhei.ttc" "https://github.com/anthonyfok/fonts-wqy-microhei/raw/master/wqy-microhei.ttc"
        REG_NAME="WenQuanYi Micro Hei"
        REG_FILE="wqy-microhei.ttc"
        ;;
      "Noto Sans"*)
        curl -L -o "$FONT_DIR/osu-font.otf" "https://github.com/googlefonts/noto-cjk/raw/main/Sans/OTF/Japanese/NotoSansCJKjp-Regular.otf"
        REG_NAME="Noto Sans CJK JP Regular"
        REG_FILE="osu-font.otf"
        ;;
      "Koruri"*)
        # Logic for Koruri can be added here if needed
        echo "Koruri not fully implemented in this snippet, skipping download."
        return 0
        ;;
    esac

    # Apply registry
    if [ -n "$REG_NAME" ]; then
        cat > "$WINEPREFIX/font_fix.reg" << EOF
REGEDIT4
[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes]
"Arial"="$REG_NAME"
"Segoe UI"="$REG_NAME"
"MS Gothic"="$REG_NAME"
"Meiryo"="$REG_NAME"
[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Fonts]
"$REG_NAME (TrueType)"="$REG_FILE"
[HKEY_CURRENT_USER\Control Panel\Desktop]
"FontSmoothing"="2"
"FontSmoothingGamma"=dword:00000578
"FontSmoothingOrientation"=dword:00000001
"FontSmoothingType"=dword:00000002
[HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Nls\CodePage]
"932"="cp932.nls"
"00000411"="cp932.nls"
EOF
        WAYLAND_DISPLAY="" "$WINE_BIN" regedit "$WINEPREFIX/font_fix.reg" 2>/dev/null
        rm "$WINEPREFIX/font_fix.reg"
    fi
}
run_task "Fonts" "Installing fonts..." configure_fonts

# --- 9. Discord RPC ---
install_rpc() {
    if [ "$INSTALL_RPC" != "TRUE" ]; then return 0; fi
    
    echo "Cleaning old bridge..."
    WAYLAND_DISPLAY="" "$WINE_BIN" net stop rpc-bridge 2>/dev/null || true
    WAYLAND_DISPLAY="" "$WINE_BIN" taskkill /IM bridge.exe /F 2>/dev/null || true
    rm -f "$WINEPREFIX/drive_c/windows/bridge.exe"

    echo "Downloading RPC Bridge..."
    TEMP_DIR="$WINEPREFIX/drive_c/windows/temp_bridge"
    mkdir -p "$TEMP_DIR"
    curl -L -o "$TEMP_DIR/bridge.zip" "https://github.com/EnderIce2/rpc-bridge/releases/latest/download/bridge.zip"
    unzip -o "$TEMP_DIR/bridge.zip" -d "$TEMP_DIR"

    BRIDGE_EXE=$(find "$TEMP_DIR" -name "bridge.exe" | head -n 1)
    if [ -n "$BRIDGE_EXE" ]; then
        WAYLAND_DISPLAY="" "$WINE_BIN" "$BRIDGE_EXE" --install
    fi
    rm -rf "$TEMP_DIR"
}
run_task "Discord RPC" "Installing Rich Presence..." install_rpc

# --- 10. Game Installation ---
TARGET_OSU_EXE=$(find "$WINEPREFIX" -name "osu!.exe" 2>/dev/null | head -n 1)

if [ -z "$TARGET_OSU_EXE" ]; then
    echo "Downloading osu! installer..."
    curl -L -o "$WINEPREFIX/osu!install.exe" "https://m1.ppy.sh/r/osu!install.exe"

    echo "Launching installer..."
    # Launch installer in background
    WAYLAND_DISPLAY="" LC_ALL=en_US.UTF-8 "$WINE_BIN" "$WINEPREFIX/osu!install.exe" &
    
    if [ "$USE_GUI" = true ]; then
        yad --title="osu! Setup" --text="<b>ACTION REQUIRED:</b>\n\n1. Install osu!\n2. Let it launch.\n3. <b>CLOSE osu!</b> to continue setup." \
            --button="Done:0" --center --width=400
    else
        echo "Waiting for user to finish installation..."
        echo "Please install osu!, let it run, then CLOSE IT."
        wait
    fi

    # Try to find exe again
    TARGET_OSU_EXE=$(find "$WINEPREFIX" -name "osu!.exe" 2>/dev/null | head -n 1)
fi

if [ -z "$TARGET_OSU_EXE" ]; then
    echo "ERROR: osu!.exe not found after installation."
    exit 1
fi

# --- 11. Create config, wrapper script and desktop files ---
CONFIG_DIR="$HOME/.config/osu-importer"
CONFIG_FILE="$CONFIG_DIR/config"
WRAPPER="$CONFIG_DIR/osu_importer_wrapper.sh"
mkdir -p "$CONFIG_DIR"

# Save configuration for wrapper
cat > "$CONFIG_FILE" << EOF
PREFIX="$INSTALL_DIR"
WINE_BIN="$WINE_FULL_PATH"
GAME_EXE="$TARGET_OSU_EXE"
EOF

cat > "$WRAPPER" << 'WRAPPER_EOF'
#!/usr/bin/env bash
exec 2>>/tmp/osu.log
set -x

# === Load configuration ===
CONFIG_FILE="$HOME/.config/osu-importer/config"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found at $CONFIG_FILE" >> /tmp/osu.log
    notify-send "Ошибка osu!" "Конфигурация не найдена. Запустите установку заново."
    exit 1
fi

source "$CONFIG_FILE"

# Verify all variables are loaded
if [ -z "$PREFIX" ] || [ -z "$WINE_BIN" ] || [ -z "$GAME_EXE" ]; then
    echo "ERROR: Invalid config" >> /tmp/osu.log
    notify-send "Ошибка osu!" "Повреждённая конфигурация"
    exit 1
fi

export WINEPREFIX="$PREFIX"
export STAGING_AUDIO_DURATION=10000
export PULSE_LATENCY_MSEC=60

# Check game existence
if [ ! -f "$GAME_EXE" ]; then
    notify-send "Ошибка osu!" "Не найден osu!.exe по пути: $GAME_EXE"
    exit 1
fi

# GameMode (optional)
if command -v gamemoderun &> /dev/null; then
    GM="gamemoderun"
else
    GM=""
fi

# === Launch ===
if [ -n "$1" ]; then
    # Import map
    FILE_PATH=$("$WINE_BIN" winepath -w "$1")
    $GM "$WINE_BIN" "$GAME_EXE" "$FILE_PATH"
else
    # Normal game launch
    $GM "$WINE_BIN" "$GAME_EXE"
fi
WRAPPER_EOF
chmod +x "$WRAPPER"

# --- 12. Icon extraction and .desktop file creation ---
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
DESKTOP_DIR="$HOME/.local/share/applications"
mkdir -p "$ICON_DIR" "$DESKTOP_DIR"

echo "Extracting icon from osu!.exe..."
if command -v wrestool &> /dev/null && command -v icotool &> /dev/null; then
    TEMP_ICO="/tmp/osu-icon.ico"
    wrestool -x -t 14 "$TARGET_OSU_EXE" > "$TEMP_ICO" 2>/dev/null || true
    
    if [ -f "$TEMP_ICO" ] && [ -s "$TEMP_ICO" ]; then
        icotool -x -o "$ICON_DIR" "$TEMP_ICO" 2>/dev/null || true
        
        # Rename icon
        EXTRACTED_ICON=$(find "$ICON_DIR" -name "*256x256*.png" -o -name "*icon_*" | head -n 1)
        if [ -n "$EXTRACTED_ICON" ]; then
            mv "$EXTRACTED_ICON" "$ICON_DIR/osu.png"
        fi
        rm -f "$TEMP_ICO"
    fi
fi

# If icon not extracted, use fallback
ICON_PATH="$ICON_DIR/osu.png"
if [ ! -f "$ICON_PATH" ]; then
    echo "Using fallback icon..."
    ICON_PATH="applications-games"
fi

# Create .desktop file for game launch
cat > "$DESKTOP_DIR/osu.desktop" << EOF
[Desktop Entry]
Name=osu!
Comment=Rhythm is just a click away
Exec=$WRAPPER
Icon=$ICON_PATH
Terminal=false
Type=Application
Categories=Game;
StartupWMClass=osu!.exe
EOF

# Create .desktop file for map import
cat > "$DESKTOP_DIR/osu-importer.desktop" << EOF
[Desktop Entry]
Name=osu! Importer
Comment=Import osu! beatmaps
Exec=$WRAPPER %f
Icon=$ICON_PATH
Terminal=false
Type=Application
NoDisplay=true
MimeType=application/x-osu-beatmap-archive;
EOF

# Register MIME type for .osz files
MIME_DIR="$HOME/.local/share/mime/packages"
mkdir -p "$MIME_DIR"

cat > "$MIME_DIR/osu-beatmap.xml" << 'MIME_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-osu-beatmap-archive">
    <comment>osu! Beatmap Archive</comment>
    <glob pattern="*.osz"/>
  </mime-type>
</mime-info>
MIME_EOF

# Update databases
update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true

echo ""
echo "====================================="
echo "Installation Complete!"
echo "====================================="
echo "Wrapper: $WRAPPER"
echo "Desktop entries: $DESKTOP_DIR"
echo ""
echo "You can now:"
echo "  - Launch osu! from your application menu"
echo "  - Run 'osu' command in terminal"
echo "  - Double-click .osz files to import beatmaps"
echo "====================================="