# BAT tv · versione ibrida Bluetooth 0.1

Un’app con tre ruoli: **Camera**, **Regia** e **Punteggi**. Interfaccia HTML/CSS/JS inclusa nell’app, funzioni native per camera, video e Bluetooth. Non carica un sito remoto. Non richiede ChatGPT, account, Wi-Fi, hotspot, dominio o server cloud.

La **Camera** è il dispositivo che possiede lo stato della partita, il cronometro e la connessione RTMPS a Facebook. **Regia** offre punteggio, cronometro, falli, timeout, quarti, annullamento e overlay. **Punteggi** offre i soli controlli della partita. I ruoli sono disponibili su iPhone e Android; la Camera può essere iPhone oppure Android. Questa prima versione collega **una Camera e un controller alla volta**, con il controller in ruolo Regia oppure Punteggi. Non include più camere o più controller contemporanei.

## Installare Android

L’APK `BAT-tv-Android.apk` è compilato e firmato per la prova diretta su **Android 8 o successivo**. Trasferiscilo sul dispositivo, aprilo e, se Android lo richiede, consenti l’installazione da quella specifica app (per esempio File). Non occorre il Play Store. È una firma di sviluppo, non una distribuzione di produzione.

## Installare iPhone

Apri `iPhone/BAT-tv.xcodeproj` con Xcode 26 o successivo. Seleziona il tuo Team in Signing & Capabilities e l’iPhone collegato, poi premi Run. HaishinKit 2.2.5 rimane il motore video. L’aggiornamento Bluetooth/ibrido è stato preparato su Linux: **questa nuova versione iPhone non è stata compilata qui**. La precedente versione Camera era stata compilata sul Mac dell’utente.

## Prima prova, senza Wi-Fi e senza account

1. Attiva Bluetooth su entrambi i dispositivi. Apri BAT tv e tienila aperta in primo piano, in orizzontale.
2. Sul dispositivo che riprende scegli **Camera**. Compare un codice a sei cifre e l’app rende disponibile il servizio Bluetooth.
3. Sul secondo dispositivo scegli **Regia** oppure **Punteggi**. Premi Cerca via Bluetooth e seleziona la Camera.
4. Conferma gli eventuali avvisi di sistema per i dispositivi nelle vicinanze e l’abbinamento Bluetooth. Inserisci nell’app il codice a sei cifre mostrato dalla Camera e premi Abbina. I punteggi appaiono dopo la conferma della Camera.
5. Prova +2 e Pausa/Avvia. In Regia prova Kiss Cam. Il cambio di stato viene applicato sulla Camera e restituito al controller.
6. Attiva la Camera, consenti camera e microfono e verifica gli overlay nell’anteprima **del dispositivo Camera**.
7. Sulla Camera inserisci indirizzo RTMPS e chiave ottenuti da Facebook Live Producer. Internet (anche 4G/5G) serve alla sola Camera. Premi Invia e controlla la ricezione in Facebook prima di pubblicare la diretta.
8. Ferma l’invio prima di cambiare ruolo o chiudere l’app.

Su Android 8–11 la scansione BLE può richiedere il permesso Posizione e il servizio Posizione attivo, anche se BAT tv non rileva o usa la posizione. Su Android 12+ l’app richiede i permessi Dispositivi nelle vicinanze. Un Android che fa da Camera deve supportare anche il ruolo BLE periferico/advertising: non tutti i modelli lo supportano; l’app segnala quando manca. Come Regia/Punteggi serve il ruolo centrale BLE.

## Stato delle verifiche

- **APK Android compilato con successo** e firma APK verificata.
- Logica Java della partita verificata: incrementi, limiti, comandi duplicati, cronometro, pausa, annullamento, overlay a tempo e formato dei messaggi.
- Interfaccia comune: verifiche dei ruoli e dei comandi della regia.
- Progetto iPhone: controllati plist, riferimenti a risorse e protocollo, ma manca la compilazione Xcode della nuova versione.
- **Non eseguiti su dispositivi reali:** abbinamento Android↔iPhone, negoziazione della cifratura Bluetooth, acquisizione e orientamento Android, composizione OpenGL degli overlay Android e trasmissione RTMPS da questa nuova versione.
- Nessuna anteprima video sul controller: BLE trasferisce i comandi e lo stato della partita. La ripresa è visibile sulla Camera.
- La perdita di Bluetooth non cancella la partita o arresta volontariamente l’invio video. Per ripristinare la regia usa Cerca, seleziona la Camera e abbina di nuovo; verifica lo stato prima di ripetere un comando non confermato.
- Il dispositivo Camera va tenuto aperto in primo piano; questa versione non implementa la ripresa in background.
- Su iPhone la chiave Facebook resta nel Portachiavi. Su Android la chiave resta solo in memoria durante la sessione, l’indirizzo è salvato localmente. La chiave non passa in Bluetooth.

## Protocollo

Servizio GATT `BA7A0001-9130-4D77-A6E0-BA7A20140001`; comando RX `...0002...`; stato TX `...0003...`. JSON UTF-8 delimitato da newline, frammentato in base alle dimensioni BLE consentite. I messaggi includono pairing, comandi con ID, conferme e snapshot con tempo della Camera. La cifratura è richiesta alle caratteristiche GATT; il codice nell’app autorizza il controller per la sessione. Limiti di lunghezza, limitazione dei tentativi di codice e protezione contro il conteggio duplicato dei comandi di partita sono inclusi.

## Ricompilare Android

Android Studio con SDK 36, JDK 17 e Gradle 8.11.1. Apri la cartella Android, lascia che Android Studio crei local.properties con il tuo percorso SDK e usa Build APKs. Da terminale: `./gradlew :app:assembleDebug`.

La dipendenza video è RootEncoder 2.6.4 (Apache 2.0) distribuita tramite JitPack. Il progetto include una chiave **di test** in Android/signing per mantenere la stessa firma nelle ricompilazioni di questa prova; non è una chiave di distribuzione. Per una distribuzione pubblica va creata una firma di produzione separata.

Il logo è ricavato dal centro del banner BAT TV scelto dall’utente. Viola #512A7D, giallo #FFFE0F e bianco.
