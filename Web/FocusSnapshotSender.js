/* Snapshot sender for embedded FOCUS HTML. Only the safe, explicit projection may be sent. */
(function () {
  'use strict';
  var MAX_BYTES = 64 * 1024;
  function utf8Bytes(text) {
    if (typeof TextEncoder !== 'undefined') return new TextEncoder().encode(text).length;
    // Fallback computes UTF-8 bytes without relying on TextEncoder.
    return unescape(encodeURIComponent(text)).length;
  }
  function sendSnapshot(project) {
    var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.focusSnapshot;
    if (typeof project !== 'function' || !handler) return false;
    try {
      var snapshot = project();
      if (!snapshot || typeof snapshot !== 'object' || Array.isArray(snapshot)) return false;
      var text = JSON.stringify({ snapshot: snapshot });
      if (!text || utf8Bytes(text) > MAX_BYTES) return false;
      // postMessage is fire-and-forget. Do not cache as acknowledged; repeated calls are
      // safe because native storage validates and atomically replaces the same projection.
      handler.postMessage({ snapshot: snapshot });
      return true;
    } catch (_) { return false; }
  }
  window.FOCUSNativeSnapshot = Object.freeze({ send: sendSnapshot });
})();
