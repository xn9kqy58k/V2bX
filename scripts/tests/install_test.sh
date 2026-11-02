#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# Sourcing defines pure helpers only; it must never start an installation.
source "$script_dir/install.sh"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/v2bx-installer-tests.XXXXXX")
trap 'rm -rf -- "$test_dir"' EXIT

assert_eq() { [[ "$1" == "$2" ]] || { printf 'FAIL: expected <%s>, got <%s>\n' "$2" "$1" >&2; exit 1; }; }
assert_file_eq() { cmp -s -- "$1" "$2" || { printf 'FAIL: file differs: %s\n' "$1" >&2; exit 1; }; }

assert_eq "$(release_arch x86_64 64)" linux-64
assert_eq "$(release_arch x86_64 32)" linux-32
assert_eq "$(release_arch i686 32)" linux-32
assert_eq "$(release_arch aarch64 64)" linux-arm64-v8a
assert_eq "$(release_arch aarch64 32)" linux-arm32-v7a
assert_eq "$(release_arch armv8l 32)" linux-arm32-v7a
assert_eq "$(release_arch armv6l 32)" linux-arm32-v6
assert_eq "$(release_arch armv5tejl 32)" linux-arm32-v5
assert_eq "$(release_arch mips 32 little)" linux-mips32le
assert_eq "$(release_arch mips 32 big)" linux-mips32
assert_eq "$(release_arch mips64 64 little)" linux-mips64le
assert_eq "$(release_arch mips64 32 big)" linux-mips32
assert_eq "$(release_arch ppc64le 64)" linux-ppc64le
assert_eq "$(release_arch riscv64 64)" linux-riscv64
if release_arch unknown 64 >/dev/null; then exit 1; fi
if release_arch mips 32 >/dev/null; then exit 1; fi
render_service /usr/local/bin /etc/V2bX >"$test_dir/default.service"
assert_file_eq "$test_dir/default.service" "$script_dir/V2bX.service"

mkdir -p "$test_dir/fixture"
cat >"$test_dir/fixture/new-binary" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == version ]] || exit 1
echo 'V2bX installer fixture'
EOF
chmod +x "$test_dir/fixture/new-binary"
digest=$(sha256sum "$test_dir/fixture/new-binary"); digest=${digest%% *}
printf '%s  V2bX-linux-64.zip\n' "$digest" >"$test_dir/fixture/checksum"
cat >"$test_dir/runner.sh" <<'EOF'
#!/usr/bin/env bash
source "$INSTALLER"
id() { [[ "$1" == -u ]] && printf '0\n'; }
uname() { case "$1" in -s) printf 'Linux\n' ;; -m) printf 'x86_64\n' ;; esac; }
getconf() { printf '64\n'; }
sleep() { :; }
systemd_available() { [[ "${TEST_SYSTEMD:-0}" == 1 ]]; }
download() {
    printf '%s\n' "$1" >>"$TEST_CASE/downloads"
    [[ "${TEST_DOWNLOAD_FAIL:-0}" == 0 ]] || return 1
    case "$1" in
        https://github.com/xn9kqy58k/V2bX/releases/*.zip.sha256)
            if [[ "${TEST_BAD_CHECKSUM:-0}" == 1 ]]; then
                printf '%064d  V2bX-linux-64.zip\n' 0 >"$2"
            else cp "$FIXTURE/checksum" "$2"; fi ;;
        https://github.com/xn9kqy58k/V2bX/releases/*.zip) cp "$FIXTURE/new-binary" "$2" ;;
        *) return 1 ;;
    esac
}
unzip() {
    printf '%s\n' "$3" >>"$TEST_CASE/extracted"
    case "$3" in
        V2bX) cat "$2" ;;
        geoip.dat) printf 'bundled geo data\n' ;;
        *) return 11 ;;
    esac
}
systemctl() {
    printf '%s\n' "$*" >>"$TEST_CASE/systemctl"
    case "$1" in
        show)
            if [[ "$2" == --property=FragmentPath ]]; then
                if [[ -n "${TEST_FRAGMENT_PATH:-}" ]]; then printf '%s\n' "$TEST_FRAGMENT_PATH"
                elif [[ -e "$TEST_CASE/service/V2bX.service" ]]; then printf '%s\n' "$TEST_CASE/service/V2bX.service"; fi
            else
                printf '{ path=%s ; argv[]=%s server ; ignore_errors=no ; }\n' "${TEST_SERVICE_BINARY:-$TEST_CASE/bin/V2bX}" "${TEST_SERVICE_BINARY:-$TEST_CASE/bin/V2bX}"
            fi ;;
        is-active) [[ "${TEST_WAS_ACTIVE:-0}" == 1 || -f "$TEST_CASE/active" ]] ;;
        is-enabled) [[ "${TEST_WAS_ENABLED:-0}" == 1 ]] ;;
        restart)
            if [[ "${TEST_FAIL_RESTART:-0}" == 1 && ! -f "$TEST_CASE/restart-failed" ]]; then
                touch "$TEST_CASE/restart-failed"; return 1
            fi
            touch "$TEST_CASE/active" ;;
        stop) rm -f "$TEST_CASE/active" ;;
        *) return 0 ;;
    esac
}
main "$@"
EOF

export INSTALLER="$script_dir/install.sh" FIXTURE="$test_dir/fixture"
new_case() {
    TEST_CASE="$test_dir/$1"; export TEST_CASE
    mkdir -p "$TEST_CASE/bin" "$TEST_CASE/config" "$TEST_CASE/service"
}
run_case() {
    "$BASH" "$test_dir/runner.sh" "$@" --install-dir "$TEST_CASE/bin" --config-dir "$TEST_CASE/config" --service-dir "$TEST_CASE/service"
}
expect_failure() { if "$@"; then printf 'FAIL: command unexpectedly succeeded\n' >&2; exit 1; fi; }

new_case 'fresh install; spaces'
TEST_SYSTEMD=1 run_case install --yes --version v0.4.2
assert_file_eq "$TEST_CASE/bin/V2bX" "$FIXTURE/new-binary"
[[ -f "$TEST_CASE/config/config.json.example" && ! -e "$TEST_CASE/config/config.json" ]]
[[ -f "$TEST_CASE/service/V2bX.service" ]]
[[ -f "$TEST_CASE/config/geoip.dat" ]]
if grep -Eq '^(enable|restart|start) ' "$TEST_CASE/systemctl"; then exit 1; fi
grep -Fq '/releases/download/v0.4.2/V2bX-linux-64.zip.sha256' "$TEST_CASE/downloads"

printf 'keep my config\n' >"$TEST_CASE/config/config.json"
printf 'keep my geo data\n' >"$TEST_CASE/config/geoip.dat"
TEST_SYSTEMD=1 TEST_WAS_ACTIVE=1 run_case update
assert_eq "$(cat "$TEST_CASE/config/config.json")" 'keep my config'
assert_eq "$(cat "$TEST_CASE/config/geoip.dat")" 'keep my geo data'
grep -Fq 'restart V2bX.service' "$TEST_CASE/systemctl"

new_case no-service
TEST_SYSTEMD=1 run_case install --no-service
[[ ! -e "$TEST_CASE/systemctl" && ! -e "$TEST_CASE/service/V2bX.service" ]]

for failure in checksum download; do
    new_case "$failure"
    printf 'old program\n' >"$TEST_CASE/bin/V2bX"
    cp "$TEST_CASE/bin/V2bX" "$TEST_CASE/old-binary"
    if [[ "$failure" == checksum ]]; then
        TEST_BAD_CHECKSUM=1 expect_failure run_case update --no-service
    else
        TEST_DOWNLOAD_FAIL=1 expect_failure run_case update --no-service
    fi
    assert_file_eq "$TEST_CASE/bin/V2bX" "$TEST_CASE/old-binary"
    [[ ! -e "$TEST_CASE/extracted" ]]
done

new_case restart-failure
printf 'old program\n' >"$TEST_CASE/bin/V2bX"
cp "$TEST_CASE/bin/V2bX" "$TEST_CASE/old-binary"
printf 'existing config\n' >"$TEST_CASE/config/config.json"
printf 'old unit\n' >"$TEST_CASE/service/V2bX.service"
cp "$TEST_CASE/service/V2bX.service" "$TEST_CASE/old-unit"
TEST_SYSTEMD=1 TEST_WAS_ACTIVE=1 TEST_WAS_ENABLED=1 TEST_FAIL_RESTART=1 expect_failure run_case update
assert_file_eq "$TEST_CASE/bin/V2bX" "$TEST_CASE/old-binary"
assert_file_eq "$TEST_CASE/service/V2bX.service" "$TEST_CASE/old-unit"
assert_eq "$(grep -c '^restart V2bX.service$' "$TEST_CASE/systemctl")" 2

new_case different-service-path
printf 'old program\n' >"$TEST_CASE/bin/V2bX"
cp "$TEST_CASE/bin/V2bX" "$TEST_CASE/old-binary"
printf 'custom configuration\n' >"$TEST_CASE/config/config.json"
cp "$TEST_CASE/config/config.json" "$TEST_CASE/old-config"
printf 'custom unit\n' >"$TEST_CASE/service/V2bX.service"
TEST_SYSTEMD=1 TEST_SERVICE_BINARY=/opt/another/V2bX expect_failure run_case update
assert_file_eq "$TEST_CASE/bin/V2bX" "$TEST_CASE/old-binary"
assert_file_eq "$TEST_CASE/config/config.json" "$TEST_CASE/old-config"
[[ ! -e "$TEST_CASE/downloads" ]]

new_case vendor-service
printf 'old program\n' >"$TEST_CASE/bin/V2bX"
cp "$TEST_CASE/bin/V2bX" "$TEST_CASE/old-binary"
printf 'custom configuration\n' >"$TEST_CASE/config/config.json"
mkdir "$TEST_CASE/vendor"
printf 'vendor unit with user settings\n' >"$TEST_CASE/vendor/V2bX.service"
cp "$TEST_CASE/vendor/V2bX.service" "$TEST_CASE/old-unit"
TEST_SYSTEMD=1 TEST_FRAGMENT_PATH="$TEST_CASE/vendor/V2bX.service" expect_failure run_case update
assert_file_eq "$TEST_CASE/bin/V2bX" "$TEST_CASE/old-binary"
assert_file_eq "$TEST_CASE/vendor/V2bX.service" "$TEST_CASE/old-unit"
[[ ! -e "$TEST_CASE/service/V2bX.service" && ! -e "$TEST_CASE/downloads" ]]

new_case invalid-version
expect_failure run_case install --no-service --version 'v0.4.2; printf unsafe'
[[ ! -e "$TEST_CASE/downloads" && ! -e "$TEST_CASE/bin/V2bX" ]]

new_case missing-update
expect_failure run_case update --no-service
[[ ! -e "$TEST_CASE/downloads" ]]
printf 'PASS: installer mapping, isolated install/update, config preservation, checksum/download rejection, service rollback\n'
