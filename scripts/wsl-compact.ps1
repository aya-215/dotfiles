# Run in an elevated (Administrator) PowerShell. This stops every WSL session.
$ErrorActionPreference = 'Stop'
$vhdx = 'C:\WSL\Ubuntu-22.04\ext4.vhdx'
$distro = 'Ubuntu-22.04'

"before: {0:N1} GB" -f ((Get-Item $vhdx).Length / 1GB)

wsl --shutdown
Start-Sleep 10

# uv cache is locked while uv-based MCP servers run, so clean it on a fresh boot
wsl -d $distro -u aya -- /home/aya/.local/bin/uv cache clean
wsl -d $distro -u aya -- rm -rf /home/aya/.cache/ms-playwright/chromium-1234 /home/aya/.cache/ms-playwright/chromium-1243 /home/aya/.cache/ms-playwright/chromium_headless_shell-1234 /home/aya/.cache/ms-playwright/chromium_headless_shell-1243
wsl -d $distro -u root -- fstrim -av

wsl --shutdown
Start-Sleep 10

$script = Join-Path $env:TEMP 'wsl-compact.txt'
Set-Content -Encoding ascii $script @"
select vdisk file="$vhdx"
attach vdisk readonly
compact vdisk
detach vdisk
"@
diskpart /s $script

"after:  {0:N1} GB" -f ((Get-Item $vhdx).Length / 1GB)
