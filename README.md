# SpellDamageInfo

<img width="974" height="303" alt="image" src="https://github.com/user-attachments/assets/53ce8d22-72de-412f-a048-e44b9a319e1d" />


A World of Warcraft addon for WoW: Forever and Classic Era. It puts the damage (or healing) of each spell on your action buttons and adds a line or two to the spell tooltip. The numbers come from the spell's own description, in English or German; an optional estimate adds your spell power by the Classic coefficient rules, and says so. Debuffs that lower the enemy's damage or attack power, such as Curse of Weakness or Demoralizing Shout, show the reduction in red ("-3", "-10%").

The pet bar shows the pet's spells too (the Imp's Firebolt, for example), with the numbers from the description only, since the pet has its own spell power.

**Install:** unzip `SpellDamageInfo-0.4.1.zip` into `Interface\AddOns` of your game folder (`_classic_beta_` for Forever, `_classic_era_` for Classic Era), then restart the game: a new addon folder is only picked up at start. Type `/sdi` (or open Options > AddOns > SpellDamageInfo) for the settings window, with a live preview of the numbers on a sample button; `/sdi help` lists the commands, such as the size (`/sdi size 50-200`) and place (`/sdi position bottom|center|top`) of the numbers.

Inspired by DrDamage by Gagorian. The options window is adapted from DoesItDie by Joe Greive (MIT). Licence: MIT (see `LICENSE`).
