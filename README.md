# Box Sync

Small `rclone` helper script for syncing local Fedora folders to Box.

Local folders are the **source of truth**. The script mirrors them to Box with `rclone sync` and applies ignore rules from [`rclone-filters.txt`](rclone-filters.txt).

## What syncs

| Local | Box remote |
|-------|------------|
| `~/Documents` | `box:Fedora/Documents` |
| `~/Downloads` | `box:Fedora/Downloads` |

Logs: `~/.scripts/box-sync-log/box-sync.log`

## Requirements

- Fedora
- `rclone`
- A configured `rclone` Box remote named `box`
- [`rclone-filters.txt`](rclone-filters.txt) next to `box_sync.sh` (used automatically)

## Install rclone on Fedora

```bash
sudo dnf install rclone
rclone version
```

## Configure Box

```bash
rclone config
```

Create a new remote:

1. Choose `n` for a new remote.
2. Name it `box`.
3. Choose `box` as the storage provider.
4. Follow the prompts to authorize your Box account.
5. Save the remote.

Check that the remote works:

```bash
rclone lsd box:
```

The script expects the remote name `box` and paths:

```bash
box:Fedora/Documents
box:Fedora/Downloads
```

## Make the script executable

```bash
chmod +x box_sync.sh
```

## Add a shell alias

In `~/.zshrc` (or `~/.bashrc`):

```bash
alias box-sync="$HOME/.scripts/box-sync/box_sync.sh"
```

Reload:

```bash
source ~/.zshrc   # or: source ~/.bashrc
```

The alias does not need extra flags for filters. `box_sync.sh` resolves [`rclone-filters.txt`](rclone-filters.txt) relative to the script path and passes `--filter-from` to rclone.

## Usage

```bash
box-sync
```

Or:

```bash
"$HOME/.scripts/box-sync/box_sync.sh"
```

On an interactive terminal, the script shows a minimal progress UI (Unicode bar per target):

- During a real upload, the bar tracks rclone's actual byte percentage (parsed from `--stats=1s` output in the log).
- While rclone is only comparing files (no bytes to transfer), the bar fills with a smooth time-based estimate.

rclone transfer details go to the log file, not the console. Non-TTY runs (e.g. cron/systemd) print plain status lines instead.

Exit code is the number of failed sync targets (`0` = success).

## Filters

Ignored paths are defined in [`rclone-filters.txt`](rclone-filters.txt). Every `box-sync` run uses that file.

Excluded by default:

- `.git/` directories
- OnlyOffice / LibreOffice locks and temps (`.~lock.*`, `.~*`, `~$*`)
- Agent / IDE tooling (`.antigravitycli`, `.claude`, `.agents`, `.gemini`)
- Common junk (`node_modules`, `__pycache__`, `.venv`, `.cache`, `*.tmp`, `*.swp`, `.DS_Store`, `Thumbs.db`)

Edit the filter file to add or remove patterns. Root and nested forms are both listed (e.g. `.git/**` and `**/.git/**`) so matches work at folder roots and deeper paths.

### Symlinks

The sync uses `--skip-links`: symlinks are ignored and rclone does not log a NOTICE for each one.

`--copy-links` / `-L` is intentionally **not** used. Some links under Documents point outside the tree (for example Gemini config under `~/.gemini`), and following them would upload tooling files you do not want on Box.

### Preview a sync (no upload)

```bash
rclone sync ~/Documents box:Fedora/Documents \
  --filter-from="$HOME/.scripts/box-sync/rclone-filters.txt" \
  --dry-run -v
```

## Clean up junk already on Box

Do **not** pass the sync filter file to `rclone delete`. Those rules use `-` (exclude), so they skip the junk instead of deleting it.

Use `--include` to whitelist junk only. Include **both** root and nested patterns — `**/.~lock.*` alone misses files in the remote root (for example `.~lock.*.docx#` in `Downloads`).

### List matching junk

```bash
rclone lsf "box:Fedora/Downloads" -R --include "{**/,}.~lock.*"
rclone lsf "box:Fedora/Documents" -R --include "{**/,}.~lock.*"
rclone lsf "box:Fedora/Documents" -R --include "{**/,}.git/**"
```

### Dry-run delete (Downloads)

```bash
rclone delete "box:Fedora/Downloads" \
  --include ".~lock.*" \
  --include "**/.~lock.*" \
  --include ".~*" \
  --include "**/.~*" \
  --include "~$*" \
  --include "**/~$*" \
  --include "*.tmp" \
  --include "**/*.tmp" \
  --include "*.swp" \
  --include "**/*.swp" \
  --include ".*.sw?" \
  --include "**/.*.sw?" \
  --include ".DS_Store" \
  --include "**/.DS_Store" \
  --include "Thumbs.db" \
  --include "**/Thumbs.db" \
  --include ".git/**" \
  --include "**/.git/**" \
  --include "node_modules/**" \
  --include "**/node_modules/**" \
  --include "__pycache__/**" \
  --include "**/__pycache__/**" \
  --include ".venv/**" \
  --include "**/.venv/**" \
  --include ".cache/**" \
  --include "**/.cache/**" \
  --rmdirs \
  --dry-run -v
```

### Dry-run delete (Documents)

Same command with `"box:Fedora/Documents"` instead of `"box:Fedora/Downloads"`.

### Delete for real

Drop `--dry-run` after the dry-run output looks correct.

To remove a single file:

```bash
rclone deletefile "box:Fedora/Downloads/.~lock.example.docx#"
```

## Notes

- `rclone sync` makes the Box destination match the local source. Files you delete locally can also be removed from the matching Box folder.
- Filters stop new uploads of junk; they do not remove junk already on Box until you run a cleanup (see above).
- Symlinks are skipped with `--skip-links` (see [Symlinks](#symlinks)); do not enable `--copy-links` for this backup.
- `--delete-excluded` on sync can purge excluded remote files automatically, but use it only after a careful `--dry-run`.
