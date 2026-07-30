# ClickTrivia

Quiz multipiattaforma (iOS, iPadOS, macOS) in SwiftUI e Swift puro, nato con
un vincolo fondante: **accessibilità totale**. Giocatori con e senza
disabilità giocano e competono alle stesse condizioni; ogni informazione
importante viaggia su più canali (testo/forma, suono, aptica), mai sul solo
colore.

Perimetro tecnico: nessun server proprio, nessun servizio a pagamento.
Connettività solo con Multipeer Connectivity (gioco in presenza, max 8) e
CloudKit (gioco a distanza asincrono), con degrado con grazia: l'app è sempre
pienamente giocabile offline e in locale.

## Struttura

```
ClickTrivia.xcodeproj      Un target multipiattaforma (iPhone, iPad, Mac)
App/                       Guscio sottile: entry point, composizione, vista radice
Packages/ClickTriviaKit/   Tutta la logica, in moduli per fase di sviluppo
  TriviaCore               Fase 0 · dominio puro: profilo, domanda, quiz,
                           partita, punteggio, curva bonus, power-up, progressione
  TriviaAccessibility      Fondamenta · preferenze + impostazioni di sistema +
                           FeedbackCenter (canali audio/aptico/visivo + VoiceOver)
  TriviaDesign             Fondamenta · tema meccanico-elettrico: palette blu e
                           varianti accessibili, simboli d'esito, zig-zag, motion token
  TriviaPersistence        Fase 0 · store JSON locali, offline-first
  TriviaImport             Fase 2 · contratti per l'import di quiz
  TriviaNearby             Fase 3 · contratti Multipeer Connectivity
  TriviaRemote             Fase 4 · contratti CloudKit e degrado con grazia
```

Regola di dipendenza: tutto dipende da `TriviaCore`; `TriviaCore` non dipende
da nulla (né UI né framework di sistema).

## Fasi

0. **Fondamenta** — progetto, moduli, modello dati, impianto accessibilità ✅
1. **Single-player offline** — motore di partita, schermate di gioco, audio
   sintetizzato, pattern CoreHaptics, momento-bonus sui tre canali ✅
2. **Import di quiz** — lettore .xlsx in casa (zip+XML, zero dipendenze),
   template Kahoot, anteprima di revisione accessibile con correzione ✅
3. **Gioco in presenza** — sale Multipeer (max 8) con accettazione esplicita,
   partita a ritmo condiviso, stati di connessione su tre canali accessibili ✅
4. Gioco a distanza asincrono (CloudKit)

Test del dominio: `swift test --package-path Packages/ClickTriviaKit`
