# Alucard (MLBB) - Kit Specification

Values come from Mobile Legends Fandom / Liquipedia search extracts plus mlbb.io, mlbb.tools and guide sites (direct Fandom/Liquipedia fetch was blocked). "unknown" = not found. "disputed" = sources disagree.

## Hero overview
- Role / lane: Fighter / Assassin, jungle (EXP lane also common). Melee.
- Resource: none (0 mana); skills have no mana cost.
- Basic attack: melee single target. After any skill cast, the next basic attack becomes a dash (Pursuit).
- Attack range: disputed. Search extracts gave 1.8 for most melee heroes; one extract listed a stray value of 4 (likely the Malefic Gun passive range bonus, not a base value). Treat as 1.8 (low confidence).
- Base stats at level 1 (Fandom / mlbb.io): HP 2443, regen 7.8, physical attack 123, physical defense 21, magic defense 15, attack speed 1.13, movement speed 260.
- Growth per level: HP +225, regen +0.44, phys attack +8.64, phys defense +4.6429, magic defense +2.5, attack speed +0.0293 (level 15: HP 5593, attack 244, phys def 86, attack speed 1.54).
- Disputed (mlbb.tools): HP 2621, regen 7.8, phys attack 126, phys defense 20, magic defense 10, attack speed 0.88. Prefer Fandom/mlbb.io.
- Max skill levels: S1 6, S2 6, Ultimate 3.

## Passive - Pursuit
- Cast type: passive, enhances next basic attack.
- After each skill cast, Alucard's next basic attack dashes to the target's location and deals physical damage equal to 140% Total Physical Attack (mlbb.io, oneesports-style). Disputed: mlbb.tools lists 125% (older value). Deals 110% damage to creeps (mlbb.tools only).
- Window for using the empowered attack, dash range, passive cooldown: unknown.

## Skill 1 - Groundsplitter
- Cast type: ground-targeted leap/roll (dash to target area) with AoE slam.
- Effect: rolls to the target location and slams his blade, dealing 270 (+85% Extra Physical Attack) physical damage to enemies hit and slowing them by 40% for 2 s. Scaling coefficient disputed: +80% in one extract, +85% in the Fandom text.
- Cooldown by level: 8.5 s at level 1 down to 6.5 s at level 6 (intermediate steps = unknown).
- Base damage: 270 at level 1 up to 370 at level 6.
- Cast range, radius: unknown. Cost: none.

## Skill 2 - Whirling Smash
- Cast type: self-centered AoE spin/slash (no aim).
- Effect: launches a whirling slash dealing 345 (+120% Extra Physical Attack) physical damage to nearby enemies.
- Cooldown: 6.0 s at level 1 down to 4.0 s at level 6.
- Base damage: 345 at level 1 up to 570 at level 6.
- Radius: unknown. Cost: none.

## Ultimate - Fission Wave
- Cast type: ground-targeted AoE (absorb) then recast directional skillshot.
- Passive part: permanent Hybrid Lifesteal. Level values disputed: 10% (all levels) per Fandom-style text vs 10% / 20% / 30% by level in another extract.
- Active: absorbs the energy of enemies in the target area, reducing their movement speed by 30% and Hybrid Defense by 10. Alucard gains Hybrid Defense (10) for each enemy hero hit, and reduces the cooldown of his other skills to 50% for 6 s.
- Recast (Use Again): releases a shockwave in the target direction dealing 400 (+200% Extra Physical Attack) physical damage to enemies hit. Recast window length, shockwave range/width: unknown.
- Cooldown by level: 40 / 35 / 30 s (level 2 = 35 from one extract; endpoints 40 and 30 agreed).
- Base damage: 400 / 550 / 700. Cost: none.
- Slow/defense-debuff duration: unknown.

## Gameplay identity
- Skirmisher/lifesteal brawler: skill, then dash-basic-attack, chaining mobility and damage.
- Gap-closer via Groundsplitter plus Pursuit dash gives constant re-engagement.
- Ultimate halves other cooldowns for 6 s, enabling skill-spam burst windows; lifesteal is permanent.
- Rewards multi-skill rotations instead of waiting on cooldowns; no mana to manage.

## Simulation notes
- Standard: ground-target leap with slow, self AoE, skillshot recast, flat/percent lifesteal, defense debuff, movement slow.
- Needs special state: "next basic attack dashes" flag set by any skill cast (with dash); ultimate recast window and timed cooldown-rate modifier (other skills at 50% cooldown for 6 s); per-hit hero-count scaling of gained defense; permanent hybrid lifesteal attribute scaling with ult level.

## Sources
- https://mobile-legends.fandom.com/wiki/Alucard (via search extract)
- https://liquipedia.net/mobilelegends/Alucard (via search extract)
- https://mlbb.io/en/hero/alucard
- https://mlbb.tools/heroes/alucard
- https://www.oneesports.gg/mobile-legends/alucard-best-build-guide/
- https://mobile-legends.fandom.com/wiki/Hybrid_Lifesteal
