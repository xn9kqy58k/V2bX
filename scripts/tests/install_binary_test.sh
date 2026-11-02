#!/usr/bin/env bash
set -euo pipefail

[[ $# == 1 && -f "$1" ]] || { printf '用法：bash install_binary_test.sh /path/to/Linux/V2bX\n' >&2; exit 1; }
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$script_dir/install.sh"
for dependency in zip unzip sha256sum timeout; do command -v "$dependency" >/dev/null || exit 1; done
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/v2bx-installer-binary-test.XXXXXX")
trap 'rm -rf -- "$test_dir"' EXIT
mkdir -p "$test_dir/release" "$test_dir/tools" "$test_dir/bin" "$test_dir/config" "$test_dir/units"
cp -- "$1" "$test_dir/release/V2bX"
chmod +x "$test_dir/release/V2bX"
timeout 15 "$test_dir/release/V2bX" version
asset="V2bX-$(detect_arch).zip"
printf 'release geo data\n' >"$test_dir/release/geoip.dat"
(cd "$test_dir/release"; zip -q "$asset" V2bX geoip.dat; sha256sum "$asset" >"$asset.sha256")

# Only these fake commands shadow the host; all installation paths stay in test_dir.
cat >"$test_dir/tools/curl" <<'EOF'
#!/usr/bin/env bash
set -eu
destination=''
while [[ $# -gt 0 ]]; do
    case "$1" in --output) destination=$2; shift 2 ;; *) url=$1; shift ;; esac
done
[[ "$url" == https://github.com/xn9kqy58k/V2bX/releases/* && -n "$destination" ]] || exit 1
printf '%s\n' "$url" >>"$TEST_RELEASE/downloads"
cp -- "$TEST_RELEASE/${url##*/}" "$destination"
EOF
cat >"$test_dir/tools/id" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == -u ]] && printf '0\n'
EOF
chmod +x "$test_dir/tools/curl" "$test_dir/tools/id"
export PATH="$test_dir/tools:$PATH" TEST_RELEASE="$test_dir/release"
install_args=(--no-service --yes --install-dir "$test_dir/bin" --config-dir "$test_dir/config" --service-dir "$test_dir/units")
"$BASH" "$script_dir/install.sh" install --version v0.4.2 "${install_args[@]}"
timeout 15 "$test_dir/bin/V2bX" version
[[ -f "$test_dir/config/config.json.example" && ! -e "$test_dir/config/config.json" && ! -e "$test_dir/units/V2bX.service" ]]
printf 'preserve exact configuration\n' >"$test_dir/config/config.json"
printf 'preserve my geo data\n' >"$test_dir/config/geoip.dat"
"$BASH" "$script_dir/install.sh" update "${install_args[@]}"
[[ $(cat "$test_dir/config/config.json") == 'preserve exact configuration' ]]
[[ $(cat "$test_dir/config/geoip.dat") == 'preserve my geo data' ]]
cp "$test_dir/bin/V2bX" "$test_dir/installed-before-failure"
printf '%064d  %s\n' 0 "$asset" >"$test_dir/release/$asset.sha256"
if "$BASH" "$script_dir/install.sh" update "${install_args[@]}"; then printf 'FAIL: accepted corrupted checksum\n' >&2; exit 1; fi
cmp -s "$test_dir/bin/V2bX" "$test_dir/installed-before-failure"
timeout 15 "$test_dir/bin/V2bX" version
printf 'PASS: real Linux binary installed and updated in an isolated directory; config preserved; corrupted download rejected\n'
