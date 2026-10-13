# Privacy Policy

<!-- Published text. {{…}} is filled from site/config.json. Have it reviewed by counsel before publishing. Public URL: docs/appstore/metadata/en-US/privacy_url.txt.
     Written for the build with online features (FeatureFlags.lanMatch == true). The Japanese version (privacy_policy_ja.md) prevails in case of conflict. -->

This Privacy Policy explains how {{PUBLISHER_NAME}} ("we", "us") handles information in connection with the iPhone game "VELSIA: Star Ring Arena" (the "App").

## 1. Summary

- Information needed to play, including matches against AI, is stored on your device. We never store your game progress, items or in-game currency balances on our servers.
- The App's online features (online matches, spectating, friends and party invitations) connect only after you accept the online rules (our Community Guidelines and Terms of Service). When you use them, the information described in sections 3 and 4 is sent to the devices of other players in the same room or to a relay server that we operate. The only information the relay server stores is the friend-feature data described in section 4 and the running numbers of room participants described in section 3.2 (deleted 10 minutes after the host closes the room).
- The App does not show advertising, does not analyze your behavior and does not track you across other companies' apps or websites. It contains no analytics, advertising or tracking SDKs.
- We do not sell your information.

## 2. Information stored on your device

The App stores the following information on your device. The items described in sections 3 and 4 are sent when you use the online features. Nothing else is sent to us or to any third party.

| Information | Details | Purpose |
|---|---|---|
| Profile | Display name (player name), owned items and in-game currencies, game progress, settings | Providing the game |
| Age group | The age group you select (we do not ask for your date of birth) | Applying monthly purchase limits by age; checking whether you can use the online features (they are not available under 13) |
| Purchase records | In-App Purchase transaction IDs, dates and the items granted | Delivering purchases, preventing duplicate grants, restoring purchases |
| Match history and replays | Match results and input records. Replays of online matches include the other players' display names | Showing your match history, replay playback |
| Online identifiers | Player ID (a random identifier created by the App), friend code (8 characters), inbox key (a secret string the App creates to prove you own your friend code) and whether you have ever connected to your inbox on the relay server | Joining and rejoining online matches, the friend feature, deleting your inbox on the relay server when you delete your data |
| Friend data | Your friends' friend codes, display names and the dates they were added; friend codes of players you have sent requests to and when you sent them | The friend feature (including withdrawing requests after 14 days) |
| Block list | Friend codes and display names of players you have blocked, and when you blocked them | Refusing requests, invitations and room entry from blocked players |
| Online rules consent | The version of the online rules you accepted | Checking whether you can use the online features |

## 3. Information sent in online matches

### 3.1 What is sent and to whom

When you open the App's online screen, the App creates a room (party) for you. In an online match, the device of the player who created the room (the host) runs the match and exchanges the following information with the other players' devices.

| Information | Sent to | Purpose |
|---|---|---|
| When joining: player ID, display name, the hero set as your icon, friend code, App version, whether you want to spectate | The host's device | Joining the room, returning to the same seat after a disconnection, showing players, friend requests |
| Room state: every participant's player ID, display name, icon and friend code, connection latency, role (host, player or spectator), seat, chosen hero, battle spells, emblem and skin, ready status, the room name and room settings | Everyone in the room, including spectators | Showing and syncing the lobby and hero selection screens |
| Match data: your inputs and the game state | Everyone in the room (spectators receive it with the delay set for the room) | Running the match, correcting desyncs, spectating |

The room name is generated automatically from your display name, in the form "[display name]'s party". Your friend code is sent to the other devices in the room and is shown on screens such as the report and block screens. Other players can send you a friend request from those screens.

### 3.2 How it travels

- **Same network (nearby rooms)**: On the same Wi-Fi or other local network, devices connect to each other directly. This traffic is not encrypted. While your room is open on the online screen, its name, whether a match is in progress, the number of players and spectators, and whether spectating is allowed are visible to other devices on the same network (this uses iOS's Local Network permission). Devices on the same network can join or spectate the room without the host's approval (the host can remove players from the room).
- **Room code**: While your room is open on the online screen, a room that others can join by room code is set up on a relay server that we operate, even if you only play on the same network (the host's device connects to the relay and registers the room code). Traffic with players who join by room code passes through the relay. The connection between each device and the relay is encrypted with TLS, but there is no end-to-end encryption between devices. The relay forwards data to the other devices without interpreting it, and we do not store the content of the traffic or access logs on the relay. For rooms, the only thing the relay stores is a running number assigned to each participant in a room, which is deleted 10 minutes after the host closes the room. Anyone who knows the room code can join or spectate the room without the host's approval.

### 3.3 On other players' devices

Other players' devices show your display name and other information, and automatically save the match as a replay that includes your display name. Players can also share replay files. We do not control information stored on other players' devices and cannot delete it. Please do not use your real name, contact details or other information that identifies you as your display name.

### 3.4 Sharing invitations and links

If you share a room invitation, the room name, room code and a join link are sent to the app or person you choose. If you share your friend link, your friend code and display name are sent.

## 4. Information sent and stored for the friend feature

### 4.1 Connecting to your inbox

To receive friend requests and party invitations, once you have accepted the online rules the App connects to your "inbox" on the relay server whenever the App is on screen, even if the online screen is not open. It sends your friend code and inbox key when it connects. It does not connect while the App is not on screen, or after you choose Stop Using Online Features in Settings > Privacy. Friend codes that we have suspended under the Terms of Service cannot connect to their inbox.

### 4.2 Information stored on the relay server

| Information | Details | Retention |
|---|---|---|
| Hash of your inbox key | Your inbox key converted with SHA-256 (the key itself is not stored), used to confirm who owns a friend code | Until you delete it from the App (section 12). Deleted automatically if you do not connect for one year |
| Time of your last connection | When you last connected to your inbox (updated when you connect and disconnect) | Same as above |
| Pending friend requests and acceptances | Requests and acceptances sent while you did not have the App open (the sender's friend code, the sender's display name and the time received), up to 20 per inbox | Deleted as soon as they are delivered to you. Anything older than 14 days is not delivered and is deleted. Sending the same request again does not extend this period (the App resends a request that has not been accepted only during the 14 days after it was sent) |
| Deletion marker | A marker that prevents a deleted friend code from being used again (it only shows that the inbox was deleted and contains no key hash or requests) | Kept without a time limit |
| Suspended friend codes | The list of friend codes we have suspended after confirming a violation of the Terms of Service or Community Guidelines (stored as a relay server setting) | Until the suspension is lifted |

### 4.3 Information relayed without being stored

- Party invitations (the inviter's display name, the room code and room name) and replies to them (join, decline, join shortly, or busy in a match). If the recipient is not connected, the invitation is discarded rather than delivered.
- Online status checks. To show whether your friends have the App open, the App sends your friends' friend codes (up to 100) to the relay about every 20 seconds and receives back the ones that are connected.

### 4.4 What other players can see

- When you send or accept a friend request, your display name and friend code are delivered to the other player.
- The relay does not check whether two players are friends when answering an online status check, so anyone who knows your friend code (including players you have blocked) can tell whether you currently have the App open. Only share your friend code with people you trust.
- Friend requests, acceptances and invitations from players you have blocked are discarded on your device. Blocked players are not told that you blocked them.

## 5. Relay server operation and service providers

- We operate the relay server on cloud services provided by Cloudflare, Inc. (United States): Cloudflare Workers and Durable Objects.
- To carry the connection, Cloudflare receives information such as your IP address. Our code does not read IP addresses, and we do not record them. For how Cloudflare handles information, see Cloudflare's Privacy Policy (<https://www.cloudflare.com/privacypolicy/>).
- The data in section 4.2 is stored in a Cloudflare data center chosen automatically near the place where that inbox was first accessed, so we cannot specify the country in advance. It may be stored outside Japan.
- We have reviewed the United States' personal information protection framework using the information published by Japan's Personal Information Protection Commission (<https://www.ppc.go.jp/personalinfo/legal/kaiseihogohou/>, Japanese) and take the security measures described in section 10.
- The App's official website is served by Vercel Inc. (United States). The website contains no analytics or advertising, but Vercel receives information such as visitors' IP addresses in order to serve it.
- Through our contracts with the service providers that handle information on our behalf (Cloudflare, Inc. and Vercel Inc.), including their data processing terms, we require them to protect information at a level equal to or higher than this policy, and we do not allow them to use it for any purpose other than the services they provide to us.

## 6. In-App Purchases

Payments are processed by Apple Inc. through the App Store. We do not receive your name, payment method or Apple Account details.
When a purchase completes, the App receives a verified transaction from Apple on your device and uses it only to deliver the purchased item.
See Apple's Privacy Policy (<https://www.apple.com/legal/privacy/>) for how Apple handles your information.

## 7. When you contact us or submit a report

If you email us with a question or a report, we receive your email address, the content of your message and anything else you choose to include or attach.

- Emails created from Settings > Support > Contact Us in the App include the App version, device model, iOS version, your player ID and the display language.
- Problem reports created with "Report" on the match results screen include match information (mode, a value used to reproduce the match, duration, how the match ended, the winning team, the heroes used, kills, deaths and assists, AI difficulty, App and iOS versions, device model and similar). They do not include display names or player IDs.
- Emails created when you report another player from the online screens or the match results screen include the reason and your description, the other player's display name, friend code and player ID, where you met them, the room code, your own friend code, the date and time, and the App and iOS versions. Reports from the match results screen also include a value used to reproduce the match, the match duration and the other player's seat; reports from a party invitation also include the room name.
- In every case you send the email yourself from your mail app and can review or edit it before sending.

We use this information only to respond to you, investigate problems and handle reports (including checking for violations of our Terms of Service and Community Guidelines), and we delete it once it is no longer needed after we have finished handling it.

## 8. Crash reports

If you have turned on "Share With App Developers" in iOS, Apple may provide us with crash reports (diagnostic data that does not identify you), which we use only to fix bugs.

## 9. How we use and share information

We use the information we obtain only to:

1. provide online matches, spectating, friends and party invitations;
2. investigate connection problems and keep the service safe, including dealing with unauthorized connections and abusive behavior;
3. respond to inquiries and reports, and act on violations of our Terms of Service and Community Guidelines; and
4. comply with the law.

We do not share the information we obtain with third parties, except:

1. when we deliver information you send through the online features to the recipients described in this policy (other players in the same room, and the recipients of your friend requests and invitations); or
2. when required by law, when necessary to protect someone's life, body or property and it is difficult to obtain consent, or as otherwise permitted by Japan's Act on the Protection of Personal Information.

## 10. Security

We take the following measures to prevent the leakage, loss or damage of the information we handle:

- Organizational and personnel measures: we have appointed a person responsible for handling information and limit who manages the relay server and handles support email.
- Technical measures: the relay stores inbox keys only as hashes and does not store the content of traffic or access logs. An inbox is deleted only at the request of the device that holds its key. Connections between devices and the relay are encrypted with TLS. Checks for offensive words in display names and room names run on users' devices; the relay does not inspect the content of traffic.
- Physical measures: the relay runs in Cloudflare's data centers, and Cloudflare is responsible for the physical security of the facilities.
- Understanding the foreign environment: see section 5.

## 11. Retention at a glance

| Information | Where | How long |
|---|---|---|
| Information in section 2 | Your device | Until you delete it (deleting the App also deletes it) |
| Running numbers of room participants | Relay server | 10 minutes after the host closes the room |
| Hash of your inbox key and time of your last connection | Relay server | Until you delete it from the App; deleted automatically one year after your last connection |
| Pending friend requests and acceptances | Relay server | Until delivered; at most 14 days after they were received |
| Deletion marker | Relay server | Kept without a time limit (shows only that the inbox was deleted) |
| Suspended friend codes | Relay server (setting) | Until the suspension is lifted |
| Support and report emails | Our email | Until no longer needed after we have finished handling them |

## 12. Deleting your information and your requests

- **All of your information**: Settings > Privacy > Delete All Data in the App deletes your inbox on the relay server (the key hash, the time you last connected and any pending requests) and everything stored on your device. We cannot recover deleted data. Deleting creates a new player ID, friend code and inbox key.
- **Only the relay server data**: Delete Friend Server Data in Settings > Privacy deletes your inbox on the relay server while keeping your game data on your device. No one, including you, can use the deleted friend code again, and a new friend code is created the next time you use the online features.
- **Automatic deletion**: If you can't use the App, for example because you deleted the App or lost your device, your inbox on the relay server is deleted automatically one year after your last connection. Your inbox key exists only on your device, and we can't confirm from a friend code alone that you are the owner, so we do not delete inboxes in response to email requests. Friend requests you sent that are waiting in another player's inbox because they were away (your friend code and display name) are deleted 14 days after they were received. See [Data Deletion and Privacy Choices](/en/privacy-choices) for the steps.
- **Other requests**: You may ask us to tell you how we use your information, disclose it, correct, add to or delete it, stop using or erase it, or stop sharing it with third parties. Email us at the address in section 17. To confirm that you are the person concerned, we may ask about information shown in the App. We do not charge a fee for these requests.
- **Complaints**: You can send complaints or questions about how we handle information to the contact in section 17.

## 13. Minors and children

- Minors should use the App and make purchases only with the consent of a parent or guardian. The App applies monthly purchase limits based on the selected age group (15 and under: JPY 5,000; 16 to 19: JPY 10,000).
- The age group is used only on your device and is never sent to our servers.
- Players who select the under-13 age group cannot use the online features, and the App makes no connections for the online features for them.
- If your child is 13 or older and uses the online features, please review them together and make sure your child does not use a real name or other identifying information as a display name. Your child's information can be deleted in Settings > Privacy on your child's device, and a parent or guardian may make the requests in section 12 for their child's information.

## 14. Users outside Japan

- **EU and UK**: We process information for the online features because it is necessary to perform our contract with you (Article 6(1)(b) GDPR). We rely on our legitimate interests (Article 6(1)(f)) to keep the service safe and to handle inquiries and reports, and on legal obligations (Article 6(1)(c)) to comply with the law. You have the right to access, rectify and erase your data, to restrict or object to processing, to data portability, and to lodge a complaint with the supervisory authority where you live. Providing the information in sections 3 and 4 is necessary to use the online features; without it you cannot use them, but you can still play against AI. We do not use automated decision-making, including profiling. Information is processed in Japan (by us) and in Cloudflare's data centers (including in the United States and other countries). Japan is covered by adequacy decisions of the European Commission and the United Kingdom. Transfers from us to Cloudflare, Inc. and other service providers in the United States are based on the Standard Contractual Clauses adopted by the European Commission (with the UK Addendum for the UK) included in their data processing terms, and, where the provider is certified under the EU-U.S. Data Privacy Framework (including the UK Extension), on that certification. You can obtain a copy of these safeguards by contacting us at the address in section 17 (with commercially sensitive parts removed).
- **California**: We do not sell personal information or share it for cross-context behavioral advertising. Neither the App nor our website tracks users, so we handle information the same way whether or not your browser sends a Do Not Track signal, and no third party tracks you through the App or our website. You can ask to review or correct the information described in sections 2 to 7 as explained in section 12.

## 15. External transmission notice (Japan)

The disclosures required by Japan's Telecommunications Business Act for sending user information externally are on the [External Transmission](/en/external-transmission) page.

## 16. Changes to this policy

We may update this policy when laws change or when we add or change features in the App. We will announce the updated policy and its effective date in the App or on our website.
If a change expands the information we collect or how we use it, we will announce it in advance and obtain consent where required.

## 17. Contact

{{PUBLISHER_NAME}}\
Representative: {{REPRESENTATIVE_NAME}}\
Address: {{POSTAL_ADDRESS}}\
Email: {{SUPPORT_EMAIL}}

Effective date: {{EFFECTIVE_DATE}}\
Last updated: {{UPDATED_DATE}}
