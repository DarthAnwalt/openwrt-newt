#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail
umask 077

key_dir="${1:-./signing-key}"
private_key="$key_dir/private-key.pem"
public_key="$key_dir/newt-repository.pem"

mkdir -p "$key_dir"
if [[ -e "$private_key" || -e "$public_key" ]]; then
	echo "Refusing to overwrite an existing key in $key_dir" >&2
	exit 1
fi

openssl ecparam -name prime256v1 -genkey -noout -out "$private_key"
openssl ec -in "$private_key" -pubout -out "$public_key"
chmod 0600 "$private_key"
chmod 0644 "$public_key"

cat <<EOF
Generated:
  private: $private_key
  public:  $public_key

Keep the private key offline. Add its base64 value as the GitHub Actions
secret APK_SIGNING_KEY_B64 with:

  gh secret set APK_SIGNING_KEY_B64 < <(base64 < "$private_key" | tr -d '\n')
EOF

