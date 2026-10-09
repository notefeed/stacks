# stacks

How [notefeed.me](https://notefeed.me) runs [notefeed](https://github.com/notefeed/notefeed): the compose files of the server, one folder per tool. It is public as a worked example of a production setup with PostgreSQL, an S3-compatible image store and Caddy in front; take what is useful.

| Folder | What runs | Reachable |
|---|---|---|
| `notefeed/` | notefeed, PostgreSQL 17 and Versity Gateway (the image store); `legal/` holds this instance's imprint, privacy page and the notice on its start page, `scripts/dump.sh` dumps the database and `scripts/copy-images.sh` copies the image files | On the server's private address only: Caddy passes requests on, and the monitoring server scrapes `/metrics` |
| `caddy/` | Caddy: certificates from Let's Encrypt and the front door | Public, ports 80 and 443 |
| `collectors/` | Alloy (container logs to Loki), the Beszel agent, and AutoKuma, which turns the `kuma.*` labels in these files into monitors in Uptime Kuma | Not from outside |

## How it is used

This repository is checked out on the server. A companion repository, which is private because it holds the inventory and the secrets, provisions the server with Ansible, writes each folder's `.env` and runs `docker compose up`. So:

- **There are no secrets and no server addresses in here.** Each folder's `.env.example` lists the names; the values are written on the server.
- **Nobody edits files on the server.** A change is a commit here, then a deployment.
- **Versions are pinned.** Dependabot opens a pull request when a new image exists; merging it is the decision to upgrade.

## Backups: dumps of the database and copies of the images

`notefeed/scripts/dump.sh <kind> <days to keep>` writes one dump to `notefeed/data/dumps` and removes older dumps of the same kind. On the server it runs every hour (kept 1 day), every day (kept 30 days) and before each deployment that changes something; the timers are set up by the companion repository. The images are not in a dump: they are the files in `notefeed/data/s3`, and `notefeed/scripts/copy-images.sh <kind> <days to keep>` copies them into `notefeed/data/image-copies`, every day, kept 30 days, with unchanged files hard-linked to the previous copy so thirty copies cost one copy plus what changed. How to restore is at the top of each script: a restore is a dump and the copy made the same day.

Everything stays on the server, on the same disk as the database, plus the 7-day snapshots Hetzner keeps apart from the server. That is a decision ([notefeed/notefeed#157](https://github.com/notefeed/notefeed/issues/157)): nothing is copied outside the account while the service earns nothing. The dumps undo a bad upgrade or a mistake, the snapshots cover a lost disk; the account itself being lost is accepted for now.

A deleted feed is gone from the last backup after 31 days: 30 days of daily dumps and copies, each made up to a day after the deletion. That is the number on the privacy page. Backups are for the operator's disasters only, never for restoring a feed on request: deletion is final for users.

## Trying it yourself

```sh
cp notefeed/.env.example notefeed/.env   # fill in the secrets; PRIVATE_IP=127.0.0.1 on a single machine
cp caddy/.env.example caddy/.env         # your host name and address; UPSTREAM=127.0.0.1:3000 to match
mkdir -p notefeed/data/s3/notefeed-images
(cd notefeed && docker compose up -d)
(cd caddy && docker compose up -d)
```

`collectors/` is only useful with a Loki, a Beszel hub and an Uptime Kuma to send to. The settings are explained in notefeed's [documentation](https://docs.notefeed.me/self-hosting/configuration/).
