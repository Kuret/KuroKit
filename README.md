# KuroKit

A small all-in-one addon for **World of Warcraft: Forever**. It replaces a pile of feature-rich addons with just the handful of features actually used, written from scratch. It works with Blizzard's default UI and Edit Mode rather than replacing them.

> Personal project, early days. Built for the Forever client (interface 16001); other WoW versions aren't supported.

## Features

| Tab | Feature | What it does |
|---|---|---|
| General | **Repair & Sell Greys** | At a merchant: repair everything (guild funds first, or own gold) and sell grey items, retrying until the server has taken them all. |
| General | **Hide Error Spam** | Hides the red cooldown / resource / range / target errors. Useful ones (bags full, quest log full) still show. |
| General | **Follow Default Audio Device** | Game sound follows Windows' default output device (headset on/off), instead of staying on the device the game started with. |
| General | **Graphics** | Always-on sharpening toggle. |
| Interface | **Micro Menu & Bags** | Micro menu and bag bar stay hidden until you hover their spot, then slide in from the screen edge. Optional single bag button styled like a micro menu button and lined up with it automatically. Positions stay in Blizzard's Edit Mode. |
| Interface | **Tooltip at Cursor** | Tooltips follow the mouse at a chosen side, clear of the cursor icon (and of the unit health bar). |
| Developer | **Developer Tools** | `/rl` to reload, Lua error popups toggle, and a frame spike finder. |

Everything is configured in **Settings → AddOns → KuroKit** (or `/kk`, or the minimap's addon menu). Settings are shared by all characters.

## Install (manual)

1. Download `KuroKit-vX.Y.Z.zip` from the [Releases](../../releases) page.
2. Extract it into `World of Warcraft\_forever_\Interface\AddOns\`, so you end up with `...\AddOns\KuroKit\KuroKit.toc`.
3. Restart the game (or `/reload` if it was already running) and make sure KuroKit is enabled in the addon list.

## Commands

- `/kk`: open the settings
- `/kk list`: features and whether they're on, in chat
- `/kk errors`: which error types are hidden (diagnostics)
- `/kk dev spikes [seconds]`: frame spike finder
- `/rl`: reload the UI

## Development

```powershell
pwsh tools\link.ps1                                  # junction the addon into Interface\AddOns (once)
python -m venv tools\.venv; tools\.venv\Scripts\pip install lupa
tools\.venv\Scripts\python.exe -I tools\check.py     # Lua 5.1 syntax, TOC and globals check
```

Edit, run the check, then `/rl` in game. `CLAUDE.md` describes the conventions (Edit Mode compatibility, taint rules, performance rules).

## License

MIT, see [LICENSE](LICENSE).
