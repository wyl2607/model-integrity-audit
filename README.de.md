# Modellintegritätsaudit

Sprache: [English](README.md) | [中文](README.zh-CN.md) | Deutsch

Model Integrity Audit ist ein wiederverwendbares Kommandozeilen-Toolkit zum Prüfen, ob ein mit der OpenAI Responses API kompatibler Endpunkt wie erwartet funktioniert. Es führt reproduzierbare API-Qualitätsprüfungen, Modellrouten-Integritätsproben, negative Kontrollen und Verhaltens-Fingerprinting aus und schreibt bereinigte JSON- und Markdown-Berichte.

Das Projekt ist für typische Windows-, macOS- und Linux-Umgebungen gedacht. Reale Zugangsdaten müssen nicht im Repository gespeichert werden. Verwende Umgebungsvariablen, eine lokale `.env`-Datei oder Laufzeitargumente.

## Was Geprüft Wird

- Ob der Endpunkt gültige Responses-API-Anfragen akzeptiert.
- Ob das zurückgegebene Feld `model` zum angefragten Modell passt.
- Ob ungültige Modellnamen abgelehnt werden.
- Ob ungültige Werte für `reasoning.effort` mit Validierungsfehlern abgelehnt werden.
- Ob `gpt-5.5` in Token- und Verhaltens-Fingerprints auffällig ähnlich zu einem Basismodell wirkt.
- Ob App- und CLI-Codex-Routen ähnlich wirken, falls Codex CLI verfügbar ist.

## Modi

- `quick`: Schneller Vertrauenscheck in etwa 10-30 Sekunden für häufige API- und Modellroutenprobleme.
- `full`: Tiefere Mehrfachstichproben-Prüfung über ein oder mehrere Modelle.

## Repository-Struktur

- `check-api-quality-and-model-integrity.sh`: Haupt-Bash-Einstieg für `quick` und `full`.
- `check-api-quality-and-model-integrity.ps1`: Windows-PowerShell-Wrapper für den Hauptaudit.
- `scripts/probe-gpt55-authenticity.sh`: Fokussierte `gpt-5.5`-Authentizitätsprobe.
- `scripts/probe-gpt55-authenticity.ps1`: Windows-PowerShell-Wrapper für die fokussierte Probe.
- `compare-app-vs-cli-gpt55.sh`: Optionaler Vergleich zwischen App- und CLI-Codex-Route.
- `compare-app-vs-cli-gpt55.ps1`: Windows-PowerShell-Wrapper für den App/CLI-Vergleich.
- `docs/report-schema.md`: JSON-Berichtsfeldvertrag und Hinweise für Consumer.
- `docs/model-integrity-methodology.md`: Erklärung der Modellintegritätskontrollen und ihrer Grenzen.
- `examples/reports/`: Bereinigte Beispielberichte für schnelle Prüfung und nachgelagerte Integration.
- `.env.example`: Sichere Vorlage mit Platzhaltern.
- `reports/`: Lokales Ausgabeverzeichnis, von Git ignoriert.

## Sicherheitsregeln

- Keine `.env`-Dateien, API-Schlüssel, Bearer Tokens, Roh-Traces oder generierten Berichte committen.
- Generierte Berichte werden nach `reports/` geschrieben; dieses Verzeichnis wird von Git ignoriert.
- Die Skripte bereinigen Berichte und vermeiden das Schreiben von API-Schlüsseln oder Bearer Tokens.
- Endpunkte werden in Berichten standardmäßig redigiert. Verwende `--show-endpoint` nur, wenn die Endpoint-Origin absichtlich in lokalen Berichten erscheinen soll.
- Vor einem PR `./scripts/secret-scan.sh` oder `.\scripts\secret-scan.ps1` ausführen.
- Dokumentation und Beispiele verwenden nur Platzhalter wie `https://your-relay.example.com/v1`.
- Prüfe Markdown- und JSON-Berichte manuell, bevor du sie veröffentlichst.

## Voraussetzungen

Für den Hauptaudit erforderlich:

- `bash`
- `curl`
- `jq`
- `rg` aus ripgrep
- `awk`
- `sed`
- `perl`

Optional:

- `codex` CLI, nur für `compare-app-vs-cli-gpt55.*`.
- Ein offizieller OpenAI API Key, nur für einen optionalen Vergleich zwischen Relay und offiziellem Endpunkt.

## Abhängigkeiten Installieren

### Windows

Empfohlenes Setup in Windows Terminal:

1. Git for Windows installieren: `https://git-scm.com/download/win`
2. ripgrep und jq mit Winget installieren:

```powershell
winget install BurntSushi.ripgrep.MSVC
winget install jqlang.jq
```

3. Windows Terminal neu öffnen.
4. Den PowerShell-Wrapper im Repository-Stammverzeichnis ausführen.

Git for Windows liefert in typischen Installationen `bash`, `curl`, `awk`, `sed` und `perl`. Wenn ein Wrapper einen fehlenden Befehl meldet, installiere den Befehl und öffne das Terminal erneut.

### macOS

Abhängigkeiten mit Homebrew installieren:

```bash
brew install jq ripgrep
```

macOS enthält Bash, curl, awk, sed und perl bereits. Die Systemversionen reichen für dieses Projekt aus.

### Linux

Debian oder Ubuntu:

```bash
sudo apt update
sudo apt install -y bash curl jq ripgrep gawk sed perl
```

Fedora:

```bash
sudo dnf install -y bash curl jq ripgrep gawk sed perl
```

Arch Linux:

```bash
sudo pacman -S --needed bash curl jq ripgrep gawk sed perl
```

## Repository Klonen

```bash
git clone https://github.com/wyl2607/model-integrity-audit.git
cd model-integrity-audit
```

Auf macOS und Linux bei Bedarf Ausführungsrechte setzen:

```bash
chmod +x *.sh scripts/*.sh
```

## Zugangsdaten Konfigurieren

Der sicherste Weg ist eine lokale `.env`-Datei aus der Vorlage:

```bash
cp .env.example .env
```

`.env` lokal bearbeiten:

```bash
RELAY_BASE_URL="https://your-relay.example.com/v1"
RELAY_API_KEY="your_relay_api_key"
```

Auf macOS oder Linux laden:

```bash
set -a
source .env
set +a
```

In PowerShell setzen:

```powershell
$env:RELAY_BASE_URL = "https://your-relay.example.com/v1"
$env:RELAY_API_KEY = "your_relay_api_key"
```

Alternativ direkt zur Laufzeit übergeben:

```bash
./check-api-quality-and-model-integrity.sh --relay-base-url "https://your-relay.example.com/v1" --relay-api-key "your_relay_api_key" --mode quick
```

Auf gemeinsam genutzten Maschinen echte Werte nicht unnötig in die Shell-Historie schreiben.

## Schnellaudit

Windows PowerShell:

```powershell
.\check-api-quality-and-model-integrity.ps1 --mode quick
```

Windows PowerShell mit expliziten Werten:

```powershell
.\check-api-quality-and-model-integrity.ps1 --mode quick --relay-base-url "https://your-relay.example.com/v1" --relay-api-key "your_relay_api_key"
```

macOS oder Linux:

```bash
./check-api-quality-and-model-integrity.sh --mode quick
```

macOS oder Linux mit expliziten Werten:

```bash
./check-api-quality-and-model-integrity.sh --mode quick --relay-base-url "https://your-relay.example.com/v1" --relay-api-key "your_relay_api_key"
```

Für langsamere Endpunkte können Netzwerkparameter gesetzt werden:

```bash
./check-api-quality-and-model-integrity.sh --mode quick --connect-timeout 10 --max-time 60 --retries 2
```

Berichte redigieren Endpoint-Origins standardmäßig. Für lokale Berichte mit sichtbarer bereinigter Origin kann `--show-endpoint` ergänzt werden.

## Vollständiger Audit

Windows PowerShell:

```powershell
.\check-api-quality-and-model-integrity.ps1 --mode full --reasoning-effort medium --samples 5 --baseline gpt-5.4-mini --models "gpt-5.5 gpt-5.4 gpt-5.4-mini gpt-5.3-codex gpt-5.2"
```

macOS oder Linux:

```bash
./check-api-quality-and-model-integrity.sh \
  --mode full \
  --reasoning-effort medium \
  --samples 5 \
  --baseline gpt-5.4-mini \
  --models "gpt-5.5 gpt-5.4 gpt-5.4-mini gpt-5.3-codex gpt-5.2"
```

## Fokussierte GPT-5.5-Probe

Windows PowerShell:

```powershell
.\scripts\probe-gpt55-authenticity.ps1 --model gpt-5.5 --samples 6 --reasoning-effort medium
```

macOS oder Linux:

```bash
./scripts/probe-gpt55-authenticity.sh --model gpt-5.5 --samples 6 --reasoning-effort medium
```

Optionaler offizieller API-Vergleich:

```bash
OFFICIAL_OPENAI_API_KEY="your_official_openai_api_key" ./scripts/probe-gpt55-authenticity.sh --model gpt-5.5
```

## App-vs-CLI-Routenvergleich

Dieses optionale Skript benötigt Codex CLI und lokale Codex-Konfiguration.

Windows PowerShell:

```powershell
.\compare-app-vs-cli-gpt55.ps1
```

macOS oder Linux:

```bash
./compare-app-vs-cli-gpt55.sh
```

## Ausgabe

Berichte werden lokal geschrieben:

- `reports/api-quality-model-integrity-quick-<timestamp>.json`
- `reports/api-quality-model-integrity-quick-<timestamp>.md`
- `reports/api-quality-model-integrity-full-<timestamp>.json`
- `reports/api-quality-model-integrity-full-<timestamp>.md`
- `reports/app-vs-cli-gpt55-<timestamp>.json`
- `reports/app-vs-cli-gpt55-<timestamp>.md`

Berichte sind standardmäßig bereinigt, sollten vor dem Teilen aber trotzdem geprüft werden.

Jeder JSON-Bericht enthält erklärende Felder:

- `evidence`: menschenlesbare Prüfungen mit Level, Nachricht und unterstützenden Werten.
- `warnings`: aus der Evidence extrahierte Warnungen.
- `failed_controls`: fehlgeschlagene oder zu prüfende Kontrollen.
- `recommendations`: nächste Schritte basierend auf der beobachteten Evidence.

Siehe `docs/report-schema.md` für den JSON-Feldvertrag und `examples/reports/` für bereinigte Beispielberichte.

Siehe `docs/model-integrity-methodology.md` für die Begründung von positiven Kontrollen, negativen Kontrollen, Model Echo, Usage Visibility und Baseline Similarity.

## Secret Scan

Vor dem Committen oder Teilen ausführen:

```bash
./scripts/secret-scan.sh
```

Windows PowerShell:

```powershell
.\scripts\secret-scan.ps1
```

Der Scan prüft getrackte Dateien auf typische API-Key-Muster, Bearer Tokens, private Endpoint-Beispiele, Trace IDs und versehentlich getrackte `.env`- oder `reports/`-Dateien.

## Offline-Integritätstest

Das Repository enthält eine lokale Mock-Responses-API, damit CI und Mitwirkende den Audit-Ablauf ohne echte API-Schlüssel oder echte Endpunkte testen können:

```bash
./tests/run_mock_e2e.sh
```

Das Skript startet `tests/mock_responses_api.py`, führt den Quick Audit und die fokussierte Probe gegen `127.0.0.1` aus, prüft Endpoint-Redaktion und negative Kontrollen und entfernt anschließend den lokalen Testserver.

Zusätzlich gibt es Abdeckung für Fehlerpfade:

```bash
./tests/run_mock_failure_e2e.sh
```

Dieser Test prüft, dass Serverfehler, fehlerhaftes JSON, fehlende Usage-Daten, Modell-Mismatches und langsame Antworten Warnungen oder fehlgeschlagene Kontrollen erzeugen, statt fälschlich einen High-Confidence-Erfolg zu melden.

## Ergebnisse Interpretieren

- `likely_real_gpt55_route`: Die Route hat die implementierten Verhaltensprüfungen bestanden.
- `suspicious_or_unstable`: Wichtige Prüfungen sind fehlgeschlagen oder die Route wirkt instabil.
- `inconclusive`: Die Evidenz reicht nicht für eine stärkere Aussage.

Nutze `verdict`, `score`, `warnings` und `failed_controls` zusammen. Ein hoher Score bedeutet, dass das Endpunktverhalten in diesem Lauf zu den implementierten Kontrollen passte; es ist kein kryptografischer Identitätsnachweis des Backends.

Prüfsignale können mehrere Ursachen haben:

- Fehlende `usage`-Daten können bedeuten, dass das Relay Metadaten verbirgt; das beweist nicht automatisch ein falsches Modell.
- Model-Echo-Mismatches können durch Proxy-Normalisierung, Aliase, Fallback-Routing oder eine falsche Route entstehen.
- Timeouts, fehlerhaftes JSON oder Serverfehler sind Zuverlässigkeitssignale und sollten vor starken Schlussfolgerungen meist erneut getestet werden.
- Hohe Ähnlichkeit zu einem Basismodell ist Verhaltenshinweis und sollte zusammen mit negativen Kontrollen und HTTP-Evidence bewertet werden.

Für Abrechnung, Beschaffung oder Incident Response sollten zusätzlich Provider-Logs, Abrechnungsexporte, Vergleiche mit offiziellen Endpunkten und unabhängige Betriebsprüfungen verwendet werden.

## Fehlerbehebung

- `missing command: jq`: `jq` installieren und Terminal neu öffnen.
- `missing command: rg`: ripgrep installieren und Terminal neu öffnen.
- `relay url/key empty`: `RELAY_BASE_URL` und `RELAY_API_KEY` setzen oder `--relay-base-url` und `--relay-api-key` übergeben.
- PowerShell blockiert die Ausführung: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\check-api-quality-and-model-integrity.ps1 --mode quick` verwenden.
- Bash meldet `$'\r'` oder Syntaxfehler: sicherstellen, dass `.sh`-Dateien LF-Zeilenenden verwenden. Das Repository erzwingt dies über `.gitattributes`.
- Langsame oder hängende Endpunkte: `--connect-timeout`, `--max-time` und `--retries` verwenden.

## Lizenz

MIT. Siehe [LICENSE](LICENSE).
