# KuroKit

A personal all-in-one WoW addon. It replaces many feature-rich addons by reimplementing only the features the user actually uses. Claude writes all the code; the user tests in game and reports back.

## Target
- Client: **WoW Forever**, `C:\Games\World of Warcraft\_forever_` (flavor `wowf`), TOC `## Interface: 16001`.
- The API is modern (C_AddOns, C_Container, C_Timer, Settings, MenuUtil, TooltipDataProcessor and GetMouseFoci all exist), but Forever is new, so public wikis and retail docs may not match.
- **Primary API reference: Blizzard's own UI source for this client**, exported to `C:\Games\World of Warcraft\_forever_\BlizzardInterfaceCode\Interface\AddOns\` (exported 2026-11-21, 349 Blizzard addons).
  - `Blizzard_APIDocumentationGenerated/` holds the API signatures and events.
  - `*/Camelot/` subfolders hold Forever-specific overrides; check these first, they beat the Mainline versions.
  - Read the frame code before hooking anything. It goes stale after a game patch; ask the user to re-export (`-console` launch option, then `exportInterfaceFiles code` at the login screen).
- Secondary reference: how the installed Forever addons use an API (Polestar, Manners, EllesmereUI).
- The user plays with a **gamepad**. Any UI we add must work with gamepad navigation, or at least not get in its way.

## Layout
- `KuroKit/`: the addon itself. Junction-linked into `Interface\AddOns\KuroKit` by `tools\link.ps1`.
- `KuroKit/Core/`: framework (events, settings, modules, slash commands). Keep it small.
- `KuroKit/Modules/<Name>.lua`: one file per feature group, each made with `ns:NewModule`. Every module can be toggled per account or per character with `/kk on|off <Module> [char]`.
- `docs/`: feature inventory and design notes.

## Rules
- **Write original code.** Read other addons to learn how they do things (events, hooks, frames), then write our own version. Never copy code from them; several are "All Rights Reserved".
- No embedded libraries (Ace3 etc.) unless there's no reasonable alternative.
- **Performance is a requirement, not a polish step** (user's rule). Prefer events and hooks over polling. If polling is unavoidable, run it only while it's needed (e.g. only while a thing is visible) and throttle it. Allocate no tables in per-frame or per-tick code. Measure suspicious changes with Developer Tools → Frame spike finder (`/kk dev spikes`).
- Blizzard sometimes calls methods through references captured at load time (e.g. `EventRegistry` callbacks registered with `self.Layout`), which bypass `hooksecurefunc`. Check the callers in the exported code before relying on a hook alone.
- Respect combat lockdown: anything that touches protected frames goes through `ns:OutOfCombat(fn)`. Prefer `hooksecurefunc` over replacing Blizzard functions, to avoid taint.
- Turning a module off takes effect after `/reload`. Modules don't need to undo their hooks.
- After every change, run `tools\.venv\Scripts\python.exe -I tools\check.py`. It checks Lua 5.1 syntax and TOC/file consistency, and scans the bytecode for accidental global writes and suspicious global reads (out-of-scope locals). New intentional globals go in its `ALLOWED_WRITES` / `ALLOWED_READS`.
- KuroKit errors print in chat once (`ns.OnError`), because the user normally has Lua error popups off. Wrap anything that runs outside `ns:On` handlers (OnUpdate scripts, button clicks) in `ns.safecall`. A new file must also be added to the `.toc`. On this client `/reload` picks up edits *and* new files listed in the TOC (verified 2026-11-21). Some TOC header fields (e.g. AddonCompartmentFunc) may still need a full restart.
- Settings are **account-wide only** (one `KuroKitDB`, no per-character profiles), per the user.
- Every user-facing setting goes in the module's `options` list (`Core/Options.lua`). Don't add slash-command-only settings; slash commands are for diagnostics.
  - The settings page is one canvas page with **tabs by group** (General, Interface, Chat & Map, Gameplay, Developer). Each module sets `group`; empty groups are hidden. Each module shows as a section with an on/off checkbox in front of its title; `alwaysOn = true` hides that checkbox.
  - Options that need a reload get `reload = true`; the page then shows a reload bar.
  - The page is built on first open, from Blizzard templates (MinimalTab, SettingsCheckbox, WowStyle1Dropdown, MinimalSliderWithSteppers).
- Model "on/off + how" settings as a single dropdown. If a greyed-out child row is really needed, use `AddModifyPredicate` + `AddEvaluateStateCVar(parentVariable)`, never `SetParentInitializer` (it taints the search box). See the comment in `Core/Options.lua`.

## Design direction (decided with the user)
- Stay fully compatible with Blizzard's **Edit Mode**. Never add our own mover or edit mode for HUD elements.
- Keep the default look; tweak default frames in place (BetterBlizzFrames/BetterBlizzPlates style). No replacement unit frames, bars or nameplates.
- Keyboard + mouse first. Gamepad should keep working, but doesn't drive the design.
- Build feature by feature, in the order in `docs/FEATURES.md`. The user tests each step in game.

## Keep as separate addons (don't absorb)
Baganator (+Syndicator), GamepadSuite, Manners, DialogueUI, Spoken*, Polestar*, TalentsForeverBook, SmartHeal, Auctionator.

## Reference code
Other addons' source, kept outside this repo and never loaded in game: the installed addons in `Interface\AddOns`, plus downloads in `..\wow-addon-refs\` (next to this repo). Treat it as reading material only; don't run anything from there.
