# Setup rclone For Google Drive On RunPod

Use `rclone`, not public Google Drive links. Public links are fragile, rate-limited, and awkward for large files.

## 1. Start rclone config

```bash
rclone config
```

Choose:

```text
n
```

Remote name:

```text
gdrive
```

Storage type:

```text
drive
```

Client ID and client secret can be left empty for first use. For heavy long-term use, a personal Google OAuth client is more stable.

Scope:

```text
1
```

This gives full Drive access to this rclone remote. A narrower scope can be used later if desired.

For advanced config, choose:

```text
n
```

For auto config, choose:

```text
n
```

RunPod is a remote server without your local browser. rclone will print a URL. Open that URL on your local computer, approve access, copy the returned token/code, and paste it back into the RunPod terminal.

Finish the remote setup and keep the remote.

## 2. Test the remote

```bash
rclone lsd gdrive:
rclone mkdir gdrive:RunPod_Backup
rclone ls gdrive:RunPod_Backup
```

If these commands work, the backup scripts can use Google Drive.

## 3. Token safety

The rclone config contains access credentials. Do not paste it into chat or screenshots.

Usual location:

```bash
~/.config/rclone/rclone.conf
```

On a future RunPod, either run `rclone config` again or copy this config securely.

