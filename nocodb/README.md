# Reports: NocoDB

Reports about content on the site land here: notefeed puts a **Report** link on every note (`NOTEFEED_REPORT_URL`, see the notefeed [documentation](https://docs.notefeed.me/self-hosting/legal-pages/#a-report-link-on-every-note)), the link opens NocoDB's public form with the note's ids filled in, and the operator works through the rows. The reasons, and what is kept for how long, are in the companion repository's `docs/decisions.md` (Reports). This file is the recipe: what is clicked in NocoDB's UI once the container runs, because NocoDB keeps that in its database, not in files.

Tried on 2026-10-09 with NocoDB 2026.09.1 (a local container, the meta API and a browser): the pre-filled form and the webhook work as described; the licence and the spam question are in the decisions file.

## The table

Base **Reports**, table **reports**, with these fields (the titles without spaces, so the link's query string stays plain):

| Field | Type | Notes |
|---|---|---|
| `read_id` | Single line text | Filled by the link; the feed's read id, never its name |
| `note_id` | Single line text | Filled by the link |
| `file` | Single line text | Filled by the link; the note's file name |
| `reason` | Single select | `Illegal content`, `Personal data`, `Copyright`, `Spam`, `Other` |
| `text` | Long text | What the reporter says |
| `email` | Email | Optional; blanked when the report is closed |
| `status` | Single select | `open` (default), `acted on`, `rejected` |
| `takedown` | Single line text | What was done: the takedown command's output, or why not |

## The form

A **Form** view on the table, shared (**Share** → **Enable public viewing**), with **Enable prefill** on and the prefilled fields **locked** (read-only), so a reporter cannot change the ids by hand. In the form, `read_id`, `note_id` and `file` are shown read-only (or hidden: NocoDB's third mode), `reason` and `text` are required, `email` optional with the note that it is used only to answer, `status` and `takedown` are left out of the form.

The link notefeed puts on every note, with the share's uuid:

```
NOTEFEED_REPORT_URL=https://report.notefeed.me/#/nc/form/<uuid>?read_id={read_id}&note_id={note_id}&file={file}
```

A URL parameter is matched to a field by its title, percent-encoded as notefeed sends it.

## The ping

A **Webhook** on the table, event **After insert**, method **GET**, URL

```
https://ntfy.sh/<the alerts topic>?message=new+report&title=report.notefeed.me&priority=4&tags=mailbox
```

ntfy publishes a GET's query as the message, and NocoDB sends a GET without a body (checked: only the query arrives), so the ping says "new report" and nothing of the report's content leaves the server.

## Working through a report

1. Open the row; the ids open `https://notefeed.me/r/<read_id>/<note_id>`.
2. Act or not: the takedown command (notefeed/notefeed #155) with the read id, or a reply to the reporter. Nothing is hidden automatically on a report.
3. Set `status` to `acted on` or `rejected`, write what was done in `takedown`, and blank `text` and `email`: the bare record (time, reason, outcome) stays a year, then the row is deleted. The year's rows are reviewed at the start of each year.

## Spam

NocoDB's shared form has no captcha and no rate limit. The form's address is only on the notes' links and the ping carries no content, so spam costs an alert and a row to reject. If it comes: a rate limit in Caddy on `report.<site>` (Caddy needs the `caddy-ratelimit` module for that, a custom build) or a shared-view password, which would stop anonymous reports as well.
