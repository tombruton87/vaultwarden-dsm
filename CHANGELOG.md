# Changelog

## 1.0.0

First release, on the DSM app chassis.

- Vaultwarden (vaultwarden/server, amd64 and arm64) as a Container Manager project; its data in the `vaultwarden_data` volume, backups and settings in the `vaultwarden` shared folder.
- DSM window: Overview; **Admin** (the admin page's token, hashed in the container and shown once here; sign-ups and invitations on/off; password hints); **Users** (every account with last activity, 2FA and attachment size; remove 2FA for someone locked out, disable/enable, invite, delete); Backups (consistent SQLite copy, attachments, sends, keys, admin settings; nightly, restore); Site address (HTTPS behind DSM's reverse proxy); **Mail** (send a test email through Vaultwarden's SMTP settings); **Activity** (failed sign-ins by address from Vaultwarden's log, a DSM notification on a burst); Updates (image and package); Storage; Maintenance (support report, remove everything).
