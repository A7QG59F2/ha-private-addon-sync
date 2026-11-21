# Private Add-on Sync

Home Assistant's add-on store can't add private GitHub repositories. This
add-on fetches them with a GitHub token and copies each add-on folder into
`/addons`, where it shows up under **Local add-ons**. When a repo changes, it
reloads the store so the new version appears as an update.

## Token

Either works:

- **Fine-grained token (recommended):** GitHub → Settings → Developer settings →
  Fine-grained tokens. Limit it to the repos you want, with
  **Contents: Read-only**.
- **Classic token:** the `repo` scope. It can read every private repo you have.

## Configuration

```yaml
github_token: github_pat_xxx
repositories:
  - repo: your-name/your-private-addons
  - repo: your-name/another-repo
    branch: dev
sync_interval_minutes: 60
```

- `repositories`: `owner/name`, plus an optional `branch` (default branch if
  omitted). Every folder with a `config.yaml` (or `.yml`/`.json`) at the repo
  root or one level down is installed. A root-level add-on is named after the
  repo.
- `sync_interval_minutes`: how often to check. `0` syncs once at start;
  restart the add-on to sync again.

## Notes

- Add-ons install to `/addons/<folder name>`. A folder that already exists and
  wasn't created by this add-on (for example one you copied by hand) is left
  alone and logged; delete it once and the next sync takes over.
- Uninstalling this add-on leaves the synced add-ons in place.
- Local add-ons build on your Home Assistant host, so the first install and
  each update take a little longer than prebuilt images.
