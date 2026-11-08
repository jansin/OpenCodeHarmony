(function () {
  if (window.__OC_SESSION_SYNC__) return window.__OC_SESSION_SYNC__;
  var DIR = 'D:\\Huawei\\OpenHarmony\\work\\OpenCodeHarmony';
  var SOURCE = 'browser';
  var POLL_MS = 1000;
  var state = { appliedFocusAt: 0, lastLocalSid: '', navigating: false, timer: 0, badge: null };

  function headers(json) {
    var h = { Accept: 'application/json', 'x-opencode-directory': DIR };
    if (json) h['Content-Type'] = 'application/json';
    return h;
  }
  function api(path, opts) {
    opts = opts || {};
    return fetch(path, {
      method: opts.method || 'GET',
      headers: headers(!!opts.body),
      body: opts.body,
      credentials: 'include',
      cache: 'no-store'
    }).then(function (res) {
      return res.text().then(function (t) {
        if (!res.ok) throw new Error(res.status + ' ' + t.slice(0, 120));
        try { return JSON.parse(t); } catch (e) { return t; }
      });
    });
  }
  function extractSid(href) {
    var m = String(href || location.href).match(/\/session\/(ses_[A-Za-z0-9]+)/);
    return m ? m[1] : '';
  }
  function sessionHref(sid) {
    var m = location.pathname.match(/^(.*?\/server\/[^/]+)/);
    if (m) return m[1] + '/session/' + sid;
    var key = btoa(location.origin).replace(/=+$/, '');
    return '/server/' + key + '/session/' + sid;
  }
  function ensureBadge() {
    if (state.badge && document.body.contains(state.badge)) return;
    var el = document.createElement('div');
    el.textContent = 'SYNC ON';
    el.style.cssText = 'position:fixed;right:12px;bottom:12px;z-index:2147483647;background:#1a7f37;color:#fff;font:12px sans-serif;padding:6px 10px;border-radius:999px;opacity:.92;pointer-events:none';
    document.body.appendChild(el);
    state.badge = el;
  }
  function setBadge(text, ok) {
    ensureBadge();
    state.badge.textContent = text;
    state.badge.style.background = ok === false ? '#cf222e' : '#1a7f37';
  }
  function publishFocus(sid) {
    if (!sid) return Promise.resolve();
    var at = Date.now();
    state.appliedFocusAt = at;
    state.lastLocalSid = sid;
    return api('/session/' + sid, {
      method: 'PATCH',
      body: JSON.stringify({ metadata: { ocFocus: at, ocFocusSource: SOURCE } })
    }).then(function () {
      return api('/tui/select-session', {
        method: 'POST',
        body: JSON.stringify({ sessionID: sid })
      }).catch(function () {});
    }).then(function () {
      setBadge('pub ' + sid.slice(-8), true);
    });
  }
  function navigateTo(sid) {
    if (!sid || state.navigating) return;
    if (extractSid(location.href) === sid) return;
    state.navigating = true;
    state.lastLocalSid = sid;
    setBadge('follow ' + sid.slice(-8), true);
    // Prefer SPA click so inject survives; fallback to hard navigate
    var sel = 'a[href*="/session/' + sid + '"]';
    var link = document.querySelector(sel);
    if (link) {
      link.click();
      setTimeout(function () { state.navigating = false; }, 800);
      return;
    }
    location.href = sessionHref(sid);
    setTimeout(function () { state.navigating = false; }, 1500);
  }
  function tick() {
    ensureBadge();
    var sidNow = extractSid(location.href);
    var p = Promise.resolve();
    if (sidNow && sidNow !== state.lastLocalSid && !state.navigating) {
      p = publishFocus(sidNow);
    }
    return p.then(function () {
      return api('/session?limit=50');
    }).then(function (sessions) {
      var best = null;
      for (var i = 0; i < (sessions || []).length; i++) {
        var s = sessions[i];
        var focus = (s.metadata && s.metadata.ocFocus) || 0;
        if (!best || focus > ((best.metadata && best.metadata.ocFocus) || 0)) best = s;
      }
      var focusAt = (best && best.metadata && best.metadata.ocFocus) || 0;
      var focusSid = best && best.id;
      if (focusSid && focusAt > state.appliedFocusAt) {
        state.appliedFocusAt = focusAt;
        if (focusSid !== extractSid(location.href)) navigateTo(focusSid);
        else setBadge('sync ' + focusSid.slice(-8), true);
      }
    }).catch(function (e) {
      setBadge('err ' + (e && e.message ? e.message : e), false);
    });
  }

  var _push = history.pushState;
  var _replace = history.replaceState;
  history.pushState = function () {
    var r = _push.apply(this, arguments);
    setTimeout(function () {
      var sid = extractSid(location.href);
      if (sid && sid !== state.lastLocalSid) publishFocus(sid);
    }, 0);
    return r;
  };
  history.replaceState = function () {
    var r = _replace.apply(this, arguments);
    setTimeout(function () {
      var sid = extractSid(location.href);
      if (sid && sid !== state.lastLocalSid) publishFocus(sid);
    }, 0);
    return r;
  };
  window.addEventListener('popstate', function () {
    var sid = extractSid(location.href);
    if (sid && sid !== state.lastLocalSid) publishFocus(sid);
  });

  state.lastLocalSid = extractSid(location.href);
  if (state.lastLocalSid) publishFocus(state.lastLocalSid).catch(function () {});
  tick();
  state.timer = setInterval(tick, POLL_MS);
  window.__OC_SESSION_SYNC__ = {
    stop: function () {
      if (state.timer) clearInterval(state.timer);
      state.timer = 0;
      if (state.badge) state.badge.remove();
      delete window.__OC_SESSION_SYNC__;
    },
    tick: tick,
    publishFocus: publishFocus
  };
  console.log('[oc-sync] started');
  return window.__OC_SESSION_SYNC__;
})();
