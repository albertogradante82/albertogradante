# Calcio Giovanile – registrazione e analisi movimenti (iPhone)

App iOS (SwiftUI, iOS 17+) per **registrare le partite del settore giovanile** e **analizzare i movimenti dei giocatori**: distanza percorsa, velocità, sprint, mappe di calore, posizioni medie e compattezza della squadra.

Tutto viene elaborato **sul telefono**, senza cloud: i video di minori non lasciano il dispositivo (vedi la sezione privacy).

## Funzioni

| Area | Cosa fa |
|---|---|
| **Squadre e rosa** | Squadre per categoria (Piccoli Amici → Juniores), giocatori con numero, ruolo, anno di nascita |
| **Registrazione** | Video 1080p HEVC dalla fotocamera (anche grandangolo 0.5×), cronometro, spazio libero, schermo sempre acceso, **pulsanti rapidi per gli eventi** (gol, tiro, occasione, recupero, palla persa, fallo, angolo, inizio 2° tempo, nota) |
| **Importazione** | In alternativa, importi un video dal Rullino (es. ripreso con un altro telefono o una action cam) |
| **Calibrazione campo** | Tocchi sull'immagine almeno 4 punti noti (angoli, metà campo, vertici dell'area) con una lente d'ingrandimento; l'app calcola l'**omografia** pixel → metri e sovrappone le linee del campo per verificare |
| **Analisi automatica** | Vision (`VNDetectHumanRectanglesRequest`) rileva le persone, la posizione dei piedi viene proiettata sul campo, un tracker multi-oggetto segue ogni giocatore e il colore della maglia separa le squadre (k-means) |
| **Assegnazione tracce** | Le tracce anonime si assegnano ai giocatori della rosa guardando il fotogramma con il riquadro evidenziato; arbitro/pubblico si eliminano con un tocco |
| **Tracciamento manuale** | Il video scorre al rallentatore e tieni il dito sul giocatore: utile per azioni specifiche o quando il tracking automatico lo perde |
| **Analisi giocatore** | Minuti tracciati, distanza, m/min, velocità media e massima, numero di sprint, distanza per fascia di intensità, % di tempo in difesa/centrocampo/attacco e nelle corsie, **mappa di calore**, **percorso**, grafico della velocità; filtro 1°/2° tempo |
| **Analisi squadra** | Posizioni medie (disposizione reale in campo), ampiezza, profondità e baricentro nel tempo, classifica per distanza |
| **Stagione** | Andamento di ogni giocatore partita dopo partita |
| **Esportazione** | CSV (riepilogo + tutte le posizioni) apribile con Excel/Numbers |

## Come si usa in campo

1. **Treppiede fisso e in alto** (tribuna, scaletta, asta telescopica). Più la camera è alta, più è precisa la posizione dei giocatori. La camera **non deve muoversi** per tutta la partita (niente zoom o panoramiche dopo l'inizio).
2. Inquadra **tutto il campo**; per campi a 9 e a 11 usa il grandangolo 0.5× posizionandoti a metà campo.
3. Avvia la registrazione e, se vuoi, tocca i pulsanti degli eventi. Tocca **"Inizio 2° tempo"** alla ripresa: serve per invertire il verso d'attacco nelle statistiche.
4. A fine partita: **Calibra il campo** → **Analisi automatica** → **Assegna le tracce** → guarda i risultati.

Consigli pratici: telefono in carica (power bank), circa 4–6 GB per un'ora di video HEVC 1080p, controlla le misure reali del campo (i formati preimpostati sono indicativi).

## Compilare il progetto

Serve un Mac con **Xcode 15 o successivo**.

```bash
brew install xcodegen      # una volta sola
cd CalcioGiovanile
xcodegen generate          # crea CalcioGiovanile.xcodeproj da project.yml
open CalcioGiovanile.xcodeproj
```

In Xcode: seleziona il tuo *Team* in *Signing & Capabilities*, collega l'iPhone e premi ▶︎. I test (`⌘U`) coprono omografia, statistiche, heatmap, tracker e clustering dei colori.

Senza XcodeGen: crea in Xcode un nuovo progetto *iOS App* (SwiftUI, SwiftData) chiamato `CalcioGiovanile`, cancella i file generati, trascina dentro la cartella `CalcioGiovanile/` e aggiungi nel target le chiavi Info.plist elencate in `project.yml` (fotocamera, microfono, libreria foto).

## Struttura

```
CalcioGiovanile/
├── App/            avvio app e tab principali
├── Models/         SwiftData (Team, Player, Match, Track, MatchEvent) + geometria campo e omografia
├── Recording/      AVCaptureSession e registrazione video
├── Analysis/       VideoAnalyzer (Vision), PlayerTracker, k-means maglie, statistiche, heatmap
├── Views/          schermate SwiftUI
└── Utils/          archiviazione video, esportazione CSV
```

### Come funziona l'analisi

1. **Lettura video** con `AVAssetReader` a 2/5/10 fotogrammi al secondo.
2. **Rilevamento persone** con Vision; in *alta precisione* il fotogramma è diviso anche in 6 riquadri sovrapposti, così vengono trovati i giocatori piccoli sul lato lontano. I doppioni sono eliminati con *non-maximum suppression*.
3. **Proiezione sul campo**: il centro del lato inferiore del riquadro (i piedi) passa per l'omografia e diventa una coordinata in metri. Chi è fuori dalle linee (panchina, genitori) viene scartato.
4. **Tracking**: predizione a velocità costante + associazione per distanza e colore maglia; tracce più corte di 3 s vengono scartate.
5. **Statistiche**: posizioni smussate (media mobile 1 s), salti oltre i 2 s non contano nella distanza, velocità non plausibili (> 32 km/h) sono filtrate. Fasce di velocità pensate per i ragazzi: camminata < 7, corsa lenta 7–13, corsa 13–17, sprint > 17 km/h per almeno 1 s (modificabili in `SpeedZones`).

### Limiti da conoscere

- È un tracking da **una sola camera**: in mischie, contrasti e quando i giocatori si sovrappongono le tracce si spezzano; per questo esiste la fase di assegnazione (più tracce → stesso giocatore).
- La precisione dipende soprattutto dall'**altezza della camera** e dalla qualità della calibrazione: da bordo campo ad altezza d'uomo, il lato lontano è poco accurato.
- Il riconoscimento del numero di maglia non è automatico.
- L'analisi di una partita intera richiede tempo (indicativamente 10–40 minuti su un iPhone recente, in base alle impostazioni); puoi analizzare solo una parte del video.

## Privacy (minori)

- Video e dati restano nella cartella Documenti dell'app; nessun invio a server esterni.
- Prima di riprendere, raccogli il **consenso dei genitori** come previsto dal regolamento della società e dal GDPR; condividi i video solo con lo staff.
- Eliminando una partita si elimina anche il relativo video.
