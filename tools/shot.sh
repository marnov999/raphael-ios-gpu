#!/bin/bash
# shot.sh NAME: phone screenshot -> out/games/play/NAME.png and a 270x585 copy NAME-s.png (for a quick look)
cd "$(dirname "$0")/.."
mkdir -p out/games/play
python3 -I tools/screencap.py "out/games/play/$1.png" >/dev/null 2>&1 || { echo "shot $1 failed"; exit 1; }
python3 -I -c "from PIL import Image; Image.open('out/games/play/$1.png').convert('RGB').resize((270,585)).save('out/games/play/$1-s.png')"
echo "out/games/play/$1-s.png"
