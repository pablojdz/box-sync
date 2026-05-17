# Box Sync

Small `rclone` helper script for syncing local Fedora folders to Box.

The script currently syncs:

- `~/Documents` to `box:Fedora/Documents`
- `~/Downloads` to `box:Fedora/Downloads`

Logs are written to:

```bash
~/.scripts/box-sync-log/box-sync.log
```

## Requirements

- Fedora
- `rclone`
- A configured `rclone` Box remote named `box`

## Install rclone on Fedora

Install `rclone` from the Fedora repositories:

```bash
sudo dnf install rclone
```

Confirm it installed:

```bash
rclone version
```

## Configure Box

Start the interactive `rclone` setup:

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

The sync script expects the remote to be named exactly `box`, because it uses paths like:

```bash
box:Fedora/Documents
box:Fedora/Downloads
```

## Make the script executable

From this directory:

```bash
chmod +x box_sync.sh
```

## Add a shell alias

Add this alias to your shell config.

For `zsh`, edit `~/.zshrc`:

```bash
alias box-sync="/home/pablo/.scripts/box-sync/box_sync.sh"
```

Reload your shell config:

```bash
source ~/.zshrc
```

For `bash`, add the same alias to `~/.bashrc` and reload it:

```bash
source ~/.bashrc
```

## Usage

Run:

```bash
box-sync
```

Or run the script directly:

```bash
/home/pablo/.scripts/box-sync/box_sync.sh
```

The script prints progress in the terminal and exits with the number of failed sync targets. A successful run exits with `0`.

## Notes

This uses `rclone sync`, which makes the destination match the source. Files removed locally from `~/Documents` or `~/Downloads` can also be removed from the corresponding Box destination.
