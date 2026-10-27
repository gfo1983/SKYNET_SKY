#!/bin/bash
# SKYNET — оновлення / відкат наземки, запуск ПРЯМО НА НАЗЕМЦІ (для старих версій без кнопки у вебі).
# Наземці потрібен інтернет. Запуск від root:
#   curl -fsSL https://raw.githubusercontent.com/gfo1983/SKYNET_SKY/main/gs_update.sh | bash -s update
#   curl -fsSL https://raw.githubusercontent.com/gfo1983/SKYNET_SKY/main/gs_update.sh | bash -s rollback
#   curl -fsSL https://raw.githubusercontent.com/gfo1983/SKYNET_SKY/main/gs_update.sh | bash -s status
# Ставить останній реліз SKYNET_SKY тим самим інсталятором, що й кнопка у вебі: лише підписаний реліз,
# бекап поточної версії перед установкою, автоматичний відкат, якщо сервіси не стартують.
# Конфіг, ключі й ліцензія не змінюються.
set -euo pipefail

ACTION="${1:-status}"
REPO="${SKY_REPO:-gfo1983/SKYNET_SKY}"
URL="https://github.com/$REPO/releases/latest/download"
export GS_DIR=/opt/gs PYTHONPATH=/opt/gs/bin

[ "$(id -u)" = 0 ] || { echo "запустіть від root"; exit 1; }

case "$ACTION" in
  status)
    if [ -x /opt/gs/bin/gs_update ]; then /opt/gs/bin/gs_update status
    else echo "оновлювача ще нема (стара версія) — запустіть з параметром update"; fi
    ;;
  rollback)
    [ -x /opt/gs/bin/gs_update ] || { echo "наземка ще не оновлювалась — відкочувати нема на що"; exit 1; }
    /opt/gs/bin/gs_update rollback; /opt/gs/bin/gs_update status
    ;;
  update)
    T=/tmp/gsupd
    rm -rf "$T" && mkdir -p "$T/run"
    echo "завантажую останній реліз з github.com/$REPO ..."
    curl -fsSL -o "$T/manifest.json" "$URL/manifest.json"
    curl -fsSL -o "$T/manifest.sig"  "$URL/manifest.sig"
    TGZ=$(python3 -c "import json;print([n for n in json.load(open('$T/manifest.json'))['files'] if n.startswith('gs-') and n.endswith('.tar.gz')][0])")
    curl -fsSL -o "$T/$TGZ" "$URL/$TGZ"
    # оновлювач береться з НОВОГО релізу (у старої наземки його нема); підпис він перевіряє сам
    tar -xzf "$T/$TGZ" -C "$T/run" bin/gs_update
    set +e
    systemd-run --wait --pipe --collect --unit="gs-update-$$" \
        --setenv=GS_DIR=/opt/gs --setenv=PYTHONPATH=/opt/gs/bin \
        "$T/run/bin/gs_update" install-local "$T"
    rc=$?
    rm -rf "$T"
    /opt/gs/bin/gs_update status
    exit $rc
    ;;
  *) echo "використання: ... | bash -s update|rollback|status"; exit 1 ;;
esac
