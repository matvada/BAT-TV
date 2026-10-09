"""Create release notes from commits and document the earlier BAT tv builds."""

import re
import subprocess
import sys


LEGACY = {
    2: ["Prima IPA iPhone di BAT tv, installabile tramite SideStore.",
        "App ibrida con ruoli Camera, Regia e Punteggi, comandi Bluetooth e video RTMPS."],
    3: ["Versione iPhone numerata 1.0.3 per consentire gli aggiornamenti in SideStore.",
        "Sorgente SideStore aggiornata automaticamente con la versione e l’IPA corrispondenti."],
    7: ["Ripresa iPhone in orizzontale e anteprima Camera adattata allo schermo.",
        "IPA e APK Android pubblicati insieme; numero di build allineato tra le piattaforme."],
    8: ["Anteprima Camera a pieno schermo.",
        "Scelta dei ruoli senza scorrimento verticale."],
    9: ["Comandi Camera in un pannello laterale richiudibile.",
        "Regia e Punteggi organizzati in schede senza scorrimento della schermata."],
    10: ["Logo BAT tv e barra del punteggio riportati entro l’inquadratura.",
         "Apertura dei comandi toccando il logo nella schermata Camera."],
    11: ["Interruttore per scegliere se gestire il cronometro; quando è disattivato resta visibile il quarto.",
         "Grafiche della diretta aggiornate, inclusa l’animazione della tripla."],
    12: ["Facebook Live Producer aperto dentro BAT tv sullo stesso iPhone Camera.",
         "Copia di URL e chiave persistente, avvio dell’invio e conferma della diretta su Facebook."],
    13: ["Live Producer utilizzabile in verticale; ritorno alla Camera in orizzontale.",
         "Orientamento della ripresa mantenuto durante l’uso del pannello Facebook."],
    14: ["Pannello Camera allargato e comandi Diretta compattati.",
         "Campi URL e chiave affiancati, con Salva destinazione accessibile sopra Cambia ruolo."],
}


def current_notes(number: int) -> str:
    tags = subprocess.check_output(
        ["git", "tag", "-l", "ios-build-*"], text=True
    ).splitlines()
    prior = max((int(match.group(1)) for tag in tags
                 if (match := re.fullmatch(r"ios-build-(\d+)", tag))
                 and int(match.group(1)) < number), default=None)
    base = f"ios-build-{prior}..HEAD" if prior is not None else "HEAD"
    subjects = subprocess.check_output(
        ["git", "log", "--format=%s", base], text=True
    ).splitlines()
    subjects = [subject for subject in reversed(subjects)
                if subject and "[skip ci]" not in subject
                and not subject.startswith("Aggiorna sorgente SideStore")]
    if not subjects:
        raise SystemExit("No implementation commits found for release notes")
    return (f"## Modifiche · 1.0.{number}\n\n"
            + "\n".join(f"- {subject}." for subject in subjects)
            + "\n\n## File\n\n"
            + f"- `BAT-tv-1.0.{number}-iPhone.ipa` — iPhone, installazione con SideStore.\n"
            + f"- `BAT-tv-1.0.{number}-Android.apk` — Android, app ufficiale.\n")


if __name__ == "__main__":
    command = sys.argv[1]
    if command == "legacy-list":
        print("\n".join(map(str, sorted(LEGACY))))
    elif command == "legacy":
        number = int(sys.argv[2])
        print(f"## Modifiche · 1.0.{number}\n")
        for line in LEGACY[number]:
            print(f"- {line}")
        print("\n## File\n\nScarica l’IPA per SideStore e, se presente in questa release, l’APK Android dagli allegati qui sotto.")
    elif command == "current":
        print(current_notes(int(sys.argv[2])))
    else:
        raise SystemExit("Usage: release_notes.py legacy-list | legacy NUMBER | current NUMBER")
