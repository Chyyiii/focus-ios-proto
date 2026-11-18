#!/usr/bin/env bash
set -euo pipefail

DD="${1:?укажите путь к DerivedData}"
APP="$DD/Build/Products/Debug-iphonesimulator/FocusProto.app"
APPEX="$APP/PlugIns/FocusWidget.appex"
fail=0

check() {
  if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi
}

check "приложение собрано ($APP)"           "[ -d '$APP' ]"
check "исполняемый файл приложения"         "[ -f '$APP/FocusProto' ]"
check "виджет встроен (PlugIns/FocusWidget.appex)" "[ -d '$APPEX' ]"
check "исполняемый файл виджета"            "[ -f '$APPEX/FocusWidget' ]"
check "виджет объявлен как widgetkit-extension" \
  "[ \"\$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' '$APPEX/Info.plist' 2>/dev/null)\" = 'com.apple.widgetkit-extension' ]"

if [ "$fail" -ne 0 ]; then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: PASS"
