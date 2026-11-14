# stacks

How [notefeed.me](https://notefeed.me) runs [notefeed](https://github.com/notefeed/notefeed): the compose files of the server, one folder per tool. It is public as a worked example of a production setup with PostgreSQL and an S3-compatible image store; take what is useful.

| Folder | What runs | Reachable |
|---|---|---|
| `notefeed/` | notefeed, PostgreSQL 17 and Versity Gateway (the image store); `legal/` holds this instance's imprint, privacy page, terms and the license page's words (`license.md`), `scripts/dump.sh` dumps the database and `scripts/copy-images.sh` copies the image files | On the server's private address only: the business's Caddy on its other server passes requests on |
| `collectors/` | Alloy (container logs to Loki; the machine's, notefeed's, PostgreSQL's and healthchecks' numbers to Prometheus, which fetches nothing from this server itself), the Beszel agent, AutoKuma, which turns the `kuma.*` labels in these files into monitors in Uptime Kuma, and the PostgreSQL exporter (profile `postgres`, once its login has a password) | Not from outside |

Until 2026-11-01 gesetze-fuer-ki.de had its folder here too; it moved, with its history, to Gesetze-fuer-KI/stacks.

Until 2026-11 `caddy/` was here too: the front door with the certificates, for this server's three sites (notefeed.me,
[gesetze-fuer-ki.de](https://gesetze-fuer-ki.de), [gamepanion.app](https://gamepanion.app)). Since then the one Caddy of the
business, on its other server, serves every public name and passes notefeed.me's requests on over the private network; this
server has no public port but SSH. Its routes, with the same limits and the same access log (no addresses, no feed names),
are in the business's private stacks repository.

## How it is used

This repository is checked out on the server. A companion repository, which is private because it holds the inventory and the secrets, provisions the server with Ansible, writes each folder's `.env` and runs `docker compose up`. So:

- **There are no secrets and no server addresses in here.** Each folder's `.env.example` lists the names; the values are written on the server.
- **Nobody edits files on the server.** A change is a commit here, then a deployment.
- **Versions are pinned.** Dependabot opens a pull request when a new image exists; merging it is the decision to upgrade.

## Backups: dumps of the database and copies of the images

`notefeed/scripts/dump.sh <kind> <days to keep>` writes one dump to `notefeed/data/dumps` and removes older dumps of the same kind. On the server it runs every hour (kept 1 day), every day (kept 30 days) and before each deployment that changes something; the timers are set up by the companion repository. The images are not in a dump: they are the files in `notefeed/data/s3`, and `notefeed/scripts/copy-images.sh <kind> <days to keep>` copies them into `notefeed/data/image-copies`, every day, kept 30 days, with unchanged files hard-linked to the previous copy so thirty copies cost one copy plus what changed. A SQLite file of its own, `notefeed/data/accounts/accounts.sqlite` (the accounts and their licenses), is saved next to each dump by `dump.sh` (`<kind>-<time>.accounts.sqlite`, kept the same days; the host needs `sqlite3`). How to restore is at the top of each script: a restore is a dump and the copy made the same day.

Everything stays on the server, on the same disk as the database, plus the 7-day snapshots Hetzner keeps apart from the server. That is a decision ([notefeed/notefeed#157](https://github.com/notefeed/notefeed/issues/157)): nothing is copied outside the account while the service earns nothing. The dumps undo a bad upgrade or a mistake, the snapshots cover a lost disk; the account itself being lost is accepted for now.

A deleted feed is gone from the last backup after 31 days: 30 days of daily dumps and copies, each made up to a day after the deletion. That is the number on the privacy page. Backups are for the operator's disasters only, never for restoring a feed on request: deletion is final for users.

## Trying it yourself

```sh
cp notefeed/.env.example notefeed/.env   # fill in the secrets; PRIVATE_IP=127.0.0.1 on a single machine
mkdir -p notefeed/data/s3/notefeed-images
(cd notefeed && docker compose up -d)
```

Put a reverse proxy with TLS in front of `127.0.0.1:3000`. With Caddy, the essentials of notefeed.me's:

```caddyfile
notes.example.com {
	encode zstd gzip
	# A note with its pictures is one request: the text and up to ten images of at most 10 MiB each.
	request_body {
		max_size 120MB
	}
	# Caddy writes X-Forwarded-For itself, which notefeed reads with NOTEFEED_TRUST_PROXY=1.
	reverse_proxy 127.0.0.1:3000
}
```

`collectors/` is only useful with a Loki, a Beszel hub and an Uptime Kuma to send to. The settings are explained in notefeed's [documentation](https://docs.notefeed.me/self-hosting/configuration/).
