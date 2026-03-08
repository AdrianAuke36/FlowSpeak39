# BlueSpeak Smoke Test Checklist

Bruk denne før hver release eller når du har ny build.

## 0) Før du starter

- Bruk siste build av BlueSpeak
- Logg inn med en testbruker
- Sett backend URL til: `https://flowspeak39-eu.onrender.com`
- Sørg for at backend JWT ligger i utklippstavla før terminaltestene (kopier token fra appen)

## 1) Backend smoke (terminal, 3-5 min)

Kjør fra prosjektrot:

```bash
cd /Users/adrianauke/Documents/FlowSpeak/flowlite-backend
JWT="$(pbpaste)"

FLOWSPEAK_BENCH_TOKEN="$JWT" npm run launch:check -- \
  --url https://flowspeak39-eu.onrender.com \
  --origin https://flow-speak-direct.lovable.app \
  --timeout 5000

FLOWSPEAK_BENCH_TOKEN="$JWT" npm run latency:profile -- \
  --url https://flowspeak39-eu.onrender.com \
  --n 24 --c 6 --budget 5000
```

### A1: Health + auth endpoints
Forventet:
- `ok: true` i launch-check
- `health`, `ready`, `version(auth)`, `metrics(auth)`, `polish(auth)`, `rewrite(auth)` er grønne

### A2: Latency profile
Forventet:
- `totalFailures = 0`
- `overall.endpointMs.p95` under valgt `budget`

## 2) App smoke (manuell, 10-15 min)

Kjør disse i rekkefølge.

### B1: Ikke innlogget-beskyttelse
Steg:
- Logg ut
- Trykk hovedtast for diktering
Forventet:
- `Signed out` popup vises
- App forsøker ikke opptak

Alt var riktig utenom, i menyen opp viser det "sing out" selvom du er utlogget. ""

### B2: Innlogging
Steg:
- Logg inn igjen
Forventet:
- Du kommer til Home
- Backend vises som online
riktig

### B3: Onboarding permissions
Steg:
- Kjør onboarding på ny bruker/maskin
Forventet:
- Accessibility/Input/Mic kan fullføres
- Continue-knapper fungerer

### B4: Vanlig diktering (hovedtast)
Input (si):
- `Hei dette er en test punktum`
Forventet:
- `Hei dette er en test.`
- Blå overlay

Hei dette er en test.

### B5: Korrigering i samme setning
Input (si):
- `Kaffe på torsdag eh nei fredag`
Forventet:
- Kun siste valg beholdes (`fredag`)
- `torsdag` skal ikke stå igjen i slutttekst

test 1:Kaffe fredag.
test 2:Kaffe fredag.

### B6: Tegnsetting med stemme
Input (si):
- `mat slash brus`
- `åpen parantes test lukket parantes`
Forventet:
- `mat/brus`
- `(test)`

Test 1: Handleliste
- mat
- brus

### B7: Liste når det gir mening
Input (si):
- `Handleliste egg brød rosiner`
Forventet:
- Listeformat:
  - `Handleliste`
  - `- egg`
  - `- brød`
  - `- rosiner`
Test 1:Handleliste
- egg
- brød
- rosiner

### B8: Ikke hardkod handleliste
Input (si):
- `Det vi trenger til middag pasta tomatsaus basilikum`
Forventet:
- Naturlig heading + punkter, f.eks.:
  - `Det vi trenger til middag:`
  - `- pasta`
  - `- tomatsaus`
  - `- basilikum`
  Test 1: Det vi trenger til middag:
- det , til middag
- pasta
- tomatsaus
- basilikum

### B9: Oversettelse (hovedtast + Shift)
Input (si):
- `handleliste for i morgen taco ingredienser egg melk`
Forventet:
- Grønn overlay
- Engelsk output (ikke blanding med norsk)
- Punktliste med naturlig heading
test 1:Shopping list for tomorrow:
- taco ingredients
- eggs
- milk
Shopping list for tomorrow:
- for tomorrow: taco
- shirt
- eggs
- milk

### B10: Rewrite valgt tekst (hovedtast + Control)
Steg:
- Marker en tekst
- Hold hovedtast + Control
- Si: `Gjør kortere`
Forventet:
- Rød overlay
- Markert tekst erstattes med kortere versjon

test 1:Dette er en test. Jeg heter Adrian, er 26 år og liker å utvikle apper.
det funket ikke, rød glød kom men ikke noe kortere tekst.  

### B11: Rewrite skal beholde språk
Steg:
- Marker engelsk tekst
- Kjør rewrite med instruksjon som ikke ber om oversettelse
Forventet:
- Output forblir engelsk

test 1: Hello, I'm Adrian, 26, and I enjoy developing apps.
det funket

### B12: Quick reply context lagring (hovedtast + <)
Steg:
- Trykk hovedtast + <
Forventet:
- Ingen lydbar overlay åpnes
- Check/saved feedback vises
- Debug log har `Quick reply context saved`
<<

### B13: Quick reply drafting fra lagret kontekst
Steg:
- I tomt svarfelt: hold hovedtast + Control
- Si: `Svar at jeg ikke kan komme, men takk for invitasjonen`
Forventet:
- Fullt svar (ikke bare fragment)
- Høflig tone
- E-postformat hvis feltet er e-post

test1: det fungerte ikke

### B14: Overlay-farger
Forventet:
- Blå = vanlig diktering
- Grønn = oversettelse
- Rød = rewrite
test fungerte

### B15: Meny og UI
Forventet:
- Ingen `Menu View`-toggle i menylinje
- Profile-knapp oppe til høyre fungerer
- Tips-boks viser alle shortcuts inkl. hovedtast + <

### B16: Settings
Forventet:
- Seksjoner finnes: General, Account, Data & Privacy, Plans & Billing, Advanced
- Account: first/last name kan oppdateres
- Account: reset password handling fungerer
- Account: delete account dialog finnes

## 3) Samle logg til review

I appen:
- `Settings -> Advanced -> Copy debug log`

Legg ved i svar:
- Launch-check output
- Latency-profile output
- 20-40 siste linjer fra debug-logg

## 4) Resultatmal (kopier og fyll ut)

```text
BlueSpeak Smoke Run
Dato/tid:
Build:
macOS:
Backend URL:

A1 Health+auth: PASS/FAIL
A2 Latency: PASS/FAIL (p95=___ms)

B1 Signed-out popup: PASS
B2 Login: PASS
B3 Onboarding: PASS
B4 Dictation: PASS
B5 Correction last-intent: PASS, men for kort.
B6 Punctuation voice: PASS
B7 Handleliste formatting: PASS
B8 Generic list formatting: FAIL, ble ikke riktig format
B9 Translation formatting/language: FAIL, feil format
B10 Rewrite selected: FAIL, klarte ikke å korte ned tekst, men rød glød
B11 Rewrite keep language: PASS
B12 Save reply context: FAIL, checkmark kommer opp men bytter ut text.
B13 Draft from saved context: FAIL
B14 Overlay colors: PASS
B15 Menu/UI checks: PASS
B16 Settings checks: PASS

Feil observert (kort):
1)
2)
3)

Vedlegg:
- launch-check JSON
- latency-profile JSON
- debug log utdrag
```


