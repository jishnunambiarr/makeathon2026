# CampusPal (agent-first demo fork)

This repository is a **demo fork** of the open-source [TUM Campus Flutter app](https://github.com/TUM-Dev/campus_flutter).

For this demo, we re-imagine the app for the **agentic era**:

- A voice agent (ElevenLabs “Eva”) is integrated directly into the app
- The agent can **navigate** the app using whitelisted client tools (open screens, search, shortcuts)
- A minimal local Node backend mints short-lived conversation tokens (keeps secrets off-device)

## Features

- [x] Calendar Access
- [x] Lecture Details
- [x] Grades
- [x] Tuition Fees Information
- [x] Study Room Availability
- [x] Cafeteria Menus
- [x] Room Maps
- [x] Universal Search: Room
- [x] [TUM.sexy](https://tum.sexy) Redirects

<!--
## Screenshots

| | | | |
|-|-|-|-|
|![Simulator Screen Shot - iPhone 12 Pro Max - 2021-01-11 at 03 07 47](https://user-images.githubusercontent.com/7985149/107104416-d9125980-6821-11eb-8c06-bc26512e65fb.png)|![Simulator Screen Shot - iPhone 12 Pro Max - 2021-01-11 at 03 08 14](https://user-images.githubusercontent.com/7985149/107104419-da438680-6821-11eb-83ad-d0cd16c3fe33.png)|![Simulator Screen Shot - iPhone 12 Pro Max - 2021-01-11 at 03 09 44](https://user-images.githubusercontent.com/7985149/107104428-e3345800-6821-11eb-9169-7e76459a096c.png)|![Simulator Screen Shot - iPhone 12 Pro Max - 2021-01-11 at 03 09 51](https://user-images.githubusercontent.com/7985149/107104433-e7f90c00-6821-11eb-8e2b-42d21b2ced66.png)|
-->

<!--
## Contributing
You're welcome to contribute to this app!
Check out our detailed information at [CONTRIBUTING.md](https://github.com/TCA-Team/iOS/blob/master/CONTRIBUTING.md)!
-->

## Upstream

This is a demo fork. The official upstream project is maintained at:

- https://github.com/TUM-Dev/campus_flutter

## Development

To develop this project, you need these dependency's installed. If you have any problems with any of the steps below, please open an issue.
Please refer to the respective installation instructions:

| Dependency                               | Usage                                    | where to download it                         |
|------------------------------------------|------------------------------------------|----------------------------------------------|
| `Flutter` (includes the `Dart` compiler) | SDK to develop this app                  | https://docs.flutter.dev/get-started/install |

## Local voice agent (ElevenLabs) – dev setup

This repo includes a **hackathon/demo** voice agent integration:

- Flutter uses `elevenlabs_agents` for a realtime session (WebRTC)
- A small Node backend mints short-lived conversation tokens (keeps `XI_API_KEY` off-device)
- The model invokes **client tools** that run **inside the app** (navigation, calendar, search, …)

**Setup guide:** [docs/AGENT_SETUP.md](docs/AGENT_SETUP.md) — duplicate our ElevenLabs agent, add your API key, run the token server, set `AGENT_BACKEND_URL`.

### Quick start

1. **ElevenLabs:** duplicate (or import) the project’s reference agent, then create an **API key**. Put the **new** agent’s ID and the key in `.env` (see guide).

2. **Backend:**

```bash
cd backend/agent-server
cp .env.example .env   # then set XI_API_KEY and ELEVEN_AGENT_ID
npm install
npm run dev
```

Health check: `GET http://127.0.0.1:8787/healthz`

3. **Flutter** (set backend URL for your device):

| Target | `AGENT_BACKEND_URL` |
|--------|---------------------|
| Android emulator | `http://10.0.2.2:8787` |
| iOS Simulator | `http://127.0.0.1:8787` |
| Physical device | `http://<your PC LAN IP>:8787` |

```bash
flutter run --dart-define=AGENT_BACKEND_URL=http://10.0.2.2:8787
```

### Permissions

- Android: `RECORD_AUDIO` (for voice)
- iOS: `NSMicrophoneUsageDescription`

### Updating the `.proto` files

To update the generated stubs for the Campus, you need protoc installed, then activte it in dart and then you can generate the new client

```bash
dart pub global activate protoc_plugin
export PATH="$PATH:$HOME/.pub-cache/bin"
curl -o protos/tumdev/campus_backend.proto https://raw.githubusercontent.com/TUM-Dev/Campus-Backend/main/server/api/tumdev/campus_backend.proto
protoc --dart_out=grpc:lib/base/networking/apis -I./protos google/protobuf/timestamp.proto google/protobuf/empty.proto tumdev/campus_backend.proto 
```

### Currently needed Forks

To ensure that campus_flutter runs on every supported platform, we need to make some modifications to packages.

| Package         | Reason                              | Link                                            |
|-----------------|-------------------------------------|-------------------------------------------------|
| gRPC            | Caching                             | https://github.com/jakobkoerber/grpc-dart       |
| Xml2Json        | Fix Parsing of XML to JSON          | https://github.com/jakobkoerber/xml2json        |
| flutter_linkify | Fix Selection Menu and Text Scaling | https://github.com/jakobkoerber/flutter_linkify |



