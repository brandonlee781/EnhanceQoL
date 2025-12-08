# Changelog

## [6.2.0] – 2025-12-03

### Important note

Changing minimap Button behaviour

- Leftclick now opens the new option menu
- Rightclick has an option to open the old Legacy Settings until midnight comes out (Legacy will likely be gone in midnight)

### ✨ Added

- Shortening per _Currency_ in _Currency Stream_ added
- Hide border and/or background of _Button Sink_
- Scaling, width, height of Reputation and XP-Bar implemented
- World Marker Cycle
  - Set a keybind to cycle through all world markers
  - Set another keybind to clear all world markers
- Hide Action Button borders
- Action Bars: Fade amount slider to control how transparent mouseover-hidden bars become (applies to pet/stance bars too)
- Square minimap: new layout re-anchor option (on by default) to reposition minimap, zoom buttons, addon compartment, and difficulty indicator for the square shape
- Action Bars: Option to hide the Assisted Combat Rotation overlay/glow on buttons
- Automatically open the preview for player housing items
- _Cypher of Relocation_ and two Warlords teleports that were missing
- 4 Borders, 4 Statusbar textures to sharedmedia
- Cooldown Manager: per-viewer "Show when" multi-select (in combat, while mounted/not mounted, on mouseover) for Essential/Utility/Buff Bar/Buff Icon cooldown viewers, with edit-mode-friendly fading
- Minimap Button Sink: configurable flyout direction (auto or specific edge/corner) with screen-safe fallback
- Unit Frames (Player/Target/ToT/Pet/Focus/Boss)
  - Custom frames with Edit Mode controls for size, strata/level, borders, health/power bars (colors, fonts, textures, text formats), cast bars, and status line options
  - Target auras get anchor/offset controls and an optional separate debuff anchor; boss frames have container anchor, growth, and spacing
  - New “Settings” group adds a copy dropdown + confirmation popup to duplicate another frame’s settings while keeping your current position/enable state

### 🔄 Changed

- _Show leader icon on raid style party frames_ now also shows leader and assist in raids
  Changed everything which will be part of midnight to the Blizzard Option menu

### ❌ Removed

- Old libraries

### 🐛 Fixed

- _Enhance Ignore List_ Strata was to high
- Range coloring on action bars now clears correctly when your bar switches (mounts/stance/override)

---

## [6.1.0] – 2025-11-20

### ✨ Added

- Actionbar and Frame fading if you choose to hide it
- PlayerFrame
  - Show when I target something
  - New visibility rule: “Always hide in party/raid” (overrides other rules while grouped; mouseover can still reveal)
- Quest Tracker
  - Optional quest counter beneath the tracker header, showing `current/max` with configurable offsets
- Resource Bars
  - Optional auto-hide while mounted or inside vehicles, reacting instantly to mounting/vehicle events
- Sync the width of your resource bars with the relative frame
- Missing Mythic Keystone id for Keystone helper

### ⏰ Temporarily disabled

- Show Party frame in solo content, this break in group content with secrets in midnight beta

### ❌ Removed

- Hide raid frame buffs (something changed as this now throws error in retail too)

### 🐛 Fixed

- Error: attempt to perform indexed assignment on field 'moneyTracker'
- Guard against ChatIM and Ignore feature in restricted content (Raid/M+) for midnight because of secret values
- Resource Bars: Druid form-specific visibility now uses a secure state driver (no more tug-of-war with the hide rules), and disabling all visibility rules no longer forces redundant bar rebuilds
- Resource Bars: The module now fully unregisters its visibility drivers when turned off, and “Hide while mounted” also suppresses bars in Travel/Stag form for Druids
- BR Tracker working in m+/raid now
- World Map Dungeon Teleports fixed in m+/raid
- Resource Bars: Health bar now has absorb configuration (enable/disable, custom color, custom texture, sample preview)

---

## [6.0.0] – 2025-11-15

## Midnight Beta – Addon Status

Because of Blizzard’s new addon API restrictions in **Midnight**, some EQoL features have to behave differently in combat than before.  
Here’s what currently works, what’s limited, and what’s turned off in the Midnight beta.

### ✨ Added

- Dungeon teleports and talent reminder for midnight dungeon
- **Visibility Hub** (UI → Action Bar) lets you pick any Blizzard action bar or frame, then mix-and-match mouseover, combat, and the new “Player health below 100%” triggers with a single dropdown workflow. Action bars still expose their anchor/keybind extras when selected.
- Action bars gained a dedicated “While skyriding” visibility rule so you can force a bar (e.g., Action Bar 1) to appear when using Skyriding/Dragonriding abilities.
- Legion Remix achievements can now list their reward items directly in the missing-items tooltip, complete with item-quality coloring.
- Resource Bars can now anchor to the Essential/Utility cooldown viewers, both buff trackers, and all default Blizzard action bars (Main + MultiBars) for tighter layouts without custom macros.
- Health bars gained a “Use class color” toggle alongside the existing custom-color controls so you can instantly match your class tint without extra configuration.
- Resource Bars now have an optional “Hide out of combat” toggle that drives the frame visibility via a secure state driver, so the bars stay hidden without tripping combat lockdown.
- Adjust the columns per row in **Button Sink**

### 🔄 Changed

- **Aura Tracker**
  - In **combat**, almost all auras are now “hidden” from addons by Blizzard.  
    → Practically **no auras can be iterated in combat** anymore.  
    → Aura checks and updates happen **after combat**, when the restrictions are lifted.
  - **Out of combat**, new auras are scanned and displayed as usual.
  - **Resource bars**
    - Fully **Midnight-compatible**.
- Unit frame visibility now uses the same scenario model as action bars, enabling multiple states per frame while keeping legacy “always hide” support.
- Health-triggered frame fades only register the relevant unit events when a frame actually uses that rule, and updates are throttled to avoid `UNIT_HEALTH_FREQUENT` spam.

### ⏰ Temporarily disabled

These features are turned off **only for the Midnight beta** until there’s a safe way to re-implement them:

- **Tooltip enhancements**
  - Actually all stuff doing anything like adding data to the tooltip is disabled, as of a bug in midnight beta
- **Buff hiding on raid frames** in Midnight beta (disabled until a working solution is found)
- **Vendor module** tooltip information
- Changing the **max color** for power/resource bars
- The **“Smooth bars”** option is temporarily disabled. Blizzard is adding a built-in smoothing feature, which EQoL will use once it’s available.
- Account money frame feature (due to tooltip-handling bugs)

### ❌ Removed (Midnight beta)

These features are currently removed in the Midnight beta because of API changes or bugs:

- **Inventory**
  - Cloak Upgrade button (Midnight beta only)
- **Module:** `CombatMeter`
- **Mythic+ features**
  - Auto-marking tank and healer (now requires hardware events / secure input)
  - Potion tracker
- **Aura-based features**
  - Cast tracker
  - Cooldown notify

### 💡 Side note

- The **trinket cooldown tracking** inside **_Aura Tracker_** still works.

### 🐛 Fixed

- Nameplate **health percentage / absolute values** corrected for Midnight beta
- Tooltip error when hovering items with the **ignore list** enabled
- Player frame now correctly shown at **100% health** in Midnight beta
- Boss frames are now **targetable** again when changing visibility behaviour
- Error when hovering the **EQoL options menu** fixed
- Removed `UNIT_HEALTH_FREQUENT` (API is deprecated)
- Context menu checks for **NPC ID** hardened to avoid errors
- Health macro combat checks moved into **protected** logic
- **Healthbar colors** no longer sometimes display the wrong color
- Keybind shortening leads to invisible text
