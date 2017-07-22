# AutoGear

AutoGear is a World Of Warcraft addon that automatically rolls on and equips loot according to stat weights like WoWhead filters. AutoGear rolls "need" on upgrades and "greed" otherwise.

AutoGear also optionally interacts with quest NPCs, automatically accepting and completing quests, including deciding the best quest reward based on the same stat weights. If no item is deemed to be an upgrade, the item worth the most vendor gold is chosen.

Included in AutoGear are default stat weights for all specs of all classes. Using these weights, AutoGear will roll "need" on better loot and equip it for you when it can.

Stat weights work like the advanced filter on WoWhead. For example, if you specify that 1 point of strength is worth 1 point and 1 point of crit is worth 0.5 points, an item with 5 strength and 3 crit will be worth 6.5 points. That item might then replace an item in the same slot with 3 strength and 2 crit, worth 4 points. If the first item was presented in a loot roll, AutoGear would roll "need" and if you won the roll, it would equip the new item as soon as it could.

The default stat weights may not be what you prefer. If you want to change them, stat weights for all classes and specs can be found in the "SetStatWeights()" function in "[wow]\Interface\AddOns\AutoGear\AutoGear.lua". Simply edit the numbers there, save the file, and type "/run ReloadUI()" to update. A GUI for setting stat weights would be nice, but the authors haven't been motivated to make one yet. Code patches are welcome. This includes improvements to AutoGear's current stat weights, which sometimes need updating due to WoW class balance changes.

If you receive an upgrade mid-combat, AutoGear queues the upgrade to be equipped when combat ends. It used to equip weapon upgrades immediately because weapons could be changed in combat, but due to addons that automated weapon swaps in combat for DPS at maximum level, Blizzard now prevents addons from swapping weapons in combat automatically. You can still equip them manually earlier than AutoGear can if you notice you've received a weapon upgrade.

Chat commands:
```
/ag - options menu
/ag scan - manually run automatic gearing once (scan all bags for better gear)
/ag toggle/[enable/on/start]/[disable/off/stop] - toggle automatic gearing
/ag quest [enable/on/start]/[disable/off/stop] - toggle quest handling
/ag party [enable/on/start]/[disable/off/stop] - toggle automatic acceptance of party invitations
```

Warning: AutoGear currently automatically rolls "greed" on everything that isn't a gear upgrade for the current spec, including mounts and crafting reagents. It works quite well for leveling quickly and conveniently, but you should disable it before loot rolls you want control over. To do so, simply run "/ag toggle" or toggle it from the options menu.

Warning: AutoGear is not recommended for use at max level. Its weights are not optimal, nor are stat weights ideal for determining upgrades in end-game content. AutoGear is meant primarily as a convenience for leveling quickly. Using it at max level, especially in team PvE or PvP, is likely to get you kicked from various groups and guilds. Calculating proper upgrades using SimulationCraft is preferable. This will be very time-consuming, but worth it for your powerful max-level character.
