## 1.1.3 — 2026-10-10

- The Copy button for the admin token works when DSM is opened over plain
  HTTP (http://nas:5000), where browsers don't offer the clipboard API. If
  copying is refused, the token is selected with a Ctrl+C hint.
- Built on the latest chassis (volumes made with Docker Compose's labels;
  shared HTTPS helpers).

## 1.1.2 — 2026-10-09

- A new icon: Vaultwarden's own cog-and-V mark on a slate tile shaped like
  DSM's own icons, in Package Center, the main menu and the window.
- The HTTPS proxy's volume is made with Docker Compose's labels, so Compose
  no longer warns that it isn't its own.

## 1.1.1 — 2026-10-09

- Upgrading from 1.0.0 left the address (and so every link in the window and
  Vaultwarden's own DOMAIN) on http:// while the proxy served HTTPS. Each start
  now reconciles the address with the HTTPS mode, and an upgraded install
  gets HTTPS with DSM's certificate.

## 1.1.0 — 2026-10-09

- HTTPS is served by the package itself: nginx in front of Vaultwarden with
  DSM's system-default certificate (read from the NAS, refreshed daily so
  renewals follow) or a self-signed one made at install. Chosen in the
  install wizard and on the Site address tab, which also shows the
  certificate in use, with a button to read DSM's again or make a new
  self-signed one. Plain HTTP behind DSM's reverse proxy remains an option.
- Failed sign-ins are kept for seven days in a file, so they survive a
  restart or a new admin token.
- Disabled accounts were shown as enabled; invited accounts as having 2FA.

# Changelog

## 1.0.0

First release, on the DSM app chassis.

- Vaultwarden (vaultwarden/server, amd64 and arm64) as a Container Manager project; its data in the `vaultwarden_data` volume, backups and settings in the `vaultwarden` shared folder.
- DSM window: Overview; **Admin** (the admin page's token, hashed in the container and shown once here; sign-ups and invitations on/off; password hints); **Users** (every account with last activity, 2FA and attachment size; remove 2FA for someone locked out, disable/enable, invite, delete); Backups (consistent SQLite copy, attachments, sends, keys, admin settings; nightly, restore); Site address (HTTPS behind DSM's reverse proxy); **Mail** (send a test email through Vaultwarden's SMTP settings); **Activity** (failed sign-ins by address from Vaultwarden's log, a DSM notification on a burst); Updates (image and package); Storage; Maintenance (support report, remove everything).
