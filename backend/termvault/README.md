# TermVault encrypted cloud vault

The API stores opaque AES-GCM ciphertext. Encryption and decryption happen in
the iOS app; the server never receives vault keys or plaintext infrastructure
data.

## Endpoints

- `GET /health`
- `POST /v1/register`
- `POST /v1/login`
- `GET /v1/vault`
- `PUT /v1/vault` with optimistic revision checking

Production is deployed with `compose.yml` on `127.0.0.1:8791` and exposed by
Caddy at `https://masystem.co.in/termvault-api`.

Run tests with `python3 -m unittest -v test_server.py`.
