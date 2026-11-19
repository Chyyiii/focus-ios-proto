#!/usr/bin/env bash
# E2E в симуляторе: запуск приложения с демо-данными и проверка файла снимка в App Group.
# Использование: e2e_sim.sh <UDID> <путь к FocusProto.app> <метка>
# Информативный шаг: результат зависит от того, выдаёт ли симулятор контейнер App Group сборке без подписи.
set -uo pipefail
UDID="$1"; APP="$2"; LABEL="$3"; OUT="build/e2e-$LABEL"
mkdir -p "$OUT"
{ codesign -d --entitlements - "$APP" 2>&1 || true; } | tee "$OUT/entitlements.log"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
xcrun simctl uninstall "$UDID" com.focusproto.app 2>/dev/null || true
xcrun simctl install "$UDID" "$APP" 2>&1 | tee "$OUT/install.log"
xcrun simctl launch "$UDID" com.focusproto.app -focusDiagnostics -focusAutoDemo 2>&1 | tee "$OUT/launch.log"
sleep 25
xcrun simctl io "$UDID" screenshot "$OUT/screenshot.png" 2>&1 | tee -a "$OUT/launch.log" || true
GROUPS_OUT="$(xcrun simctl get_app_container "$UDID" com.focusproto.app groups 2>&1 || true)"
echo "$GROUPS_OUT" | tee "$OUT/groups.log"
GROUP_PATH="$(echo "$GROUPS_OUT" | awk -F'\t' '$1=="group.com.focusproto.app"{print $2}')"
if [ -z "$GROUP_PATH" ]; then
  echo "E2E[$LABEL] FAIL: контейнер App Group не выдан симулятором" | tee "$OUT/result.log"
  exit 1
fi
python3 scripts/check_snapshot.py "$GROUP_PATH/widget/widget-snapshot.json" 30 2>&1 | tee "$OUT/result.log"
exit "${PIPESTATUS[0]}"
