#!/usr/bin/env bash
# Проверка результата сборки: приложение собрано, расширение виджета встроено.
# Использование: scripts/verify_build.sh <DerivedData>
set -euo pipefail

DD="${1:?укажите путь к DerivedData}"
APP="$DD/Build/Products/Debug-iphonesimulator/FocusProto.app"
APPEX="$APP/PlugIns/FocusWidget.appex"
fail=0

check() { # описание, условие
  if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi
}

check "приложение собрано ($APP)"           "[ -d '$APP' ]"
check "исполняемый файл приложения"         "[ -f '$APP/FocusProto' ]"
check "виджет встроен (PlugIns/FocusWidget.appex)" "[ -d '$APPEX' ]"
check "исполняемый файл виджета"            "[ -f '$APPEX/FocusWidget' ]"
check "виджет объявлен как widgetkit-extension" \
  "[ \"\$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' '$APPEX/Info.plist' 2>/dev/null)\" = 'com.apple.widgetkit-extension' ]"

check "Web/index.html в пакете приложения" "[ -f '$APP/Web/index.html' ]"
check "FocusSnapshotSender.js в пакете"     "[ -f '$APP/Web/FocusSnapshotSender.js' ]"
check "пакетный index.html совпадает с web-manifest (SHA-256)" \
  "[ \"\$(shasum -a 256 '$APP/Web/index.html' | cut -d' ' -f1)\" = \"\$(python3 -c \"import json;print(json.load(open('Web/web-manifest.json'))['patchedSha256'])\")\" ]"
check "index.html подключает отправитель"   "grep -q 'FocusSnapshotSender.js' '$APP/Web/index.html'"
check "схема focus-app объявлена в Info.plist" \
  "/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' '$APP/Info.plist' 2>/dev/null | grep -qx 'focus-app'"
check "виджет не содержит WebKit-кода моста" "! strings '$APPEX/FocusWidget' | grep -q 'FocusBridgeHandler'"

if [ "$fail" -ne 0 ]; then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: PASS"
