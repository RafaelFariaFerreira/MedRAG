#!/usr/bin/env bash
# uso: tools/shot.sh nome  -> captura a tela do emulador reduzida
A="${ANDROID_HOME:-$HOME/Android/Sdk}/platform-tools/adb"; S="${SHOTS_DIR:-/tmp/medrag-shots}"; mkdir -p "$S"
$A exec-out screencap -p > $S/$1.png && python3 -c "
from PIL import Image; im=Image.open('$S/$1.png'); im.thumbnail((540,1200)); im.save('$S/$1.png')"; echo $S/$1.png
