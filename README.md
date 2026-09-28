# HeirLoom

HeirLoom is a native iOS application and backend platform designed to preserve family history, oral traditions, and intergenerational connections. 

At the center of the system is Loomie, an oral historian voice agent powered by real-time speech and state-managed conversation memory. Spoken stories are processed, parsed, and automatically organized into an interactive corkboard family tree, generational connection matches ("Sparks"), and a 3D ancestral map

Note: This project won the Meta Track at hackGT

---

## Core Features

- **Conversational Oral History (Loomie):** Full-duplex spoken dialogue with low latency using xAI's real-time voice streaming. The agent guides conversations using sensory-focused follow-ups to record life stories without clinical questioning.
- **Dynamic Corkboard Family Tree:** Renders an evidence-board-style family tree in SwiftUI with pushpins, calculated card tilts, and red twine strings connecting spouses, parents, and children.
- **Cross-Generational Sparks:** Automatically analyzes new stories against the wider family archive to identify shared passions, trades, and hobbies between distant relatives or across generations.
- **3D Living Heritage Globe:** An interactive MapKit globe that plots ancestral hometowns, migration paths, and story locations.
- **iOS Share Extension:** Enables family members to share photos, notes, and external media directly into the family archive from any app via the native iOS share sheet.
- **Persistent State & Memory:** Uses Backboard.io state machines to ground conversations in previous family knowledge and maintain long-term memory across sessions.

---

## System Architecture

```
                  ┌────────────────────────────────────────┐
                  │          iOS Client (SwiftUI)          │
                  │  - Real-Time Audio (AVFoundation)      │
                  │  - Interactive Corkboard Engine        │
                  │  - 3D Heritage Globe (MapKit)          │
                  │  - Native ShareSheet Extension         │
                  └───────┬────────────────────────┬───────┘
                          │                        │
      Bidirectional Audio │ 24kHz PCM              │ REST / JSON
                          ▼                        ▼
       ┌────────────────────────────┐    ┌───────────────────────────┐
       │     xAI Realtime API       │    │     FastAPI Backend       │
       │  (grok-voice-latest: eve)  │    │  (heirloom-api / Python)  │
       └────────────────────────────┘    └──────┬─────────────┬──────┘
                                                │             │
                                                ▼             ▼
                                     ┌──────────────┐   ┌────────────┐
                                     │ Backboard.io │   │  MongoDB   │
                                     │ State Engine │   │   Atlas    │
                                     └──────────────┘   └────────────┘
```

- **Client:** Native iOS 17+ application built with Swift and SwiftUI.
- **Voice Pipeline:** Sub-second full-duplex audio over WebSockets using `AVAudioEngine` and xAI's Realtime Voice API.
- **Agent Intelligence:** xAI Grok (4.3) via the official `xai-sdk` for entity extraction, story summarization, and kinship graph resolution.
- **State & Memory:** Backboard.io REST API managing persistent conversational threads and assistant-scoped memory vectors.
- **Backend API:** FastAPI application utilizing `motor` for asynchronous MongoDB Atlas operations.
- **Data Store:** MongoDB Atlas storing members, stories, items, and relationship collections.

---

## Repository Structure

```
├── heirloom_GT/               # Main iOS application source code
│   ├── Screens/               # SwiftUI views (Corkboard, Globe, Feed, Chat)
│   ├── Model/                 # State controllers and data models
│   ├── LoomVoiceSession.swift # WebSocket voice streaming and audio I/O
│   └── AppConfiguration.swift # Client-side runtime configuration
├── HeirLoomShareExtension/    # Native iOS Share Extension target
├── heirloom-api/              # FastAPI server and agent processing pipeline
│   ├── main.py                # REST endpoints and database routing
│   ├── archive_manager.py     # Grok extraction agent and spark discovery
│   ├── backboard_sync.py      # Backboard.io state machine synchronization
│   ├── tree_engine.py         # Corkboard graph layout and coordinate solver
│   └── requirements.txt       # Python dependencies
├── win-loomie/                # Standalone local web preview harness for testing
├── scripts/                   # Database setup and synchronization utilities
└── middleware/                # Shared environment configuration
```

---

## Prerequisites

- **iOS Development:** macOS running Xcode 15.0 or later with iOS 17.0+ SDK.
- **Backend Development:** Python 3.10 or newer.
- **API Keys & Services:**
  - xAI API Key (with access to Grok chat and real-time voice endpoints)
  - Backboard.io API Key
  - MongoDB Atlas database cluster

---

## Getting Started

### 1. Backend Service Setup

Navigate to the API directory and configure your environment:

```bash
cd heirloom-api
python -m venv venv
# Windows:
.\venv\Scripts\activate
# macOS/Linux:
source venv/bin/activate

pip install -r requirements.txt
```

Create a `.env` file in `heirloom-api/` (or `middleware/.env`):

```env
XAI_API_KEY="your-xai-api-key"
BACKBOARD_API_KEY="your-backboard-api-key"
MONGODB_URI="mongodb+srv://<user>:<password>@<cluster>.mongodb.net/?retryWrites=true&w=majority"
MONGODB_DATABASE="HeirLoomDb"
HEIRLOOM_API_TOKEN="optional-secure-token"
HEIRLOOM_FAMILY_ID="default-family-id"
```

Initialize the database collections and seed data if needed:

```bash
python ../scripts/setup_mongodb.py
```

Start the API server:

```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

The API documentation will be accessible at `http://localhost:8000/docs`.

---

### 2. iOS Application Setup

1. Open `heirloom_GT.xcodeproj` in Xcode.
2. Ensure your active development team is configured under Signing & Capabilities for both `heirloom_GT` and `HeirLoomShareExtension`.
3. Check `heirloom_GT/AppConfiguration.swift` to verify API endpoint targets and key mappings.
4. Select a physical iPhone or simulator running iOS 17+ and press **Run** (Cmd + R).

*Note: Live microphone testing for LoomVoiceSession requires a physical iOS device with microphone permissions enabled.*

---

### 3. Local Web Preview (Optional)

A lightweight browser-based preview server is included in `win-loomie/` for testing Loomie's voice agent logic without compiling the iOS app:

```bash
cd win-loomie
python server.py
```

Open `http://localhost:8765` in your browser.

---

## License

This project was built for hackathon demonstration. All rights reserved.
