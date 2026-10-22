# Data Deletion and Privacy Choices

<!-- Published text. Set as the "User Privacy Choices URL" in App Store Connect (metadata/<locale>/privacy_choices_url.txt). {{…}} is filled from site/config.json. The Japanese version (privacy_choices_ja.md) prevails in case of conflict. -->

This page explains where the data of "VELSIA: Star Ring Arena" (the "App") is stored, how to delete it, and how to make requests to {{PUBLISHER_NAME}} ("we", "us"). For details, see our [Privacy Policy](/en/privacy).

## 1. About accounts

The App has no account sign-up or login. For the online features, the App automatically creates a player ID, a friend code and an inbox key on each device. You can delete these, together with your inbox and rank on the relay server, from within the App (sections 3 and 4).

## 2. Where your data is stored

| Where | Data | How to delete it |
|---|---|---|
| Your device | Profile (display name, items, in-game currencies, progress, settings), age group, purchase records, match history and replays, player ID, friend code, inbox key, friend list, blocked players | Delete All Data in the App (section 3) |
| Our relay server (your inbox) | Hash of your inbox key; the time you last connected; friend requests and acceptances waiting for you (the sender's friend code and display name, kept for 14 days after they were received) | Delete Friend Server Data or Delete All Data in the App (sections 3 and 4). Deleted automatically one year after your last connection |
| Our relay server (your rank) | The rank you stored after accepting the online rules (tier, stars, wins, losses and similar), the results of your last 50 matches, and the hash of your inbox key | Delete Friend Server Data or Delete All Data in the App (sections 3 and 4). Not deleted automatically |
| Our relay server (your account) | Your whole profile stored after you set a password or linked Game Center, a salted hash of the password-derived value, and the link to your Game Center player ID | Profile > Account > Delete Account, Delete Friend Server Data or Delete All Data in the App. Not deleted automatically |
| Our relay server (your name card and leaderboard entry; public) | Your name card (display name, avatar hero, avatar frame, level, country or region, matches and wins for your 3 most-played heroes, total matches and wins), your current rank, your best rank this season and this season's wins and losses | Deleted together with your rank (Delete Friend Server Data, Delete All Data, Stop Using Online Features). Not deleted automatically |
| Our relay server (other players' inboxes) | Friend requests and acceptances you sent that are waiting because the other player was away (your friend code and display name) | Deleted automatically 14 days after they were received (section 4) |
| Other players' devices | Replays of matches you played together (including your display name); the friend lists of players who added you as a friend | We cannot delete this |
| Our email | Support and report emails | Email request (section 6) |
| Apple | Your App Store purchase history | Managed by Apple (section 7) |

## 3. Deleting all of your data

1. Open Settings > Privacy in the App.
2. Choose Delete All Data and continue on the confirmation screen.
3. At the final confirmation, choose Delete Everything.

If you have used the online features, the App first deletes your inbox on the relay server (the key hash, the time you last connected and any pending requests) and your rank there; this needs an internet connection. Then your profile, items, in-game currencies, match history, replays, settings, player ID, friend code, friend list and blocked players are deleted from your device, and the App returns to its first-launch state.

- If your data on the relay server can't be deleted (for example, because you are offline), you can try again or delete only the data on your device. If you delete only the data on your device, your inbox on the relay server is deleted automatically one year after your last connection, but your rank may remain.
- Deleting (uninstalling) the App deletes the data on your device but not your inbox or rank on the relay server (the inbox is deleted automatically one year after your last connection). Use Delete All Data or the steps in section 4 first.
- We cannot recover deleted data. If you need it, export a backup from Data Transfer first.
- Your paid gem balance is also lost and cannot be restored. Purchases that can be restored, such as Star Pass Premium, can be recovered with Restore Purchases in the Store.
- After deletion, a new player ID, friend code and inbox key are created, and your friend list is empty.

## 4. Deleting only the data on the relay server

You can delete only the data on the relay server and keep your game progress.

1. Open Settings > Privacy in the App.
2. In the Online Features section, choose Delete Friend Server Data, then choose Delete on the confirmation screen.

Your inbox on the relay server (the key hash, the time you last connected and any pending requests) and the rank you stored there are deleted, and the online features are turned off (the rank on your device is kept).

- No one, including you, can use a deleted friend code again (so no one else can take over your friend code). The next time you use the online features, a new friend code is created.
- The friend list and the friend requests you sent are also deleted from your device. Send your friends new requests with your new friend code. Your list of blocked players is kept.
- Friend requests you sent that are held in other players' inboxes (your friend code and display name) are deleted automatically 14 days after they were received. The App resends a friend request that has not been accepted only during the 14 days after you sent it, and then withdraws it.
- If you open the App with a friend code whose inbox was deleted on another device, or deleted because it was not used for a year, the App automatically creates a new friend code.

If you can't use the App, for example because you lost your device: your inbox key exists only on that device, and we can't confirm from a friend code alone that you are the owner, so we cannot delete an inbox or rank at your request. Your inbox on the relay server is deleted automatically one year after your last connection, and pending requests 14 days after they were received (your rank is not deleted automatically). If you have a backup from Data Transfer, import it on your new device and then follow the steps in this section.

## 5. If you don't want to use the online features

- You can play against AI without using the online features. The online features become available when you open Online on the Home screen and accept the Community Guidelines and Terms of Service. Until then, the App makes no connections to the relay server or other players' devices for the online features. If you selected the under-13 age group, you cannot use the online features.
- Once you have accepted, the App connects to your inbox on the relay server whenever it is on screen, so that it can receive friend requests and invitations. It also stores your rank on the relay server when it starts and after Ranked matches. When you open the online screen, your room (party) is created: it is shown to other devices on your network, and a room that others can join by room code is set up on the relay server. If you don't open the online screen, no room is created.
- To stop using the online features, choose "Stop Using Online Features" in Settings > Privacy. You leave any room and the App stops connecting to your inbox and sending your rank. Your friend list stays on your device, and the next time you open Online you can start again by accepting the rules. To also delete your data on the relay server, follow the steps in section 4.
- If you don't play on the same network (nearby rooms), you can turn the App off in your iPhone's Settings > Privacy & Security > Local Network.
- The App does not track you and does not send information for advertising or analytics.

## 6. Other requests

You may ask us to tell you how we use your information, disclose it, correct, add to or delete it, stop using or erase it, or stop sharing it with third parties. Email {{SUPPORT_EMAIL}} with your request and your friend code. We do not charge a fee. To confirm that you are the person concerned, we may ask about information shown in the App. You can ask us to delete your support and report emails in the same way.

Even if you ask us to delete your information, we may keep records that the law requires us to keep (for example, records of how we handled a request from the authorities, and transaction and accounting records), and records needed to exercise or defend legal rights (including records of enforcement actions), only for as long as necessary.

## 7. Purchase history and refunds

Your App Store purchase history and refunds are managed by Apple. We store purchase records (such as transaction IDs) only on your device, so there are no purchase records for us to delete on our side. Request a refund through Apple's "Report a Problem" page (<https://reportaproblem.apple.com>).

## 8. Requests from parents and guardians

Your child's data can be deleted by following the steps in sections 3 and 4 on your child's device. A parent or guardian can also make the requests in section 6 for their child's data. Please include your child's friend code and state in your email that you are their parent or guardian. Information for parents is on the [For Parents](/en/parents) page.

Effective date: {{UPDATED_DATE}}
