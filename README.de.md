# Leistbarkeit von Wohnraum in Wien nach Bezirken 🏘️

Eine SQL- und Power-BI-Analyse darüber, wie sich die Leistbarkeit von Wohnraum in den 23 Wiener Bezirken zwischen 2022 und 2024 verändert hat — und was das für das Kreditrisiko bei Immobilienfinanzierungen bedeutet.

## Die Fragestellung

Die Immobilienpreise in Wien unterscheiden sich stark je nach Bezirk — von rund 3.000 €/m² in den Außenbezirken bis über 8.000 €/m² in der Innere Stadt. Für Banken, die Hypothekarkredite vergeben, ist das direkt relevant: Je höher das Verhältnis von Preis zu Einkommen in einem Bezirk, desto höher das Risiko, dass ein Kredit für die Kreditnehmerin oder den Kreditnehmer nicht mehr leistbar wird.

Diese Analyse untersucht eine einfache Frage: **In welchen Bezirken müsste ein Haushalt am längsten sparen, um sich eine typische Wohnung leisten zu können — und wie hat sich das über die Zeit verändert?**

## Datenquellen

- **Immobilienpreise**: [Statistik Austria – Immobiliendurchschnittspreise](https://www.statistik.at/statistiken/volkswirtschaft-und-oeffentliche-finanzen/preise-und-preisindizes/immobilien-durchschnittspreise) — offizielle Durchschnittspreise pro m² nach Bezirk, 2022–2024
- **Haushaltseinkommen**: [Stadt Wien – Durchschnittlicher Jahresbezug pro ArbeitnehmerIn nach Bezirken](https://www.wien.gv.at/statistik/einkommen-bezirke-zeitreihe) — durchschnittliches Nettojahreseinkommen nach Bezirk, aktuellster verfügbarer Wert (2018)

**Bekannte Einschränkung**: Die Einkommensdaten reichen nur bis 2018, während die Preisdaten den Zeitraum 2022–2024 abdecken. Zum Zeitpunkt der Erstellung dieser Analyse gab es keinen aktuelleren offenen Datensatz zu Bezirkseinkommen in Wien. Der Leistbarkeitsindex vergleicht daher aktuelle Preise mit dem Einkommen von 2018 — eine reale Einschränkung der verfügbaren Daten, kein Versehen. Die Ergebnisse sollten als richtungsweisend, nicht als exakte Momentaufnahme gelesen werden.

## Die Kennzahl

Ich habe eine eigene Kennzahl entwickelt: **Jahre bis zur Leistbarkeit einer 70-m²-Wohnung**:

```
years_to_afford_70sqm = (Durchschnittspreis pro m² × 70) / Nettojahreseinkommen
```

70 m² wurde als repräsentative Wohnungsgröße gewählt; diese Annahme ist bewusst offengelegt und könnte angepasst werden.

## Datenbankdesign

Statt einer einzigen flachen Tabelle wurden die Daten als kleines Star-Schema strukturiert:

- `districts` — Referenztabelle, ein Eintrag pro Bezirk (Primärschlüssel)
- `real_estate_prices` — Preis pro m² nach Bezirk und Jahr (Fremdschlüssel → districts)
- `district_income` — Einkommen nach Bezirk (Fremdschlüssel → districts)

Die Fremdschlüssel-Constraints sind aktiv (`PRAGMA foreign_keys = ON`), sodass die Datenbank selbst jede Zeile ablehnt, die auf einen nicht existierenden Bezirk verweist — getestet durch den bewussten Versuch, einen falsch geschriebenen Bezirksnamen einzufügen, was SQLite korrekt mit einem `FOREIGN KEY constraint failed`-Fehler verhindert hat.

## Ein reales Datenbereinigungsproblem

Beim Import der über Google Sheets exportierten Preisdaten wurden Zahlen wie `8496` in jeder Berechnung stillschweigend als `8` gelesen — es gab keine Fehlermeldung, die Abfrage lieferte einfach falsche (nahezu Null) Ergebnisse. Mit der SQLite-Funktion `hex()` konnte ich die Ursache finden: Google Sheets hatte das Tausendertrennzeichen als **geschütztes Leerzeichen** (Unicode U+00A0 / `C2A0` in UTF-8) exportiert — optisch identisch mit einem normalen Leerzeichen, aber technisch ein anderes Zeichen, weshalb `REPLACE(value, ' ', '')` es nicht entfernen konnte.

Lösung: `REPLACE(value, CHAR(160), '')` vor der Umwandlung in einen numerischen Typ.

Diese Art von unsichtbarem Formatierungsproblem ist ein typisches Datenqualitätsproblem aus der Praxis — es zu diagnostizieren (statt die Zahlen einfach neu einzutippen) war einer der lehrreichsten Momente bei diesem Projekt.

## Zentrale Erkenntnisse (2024)

![Benötigte Einkommensjahre für eine 70-m²-Wohnung nach Bezirk](images/bar_chart.png)

![Entwicklung der Leistbarkeit 2022–2024 für fünf ausgewählte Bezirke](images/line_chart.png)

| Rang | Bezirk | Benötigte Einkommensjahre (70 m²) |
|---|---|---|
| 1 | Innere Stadt | 22,5 |
| 2 | Josefstadt | 16,0 |
| 3 | Wieden | 15,9 |
| ... | ... | ... |
| 22 | Liesing | 10,3 |
| 23 | Simmering | 10,2 |

- **Die Innere Stadt ist ein klarer Ausreißer** — rund 40 % höher als der zweitteuerste Bezirk, mit einem auffälligen Sprung zwischen 2023 (30,3 Jahre) und 2024 (22,5 Jahre), der laut Methodik-Hinweis von Statistik Austria eher auf die geringe Anzahl an Transaktionen in diesem Bezirk zurückzuführen ist als auf eine tatsächliche Marktverschiebung.
- Die **Außenbezirke** (Simmering, Liesing, Floridsdorf) sind durchgehend am leistbarsten und blieben über alle drei Jahre relativ stabil.

## Aufbau des Repositorys

```
data/raw/        Originaltabelle von Statistik Austria (.ods)
data/prepared/   in Google Sheets aufbereitete CSV-Dateien, Input für SQL
data/output/     finale Leistbarkeitstabelle (Export der SQL-View)
sql/             vollständige SQL-Pipeline: Schema, Bereinigung, View, Analysen
database/        resultierende SQLite-Datenbank
images/          Screenshots der Power-BI-Diagramme
```

Reproduzierbar: die beiden CSV-Dateien aus `data/prepared/` in eine leere SQLite-Datenbank importieren (als `raw_prices` und `raw_income`) und `sql/analysis.sql` ausführen — Details in den Kommentaren am Anfang des Skripts.

## Verwendete Tools

- **SQLite** (über DB Browser for SQLite) — Datenspeicherung, -bereinigung und -analyse
- **SQL** — Joins, Subqueries, Aggregatfunktionen, Views, Schemadesign mit Primär-/Fremdschlüsseln
- **Power BI** — Balkendiagramm und mehrjährige Liniendiagramm-Visualisierungen
- **Google Sheets** — erste Datenaufbereitung aus den Rohdaten von Statistik Austria

## Mögliche nächste Schritte

- Eine Choroplethenkarte Wiens nach Bezirken — versucht mit Power BIs Filled-Map- und Azure-Maps-Visuals, jedoch an reale technische Grenzen gestoßen: Bings Geocoding löst keine Bezirksgrenzen auf (es liefert stattdessen die gesamte Stadtgrenze), und die Reference-Layer-Funktion von Azure Maps erfordert ein organisatorisches Microsoft-Konto, das bei einem privaten Konto nicht verfügbar ist. Für eine zukünftige Version vorgesehen, eventuell mit Python (folium/geopandas).
- Aktuellere Einkommensdaten, sobald Statistik Austria oder die Stadt Wien eine Aktualisierung nach 2018 veröffentlichen.
- Erweiterung des Leistbarkeitsindex um Hypothekarzinsen (EZB-/OeNB-Daten), um die tatsächliche monatliche Belastung statt nur des reinen Preis-Einkommens-Verhältnisses abzubilden.

## Hinweis zum Arbeitsprozess

Ich habe Claude (Anthropic) als Lernassistenten verwendet, um SQL von Grund auf zu lernen, das Problem mit dem unsichtbaren Zeichen zu debuggen und das Datenbankschema zu entwerfen. Ich verstehe die Logik hinter jeder Abfrage und jeder Designentscheidung in diesem Projekt und kann sie erklären — ich nenne die KI-Nutzung hier aus Transparenzgründen, statt sie unerwähnt zu lassen.

---

*Erstellt von einem Schüler (mit Studienziel Wirtschaftsinformatik in Wien) als erstes praktisches SQL- und Power-BI-Projekt.*
