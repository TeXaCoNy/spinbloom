# What Spinbloom does on your computer

Spinbloom is a music player for the Omarchy shell. This page lists everything it runs, stores, changes and connects to, so you can decide whether to install it.

## What it runs

- **A hidden Chromium window** (your installed Chromium-based browser), opened in its own separate profile, showing music.youtube.com. It is the music engine and is parked on a hidden Hyprland workspace. It never shares your normal browser profile, history or passwords.
  - It is controlled through `--remote-debugging-pipe`: a private pipe between two processes, not a network port. Nothing on your network or on other user accounts can reach it.
  - Extensions, sync and Chromium's background services are turned off in that profile.
- **A small Python helper** (`bin/spinbloom-engine`), started as a user service (`systemd-run --user`, unit `spinbloom-engine`). It talks to the shell through a Unix socket that only your user can open (folder `0700`, socket `0600`).
- **Standard desktop tools**, always called with fixed program paths and separate arguments, never through a shell with outside text in it:
  - `hyprctl` (window rules, keyboard shortcuts),
  - `notify-send` (song notifications),
  - `pactl` (the "Play music on" device picker),
  - `wl-copy` ("Copy song link").

Spinbloom never asks for `sudo` or other admin rights, and never downloads or runs code from the internet.

## What it connects to

Only these, all over HTTPS:

- `music.youtube.com`, `www.youtube.com` and `accounts.google.com`: YouTube Music itself and its sign-in.
- Google's and YouTube's image servers (`i.ytimg.com`, `lh3.googleusercontent.com`, `yt3.googleusercontent.com`, `yt3.ggpht.com`, `lh3.ggpht.com`): album covers for notifications. Downloads are capped at 2 MB, and a redirect to any other address is refused.
- `github.com`: only if you click a link on the About page.

Spinbloom has no analytics, tracking or telemetry.

## What it stores

| Folder | What | Removed by |
|---|---|---|
| `~/.local/share/spinbloom` | The hidden browser profile (your YouTube Music sign-in) | Settings → Advanced → Erase, or uninstalling |
| `~/.cache/spinbloom` | Up to 200 small album covers | Settings → Advanced → Clear cache |
| `~/.local/state/spinbloom` | Small markers (for example whether you turned on desktop blur) | Uninstalling |
| `/run/user/<you>/spinbloom` | The socket, and the song to resume after a restart | Your next log-out |

Your settings live in your own `~/.config/omarchy/shell.json`, in Spinbloom's bar entry.

**After you uninstall:** if the plugin folder is gone and no player has connected for two minutes, the helper closes the hidden browser and deletes the four folders above (only folders whose name ends in `spinbloom`). Before deleting, it checks every path.

## What it changes in your desktop

Everything below is set while Hyprland runs and is never written into your Hyprland config files. A Hyprland reload or restart undoes it, and Spinbloom sets it again next time it starts.

- **Window and layer rules:** they keep the hidden browser off your screen and blur the glass behind Spinbloom's own panels.
- **Keyboard shortcuts:** Super+Alt+M (player), Super+Alt+P (play/pause), Super+Alt+N (next), Super+Alt+B (previous) and Super+Alt+L (like).
  - A key another app already uses is never taken; Spinbloom uses its next choice instead.
  - The shortcuts are removed when the plugin is removed, and you can turn them off with the `globalKeys` setting.
- **"Use desktop blur"** (Settings → Appearance) is **off by default**. When you turn it on, it switches on Hyprland blur for panels only (app windows are left unblurred). Turning it off switches it back.

Spinbloom never touches another plugin's files. If **Solfa**, the player Spinbloom is based on, is installed too, both run side by side and Spinbloom leaves Solfa's folders alone.

## Text from the internet

Song titles, artists, playlist names and lyrics come from YouTube, and anyone can upload them. Spinbloom always shows them as plain text, and escapes them in notifications, so a title can't change how anything looks or behaves. When a song or playlist value is sent to the YouTube Music page, it is encoded as data (JSON), never as code.

## Reporting a problem

If you find a security problem, please open an issue on the project's GitHub page. For anything sensitive, ask there for a private contact first.
