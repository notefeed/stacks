# stacks

How [notefeed.me](https://notefeed.me) runs [notefeed](https://github.com/notefeed/notefeed): the compose files of the server, one folder per tool. It is public as a worked example of a production setup with PostgreSQL, an S3-compatible image store and Caddy in front; take what is useful.

| Folder | What runs | Reachable |
|---|---|---|
| `notefeed/` | notefeed, PostgreSQL 17 and Versity Gateway (the image store) | Only through Caddy; `/metrics` also on the private network |
| `caddy/` | Caddy: certificates from Let's Encrypt and the front door | Public, ports 80 and 443 |
| `collectors/` | Alloy (container logs to Loki) and the Beszel agent | Not from outside |

## How it is used

This repository is checked out on the server. A companion repository, which is private because it holds the inventory and the secrets, provisions the server with Ansible, writes each folder's `.env` and runs `docker compose up`. So:

- **There are no secrets and no server addresses in here.** Each folder's `.env.example` lists the names; the values are written on the server.
- **Nobody edits files on the server.** A change is a commit here, then a deployment.
- **Versions are pinned.** Dependabot opens a pull request when a new image exists; merging it is the decision to upgrade.

## Trying it yourself

```sh
docker network create edge
cp notefeed/.env.example notefeed/.env   # fill in the secrets; PRIVATE_IP=127.0.0.1 on a single machine
cp caddy/.env.example caddy/.env         # your host name and address
mkdir -p notefeed/data/s3/notefeed-images
(cd notefeed && docker compose up -d)
(cd caddy && docker compose up -d)
```

`collectors/` is only useful with a Loki and a Beszel hub to send to. The settings are explained in notefeed's [documentation](https://docs.notefeed.me/self-hosting/configuration/).
