# SpellDamageInfo

<img width="974" height="303" alt="image" src="https://github.com/user-attachments/assets/53ce8d22-72de-412f-a048-e44b9a319e1d" />


A World of Warcraft addon for WoW: Forever, Classic Era and Retail. It puts the damage (or healing) of each spell on your action buttons and adds a line or two to the spell tooltip. The numbers come from the spell's own description, in English or German, whichever each text is in; an optional estimate adds your spell power, at the share the game's own spell data gives each spell on WoW: Forever and Classic Era (Classic's coefficient rules for a spell the data does not cover), and says so. Debuffs that lower the enemy's damage or attack power, such as Curse of Weakness or Demoralizing Shout, show the reduction in red ("-3", "-10%").

Abilities that hit with your weapon (Heroic Strike, Maul, Claw, Shred, Sinister Strike, Aimed Shot and the like) show their potential damage in blue: your weapon's average hit, times the ability's percentage, plus its bonus. Spells that raise attack power (Battle Shout, Rockbiter Weapon, Blessing of Might, Seal of the Crusader, Bear and Cat Form, Aspect of the Hawk) show what they add to each hit, as "+103". Both are estimates from your weapon's numbers, read out of combat, and the tooltip says so; `/sdi weapon off` turns them off. `/sdi misses` lists the spells on your bars that give no number, which is the list to send when something is missing.

Seals show what they add to every hit (Seal of Righteousness and Flametongue Weapon, whose texts give a range for all weapon speeds, at your weapon's speed), and Judgement shows the damage of the seal that is active. Effects that trigger by chance (Windfury, Seal of Command, Seal of Light, poisons, Frostbrand) show what one trigger does, and the tooltip gives the chance. Shields show what they absorb (in purple), finishers their damage at five combo points with the other points in the tooltip, and totems, Lay on Hands, Execute and Mana Burn what their descriptions work out to (a totem's or trap's number gets no spell power estimate: it is the totem's own spell, which the data does not name). `/sdi dump` writes your spellbook's descriptions, as your client shows them, to the saved variables, for testing; `/sdi dump all` does the same for every class's abilities.

The pet bar shows the pet's spells too (the Imp's Firebolt, for example), with the numbers from the description only, since the pet has its own spell power.

On Retail, whose descriptions already include your stats, the numbers are the descriptions' own: the spell power estimate and the weapon arithmetic are off there.

The addon's interface language (labels, chat messages, number formatting) can be switched independently of the game language via the settings window or `/sdi lang auto|en|de`. Auto follows the game's language.

**Install:** unzip `SpellDamageInfo-0.7.3.zip` into `Interface\AddOns` of your game folder (`_classic_beta_` for Forever, `_classic_era_` for Classic Era, `_retail_` for Retail), then restart the game: a new addon folder is only picked up at start. Type `/sdi` (or open Options > AddOns > SpellDamageInfo) for the settings window, with a live preview of the numbers on a sample button; `/sdi help` lists the commands, such as the size (`/sdi size 50-200`) and place (`/sdi position bottom|center|top`) of the numbers.

Inspired by DrDamage by Gagorian. The options window is adapted from DoesItDie by Joe Greive (MIT). Licence: MIT (see `LICENSE`).
