<p align="center">
  <img src="App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="112" alt="SENSE app icon">
</p>

<h1 align="center">SENSE</h1>

<p align="center"><strong>AI that understands the world around you.</strong></p>

<p align="center">
  A native iPhone app that turns what you see, photograph, say and type into structured memories, reminders and answers — on your device, without a subscription.
</p>

---

## What is SENSE?

Every day you run into things you need to remember or act on: a poster announcing a registration deadline, a receipt, a lab safety sheet, a component on a workbench, a thought you have on the way to class. Today that information ends up scattered across photos, notes and reminder apps, and you're the one doing the organizing.

SENSE removes that step. You capture something; SENSE works out what it is, what matters in it, and what you might want to do about it.

```
Capture something  →  SENSE understands it  →  Remember it, act on it, find it again
```

SENSE is not a chatbot, a notes app or a reminders app. It is a contextual memory for the physical world.

## What it does

| Capability | How it works |
| --- | --- |
| **Camera & photo understanding** | Text recognition (Vision) and image classification run on device. SENSE classifies the capture (announcement, receipt, document, event, object, note…) and extracts dates, deadlines, amounts, merchants, warnings, requirements, links, phone numbers and emails. |
| **"What's important here?"** | A live camera view (VisionKit) highlights text as you point at it. Tap the button and SENSE explains what matters in the scene. |
| **Voice capture** | Speech is transcribed with Apple's Speech framework, on device by default. |
| **Natural-language intents** | Speech and text are routed automatically: *"Remind me about this when I get to the university"* creates a place reminder for your latest capture, *"What did I capture yesterday?"* searches, *"Have I seen this before?"* finds similar memories, anything else becomes a memory. |
| **Structured memory** | Captures are stored as typed memories with highlights, entities, tags, the original text, an optional photo and an optional place. |
| **Search** | Hybrid search: BM25 keyword ranking with stemming, plus vector similarity using Apple's on-device sentence embeddings. Queries understand time ("last week", "yesterday", "on Monday"), places ("at the university") and memory types ("receipts", "announcements"). |
| **Reminders** | Deadlines found in captures are offered as one-tap reminders, scheduled a sensible lead time ahead (for example, the day before a deadline). Time-based and arrive/leave place-based reminders use local notifications. |
| **Places** | Places you choose (via search, or your current location) are remembered by name, so "the university" resolves automatically next time. |
| **Optional AI provider** | Connect any OpenAI-compatible server (Ollama, LM Studio, llama.cpp or a hosted API) for richer titles and summaries. If it isn't configured or can't be reached, SENSE falls back to on-device understanding. |

### Example

You photograph a poster:

> **FALL SEMESTER REGISTRATION**
> Registration closes October 8 at 4 PM.
> Students must bring their ID card to the registrar office.

SENSE files it as an *Announcement* titled "Fall Semester Registration", highlights the deadline and the ID requirement, and suggests a reminder — **"Registration closes · Due Oct 8, 4:00 PM"** — set for the day before. One tap adds it, and you can adjust the time.

## Privacy model

Privacy is a product requirement, not a setting.

- **On device by default.** Text recognition, image classification, transcription (when supported for your language), understanding, embeddings and search all run on the iPhone. No account, no analytics, no tracking.
- **Explicit, contextual permissions.** Onboarding requests nothing. The camera, microphone, speech recognition, location and notifications are each requested the first time you use a feature that needs them, with a plain explanation. Photos are picked through the system photo picker, so SENSE never has access to your library.
- **No background sensing.** The microphone is only active while the voice sheet is open. The camera is only active while a capture view is open. SENSE never tracks your location: place reminders use iOS region monitoring, which wakes the app only when you arrive at or leave a place you chose.
- **Location tagging is opt-in.** Memories are only tagged with where they were captured if you turn that on in Settings.
- **Local, protected storage.** Memories, reminders and places are stored with SwiftData under iOS data protection; photos are written with complete file protection, so they are encrypted whenever the device is locked. API keys go in the Keychain, scoped to this device.
- **You control external AI.** Only the recognized *text* of a capture is sent to a provider you configure yourself. Photos and audio are never sent. Dates, reminders and search always stay on device.
- **One-tap erase.** Settings → Erase All SENSE Data removes memories, photos, reminders and places.

## Architecture

SENSE is split into a platform-independent core and a thin iOS layer.

```
SENSE/
├── Packages/SenseCore/           Swift package. No UI and no Apple-only frameworks; builds and tests on macOS and Linux.
│   ├── Models/                   Capture input, memory kinds, highlights, entities, reminders, understanding.
│   ├── Understanding/            DateExtractor, EntityExtractor, ContentAnalyzer, IntentParser.
│   ├── Search/                   QueryParser, MemorySearchEngine (BM25 + vectors), TextEmbedder, HashingEmbedder.
│   ├── Providers/                IntelligenceProvider protocol, on-device provider, OpenAI-compatible provider, fallback.
│   └── Text/                     Tokenization, stemming, pattern helpers.
├── App/                          The iOS app (SwiftUI, iOS 17+).
│   ├── Application/              App entry point and AppModel (composition root, command routing).
│   ├── Perception/               Vision OCR + classification, speech transcription, sentence embeddings, capture pipeline.
│   ├── Persistence/              SwiftData models, memory/reminder/place stores, protected image storage.
│   ├── Services/                 Permissions, location, notifications, network status, settings, Keychain.
│   ├── Features/                 Home, Capture review, Live look, Voice, Text, Memories, Reminders, Places, Settings, Onboarding.
│   └── Shared/                   Reusable views and presentation helpers.
├── web/                          Installable web app (PWA): SenseCore logic in TypeScript, Preact UI, IndexedDB storage.
├── Config/                       Build configuration (signing values live in an ignored Local.xcconfig).
└── project.yml                   XcodeGen project definition.
```

**Capture pipeline**

```
Camera / Photo / Live ──► Vision (text + labels) ─┐
Voice ──► Speech (on device) ──► IntentParser ────┼──► CaptureInput ──► IntelligenceProvider ──► Understanding ──► Review ──► Memory + Reminders
Text ─────────────────────────► IntentParser ─────┘                         │
                                                                             ├─ OnDeviceIntelligence (default, rule-based, free)
                                                                             └─ OpenAICompatibleIntelligence (optional, falls back on error)
```

**Key decisions**

- **Provider abstraction.** `IntelligenceProvider` is a single async protocol. The remote provider *refines* the on-device result (title, summary, extra highlights) rather than replacing it, so dates and reminders stay deterministic and never depend on a network call.
- **Deterministic understanding first.** The on-device analyzer uses explicit parsing for dates (absolute, numeric, relative, weekday, durations, time pairing), money, contacts and statement-level cues. It is predictable, fast, testable and free.
- **Pluggable embeddings.** `TextEmbedder` lets search swap embedding models. The app combines a feature-hashing embedder with Apple's `NLEmbedding` sentence model; memories are re-embedded automatically when the model changes.
- **Testable core.** Everything that doesn't need UIKit lives in `SenseCore` and is covered by unit tests that run on Linux and macOS.

## Getting started

### Requirements

- macOS with **Xcode 16** or later
- **iOS 17** or later (an iPhone is recommended: the camera, live text scanning, on-device speech and region monitoring need real hardware)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (free)

### Run the app

```bash
git clone https://github.com/yousef-yasin/SENSE.git
cd SENSE
scripts/setup.sh
```

`scripts/setup.sh` installs XcodeGen with Homebrew if it's missing, generates `SENSE.xcodeproj` from `project.yml` and opens it in Xcode. The manual equivalent is `brew install xcodegen && xcodegen generate && open SENSE.xcodeproj`.

Select the **SENSE** scheme and run. No API keys or accounts are needed.

### Install on your iPhone

A free Apple ID is enough. SENSE uses no capabilities that require a paid Apple Developer Program membership (no push notifications, iCloud or App Groups).

1. **Mac:** install Xcode from the Mac App Store and open it once. Use the latest release: an older Xcode can't install apps on an iPhone running a newer iOS.
2. **Mac:** in Xcode → *Settings* → *Accounts*, add your Apple ID. A *Personal Team* is created for it.
3. **iPhone:** connect it to the Mac with a cable, unlock it and tap *Trust This Computer*.
4. **Mac:** run `scripts/setup.sh` in the cloned repository.
5. **Xcode:** select the **SENSE** project → **SENSE** target → *Signing & Capabilities*, keep *Automatically manage signing* on, and choose your team.
   If Xcode says the bundle identifier isn't available, change it there to something unique, such as `app.sense.ios.yourname`.
6. **Xcode:** in the toolbar, choose the **SENSE** scheme and your iPhone as the run destination, then press **⌘R**.
7. **iPhone:** if prompted, turn on *Settings* → *Privacy & Security* → *Developer Mode* and restart. After the first install, if iOS says the developer isn't trusted, open *Settings* → *General* → *VPN & Device Management*, select your Apple ID and tap *Trust*. Press **⌘R** again.

`xcodegen generate` recreates the project and discards a team chosen in Xcode. To keep it, sign through the ignored `Config/Local.xcconfig` instead: run `scripts/setup.sh TEAM_ID [BUNDLE_ID]`, where `TEAM_ID` is shown in Xcode under the target's *Build Settings* → *Development Team* once a team is selected.

With a free Apple ID, the app stops launching after 7 days; connect the iPhone and press ⌘R to reinstall. Memories on the device are kept. A paid membership extends this to one year and is required for TestFlight or the App Store.

### Web app (PWA)

A web version of SENSE runs in any modern browser at **https://yousef-yasin.github.io/SENSE/**. It needs no install, account or API key. On iPhone, open it in Safari, tap **Share → Add to Home Screen**, and SENSE opens full screen like an app. In Chrome or Edge on Windows, use **Install SENSE** in the address bar or menu.

The web app lives in [`web/`](web) and reuses SenseCore's logic, ported to TypeScript. The same unit tests are ported too, so the TypeScript and Swift versions are checked against the same cases. Everything runs in the browser, and data is stored only in that browser on that device.

| Capability | Web app |
| --- | --- |
| Camera & photos | Take or choose a photo, or use the live camera view. Text is read on device with [Tesseract.js](https://github.com/naptha/tesseract.js); its English model downloads once on first use and is then cached. |
| Understanding, memories, search | Same rules as the iPhone app: classification, dates, deadlines, amounts, contacts, intents, keyword and similarity search. Stored in IndexedDB. |
| Voice | Uses the browser's speech recognition (Safari, Chrome, Edge). Depending on the browser, audio may be processed by Apple or Google. Where it's unsupported, the Text sheet and keyboard dictation still work. |
| Reminders | Time-based reminders send a notification if one comes due while SENSE is open (on iPhone, notifications need the Home Screen app, iOS 16.4+). Due reminders are also shown when you next open SENSE. **Add to Calendar** exports any reminder as an `.ics` event, so the system calendar alerts you even when SENSE is closed. |
| Not available on the web | Place-based reminders (browsers can't monitor regions in the background), image classification of objects without text, and location tagging. Use the iPhone app for these. |
| Optional AI provider | Any OpenAI-compatible endpoint that is served over HTTPS and allows cross-origin requests. A plain-HTTP server on your local network can't be reached from the hosted page. |

```bash
cd web
npm install
npm test          # unit tests (core logic + calendar export)
npm run dev       # local development server
npm run build     # production build in web/dist
```

Every push to `main` that changes `web/` runs the tests, builds the app and publishes it to the `gh-pages` branch, which GitHub Pages serves.

### Run the tests

```bash
swift test --package-path Packages/SenseCore
```

The core tests also run in Xcode through the SENSE scheme (⌘U) and in CI on both Linux and macOS.

### Optional: connect a local AI model

SENSE works fully without this. To try richer summaries for free with [Ollama](https://ollama.com):

1. On your Mac: `ollama pull llama3.2`, then start Ollama so it listens on your network (`OLLAMA_HOST=0.0.0.0 ollama serve`).
2. In SENSE: *Settings → Understanding → OpenAI-compatible server*.
3. Base URL `http://<your-mac-ip>:11434/v1`, model `llama3.2`, and no API key. Tap **Test Connection**.

Any OpenAI-compatible endpoint works the same way. Hosted services need an API key, which is stored in the Keychain.

## Current limitations

These are known gaps in the current version, stated plainly:

- The on-device analyzer is rule-based and tuned for **English**. Other languages get OCR and transcription, but fewer extracted highlights.
- Semantic recall is lightweight. *"Electronics component"* finds a capture labelled *electronics*, but loosely related phrasings may not match without shared words.
- iOS limits an app to **20 active place reminders**; SENSE enforces that limit.
- The live camera view needs a device that supports VisionKit's data scanner (A12 Bionic or newer).
- People are only remembered when you explicitly write or say them. SENSE does no face recognition.

## Roadmap

- Apple Foundation Models (on-device LLM) as an additional provider where available
- Multilingual date and entity extraction
- Calendar export for events, and Reminders app integration
- Share extension and widgets for faster capture
- Shortcuts / App Intents ("Ask SENSE…")
- Encrypted iCloud sync, opt-in
- Richer object understanding via on-device Core ML models

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

SENSE is released under the [MIT License](LICENSE).
