#!/usr/bin/env bash
# Usage: ./install.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CERT_DIR="${ROOT}"

CERT_FILE="${CERT_DIR}/local.pem"
KEY_FILE="${CERT_DIR}/local-key.key"

DOMAINS=()

usage() {
	cat <<'EOF'
Usage: install.sh <domain...>
Generates a locally-trusted TLS cert (mkcert)
Examples:
  ./install.sh app.test api.app.test '*.app.test'
EOF
}

log() { printf '==> %s\n' "$*"; }
die() {
	printf '!!! %s\n' "$*" >&2
	exit 1
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	-h | --help)
		usage
		exit 0
		;;
	--)
		shift
		DOMAINS+=("$@")
		break
		;;
	-*) die "unknown option: $1" ;;
	*)
		DOMAINS+=("$1")
		shift
		;;
	esac
done

[[ ${#DOMAINS[@]} -gt 0 ]] || {
	usage
	exit 1
}

for d in "${DOMAINS[@]}"; do
	[[ "$d" == *[[:space:]]* ]] && die "invalid domain: '$d'"
done

if ! command -v mkcert &>/dev/null 2>&1; then
	die "mkcert could not be found"
fi

log "Installing local CA..."
if [[ ! -f "$(mkcert -CAROOT)/rootCA.pem" ]]; then
	mkcert -install
fi

log "Creating certificate directory..."
mkdir -p "$CERT_DIR"

log "Writing certificate to $CERT_FILE..."
mkcert -cert-file "$CERT_FILE" -key-file "$KEY_FILE" "${DOMAINS[@]}"

echo
echo "certificate: ${CERT_FILE}"
echo "key:         ${KEY_FILE}"
echo "domains:     ${DOMAINS[*]}"
echo
