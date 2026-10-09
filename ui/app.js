// Vaultwarden's tabs on the chassis window: Admin, Users, Mail, Activity.
(function (P) {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  function sw(id, on, action, onText, offText, confirmOn) {   // a setting shown as a chip with a switch button
    var box = $(id), bb = $(id + "-btn"); P.clear(box); P.clear(bb);
    box.appendChild(P.chip(on ? onText : offText, on ? "ok" : ""));
    bb.appendChild(P.btn(on ? "Turn off" : "Turn on", "", function () { P.act(action, { on: on ? 0 : 1 }, (!on && confirmOn) ? confirmOn : null); }));
  }
  P.register("admin", {
    render: function (st) {
      var a = st.app || {}; $("admin-link").href = a.admin_url || "#"; $("admin-link").textContent = a.admin_url || "/admin";
      sw("adm-signups", !!a.signups, "signups", "open — anyone who can reach it can create an account", "closed — invitation only", "Open sign-ups? Anyone who can reach Vaultwarden could create an account.");
      sw("adm-invites", !!a.invites, "invites", "on", "off", null);
      sw("adm-hints", !!a.hints, "hints", "shown on the sign-in page", "only sent by email", "Show password hints on the sign-in page? Anyone can then type an email and read its hint.");
    }
  });
  var userQuery = "";
  $("users-q").addEventListener("input", function () { userQuery = $("users-q").value.trim().toLowerCase(); if (P.S) P.tabs && 0; renderUsers((P.S || {}).status || {}); });
  function renderUsers(st) {
    var tb = $("users"), all = (st.app && st.app.users) || [];
    var users = all.filter(function (u) { return !userQuery || ((u.name || "") + " " + u.email).toLowerCase().indexOf(userQuery) >= 0; });
    $("users-count").textContent = all.length ? (users.length === all.length ? all.length + " accounts" : users.length + " of " + all.length) : "";
    var sig = JSON.stringify(users) + "|" + P.busy + "|" + P.role; if (tb.dataset.sig === sig) return; tb.dataset.sig = sig;
    P.clear(tb);
    if (!all.length) { var tr = P.el("tr"); var td = P.cell("No accounts yet — or Vaultwarden isn't running. The first account is made by signing up at the address above.", "empty"); td.colSpan = 8; tr.appendChild(td); tb.appendChild(tr); return; }
    users.forEach(function (u) {
      var who = u.email, acts = P.el("span", null, "row");
      var status = u.status === 1 ? P.chip("invited", "warn") : !u.enabled ? P.chip("disabled", "bad") : P.chip("active", "ok");
      if (u.twofa) acts.appendChild(P.btn("Remove 2FA", "", function () { P.act("remove2fa", { uuid: u.id }, "Remove two-factor sign-in for " + who + "? They'll sign in with just their master password until they set it up again."); }));
      if (u.enabled) acts.appendChild(P.btn("Disable", "", function () { P.act("userdisable", { uuid: u.id }, "Disable " + who + " and sign them out everywhere?"); }));
      else acts.appendChild(P.btn("Enable", "", function () { P.act("userenable", { uuid: u.id }); }));
      acts.appendChild(P.btn("Delete", "danger", function () { P.act("userdelete", { uuid: u.id }, "Delete " + who + " and their whole vault? There is no undo."); }));
      P.row(tb, [u.email, u.name || "–", status, u.twofa ? P.chip("on", "ok") : P.chip("off", ""), P.cell(String(u.ciphers || 0), "n"), P.cell(u.attachments ? u.attachments + " (" + u.attachment_size + ")" : "–", "n"), u.last_active || "never", P.cell(acts, "n")]);
    });
  }
  P.register("users", { render: renderUsers, tiles: function (t, st) { P.tile(t, String(((st.app || {}).users || []).length), "accounts"); P.tile(t, String(((st.app || {}).failed || {}).last_hour || 0), "failed sign-ins, last hour"); } });
  $("invite").onclick = function () { P.act("invite", { email: $("invite-email").value.trim() }); };
  P.register("mail", {
    render: function (st) { var a = st.app || {}, t = $("mail-tiles"); P.clear(t); P.tile(t, a.smtp_host ? a.smtp_host : "not set", "SMTP server"); $("mail-admin-link").href = a.admin_url || "#"; }
  });
  $("smtptest").onclick = function () { P.act("smtptest", { email: $("smtp-email").value.trim() }); };
  P.register("activity", {
    render: function (st) {
      var f = (st.app || {}).failed || {}, t = $("activity-tiles"); P.clear(t);
      P.tile(t, String(f.last_hour || 0), "failed, last hour"); P.tile(t, String(f.last_day || 0), "failed, last 24 h"); P.tile(t, String((f.by_ip || []).length), "addresses, last 24 h");
      $("activity-byip-card").hidden = !(f.by_ip || []).length; var bi = $("activity-byip"); P.clear(bi); (f.by_ip || []).forEach(function (x) { P.row(bi, [x.ip, P.cell(String(x.count), "n")]); });
    },
    show: function () { P.loadLog("failed", "activity-log"); }, tick: function () { P.loadLog("failed", "activity-log"); },
    badge: function (st) { var n = ((st.app || {}).failed || {}).last_hour || 0; $("badge-activity").hidden = !(n >= 5); $("badge-activity").textContent = String(n); }
  });
  P.register("site", {
    fill: function (st) { var t = (st.app && st.app.tls) || {}; $("set-tls").value = t.mode || "dsm"; },
    values: function () { return { tls: $("set-tls").value }; },
    render: function (st) {
      var t = (st.app && st.app.tls) || {}, c = t.cert, tb = $("tls-info"), note = $("tls-note"), acts = $("tls-actions"); P.clear(tb); P.clear(acts);
      $("tls-card").hidden = t.mode === "off";
      if (t.mode === "off") return;
      if (!c) { P.kv(tb, "Certificate", "none yet — it's made or read when Vaultwarden starts"); note.textContent = ""; return; }
      P.kv(tb, "From", t.source === "dsm" ? "DSM (the system default certificate)" : "the package (self-signed)");
      P.kv(tb, "Issued to", c.subject || "–"); P.kv(tb, "Issued by", c.self_signed ? "itself (self-signed)" : (c.issuer || "–"));
      P.kv(tb, "Expires", (c.expires || "–") + (typeof c.days_left === "number" ? " (" + (c.days_left < 0 ? "expired" : c.days_left + " days") + ")" : ""));
      if (c.names) P.kv(tb, "Names", c.names.replace(/,/g, ", "));
      note.textContent = t.mode === "dsm" && t.source === "self" ? "DSM's certificate wasn't found on this system, so a self-signed one is in use."
        : c.self_signed ? "Self-signed: browsers warn once and the web vault then works; the Bitwarden apps and extensions need a certificate they trust — in DSM, get one from Let's Encrypt (Control Panel → Security → Certificate) and make it the system default."
        : "Browsers and the Bitwarden apps trust this certificate as long as they reach Vaultwarden by one of its names.";
      acts.appendChild(P.btn(t.mode === "dsm" ? "Read DSM's certificate again" : "Make a new self-signed certificate", "", function () { P.act("refreshcert", {}, t.mode === "dsm" ? null : "Make a new self-signed certificate? Browsers will warn once more."); }));
    }
  });
  $("set-tls").addEventListener("change", function () { $("set-url").dataset.touched = "1"; var u = $("set-url").value.trim(); if ($("set-tls").value !== "off" && /^http:\/\//.test(u)) $("set-url").value = "https://" + u.slice(7); });
  P.register("secretNote", function (s) { return s.kind === "admin" ? "Open the admin page and paste it as the token. Keep it in your password manager." : ""; });
  P.register("storage", { render: function (app, st, box) { P.clear(box); var c = P.el("div", null, "card"); var h = P.el("h2", "Inside the data volume"); c.appendChild(h); var tbl = P.el("table"), tb = P.el("tbody"); tbl.appendChild(tb); c.appendChild(tbl);
    [["Database (db.sqlite3)", app["db.sqlite3"]], ["Attachments", app.attachments], ["Sends", app.sends], ["Icon cache (rebuilt as needed)", app.icon_cache]].forEach(function (p) { P.kv(tb, p[0], P.mb(p[1] || 0), true); }); box.appendChild(c); } });
})(window.Panel);
