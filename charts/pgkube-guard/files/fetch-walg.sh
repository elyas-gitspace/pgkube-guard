#!/bin/sh
# Restore drill wal-g, étape 1 (image curl) : télécharge le binaire wal-g dans /walg pour l'étape suivante
set -u
ko() { echo "$1" >> /work/error.log; echo ko > /work/status; exit 0; }

# URL vide = l'utilisateur fournit une image qui contient déjà wal-g
if [ -z "${WALG_BINARY_URL:-}" ]; then
  echo "verify.walg.binaryUrl is empty, using the wal-g shipped in the restore image"
  echo ok > /work/status
  exit 0
fi

echo "Downloading wal-g from $WALG_BINARY_URL..."
curl -fsSL -m 300 -o /walg/wal-g "$WALG_BINARY_URL" 2>>/work/error.log \
  || ko "could not download wal-g from $WALG_BINARY_URL"

# Vérifie l'empreinte sha256 si un fichier .sha256 est publié à côté (c'est le cas sur les releases wal-g)
EXPECTED=$(curl -fsSL -m 30 "$WALG_BINARY_URL.sha256" 2>/dev/null | cut -d' ' -f1)
if [ -n "$EXPECTED" ]; then
  ACTUAL=$(sha256sum /walg/wal-g | cut -d' ' -f1)
  [ "$EXPECTED" = "$ACTUAL" ] || ko "wal-g checksum mismatch (expected $EXPECTED, got $ACTUAL)"
  echo "Checksum OK"
fi

chmod 755 /walg/wal-g
echo ok > /work/status
exit 0
