# SKYNET — підготувати ФЛЕШКУ для встановлення ZIRKA без інтернету (Windows, PowerShell).
# Запуск (ПК з інтернетом, флешка вставлена):
#   powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/gfo1983/SKYNET_SKY/main/zirka_usb.ps1 | iex"
# Скрипт спитає букву флешки й покладе в папку <флешка>:\zirka\ останній реліз:
#   zirka_install.sh, manifest.json, manifest.sig, zirka-deploy-<N>.tar.gz
# Далі на малині:  sudo bash /<точка монтування>/zirka/zirka_install.sh
$ErrorActionPreference = 'Stop'
$repo = 'gfo1983/SKYNET_SKY'
$rel  = "https://github.com/$repo/releases/latest/download"
$raw  = "https://raw.githubusercontent.com/$repo/main"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$drive = (Read-Host 'Буква флешки (наприклад E)').Trim().TrimEnd(':','\')
$dst = "${drive}:\zirka"
if (-not (Test-Path "${drive}:\")) { throw "Диска ${drive}: нема" }
New-Item -ItemType Directory -Force $dst | Out-Null

Write-Host "Завантажую останній реліз SKYNET у $dst ..."
Invoke-WebRequest -UseBasicParsing "$rel/manifest.json" -OutFile "$dst\manifest.json"
Invoke-WebRequest -UseBasicParsing "$rel/manifest.sig"  -OutFile "$dst\manifest.sig"
$m = Get-Content "$dst\manifest.json" -Raw | ConvertFrom-Json
$tgz = @($m.files.PSObject.Properties.Name | Where-Object { $_ -like 'zirka-deploy-*' })[0]
if (-not $tgz) { throw 'У релізі нема пакета ZIRKA' }
Invoke-WebRequest -UseBasicParsing "$rel/$tgz" -OutFile "$dst\$tgz"
Invoke-WebRequest -UseBasicParsing "$raw/zirka_install.sh" -OutFile "$dst\zirka_install.sh"
Invoke-WebRequest -UseBasicParsing "$raw/ZIRKA_ADMIN.md" -OutFile "$dst\ZIRKA_ADMIN.md"

$sha = (Get-FileHash "$dst\$tgz" -Algorithm SHA256).Hash.ToLower()
if ($sha -ne $m.files.$tgz.sha256) { throw "Контрольна сума $tgz не збігається — спробуйте ще раз" }
# старі пакети з попередніх релізів прибираємо, щоб не сплутати
Get-ChildItem $dst -Filter 'zirka-deploy-*.tar.gz' | Where-Object { $_.Name -ne $tgz } | Remove-Item

Write-Host ""
Write-Host "ГОТОВО: реліз №$($m.version) на флешці ($dst)." -ForegroundColor Green
Write-Host "На малині (без інтернету):  sudo bash /<точка монтування флешки>/zirka/zirka_install.sh"
