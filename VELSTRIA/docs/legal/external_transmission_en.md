# External Transmission

<!-- Published text. Reference translation of external_transmission_ja.md (disclosures under Article 27-12 of Japan's Telecommunications Business Act). The Japanese version prevails. -->

*This is an English translation provided for reference. The [Japanese version](/external-transmission) is the official text.*

Under Article 27-12 of Japan's Telecommunications Business Act, {{PUBLISHER_NAME}} ("we", "us") discloses the information about users that the iPhone game "VELSIA: Star Ring Arena" (the "App") sends from the user's device to outside parties.

The App contains no modules that send information to third parties for analytics, advertising or tracking. If we ever add such a module, we will update this page beforehand. In the table below, information is sent to our relay server, to other players' devices in the same room and to devices on the same local network only if you accept the online rules and use the online features (never if you selected the under-13 age group).

## What is sent and to whom

| Recipient | Information sent | Purpose at the recipient | When |
|---|---|---|---|
| Us (relay server, run on cloud services provided by Cloudflare, Inc.) | Friend code, inbox key, friend codes of friends whose online status is checked, friend requests and acceptances (display name), party invitations and replies (display name, room code, room name) | Delivering friend requests and invitations, showing friends' online status, confirming who owns a friend code | Whenever the App is on screen, after you accept the online rules (until you choose Stop Using Online Features) |
| Us (relay server, as above) | Friend code, inbox key, the rank on your device (tier, stars, wins, losses and similar), Ranked match results (match identifier, win or loss, match rating, whether you were MVP) | Calculating and storing your rank | After you accept the online rules: when the App starts, when you accept the rules, and after Ranked matches (until you choose Stop Using Online Features) |
| Us (relay server, as above) | Friend code, inbox key, and your name card (display name, avatar hero, avatar frame, account level, country or region, matches and wins for your 3 most-played heroes, total matches and wins) | Showing your name card to other players and building the leaderboard (name cards and the leaderboard are public) | After you accept the online rules: when the App starts, when you accept the rules, and after a match (only when something changed) |
| Us (relay server, as above) | The friend codes whose name cards are shown, the leaderboard scope, country or region, your friends' friend codes, and your friend code | Showing name cards and the leaderboard | When you open the leaderboard, your friend list and similar screens |
| Us (relay server, as above) | Your current status (in a room, matchmaking, in a match with its mode and start time, viewing results, watching) | Showing your status in your friends' lists (not stored) | While connected to your inbox, when your status changes |
| Us (relay server, as above) | (None; the App only downloads our mail) | Delivering announcements and rewards from us by mail | After you accept the online rules: when the App starts and when it comes back to the foreground |
| Us (relay server, as above) | Friend code, inbox key | Deleting your inbox, rank and name card on the relay server | When you choose Delete Friend Server Data or Delete All Data in Settings > Privacy, and when you choose Stop Using Online Features (rank and name card) |
| Us (relay server, as above) | Room code and online match data (player ID, display name, the hero set as your icon, friend code, chosen hero, battle spells, emblem and skin, inputs, game state and similar) | Setting up a room that others can join by room code, and forwarding data to the other devices in the room (forwarded data is not stored) | While your room is open on the online screen (a room that others can join by room code is set up on the relay server even if you only play on the same Wi-Fi; match data is sent while players who joined by room code are in the room) |
| Cloudflare, Inc. | Information needed to carry the connection, such as your IP address | Providing the connection to the relay server | When connecting to the relay server |
| Devices of other players in the same room | Online match data (as above) | Running and displaying the match | During online matches |
| Devices on the same local network | Room name (which includes your display name), whether a match is in progress, the number of players and spectators, whether spectating is allowed | Showing nearby rooms | While your room is open on the online screen |
| Apple Inc. | Information needed to process In-App Purchases | Processing payments | When you make or restore a purchase |

In addition, if you have turned on "Share With App Developers" in iOS, iOS sends crash reports to Apple, and Apple may provide them to us.

## How the information is handled

What the relay server stores, for how long, and how to delete it are described in our [Privacy Policy](/en/privacy) and on the [Data Deletion and Privacy Choices](/en/privacy-choices) page.

## Our website

Our website (the App's official site) has no tags or analytics tools that send visitors' information to third parties.

Effective date: {{UPDATED_DATE}}
