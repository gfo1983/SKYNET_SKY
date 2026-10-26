#!/bin/bash
# SKYNET — розгортання передавача ZIRKA (Raspberry Pi 5) ОДНІЄЮ командою. На новій малині, з інтернетом:
#   curl -fsSL https://raw.githubusercontent.com/gfo1983/SKYNET_SKY/main/zirka_install.sh | sudo bash
#
# Завантажує з останнього релізу SKYNET_SKY пакет zirka-deploy-<N>.tar.gz, перевіряє ЦИФРОВИЙ ПІДПИС релізу
# (той самий ключ релізів, що й для наземок) і контрольну суму, ставить і вмикає WFB:
#   драйвери RTL8812AU/EU + wfb-ng (готові під ядро Zirka, інакше збираються), wfbd, wfb_lic, сервіси,
#   агент зміни каналу, кнопка (коротко = bind, 15 с = відкат), резервний маршрут відео без кабелю.
# Ядро, config.txt і софт Zirka не змінюються.
# Секрети (bind-ключ, SSH-ключ борта) у публічному пакеті НЕМАЄ — вони приходять із ключем активації.
#
# БЕЗ ІНТЕРНЕТУ (з флешки): поруч із цим скриптом мають лежати manifest.json, manifest.sig і
# zirka-deploy-<N>.tar.gz з одного релізу (їх кладе на флешку zirka_usb.ps1). Тоді:
#   sudo bash /шлях/до/флешки/zirka_install.sh
# Підпис і контрольна сума перевіряються так само, але без мережі.
set -euo pipefail

SELF_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then    # run as a file (not piped from curl)
    SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
LOCAL=""
if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/manifest.json" ] && [ -f "$SELF_DIR/manifest.sig" ]; then
    LOCAL="$SELF_DIR"
fi

REPO="${SKY_REPO:-gfo1983/SKYNET_SKY}"
URL="https://github.com/$REPO/releases/latest/download"
DIR=/opt/wfb/deploy
# public half of the SKYNET release signing key
PUB='-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAs1+MAAgcILSdgeWpMoAaB6l8Paulxs62VAt+AOv+vbo=
-----END PUBLIC KEY-----'

say() { echo "=== $*"; }
[ "$(id -u)" = 0 ] || { echo "запустіть через sudo"; exit 1; }
grep -q "Raspberry Pi 5" /proc/device-tree/model 2>/dev/null || { echo "це не Raspberry Pi 5 — скрипт лише для ZIRKA"; exit 1; }

rm -rf "$DIR" && mkdir -p "$DIR" && cd "$DIR"
if [ -n "$LOCAL" ]; then
    say "встановлення БЕЗ інтернету з $LOCAL"
    cp "$LOCAL/manifest.json" "$LOCAL/manifest.sig" .
else
    say "завантажую останній реліз з github.com/$REPO"
    curl -fsSL -o manifest.json "$URL/manifest.json"
    curl -fsSL -o manifest.sig "$URL/manifest.sig"
fi
printf '%s\n' "$PUB" > release_pub.pem
tr -d '\r\n' < manifest.sig | base64 -d > manifest.sig.bin
openssl pkeyutl -verify -pubin -inkey release_pub.pem -rawin -in manifest.json -sigfile manifest.sig.bin >/dev/null \
    || { echo "ПІДПИС РЕЛІЗУ НЕВІРНИЙ — нічого не встановлюю"; exit 1; }
say "підпис релізу вірний"

read -r TGZ SHA < <(python3 -c "
import json; m=json.load(open('manifest.json'))
n=[k for k in m['files'] if k.startswith('zirka-deploy-')]
print(n[0], m['files'][n[0]]['sha256']) if n else print('none none')")
[ "$TGZ" != none ] || { echo "у релізі нема пакета ZIRKA"; exit 1; }
if [ -n "$LOCAL" ]; then
    [ -f "$LOCAL/$TGZ" ] || { echo "на флешці нема $TGZ (має бути з того ж релізу, що й manifest.json)"; exit 1; }
    cp "$LOCAL/$TGZ" .
else
    curl -fsSL -o "$TGZ" "$URL/$TGZ"
fi
echo "$SHA  $TGZ" | sha256sum -c --quiet || { echo "контрольна сума пакета не збігається"; exit 1; }
REL=$(python3 -c "import json;print(json.load(open('manifest.json'))['version'])")
say "пакет $TGZ (реліз №$REL) перевірено"

tar -xzf "$TGZ"
say "встановлюю (драйвери, wfb-ng, wfbd, сервіси)"
bash zirka/install_wfb_pi5.sh all
systemctl restart wfb-bindwatch wfb-led wfb-chanagent || true
systemctl restart wfb-drone || true
echo "$REL" > /etc/wfb_ng/deploy_release

ID=$(/usr/local/sbin/wfb-id 2>/dev/null || echo "?")
echo "$ID" > /root/ZIRKA_DEVICE_ID.txt
rm -rf "$DIR"
echo
say "ГОТОВО: софт ZIRKA розгорнуто (реліз №$REL)"
echo
echo "  ┌─────────────────────────────────────────────────────────────┐"
echo "  │  ІДЕНТИФІКАТОР ПРИСТРОЮ:  $ID  │"
echo "  └─────────────────────────────────────────────────────────────┘"
echo "  (збережено в /root/ZIRKA_DEVICE_ID.txt; показати ще раз: sudo wfb-id)"
echo
echo "  1. Надішліть цей ідентифікатор постачальнику — він видасть КЛЮЧ АКТИВАЦІЇ."
echo "  2. Отримавши ключ, виконайте на цій малині:  sudo zirka-activate <КЛЮЧ>"
echo "  3. Потім BIND з наземкою (коротко натиснути кнопку бінду на борту)."
