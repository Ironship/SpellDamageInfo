# SpellDamageInfo

<img width="974" height="303" alt="image" src="https://github.com/user-attachments/assets/53ce8d22-72de-412f-a048-e44b9a319e1d" />


A World of Warcraft addon for WoW: Forever and Classic Era. It puts the damage (or healing) of each spell on your action buttons and adds a line or two to the spell tooltip. The numbers come from the spell's own description, in English or German; an optional estimate adds your spell power by the Classic coefficient rules, and says so. Debuffs that lower the enemy's damage or attack power, such as Curse of Weakness or Demoralizing Shout, show the reduction in red ("-3", "-10%").

Abilities that hit with your weapon (Heroic Strike, Maul, Claw, Shred, Sinister Strike, Aimed Shot and the like) show their potential damage in blue: your weapon's average hit, times the ability's percentage, plus its bonus. Spells that raise attack power (Battle Shout, Rockbiter Weapon, Blessing of Might, Bear and Cat Form, Aspect of the Hawk) show what they add to each hit, as "+103". Both are estimates from your weapon's numbers, read out of combat, and the tooltip says so; `/sdi weapon off` turns them off. `/sdi misses` lists the spells on your bars that give no number, which is the list to send when something is missing.

The pet bar shows the pet's spells too (the Imp's Firebolt, for example), with the numbers from the description only, since the pet has its own spell power.

The addon's interface language (labels, chat messages, number formatting) can be switched independently of the game language via the settings window or `/sdi lang auto|en|de`. Auto follows the game's language.

**Install:** unzip `SpellDamageInfo-0.5.0.zip` into `Interface\AddOns` of your game folder (`_classic_beta_` for Forever, `_classic_era_` for Classic Era), then restart the game: a new addon folder is only picked up at start. Type `/sdi` (or open Options > AddOns > SpellDamageInfo) for the settings window, with a live preview of the numbers on a sample button; `/sdi help` lists the commands, such as the size (`/sdi size 50-200`) and place (`/sdi position bottom|center|top`) of the numbers.

Inspired by DrDamage by Gagorian. The options window is adapted from DoesItDie by Joe Greive (MIT). Licence: MIT (see `LICENSE`).
