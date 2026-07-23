# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [v3.8.3] - 2026-07-23

### Features

- Add a **Hide Feed Descriptions** toggle under **Settings > Apollo Reborn > Features > Subreddits** — hides the subtitle lines under the built-in feed rows (Home, Popular Posts, All Posts, Moderator Posts) in both the classic and modern list styles, independent of the Subreddit List Enhancements master ([#692](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/692): @icpryde)
  - The same PR also refines the modern subreddit list: pinned section headers stay transparent instead of becoming a solid band over the rows scrolling beneath them, the A-Z index letters ride above the section-header bands in classic mode, and turning **Subreddit List Enhancements** off now strips the modern chrome live instead of waiting for a relaunch

### Fixes

- Fix a **crash on posts with link previews** — an oversized inline link-preview image could be downscaled synchronously deep inside a table row-layout pass (often triggered by a vote or a comment-sort switch) and overflow the layout stack; the resize now runs off the layout stack with a per-image cache, so previews keep showing their loaded image while the resized bitmap is prepared ([#686](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/686): @icpryde)
- Fix **translated comments flickering when you vote** — voting no longer flashes the original-language text for a frame, bounces the row height, or shifts the avatar; the settled translated body stays put while the arrow and score update, and the fix holds up through scrolling and long-press context menus ([#676](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/676): @icpryde)
- Fix **user flair issues on API-key-free accounts and just-posted comments** ([#670](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/670): @icpryde)
  - The flair editor now shows each community's real per-sub emoji limit instead of a flat 10, and going over it warns you (with Keep Editing / Save Anyway) instead of silently letting Reddit drop the extra emoji
  - Your own flair pill now appears on a comment the instant you post it, rather than only after a pull-to-refresh

## [v3.8.2] - 2026-07-23

### Features

- Add **configurable AI summary depth** under **Settings > Apollo Reborn > Apollo AI** — a **Minimum Post Length** slider (50–300 words, how long a text post must be before it's worth summarizing) plus independent **Post/Link Detail** and **Discussion Detail** levels of Brief, Balanced, or In-depth ([#687](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/687): @icpryde)
  - Balanced keeps the summaries you already know; Brief trims them to 1–2 concise sentences; In-depth adds useful context without reproducing the source. The length threshold applies only to Reddit text-post bodies — linked articles stay eligible regardless
  - A configured **Cloud Model** honors the same detail levels (with a larger input budget on capable models), and cached summaries regenerate when you change a level or switch models
  - The detail sliders respond to a tap as well as a drag

### Fixes

- Fix the **Liquid Glass scroll-edge fades** going transparent during a swipe-back — the blurred bands behind the floating top pills and the bottom bar now stay put through the whole gesture instead of flicking see-through and exposing crisp text ([#693](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/693): @icpryde)
  - Hardened against overlapping navigation transitions, so a rapid back-and-forth can't drop another screen's fades mid-swipe

## [v3.8.1] - 2026-07-20

### Features

- Add an **Icon-Only Tab Bar** toggle under **Settings > Apollo Reborn > Profiles** — hides every tab title while keeping the icons, navigation, and accessibility names, applies immediately, and persists across launches ([#691](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/691): @icpryde)
  - Coordinates with **Hide Username on Tab Bar**: enabling icon-only supersedes it and fades its row; turning icon-only off re-enables the row without flipping it back on
- Improve **Settings** organization — **Open Links in** and **Open Videos in YouTube App** now live under **Open in App**, and **Hide Username on Tab Bar** under **Profiles**; the rows write the same native keys (nothing resets) and settings search finds them at their new homes ([#695](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/695): @icpryde)
  - The Settings search bar now scrolls away with the list and reveals on a pull back to the top, like a native iOS search bar

### Fixes

- Fix **inline comment images rendering tiny** after collapsing and re-expanding a comment — the image bitmap could be captured while the row was momentarily the wrong size — and stop the reload flicker loop when voting on a comment with an inline image ([#675](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/675): @icpryde)
- Fix the **trailing button pill leaning left** on Liquid Glass — the trophy + ••• group on feeds and sort + ••• in comments now centers with even padding, with or without the translation globe ([#671](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/671): @icpryde)

## [v3.8.0] - 2026-07-19

### Features

- Revamp **Settings** — the Apollo Reborn screen is now a compact, task-oriented hub (Setup, Features, Data, Advanced, Privacy, About) with grouped feature screens, modern icon tiles, and duplicate controls removed ([#637](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/637): @jordanearle)
  - Add **settings search**: pull down on Apollo's Settings screen to search every Reborn and native setting by name, with breadcrumbs showing where each result lives and `apollo://reborn/settings/…` deep links
  - Settings that belong with Apollo's own controls now live in their native families — Open in App under **General > Open Links**, Picture-in-Picture under **General > Media**, Translation and Saved Categories under **General > Other**, Color Flairs under **Appearance > Flair**, Tag Filters under **Filters & Blocks**
  - Replace coupled toggle pairs with clear three-way pickers for AI summary behavior, Translation mode, and Deleted Comments mode, with toast confirmations and a Setup footer that disappears once your Reddit key is configured
  - Add **Feature Requests** (the Reborn board, with voting) and a privacy-conscious **Bug Reports** form with version prefill and an explicit opt-in Attach Logs step, both under **Settings > Apollo Reborn > About**
- Add **native poll voting and creation** behind the new off-by-default **Settings > Apollo Reborn > Polls** switch, using a per-account reddit.com web session for the same endpoints Reddit's own web client uses ([#643](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/643): @jordanearle)
  - Tap a poll option to vote — your choice renders immediately and authoritative totals fill in on their own, with clean rollback if Reddit rejects the vote
  - Create polls from the post composer's new **Poll** segment (title, 2–6 options, duration)
  - Poll-only web sessions are isolated from the API-key-free transport, cookie and token material stays out of caches and diagnostics, and every hook stays dormant while the switch is off

## [v3.7.2] - 2026-07-18

### Fixes

- Fix **Link Previews** showing a mangled URL-slug title and the site's favicon for articles on bot-protected news sites (expresso.pt and other DataDome/Cloudflare-fronted sites) — metadata is now fetched the way Safari would and retried when a bot wall answers, so cards get the real headline, photo, and description; previously-broken cards heal themselves on next view, and the fetcher no longer sends your Reddit API user agent to third-party websites (#18)
  - When a site still can't be fetched, the fallback title is cleaner — leading dates and trailing content-id hashes are stripped from the URL slug
- Fix **long headlines hiding the card subtitle** — link cards whose title runs long now show a third title line and keep a one-line description, instead of truncating the title at two lines and dropping the description entirely (#18)

## [v3.7.1] - 2026-07-17

### Features

- Add the **Synthwave** Liquid Glass app icon to the Community section of the icon picker ([#663](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/663): @IllIIllIllIllII)

### Fixes

- Fix **login not persisting on sideloads** — signed-in accounts silently vanished on sideloaded builds because the account was split across keychain access groups and Apollo's scoped read missed it; the account is now recovered by reading across every access group, the underlying protection-class mismatch is healed so later writes land where the read looks, and API-key-free sign-in no longer creates an unreadable account keychain item in the first place ([#677](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/677): @jordanearle, [#681](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/681): @DeltAndy123, [#682](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/682): @DeltAndy123, [#683](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/683): @jordanearle)
- Fix **hold-for-speed staying stuck** after scrubbing a video — the fast-forward speed no longer sticks on once you've dragged the video scrubber ([#667](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/667): @icpryde)
- Speed up **full Community Highlights loading** ([#661](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/661): @icpryde)
- Fix the **Mod Queue filter menu** anchoring on Liquid Glass — the filter menu now attaches to its button instead of drifting away ([#679](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/679): @JeffreyCA)
- Fix **Search tab** suggestions padding and the **Random Subreddit** icon's stroke weight ([#680](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/680): @icpryde)
- Recognize more **inline sports clips** — streama.in and streamff.link are now handled, and moved dubz/streamff CDNs are followed so their goal/highlight clips keep playing inline ([#665](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/665): @icpryde)
- Fix the **Apollo Classic** app icon assets on iOS 27 ([#666](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/666): @IllIIllIllIllII)

## [v3.7.0] - 2026-07-16

### Features

- Add **Hidden, Removed & Deleted content recovery** to profiles — a new eye-slash button on any profile screen (yours or another user's) surfaces posts and comments that are hidden from the account's own listing, removed by mods/AutoMod/Reddit, or deleted by the author, using Reddit's own API and the Arctic Shift archive rather than scraping ([#633](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/633): @ostechgit)
  - Tapping it opens a Posts vs Comments picker, then a results screen where each item is labeled **Hidden** (still live — opens natively in-app), **Removed** (archived title/body shown, with a Moderator / AutoMod / Reddit Admins qualifier when known), or **Deleted** (archived title/body shown); the archived view has Share and Open in Arctic Shift buttons
  - Results are cached per user for an hour, transient network failures never poison the cache or close the sheet, and posts with non-ASCII permalinks now open correctly
- Add **per-account sign-in mode** — the account switcher and the Custom API screen now tell the truth about each account instead of showing one global state ([#603](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/603): @icpryde)
  - Switcher rows read **API key · default**, **API key · custom**, **API-key-free**, or **No API key set** instead of a blanket "Web session"
  - **Settings > Apollo Reborn > Custom API** now follows the active account: the API-Key-Free switch, Redirect URI, and key fields reflect (and edit) the account you're actually looking at, while a keyless account dims its unused key fields
  - Interactive OAuth sign-in clears any leftover web session for that username, and a keyless row's ⋯ menu gains **Use API Key Instead…** to un-stick an account that was silently migrated to keyless
- Enable **user flair without a Reddit API key** — picking, saving, and hiding your flair now works in API-key-free mode through Reddit's cookie-authenticated selector, with your current flair recovered from the subreddit sidebar and marked with Apollo's native checkmark ([#653](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/653): @icpryde)
- Add the **Apollo Classic** Liquid Glass app icon, inspired by the original Apollo icon, to the Community section of the icon picker ([#660](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/660): @IllIIllIllIllII)

### Fixes

- Fix **missing inline images in API-key-free feeds** — direct Reddit images whose keyless listing item omitted its media metadata fell back to a link card; the missing fields are now hydrated from the post's old-Reddit comments response (up to six per response, fetched in parallel) so the image renders inline with the correct aspect ratio ([#654](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/654): @icpryde)
- Fix **Auto Hide Read Posts** not hiding read posts on **Popular** and **All** when "Disable in Subreddits" is also on — Apollo models those aggregate feeds as the r/popular and r/all subreddits, so the subreddit gate wrongly skipped them; they now auto-hide like Home while real subreddits still honor the toggle ([#649](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/649): @icpryde)
- Fix **Deleted Comments** recovery reliability — failed or throttled Arctic Shift fetches no longer poison the cache (so the same threads stop staying broken), more comments recover on popular posts, recovered bodies render full markdown instead of raw `[text](url)`, and the row re-measure no longer animates the wrong way during a collapse ([#630](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/630): @icpryde)
- Fix **posts that wouldn't translate** — long bodies are now split into sentence-bounded chunks so they no longer blow past the provider's URL limit and fail wholesale, and the Apple provider's language pre-detection is length-adaptive so clearly-foreign short bodies stop getting dropped ([#629](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/629): @icpryde)
- Fix comments **flashing blank on every up/down-vote** — voting (and returning from the app switcher) forced visible cells to re-display before their backing store was ready; translated comments additionally flashed their original language, bounced in height, and showed raw `![gif](…)` tokens, all now committed in the same frame ([#627](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/627): @icpryde)

## [v3.6.1] - 2026-07-15

### Features

- Add a **tab bar corner picker** for Hide Bars on Scroll on Liquid Glass — the collapsed tab-bar pill no longer has to sit bottom-left; the native **Settings > General > Hide Bars on Scroll** switch is now a small **Left / Right / Off** menu ([#645](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/645): @icpryde)
  - The pill rides the normal minimize/expand animation on either side; non-Liquid-Glass builds keep the plain switch
- Improve **feed scrolling performance** — language-detection results are cached, per-row translation scans are coalesced, failing translation providers back off before retrying, and verbose diagnostics are compiled out of the scrolling hot path (a reproducible ~100ms scroll freeze is gone) ([#652](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/652): @icpryde)

### Fixes

- Fix **Recently Read** not bumping revisited posts to the top (or needing two pull-to-refreshes to do it) — marking a post as read is now deterministic instead of racing a 2-second timer, the screen refreshes itself when you return to it, and refreshes happen in place instead of clearing to a spinner; also fixes a data race and several latent bugs in the screen's data flow ([#632](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/632): @JeffreyCA)
- Fix **bulk hide/unhide silently dropping 50 posts** — hiding more than 50 posts at once miscounted its request batches and one whole batch of 50 never reached Reddit, so those posts kept coming back on the next refresh ([#650](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/650): @icpryde)
- Fix **Translation** marking languages on your Don't Translate list — comments and titles in a skipped language no longer get a "🌐 Translated from…" marker or a do-nothing Translate affordance, and **Show translation** no longer disappears after collapsing and expanding a comment ([#628](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/628): @icpryde)
- Fix the compact **🌐 language marker** rendering oversized on media-heavy posts — it now always matches the size of the other info-row stats, and an oversized marker snaps back in place once the row is on screen ([#616](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/616): @icpryde)
- Fix the **comment-count jump** opening the post at the top and then lurching down — tapping a post's comment count now slides in already anchored on the action bar, with the discussion right below ([#626](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/626): @icpryde)
- Fix **notification account registration** failing with "missing required credentials" against self-hosted backends — Reddit API credentials now ride request headers on account upserts, where Apollo's upload tasks can't drop them ([#642](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/642): @nickclyde)

## [v3.6.0] - 2026-07-13

### Features

- Add separate **Light & Dark theme assignments** to the Theme Manager — pair a different custom or gallery theme with each appearance instead of one theme for both ([#651](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/651): @jordanearle)
  - Opt-in from **Settings > Apollo Reborn > Theme Manager**; once enabled, applying a theme asks for Light Mode, Dark Mode, or Both, sun/moon indicators show each theme's assignment, and assignments survive copying a gallery theme into My Themes
- Add an **Info Row** settings screen to customize the post stats strip (score / % upvoted / comments / time / edited / 🌐) ([#613](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/613): @icpryde)
  - Pick which icons respond to a tap (**Upvote**, **Comments**, **Translation**) and how the detail icons reveal their info: a dismissable **Popup** — which finally makes the tap-for-full-date-and-time behavior optional ([#599](https://github.com/Apollo-Reborn/Apollo-Reborn/issues/599)) — or a self-fading **Overlay** card
  - The press-and-hold **Magnifier** toggle moves here from General, and the magnifier no longer renders blank on very long posts
- Add **more inline video hosts** — goal and highlight clips from the hosts big sports subreddits use (streamin, streamain, streamff, bangr, dubz, dropr, MLB produced clips) now play as real inline videos exactly like Streamable, with autoplay rules, fullscreen, mute handling, hold-for-speed, and PiP ([#596](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/596): @icpryde)
  - Toggle it under **Settings > Media > Sports Clip Links Play Inline** (on by default); copy and share still use the original link

### Fixes

- Fix **Inline Media crashes and scroll lag** — a post linking the same imgur album twice crashed the app, leaving a post mid-resolve could crash it a moment later, and busy media-heavy threads (like game megathreads) could crash during layout; the same rework removes several scroll-performance hotspots so album-heavy posts scroll noticeably smoother ([#638](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/638): @JeffreyCA)
  - Also brings the fullscreen **PiP button** to inline videos, and the mature-content blur no longer mispredicts when multiple signed-in accounts disagree on the setting
- Fix the **signed-in Reddit account getting wiped** seconds after signing in — an iCloud-Keychain-synced credentials item made Apollo's keychain read miss it and delete the account on the spot ([#579](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/579): @ostechgit)
- Fix the app **freezing when composing a Media post** on iOS 26 — tapping **"Text (optional)"** pegged the main thread in an endless nav-bar layout loop until the watchdog killed the app ([#623](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/623): @icpryde)
- Fix **AI Summaries**' "Discussion so far" card getting stuck on *Summarizing…* forever in **Tap to Summarize** mode (and not reacting to taps); post summaries are also offered on shorter posts now (200+ words, down from 300) ([#610](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/610): @icpryde)
- Fix **custom theme fonts** breaking markdown — code blocks stay monospaced under every theme font, and italics render actually slanted under SF Pro Rounded ([#640](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/640): @DeltAndy123)
- Fix **theme colors** on separators and search — table separators and comment/post-header dividers now follow the theme's Separators color, and search fields keep the neutral input background ([#648](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/648): @jordanearle)
- Fix the **Helios Cryo Halo icon** artwork and sort the Helios variants alphabetically in the icon picker ([#617](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/617): @IllIIllIllIllII)
- Fix the **Anonymous Install Count** heartbeat forgetting its monthly token and opt-out choice on reinstall — both now live in durable storage, with existing opt-outs migrated ([#612](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/612): @jordanearle)

## [v3.5.2] - 2026-07-11

### Fixes

- Fix **Color Flairs** losing their color after backgrounding the app — a flair's colored pill snapped back to Apollo's default grey (with the wrong text color) after you switched away and reopened Apollo, only recovering once you scrolled it off-screen and back; the color now holds across background/foreground and light/dark changes without a scroll ([#624](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/624): @icpryde)
- Fix **X/Twitter links** always opening in the system browser instead of honoring your **Open Links in** setting — tweet links now open the X app when it's installed, and otherwise respect your In-App Safari choice like every other link ([#625](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/625): @icpryde)

## [v3.5.1] - 2026-07-09

### Features

- Add a **Remember Post Sort** option — remember the comment sort you pick per post instead of per subreddit, so switching one thread to e.g. Controversial no longer changes what every other post in that subreddit opens with ([#570](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/570): @icpryde)
  - Opt-in from **Settings > General > Comments**, right under its sibling **Remember Subreddit Sort**; the two toggles are mutually exclusive (enabling one turns the other off), and a remembered post sort beats everything, suggested sort included

### Fixes

- Fix **Autoplay Inline GIFs** set to Never (or WiFi Only) only stopping some GIFs — GIFs from slow hosts kept animating until their static cover finished downloading, and pausing a GIF wiped its own play-button state ([#602](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/602): @icpryde)
  - Paused GIFs now show a proper **Tap to Play** overlay instead of opening the media viewer, changing the autoplay setting now applies to GIFs already on screen, and Apollo-native inline animated media respects the same gate
  - The inline media options now live in their own **Settings > Apollo Reborn > Inline Media Settings** screen, with a live preview and an inline size slider
- Fix the **Inline Media size slider** getting stuck mid-drag or swiping back to the previous screen when grabbed at its far-left 50% position — a drag that starts on the slider can no longer trigger Apollo's full-width swipe-back ([#611](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/611): @icpryde)
- Fix **Tag Filters** double-blurring tagged media the Reddit account's **Blur mature (18+) images** setting was already blurring — Apollo's native "tap to view" overlay now wins and the tweak's overlay stands down, including on compact-mode thumbnails ([#585](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/585): @JeffreyCA)
- Explain the empty **User Flair** screen on API-key-free accounts — Reddit only serves flair over OAuth, so instead of a blank picker those accounts now get a short notice saying an API key is needed for flair ([#606](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/606): @icpryde)
- Remove the **"Subscribe to r/ApolloApp?" pop-up** that appeared on every fresh sign-in ([#614](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/614): @icpryde)

## [v3.5.0] - 2026-07-08

### Features

- Add **Bark notification delivery** so free-Apple-ID sideloads finally get push notifications — Apple never grants those builds the push entitlement, so replies, PMs, and watcher alerts are relayed through the free [Bark](https://apps.apple.com/app/id1403753865) app instead ([#578](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/578): @nickclyde)
  - Turn on **Bark Delivery** and paste your Bark push URL in **Settings > Apollo Reborn > Notification Backend**, then send a test notification from the same screen; tapping a notification deep-links back to the right thread or your inbox
  - Notifications carry your selected Apollo app icon and match Apollo's in-app notification sound, and paid-certificate installs can switch between native push and Bark freely
- Improve **Translation** with per-item language markers, tap-to-toggle, and an opt-in **Tap to Translate** mode, on all providers (Google / LibreTranslate / Apple) ([#564](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/564): @icpryde)
  - Translated comments get a small *🌐 Translated from Spanish* line and post titles a compact *🌐 PT* marker on the stats row; tapping one flips just that item between translation and original (a post's title, body preview, and link card flip together)
  - **Tap to Translate** in **Settings > Translation** stops auto-swapping entirely — comments show a tappable *🌐 Translate* line and translate on demand, with background prefetch so taps feel instant
  - New **Details on Comments & Posts**, **Details on Titles**, and **Match App Colour** toggles control the markers; also fixes genuinely-foreign Title-Case titles being mistaken for proper nouns and left untranslated
- Show the **Picture-in-Picture button** in the fullscreen player for spoiler- and NSFW-tagged videos — those posts never autoplay inline, so PiP is safe there even with autoplay on ([#584](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/584): @JeffreyCA)
- Add eight **Helios Liquid Glass icon variants** — Helios, Halo, Cryo, Cryo Halo, Parallax, Parallax Halo, Ultra, and Ultra Halo ([#590](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/590): @IllIIllIllIllII)
- Add an **Anonymous Install Count** heartbeat with a one-tap opt-out in **Settings > Apollo Reborn > Privacy** ([#589](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/589): @jordanearle)
  - At most once a day it sends the app version, build variant, iOS version, and a random token that rotates monthly — no IP is logged or stored, no account details or per-feature tracking, and data is auto-deleted after ~13 months, as spelled out in the privacy policy

### Fixes

- Fix **API-Key-Free Mode** sessions going stale a few times a day — rotated Reddit cookies are now captured back into the stored session, an expired-looking session silently re-harvests from the login browser before ever prompting, and rate limits are no longer misread as session expiry ([#562](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/562): @nickclyde)
  - Also restores keyless image uploads to Reddit's own CDN instead of falling back to Imgur, and fixes composer and chat issues in this mode
- Fix **native menus** on Liquid Glass builds popping in with a plain fade — they now bloom out of the tapped button as a glass bubble and morph back into it on dismissal, matching native iOS 26 menus ([#600](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/600): @icpryde)
- Fix **Hide Bars on Scroll** stuttering on non-Liquid-Glass builds — the navigation and tab bars no longer pop back fully visible for a beat before actually hiding ([#598](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/598): @icpryde)
- Fix **Bluesky and Twitter link cards** whose long post text painted past the card background over the post's info row, and crop tall preview images from the top so faces stay in frame ([#577](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/577): @icpryde)
- Fix **search result rows** stuck at full hero height with a blank gap below when a link preview resolves to a compact card ([#597](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/597): @icpryde)

## [v3.4.1] - 2026-07-06

### Fixes

- Fix **AI Summaries** answering in the thread's language instead of yours — cloud-generated summaries now always respond in your device's language (script-aware, e.g. Simplified vs Traditional Chinese), matching how on-device summaries always behaved (#5)
  - Also fixes rare corrupted output on non-English threads where some cloud models mixed in characters from other writing systems
  - Changing the device language now regenerates cached summaries in the new language

## [v3.4.0] - 2026-07-05

### Features

- Add a **Cloud Model backend for AI Summaries** in **Settings > Apollo Reborn > Apollo AI > Cloud Model** — bring your own OpenAI-compatible API key (OpenAI, OpenRouter, Groq, or a local server) and summaries are generated by your configured model first, falling back to on-device Apple Intelligence if the cloud fails (#1: @paradoxally)
  - A configured cloud model enables AI Summaries on devices **without Apple Intelligence** (pre-iOS 26), raises the input limits (up to 40 representative comments and much longer posts and articles per summary), and the summary card's caption now names the model that generated it (e.g. `gpt-5.4-mini` — the new default — or `Apple Intelligence`)
  - Streams tokens live, transparently retries parameter-shape rejections from newer models (e.g. `gpt-5.4-mini`), and requires HTTPS endpoints (plain HTTP is allowed only for local network addresses); the Apollo AI privacy footers now spell out exactly what is sent — and that nothing leaves the device without a key
- Add **Theme Manager v2** — a full rearchitecture of custom themes with a single **Themes hub** (Current, Create, Browse, My Themes, Imported, Options) replacing the separate Themes / Theme Builder entries ([#558](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/558), [#576](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/576): @jordanearle)
  - Browse a **Theme Gallery** of 50 presets (Dracula, Catppuccin, Gruvbox, Nord, Tokyo Night, …) compiled into the binary, with theme data credit to @harshb16
  - Create themes from scratch, by **AI**, or by import; custom **fonts** support; themes compile to the same runtime form as Apollo's built-ins
  - Share and import a theme as a **single image** — a mock Apollo post painted in the theme's colours with a scannable QR card, alongside JSON export/import ([#581](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/581): @jordanearle, original implementation @icpryde)
- Overhaul **Deleted Comments** into its own settings sub-screen with three modes — **Always Show**, **Tap to Show**, and a new **Passive** per-thread mode — plus a quick **Show/Hide Deleted Comments** shortcut in the comments **⋯** menu ([#572](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/572): @icpryde)
- Add **Follow New Live Comments** for the Live Update comment sort — when you're at the live edge the newest comment stays pinned to the top, and when you scroll away your reading position is anchored while a floating **"N new comments"** pill offers a jump back to the newest ([#535](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/535): @icpryde)
- Add an **Open in App** settings screen gathering per-service link handling in one place — Steam, YouTube, GitHub, X, and Bluesky links can open in their apps, plus a **Default Browser** picker (In-App Safari or your iOS default) ([#547](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/547): @icpryde)
- Improve **AI Summaries open behavior** — **Tap to Summarize** now opens the card by itself once the summary is ready (no second tap), a new **Open Summaries Automatically** toggle expands auto-generated cards on their own, cards reopen in the state you left them, and cached summaries expire so stale ones regenerate ([#532](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/532): @icpryde)
- Add **Comment Link Host** — attach images to comments as plain Imgur / Img Chest links instead of embedded uploads ([#573](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/573): @icpryde)
- Make the post **stats row** easier to hit — tapping the comment bubble now opens the thread scrolled straight to the discussion, and holding the row raises a **magnifier loupe** to pick the exact stat ([#566](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/566): @icpryde), with refined loupe activation and the selection pill matching your theme ([#586](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/586): @JeffreyCA)
- Make all tweak-drawn UI (settings screens, GIF picker, sign-in buttons, AI summary cards, follow pill, …) follow the active **theme accent** instead of defaulting to blue, with legibility guards for near-white accents ([#586](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/586): @JeffreyCA)
- Make **Hold for Video Speed** configurable — choose the held-down playback speed and toggle the gesture on or off ([#545](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/545): @icpryde), with a haptic tap when the speed engages ([#531](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/531): @icpryde)
- Let **Picture-in-Picture** start from the fullscreen player when autoplay is off, with audio-session fixes so PiP audio behaves ([#569](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/569): @JeffreyCA)
- Support **Streamable and Redgifs** posts in **Share as Video** ([#540](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/540): @icpryde)
- Add a **Public Sticky from Subreddit** option when removing a post as a moderator ([#537](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/537): @icpryde)
- Add a **Show Detailed Profiles** toggle ([#536](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/536): @icpryde)
- Add an **LGBTQ Liquid Glass icon set** ([#529](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/529): @lilacvibes)

### Fixes

- Fix **Show Deleted Comments** freezing threads and rendering oversized text ([#541](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/541): @icpryde), fix an intermittent crash in its live-font capture ([#563](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/563): @nickclyde), and make the warning shown when enabling it clearer ([#565](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/565): @icpryde)
- Fix the **AI summary card** rendering as an empty box when revisiting a tapped card ([#544](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/544): @icpryde)
- Fix **Theme hub** ambient-theme inheritance, search and vote-arrow theming, and mono font sizing ([#580](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/580): @jordanearle)
- Recognize **modern Redgifs subdomains** (e.g. `v3.redgifs.com`) so those posts play inline again ([#568](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/568): @icpryde)
- Fix **Share as Image** on shorter phones — the Share button no longer sits off-screen, and gallery posts render a collage when **Include Post Details** is on ([#553](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/553): @icpryde)
- Fix **multi-image Img Chest album posting** ([#554](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/554): @icpryde)
- Fix spurious **"REMOVED BY MOD"** chips appearing on non-removed content such as sidebar stats and bylines ([#516](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/516): @icpryde)
- Fix **comment avatars** loading intermittently and speed up their loading ([#530](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/530): @icpryde)
- Dock the **iPad floating tab bar** at the bottom of the screen ([#557](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/557): @icpryde)
- Improve the **subreddit feed search bar** under Liquid Glass ([#534](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/534): @icpryde)
- Fix **modmail conversation layout** under Liquid Glass ([#543](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/543): @icpryde)
- Highlight **subreddit-list rows** on tap regardless of Modern Dividers / List Enhancements ([#556](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/556): @icpryde)
- Show the subreddit's **real emoji limit** in the user flair editor instead of a flat /10 ([#533](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/533): @icpryde)

## [v3.3.0] - 2026-06-26

### Features

- Add a **Theme Builder** in **Settings > Appearance > Themes** to create, save, and manage multiple custom themes that behave like Apollo's built-in themes, including importing and exporting themes to share them (#454: @jordanearle, @icpryde)
- Add **AI Summaries** in **Settings > Apollo Reborn > Apollo AI** (off by default, iOS 26+) — generates post, discussion, and linked-article summaries entirely **on-device** using Apple's FoundationModels (#489, #491: @jordanearle, @icpryde)
  - Post summaries appear in the comments header between the title and body, and discussion summaries appear above the first comment on larger threads; summaries stream in token-by-token and are cached to disk so reopening a thread is instant
  - Includes per-type controls and a **Tap to Summarize** option that avoids auto-fetching a linked article's page until you ask for it
- New experimental **API-Key-Free Mode** in **Settings > Apollo Reborn > API Keys** to use Apollo without API keys by signing in to reddit.com directly! Supports browsing, voting, commenting, and saving. (#442: @nickclyde)
  - In this mode, images attached to comments and posts now upload straight to Reddit's own CDN instead of falling back to Imgur (#495: @nickclyde)
- Add **multi-account credentials** so each signed-in account can use its own Reddit API key (or web session) instead of sharing one, with a redesigned account switcher to add, edit, reorder, and remove accounts, and support for Reddit "Web app" confidential clients (#505: @DeltAndy123)
- Add **Picture-in-Picture** for videos and GIFs — a floating in-app miniplayer that keeps playing as you scroll through the comments (drag to reposition, swipe to hide, double-tap to resize), with optional handoff to the iOS system PiP so playback continues when you leave Apollo (#467: @JeffreyCA)
- Add **Img Chest** as a media upload host in **Settings > Apollo Reborn > Media Upload Host** for single images and albums, with thumbnails and host labels in **Manage Uploads**, the ability to delete Img Chest uploads, and an improved album viewer with share, Save All, an accurate loading percentage, and swipe-to-dismiss (#434: @icpryde)
- Revamp the **Subreddit Sidebar** to render new-Reddit's structured content above the existing markdown — community stats (subscribers and created date), a **Search by Flair** chip row that jumps straight to a flair's posts, related communities, resource links, and a table of contents (#462: @icpryde)
- Add an opt-in **Community Highlights** carousel in **Settings > Apollo Reborn > Subreddits**, showing a subreddit's pinned posts as tappable cards at the top of the feed, with tap-to-collapse, spoiler blurring, and an optional **Load All Highlights** mode that surfaces the full set of pinned posts (#463, #499: @icpryde)
- Expand **Filters & Blocks** with per-subreddit keyword and post-flair filters plus subreddit-name filtering that hides any subreddit whose name contains a word (e.g. `circlejerk`) across feeds and search (#507: @icpryde)
- Improve **Direct Chat** with inline images, GIFs, and emoji/snoomoji in message bubbles, ImgChest-backed image sending, a recipient avatar in the composer, a **Direct Chat** inbox filter with avatars on every row, and an **Inline Media in Chat** toggle in **Settings > Media** (#488: @icpryde)
- Add **Apple's on-device Translation** (iOS 18+) as a translation provider in **Settings > Translation > Primary Provider**, alongside Google and LibreTranslate (#460: @icpryde)
- Show a user's **Social Links** on their profile page (#465, #496, #498: @icpryde)
- Move **Rich Link Previews** into its own settings section with a combined Body, Comments, and Color sub-screen, and replace the preset card colors with a full color picker (grid, spectrum, sliders, eyedropper, hex) plus quick swatches, a live card preview, and exact full-fill card coloring with automatic text contrast (#504: @icpryde)
- Add **Include Link** and **Share as Video** options to **Share as Image** — attach the post's Reddit link alongside the rendered image, or export the post as a video (#484: @icpryde)
- Add **Inbox Comment Scroll** so tapping a reply in the Inbox lands on the linked comment instead of the top of the post (#457: @icpryde)
- Improve the **user flair selector** to handle old (CSS-class) and emoji-based flair systems, add a custom-emoji picker, and show clearer empty states instead of errors or walls of blank rows (#474: @icpryde)
- Show **moderator avatars** in the subreddit Mods list (#459: @icpryde)
- Add **0.75× and 1.25× playback speeds** to the fullscreen video player (#476: @icpryde)
- Add a **hold-for-2× gesture** — press and hold the right side of a fullscreen video to play at 2× while held, then release to restore the previous speed (#479: @icpryde)

### Fixes

- Replace the misleading **"Error Loading Notifications — contact developer"** alert on free-Apple-ID sideloads with a clear **Notifications Unavailable** explanation, since Apple only grants the push entitlement to paid Developer accounts, so push, watchers, and inbox alerts can never reach those builds; paid-account sideloads and App Store/jailbreak builds are detected and left untouched (#492: @federgilad)
- Make **deleted comment recovery** faster and more reliable, with cleaner labels on recovered comments and a heads-up when enabling it that comments may load slower (#418: @nunoo)
- Fix the tweak's settings screens only following the system light/dark mode instead of **Apollo's own color theme**, along with related cell coloring glitches when switching appearance (#440: @iCrazeiOS)
- Keep a profile's **avatar, banner, bio, and social links** visible even when **Show User Profile Pictures** is turned off (#487: @icpryde)
- Rework the **feed and subreddit search bar** so the navigation bar fully hides on iOS 26 instead of floating half-visible, and add an opt-in **Keep Search Bar In Place** mode in **Settings > Apollo Reborn > General** (#451: @icpryde)
- Fix **link-preview card text** showing raw HTML entities like `&amp;` (#461: @icpryde)
- Fix the **SUBREDDIT SUGGESTIONS** header overlapping the first row on the Search tab (#478: @icpryde)
- Fix the **modern subreddit list** tinting the whole navigation bar when the Home row is selected (#453: @icpryde)
- Fix the **profile-picture tab icon** greying out after opening a direct chat room from the Inbox (#458: @icpryde)
- Fix the **translation globe** spacing in the Liquid Glass navigation bar (#455: @icpryde)
- Fix **Pixel Pals** opening their menu over media, web views, and modals (#506: @icpryde)
- Hide the redundant **GIF** caption beneath inline GIFs (#464: @icpryde)
- Improve the **manual sign-in fallback** UI on older iOS versions (#480: @Alstruit)
- Fix **Hide Mod Subreddits** stripping the moderator badge and mod tools when every moderated subreddit was hidden; the Subreddits list now filters display only, leaving the app-wide moderator roster intact (#500: @icpryde)
- Restore the **follow-thread Live Activity** in the Reborn widgets so a self-hosted notification backend can render and update it again (#490: @nickclyde)
- Show the **website name** on a link card when the scraped title is only numbers, instead of a bare number like a single-page app's match ID (#503: @icpryde)

## [v3.2.0] - 2026-06-14

### Features

- New **Apollo Reborn Widgets** — nine Home Screen, Lock Screen, and StandBy widgets (Showerthoughts, Jokes, Post, Feed, Photo, Shortcuts, Apollo Actions, Calendar, and Headline) (#406: @jordanearle)
  - Most widgets read Reddit through your API key: copy a one-time setup code from **Settings > Apollo Reborn > Copy Widget Setup Code** and paste it into any widget, and the rest pick it up automatically
  - Tapping a widget opens the post or subreddit in Apollo; included in the standard build but not the no-extensions variant
- Add a **Universal OAuth Sign-In** toggle in **Settings > Apollo Reborn** (on by default) to fall back to Apollo's native sign-in if the in-app login causes trouble, and ship released IPAs with the `dystopia` and `redreader` sign-in URL schemes already registered so the shared API key works without manually editing Info.plist (#432: @JeffreyCA)
- Add a **manual sign-in fallback** for older iOS versions that can't load Reddit's login page, using an external browser and an Apollo Reborn userscript to paste a sign-in code back into Apollo (#430: @DeltAndy123; sign-in keyboard improvements by @Alstruit)
- Add a **Text Post Thumbnails** toggle in **Settings > Apollo Reborn > Media** (on by default) — text posts that embed an image now show a thumbnail with a **Text Post** badge, and tapping it opens the image in the media viewer instead of the thread (#426: @icpryde)
- Add **Hide Mod Subreddits** to remove moderated subreddits you can't leave from the Subreddits list — tap Edit, then the blue button to hide a subreddit and the green button to bring it back (#424: @icpryde)
- Show **moderator reports** as native inline sections in the post and comment action menu (#412: @JeffreyCA)
- Make the **banned-profile overlay** dismissable (#409: @JeffreyCA)
- Combine cache-clearing options into one **Clear Tweak Caches** button under a renamed **Data** section (#409: @JeffreyCA)

### Fixes

- Show the **author avatar and subreddit icon** in **Share as Image** post exports, so the image matches what you see in the app (#438: @icpryde)
- Fix several **link card glitches in feeds** — cards whose text overflowed into the post below, Bluesky posts losing their paragraph breaks, compact cards stuck at full height, and blank image areas on links whose thumbnail isn't ready yet (#427: @icpryde)
- Fix **gallery GIFs** getting stuck on a loading spinner when swiping between items in an album (#404: @JeffreyCA)
- Fix comment and post text showing a literal **`&#x200B;`** or an extra blank line at the end (#405: @JeffreyCA)
- Fix **comment scrolling freezing** in threads that contain a link to removed media, such as a deleted `v.redd.it` video (#395: @JeffreyCA)
- Fix spurious **"error :(" overlay** appearing over videos that play fine but whose preview image fails to load (#409: @JeffreyCA)
- Fix **Live Activities** not updating on secret-protected self-hosted notification backends (#411: @nickclyde)
- Fix an **installation conflict** when upgrading from some older versions (#401: @Alstruit)
- Bundle **libFLEX inside the app** so rootless jailbreak users can keep the standalone libFLEX package installed without it conflicting with Apollo Reborn (#437: @iCrazeiOS)

## [v3.1.1] - 2026-06-07

- Fix a **crash when sharing a post to Messages or Mail** from the share sheet — the system compose controller was misidentified as an Apollo composer, leaving GIF-toolbar injection timers that dereferenced the dismissed share UI and crashed (#378: @nickclyde)
- Fix **Reddit login on iOS 15** by automatically falling back to Old Reddit, and add an Old Reddit button to the auth view for users who need to switch manually (#377: @DeltAndy123)
- Fix **video controls** overlay rendering, including the AirPlay button getting clipped or misaligned (#383: @JeffreyCA)
- Fix **flair alignment** so post and user flairs no longer sit too low or clip their text (#389: @JeffreyCA)
- Fix **Color Flairs** reverting to grey or the wrong shade after returning to Apollo from the background (#391: @icpryde)

## [v3.1.0] - 2026-06-05

### Features

- Support **any custom redirect URI** for the Reddit API without patching the app's Info.plist, so custom URI schemes authenticate without the "address is invalid" error (also removes the need for LiveContainer users to patch manually) (#368: @DeltAndy123)
- Add **GLASS Icons** and **No Extensions + GLASS Icons** distribution variants that bundle the Liquid Glass icon catalog without opting into the iOS 26 UI runtime (#317: @nackerr)
- Add new **Glitched** (@bajader) and **Modern** / **Modern Alt** (@paulo1manso) Liquid Glass app icons (#353: @bajader, @paulo1manso)
- **Restore logged-in accounts** when restoring a settings backup, so reinstalling no longer requires re-authenticating each Reddit account (#331: @nickclyde)
- Add a **Subreddit List Enhancements** toggle in **Settings > Apollo Reborn Options > Subreddits** to fall back to Apollo's native list, working around misaligned rows and a broken index scrubber on some devices (#355: @JeffreyCA)
- Add a **Color Flairs** option in **Settings > Apollo Reborn Options > General** to color post and user flairs using Reddit's flair colors (#360: @icpryde)
- Add **Show Deleted Comments** to restore deleted or removed comments inline from archived copies when available (#300: @nunoo)
- Render comments with **two or more link previews** as compact cards instead of stacking full hero cards (#344: @icpryde)
- Show **feed thumbnails for text posts** that embed images but produce no native thumbnail, in both Large and Compact modes (#351: @icpryde)
- Fade and disable the comment **image/GIF buttons** when a subreddit doesn't allow that media type, instead of failing only at submit time (#356: @icpryde)
- Add a separate **Autoplay Inline GIFs** setting in **Settings > Apollo Reborn Options > Media** to control inline GIF autoplay independently of Apollo's native Autoplay GIFs/Videos setting (#365: @JeffreyCA)
- Ship an Apollo-Reborn **userscript** and an **"Open in Apollo" Shortcut** recipe as app-independent ways to open Reddit links in Apollo from any browser, handy for the no-extensions variant (#307: @nickclyde)

### Fixes

- Fix the bundled **"Open in Apollo" Safari extension**, which stopped opening links on sideloaded builds — its default "Automatic" mode redirected through `openinapollo.com`, whose auto-open only works for the App Store build. It now redirects straight to `apollo://` and handles `/s/` share links (#307: @nickclyde)
- Fix the bundled **"Open in Apollo" share-sheet action** so it opens Reddit links in Apollo from **any** browser (Chrome, Firefox, Edge, Brave…), not just Safari, replacing a deprecated call that iOS 18+ refused to run. On iOS 26 the extension only launches if your installer sets the appex main-binary flag — **AltStore/SideStore** do, **Sideloadly/Feather** don't, where the Shortcut remains a signer-independent fallback (#307: @nickclyde)
- Fix **Recently Read** showing no posts after a Reddit API change (#341: @JeffreyCA)
- Fix inline **Reddit GIFs in comments** staying frozen instead of autoplaying until collapsed/expanded or refreshed (#349: @icpryde)
- Fix inline **GIFs not autoplaying on cellular** when Autoplay GIFs/Videos is set to Always (#347: @JeffreyCA)
- Fix the inline **video play button** missing on post-body Reddit videos and a clipped AirPlay icon (#350: @icpryde)
- Fix laggy **subreddit header** scrolling and incorrect handling on non-subreddit feeds (#339: @JeffreyCA)
- Fix **Share as Image** not opening under the iOS 26 native action menu (#335: @icpryde)
- Fix the **Rich Link Previews – Body** setting having no effect and following the Comments setting instead (#329: @nickclyde)
- Fix a crash in the banned-profile hook (#326: @JeffreyCA)
- Fix a crash when navigating into comments from a dangling host pointer in inline image cleanup (#362: @JeffreyCA)

## [v3.0.0] - 2026-05-29

### Features

- Post **GIFs in comments**: a new **Gif** button in the compose toolbar opens a built-in Giphy browser (trending + search) and uploads selected GIFs natively to Reddit (#276: @icpryde)
    - Requires a free Giphy API key — set it in **Settings > Custom API > API Keys > Giphy API Key**. See the in-app **Giphy & ImgChest API Key Setup** guide for instructions (#285: @icpryde)
    - Inline playback honors **Settings > General > Autoplay GIFs/Videos** with a static cover + play overlay when paused
- Add **Image Chest** inline album support: bare Image Chest links show the first image inline and open an in-app album viewer with tap-to-hide controls, idle auto-hide, and per-image pinch zoom (#241: @icpryde)
    - To set up Image Chest, create an account at https://imgchest.com, generate an API token at https://imgchest.com/profile/api, and paste it into **Img Chest API Key** under **Settings > Custom API > API Keys**
- Add **Subreddit Headers**: view subreddit banners and display icons on subreddit pages, with optional tap-to-set custom local images that can be reset anytime in Settings (#266: @jordanearle, @icpryde)
- Compact **u/username** and **r/subreddit** cards in rich link previews show avatar/icon, display name, member count, and an about snippet, with long-press peek into the native profile/community view (#262: @icpryde)
- Long-press peek now works on usernames and subreddit links in threads and comments (#262: @icpryde)
- Show **banned profile state** with a dead Snoo overlay on user profiles, and surface comment author hints for banned/suspended users (#271, #278: @icpryde, @jordanearle)
- Add **editable user flair text** support to Apollo's flair selector (#255: @nunoo)
- Rich link previews now support translation alongside the rest of post and comment content (#262: @icpryde)
- Subreddit list (Modern mode) polish (#262: @icpryde)
- Add **41 new Liquid Glass icon variants** by @jryng under a new **New Variants** group, plus new **Aperture Science** and **ApollOS** icon sets by @bajader, and reorganize the in-app App Icon picker into groups to reduce clutter (#287, #254: @DeltAndy123, @jryng, @bajader)
- Add **Inline Media Alignment** option in **Settings > Custom API > Media** to left-align, center, or right-align inline images that don't fill the full content width (#273: @lampemw)
- Rename **Custom API** to **Apollo Reborn Options** in Settings, polish the **Thanks To** screen with maintainer/code/icon & design groupings sourced from `contributors.json`, and add an **Apollo Reborn Subreddit** row that opens r/ApolloReborn in-app (#294: @icpryde)
- **Mask API keys** in Custom API settings: Reddit, Reddit Secret, Imgur, Img Chest, and Giphy fields show dots when idle and reveal only while editing (#276: @icpryde)
- Add **Buy Us a Coffee** screen in Settings with maintainer links, and move Apollo's original **Tip Jar** to **Settings > About** above **What's New** (#294: @icpryde)

### Fixes

- Fix scroll freeze / loading-spinner lockup while scrolling threads with rich link previews (#262: @icpryde)
- Fix comment layout shifting around as user avatars load in (#262: @icpryde)
- Replace placeholder filler text in rich link previews with skeleton loading bars, and reduce flicker when previews reappear (#262: @icpryde)
- Fix a stray translucent star/blob on rich link previews when using Share as Image (#262: @icpryde)
- Fix visionOS (Vision Pro) use-after-free crash on multireddits (#270: @rebelancap)
- Fix X and Edit buttons touching the top of the account switcher popup on Liquid Glass (#275: @lampemw)
- General stability improvements around rapid subreddit navigation and image loading (#262, #266: @icpryde, @jordanearle)
- Smoother scrolling through threads with lots of rich link previews (#262: @icpryde)
- Keep user profile cards and peek previews up to date when an account is suspended or banned (#278: @jordanearle, @icpryde)
- Fix launch crash when opening a banned user's profile (#276: @icpryde)
- Fix crash on Reddit link previews in some comment threads (#276, #280: @JeffreyCA, @icpryde)
- Fix Reddit-hosted GIFs stopping animation after leaving and returning to a thread (#276: @icpryde)
- Fix Giphy GIFs posted from Apollo not rendering in the official Reddit iOS app (and showing a "image was probably deleted" placeholder when editing in Apollo) (#289: @icpryde)
- Fix Compact link preview cards growing to hero size and overlapping the next comment after voting on a comment that contains a link (#290: @icpryde)

## [v2.14.0] - 2026-05-20

### Features

- **Notification Backend** support (requires paid Apple Developer account): point Apollo at your own forked self-hosted [apollo-backend](https://github.com/nickclyde/apollo-backend) instance so push registrations, watchers, and inbox checks route there instead of being silently dropped. (Thanks @nickclyde!)
    - Configure in **Settings > Custom API > Notification Backend** with the backend URL and optional registration token. Leave empty to keep current blocking behavior.
    - APNs delivery still requires a paid Apple Developer account on the signing side. 
- New **Reddit API Secret** field in **Settings > Custom API > API Keys** so per-account Reddit credentials can be forwarded to a self-hosted notification backend that performs token refreshes server-side. Usually left empty for installed-app Reddit credentials. (Thanks @nickclyde!)

### Fixes

- Improve **Profile Picture Tab Icon** reliability across Liquid Glass tab bar refreshes, theme changes, and app foregrounding.
- Refine Liquid Glass **Hide Bars on Scroll** idle behavior with smoother re-collapse/re-expand handling and disable the idle setting on unsupported iOS versions.
- Improve performance and stability across subreddit list polish, rich link previews, and the media post composer.

## [v2.13.0] - 2026-05-19

### Features

- Add **Rich Link Previews**: first-party cards for YouTube, Reddit, GitHub, Wikipedia, Twitter/X, Bluesky, and a configurable preview card color (thanks @icpryde!)
    - Configurable for posts and comments separately between with Full, Compact, and Off in **Settings > Custom API > Media**
- Profile pages now include Reddit display name, about text, and an Edit button that opens Reddit's profile editor (thanks @icpryde!)
- New **Profile Picture Tab Icon** setting (**Settings > Custom API > Media**) that displays user profile picture in the tab bar.
- Polish subreddit list view with a custom alphabet index overlay, larger favourite-star hit targets, and a **Modern Subreddit Dividers** style (**Settings > Custom API > Subreddits**) (thanks @icpryde!)
- Liquid Glass: replace action sheets with native iOS action menus throughout the app
- Liquid Glass: add new **Sunset** app icon (thanks @bajader!), rename icons, and show icon designer names in the picker

### Fixes

- Fix user profile pictures appearing inside flair text
- Fix the media post body text editor in subreddits that do not expose Apollo's normal Text tab (thanks @icpryde!)
- Fix subreddit list view scroll position shifting after favouriting a subreddit
- Fix stale subreddit entries lingering after unfavouriting from Favourites section
- Liquid Glass: fix separators blocking alphabet in subreddit list view
- Update Custom API settings view to match app theme
- Add statsigapi.net to the blocked URL list 

## [v2.12.0b] - 2026-05-16

### Features

- Add an optional **Text** row to Media posts that opens Apollo's native Post Text editor (with Markdown toolbar) and submits the body text alongside Reddit-hosted media (thanks @icpryde!)
- Add a long-press menu on profile usernames to copy the username to the clipboard (thanks @icpryde!)
- Add single-video Reddit-hosted uploads from the media composer, including video selection, poster upload, and native hosted-video posts (thanks @icpryde!)
- Refresh user profile pictures on pull-to-refresh and add a **Clear Profile Picture Cache** action under **Settings > Custom API > Media**.
- Add **harunatsu** Liquid Glass app icon to Apollo's native App Icon picker (thanks @jordanearle and /u/harunatsu91202024!)
- Liquid Glass: new **Tab Bar Re-Expands When Idle** toggle in **Settings > Custom API > General** that re-expands the tab bar after a deliberate upward scroll or a longer idle timeout (thanks @icpryde!)
- New **Thanks To** screen under **About** section. Thank you to all the contributors who've helped make this tweak what it is ❤️

### Fixes

- Fix Reddit-hosted multi-image photo posts by submitting them as native Reddit galleries instead of Imgur albums, including the post-submit comments permalink Apollo opens after success (thanks @icpryde!)
- Fix the Photo Post composer thumbnail strip so all selected images can be reviewed with reliable horizontal scrolling before submit (thanks @icpryde!)
- Improve user avatar loading on multireddits

## [v2.11.0] - 2026-05-15

- **Liquid Glass app icons!** Apollo's native App Icon picker now ships with 4 community-designed Liquid Glass app icons that render with full iOS 26 Liquid Glass effects on the home screen
    - Requires re-patching your IPA using the updated `patch.sh` script or **Patch IPA** GitHub Action. Previously patched IPAs won't show them
    - Huge thanks to @jordanearle for figuring out the `.icon` → `Assets.car` build flow, @DeltAndy123 for the asset-rebuild tooling and tint fixes, and to @jryng, @iGerman00, and @metalnakls for the icon designs
- New **Show User Profile Pictures** toggle to display Reddit user avatars next to usernames in posts, comments, as well as in user profiles (thanks @icpryde for implementing this feature!)
    - Configure in **Settings > Custom API > Media > Show User Profile Pictures**
- Preserve typed text when submitting Reddit-hosted image comments (thanks @icpryde!)
- Remove duplicate **Hide Next Parent Button** setting; Apollo already provides this as **Show Jump Button** (thanks @icpryde!)
- Fix Pixel Pals receiving 3 food items on every launch (thanks @DeltAndy123!)

## [v2.10.0] - 2026-05-12

- New **Hide Next Parent Button** toggle in **Settings > Custom API > General** to hide the floating button in the bottom-right of comments views (thanks @icpryde!)
- Liquid Glass: **Hide Bars on Scroll** now uses native iOS 26 tab bar minimize behaviour so it collapses into the small pill on scroll-down and re-expands on scroll-up (thanks @icpryde!)
- Fix Reddit-hosted image uploads in text posts failing with a `BAD_URL` error
- Improve link-button hiding with inline media previews

## [v2.9.0] - 2026-05-11

- New **Inline Media Previews** option to render images, GIFs, and videos inline within posts and comments
    - Configure in **Settings > Custom API > Media > Inline Media Previews** (on by default)
    - Supports most animated GIFs (including GIFV), Reddit hosted videos, and Imgur images and albums
    - Thank you @icpryde for the collaboration and adding support for videos, Imgur albums, and thumbnail retrieval
- Fix Apollo bug where viewing MP4-style GIFs / GIFVs on subsequent loops would randomly freeze
- Fix rare crash issue caused by comment collapse hooks
- Liquid Glass: fix tab bar icon and label tinting so it adapts to light/dark mode and to bright/dark content behind the glass material (thanks @icpryde!)
- Liquid Glass: fix subreddit title being misaligned to the left in the navigation bar

## [v2.8.0] - 2026-05-08

- New **Image Upload Host** option to upload images directly to Reddit instead of Imgur (thanks @icpryde for the implementation!)
    - Configure in **Settings > Custom API > Media > Image Upload Host**
    - Reddit image upload is **experimental** and does not currently support multi-image or video uploads
        - Right after posting, Apollo may briefly show a generic preview icon while Reddit finishes processing the image. Pull to refresh and the real thumbnail should appear

## [v2.7.2] - 2026-05-07

- Bulk translation: add Bosnian language support (thanks @hllvc!)

## [v2.7.1] - 2026-05-06

- Bulk translation: fix post titles getting automatically translated when Auto Translate is off (thanks @icpryde!)
- Fix crash when searching for a URL in the Search tab. URL searches now return posts that link to that URL.

## [v2.7.0] - 2026-05-05

- New **Tag Filters** feature to blur NSFW and/or Spoiler posts (including titles) in feeds (thanks @icpryde for implementing this!)
    - Configure in **Settings > Tag Filters**
    - Tap a blurred post for a "View hidden post?" confirmation alert
    - Per-subreddit overrides let you toggle NSFW or Spoiler filtering for individual subreddits
- Bulk translation fixes (thanks @icpryde!):
    - Fix post body briefly flashing the original language after voting, and not reverting when toggling translation off while scrolled past the body
    - Fix comment cells being skipped when toggling translation, and translations appearing half-applied after returning to Apollo from another app
    - Fix plain multi-paragraph post bodies being skipped

## [v2.6.1] - 2026-05-01

- Fix tab bar disappearing after sharing content

## [v2.6.0] - 2026-04-30

- Bulk translation improvements (thanks @icpryde for continuing to refine this!)
    - New **Don't Translate** languages list in **Settings > Translation** to keep selected languages untranslated
    - New option to translate post titles in **Settings > Translation**
    - Various bug fixes and stability improvements
- Tap a comment or post's relative-time label (e.g. "2.8y") to show an alert with the absolute creation date and time, mirroring Apollo's existing "Edited" alert
- Liquid Glass: fix tab bar not reappearing on scrolling up when "Hide Bars on Scroll" is enabled (thanks @icpryde for the fix!)
- Liquid Glass: hide translucent status bar background strip that appears at the top of the screen when "Hide Bars on Scroll" is enabled
- Liquid Glass: fix first list row being clipped under nav bar in subreddit list view when "Hide Bars on Scroll" is enabled

## [v2.5.0] - 2026-04-28

- New bulk translation feature for comment threads and self posts (thanks @icpryde for implementing this feature!)
    - When enabled, loaded comments are translated in-place. Configure in **Settings > Translation**
    - Adds a per-thread globe toggle to switch between translated and original text in comments view
    - Supports both Google and LibreTranslate, with custom LibreTranslate URL and API key
    - Translations persist in place while voting, collapsing and expanding comments, opening previews, scrolling, and refreshing the thread
    - Preserves links while translated and leaves code or preformatted content untranslated

## [v2.4.0] - 2026-04-18

- Add option to proxy Imgur images through DuckDuckGo (Settings > General > Custom API > Media)
    - Only supports viewing single images; albums are not supported

## [v2.3.0] - 2026-04-09

- Add option to hide NSFW posts in Recently Read
- Show inline NSFW badge on post titles in Recently Read
- Use distinct placeholder thumbnails for self-posts vs link posts in Recently Read

## [v2.2.1] - 2026-03-25

- Block additional tracking and analytics URLs (thanks @Uranosphaerite!)
- Liquid Glass: fix header flicker issue in comments

## [v2.2.0] - 2026-03-20

- Add "Collapse Pinned Comments" setting to auto-collapse pinned/stickied comments
- Add "Can't sign in?" troubleshooting section
- Liquid Glass: fix blur overlay issue when viewing messages

## [v2.1.0] - 2025-03-12

- Add Steam store deep linking support (thanks @wdeezy for the contribution!)
    - To enable, toggle "Open Steam Links in App" in Custom API > General
- Update default recently read posts limit to be unlimited
- Fix share links opening in different Apollo app
- Fix Pixel Pals making dynamic island taller than expected on newer iPhone models

## [v2.0.0] - 2025-03-07

🎉 ***Massive*** update that enables Ultra features like saved categories, new app icons and Pixel Pals! This also brings new features like recently read posts and fixes for some longstanding Apollo bugs.

The Custom API settings view has also been redesigned and is now accessible directly from Settings.

**Note:** Ultra features that rely on push notifications do not work out of the box. Advanced users can optionally point the tweak at a self-hosted [apollo-backend](https://github.com/nickclyde/apollo-backend) fork (see **Settings > Custom API > Notification Backend**) — APNs delivery requires a paid Apple Developer account on the signing side.

| | | |
|:--:|:--:|:--:|
| <img src="img/settings.jpg" alt="Settings" width="200"> | <img src="img/custom.jpg" alt="Custom API Settings" width="200"> | <img src="img/recents.jpg" alt="Recently Read" width="200"> |

### Saved Categories
- To enable saved categories, set "Allow Saved Categories" in Settings > General > Other
- New "Saved Categories" section in Settings tab to edit and delete saved categories
- Fixed: Saved category names are now consistently sorted in menus
- **Note:** Saved categories are global, while saved items are tied to individual accounts

### Recently Read
- New "Recently Read" button in Profile tab to view and clear all recently read posts
- "Disable Marking Posts Read" **must be unchecked** in Settings > General > Mark Read / Hiding Posts
- **Note:** Recently read is global (not account-specific)

### Media Playback
- New "Unmute Videos in Comments" setting (Settings > General > Custom API)
    - **Default**: Default Apollo behaviour
    - **Remember from Fullscreen Player**: If you unmute a video in the fullscreen player, it stays unmuted when you navigate into comments
    - **Always**: Header videos are always automatically unmuted after opening comments 
- New "Preferred GIF Fallback Format" setting (Settings > General > Custom API)
    - Choose between GIF or MP4 when Apollo fetches certain animated images from Reddit API
    - Try setting to "GIF" if you find certain animated images get stuck with loading spinner

### Other Issues Fixed
- Interacting with Ultra features and settings no longer causes app to crash
    - "New Comments Highlightifier" can be toggled normally in Settings > General, and is removed from Custom API settings
- Fix multi-image Imgur uploads failing the first time
- Fix share links opening in webview on iOS 26
- Fix album image count label placement on newer iPhone models
- Fix "Processing img" in self-posts
- Liquid Glass: fix clipping when collapsing long comment chains
- Add support for YouTube Shorts links
- Various video playback fixes and improvements

### Pixel Pals
- Pixel Pals are now available on newer iPhone models
- Unlock hidden "Artificial Superintelligence" Pixel Pal

### App Icons & Themes
- Unlock hidden "Chumbus" theme
- Unlock all app icons, including:
    - Community Icon Pack
    - SPCA Animals Pack
    - Ultra Icons
    - <details>
      <summary>22 Sekrit Icons (click to expand)</summary>

        - Beans (Black Friday 2022)
        - Sloth-kun
        - iJustine / Wrapping Paper
        - America!
        - Super America
        - UK / Hugh Laurie
        - Yo. Jonathan Here. (TLD Today)
        - ApolloBook Pro
        - Wallpapers
        - ATP
        - Phil Schiller
        - Canada D'Eh
        - Ukraine
        - Ernest
        - Sus (Among Us)
        - Dave2D
        - MKBHD (Keith)
        - Peachy (Neon Peach)
        - Linus Tech Tips
        - Andru Edwards
        - Everything Apple Pro (Icons Drop Test)\*
        - Rene Ritchie
        - Snazzy Labs

         The "Icons Drop Test" icon does not show up in App Icons. To set, go to Settings > About, shake device, and input `everythingapplepro`.
      </details>

## [v1.4.5] - 2026-02-17

- Prevent certain crashes when Reddit API goes down

## [v1.4.4] - 2026-02-13

- Fix GIFs showing up as `Processing img <id>` in comments

## [v1.4.3] - 2026-02-12

- Fix inline Giphy GIFs not loading in comments

## [v1.4.2] - 2026-02-06

- Update default trending source to `https://jeffreyca.github.io/subreddits/trending-subriff-blended.txt`
    - Previous source has been discontinued
- Fix certain GIFs playing at 2x speed on 120Hz displays

## [v1.4.1] - 2026-01-23

- Fix certain Streamable links not loading in media view

## [v1.4.0] - 2026-01-10

- Support custom redirect URI and user agent (in Settings > General > Custom API)
- Liquid Glass: fix sort options alignment in comment view

## [v1.3.2] - 2026-01-07

- Fix crashes in Custom API settings on older iOS versions

## [v1.3.1] - 2026-01-03

- Liquid Glass UI improvements and fixes:
    - Restore long press gesture on account tab to open account switcher
    - Fix opaque nav bar background in dark mode
    - Fix dark band appearing in nav bar when scrolling
    - Fix misaligned tab labels on startup

## [v1.3.0] - 2025-12-28

- Backup and restore most Apollo and tweak settings (in Settings > General > Custom API)
    - Settings are exported as a .zip file with 2 plist files: preferences.plist (most Apollo and tweak settings) and group.plist (filters, theme settings)
    - Restoring settings **does not** restore or affect existing account logins. This means on a clean install, accounts need to be re-added manually. The backup .zip contains an accounts.txt with all account usernames for reference.
- Update Custom API Settings layout

## [v1.2.6] - 2025-11-08

- Fix video downloads failing on certain v.redd.it videos
    - Recently, Reddit started using [CMAF media format](https://developer.apple.com/documentation/http-live-streaming/about-the-common-media-application-format-with-http-live-streaming-hls) for serving video content, which Apollo does not natively support downloading for.

## [v1.2.5] - 2025-10-18

- Fix occassional crashes when scrolling on iOS 26 with Liquid Glass patch (thanks @dankrichtofen for the original implementation)
- Fix crashes when tapping share URL link buttons on iOS 26
    - Note that this is **not** a full fix. Tapping the link button now navigates to a webview on iOS 26. As a workaround, tap the inline text (see [comment here](https://github.com/Apollo-Reborn/Apollo-Reborn/issues/62#issuecomment-3247359652)).
- Fix debug logging on iOS 26

## [v1.2.4] - 2025-08-23

- Fix RedGIFs links loading without sound (again)

## [v1.2.3] - 2025-04-07

- Fix issue with Imgur multi-image uploads consistently failing. Note that multi-image uploads still fail on the first attempt but should succeed on the next attempt.
- Update Custom API settings with link to [new GitHub discussion](https://github.com/Apollo-Reborn/Apollo-Reborn/discussions/60) where you can share your own subreddit sources with others.

## [v1.2.2] - 2025-01-16

- Fix video downloads failing on certain v.redd.it videos
    - Note that the `.deb` file is significantly larger (several MB) because of new external dependencies needed to fix the issue (FFmpegKit)

## [v1.2.1] - 2024-12-19

- Custom random and trending subreddits - you can now specify an external URL to use as the source for random and trending subreddits (in Settings > General > Custom API)
    - Sources should be a plaintext file with one subreddit name per line, without the `/r/` prefix (see examples below)
    - Default trending source (data from [gummysearch.com](https://gummysearch.com/tools/top-subreddits/)): https://jeffreyca.github.io/subreddits/trending-gummy-daily.txt
    - Default /r/random source: https://jeffreyca.github.io/subreddits/popular.txt
    - New setting to customize how many trending subreddits to show
    - New setting to show a dedicated RandNSFW button
- Minor UI updates to the settings view
- URL optimizations (thanks [@ryannair05](https://github.com/ryannair05)!)

## [v1.1.8] - 2024-12-07

- Fix RedGIFs links loading without sound (thanks [@iCrazeiOS](https://github.com/iCrazeiOS)!)

## [v1.1.7b] - 2024-10-25

- Add rootless package (thanks [@darkxdd](https://github.com/darkxdd)!)

## [v1.1.7] - 2024-10-19

- Improve parsing `new.reddit.com` and `np.reddit.com` links

## [v1.1.6] - 2024-10-05

- Fix issue with share URLs not working after device locks
- Remove unused code for handling Imgur links

## [v1.1.5b] - 2024-09-18

- Fix rare crashing issue
- Include tweak version in Custom API settings view

## [v1.1.4] - 2024-08-28

- Improve share URL and Imgur link parsing (specifically URLs formatted like: `https://imgur.com/some-title-<imageid>`)
- Fix crashing issue when loading content

## [v1.1.3] - 2024-08-23

Fix issue with newer Imgur images and albums not loading properly

## [v1.1.2] - 2024-08-01

Update user agent to fix multireddit search

## [v1.1.1] - 2024-07-27

- Working hybrid implementation of "New Comments Highlighter" Ultra feature
- Add FLEX integration for debugging/tweaking purposes (requires app restart after enabling in Settings -> General -> Custom API)

## [v1.0.12] - 2024-07-25

Use generic user agent independent of bundle ID when sending requests to Reddit

## [v1.0.11] - 2024-02-27

Fix issue with Imgur uploads consistently failing. Note that multi-image uploads may still fail on the first attempt.

## [v1.0.10] - 2024-01-22

Add support for /u/ share links (e.g. `reddit.com/u/username/s/xxxxxx`).

## [v1.0.9] - 2023-12-29

- Randomize "trending subreddits list" so it doesn't show **iOS**, **Clock**, **Time**, **IfYouDontMind** all the time - thanks [@iCrazeiOS](https://github.com/iCrazeiOS)!
    - Context: There isn't an official Reddit API to get the currently trending subreddits. Apollo has a hardcoded mapping of dates to trending subreddits in this file called `trending-subreddits.plist` that is bundled inside the .ipa. The last date entry is `2023-9-9`, which is why Apollo has been falling back to the default **iOS**, **Clock**, **Time**, **IfYouDontMind** subreddits lately.

## [v1.0.8] - 2023-12-15

- Lower minimum iOS version requirement to 14.0
- Toggleable settings for blocking announcements and some Ultra settings (not fully working, see [#1](https://github.com/Apollo-Reborn/Apollo-Reborn/issues/1)). **These are the same as the previous experimental builds.**
    - All toggles are located in Settings -> General -> Custom API
    - New Comments Highlightifier shows new comment count badge, but doesn't highlight comments inside a thread
    - Subreddit Weather and Time widget doesn't seem to work (not showing or loads infinitely)

## [v1.0.7] - 2023-12-07

- Add support for resolving Reddit media share links ([#9](https://github.com/Apollo-Reborn/Apollo-Reborn/pull/9)) - thanks [@mmshivesh](https://github.com/mmshivesh)!

## [v1.0.5] - 2023-12-02

- Fix crash when tapping on spoiler tag

## [v1.0.4] - 2023-11-29

Add support for share links (e.g. `reddit.com/r/subreddit/s/xxxxxx`) in Apollo. These links are obfuscated and require loading them in the background to resolve them to the standard Reddit link format that can be understood by 3rd party apps.

The tweak uses the workaround and further optimizes it by pre-resolving and caching share links in the background for a smoother user experience. You may still see the occassional (brief) loading alert when tapping a share link while it resolves in the background.

There are currently a few limitations:
- Share links in private messages still open in the in-app browser
- Long-tapping share links still pop open a browser page

## [v1.0.3b] - 2023-11-26
- Treat `x.com` links as Twitter links so they can be opened in Twitter app
- Fix issue with `apollogur.download` network requests not getting blocked properly (#3)

## [v1.0.2c] - 2023-11-08
- Fix Imgur multi-image uploads (first attempt usually fails but subsequent retries should succeed)

## [v1.0.1] - 2023-10-18
- Suppress wallpaper popup entirely

## [v1.0.0] - 2023-10-13
- Initial release

[v3.8.3]: https://github.com/paradoxally/Apollo-Reborn/compare/v1.15.11_3.8.2...v1.15.11_3.8.3
[v3.8.2]: https://github.com/paradoxally/Apollo-Reborn/compare/v1.15.11_3.8.1...v1.15.11_3.8.2
[v3.8.1]: https://github.com/paradoxally/Apollo-Reborn/compare/v1.15.11_3.8.0...v1.15.11_3.8.1
[v3.8.0]: https://github.com/paradoxally/Apollo-Reborn/compare/v1.15.11_3.7.2...v1.15.11_3.8.0
[v3.7.2]: https://github.com/paradoxally/Apollo-Reborn/compare/v1.15.11_3.7.1...v1.15.11_3.7.2
[v3.7.1]: https://github.com/paradoxally/Apollo-Reborn/compare/v1.15.11_3.7.0...v1.15.11_3.7.1
[v3.7.0]: https://github.com/paradoxally/Apollo-Reborn/compare/v1.15.11_3.6.1...v1.15.11_3.7.0
[v3.6.1]: https://github.com/paradoxally/Apollo-Reborn/compare/v1.15.11_3.6.0...v1.15.11_3.6.1
[v3.6.0]: https://github.com/paradoxally/Apollo-Reborn/compare/v1.15.11_3.5.2...v1.15.11_3.6.0
[v3.5.2]: https://github.com/paradoxally/Apollo-Reborn/compare/v1.15.11_3.5.1...v1.15.11_3.5.2
[v3.5.1]: https://github.com/paradoxally/Apollo-Reborn/compare/v1.15.11_3.5.0...v1.15.11_3.5.1
[v3.5.0]: https://github.com/paradoxally/Apollo-Reborn/compare/v1.15.11_3.4.1...v1.15.11_3.5.0
[v3.4.1]: https://github.com/paradoxally/Apollo-Reborn/compare/v1.15.11_3.4.0...v1.15.11_3.4.1
[v3.4.0]: https://github.com/paradoxally/Apollo-Reborn/compare/v1.15.11_3.3.0...v1.15.11_3.4.0
[v3.3.0]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.15.11_3.2.0...v1.15.11_3.3.0
[v3.2.0]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.15.11_3.1.1...v1.15.11_3.2.0
[v3.1.1]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.15.11_3.1.0...v1.15.11_3.1.1
[v3.1.0]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.15.11_3.0.0...v1.15.11_3.1.0
[v3.0.0]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v2.14.0...v1.15.11_3.0.0
[v2.14.0]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v2.13.0...v2.14.0
[v2.13.0]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v2.12.0b...v2.13.0
[v2.12.0b]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v2.11.0...v2.12.0b
[v2.11.0]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v2.10.0...v2.11.0
[v2.10.0]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v2.9.0...v2.10.0
[v2.9.0]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v2.8.0...v2.9.0
[v2.8.0]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v2.7.2...v2.8.0
[v2.7.2]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v2.7.1...v2.7.2
[v2.7.1]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v2.7.0...v2.7.1
[v2.7.0]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v2.6.1...v2.7.0
[v2.6.1]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v2.6.0...v2.6.1
[v2.6.0]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v2.5.0...v2.6.0
[v2.5.0]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v2.4.0...v2.5.0
[v2.4.0]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v2.3.0...v2.4.0
[v2.3.0]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v2.2.1...v2.3.0
[v2.2.1]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v2.2.0...v2.2.1
[v2.2.0]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v2.1.0...v2.2.0
[v2.1.0]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v2.0.0...v2.1.0
[v2.0.0]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.4.5...v2.0.0
[v1.4.5]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.4.4...v1.4.5
[v1.4.4]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.4.3...v1.4.4
[v1.4.3]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.4.2...v1.4.3
[v1.4.2]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.4.1...v1.4.2
[v1.4.1]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.4.0...v1.4.1
[v1.4.0]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.3.2...v1.4.0
[v1.3.2]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.3.1...v1.3.2
[v1.3.1]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.3.0...v1.3.1
[v1.3.0]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.2.6...v1.3.0
[v1.2.6]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.2.5...v1.2.6
[v1.2.5]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.2.4...v1.2.5
[v1.2.4]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.2.3...v1.2.4
[v1.2.3]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.2.2...v1.2.3
[v1.2.2]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.2.1...v1.2.2
[v1.2.1]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.1.8...v1.2.1
[v1.1.8]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.1.7b...v1.1.8
[v1.1.7b]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.1.7...v1.1.7b
[v1.1.7]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.1.6...v1.1.7
[v1.1.6]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.1.5b...v1.1.6
[v1.1.5b]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.1.4...v1.1.5b
[v1.1.4]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.1.3...v1.1.4
[v1.1.3]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.1.2...v1.1.3
[v1.1.2]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.1.1...v1.1.2
[v1.1.1]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.0.12...v1.1.1
[v1.0.12]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.0.11...v1.0.12
[v1.0.11]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.0.10...v1.0.11
[v1.0.10]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.0.9...v1.0.10
[v1.0.9]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.0.8...v1.0.9
[v1.0.8]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.0.7...v1.0.8
[v1.0.7]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.0.5...v1.0.7
[v1.0.5]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.0.4...v1.0.5
[v1.0.4]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.0.3b...v1.0.4
[v1.0.3b]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.0.2c...v1.0.3b
[v1.0.2c]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.0.1...v1.0.2c
[v1.0.1]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.0.0...v1.0.1
[v1.0.0]: https://github.com/Apollo-Reborn/Apollo-Reborn/compare/v1.0.0
