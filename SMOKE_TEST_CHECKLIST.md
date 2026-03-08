# BlueSpeak Smoke Test Checklist

Input (si):
- `Hei dette er en test punktum`
Forventet:
- `Hei dette er en test.`
- Blå overlay

#Test: 
Dette er en test.
det fungerte


### B5: Korrigering i samme setning
Input (si):
- `Kaffe på torsdag eh nei fredag`
Forventet:
- Kun siste valg beholdes (`fredag`)
- `torsdag` skal ikke stå igjen i slutttekst

#Test: 
test 1:Kaffe på torsdag eller fredag.
test 2: Kaffe fredag.



### B6: Tegnsetting med stemme
Input (si):
- `mat slash brus`
- `åpen parantes test lukket parantes`
Forventet:
- `mat/brus`
Handleliste
- mat
- brus
Mat/brus.


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
  



### B8: Ikke hardkod handleliste
Input (si):
- `Det vi trenger til middag pasta tomatsaus basilikum`
Forventet:
- Naturlig heading + punkter, f.eks.:
  - `Det vi trenger til middag:`
  - `- pasta`
  - `- tomatsaus`
  - `- basilikum`
  
  Det vi trenger til middag:
- det , til middag
- det
- kjøttdeig


### B9: Oversettelse (hovedtast + Shift)
Input (si):
- `handleliste for i morgen taco ingredienser egg melk`
Forventet:
- Grønn overlay
- Engelsk output (ikke blanding med norsk)
- Punktliste med naturlig heading

What we need for dinner:
- what , for dinner
- that
- basil





### B10: Rewrite valgt tekst (hovedtast + Control)
Steg:
- Marker en tekst
- Hold hovedtast + Control
- Si: `Gjør kortere`
Forventet:
- Rød overlay
- Markert tekst erstattes med kortere versjon


### B11: Rewrite skal beholde språk
Steg:
- Marker engelsk tekst
- Kjør rewrite med instruksjon som ikke ber om oversettelse
Forventet:
- Output forblir engelsk


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





B6 Punctuation voice: PASS
B7 Handleliste formatting: PASS
B8 Generic list formatting: FAIL, ble ikke riktig format
B9 Translation formatting/language: FAIL, feil format
B10 Rewrite selected: FAIL, klarte ikke å korte ned tekst, men rød glød
B11 Rewrite keep language: PASS
B12 Save reply context: FAIL, checkmark kommer opp men bytter ut text.
B13 Draft from saved context: FAIL



