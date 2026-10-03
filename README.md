# Thailand Trip 🇹🇭

An iPhone app for two people traveling Thailand together. It includes:

- a **shared itinerary** that syncs between both phones
- **walking directions** with a Google Maps hand-off
- "**where am I**" with photos of nearby sights
- **food and hotel ideas**
- a **baht ⇄ dollar** converter with shared expenses
- an **English ⇄ Thai translator** that works offline

It's built with Swift and SwiftUI for iOS 18 or later, using only Apple frameworks with no third-party code. Data is stored with Core Data and synced and shared through iCloud (CloudKit).

---

## What's in the app

| Tab | What you can do |
|---|---|
| **Trip** | Create a trip with dates; each day gets its own plan, and the **Wish List** holds places you haven't scheduled.<br><br>**Working with places:**<ul><li>Add places with photos, time, cost, link and notes.</li><li>Drag a place onto another day or the wish list.</li><li>Swipe right for **Done**, left to **Delete**.</li><li>🗺 shows a day's stops as numbered pins.</li><li>**Starter Ideas** covers Bangkok, Chiang Mai, Phuket, Krabi and Koh Samui.</li></ul>**Trip-level tools:**<ul><li>A shared **Packing** list.</li><li>**Share Trip** (👤+) invites your partner.</li><li>Tap the trip name for the menu: Emergency Info, Travel Documents, Your Name, switch or delete trips.</li></ul> |
| **Nearby** | <ul><li>The neighborhood and city you're in, plus steps and km walked today.</li><li>Weather with heat, UV and rain alerts.</li><li>**Today's Plan** with **Walk There** for each stop, or the whole day in Google Maps.</li><li>A Look Around preview and Wikipedia photos of landmarks within 5 km. Tap one for details, **Walk There**, or **Add to Wish List / Day**.</li><li>An optional **Auto-log** journal.</li><li>The 🆘 button opens emergency numbers.</li></ul> |
| **Explore** | **Eat / Stay / See** near you, or in any city you search ("Chiang Mai").<ul><li>Each result shows a photo, its distance and walking time.</li><li>Open a place to walk there (Apple or Google Maps), call it, visit its website, or get a Grab or Bolt ride.</li><li>Save any place to your trip.</li></ul>**Offline guides:** 30 **must-try dishes** with "Show to the vendor", the best **areas to stay** in each city, and **etiquette & scams**. |
| **Convert** | <ul><li>Two big THB/USD fields that update as you type, ⇅ to swap, and ฿20–฿1000 shortcuts.</li><li>"Rate as of…", a manual rate, and offline use with the last saved rate.</li><li>Tip & split calculator.</li><li>**Trip Spending** shows shared expenses and who owes whom.</li></ul> |
| **Translate** | <ul><li>Type or **hold the mic to talk**; the translation is shown and spoken.</li><li>**Talk** mode splits the screen so the other person reads Thai the right way up.</li><li>**Show** mode displays huge Thai text for a driver or vendor.</li><li>**Phrases** has about 80 offline phrases with romanization and the ครับ/ค่ะ polite ending.</li><li>History & favorites.</li><li>🔍 scans menus and signs with Live Text.</li></ul> |

**The walking tracker** opens from Walk There and works while the app is open:

- the route on a map, the next turn, and the distance and time left
- your arrival time, with re-routing if you go the wrong way
- **Google Maps** and **Apple Maps** buttons to hand off at any point

---

## What you need

- **A Mac with Xcode 16 or newer.** It's free in the Mac App Store.
- **An iPhone on iOS 18 or newer** for each traveler.
- **An Apple Developer Program membership** ($99/year). You have one; it's needed for iCloud sharing, Weather and TestFlight.
- **Both travelers signed in to iCloud** on their iPhones (Settings → your name), with **iCloud Drive turned on**.

---

## Part 1: Run it on your iPhone from Xcode

1. Open Terminal on your Mac and run:
   ```bash
   git clone https://github.com/kbreed1280/Thailand.git
   cd Thailand
   open Thailand.xcodeproj
   ```
   Later, run `git pull` in that folder to get updates.
2. **Add your developer account to Xcode:** Xcode → Settings → Accounts → **+** → Apple ID. Sign in with the Apple ID that has the developer membership.
3. **Set up signing:**
   1. Click the blue **Thailand** project at the top of the left sidebar.
   2. Select the **Thailand** target and open the **Signing & Capabilities** tab.
   3. Check **Automatically manage signing**.
   4. Set **Team** to your developer team (not "Personal Team").
   5. If Xcode says the bundle identifier is taken, change `com.kbreed.thailandtrip` to something unique, such as `com.yourname.thailandtrip`. Then change the iCloud container in the next step to match.
4. **Turn on iCloud:**
   1. Scroll down to the **iCloud** section in the same tab. CloudKit should already be checked.
   2. Under **Containers**, make sure `iCloud.com.kbreed.thailandtrip` is checked. If it shows in red or isn't listed, click **+** and type exactly `iCloud.com.kbreed.thailandtrip`.
   3. If you changed it, also update `containerIdentifier` in `Thailand/Services/Persistence/PersistenceController.swift` and in `Thailand.entitlements`.
5. **Turn on WeatherKit** (for the weather card):
   1. Sign in at [developer.apple.com/account](https://developer.apple.com/account) and go to **Certificates, IDs & Profiles** → **Identifiers**.
   2. Open your app's identifier.
   3. Check **WeatherKit** on the **Capabilities** tab *and* on the **App Services** tab, then Save.
   4. Wait about 30 minutes. Until then, the Nearby tab just says "Weather unavailable".
6. **Prepare your iPhone:**
   1. Plug it into the Mac and tap **Trust** on the phone if asked.
   2. Turn on Developer Mode: **Settings → Privacy & Security → Developer Mode → On**. The phone restarts.
7. **Run it:** in Xcode's toolbar, choose your iPhone as the destination and press **⌘R**.

> **Tip:** on the Trip tab, tap **Try the Demo Trip** to see everything filled in. You can delete it later from the trip menu.

---

## Part 2: Prepare iCloud for sharing (one-time)

The app syncs trips through **CloudKit**. While you run from Xcode, it uses CloudKit's **Development** environment and creates the data layout (the "schema") automatically. TestFlight and App Store builds use the **Production** environment, so you have to copy the schema there **once** before your partner installs from TestFlight.

1. Run the app from Xcode on your iPhone and create every kind of data at least once:
   1. Load the demo trip; it includes days, places, packing items and expenses.
   2. Add a photo to a place.
   3. Turn on **Auto-log** on the Nearby tab once (that creates a journal entry).
   4. Wait a minute with Wi-Fi on so it syncs.
2. Open the [CloudKit Console](https://icloud.developer.apple.com/) → **CloudKit Database** → choose `iCloud.com.kbreed.thailandtrip` → **Development**.
3. Click **Deploy Schema Changes…** and confirm it to **Production**.

**Schema notes (for reference):**

- Core Data creates these record types: `CD_Trip`, `CD_Day`, `CD_Item`, `CD_ItemPhoto`, `CD_VisitLog`, `CD_Expense` and `CD_PackingItem`.
- Each attribute is stored as a field named `CD_<attributeName>`. Photos are stored as CKAssets.
- Sharing uses CloudKit zone sharing: each shared trip lives in its own zone with a `CKShare`.
- Your own trips live in the **private** database. Trips others share with you live in the **shared** database.
- If you add a new field later, run once from Xcode, then deploy the schema again.

> **Important:** a phone running an **Xcode build** (Development) and a phone running a **TestFlight build** (Production) **can't see each other's trips.** For sharing, both of you should use TestFlight builds, or both use Xcode builds.

---

## Part 3: Get the app onto your travel partner's iPhone (TestFlight)

1. **Create the app record:**
   1. Go to [App Store Connect](https://appstoreconnect.apple.com) → **Apps** → **+** → **New App**.
   2. Platform iOS. Pick a name that's unique on the App Store, such as "Thailand Trip – yourname".
   3. Choose your bundle ID, enter any SKU, and click Create.
2. **Upload a build:**
   1. In Xcode, set the destination to **Any iOS Device (arm64)**.
   2. Choose **Product → Archive** and wait for the Organizer window.
   3. Click **Distribute App → TestFlight & App Store → Distribute**.
   4. The upload takes a few minutes. Processing on Apple's side takes 10–30 more.
3. **Invite your partner as a tester:**
   1. In App Store Connect, go to **Users and Access** → **+** and invite your partner's Apple ID email with any role (for example "Customer Support"). They accept the email.
   2. Open your app → **TestFlight** → **Internal Testing** → **+** to create a group. Add your partner and the build.
   3. Internal testing doesn't need App Review, so the build is available right away.
4. **Your partner installs it:** they install Apple's **TestFlight** app from the App Store, open the invite email on their iPhone, tap **View in TestFlight**, then **Install**.
5. **Install the TestFlight build on your phone too** (see the Important note in Part 2).
6. **Share the trip:**
   1. On your phone, open the trip and tap **👤+**.
   2. Choose **Messages** (or Mail, or copy the link) and send it to your partner. They can **edit** by default; tap **Share Options** to make someone view-only.
   3. Your partner taps the link on their iPhone, and the app opens with "Joining the shared trip…".
   4. The trip appears within a minute. After that, anything either of you adds, edits or checks off shows up on both phones, usually within seconds when online.
   5. Offline changes sync when you reconnect.
   6. To change permissions or stop sharing later, tap the 👥 button again.

TestFlight builds expire after 90 days. Upload a new archive if you need more time.

---

## Part 4: Pre-trip checklist (do this on Wi-Fi, before the flight)

- [ ] **Translate tab → Download** the Thai language pack. You can also do it in Settings → Apps → Translate → Downloaded Languages. Without it, translation needs internet. The phrasebook always works offline.
- [ ] **Download a Thai voice** for the speak buttons: Settings → Accessibility → Spoken Content → Voices → Thai → download a voice (Enhanced sounds best).
- [ ] **Open the Convert tab** so the exchange rate is saved for offline use.
- [ ] **Download offline maps** of each city:
  - **Google Maps:** profile picture → Offline maps → Select your own map.
  - **Apple Maps:** profile picture → Offline Maps.

  Walking directions in the app need internet, but Google and Apple Maps can work offline.
- [ ] **Open each tab once** so iOS asks for Location (While Using), Microphone, Speech Recognition, Motion & Fitness and Camera. Choose **Allow**.
- [ ] **Accept the shared trip** on your partner's phone and check that an edit on one phone appears on the other.
- [ ] **Trip menu → Emergency Info:** paste your hotel's address in Thai (ask the hotel or copy it from the booking).
- [ ] **Trip menu → Travel Documents:** add photos of passports, visas, flights and hotel bookings. They stay only on that phone, locked with Face ID.
- [ ] **Translate tab → 👤 menu:** choose the polite ending, ครับ khráp (male speaker) or ค่ะ khâ (female speaker).
- [ ] **Add Starter Ideas** for your cities and the packing essentials.

---

## Privacy

- **Location:** used only while the app is open (When In Use). There is no background tracking. Auto-log records a stop only while the Nearby tab is open.
- **Sharing:** trips sync through your own iCloud account. Only people you invite can see a shared trip.
- **Stays on your phone:** translation history and favorites, plus the travel documents vault, which also requires Face ID or your passcode.
- **On-device processing:** translation runs on the phone with Apple's Translation framework once Thai is downloaded. Live Text scanning also runs on the phone.

---

## For developers

```
Thailand.xcodeproj            Xcode 16 project; Thailand/ and ThailandTests/ are synced folders
Thailand-Info.plist           extra Info.plist keys (URL schemes, CKSharingSupported, push)
Thailand.entitlements         iCloud/CloudKit, push, WeatherKit
Thailand/
  App/                        app entry, AppDelegate/SceneDelegate (share acceptance), tabs
  Models/                     Core Data model (in code), entities, ordering, currency math,
                              phrasebook, food/stay/etiquette guides, starter ideas, demo trip
  Services/
    Persistence/              CloudKit container (private + shared stores), itinerary store, sharing
    Location/                 location, place search, walking navigator
    Places/                   POI search, Look Around/map images, Wikipedia, Google Maps/Grab/Bolt
    Currency/ Network/        exchange rates, online/offline
    Translation/ Speech/      TranslationSession model, history, speech-to-text, text-to-speech
    Weather/ Motion/ Vault/   WeatherKit, pedometer, Face ID document vault
    Permissions/ Imaging/
  Views/                      Trip, Nearby, Explore, Convert, Translate, Extras, Components
ThailandTests/                itinerary ordering + currency math unit tests
```

- **Continuous integration:** every push is built and the unit tests run on an iPhone simulator by GitHub Actions ([.github/workflows/ios-build.yml](.github/workflows/ios-build.yml)).
- **Run the tests:** press ⌘U in Xcode.

### Known limitations

- **Tested only in CI so far.** The app was written without a Mac and checked by CI (it builds with no warnings and the tests pass). Camera, voice, Translation, Look Around, Weather and CloudKit sharing need testing on real iPhones.
- **Grab and Bolt** don't publish a destination deep link. The app copies the address and opens the app (or its App Store page), and you paste it into "Where to?".
- **Look Around coverage** in Thailand is limited (mostly central Bangkok). Elsewhere you'll see a map snapshot instead.
- **Newer Xcode versions** may show deprecation warnings for `CLGeocoder` and `MKPlacemark`. These are fine on iOS 18.

### Planned next (steps 8–10)

These are Tripsy-style additions:

- **Step 8:** a day timeline with walking time between stops and "running late" warnings, saved places such as the hotel, and trip colors and covers.
- **Step 9:** bookings with Smart Import (scan a confirmation and it becomes itinerary items), plus calendar sync.
- **Step 10:** a shareable **Trip Book**, plus Siri and Shortcuts.
