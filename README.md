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
| General | **Graphics** | Sharpening at every render scale (on by default, toggle kept), and HDR output with sliders for your monitor's peak brightness, brightness and highlight factor. |
| Interface | **Micro Menu & Bags** | Micro menu and bag bar stay hidden until you hover their spot, then slide in from the screen edge. The bag bar becomes a single backpack button, styled like a micro menu button and lined up with it automatically. Positions stay in Blizzard's Edit Mode. |
| Interface | **XP & Reputation Bars** | Same hover reveal for the experience and reputation bars. Experience always stays in Status Bar 1, also while you track a reputation. |
| Interface | **Tooltip at Cursor** | Tooltips follow the mouse, just below and to the right of the cursor icon. Back to Blizzard's spot while you play with a controller. |
| Interface | **Tooltip Extras** | Class-coloured name, class line and border; level in difficulty colour; race and faction in faction colour; guild name in green (brighter for your own guild) with rank; talent spec and role (best guess from talent points); target line; mount and buffs (out of combat); item quality border and stack size. |
| Interface | **Nameplates** | Friendly players, NPCs and pets show only their name (class colour, NPC colours, pet blue) with the guild or NPC title under it. Enemy plates show cast bars with spell, icon and target, health as percentage (left) and value (right), as on the unit frames, and all your own debuffs. Quest mobs show your objective progress (8/10) in a box left of the health bar, including items they drop when Polestar is installed, plus a class-coloured dot for each group member who still needs the mob (their count shows once yours is done). Plates keep one size at any distance and when targeted. |
| Interface | **Best Quest Reward** | When a quest lets you choose a reward, the one that sells for the most (price × count) gets a gold coin, in the quest frame and the quest log. |
| Interface | **Movable Windows** | Drag Blizzard's windows by their empty space (snapping to the screen edges, other windows and an 8 px grid), scroll on the title bar to scale, right-click the title bar for 100%. Positions and scales are remembered. |
| Interface | **Controller Target Tooltip** | While you play with a controller, the tooltip of your target, or of what you aim at with soft targeting, stays in the default tooltip spot. Gone as soon as you touch the mouse or keyboard; works with the game's gamepad UI off. |
| Chat & Map | **Square Minimap** | Square map in the bronze frame of Forever's windows, zone in its title bar. FPS, clock (left-click calendar, right-click stopwatch) and mail inside the map; addon menu, tracking, calendar and coordinates appear on hover. Addon minimap buttons move into Blizzard's addon menu. Built-in gap to the screen edge; size and position stay in Edit Mode. |
| Gameplay | **Fishing** | One key (Key Bindings → KuroKit) casts and reels in; double right-click in the world casts too. While fishing the splash is loud, music and nameplates are off and the bobber is easy to target; everything comes back a few seconds after you stop. |
| Gameplay | **Flight Timer** | While on a flight path: origin, destination and time left at the top centre (just above the zone text), with the cast bar's look. Switches to the next stop when you use the game's land-early button. Recorded flight times (estimated from the route's length until you've flown it); the flight master's map shows each destination's flight time. |
| Gameplay | **Quick Loot** | Loot is taken instantly and the loot window stays out of sight unless something is left in it (bags full, a roll). Hold Shift while looting to see it as usual. |
| Gameplay | **Loot Feed** | Short-lived rows for items, money, reputation, currencies and skill ups you gain (repeats add up in one row), where the loot window appears: move "Loot Window" in Edit Mode to move it. |
| Interface | **Quest Tracker** | Tracked quests grouped by zone (current zone first, finished quests last), in Blizzard's tracker look at its Edit Mode spot. Right-aligned to the screen edge, no header. Click a zone to fold it; a quest button on the minimap (shown while hovering it, next to the calendar) hides or shows the tracker; left-click opens the quest as usual, right-click for untrack, share, abandon and a Wowhead link; quest item buttons, finished quests in green and the focused quest in bright white-gold (Focus is in the right-click menu), Spoken's Play button and quest timers. |
| Interface | **Unit Frames** | Blizzard's unit frames with players' health bars in class colour (raid-style frames via Blizzard's own option), health as value and percentage, and without portrait combat text, the resting glow and zzz (your level number turns blue while resting instead) and leader icons. |
| Interface | **Cast Bars** | Blizzard's cast bars with a soft drop shadow, outlined text and the time left; target and focus bars slightly larger; a latency zone at the end of your own casts. Your cast bar's size stays in Edit Mode. |
| Interface | **Unit Frame Skin** | Player, target, focus, pet, party and boss frames as one block (boss frames without a portrait): a square portrait beside taller health and mana bars, in one plate lined like Forever's nameplates (bronze; gold for elites, silver for rares), pixel-aligned. The level in the nameplates' level box. Blizzard's frames underneath, positioned in Edit Mode. |
| Interface | **Frame Fading** | Your player frame fades out of combat and shows while you have a target or hover its spot. The Cooldown Manager, when Edit Mode shows it in combat only, also shows with a target or on hover. |
| Gameplay | **Spell Uprank** | When you learn a higher rank of a spell, the lower ranks on your action bars are replaced by it (out of combat), with a line in chat. A lower rank you place on purpose afterwards stays. Pet abilities on your own bars follow your pet's ranks. |
| Chat & Map | **Minimal Chat** | Only the chat text shows: tabs, buttons and scroll bar appear while you hover the chat, no background, plain input line. The chat can sit right at the left screen edge (its buttons then move to the right). A copy button opens the chat text for copying. Timestamp format setting. |
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
- `/kk uprank`: replace every lower spell rank on your action bars now
- `/kk flighttimer test`: show a sample flight timer for 30 seconds
- `/kk windows reset [name]`: forget saved window positions and scales
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
