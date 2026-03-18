# Nginx Pool Serverblock Generator

Dette scriptet genererer Nginx `server`-blokker for hver pool i et labmiljø, og peker trafikk videre til en fast backend-IP per pool.

Designet for miljøer der:

- Hver pool har eget subnet (f.eks. `10.14.[pool].0/24`)
- Backend-proxy per pool ligger på en fast IP (f.eks. `.20`)
- Frontend-proxy håndterer publisering basert på subdomain (`[pool].bleikervgs.no`)

---

## 📦 Funksjonalitet

Scriptet:

- Genererer én serverblock per pool
- Setter riktig `proxy_pass` til backend
- Kan:
  - skrive til `sites-available`
  - lage symlink til `sites-enabled`
  - overskrive eksisterende filer
  - kjøre i `dry-run` modus

---

## 🧠 Arkitektur

```text
Internet
→ Firewall (80/443)
→ Frontend Nginx (denne configen)
→ [pool].bleikervgs.no
→ 10.14.[pool].20:80
→ Elevens egen proxy
→ Lokal app (3000/3001/etc)