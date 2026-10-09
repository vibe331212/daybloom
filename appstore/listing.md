# Daybloom: App Store Connect, field by field

Copy each box into App Store Connect. Character limits are already checked.
Things only you can fill in are marked **YOU**.

---

## App Information (left sidebar → App Information)

| Field | What to enter |
|---|---|
| Name (30 max) | `Daybloom: Schedule & Friends` (28) |
| Subtitle (30 max) | `Calendar, clock & friend chat` (29) |
| Primary category | Productivity |
| Secondary category | Lifestyle |
| Content rights | No, it does not contain, show, or access third-party content |
| Age rating | Answer the questions as in **Age rating** below |

## Pricing and Availability
- Price: **Free**
- Availability: all countries and regions (or just the ones you want)

## App Privacy (left sidebar → App Privacy)
- Privacy Policy URL: `https://vibe331212.github.io/daybloom/privacy.html`
- Answers: see `app-privacy.md` in this folder.

---

## Version 1.0 page (iOS App → 1.0 Prepare for Submission)

### Screenshots
Under **iPhone 6.9" Display**, drag in `screenshots/01-calendar.png` through `screenshots/08-timer.png`, in order.

### Promotional text (170 max)
```
Plan your days, see your friends' schedules, and chat privately. Reminders ring even when the app is closed, with 300 original ringtones and 11 relaxing scenes.
```

### Description (4000 max)
```
Daybloom is a calm, colorful planner for your whole day, made to share with the friends you know in real life.

PLAN YOUR DAYS
• A clean monthly calendar with an Up Next list
• Events that repeat every day, week, month, or year
• All-day events for trips, birthdays, and big days
• Reminders that ring even when Daybloom is closed
• Mark any event "Only me" to keep it private

FRIENDS, SCHEDULES, AND CHAT
• Add friends in person with a friend code that changes every 45 seconds
• See when your friends are free with their shared schedules
• Private one-on-one and group chats, only the people in a chat can read it
• Send photos, react to messages, and give groups their own name and icon
• Pick your own animal: fox, wolf, bear, panda, owl, and more

CLOCK
• A big clock with a sweeping second hand
• World clock: search any city and see its time
• Timer and a stopwatch that remembers what you were timing
• 300 original ringtones

MAKE IT YOURS
• 11 modes, each with its own relaxing moving scene: Royal gold dust, Nature with swaying trees, Ocean waves, Aurora northern lights, Midnight shooting stars, and more
• Brighten or deepen any mode with the screen shade slider

SAFE BY DESIGN
• Community rules everyone agrees to
• Report and block anyone, right from a message or chat
• A word filter that hides swear words and slurs
• Delete your account any time from Settings
• No ads, no tracking, and your information is never sold

Daybloom is for ages 13 and up.
```

### Keywords (100 max, commas, no spaces after commas)
```
planner,calendar,schedule,reminder,timer,stopwatch,world clock,homework,routine,alarm,group chat
```
(96 characters. Words already in the name, like "friends" and "schedule", count automatically, so they don't need to be repeated, but "schedule" here helps with the plural.)

### URLs
| Field | What to enter |
|---|---|
| Support URL | `https://vibe331212.github.io/daybloom/terms.html` |
| Marketing URL (optional) | `https://vibe331212.github.io/daybloom/` |

### Version and copyright
| Field | What to enter |
|---|---|
| Version | `1.0` (already set in the app) |
| Copyright | `2026 ` followed by **YOU**: your name, or your parent's if they own the developer account |

### Build
After I upload the app, click **Add Build** (the + next to Build) and choose build 1.0 (1).
If asked about encryption, the app already answers this for you (it only uses standard HTTPS).

### App Review Information
| Field | What to enter |
|---|---|
| Sign-in required | Yes |
| User name | `appreview` |
| Password | Copy from `review-account.local.txt` in the project folder (never commit it) |
| Contact first/last name, phone, email | **YOU**: Apple only uses these to reach you about the review |
| Notes | Copy everything under the line in `../ios/AppReviewNotes.md` |

### Version release
Choose **Manually release this version** for your first time, so you can press the button yourself once it's approved.

---

## Age rating
Answer Apple's age rating questions like this. Apple calculates the final rating from your answers; with chat and user content, expect **13+**, which matches Daybloom's rules.

| Question | Answer |
|---|---|
| Violence (cartoon, realistic, graphic) | None |
| Sexual content or nudity | None |
| Profanity or crude humor | None (in the app's own content) |
| Horror or fear themes | None |
| Alcohol, tobacco, drugs | None |
| Mature or suggestive themes | None |
| Simulated gambling / gambling / contests | None / No / No |
| Medical or treatment information | None |
| Unrestricted web access | No (links only open Daybloom's own pages in Safari) |
| User-generated content | **Yes** |
| Messaging and chat | **Yes** |
| Advertising | No |
| Parental controls / age assurance | No |
| Made for Kids | **No** (chat apps can't be in the Kids category) |
