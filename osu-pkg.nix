{ pkgs ? import <nixpkgs> {} }:

let
  # Список программ, которые нужны нашему скрипту
  runtimeDeps = with pkgs; [
    bash
    wineWowPackages.staging # Системный Wine (staging версия лучше для игр)
    winetricks
    yad                 # Для GUI окон
    curl
    unzip
    icoutils            # Для извлечения иконок
    desktop-file-utils  # Для update-desktop-database
    shared-mime-info    # Для xdg-mime
    libnotify           # Для notify-send в wrapper
  ];

in pkgs.stdenv.mkDerivation {
  pname = "osu-installer";
  version = "4.0.0-nix";

  # Используем текущую папку как источник
  src = ./.;

  # Инструмент для создания оберток (wrapper)
  nativeBuildInputs = [ pkgs.makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    
    # === 1. Устанавливаем сам скрипт инсталлятора ===
    cp install-nix.sh $out/bin/osu-install
    chmod +x $out/bin/osu-install

    # "Оборачиваем" скрипт: добавляем в его PATH нужные программы (Wine, curl и т.д.)
    wrapProgram $out/bin/osu-install \
      --prefix PATH : ${pkgs.lib.makeBinPath runtimeDeps} \
      --set STAGING_AUDIO_DURATION 10000 \
      --set PULSE_LATENCY_MSEC 60

    # === 2. Создаем команду запуска 'osu' ===
    # Она проверяет, создан ли уже wrapper. Если да — играет, если нет — ставит.
    cat > $out/bin/osu <<'EOF'
#!/bin/sh

# Путь к wrapper, который создаёт инсталлятор
WRAPPER="$HOME/.config/osu-importer/osu_importer_wrapper.sh"
CONFIG="$HOME/.config/osu-importer/config"

if [ -x "$WRAPPER" ] && [ -f "$CONFIG" ]; then
  # Если wrapper есть — запускаем его
  exec "$WRAPPER" "$@"
else
  echo "osu! не найдена или не настроена."
  echo "Запускаю мастер установки..."
  exec osu-install
fi
EOF
    
    chmod +x $out/bin/osu
  '';

  meta = with pkgs.lib; {
    description = "Unofficial osu! installer and wrapper for NixOS";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}