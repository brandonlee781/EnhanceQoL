# Enhance QoL – Small Tweaks & UI Improvements for World of Warcraft

A modular collection of tiny quality-of-life fixes and UI polish.  
Every feature can be switched off; footprint is negligible.

***

## Slash Commands

| Command          |Action                                           |
| ---------------- |------------------------------------------------ |
| <code>/eqol</code> |Open the configuration window                    |
| <code>/eqol resetframe</code> |Re-center all Enhance QoL windows                |
| <code>/eqol lag</code> |List gossip IDs of the current NPC dialog        |
| <code>/eqol aag &lt;id&gt;</code> |Auto-pick a gossip option (chosen via <code>/eqol lag</code>) |
| <code>/eqol rag &lt;id&gt;</code> |Remove an auto-picked gossip ID                  |

***

## Supported Languages

English • German • French • Spanish • Italian • Russian • Korean • zhCN • zhTW • ptBR

***

## Feature Set

### Bags & Inventory

*   Show item level, gems, enchants and durability on bag icons (bank optional).
*   Flexible **Bag Filter Window** – filter by slot, rarity, spec-usable, expansion, upgrade track, vendor-sellable, auction-house-sellable, binding type or custom item-level range.
*   Use `/way` to drop a map pin from the Bag Filter search.
*   Hideable Bag Bar (mouse-over).
*   Money tracker – total gold for all characters in one tooltip.
*   Alt-inventory cache – counts how many of each item your alts own.

### Character & Inspect

*   Item level, gems and enchants displayed in the Character Frame.
*   Extra info in the Inspect Frame (experimental).

### Action Bars & Mouse

*   Mouse-over action bars.
*   Optional full button range coloring.
*   Customisable mouse ring and mouse trail for better cursor visibility.
*   Choose separate fonts, sizes, and outlines for macro names and keybind text.
*   Per-bar keybind visibility plus optional shorthand labels (e.g., `SM3` for Shift + Mouse Button 3).

### Group & Raid Tools

*   **Auto Marker** – mark the tank on dungeon entry; removes the marker from yourself when you switch to healer spec.
*   Leader-crown icon in compact party frames.
*   Auto-accept invites (friends / guild only if desired).
*   Option to show the party frame even when solo.

### Dungeon / Mythic Plus

*   Quick-signup in the LFG browser; sort applicants by Raider.IO score.
*   Keystone helper: auto-insert keystone, ready-check & pull timer (DBM/BigWigs compatible), auto-start on zero.
*   Keystone helper UI options: polished design with animated status icon or revert to the legacy layout.
*   Objective-Tracker Auto-Hide when a Mythic+ key starts.
*   Talent loadout reminders per dungeon.
*   Combat-rez tracker and party keystone list.
*   Extended dungeon filter (Bloodlust, Battle Res, role fit, spec duplicates).

### Teleports & Travel

*   Teleport Frame with cooldowns, portals, class & engineering teleports, toys, etc.
*   "Teleport Compendium" tab inside the PVE frame.
*   Right-click portals to mark them as favourites – favourites show at the top and can bypass hide options when **Always show favorites from hidden expansions** and **Always show favorite teleports regardless of filters** are enabled.

### Quest & Vendor Automation

*   Auto-accept/turn-in quests with daily/weekly/trivial/NPC excludes.
*   Auto-repair and smart junk-sell (rarity & ilvl threshold, drag-and-drop whitelist/blacklist).
*   "DELETE" confirmation text on item destroys.

### Tooltip Control

Fully configurable per context (combat, dungeon, friendly/enemy): items, item counts & IDs, spell IDs, NPC IDs, Mythic+ score, class colours and more.

### UI Tweaks & Extras

*   Hideable Target Frame, Micro Menu (fade in on mouse-over).
*   Profession-quality icon fade while searching.
*   Quick-loot mode (disable Blizzard auto-loot for best speed).
*   Custom loot toasts with item-level thresholds, mount/pet filtering,
    include list and optional sound.
*   Option to hide Raid Tools in party play.
*   Disable Talking Head frame, plus other minor class-specific bar tweaks.

* **Enhanced Ignore List** – organise ignored players in a searchable window, highlight them in group finder and block unwanted requests. Toggle with `/eil`.
* **Instant Messenger** – mini whisper window with tabs, message history and optional fade. Toggle with `/eim`.
* **Gem-Socket Helper** – shows socketable gems below the socket UI.
* **Aura Tracker** – track buffs and debuffs in custom categories. Categories can be exported and imported for easy sharing.

# DataPanels & Streams

DataPanels display information supplied by registered streams and can be configured through the in-game interface.

### Creating external streams

1. Copy <code>Streams/Template.lua</code> to a new file.
2. Fill in the required provider fields and implement <code>collect</code>.
3. Register the stream with <code>EnhanceQoL.DataHub.RegisterStream</code> during addon load.
4. Optionally add filters, actions or settings.
5. Add the stream to a DataPanel through the DataPanel configuration interface.

For more details, see [docs/Streams.md](docs/Streams.md).

# Help
For a full list of configuration checkboxes see [docs/OptionsReference.md](docs/OptionsReference.md).
