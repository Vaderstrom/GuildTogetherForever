# Changelog

## 0.1.0 beta (1 November 2026)
The first beta, for WoW Forever (tested on the retail client until Forever is out).
- A bar under the game's guild window, with a place for each part of guild life: Home, PvP Challenges, Games,
  Gambling, Treasury, Professions, Punishments, Council and Calendar, and Guild settings for the Guild Master.
- Duels, the duel crown, tournaments and bets; deathrolls, high rolls and lotteries; guild events; playful
  punishments; rules, polls, votes and a guild court; guild tax and the bank log; the guild's story, with the weekly
  news and the mascot.
- Play for gold or the guild's own Marks. Members without the addon can still vote by whisper.
- `/gtf` opens the panel; `/gtf tour` shows you around.

## Before the beta
- **The name: Guild Together Forever** (SPEC decision 77), Guild Together for short in the game, and the chat command
  `/gtf`. CurseForge already has an addon called GuildPlus, the name used from 30 October. The addon folder and files
  are `GuildTogetherForever` and `GuildTogetherForever-Dev`, the saved data `GuildTogetherForeverDB`
  (`tools/move-saved-data.ps1` copies the GuildPlus saved files over), and addon messages use the prefix `GTF`. New
  folder and files: restart the game.
- **Face to face** (SPEC decision 72): a deathroll, a high roll, a bet on a duel, Bingo, a lottery ticket and the
  transmog contest (entering and voting) need you near the other player: in your group and close by, or your target.
  Far away, the button is greyed and says who to go near; walking away after a game started does not stop it. Players
  in these games are drawn as their characters while near, else as their class icon.
- **Getting started**: a tour of Guild Together for your rank (Show me around), on a sample guild that is never saved or
  sent. Offered the first time you open Guild Together and when your rank goes up; again from Home, Your options or
  `/gtf tour`. The Guild Master's tour starts with a setup guide on their own guild. Home's Getting started card
  now has setup steps that tick themselves (the rules accepted, your options; for the Guild Master the setup, the
  Marks, the tax, the powers and the features).
- **Scenes and pages** (SPEC decision 73): the lottery's drum with everyone's tickets; seals on a scroll while an
  impeachment is voted; the entrants at the arena's gate while a tournament signs up; the rules written on the
  parchment with a seal for each member who accepted; a picture of your screen beside Your options; brackets with
  round names, class icons and gold lines for the winners; on the Guild Together screen the scene fills the column.
- `/gtf test` checks all of this and takes a picture of each step of the tour. New file: a full game restart is
  needed.
- **A player's card on their name** (SPEC decision 75): point at a name anywhere in Guild Together to see their rank and
  level, whether they are online (and as which character) or when they were last seen, their alts, their place on the
  duel ladder, the crown, their Marks and any sentence they serve. Right-click the name for their whole card.
- **The mascot, alive**: the guild's pet stands on the square as the game's own creature of its kind, beside its
  list. It eats when fish come in, roars at a new level, thinks of fish when hungry and sleeps when it sulks; its bowl
  holds this week's fish. Under it: its level and the fish to the next, its mood, this week's fish and who feeds it
  most. The Guild Master can name it there now, not only in Guild settings.
- **The Gazette as a front page**: the paper itself, with a picture of the headline's player, beside a list of the
  week's stories and last month's awards.
- **Records as a trophy wall**: a plaque for each record, with its holder and since when they hold it. A record
  changing hands plays on the alert line with a fanfare.
- **The alert line's scene** is framed in gold like the game's own banners, and drops in under the line.
- **Writing a deed** shows how it will read in Deeds as you type.
- `/gtf test` checks all of this. No new files: a `/reload` is enough.
- **Fewer clicks** (SPEC decision 74): rest the mouse on a place in the bar to see its features, each with its status
  and red number; one click opens one.
- **A gear for everyone** at the end of the bar: a member's opens Your options; the Guild Master's opens Guild
  settings, which now starts with Your options.
- **Into the game's calendar**: making a game with a start time, a tournament, an officer's own event or a lottery draw
  with a time puts it in the game's calendar as a guild event, in the same click, when your rank may make guild
  events. When it may not, an officer who may sees a red number on the Calendar (For the game's calendar) and puts it
  in with one click. The Guild Master election's days wait there too. Moving or calling it off changes it in the game's
  calendar as well. A game's own button to put it in the calendar is gone: this does it.
- **Scenes with a cast**: a line under each name says what that player does ("rolled 64", "in the Stocks", "accepted
  the rules"); your own character has its name and line too. The players sit on stools at the gambling table, the
  voters at a long table for a council vote (the newest stands to cast), and a few guildmates sit on the ground to
  watch a duel, a tournament or the Stocks.
- **The court in session**: the judge on the high bench, the jury seated before them, the accused standing. At the
  verdict each juror stands and calls "Guilty!" or "Not guilty!", then the gavel comes down and the judge calls it.
  The court page says who voted what once the verdict is in (before that, still only the counts).
- `/gtf test` checks all of this too (P18 and P19). No new files: a `/reload` is enough.
- **A moment over the guild chat** (SPEC decision 76): with the guild window on its Chat tab, a scene's moment (a roll
  landing, a juror's call, a crown dropping) plays large over the chat for a few seconds, then fades. Clicks go
  through to the chat. The panel keeps the scene's last picture. On the other tabs it plays beside the panel, as
  before.
- **The side tabs in a rail**: Chat, Roster, Guild Benefits and Guild Info sit inside the frame on dark leather, in
  the guild's colour, the open one brighter. The bar and the panel are as wide as the frame, so its right edge runs
  straight.
- **The guild's name in the title band**, beside the crest, with the guild's motto after a thin gold line. The plate
  on top is gone, and so is Guild settings' choice between the name and the motto. Drag the name or the crest to move
  the window.
- Fixed: the Gazette's toast no longer lies over the panel; it moves beside the guild window when the window is in
  the way.
- Fixed: the Mak'gora's scene now says where it stands (challenged, on, the Guild Master stands, or who won) instead of
  "The Mak'gora is on" throughout.
- Fixed: the guildmates watching a duel, the Stocks or a tournament's sign-up no longer sit on top of each other or
  of the entrants.
- `/gtf test` checks all of this (P20), and its pictures of the court wait for the jurors' calls to end. No new
  files: a `/reload` is enough.
- **Fixes from the check of 1 November (the third):**
  - The Guild Together bar no longer repeats the guild's name: the guild window already shows it. The Guild Together screen
    still shows it, and there the guild window's crest and plate no longer sit over its heading.
  - The lottery's drum is a round wheel on its stand, the tickets inside it, turning while the die is in the air,
    and the die no longer sits on the drum. The seals on a vote's scroll and on the rules are round.
  - The catwalk lies under the contestants; in a big game of Traitors every other name sits lower so names do not
    run together; the target's poster fits its player.
  - "1 vote", not "1 votes".
  - Your options: the alert line's place reads "At the top", which fits; the tour card's Skip no longer touches Back.
  - The tour's welcome opens over Home's first list, not over whatever was open last.
  - Guild rules: under their picture, the right column says how many accepted and who (it was empty).
  - The alert line at the top keeps clear of the Guild Together bar and panel too, not only the guild window (its crest
    sat on the bar): under them when it fits there with its scene, else beside them, smaller if it must be.
- **Fixes from the check of 1 November (the second):**
  - A player far away is shown by their class's icon in a scene and on their card, never a made-up face.
  - **Alerts in your options**: whether the scene plays under the alert line, where the line shows (at the top, in
    the middle, above the action bars), how big (small, normal, large), and Show me to try it. At the top it moves
    beside the guild window when the window is open there, so it never covers it.
  - The curse's glow and a live match in the cup no longer grow over the whole scene.
  - The target's poster shows under its player again; the court's gavel is the scales.
  - Home's "Going on now" says how many are going on instead of names that did not fit.
  - The side column shows a glance only when the page has something to say; Home and quiet pages keep the quiet
    column, and "Going on now" is no longer said twice.
  - An old profession request without a recipe no longer logs an error.
- **`/gtf test` takes a picture of everything** (asked for on 1 November): every feature, every form, each row that
  opens something new, every scene of the demo guild (its moment played first), the leadership moments while they
  happen, the court's verdict, the moments on the alert line and the Guild Together screen, about 120 pictures in the
  Screenshots folder. The demo guild now has every punishment, a high roll, a lottery, bingo, a gift exchange,
  Assassins with your target, and a court case judged guilty, so every scene has something to play. The test takes
  longer: about ten minutes. A /reload is enough for this step.
- **The feel of the game** (SPEC decision 71, the seven picked from the check of 1 November):
  - **The guild's setup as cards**: five cards with their emblem, who makes the rules, who judges and how the Guild
    Master falls; "In force" on yours.
  - **At a glance**: a feature with nothing picked shows what matters there instead of an empty column (the Treasury
    shows this period's tax and the top givers; Professions the orders waiting and the guild's crafts).
  - **Votes as ballot cards**: yes and no as bars, the time left, and who votes, greyed until they do.
  - **A new setup is a moment**: it plays on every member's alert line with its scene, and the Guild Master's addon
    says it in guild chat; a rule changed by vote shows too.
  - **The Election between elections** shows the month's ballot and when the next one opens.
  - **Leadership's steps** are a tracker of icons.
  - **Round radio buttons** everywhere.
  A /reload is enough for this step.
- **Fixes from the check of 1 November:**
  - The crest beside the window and in the bar showed an empty white disc with the shield picked: the shield is
    back, and the guild's own tabard now draws its emblem the way the game's guild window does.
  - The rules text showed a raw "SETUP_DEMOCRACY_5" line (also in Guild settings, The guild's setup).
  - A tournament's bracket sat on a solid yellow fill: each match box has its own dark fill again, and a live match
    glows softly inside its box only.
  - The rules' scene shows the lines on the paper again.
  - Text no longer cut off: the guild's name in the bar (a size smaller when long), the election option in The
    guild's setup (it wraps), long names in Places and features (they take a whole line), and the duel ladder's
    heading (when it starts over is a line under it).
  - The election's days read "the 1st to the 4th, the 5th to the 7th".
  - The guild's setup no longer offers "Put it to the vote" when nothing was changed.
  A /reload is enough for these.
- **The guild's setup, third batch** (SPEC decision 70). **No Mayor any more**: the Mayor, its powers and the Event of
  the week are gone. A **Democracy can elect its Guild Master** each month (the option in Guild settings, The guild's
  setup): members stand on the 1st to the 4th, everyone votes on the 5th to the 7th in the Council's new Election, and
  a winner other than the Guild Master gets the guild through the Hand over button, as after an impeachment. In a
  **Dictatorship** a declined Mak'gora has no guild vote: the challenger may declare a **rebellion**, and when a third of
  the members sign it within 3 days, the Guild Master must fight within 3 days or lose the guild. In a **Monarchy** the
  Guild Master can take a strike back. A /reload is enough for this step.
- **The guild's setup** (SPEC decision 70, second batch). The Guild Master picks how the guild is run, in Guild
  settings, The guild's setup (asked the first time they open a place): **Democracy** (the guild votes), **Warcouncil**
  (a council of officers or elders, led by the Guild Master, who may veto), **Monarchy** (the Guild Master rules, the
  officers can overrule), **Dictatorship** (the Guild Master alone; incidents judged by allowed ranks or the duel
  crown's holder) or **Free guild** (no punishments). Each says who changes the rules and the setup, who judges, who
  can impeach and who gives strikes, and gives the punishment rules their first values. Until one is picked only the
  regular features work: PvP Challenges, Games, Gambling, Professions, the Calendar, polls and debts between members.
  In a Democracy and a Warcouncil a change of setup goes to the vote, in the Council's Votes; the three punishment
  switches can be voted on too. A change of setup cancels running punishments, open court cases and open votes. The
  rules for everyone now start with the setup and what it means. A /reload is enough for this step (but restart the
  game if you have not since the first batch).
- **Every punishment has a reason** (SPEC decision 69, first batch). Giving a punishment now asks why: **unpaid tax**
  (only for a member who owes tax; it pays off their oldest unpaid period) or **an incident** (judged directly, or,
  when the Guild Master says so, only by the guild court). Trial by combat follows its own switch, and the accused who
  wins goes free without punishing back. In Your options, **Don't punish me**: nobody can punish you, and you cannot
  punish or judge; with the guild tax on you owe no new tax and can only look at the places, not take part (the
  Council's Leadership, Guild rules and Votes stay open); with it off, the Guild Master picks what it closes. Back
  in, you wait 7 days to opt out again. Others see it on your player card. The rules in force are written out at the
  top of Punishments' menu and in the Guild rules, with when they last changed; the Guild Master sets them in Guild
  settings, Punishment rules. A new file: **restart the game** for this step.
- **The guild's look** (SPEC decision 68): in Guild settings, The guild's look, the Guild Master picks the accent
  colour, the frame's leather, how dark the panels are, the crest (the shield or the guild's own tabard) and what the
  plate over the window says (the guild's name or a motto), for every member. The crest and plate change at once; the
  colours after each member's next /reload (chat says so).
- **`/gtf scenes`**: after `/gtf test`, every scene of the demo guild plays slowly, 5 seconds each, beside the
  panel and under the alert line, with a picture of each in your Screenshots folder.
  A /reload is enough for this step.
- **Fixes and changes from the second test in the game:**
  - **Real characters, as in Journey Together** (SPEC decision 66): a guildmate shows as their real character once
    the game has had them near you this session (in your group, targeted, close by with a nameplate), and stays so
    until you reload; until then their class crest stands in, with their name. The dark silhouettes are gone, and so
    is the sharing of looks.
  - **No gap at the top of the guild window**: the band where its title was is dark again.
  - **A crafting request always names a recipe** a crafter of the guild knows: search for it and pick it (SPEC
    decision 67).
  - **The brand is the guild** (SPEC decision 65): the bar, the right-click menu and the full screen show your guild's
    name instead of Guild Together.
  A /reload is enough for this step.
- **The scenes play large** (SPEC decision 63). What you pick plays in a window of its own beside the panel, up to
  480 wide, where your screen has room; the details stay in the panel. The guild's big moments (a sentence, the
  crown, a champion, a winner, BINGO) play their scene large under the alert line, and a click on it opens it; so
  does each roll of your own deathroll while the panel is elsewhere. The demo guild left open after `/gtf test`
  now shows alerts, so you can try them there.
- **The Guild Together screen** (SPEC decision 64): the new button in the panel's header (or `/gtf full`) puts Guild Together
  across your whole screen, large, over the guild window. **Back to the guild window** returns; Escape closes it with
  the window. A /reload is enough for this step.
- **Move the guild window** (SPEC decision 62): drag the guild's name at its top (or the crest) to move the window
  with Guild Together under it. It stays on your screen and where you put it, for all your characters; Options, **Back to
  the middle** puts it back.
- **Fixes from the first test in the game:** `/gtf test` no longer stops with "script ran too long" (it takes a
  breath between the pages it opens); a rule change that waits for your vote is now above the polls in Council, so
  its buttons are in sight in the shorter panel; your options' line no longer mentions the old size. Retail's
  character models cannot take another race, so guildmates far away show as figures in their class colour for now
  (the self-test says so instead of failing). A /reload is enough for this step.
- **The Calendar: every kind of event in one place** (SPEC decision 61). A new place in the bar, after the Council.
  It shows the guild's games, tournaments, lottery draws, the duel crown's deadlines, polls and votes closing, the
  Mayor's election and the Event of the week, court cases, the tax days, Journey gatherings, the guild's events from
  the game's own calendar (read only: sign up there), and the officers' own events. A switch at the top of the list
  picks **Month** (the days in a grid, a mark per event; pick a day to see its events) or **Agenda** (the coming
  events, day by day); your character keeps the one you picked. Pick an event to see when it is and where it lives,
  with a button to go there. Ranks with **Add calendar events** (the officer ranks by default; Guild settings,
  Permissions) add events of their own with a name, a time such as Sat 20:00 and a line about it; whoever added one,
  or the Guild Master, can change or remove it. Its red number counts your events that start today. Its own header
  painting (a notice board in Stormwind, or in Orgrimmar for the Horde) and medallion (a calendar page and an
  hourglass). New files and pictures: **restart the game** for this step.
- **One frame: the guild window in the middle, the Guild Together bar under it, the panel under the bar** (SPEC decisions
  58 and 59). The guild window now opens in the middle at the top of the screen, sized so that the window, the bar
  and the panel fit above your action bars (76% on a small screen, never larger than the game's own size). It wears
  Guild Together's leather and gold frame, with the guild's crest in the corner and its name on a plate along the top. The
  Guild Together bar is joined under the window on every tab (Chat, Roster, Info): Guild Together with what waits for you, then
  the places. A place opens in the panel under the bar: its features on the left, the list in the middle, what you
  pick on the right. Clicking the open place again, or the panel's close button, puts it away; the bar stays. The
  main buttons are red with a gold edge. The Size slider is gone. To keep the game's own guild window, turn off
  Options, **Dress the guild window**, and reload (or type `/gtf plain`): the bar stays under the window and the
  panel opens beside it. New files and pictures: **restart the game** for this step.
- **A short scene for every activity, with the players as their characters** (SPEC decision 60). In the panel's right column,
  what you pick plays as a small scene in its place: the guild hall's hearth for Gambling, the duelling ring, the town
  square, the guild fair and its pier, the council hall. The players are their own 3D characters doing the game's
  moves: they throw the dice, trade blows, cheer, sob, kneel, bow, dance and fall over. Every roll gets a die that
  tumbles with a "?" and lands on the game's real roll. The Wheel of punishment is now a real wheel that turns on
  every screen and stops on the result; tomatoes fly and splat; the crown drops onto the new holder; a sentence's
  medal stamps down on the alert line; the meet-up's countdown numbers zoom in. Each moment plays once, while you
  watch or when you open it within 10 minutes. Off with Alerts in Options. **Shared looks**: your Guild Together tells
  the guild what each of your characters looks like (race, body type and outfit; the gear worn where there is no
  transmog), so players far away appear as themselves too, "as of" their last share; someone with no look shared yet
  is a dark figure in their class colour. Warnings stay still. `/gtf test` checks every scene, the dice, the Wheel
  and shared looks, and the demo guild's members share looks. In the panel's right column a scene takes at most 60%
  of its height, centred, so the details stay in sight; `/gtf test` opens each one there, as a player would, and
  checks it fits. New files and pictures: **restart the game** for this step.
- **Bigger on a large screen: the guild window is the menu, and a big screen beside it shows the feature** (SPEC
  decision 57). The window shows the places along the top and the place's features as large tiles, two to a line.
  The feature you pick opens on the big screen beside the window: its list on the left, what you pick on the right,
  each with its own buttons. Its size is yours: Options, Size, from 100% to 200%; the first time, Guild Together picks the
  size that fits your screen. Its close button puts it away; pick a feature to bring it back. Home is features too
  (Waiting for you, Going on now with Start something under it, the guild's story, Options last), and so is Guild
  settings (Currency, Features, Permissions, Tax, Votes and court, Discord). A /reload is enough for this step.
- **Only players with Guild Together are tracked** (SPEC decision 56): punishments, warnings, the guild court, the tax,
  debts and bets now count only players who have the addon, so a guild where only the officers use Guild Together never
  keeps score of the others. The Good sport choice is gone: everyone with Guild Together can be punished, except the Guild
  Master. Members without the addon can no longer join a high roll by typing !join in guild chat. Getting started
  on Home now has two steps (the rules, a first duel). `/gtf test` gives its pretend members Guild Together, and steps
  down as Guild Master for the steps that punish you. A /reload is enough for this step.
- **Every name says what it is** (SPEC decision 55, picked by the guild from five each): a new place, **Gambling**,
  holds the Deathroll, the **High roll** (was Roll-off) and the Lottery, so gambling sits apart from PvP; Challenges is
  now **PvP Challenges** and Manage is **Guild settings**. Marks are called **Guild Tokens** by default (the Guild
  Master can still rename them). Among the rest: Weekly news, Guild mascot, Awards, Duel crown, Bets, Tournaments,
  Secret target, Events, Top donors, Find a crafter, Crafting orders, Being punished, Give a punishment, Tomato
  throwing, Wheel of punishment, Walk of shame, Chat curse, Screen jingle, Servant for an hour, Gift to the Guild
  Master, Guild rules, Polls, Guild court, Event of the week, and the settings tabs Features, Permissions, Tax, Votes
  and court, Discord. An event has no name box any more: it shows as "Fishing contest · Sat 20:00", and guild chat
  and the calendar name it by its kind. Gambling's header painting and icon are stand-ins (the Treasury's painting,
  the dice) until new art can be painted. New pictures: **restart the game** for this step.
- **The row you pick stays in sight**: a list scrolls to the row picked for you (a game you are in, further down
  Guild games), and the self-test now scrolls to a row before it clicks it, as a player would. A /reload is enough.
- **Plain game names, nothing below the fold, and a self-test that walks every page** (SPEC decision 54): fixed an
  error after the Gazette: opening Records (or any feature after one that used the same piece name) could break the
  page. The games have plain names: Bingo, Fishing contest, Meet-up, Treasure hunt, Transmog contest, Survival race,
  Hidden traitors and Gift exchange. Guild games now lists only the games; the game you pick opens beside the window
  with your part first (your role and who to choose, who you give to), then what you can do, its picture and About
  this game, and Join or the host's next step along the bottom, so nothing needs scrolling. Challenges shows what
  waits for you first (your duel, the duel crown and the challenges to answer), the ladder under it. `/gtf test`
  now also walks every place, feature, row and form as the Guild Master, an officer and a member; checks that what
  waits for you is in sight; and covers declined and called-off duels, games called off, left and over, the Guild
  Master tournament, a feature switched off for everyone, and messages held during a lockdown. Opened with the
  guild window closed, it waits 20 seconds for you to open it. A /reload is enough for this step.
- **Ladder seasons, Monday's Gazette, sounds and motion** (SPEC decisions 52 and 53): the duel ladder starts over
  each month, or each season of three months (the Guild Master picks in Manage, General); the ladder names its season
  and says when it starts over, and Records keeps each past season's top three. The duel crown and the all-time
  records are not reset. At your first login of a week, a toast brings last week's Gazette (when it had news); a
  click opens that edition, with a way back to this week's. The game's own sounds play when our pages open, for a
  place, a feature, gold paid, an alert, and a fanfare for a champion, a crown or BINGO (switch them off in Your
  options). Places fade in, the red number pops when it grows, and bars grow in; with alerts off, the pages stay
  still. A /reload is enough for this step.
- **The player card, the right-click menu, the welcome and Your options** (SPEC decision 52): right-click a guildmate
  in the guild window's list, in chat or as your target for **Challenge to a duel**, **Deathroll...** and **Player
  card** (the duel and deathroll need them online with Guild Together). The player card opens beside the window: their
  characters, place on the ladder, the duel crown, your duels against each other, debts between you, Good sport and
  sentences, deeds and professions, with Duel and Deathroll along the bottom. A new member is welcomed on Home with
  three steps (read the rules, Good sport, a first duel) until they are done or hidden. **Your options** (on Home,
  or /gtf options) holds your own choices: alerts, emotes, sounds, Guild Together lines in your chat and Good sport.
  A new file (UI\Card.lua): a full restart of the game is needed.
- **Painted icons, the emblem and header paintings** (SPEC decision 53): every place, feature, guild game and
  punishment has its own painted medallion in Journey Together's style (64 in all, Journey's 16 among them; the Horde
  sees them on crimson). No two things share an icon: Assassins is a hooded figure, Deathroll a skull and dagger,
  Votes a ballot box, Warnings a red flag, the Mayor a chain of office, each punishment its own picture. The
  Guild Together emblem, a blue shield with a gold cross, is our side tab's icon, sits beside Home's name and over the
  alerts. Each place has a painting of its own across the header, Alliance and Horde, with its medallion beside the
  title. Officer ranks in Manage show helmets, member ranks the guild tabard. New pictures (Media\Icons, IconsHorde,
  Emblem, EmblemSmall, Head<Place>, Horde<Place>; the old header pictures and IconSet are gone): a full restart of
  the game is needed.
- **Our own controls** (SPEC decision 53): text fields, tick boxes and radio buttons are small wells of dark glass
  whose edge turns gold under the mouse, while typing and when on (a gold tick, a gold dot). On/off settings and the
  places and features in Manage are toggles with a sliding knob. The Council's numbers and the tax per rank have a
  minus and a plus. What you pressed to cycle through is now a dropdown with its choices in a list: a tournament's
  kind and match length, the rule to change and its new value, the court's sentence, the Mayor's game of the week,
  the punishment and the curse, the mascot's kind. Second buttons have a clear gold outline and bright letters (grey
  when they cannot be pressed). Scroll bars are a thin gold line that shows only when a list is longer than its
  pane, and can be dragged. The Gazette is a newspaper on the glass: its masthead in the game's book letters between
  gold rules, the week and the number of stories, the headline, and a hairline between stories. New pictures
  (Media\Dot, Tick, Chevron): a full restart of the game is needed.
- **Simpler, and found** (SPEC decision 52): Manage has a new tab, **Places and features**: each place with its
  features as tick boxes, and every punishment and guild game. What is off hides for everyone, and nobody below the
  Guild Master can give an off punishment (the Wheel never lands on one). Leadership and Votes always stay. The
  Jingle, the Servant and the Mayor start switched off. Rows that cannot do anything hide: Gatherings without
  Journey, the Marks while the currency is gold. The Bingo card is no longer a row of its own: your card shows in
  the bingo game's screen beside the window. A guild game's buttons are there too (Join or Leave and the host's next
  step along the bottom, the host's other tools above them), and Start a roll-off... opens its form there. A row
  with nothing on shows the last result ("Last: Korgath won") for guild games, tournaments and roll-offs. The
  Mayor's game of the week only offers games that are on.
- **Plainer names, for players everywhere** (SPEC decision 51): the Charter is the **Rules**, Strikes are
  **Warnings**, the Ledger is the **Bank log**, Patrons are **Donors**, Item requests are **Bank requests**, crafting
  Requests are **Orders**, Raffles are the **Lottery**, From Journey is **Gatherings**; in Punishments, **Sentences**,
  **Yours** and **All punishments**, and the Walk of shame and the Radio are the **Naked run** and the **Jingle**.
  The Rolling Pin awards are the **Monthly awards**, the purse is the **currency**, and "the crown" is only the duel
  crown: the Guild Master's is the **Guild Master tournament**. The line at the bottom says "Updated 5 min ago".
  Statuses say what runs and how long is left ("Mak'gora · 6 days left", "7/20 accepted", "Crown: Brakka").
- **Simpler, step 2: the places rebuilt** (SPEC decisions 48 and 50): inside each place, its features are rows on the
  left, each with a short status ("Korgath wears the crown", "2 open", "Nothing on") and a red number when something
  waits for you there; the picked feature's list is on the right. No more small tabs or page buttons in the header.
  Challenges: Duels (the ladder, the crown and the bets), Tournament, Assassins and Deathroll (moved
  from the dice). Games: Guild games, Bingo card, From Journey, Roll-off, Raffles. Treasury: Tax and debts, Ledger,
  Patrons, Item requests, and the Marks. Professions: Crafters (find a recipe, then who makes what) and Requests.
  Punishments: Now serving, For you, The menu. Council: its six parts. The Hall of Fame: the Gazette, Deeds, Hall of
  fame, the mascot and memorials. Details and forms (a player to challenge, a new raffle, a request, Open a poll…,
  Hand out…, Start…) open beside the window, with the main button and Cancel. Each tool shows only to the ranks that
  may use it, and what waits for an officer (an item request to approve, a Wheel to spin) is that feature's red
  number. Home's four big actions go straight to their feature and open the form beside the window. Fix: the
  punishments' menu showed who may hand each one out by rank number; it now reads the ranks by name.
  From the in-game pictures: a red number sits on its icon's shoulder (rows) or above the name (places), so names
  are never cut; the Gazette had no name; the screen beside the window only shows a picture on the features that
  have one (Deathroll, Tournament, a game); texts say Manage and Guild Master, not Settings and GM. A new test checks
  that every text the code names is in the locale.
- **A new look** (SPEC decision 49): dark glass and gold. Panels of smoky glass with a fine edge and rounded corners,
  small gold headings with a line running out, quiet rows that light up in gold (and keep a gold edge when picked), a
  solid gold main button and gold-outline second buttons, a soft gold glow on the button waiting for you, and the red
  numbers as small glowing pills. The places along the top are plain names, the open one in gold over a gold line.
  Icons are Journey Together's painted medallions where it has one (duels, the Council's scroll, the Hall of Fame's
  book, letters, keys, maps...), else the game's icon cut round inside the same gold ring. The screen beside the
  window is glass with a gold edge. New pictures: a full restart of the game is needed.
- **Ranks and powers** (SPEC decision 50): what each rank may do is kept by the rank's name, so a rank the Guild
  Master adds or moves in the game keeps its ticks, and each rank is ticked on its own. A new or renamed rank starts
  with the default for an officer or a member rank, and Manage shows the Guild Master a red number to check it. The
  officer ranks are the ones the game lets read officer chat, as the Guild Master's addon reads them. New defaults:
  the officer ranks start tournaments, start games and raffles (now a power of its own), approve item requests,
  spin the Wheel and impeach. Earlier ticks were kept by rank number and are reset to these defaults.
  In Manage, Who may do what lists the ranks on the left (officer or member rank, how many powers, and New for a
  rank to check); pick one to tick its powers on the right, grouped by place. The court's switch moved to the
  Council tab of Manage.
- **The tax pays itself** (decision 50): gold put in the guild vault counts as soon as any member's addon reads it
  in the vault's log, and gold traded or mailed to the Guild Master counts too. Only the Guild Master's addon charges
  the tax, and only the Guild Master can record a payment by hand or mark one paid. "Record tax payments" is gone.
- **Simpler, step 1** (SPEC decision 48): Guild Together is now one side tab in the guild window. Along the top: Home,
  Challenges, Games, Treasury, Professions, Punishments and the Council, and Manage (with its gear) at the end for
  those who run things. Home shows what waits for you, what is going on now, four big actions (Duel someone,
  Deathroll someone, Open a poll, Hand out a punishment; only those you may use) and the Hall of Fame. The red
  numbers sit on the side tab and on the places. The Guild Master switches whole places off; Home and the Council
  always stay (impeachment must always be possible). The screen beside the window can now carry up to two buttons.
  For now, a place with more than one page shows them as buttons in its header; the next steps rebuild each place.
- **Easier for first-time players** (SPEC decision 47): every empty list says what to do next and names the button in
  gold; the button waiting for you glows; and a red number on the side tabs and page tabs counts what waits for you
  there (votes, duels and deathrolls to answer, your roll, debts, your defence, the charter, a hand-over). Hover the
  tab to see the list. Leadership shows the three ways to a new Guild Master when nothing is under way. The
  Council's list shows the number on each part too (Charter, Votes...).
- Fixes from the in-game pictures: the waiting button's glow is now a gold rim (it did not show on the red buttons);
  a row of buttons that does not fit goes on to a second line (the tournament's walkover buttons ran off the pane);
  a poll's voters are on their own line under each choice (they ran under the count); a lost Mak'gora counts for
  its 30-day wait even when it all happened within one second.
- **The side window** (SPEC decision 44): a larger window beside the guild window that shows what you picked as a
  lively picture. Contests: the gnome run's track, the derby's leaderboard, The Traitors' board, the hunt's trail,
  the fashion show's votes and the flash mob's countdown. Arena: the cup's bracket. Gambling: the deathroll's ladder.
  Punishments: the tomato throwers, the service quota, the servant's orders. Council: the leadership vote or duel
  and the newest poll. Doing things stays in the guild window.
- **Leadership: the old laws, impeachment and Mak'gora** (SPEC §7.5, decision 46). The Council page's first tab is
  now Leadership. A new Guild Master comes from one of three, one at a time:
  - **Impeachment by the officers**: an officer starts it (the ranks ticked for Impeachment in Settings; by default
    the rank under the Guild Master). The officers vote for 7 days: yes, with who should lead, or no. More than half
    of them for one member, and it passes. The starter can cancel it. One a week. (This replaces the motion, its
    seconds and the guild-wide vote.)
  - **Mak'gora**: after 30 days in the guild, a member challenges the Guild Master to a duel. The Guild Master has 7
    days to accept; if not, the guild votes for 3 days on forcing it. The duel must happen within 7 days, or the
    challenger wins. A lost challenge waits 30 days. A challenger gets no strikes meanwhile.
  - **The crown**: the Guild Master's tournament for the title, as before.
- **Only the rightful Guild Master leads** (decisions 45 and 46): after an impeachment, a Mak'gora or the crown, the
  Guild Master cannot give out, start or change anything in Guild Together until the guild is handed to the winner,
  with no time limit. Anyone else given the rank meanwhile is locked out too. Every member is told when the Guild
  Master has been online for an hour without handing over, when an impeachment voter is demoted, or when a
  challenger is removed from the guild.
- **The demo guild**: `/gtf test` now ends by filling a pretend guild of twenty members with every page in use, takes
  its pictures (one per game and punishment, with the side window), and leaves it open to look around in.
  `/gtf test off` (or /reload) ends it. Nothing is sent to other players.
- **Four side tabs in the guild window** (SPEC decisions 40 and 42), under Blizzard's: Compete (Arena, Contests,
  Hall of Fame), Gold (Treasury, Gambling), Professions, and Law (Council, Punishments, Settings). Each opens on the
  page it was left on, and hides when the Guild Master switched all its pages off. They move a little closer
  together when the last would pass the window's bottom.
- **Plainer page names** (SPEC decision 42), for a guild that speaks Swedish: Tavern is now Gambling, Games is
  Contests, Stocks is Punishments, and the Chronicle is the Hall of Fame (its Hall of fame tab is Records). Texts that
  named the old pages say the new names.
- **Plainer punishment names** (SPEC decision 43): the Stocks is now the Tomato Target (tag `[Tomato Target]`), the
  Dunce Cap is the Clown Hat (tag `[Clown]`), Servant for an hour is Servant, and Tribute and the Cursed Idol is the
  Cursed Idol (the tribute is now a gift). The Good sport note says "nobody can punish you".
- **Professions** (SPEC §8b, G9), on the Guild side tab. Each member's addon shares their professions and skill, and
  the recipes they know once they open that profession's window. The page lists the guild's crafters per profession
  and your own; Find a recipe shows who can make it, online first, with Whisper. Crafting requests: ask for something
  made (with your materials or not, and an optional tip in the purse); members who know the recipe are told in chat;
  the first crafter who takes it makes it; Got it owes them the tip. The Guild Master can switch the page off.
  - Fixes from the first test in game: a tip in gold shows as gold (it showed "0 g"); a profession's row counts
    members, not "crafters" (Fishing and Archaeology are listed too); what was last shared is kept per guild, so the
    self-test's pretend guild does not stop a share to the real one; the self-test waits for the pretend blacksmith's
    recipes instead of finding your own Blacksmithing.
- **The pages in the guild window's own parts** (SPEC decision 39), page by page.
  - Every page: a slimmer header, with the page's state on the right and an "i" for its help.
  - Settings: small tabs along the top (Purse and pages, Who may do what, Guild tax, Council, Discord), each group
    with the whole width, so nothing needs scrolling.
  - Treasury: the guild tax with a bar and the open debts on the left; the long ledger, Patrons, item requests and
    Marks in small tabs on the right. Click a debt or a request to see it and what can be done with it. Names are in
    class colours and gold shows with the game's coins.
  - Arena: the challenge in hand and the duel ladder on the left; click a player to see them and challenge them. The
    crown, the tournament, Assassins and wagers in small tabs on the right.
  - Tavern: what is on at the tables and who is online to challenge on the left; the deathroll, the roll-off and
    raffles in small tabs on the right, where the challenge and a new raffle open as forms.
  - Games: this week's games as rows with an icon each on the left; the game picked, your bingo card and Journey's
    Gatherings in small tabs on the right. Start a game... shows the eight games as rows, then their fields.
  - Stocks: who is serving, the Dunce Cap and Good sport on the left; click a sentence for tomatoes, bids and
    pardons. What is yours, the menu and the stocks' spot in small tabs on the right; the punishment form opens there.
  - Council: the six parts as rows on the left, each with where it stands ("Vote", "2 open"); the part on the right,
    with its forms (a poll, a rule change, a charge, a strike, filing a motion) opening from its bottom bar.
  - Chronicle: the Gazette on paper and last month's Rolling Pin awards on the left; deeds, the Hall of fame, the
    mascot and memorials in small tabs on the right.
  - `/gtf test` measures every text on every page and tab (nothing but row lines may be cut off), checks that every
    texture and icon loads, and takes a picture of each small tab.
  - Fixes from that test in game: notes are in a soft light parchment colour (the grey, and then dark ink, could not be read on the orange panes); the
    deathroll's rolls show the short name; a long strip title is cut before the text on its right; the stocks' spot,
    the election and strike rows no longer run over; the charter's count shows once; an item the game has not loaded
    shows a bag, not a question mark; the Hall of fame says "1 day".
- **Fixes from the first test in game (29 Oct 2026).**
  - A crown challenge won in the same second it was accepted now passes the crown on.
  - Tags in guild chat ([Patron], [Dunce], [Crown]) change on the next line, not a few seconds later.
  - Turning Good sport off and on again at once leaves it on.
  - `/gtf test` now also checks the Radio, curses, community service, the walk of shame, tribute and the Cursed Idol,
    a servant for an hour, the Mayor's powers, an alt counted as its main, and the month's awards.
- **G8: the Chronicle, and Discord.**
  - **Deeds** write themselves: the first to each level milestone, champions, game winners, new crowns, ten duels
    in a row, a new Guild Master. Officers the Guild Master allows write more by hand, with Marks as a reward.
  - **The Gazette**, every week, with a headline from the week's biggest moment. **The Hall of fame** keeps the
    guild's records. **The Rolling Pin awards** each month: Golden Tomato, Jailbird, Punching Bag, Gilded Rolling Pin
    and Snake Eyes.
  - **The guild mascot** (Sir Snuffles, the guild boar, until renamed) eats every fish you catch, levels up and sulks
    when forgotten. **Memorials** remember fallen and departed members.
  - **Discord** through Addon Webhooks for Discord: the Herald's game writes the guild's news on logout or reload, and
    the app posts it to the channels you pick. Post to Discord now in Settings.
- **G7: the Treasury.**
  - **Guild tax:** the Guild Master sets gold per rank, each week or month, from a level, with members let off by
    name. An officer's addon charges it at the start of each period; unpaid tax adds up as a debt to the Treasury.
  - **The long ledger:** every visit to the guild vault by a member with Guild Together adds the vault's log to one
    ledger the whole guild shares. Gold put in the vault pays your tax once an officer has seen it.
  - **Patrons:** the members who gave the Treasury the most gold, this month and of all time. This month's first wears
    [Patron] in guild chat.
  - **Item requests:** ask the vault for an item; the approver mails it with one press at a mailbox. Prizes the
    Treasury owes are mailed the same way.
- **G6: the Council.**
  - **Impeachment:** a member files a motion of no confidence; with 3 seconds in 48 hours the whole guild votes for 3
    days. If two thirds say yes (and 40% of members voted), the crown is fought for in a tournament the Guild Master
    defends. If they lose, their page shows **Hand over to <winner>**: one press, and the guild has a new leader. The
    Guild Master can also open the crown without a motion.
  - **The guild's rules:** the Guild Master sets who may open polls, file motions, see strikes, run the court and
    give strikes, and the numbers for motions and juries. The guild can change any of them by a vote.
  - **The charter**, accepted by every member again after each change. **Polls** with up to six choices, secret or
    weighted by rank. **Strikes**, confirmed by a second member. **The guild court**: a charge, a defence, a jury and
    a verdict that can send the guilty to the Stocks. **A Mayor** each month, who spins the Wheel, pardons and picks
    the game of the week.
  - Members without the addon vote by whispering `!vote 2`, `!vote yes` or `!vote <name>` to anyone with it.
- **G5b: Games, part two.**
  - **The Traitors:** the host presents and the guild plays. Roles are whispered in secret; each night the traitors
    murder one of the Faithful, each day the round table votes someone out and their role is shown on every screen.
    The Faithful win by finding every traitor; the traitors win once they are as many as the Faithful.
  - **Running of the Gnomes:** level-1 runners (invited to the guild) race the host's checkpoints. Your own addon
    checks each one as you pass and notices if you die. Everyone who reaches the finish alive shares the prize.
  - **Secret Santa:** sign up, get a guildie to surprise, mail them a gift. Their addon confirms it came from their
    Santa without telling the guild who. On reveal night every pair shows on every screen.
  - Games can be dated like "24 Dec 20:00". Guild chat lines and alerts for murders, banishments, fallen gnomes,
    gifts and the reveal.
- **Flavour: the guild hears it.**
  - **Guild chat lines** for the big moments, so members without the addon hear them too: "[Guild Together] Fenwick
    is sentenced to the stocks for 15 minutes: "Pulled the boss". The stocks stand in Goldshire. Bring tomatoes!" Also
    the Wheel's result, pardons and bail, trial by combat, the crown taken or defended, champions, raffle and game
    winners, deathroll losers and BINGO!. Said once, by the addon of the player who did it; held in dungeons and
    raids. The Guild Master can switch them off on the Settings page.
  - **Emotes** go with your clicks: throwing a tomato, sentencing, pardoning, spinning the Wheel, challenging for the
    crown. `/gtf emotes` switches them off.
  - **On-screen alerts** like a raid warning: "The crown has fallen!", "BINGO!", a champion, a sentence. The Wheel of
    Punishment now really turns on every screen and lands on the result. A flash mob counts down from 10 for
    everyone. `/gtf alerts` switches them off.
- **G5: Games (part one) and the calendar.**
  - **Start a game** (ranks that may start games): a name, when ("now", "20:00" or "Sat 20:00"), how long, and an
    optional prize the Treasury pays.
  - **Guild bingo:** everyone who joins gets their own 4 × 4 card. Squares tick themselves from real play: ding a
    level, catch a fish, down a dungeon boss, rest at an inn, take a flight path and more. First full line wins.
  - **Fishing derby:** the most fish caught while it runs.
  - **Flash mob:** be at the host's spot when the countdown hits zero; everyone there gets the prize.
  - **Scavenger hunt:** clues that lead to places in the world; claim one standing there.
  - **Fashion show:** enter, and vote for your favourite (never yourself).
  - **To calendar:** one press puts a game into the game's calendar as a guild sign-up event (or invites, when the
    rank may not make guild events).
  - **Gatherings from Journey Together Forever:** the organizer adds a Gathering to the calendar with one press,
    inviting the fellowship's members in the guild; a moved or called-off Gathering can be moved or removed there.
    This needs a small addition in Journey that is not built yet.
  - `/gtf test` plays a derby, bingo, a flash mob, a scavenger hunt and a fashion show with the pretend members.
- **G4: the Stocks.**
  - **Good sport:** tick "I'm a good sport" on the Stocks page. Without it, nobody can punish you.
  - **Hand out a punishment:** who, how long, the punishment and a reason (up to 80 letters). The Guild Master
    decides which ranks may give each one.
  - **The Stocks:** the clock runs only while the prisoner stands at the stocks. The Guild Master places them with
    "The stocks are here"; until then they stand where the sentence was given. Guildies throw tomatoes: a splat on
    the prisoner's screen and a counter.
  - **Dunce Cap** (passes on to the next one), **Curses** (Murloc-speak, or praise for the Murloc King, in guild chat
    on others' screens), **the Radio** (a jingle every few minutes; a buyout stops it), **Community service** (fish
    caught), **Walk of shame** (zones reached in order with no gear on), **the Wheel** (spun by a rank that may; one
    reroll can be bought), **Servant for an hour** (auctioned, then orders), **Tribute and the Cursed Idol**, and
    **Trial by combat** (the accused can demand a duel; the winner picks the sentence).
  - Bail and pardons. Bail goes to the Treasury.
  - The prisoner sees a banner at the top of the screen with the sentence, the time left and Pay bail.
  - Guild chat shows `[Crown]`, `[In the Stocks]` and `[Dunce]` before a player's lines, on the screens of members
    with the addon.
  - `/gtf test` sentences a pretend member, sentences you, and runs a trial by combat with the pretend members.
- **G3: the Arena.**
  - **Duel ladder:** challenge a member who is online with Guild Together; once they accept, duel them in the game.
    The winner is read from the game's own duel message and the rating moves (from 1500). Only challenged duels count.
  - **The crown:** the first ladder duel's winner takes it. Challenge the holder for it; the holder must accept one
    challenge a day: a challenge declined or left a day goes to the challenger. The longest reign is shown.
  - **Tournaments:** a rank that may start tournaments opens one: single or double elimination, groups, or round robin,
    best of 1, 3 or 5, with an entry fee and a Treasury prize. The pot is shared 60 / 30 / 10% among the top three.
    The host closes sign-up, can give walkovers, and finishes it.
  - **Wagers** on any accepted duel, crown duel or tournament match. Winners share the pot, each by what they bet.
  - **Assassins:** a week-long game of secret targets. Beat yours in a duel and you take theirs.
  - The Treasury can owe a player (a tournament prize); gold from a member who records tax payments pays it.
  - `/gtf test` plays a ladder duel with wagers, crown challenges, a tournament and Assassins with the pretend members.
- **G2: the Tavern and the purse.**
  - **Deathroll:** challenge a member who is online with the addon, for a stake in the guild's purse. You pick the
    starting number (100 × the stake unless you change it). Both roll with the game's own `/roll` until someone
    rolls 1; that player owes the stake.
  - **Roll-off night:** a rank that may start games opens it; members join (without the addon: `!join` in guild
    chat) and roll. The highest takes the difference from the lowest.
  - **Raffles:** a prize, a ticket price and how many tickets. The draw is the host's `/roll` in front of everyone;
    tickets go to the Treasury.
  - **Treasury page:** open debts in gold, with "Mark paid" for the one owed and "Pay by trade" for the one who owes,
    and every player's Marks. Ranks that may grant can give or take Marks; a balance may go below 0.
  - Gold that reaches you by trade or mail from someone who owes you marks their debt paid by itself.
  - One player is one player: debts and Marks add up across a player's characters in the guild.
  - `/gtf test` plays a deathroll, a roll-off and a raffle with the pretend members, and takes the screenshots after
    them.
- Our pages lie above everything in the guild window: Blizzard's chat scroll bar, member list and chat box no longer
  show through them.
- Settings: every other row of "Who may do what" is shaded, so a row is easy to follow to its boxes.
- Settings looks like the mockup: a gear on its tab, Purse, Pages and "Who may do what" in framed cards, and the
  page switches in two columns so all seven show without scrolling.
- The chat's scroll bar no longer draws through our pages (every Blizzard frame in the window is checked, in its
  strata too). The rank names over "Who may do what" have room between them.
- Pointing at a row in "Who may do what" shows its full name, what a punishment does, and who may do it now.
- `/gtf test` takes a screenshot of the guild window and of every page, to review the look outside the game.
- `/gtf test` on a character without a guild runs the window checks on a community of your own, with the pretend
  guild.
- The Guild Together tab is drawn like the game's own side tabs (the template it used does not exist in retail).
- A copy straight from the repository says it is a development copy instead of showing the packager's placeholder.
- **Self-test in game:** `/gtf test` checks the game's functions and templates, the art, the roster, addon messages,
  the key binding and, with the guild window open, the tab, every page, where they lie and that nothing in the guild
  window is tainted by Guild Together. Then it runs the multi-player paths in a pretend guild with four pretend
  members, each running its own copy of the sync code; nothing is sent to other players. The report is saved for the
  developer.
- **G1: the guild window.** A Guild Together tab under the game's own tabs in the guild window. Our pages lie over the
  content area, with tabs along the top (Arena, Tavern, Games, Stocks, Council, Treasury, Chronicle) and a header
  strip with the page's art. The pages themselves arrive in later versions. Clicking a game tab or closing the
  window hides them; the tab hides while a community is selected.
- `/gtf` opens the tab when the guild window is open, or the next time it opens. A key binding, "Open Guild
  Together", opens the window on the tab.
- **Settings** for the Guild Master: the purse (gold or Marks, asks before switching), the name of the Marks, which
  pages are on, who may do what per rank (each punishment and nine other actions), and whether the court may
  sentence.
- Changes go to the whole guild and every addon checks the sender's rank. A member who was offline catches up at
  login from the member who has the most to give. The pages say how fresh the guild's data is.
- **G0: the start.** The addon loads in Forever and retail and keeps its saved data. `/gtf version` shows the
  version; `/gtf` tells you when you are not in a guild (the guild window tab arrives in G1).
- Every character you log in is remembered with its guild, so your alts count as you.
- Addon messages to the whole guild and to one player, with a queue that waits in dungeons, encounters and
  lockdowns and splits long messages (copied from Journey Together Forever, with the guild channel added).
- Test harness with guilds and the guild channel.
