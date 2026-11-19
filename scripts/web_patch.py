#!/usr/bin/env python3
"""Строит Web/index.html для приложения из index.html рабочего репозитория focus.

Использование: web_patch.py <index.html из focus> <куда записать Web/index.html>
           или: web_patch.py --check <Web/index.html>   (проверка уже готового файла)

Рабочий index.html не меняется. Скрипт:
  1) проверяет, что исходный файл — ровно закреплённая версия (SHA-256);
  2) подключает FocusSnapshotSender.js и вставляет блок «проекция снимка» (каждый якорь — ровно 1 раз);
  3) пишет копию и web-manifest.json рядом.
При любом расхождении завершается с ошибкой, ничего не записывая.
"""
import hashlib, json, os, sys

BASE_COMMIT = "00f7e5eed3416d08956c7980fcf082202f2b9b34"
BASE_SHA256 = "cb4262abefc087eb901d98573ef2c7f1c8addad8270b7f792d92e85e023c9105"

HEAD_ANCHOR = '<link rel="manifest" href="manifest.webmanifest">\n'
HEAD_ADD = '<script src="FocusSnapshotSender.js"></script>\n'
TAIL_HEAD = "  try { setTab(localStorage.getItem('kassa-tab') || 'today'); } catch (e) { setTab('today'); }\n"
TAIL = TAIL_HEAD + "})();\n</script>"

PROJECTION_JS = r"""
  /* ===== FOCUS iOS: строгая проекция «снимок для виджета» (патч к КОПИИ index.html).
     Только читает данные приложения. Отправляется ТОЛЬКО перечисленный набор полей:
     schema, generatedAt, forDate, tz, theme, privacy, day (счётчики + «Дальше»), habits, limit, streak.
     Операции, счета, дневник, настроение, заметки и суммы счетов НЕ читаются и НЕ отправляются. ===== */
  var focusSnapLast = '', focusSnapLastAt = 0, focusSnapPending = true;
  function focusSnapshot() {
    var now = new Date(), k = dateStr(now), r = todayRows();
    var hm = pad(now.getHours()) + ':' + pad(now.getMinutes());
    var hide = false, locked = false, tz = '';
    try { hide = localStorage.getItem('kassa-hide') === '1'; locked = !!localStorage.getItem('kassa-lock'); } catch (e) {}
    try { tz = Intl.DateTimeFormat().resolvedOptions().timeZone || ''; } catch (e) {}
    var ht = habToday(), hd = ht.filter(function (h) { return habDone(h, k); }).length;
    var best = 0;
    hab.items.forEach(function (h) { var s = habStreak(h); if (s > best) best = s; });
    var snap = {
      schema: 1, source: 'web',
      generatedAt: now.toISOString(),
      forDate: k, tz: tz,
      theme: {
        palette: (ui.palette === 'ocean' || ui.palette === 'graphite') ? ui.palette : 'ember',
        mode: (ui.mode === 'light' || ui.mode === 'dark') ? ui.mode : 'auto'
      },
      privacy: { hideAmounts: hide, locked: locked },
      day: { done: r.done, total: r.total },
      habits: { done: hd, total: ht.length },
      streak: { best: best },
      limit: { enabled: false }
    };
    if (!locked) {
      /* «Дальше» — та же логика, что на экране «Сегодня»: ближайшая невыполненная по времени, иначе первая */
      var openT = r.tasks.filter(function (t) { return !t.done; });
      var nx = openT.filter(function (t) { return t.time && t.time >= hm; })[0] || openT[0] || null;
      if (nx) {
        snap.day.next = { text: String(nx.text || '').slice(0, 120) };
        if (nx.time) snap.day.next.time = nx.time;
      }
      /* индикатор лимита — только если он включён в настройках и суммы не скрыты */
      if (settings.on && !hide) {
        var st = saveStats(), isSh = st.short > 0.005;
        snap.limit = {
          enabled: true,
          state: isSh ? 'short' : (st.over ? 'over' : 'ok'),
          value: isSh ? -Math.ceil(st.short - 0.005) : (st.over ? -Math.ceil(-st.left - 0.005) : Math.floor(st.left + 0.005))
        };
      }
    }
    return snap;
  }
  /* force=true — отправить даже если ничего не изменилось (первый запуск, возврат на передний план) */
  function focusSnapPush(force) {
    var cmp = '';
    try {
      var s = focusSnapshot();
      cmp = JSON.stringify(s, function (key, v) { return key === 'generatedAt' ? undefined : v; });
      var stale = Date.now() - focusSnapLastAt > 15 * 60 * 1000;
      if (!force && !focusSnapPending && !stale && cmp === focusSnapLast) return;
      var ok = window.FOCUSNativeSnapshot ? window.FOCUSNativeSnapshot.send(function () { return s; }) : false;
      if (ok) { focusSnapLast = cmp; focusSnapLastAt = Date.now(); focusSnapPending = false; }
      else { focusSnapPending = true; }   /* не удалось отправить — повторить на следующем тике */
    } catch (e) { focusSnapPending = true; }
  }
  try {
    setTimeout(function () { focusSnapPush(true); }, 1000);                              /* первый запуск */
    setInterval(function () { focusSnapPush(false); }, 3000);                            /* изменения данных, смена даты, повтор после ошибки */
    document.addEventListener('visibilitychange', function () { focusSnapPush(true); }); /* уход/возврат на передний план */
    window.addEventListener('pageshow', function () { focusSnapPush(true); });
  } catch (e) {}
"""


def sha256(b):
    return hashlib.sha256(b).hexdigest()


def fail(code, msg):
    print("PATCH FAIL: " + msg)
    sys.exit(code)


def build(src):
    data = open(src, "rb").read()
    got = sha256(data)
    if got != BASE_SHA256:
        fail(2, "SHA-256 исходного index.html %s не совпадает с закреплённым %s" % (got, BASE_SHA256))
    text = data.decode("utf-8")
    if "focusSnapshot" in text or "FocusSnapshotSender" in text:
        fail(3, "в исходном файле уже есть следы патча")
    for name, anchor in (("head", HEAD_ANCHOR), ("tail", TAIL)):
        n = text.count(anchor)
        if n != 1:
            fail(4, "якорь %s найден %d раз(а), ожидалось 1" % (name, n))
    text = text.replace(HEAD_ANCHOR, HEAD_ANCHOR + HEAD_ADD)
    text = text.replace(TAIL, TAIL_HEAD + PROJECTION_JS + "})();\n</script>")
    return text.encode("utf-8")


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--check":
        got = sha256(open(sys.argv[2], "rb").read())
        m = json.load(open(os.path.join(os.path.dirname(os.path.abspath(sys.argv[2])), "web-manifest.json")))
        if got != m["patchedSha256"]:
            fail(5, "SHA-256 Web/index.html %s != web-manifest %s" % (got, m["patchedSha256"]))
        print("CHECK OK " + got)
        return
    if len(sys.argv) != 3:
        fail(1, "использование: web_patch.py <src> <dst>")
    out = build(sys.argv[1])
    dst = os.path.abspath(sys.argv[2])
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    open(dst, "wb").write(out)
    manifest = {"baseRepo": "Chyyiii/focus", "baseCommit": BASE_COMMIT, "baseSha256": BASE_SHA256,
                "baseGitBlob": "dce1b311aee5feaac8ef2f1eefdf35d690d3006a",
                "patchedSha256": sha256(out), "snapshotSchema": 1, "bridgeMessage": "focusSnapshot"}
    json.dump(manifest, open(os.path.join(os.path.dirname(dst), "web-manifest.json"), "w"), indent=2)
    print("PATCH OK")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
