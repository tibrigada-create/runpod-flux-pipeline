# Setup rclone For Google Drive On Windows

This is the local Windows version. It lets you download LoRAs from your PC and upload them to Google Drive before starting RunPod.

## 1. Install dependencies

From PowerShell in the toolkit folder:

```powershell
.\install_dependencies_windows.ps1
```

If PowerShell blocks scripts, run once:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Then rerun the installer.

## 2. Configure Google Drive

Run:

```powershell
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

Client ID and client secret can be left empty for first use.

Scope:

```text
1
```

Because this runs on your local PC, `Use auto config?` can usually be:

```text
y
```

rclone should open your browser. Log in to Google, approve access, then return to the terminal.

## 3. Test

```powershell
rclone lsd gdrive:
rclone mkdir gdrive:RunPod_Backup
rclone ls gdrive:RunPod_Backup
```

## 4. Token safety

Do not paste rclone config or API tokens into chat, screenshots, or GitHub.

Your rclone config is usually here:

```text
C:\Users\<you>\AppData\Roaming\rclone\rclone.conf
```

