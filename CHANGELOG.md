# Changelog

## 2.0.0 — Spinbloom

The first release of Spinbloom: Solfa's YouTube Music engine with a new player on top.

**Before you install**

- Needs **Omarchy 4.5 or newer**. Spinbloom is built and tested on Omarchy 4.5; earlier versions haven't been tried.
- Spinbloom is a separate plugin (id `spinbloom`), not an update to Solfa. It keeps its own sign-in, settings and data, and never touches Solfa's. If you use Solfa, you sign in once more in Spinbloom, and Solfa stays as it is.

**The player**

- A frosted-glass player opens from the bar: a large cover with a wheel of CDs beneath it (Dial), or covers side by side (Flow).
- Pick a disc and it lifts off the wheel and slides into the player, then the album's colours bloom out across the glass. Next, Previous and a song ending by itself fly the new disc in too.
- When a new playlist or radio starts, the songs you played before it sit on the left of the wheel, so you can scroll back through your history.
- Three sizes: Full, Compact and Small, each with or without the CD wheel. Click the corner button to step through them.
- A ••• menu with Radio, Save to playlist, Sleep timer, Go to album, Go to artist, Not for me, Copy song link and Settings.
- Save any song to one of your playlists, or start a new playlist from it.
- Sleep timer: 15 or 30 minutes, an hour, or the end of this song. The music fades out, then pauses.
- Like a song and the heart fills with a swirl; unlike it and the swirl winds back.
- Play music on: send just the music to another output (headphones, speakers, your TV) while the rest of your computer's sound stays put.
- Album colours can be turned off for a calm glass in your theme's own colour, light or dark.
- Calm motion swaps the flying discs, spins and swirls for simple fades.
- A welcome screen to sign in, then "Pick something to play" with search and your own mixes.

**The library panel**

- Home, Library, Queue, Lyrics and History tabs, with artwork shelves, album and artist pages, and a grid or list view for your library.
- Hearts on every song row, kept in step with your Liked music.
- The playing song turns as a small CD in the Queue and History lists.

**In the bar**

- A round cover that swirls in when the song changes, with a glass card of the song when you hover it.

**Everywhere**

- Frosted glass on every desktop: the player sets up its own blur, or uses solid glass when Hyprland blur is off (Settings → Appearance → Use desktop blur).
- Keys: Super+Alt+M opens the player, Super+Alt+P plays or pauses, plus Next, Previous and Like. A key another app already uses is never taken; Spinbloom uses its next choice instead (see the README).
- The Inter font is bundled, so the player looks the same on every system.
- Security review: artwork is only downloaded over HTTPS from YouTube's image servers (2 MB at most), all text from YouTube is shown as plain text, and the engine's private socket is readable only by you. [SECURITY.md](SECURITY.md) lists everything Spinbloom runs, stores, changes and connects to.

**Brought over from newer Solfa**

- Signing in waits for YouTube's own sign-in cookie, so it no longer comes back signed out; a second sign-in or a switch of account is seen.
- Sign in clicked while the engine is still starting says so instead of doing nothing.
- Long queues (playlists, shuffles, radio) load their next page as you reach the end of the list, and no longer stop short after the engine refreshes its page.
- The unfiltered search follows YouTube Music's own ranking and shows videos, episodes and podcasts too.

Spinbloom is based on [Solfa](https://github.com/SirAllap/omarchy-solfa) by SirAllap (MIT). The entries below are Solfa's own history.

## 1.1.0

- New History tab (key `5`): what the account played lately, newest first, under Today / Yesterday / ... Signed out it says to sign in; Premium is not needed.
- Adverts are skipped by themselves: Solfa presses the Skip button every second until the advert is gone.
- New setting (off by default): with Brave as the engine's browser, let its ad blocker fetch its filter lists so it blocks adverts.
- Fixed: Settings > Browser for the engine offered Chrome, Brave and Vivaldi even when they were not installed; picking one left Solfa off with "no Chromium-family browser found". It now offers only the browsers it finds, and a missing one is named.
- Fixed: moving another widget in the bar (or anything else that makes the shell build Solfa's service again) stopped the song and brought it back 3 seconds later when the browser or the Brave ad-blocker setting was not the default. The new service judged the running engine against its own default settings, before the shell had handed over the real ones, and restarted it. It now waits for the settings, and a change of them restarts the engine once.
- Fixed: after the shell reloaded (a bar layout change), the engine could start in Chromium instead of the browser chosen in Settings, and the sign-in was lost (Chromium cannot read another browser's cookies). The shell no longer starts the engine on settings it has not received yet.
- Fixed: the engine now keeps to the browser its profile was built with. A start that is not told the browser takes it from the launch key, then from a `.solfa-browser` mark in the profile. Auto still picks the first installed browser. A start with no settings at all on an existing profile is not opened by a guess: Solfa says "waiting for the browser setting".

## 1.0.2

- Fixed: on a free (non-Premium) account every song stopped at 0:49 and Play did nothing.
- Fixed: Sign out could fail with "YouTube Music is not ready yet" while a song played.
- A fresh install starts off: nothing loads until you turn Solfa on.
- Adverts are clearly marked: a "This is an ad" badge with the time left, and a Skip ad button.
- Google's cookie question (asked in the EU) can be answered from the panel, with the reason it is asked.
- While signing in, Solfa's icon breathes in the bar and in the panel.

## 1.0.1

- Fixed: after the bridge restarted (a plugin update or a settings change), the panel could stay on "Starting Solfa" and never load. The shell now reconnects to the bridge whenever it comes back.
- After an update, if the shell still runs the old Solfa code, the panel now says to restart the shell (`omarchy-restart-shell`) instead of staying on "Starting Solfa".

## 1.0.0

- First release.
