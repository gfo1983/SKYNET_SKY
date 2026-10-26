#!/bin/bash
# SKYNET — розгортання передавача ZIRKA (Raspberry Pi 5) ОДНІЄЮ командою. На новій малині, з інтернетом:
#   curl -fsSL https://raw.githubusercontent.com/gfo1983/SKYNET_SKY/main/zirka_install.sh | sudo bash
#
# Завантажує з останнього релізу SKYNET_SKY пакет zirka-deploy-<N>.tar.gz, перевіряє ЦИФРОВИЙ ПІДПИС релізу
# (той самий ключ релізів, що й для наземок) і контрольну суму, ставить і вмикає WFB:
#   драйвери RTL8812AU/EU + wfb-ng (готові під ядро Zirka, інакше збираються), wfbd, wfb_lic, сервіси,
#   агент зміни каналу, кнопка (коротко = bind, 15 с = відкат), резервний маршрут відео без кабелю.
# Ядро, config.txt і софт Zirka не змінюються.
# Секрети (bind-ключ, SSH-ключ борта) у публічному пакеті НЕМАЄ — їх ставлять окремо з ПК (zirka_keys.sh).
set -euo pipefail

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
say "завантажую останній реліз з github.com/$REPO"
curl -fsSL -o manifest.json "$URL/manifest.json"
curl -fsSL -o manifest.sig "$URL/manifest.sig"
printf '%s\n' "$PUB" > release_pub.pem
base64 -d manifest.sig > manifest.sig.bin
openssl pkeyutl -verify -pubin -inkey release_pub.pem -rawin -in manifest.json -sigfile manifest.sig.bin >/dev/null \
    || { echo "ПІДПИС РЕЛІЗУ НЕВІРНИЙ — нічого не встановлюю"; exit 1; }
say "підпис релізу вірний"

read -r TGZ SHA < <(python3 -c "
import json; m=json.load(open('manifest.json'))
n=[k for k in m['files'] if k.startswith('zirka-deploy-')]
print(n[0], m['files'][n[0]]['sha256']) if n else print('none none')")
[ "$TGZ" != none ] || { echo "у релізі нема пакета ZIRKA"; exit 1; }
curl -fsSL -o "$TGZ" "$URL/$TGZ"
echo "$SHA  $TGZ" | sha256sum -c --quiet || { echo "контрольна сума пакета не збігається"; exit 1; }
REL=$(python3 -c "import json;print(json.load(open('manifest.json'))['version'])")
say "пакет $TGZ (реліз №$REL) перевірено"

tar -xzf "$TGZ"
say "встановлюю (драйвери, wfb-ng, wfbd, сервіси)"
bash zirka/install_wfb_pi5.sh all
systemctl restart wfb-bindwatch wfb-led wfb-chanagent || true
systemctl restart wfb-drone || true
echo "$REL" > /etc/wfb_ng/deploy_release

echo
say "ГОТОВО: ZIRKA розгорнуто з релізу №$REL"
if [ -f /etc/wfb_ng/bind_drone.key ]; then
    echo "bind-ключ: є"
else
    echo "bind-ключ: НЕМАЄ — встановіть секрети з ПК:  ./zirka_keys.sh pi@<ip цієї малини>"
fi
echo "Ліцензія: ID цієї плати (надішліть для видачі ліцензії):"
/usr/local/sbin/wfb-id || true
echo "Далі: ліцензія (sudo wfb-license-install <КЛЮЧ>), потім BIND з наземкою (кнопка коротко)."
rm -rf "$DIR"
