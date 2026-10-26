# Ganacsi AI — Frontend (Qaybta 1)

App-ka Flutter oo **keligiis shaqeeya**, backend la'aan. Wuxuu leeyahay *demo mode* ka kooban xog tijaabo ah (8 alaab, 4 macmiil, iib 14 maalmood ah, kharash, invoices), taas oo ku kaydsan telefoonka.

## Socodsiinta

**Shuruud:** Flutter 3.27 ama ka cusub (`flutter --version`)

```bash
cd mobile
flutter create . --platforms=android,ios --org com.ganacsiai   # abuur android/ iyo ios/ (file-yada jira lama beddelo)
flutter pub get
flutter run                                                    # emulator ama telefoon ku xiran
flutter test                                                   # tijaabooyinka
```

Login-ka ka dib, riix **"Gal demo-ga"** (ama geli `615000000` / `demo123`). Waxaad sidoo kale samayn kartaa akoon cusub, kaas oo bilaabanaya isagoo madhan.

APK lagu rakibo telefoon: `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`

## Shaashadaha

| Tab | Waxa ku jira |
|---|---|
| **Guud** | Iibka, faa'iidada, kharashka, deynta · talooyin · chart 7 maalmood · alaabta ugu iibka badan · stock dhammaanaya |
| **Iib** | Liiska iibka (maanta/toddobaad/bil/sannad) · iib cusub (cart, macmiil, EVC Plus/Zaad/Sahal/e-Dahab/kaash, deyn qayb ah) · rasiid WhatsApp · tirtir |
| **Kaaliye** | Chat (demo: jawaabo ku salaysan xogta, sida iibka, stock-ga, deynta, faa'iidada, fariin WhatsApp iyo talooyin) |
| **Stock** | Alaab ku dar ama wax ka beddel · +/− stock · filter "dhammaanaya" |
| **Kale** | Macaamiil & deyn · kharash · invoices · warbixinno P&L · profile · dib u deji xogta demo-ga |

## Qaab-dhismeedka

```
lib/
├── main.dart              theme + auth gate
├── config.dart            USE_MOCK iyo API_URL
├── models/models.dart     Product, Sale, Customer, Invoice...
├── services/
│   ├── api.dart           HTTP client (wuxuu u diraa mock ama server)
│   ├── mock_backend.dart  backend tijaabo ah (Qaybta 1)
│   └── auth_state.dart    login / logout
├── screens/               12 shaashadood
├── widgets/common.dart    StatCard, chart, loading/error
└── utils/format.dart      lacag, taariikh, qoraallo
```

`mock_backend.dart` wuxuu isticmaalaa **isla endpoints-ka iyo isla JSON-ka** ee backend-ka dhabta ah, sidaas darteed Qaybta 2 shaashadaha waxba lagama beddelayo.

## Qaybta 2: ku xirida backend-ka

Tani waa tusaale **debug Android emulator** oo ku xiran server-ka isla kombiyuutarka:

```bash
flutter run --dart-define=USE_MOCK=false --dart-define=API_URL=http://10.0.2.2:3000
```

HTTP waxaa loo oggol yahay debug Android oo keliya. iOS wuxuu u baahan yahay URL HTTPS oo ay oggolaanayso App Transport Security. Dhammaan release builds-ku waxay u baahan yihiin `API_URL` HTTPS ah; ha ku darin xog dhab ah ama JWT URL HTTP ah.
