<img src="docs/icon.png" width="96" align="right" alt="">

# Vaultwarden for Synology DSM

A DSM 7 package that installs [Vaultwarden](https://github.com/dani-garcia/vaultwarden)
— the lightweight server for the Bitwarden apps — in Container Manager, with a
**Vaultwarden** window in DSM for the things that otherwise need a shell:
the admin token, locked-out users, sign-ups, backups, mail, updates, and a
clean removal. It serves **HTTPS itself**, with DSM's own certificate. Built on the [DSM app chassis](https://github.com/tombruton87/dsm-app-chassis).

## Download

### **[⬇ Download vaultwarden.spk](https://github.com/tombruton87/vaultwarden-dsm/releases/latest/download/vaultwarden.spk)**

[![Latest release](https://img.shields.io/github/v/release/tombruton87/vaultwarden-dsm?label=latest&color=3b5068)](https://github.com/tombruton87/vaultwarden-dsm/releases/latest)

That link always gives the newest version. Older ones are on the
[Releases](https://github.com/tombruton87/vaultwarden-dsm/releases) page.

Install: Package Center → Manual Install → the `.spk` (DSM 7.2.1+; Container
Manager is installed first if missing). The wizard asks for the NAS's address,
a port, a time zone, whether sign-ups are open, and how to do HTTPS. Then open
the address, create your account, and point the Bitwarden apps at it.

## HTTPS

The Bitwarden apps and browser extensions refuse plain HTTP, so the package
puts nginx in front of Vaultwarden and serves HTTPS on the chosen port:

- **DSM's certificate** (default): the system-default certificate from
  Control Panel → Security → Certificate, read from the NAS at every start
  and once a day, so a Let's Encrypt renewal is picked up by itself.
- **Self-signed**: a certificate made by the package for the NAS's address.
  Browsers warn once; the web vault then works. The apps need a trusted
  certificate, so get one from Let's Encrypt in DSM and make it the default.
- **Off**: plain HTTP, for people who put Vaultwarden behind DSM's reverse
  proxy themselves (the Site address tab has the steps).

The Site address tab shows the certificate in use (issuer, names, expiry)
and can read DSM's again or make a new self-signed one.

## The window

| Tab | What it does |
|---|---|
| **Overview** | Is it up, the container, free space, last backup, the setup log; Open, Restart. |
| **Admin** | The admin page's token (made at install, hashed in the container, shown once; make a new one if lost). Sign-ups, invitations and password hints on/off. |
| **Users** | Every account with status, 2FA, items, attachments, last activity. **Remove 2FA** for someone locked out, disable/enable, invite, delete. |
| **Backups** | A consistent SQLite copy plus attachments, sends, keys and admin settings in one tar; nightly, save, restore, retention. |
| **Site address** | URL, port, time zone; HTTPS with DSM's certificate or a self-signed one, the certificate in use; or plain HTTP behind DSM's reverse proxy, with the steps. |
| **Mail** | Which SMTP server is set; send a test email. |
| **Activity** | Failed sign-ins by address from Vaultwarden's log; a DSM notification on a burst. |
| **Updates** | A newer Vaultwarden image (backup first) or package, applied from inside DSM. |
| **Storage** | The data volume's parts: database, attachments, sends, icon cache. |
| **Maintenance** | A redacted support report, container logs, and Remove Vaultwarden and everything. |

Administrators can do everything; a DSM user the app is granted to gets a read-only window.

## Screenshots

| | |
|---|---|
| ![Overview](docs/screenshots/overview.png) | ![Admin](docs/screenshots/admin.png) |
| ![Users](docs/screenshots/users.png) | ![Backups](docs/screenshots/backups.png) |
| ![Site address](docs/screenshots/site.png) | ![Mail](docs/screenshots/mail.png) |
| ![Activity](docs/screenshots/activity.png) | ![Updates](docs/screenshots/updates.png) |
| ![Storage](docs/screenshots/storage.png) | ![Maintenance](docs/screenshots/maintenance.png) |

## Layout

```
chassis/          the DSM app chassis (git submodule)
package.conf      name, title, services, volumes, images, port, texts
app/compose.yaml  Vaultwarden and nginx in front (HTTPS); data in the vaultwarden_data volume
setup/app.sh      the hooks: HTTPS (DSM's or a self-signed certificate), admin token (argon2), backups (sqlite3 .backup), admin API, failed sign-ins
ui/               Admin, Users, Mail, Activity tabs; CGI validation of their actions
wizard/           the Accounts and HTTPS pages of the install wizard
tests/            steps for the chassis harness
```

Release: bump `VERSION`, add the changes to `CHANGELOG.md`, build, then attach
the package twice, under its versioned name and as `vaultwarden.spk` (the
download link above points at that name on the latest release):

```bash
cp dist/vaultwarden-X.Y.Z-1.spk /tmp/vaultwarden.spk
gh release create vX.Y.Z dist/vaultwarden-X.Y.Z-1.spk /tmp/vaultwarden.spk
```

Build: `chassis/build.sh . N`. Test: `chassis/tests/e2e.sh . up && chassis/tests/e2e.sh . act` on any Linux box with Docker.

## Credits

The icon is Vaultwarden's own mark (from the `vaultwarden/server` image) on a
DSM-style tile. Vaultwarden is an independent project and not affiliated with
Bitwarden, Inc.; this package is not affiliated with either, or with Synology.
