# CLAUDE.md — punto d'ingresso per le sessioni di Claude Code

Primo file da leggere all'avvio di ogni sessione dentro questo repo. Serve a
orientarsi anche a mesi di distanza, senza contesto pregresso: i protocolli qui
sotto sono **operativi**, vanno applicati identici ogni volta.

---

## Cos'è il progetto

**ClickTrivia** — app iOS/iPadOS di quiz a risposta rapida (Swift + SwiftUI),
progettata perché sia pienamente giocabile da utenti non vedenti e ipovedenti.
L'accessibilità non è un layer aggiuntivo: è il design. Ogni informazione di
gioco deve arrivare su più canali (visivo, VoiceOver, audio sintetizzato,
aptica) e nessuna deve essere veicolata dal solo colore o dalla sola posizione.

**Struttura.** App shell in `App/`, logica in un pacchetto SPM locale
`Packages/ClickTriviaKit/` diviso in moduli: `TriviaCore` (modelli, motore,
punteggio), `TriviaDesign`, `TriviaAccessibility` (canali di feedback),
`TriviaImport` (template Kahoot/XLSX), `TriviaNearby` (Multipeer),
`TriviaPersistence`, `TriviaRemote` (contratti per il futuro CloudKit).

---

## Dati infrastrutturali

| Voce | Valore |
|---|---|
| Bundle identifier | `com.scabo.click-trivia` |
| App ID sul Developer Portal | **"Quiz game accessibile"** |
| App su App Store Connect | **"ClickTrivia"** (già creata dal proprietario, `id=6795875212`) |
| Team ID | `D2KQYQ8YU8` |
| Identità di firma | `Apple Distribution: Luca Scabini (D2KQYQ8YU8)` |
| Repo codice | `https://github.com/Scabo03/click-trivia.git`, branch `main` |
| Repo certificati (match) | `https://github.com/Scabo03/lumar-lounge-certs.git` |
| Scheme Xcode | `ClickTrivia` |

**L'app e l'App ID esistono già: non crearne mai di nuovi.**

### Il repo certificati è condiviso — leggere prima di toccare la firma

ClickTrivia usa `lumar-lounge-certs`, **lo stesso repo match di Lumar Lounge**.
Non è un errore ed è deliberato: l'account Apple ha già i **3 certificati Apple
Distribution** massimi consentiti, uno per ciascuno dei repo `lumar-lounge-certs`,
`elenthyr-certs`, `sense-racing-certs`. Un repo match nuovo e vuoto costringerebbe
`match` a generare un **quarto** certificato, che Apple rifiuta o concede solo
revocandone uno già in uso da un'altra app — rompendo la firma di quella app.
Puntando al repo esistente, `match` riusa il certificato già archiviato lì e crea
soltanto il provisioning profile della nuova app.

Il repo si chiama `lumar-lounge-certs` per **ragioni storiche** (schema originario
un-repo-per-progetto), ma **ospita due app**: contiene sia
`AppStore_com.scabo.lumarlounge.mobileprovision` sia
`AppStore_com.scabo.click-trivia.mobileprovision`, su un unico certificato
Distribution. Se un domani si libera uno slot certificato (scadenza, revoca di un
progetto dismesso), ClickTrivia **può essere separata** in un proprio
`click-trivia-certs`: in quel caso va creato il repo, generato il certificato
dedicato e aggiornati `git_url` in `fastlane/Matchfile` e `CERTS_GIT_URL` in
`fastlane/Fastfile`. Finché lo slot non si libera, **non tentarlo**.

### Dove stanno i segreti (riferimenti, mai da copiare)

| Segreto | Collocazione |
|---|---|
| Chiave API App Store Connect (`.p8`) | `~/Developer/private_keys/AuthKey_MGW9GC97HV.p8` |
| Key ID, Issuer ID, Team ID, `MATCH_PASSWORD` | `~/Developer/private_keys/scabo_deploy.env` |
| Credenziali GitHub | portachiavi macOS (`osxkeychain`, account `Scabo03`) |

Questi percorsi sono **riferimenti**: il progetto vi accede per percorso assoluto
o variabile d'ambiente. Uso normale:

```sh
source ~/Developer/private_keys/scabo_deploy.env
bundle exec fastlane <lane>
```

Attenzione: `scabo_deploy.env` è **condiviso tra progetti** e contiene
`APP_IDENTIFIER` e `MATCH_GIT_URL` di *scabopdf*. Per questo `app_identifier` e
`git_url` sono **pinnati nel codice** in `Appfile`/`Matchfile`/`Fastfile` e non
letti da env: altrimenti `match` colpirebbe l'app o il repo sbagliati. Non
"semplificare" rendendoli configurabili da env.

Nota password: `lumar-lounge-certs` (e `scabopdf-certs`) usano il `MATCH_PASSWORD`
di `scabo_deploy.env`; `elenthyr-certs` e `sense-racing-certs` ne usano un'altra,
nei rispettivi `fastlane/.env`. Per ClickTrivia vale la prima.

---

## Protocollo segreti e commit

1. **I segreti restano fuori dalla cartella del progetto.** Sempre referenziati
   per percorso assoluto o variabile d'ambiente. Mai copiati dentro il repo, mai
   incollati in un file committato, mai messi in un commit message.
2. **Prima di ogni commit**, verificare che in staging non ci sia nessun file
   sensibile: `.p8`, `.p12`, `.cer`, `.mobileprovision`, `.env`, `.ipa`.
   ```sh
   git diff --cached --name-only | grep -Ei '\.(p8|p12|cer|mobileprovision|ipa)$|(^|/)\.env$'
   ```
   Nessun output = via libera. Il `.gitignore` già esclude tutto questo, ma il
   controllo va fatto comunque: è l'ultima rete prima di una fuga irreversibile.
3. **`fastlane/.env.example` può essere committato solo con i valori vuoti.** È un
   template: `MATCH_PASSWORD=` resta senza valore. Il file reale `fastlane/.env`
   è gitignorato e su questa macchina normalmente non serve nemmeno (si sourca
   quello condiviso).
4. **Se un segreto sembra mancare, cercarlo negli altri progetti in `~/Developer`**
   e dedurne la collocazione ispezionando i loro `Appfile`, `Matchfile`, `Fastfile`
   e `.env` (`lumar-lounge`, `elenthyr-app`, `sense-racing`, `scabopdf`,
   `mistcarver`). **Non inventare percorsi nuovi** e non creare una nuova cartella
   di segreti: lo schema condiviso esiste già ed è `~/Developer/private_keys/`.

---

## Protocollo firma

- **`match` gira sempre in readonly.** La lane di default è `fetch_signing`:
  recupera e installa certificato e profilo esistenti senza rigenerare nulla.
  Tutte le lane di build la invocano.
- **`setup_signing` (readonly false) è un'operazione eccezionale.** Non eseguirla
  mai di routine, mai "per sicurezza", mai per sbloccare un errore senza averne
  capito la causa. L'account è al **massimo dei 3 certificati di distribuzione**:
  una rigenerazione rischia di revocare un certificato in uso da un'altra app e di
  romperne la firma. Serve solo per creare il profilo la prima volta o dopo una
  scadenza reale, e va fatta con cognizione.
- **Development non è gestito da match.** Per il debug su device fisico si usa la
  **firma automatica di Xcode**. Il progetto ha `CODE_SIGN_STYLE = Automatic` nel
  `pbxproj` apposta: la firma manuale con il profilo match viene forzata solo da
  riga di comando durante l'archive, così lo sviluppo quotidiano in Xcode resta
  senza attriti.

### Lane disponibili (`fastlane/Fastfile`)

| Lane | Cosa fa |
|---|---|
| `fetch_signing` | Installa certificato e profilo esistenti (readonly). Default sicuro. |
| `setup_signing` | Crea/riallinea il profilo (readonly false). **Eccezionale.** |
| `next_build` | Stampa il build number del prossimo upload. Sola lettura, non costruisce nulla. |
| `build_only` | Archive + export dell'IPA firmato, **senza upload**. Verifica la firma. |
| `testflight_upload` | Build, archive, export e upload su TestFlight. |

Pipeline: `xcodebuild archive` + `-exportArchive` + `xcrun altool`, non `gym` —
è lo schema collaudato sugli altri progetti iOS di questo Mac.

---

## Protocollo versioni e build number

**Questo è il punto su cui in passato si sono creati pasticci. Applicarlo alla
lettera.**

### Le due grandezze sono diverse e non vanno confuse

| | Chiave Info.plist | Build setting | Cos'è |
|---|---|---|---|
| **Build number** | `CFBundleVersion` | `CURRENT_PROJECT_VERSION` | Contatore **interno**. Intero puro. Distingue due upload della stessa versione pubblica. Invisibile agli utenti. |
| **Marketing version** | `CFBundleShortVersionString` | `MARKETING_VERSION` | Versione **pubblica** (es. `1.0`, `1.1`). Quella che l'utente vede sull'App Store. |

### Regola del build number

> **Il build number va incrementato a ogni upload verso TestFlight e deve essere
> sempre strettamente maggiore dell'ultimo accettato da App Store Connect.**
> Altrimenti Apple rifiuta l'upload.

Meccanismo obbligatorio, **da eseguire prima di ogni upload**:

1. La lane interroga **App Store Connect** e ricava il build number più alto
   esistente per `com.scabo.click-trivia`, considerando **tutti i version train**
   (non solo quello della marketing version corrente: se la marketing version
   cambia, i numeri non devono ripartire da capo).
2. Il prossimo build number è quel massimo **+1**. Se non esiste nessun build, si
   parte da **1**.
3. Il valore viene applicato **solo da riga di comando** all'`xcodebuild`
   (`CURRENT_PROJECT_VERSION=<n>`), **senza riscrivere il `pbxproj`**.
4. **Se la query ad App Store Connect fallisce, la lane si ferma.** Nessun
   fallback su un valore locale.

**Perché così.** La fonte di verità è App Store Connect, non il disco. Un valore
locale nel `pbxproj` tra una sessione e l'altra resta indietro, e due sessioni
diverse possono ricalcolarlo uguale: sono esattamente le collisioni e le sviste da
cui questa regola protegge. Leggendo il massimo remoto e incrementandolo, due
upload non possono partire con lo stesso numero, e il meccanismo si auto-corregge
anche dopo un upload fatto a mano o da un'altra macchina.

Query di riferimento (Spaceship, già verificata su questo progetto):

```ruby
app    = Spaceship::ConnectAPI::App.find("com.scabo.click-trivia")
builds = Spaceship::ConnectAPI::Build.all(app_id: app.id)
next_build_number = (builds.map { |b| b.version.to_i }.max || 0) + 1
```

### Regola della marketing version

> **La marketing version cambia solo su decisione esplicita del proprietario**,
> quando si segna un avanzamento reale. **Mai automaticamente**, mai come effetto
> collaterale di un upload. Molti build TestFlight condividono la stessa
> marketing version: è normale e corretto.

### Coerenza Debug / Release

`MARKETING_VERSION` e `CURRENT_PROJECT_VERSION` devono avere **lo stesso valore
nella configurazione Debug e nella Release** del `pbxproj`. Valori divergenti
producono numeri di versione che cambiano a seconda di come è stata fatta la
build — una fonte di confusione difficile da diagnosticare. Se si tocca uno dei
due, toccare **entrambe** le configurazioni.

Stato attuale verificato: `MARKETING_VERSION = 1.0` e `CURRENT_PROJECT_VERSION = 1`
identici in Debug e Release.

### ✅ Allineamento completato (30 luglio 2026)

Il `Fastfile` calcolava inizialmente il build number come **epoch Unix**
(`Time.now.to_i`), schema ereditato da lumar-lounge: monotòno e senza collisioni,
ma con numeri enormi (~1,78 miliardi) e irreversibili, perché dopo il primo upload
ogni numero successivo deve restare ancora più alto, per sempre.

Lo schema epoch è stato **abbandonato** approfittando della finestra ancora aperta
(nessun build caricato). Ora `testflight_upload` usa l'helper `next_build_number`,
che implementa la regola qui sopra. Verificato sul progetto reale: 0 build
esistenti → prossimo build number **1**, e con credenziali non valide la lane si
ferma con un errore esplicito senza ripiegare su nessun valore locale.

Diagnostica: `bundle exec fastlane next_build` stampa il numero che userebbe il
prossimo upload, in sola lettura, senza costruire né caricare nulla.

---

## Stato dello sviluppo

Al 30 luglio 2026.

- **Fasi 0–3 approvate architetturalmente** dal proprietario: fondamenta,
  single-player, import Kahoot, presenza Multipeer.
- **Fase 3 in attesa di verifica su due dispositivi fisici reali.** Il trasporto
  Multipeer **non è testabile in simulatore**: finché la prova su device non è
  fatta e riportata, la fase non è chiusa.
- **Tarature manuali ancora aperte**, a carico del proprietario:
  - Fase 1 — suoni (`SynthesizedAudioChannel.tones(for:)`) e aptica
    (`CoreHapticsChannel`) da tarare su device reale.
  - Fase 2 — costanti di riga e colonna dell'import
    (`KahootLimits.firstDataRow` e `Column` in `KahootTemplateImporter`) da
    verificare contro un template Kahoot reale.
- **Fase 4 — gioco a distanza asincrono via CloudKit: non ancora costruita.**
  Schizzo già concordato: persistenza locale **unica fonte di verità**, CloudKit
  solo replica opzionale dietro un `AvailabilityMonitor` (su
  `CKContainer.accountStatus` + stato rete, che pubblica il `CloudAvailability`
  già presente in `TriviaRemote`); funzioni online **assenti-e-spiegate**, mai
  errori; coda **outbox** locale per le scritture differite.
  Da espandere in piano formale **solo al via libera esplicito**.

### Condizioni per iniziare la Fase 4

Il via libera scatta quando il proprietario conferma **entrambe**:
1. le prove della Fase 3 su dispositivi reali sono andate a buon fine;
2. è soddisfatto del setup Apple.

Poi si procede nell'ordine di sempre: **prima** si espande lo schizzo in un piano
formale di poche righe — con attenzione particolare a come il **degrado con
grazia senza iCloud** (account assente, quota piena, offline) resti sempre
giocabile in locale e venga spiegato all'utente in modo accessibile **su tutti i
canali** — **poi**, dopo l'ok sul piano, si costruisce e ci si ferma a fine fase.

---

## Metodo di lavoro

- Il proprietario delega i dettagli implementativi e dà il **via libera esplicito
  a fine fase**: costruire la fase, fermarsi, riportare.
- Vincoli **non negoziabili**: accessibilità piena, nessun server proprio,
  nessun valore hardcodato dove serve una costante o una configurazione.
- Nota emersa: il formato template Kahoot è compatibile anche con **Quizizz** e
  **Blooket** — da citare in futuro nella descrizione dell'app.
