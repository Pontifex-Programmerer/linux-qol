# Proxy pool scripts

Dette dokumentet beskriver hva de tre script-ene gjør:

* `proxy-pool-config.sh`
* `proxy-pool-state.sh`
* `proxy-pool-report.sh`

## Oversikt

Scriptpakken er laget for å administrere Nginx-konfigurasjon for pool-baserte domener som `1.bleikervgs.no`, `2.bleikervgs.no` osv.

Løsningen er delt i tre ansvar:

* **config**: oppretter eller fjerner konfigurasjonsfiler i `available`-mappene
* **state**: aktiverer eller deaktiverer konfigurasjoner ved å lage/fjerne symlinks i `enabled`-mappene
* **report**: viser status for hvilke pooler som finnes, er aktivert, mangler eller er delvis konfigurert

---

## `proxy-pool-config.sh`

Dette scriptet brukes til å **opprette** eller **fjerne** konfigurasjonsfiler for HTTP og stream per pool.

### Hva scriptet gjør

Når du kjører `create`, lager det to filer per pool:

* én HTTP-konfigurasjon i `sites-available`
* én stream-konfigurasjon i `streams-available`

Når du kjører `remove`, sletter det disse filene fra `available`-mappene.

### Hva som genereres

For hver pool bygges følgende:

* domene: `<pool>.bleikervgs.no`
* backend-IP: `<network-prefix>.<pool>.<host-octet>`

Standardverdier:

* `network-prefix`: `10.14`
* `host-octet`: `20`

Eksempel for pool `7`:

* domene: `7.bleikervgs.no`
* backend: `10.14.7.20`

### HTTP-del

HTTP-konfigurasjonen lager en vanlig reverse proxy på port 80 mot backend-maskinen for den aktuelle poolen.

Den setter også vanlige proxy-headere som:

* `Host`
* `X-Real-IP`
* `X-Forwarded-For`
* `X-Forwarded-Proto`

I tillegg er støtte for `Upgrade`/`Connection` tatt med.

### Stream-del

Stream-konfigurasjonen lager SNI-basert ruting for TLS passthrough på port 443.

Det betyr at HTTPS-trafikk ikke termineres her, men sendes videre til backend basert på domenenavn.

### Viktig avgrensning

Scriptet **aktiverer ikke** konfigurasjonen. Det skriver kun filer til:

* `/etc/nginx/sites-available`
* `/etc/nginx/streams-available`

Aktivering gjøres separat med `proxy-pool-state.sh`.

### Viktige valg

* `--overwrite` gjør at eksisterende filer blir overskrevet ved `create`
* `--dry-run` viser hva som ville blitt laget eller slettet uten å gjøre endringer
* egendefinerte output-mapper kan settes med:

  * `--http-output-dir`
  * `--stream-output-dir`

### Eksempler

```bash
proxy-pool-config.sh create --start 1 --end 10
proxy-pool-config.sh create --start 1 --end 10 --overwrite
proxy-pool-config.sh create --start 99 --end 99 --dry-run
proxy-pool-config.sh remove --start 1 --end 10
```

---

## `proxy-pool-state.sh`

Dette scriptet brukes til å **enable**, **disable** eller **sjekke status** for en eller flere pooler.

### Hva scriptet gjør

Scriptet jobber med symlinks mellom:

* `sites-available` → `sites-enabled`
* `streams-available` → `streams-enabled`

Det betyr at det styrer om en pool faktisk er aktiv i Nginx.

### Kommandoer

#### `enable`

Lager symlinks for både HTTP- og stream-konfigurasjon for valgt pool.

For at dette skal lykkes må begge kildefilene allerede finnes i `available`-mappene.

#### `disable`

Fjerner symlinks for både HTTP og stream fra `enabled`-mappene.

#### `status`

Viser om konfigurasjonen finnes i `available`, og om den er aktivert i `enabled`.

### Nginx reload

Ved `enable` og `disable` kjører scriptet som standard:

```bash
nginx -t
systemctl reload nginx
```

Dette gjør at konfigurasjonen testes og lastes inn automatisk.

### Viktige valg

* `--dry-run` viser hva som ville blitt gjort
* `--no-reload` hopper over `nginx -t` og reload

### Pool-formater

Scriptet støtter:

* enkel pool: `3`
* intervall: `1-10`
* flere enkeltpooler: `3 5 7`

### Eksempler

```bash
proxy-pool-state.sh enable 3
proxy-pool-state.sh disable 3
proxy-pool-state.sh status 3
proxy-pool-state.sh enable 1-10
proxy-pool-state.sh disable 3 5 7
proxy-pool-state.sh enable 1-5 --dry-run
proxy-pool-state.sh disable 1-5 --no-reload
```

---

## `proxy-pool-report.sh`

Dette scriptet brukes til å lage en **statusrapport** over hvilke pooler som finnes og hvordan de er konfigurert.

### Hva scriptet gjør

Scriptet undersøker fire steder:

* `/etc/nginx/sites-available`
* `/etc/nginx/sites-enabled`
* `/etc/nginx/streams-available`
* `/etc/nginx/streams-enabled`

Basert på dette viser det en tabell per pool.

### Kolonner i rapporten

* `Pool` – poolnummer
* `HTTP-A` – HTTP-konfig finnes i `sites-available`
* `HTTP-E` – HTTP er aktivert i `sites-enabled`
* `STR-A` – stream-konfig finnes i `streams-available`
* `STR-E` – stream er aktivert i `streams-enabled`
* `Status` – samlet vurdering

### Mulige statuser

#### `enabled`

Poolen er fullt konfigurert:

* HTTP finnes
* stream finnes
* begge er aktivert

#### `partial`

Poolen er delvis satt opp:

* noe finnes eller er aktivert, men ikke alt

#### `available-only`

Konfigurasjon finnes i `available`, men ingenting er aktivert

#### `missing`

Ingen konfigurasjon finnes for poolen

### Automatisk oppdagelse

Hvis du ikke oppgir noen pooler, prøver scriptet å oppdage poolnumre automatisk ved å lese filnavn fra både `available` og `enabled`.

### Filtrering

Du kan filtrere rapporten med:

* `--enabled`
* `--partial`
* `--available`
* `--missing`

### Outputvalg

* `--no-header` skjuler overskriften i tabellen
* `--summary` viser summering etter tabellen

### Eksempler

```bash
proxy-pool-report.sh
proxy-pool-report.sh 3
proxy-pool-report.sh 1-10
proxy-pool-report.sh --enabled
proxy-pool-report.sh --partial 1-20
proxy-pool-report.sh --missing 1-100
proxy-pool-report.sh --summary
proxy-pool-report.sh --enabled --no-header
```

---

## Typisk arbeidsflyt

En normal arbeidsflyt med disse script-ene vil være:

### 1. Opprett konfigurasjon

```bash
proxy-pool-config.sh create --start 1 --end 10
```

Dette lager filer i `available`-mappene.

### 2. Aktiver ønskede pooler

```bash
proxy-pool-state.sh enable 1-10
```

Dette lager symlinks i `enabled`-mappene og reloader Nginx.

### 3. Kontroller status

```bash
proxy-pool-report.sh --summary
```

Dette viser hvilke pooler som er aktivert, delvise eller mangler.

### 4. Deaktiver ved behov

```bash
proxy-pool-state.sh disable 3
```

### 5. Fjern konfigurasjon ved behov

```bash
proxy-pool-config.sh remove --start 3 --end 3
```

---

## Kort oppsummert

* `proxy-pool-config.sh` oppretter eller fjerner konfigurasjonsfiler
* `proxy-pool-state.sh` aktiverer eller deaktiverer dem
* `proxy-pool-report.sh` viser status og gir oversikt

Til sammen gir dette en ryddig modell der:

* generering av filer
* aktivering/deaktivering
* rapportering

...er tydelig skilt fra hverandre.
