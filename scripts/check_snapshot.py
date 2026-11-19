#!/usr/bin/env python3
"""Ждёт файл снимка и проверяет его по правилам схемы 1 на демо-данных приложения.

Использование: check_snapshot.py <путь к widget-snapshot.json> <таймаут, сек>
Код выхода 0 — файл появился и корректен; 1 — нет или некорректен.
"""
import json
import os
import re
import sys
import time

ISO_Z = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$")
DAY = re.compile(r"^\d{4}-\d{2}-\d{2}$")
TIME = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")


def is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def check(snap, size):
    errs = []
    if size > 64 * 1024:
        errs.append("размер %d > 65536" % size)
    if not isinstance(snap, dict):
        return ["корень не объект"]
    if snap.get("schema") != 1:
        errs.append("schema != 1")
    if not (isinstance(snap.get("generatedAt"), str) and ISO_Z.match(snap["generatedAt"])):
        errs.append("generatedAt")
    if not (isinstance(snap.get("forDate"), str) and DAY.match(snap["forDate"])):
        errs.append("forDate")
    day = snap.get("day")
    if not isinstance(day, dict) or not is_int(day.get("done")) or not is_int(day.get("total")):
        errs.append("day")
    else:
        if not (0 <= day["done"] <= day["total"]):
            errs.append("day.done/total вне границ")
        if day["total"] < 3:
            errs.append("демо-данные ещё не применены: day.total=%d (<3)" % day["total"])
        nxt = day.get("next")
        if nxt is not None:
            if not isinstance(nxt, dict) or not isinstance(nxt.get("text"), str):
                errs.append("day.next")
            elif "time" in nxt and not TIME.match(str(nxt["time"])):
                errs.append("day.next.time")
    hab = snap.get("habits")
    if not isinstance(hab, dict) or not is_int(hab.get("done")) or not is_int(hab.get("total")):
        errs.append("habits")
    elif hab["total"] < 3 or not (0 <= hab["done"] <= hab["total"]):
        errs.append("habits вне ожидаемых границ: %r" % hab)
    theme = snap.get("theme")
    if not isinstance(theme, dict) or theme.get("palette") not in ("ember", "ocean", "graphite") \
            or theme.get("mode") not in ("auto", "light", "dark"):
        errs.append("theme")
    privacy = snap.get("privacy")
    if not isinstance(privacy, dict) or not isinstance(privacy.get("hideAmounts"), bool) \
            or not isinstance(privacy.get("locked"), bool):
        errs.append("privacy")
    limit = snap.get("limit")
    if not isinstance(limit, dict) or not isinstance(limit.get("enabled"), bool):
        errs.append("limit")
    elif limit["enabled"] and limit.get("state") not in ("ok", "over", "short"):
        errs.append("limit.state")
    streak = snap.get("streak")
    if streak is not None and not (isinstance(streak, dict) and is_int(streak.get("best")) and streak["best"] >= 0):
        errs.append("streak")
    return errs


def main():
    path, timeout = sys.argv[1], int(sys.argv[2])
    deadline = time.time() + timeout
    last = "файл не появился: " + path
    raw = b""
    while time.time() < deadline:
        if os.path.exists(path):
            try:
                raw = open(path, "rb").read()
                errs = check(json.loads(raw), len(raw))
                if not errs:
                    print("SNAPSHOT OK (%d bytes)" % len(raw))
                    print(json.dumps(json.loads(raw), ensure_ascii=False, indent=2))
                    sys.exit(0)
                last = "; ".join(errs)
            except SystemExit:
                raise
            except Exception as exc:  # noqa: BLE001
                last = "ошибка чтения: %r" % exc
        time.sleep(2)
    print("SNAPSHOT FAIL: " + last)
    if raw:
        print(raw.decode("utf-8", "replace")[:2000])
    sys.exit(1)


if __name__ == "__main__":
    main()
