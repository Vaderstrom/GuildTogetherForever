# Guild Together Forever

Duels, dice, games, playful punishments, votes and the guild's story, inside the guild window.

A World of Warcraft addon for **WoW Forever**, for a whole **guild**. Guild Together adds a bar under the game's own guild
window, with a place for each part of guild life. Pick a place and its panel opens under the bar: the place's
features on the left, the list in the middle, and what you picked on the right.

Sister addon of [Journey Together Forever](https://github.com/Vaderstrom/JourneyTogetherForever), which is for a
fellowship that levels together.

## How it works
- **It lives in the guild window.** The bar shows on every tab of the game's guild window. Close the window and
  Guild Together closes with it. What the game already does (roster, notes, ranks, invites, the message of the day, the
  calendar's own sign-ups) stays in the game's window.
- **The Guild Master sets it up.** In Guild settings the Guild Master picks the features, the guild's currency, and
  which ranks may do what. Everyone else sees only the tools their rank may use.
- **One player is one player.** Your main and your alts are one player: your balance, debts, rating, sentences and
  votes follow you to every character.
- **The guild keeps it together.** Every member's addon shares what happens with the rest of the guild. What others
  did is as fresh as their last sync, and Guild Together says so ("as of 2 days ago").

## The places
### Home
What waits for you and what is going on in the guild. The guild's story: the weekly news, deeds, records, the
guild mascot (fed by every fish members catch) and memorials. A tour of Guild Together for your rank, and a setup guide
for the Guild Master.

### PvP Challenges
A duel ladder and the duel crown, Secret target, and tournaments with a pot. Bet on any match. Duels count from the
game's own duel results.

### Games
Guild events: Bingo, Hidden traitors, Survival race, Fishing contest, Treasure hunt, Transmog contest, Meet-up and
Gift exchange. Any event goes into the game's calendar with one press.

### Gambling
Deathrolls, high rolls and lotteries. Only the game's own `/roll` counts, and you play near each other.

### Treasury
Guild tax, debts and a long bank log that grows each time a member with the addon visits the guild bank. Bank
requests, and the guild's top donors.

### Professions
Who in the guild can make what, and crafting orders for what the guild needs made.

### Punishments
Playful, short punishments with bail and pardons: the Tomato Target, the Clown Hat, the Wheel of punishment,
Community service, the Walk of shame, Curses, Servant for an hour and Trial by combat. Only for players with
the addon, and never the Guild Master. The Guild Master picks which ones the guild uses and who may give them.

### Council
The guild's rules, polls and votes, a guild court, and strikes (real warnings, kept apart from the fun). Leadership:
an impeachment by the officers, a Mak'gora duel for the title, or a Guild Master tournament. Handing over the guild is
one press for the Guild Master.

### Calendar
Every event in one place: games, tournaments, votes, court cases and tax days.

### Guild settings
The Guild Master's setup: the features, the currency (gold or the guild's own Marks, with a name of the guild's
choice), the punishment rules, the tax and who may do what per rank.

## Gold or Marks
Guild Together never moves gold itself. With gold, a bet or a ticket becomes a debt that is paid by trade or mail, and
Guild Together marks it paid when the gold arrives. With Marks, the guild plays for points that only Guild Together keeps.
Betting real gold is the guild's own responsibility.

## Members without the addon
Members without the addon can still vote: they whisper `!vote 2` (or `!vote yes`) to a member who has it. They are
never punished, warned, charged, taxed or in debt.

## Discord
With [WoW Addon Webhooks for Discord](https://github.com/Vaderstrom/WoW-Addon-Webhooks-for-Discord), the guild's
news (sentences, champions, crowns, deeds and the weekly news) can be posted to the guild's Discord channels. One member,
the Herald, posts for the whole guild.

## Commands
- `/gtf` opens the guild's panel under the guild window.
- `/gtf tour` is a tour of Guild Together for your rank.
- `/gtf full` shows the guild across the whole screen, or back in the guild window.
- `/gtf options` are your own options: alerts, emotes, sounds and chat lines.
- `/gtf plain` gives back the game's own guild window, if it ever looks broken.
- `/gtf version` shows the addon's version.
- `/gtf test` runs the addon's self-test, then opens a demo guild to look around in (`/gtf test off` ends it).

## Status: beta
This is a beta. Guild Together Forever is built for WoW Forever and is tested on the retail client until Forever is public.
Everything above is checked with the addon's own self-test on retail, with one account. Tests with a real guild are
still to come. Everyone in the guild should use the same version.

Please report problems as GitHub issues, with a screenshot and the text of any Lua error
(`/console scriptErrors 1`). `CHANGELOG.md` lists what changed.

## Install
Install it with the CurseForge app, or download the zip from the latest GitHub release and unpack it into
`World of Warcraft/_retail_/Interface/AddOns/` (the folder must be called `GuildTogetherForever`). Restart the game fully after
installing or updating, then open the guild window.

## License and credits
MIT License, see `LICENSE`. Copyright (c) 2026 Vaderstrom.

Guild Together Forever is designed and developed by **Vaderstrom**. Claude, Anthropic's AI assistant, has assisted in its
development.
