# KuroKit

A small all-in-one addon for **World of Warcraft: Forever**. It replaces a pile of feature-rich addons with just the handful of features actually used, written from scratch. It works with Blizzard's default UI and Edit Mode rather than replacing them.

> Personal project, early days. Built for the Forever client (interface 16001); other WoW versions aren't supported.
>
> Deliberately opinionated: each feature does one thing the way I like it, with an on/off switch and almost no other settings.

## Features

| Tab | Feature | What it does |
|---|---|---|
| General | **Repair & Sell Greys** | At a merchant: repair everything (guild funds first, or own gold) and sell grey items, retrying until the server has taken them all. |
| General | **Hide Error Spam** | Hides the red cooldown / resource / range / target errors. Useful ones (bags full, quest log full) still show. |
| General | **Follow Default Audio Device** | Game sound follows Windows' default output device (headset on/off), instead of staying on the device the game started with. |
| General | **Graphics** | Sharpening at every render scale (on by default, toggle kept). |
| Interface | **Micro Menu & Bags** | Micro menu and bag bar stay hidden until you hover their spot, then slide in from the screen edge. The bag bar becomes a single backpack button, styled like a micro menu button and lined up with it automatically. Positions stay in Blizzard's Edit Mode. |
| Interface | **XP & Reputation Bars** | Same hover reveal for the experience and reputation bars. Experience always stays in Status Bar 1, also while you track a reputation. |
| Interface | **Tooltip at Cursor** | Tooltips follow the mouse, just below and to the right of the cursor icon. Back to Blizzard's spot while you play with a controller. |
| Interface | **Tooltip Extras** | Class-coloured name, class line and border; level in difficulty colour; race and faction in faction colour; guild name in green (brighter for your own guild) with rank; talent spec and role (best guess from talent points); target line; mount and buffs (out of combat); item quality border and stack size. |
| Interface | **Controller Target Tooltip** | While you play with a controller, the tooltip of your target, or of what you aim at with soft targeting, stays in the default tooltip spot. Gone as soon as you touch the mouse or keyboard; works with the game's gamepad UI off. |
| Chat & Map | **Square Minimap** | Square map in the bronze frame of Forever's windows, zone in its title bar. FPS, clock (left-click calendar, right-click stopwatch) and mail inside the map; addon menu, tracking, calendar and coordinates appear on hover. Addon minimap buttons move into Blizzard's addon menu. Built-in gap to the screen edge; size and position stay in Edit Mode. |
| Gameplay | **Fishing** | One key (Key Bindings → KuroKit) casts and reels in; double right-click in the world casts too. While fishing the splash is loud, music and nameplates are off and the bobber is easy to target; everything comes back a few seconds after you stop. |
| Chat & Map | **Minimal Chat** | Only the chat text shows: tabs, buttons and scroll bar appear while you hover the chat, no background, plain input line. The chat can sit right at the left screen edge (its buttons then move to the right). Timestamp format setting. |
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
- `/kk targettooltip`: controller detection and aim state (diagnostics)
- `/kk fishing debug`: explain double right-clicks that don't cast
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
