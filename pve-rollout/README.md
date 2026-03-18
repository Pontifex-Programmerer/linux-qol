# Nginx Pool Serverblock Generator (HTTP + HTTPS Passthrough)

Dette scriptet genererer Nginx-konfigurasjon for et labmiljø med mange isolerte pooler.

Det støtter:

- HTTP (port 80) via klassisk reverse proxy
- HTTPS (port 443) via TLS passthrough (SNI-basert routing)

---

## 🧠 Arkitektur

```text
Internet
→ Firewall (80/443)
→ Frontend Nginx

PORT 80 (HTTP)
→ server block per pool
→ proxy_pass → 10.14.[pool].20:80

PORT 443 (HTTPS)
→ stream (TLS passthrough)
→ SNI routing
→ proxy_pass → 10.14.[pool].20:443

→ Elevens egen proxy
→ Lokal app (3000/3001/etc)