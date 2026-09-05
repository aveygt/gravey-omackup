# Omackup

Incremental backups of personal files for [Omarchy](https://omarchy.org/), with a bar panel for setup and restore.

Omarchy's Snapper snapshots roll back the **root** filesystem after a bad update. They do not recover documents, photos, or `~/.config`. Omackup covers that gap with [restic](https://restic.net): encrypted, deduplicated, incremental backups to a USB drive, a NAS, or the cloud.

The bar icon turns red when a scheduled backup failed or is overdue, yellow when files still need backing up, and becomes the backup percent while a run is in progress. With **RGB loading bar** enabled, that percent cycles colors during the backup. After the plugin is enabled, Super+Space can launch the same panel — type **Omackup**.

A real backup and the unbacked-up-files scan cannot run at the same time. The scan yields if a backup starts.

Manual and scheduled backups run as a systemd user service (`omackup@<dest>.service`), so an Omarchy shell / Quickshell restart does not stop a run in progress. The panel reconnects and keeps showing progress.

## Install

```bash
omarchy pkg add restic
omarchy plugin add https://github.com/gravey/gravey-omackup
omarchy plugin enable gravey.omackup
omarchy bar move gravey.omackup --section right
```

From a local checkout instead of GitHub:

```bash
omarchy pkg add restic
mkdir -p ~/.config/omarchy/plugins
ln -sfn /path/to/gravey-omackup ~/.config/omarchy/plugins/gravey.omackup
omarchy-shell shell rescanPlugins
omarchy plugin enable gravey.omackup
omarchy bar move gravey.omackup --section right
```

The CLI lives inside the plugin. Call it with the full path, or add an alias:

```bash
alias omackup=~/.config/omarchy/plugins/gravey.omackup/bin/omackup
```

## First run

Click the bar icon, or open Super+Space and type **Omackup**.

1. **Sources** — a tree of `/home/<you>`. Check a folder or file to include it, or expand a folder and check only some of its children. Exclude patterns still skip caches, `node_modules`, and VM images.
2. **Add destination** — USB, NAS over SFTP, or S3 / Backblaze B2.
3. **Schedule** — nightly, another systemd calendar, or manual only.
4. **Save the password off this machine.** Backups are encrypted. The password is also stored locally so nightly runs do not prompt you. If this computer dies, that local copy is gone. Put the password in a password manager that is not only on this laptop.

Files you restore never overwrite what you have now. They land in `~/Restored/`. Move them into place yourself.

## Destinations

One restic repository per destination. You can keep several.

**USB / local drive**

Pick a mounted volume under `/run/media/$USER`. Omackup writes a `omackup` folder on that drive.

**NAS**

Host, user, and an absolute path. Stored as a restic SFTP repository:

```
sftp:you@nas:/volume1/backups/omackup
```

Optional wake command runs first, for a sleeping NAS or a mount unit.

**Cloud**

Amazon S3 (or S3-compatible) and Backblaze B2. For B2, enter the bucket plus the application key's **keyID** and **applicationKey**. Omackup talks to B2 over its S3-compatible API. Credentials are stored in `~/.local/share/omackup/secrets/<name>/env`, not in git and not in the plugin checkout.

A drive in your bag plus a bucket offsite is a solid pair: one is fast, the other survives the house.

## Password

The restic password for each destination is a `0600` file:

```
~/.local/share/omackup/secrets/<name>/password
```

That path is excluded from backups on purpose. The encrypted repository cannot unlock itself. Show a saved password with:

```bash
omackup key-show --dest usb
```

Copy that somewhere that is not this computer. Do it the day you set the destination up.

## Command line

Every panel action goes through `bin/omackup`. JSON on stdout.

```bash
omackup status
omackup destinations
omackup dest-add --name usb --kind usb --repository /run/media/$USER/Backup/omackup
omackup dest-add --name nas --kind nas --repository sftp:you@nas:/backups/omackup --schedule '*-*-* 03:00:00'
omackup dest-add --name offsite --kind cloud --repository s3:s3.amazonaws.com/my-bucket/omackup \
  --env AWS_ACCESS_KEY_ID=... --env AWS_SECRET_ACCESS_KEY=...
omackup key-set --dest usb
omackup init --dest usb
omackup backup --dest usb
omackup backup-start --dest usb
omackup snapshots --dest usb
omackup ls --dest usb --snapshot latest --path /home/$USER/Documents
omackup restore --dest usb --snapshot latest --path /home/$USER/Documents/notes.md
omackup schedule-install
omackup launcher-install
```

Config lives in `~/.config/omackup/config.json`. Last-run state is in `~/.local/state/omackup/`. Backup, the unbacked-up scan, and selection-size share a lock there so they never walk your files at the same time. Live backup progress is written to `backup.active.json` and `backup.progress.jsonl` in that state directory so the panel can resume after a shell restart.

Default retention is 7 daily, 4 weekly, 12 monthly, and 3 yearly snapshots. Older backups are thinned after each successful run.

## Schedule

`omackup schedule-install` writes systemd user timers from the config. A destination with no schedule only runs when you press **Backup now**, which starts the same `omackup@<dest>.service` unit.

Timers fire while you are logged in. `Persistent=true` means a missed 03:00 run happens at the next login. To run while the machine is on but you are logged out:

```bash
loginctl enable-linger "$USER"
```

## Uninstall

```bash
omarchy plugin remove gravey.omackup
omackup schedule-uninstall
omackup launcher-uninstall
```

Removing the widget does not delete repositories, config, or passwords. To drop local Omackup state as well:

```bash
rm -rf ~/.config/omackup ~/.local/state/omackup ~/.local/share/omackup
```

Do not delete `~/.local/share/omackup/secrets` unless you already have every destination password somewhere else. The backups themselves stay on the drive, NAS, or bucket.
