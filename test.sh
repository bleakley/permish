#!/bin/bash
# Smoke test for permish. Run from anywhere; creates a throwaway git repo
# in $TMPDIR/permish-test and verifies each mode does what it claims.
#
# Exit 0 if everything works. Non-zero if any check fails.

set -e

SB="${SB:-$(dirname "$0")/permish}"
if [ ! -x "$SB" ]; then
    echo "ERROR: $SB not found or not executable. Set SB=/path/to/permish" >&2
    exit 2
fi

TESTDIR=$(mktemp -d -t permish-test-XXXXXX)
trap "rm -rf '$TESTDIR'" EXIT
cd "$TESTDIR"
git init -q
echo "hello" > file.txt
git add . && git -c user.email=t@t -c user.name=t commit -qm initial

PASS=0
FAIL=0

check() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  ✓ $name"
        PASS=$((PASS+1))
    else
        echo "  ✗ $name (expected=$expected actual=$actual)"
        FAIL=$((FAIL+1))
    fi
}

run_silent() {
    "$SB" --quiet "$@" 2>/dev/null
}
run_ok() {
    if "$SB" --quiet "$@" >/dev/null 2>&1; then echo allow; else echo deny; fi
}

echo "Testing $SB in $TESTDIR"
echo

echo "[read mode]"
check "can read file"     allow "$(run_ok --mode read -- cat file.txt)"
check "cannot write file" deny  "$(run_ok --mode read -- bash -c 'echo x > file.txt')"
check "cannot write .git" deny  "$(run_ok --mode read -- bash -c 'echo x > .git/HEAD')"
check "/tmp is writable"  allow "$(run_ok --mode read -- bash -c 'echo x > /tmp/y')"

echo
echo "[write mode]"
check "can write file"    allow "$(run_ok --mode write -- bash -c 'echo new > file.txt')"
check "cannot write .git" deny  "$(run_ok --mode write -- bash -c 'echo x > .git/HEAD')"
check "no network"        deny  "$(run_ok --mode write -- python3 -c 'import socket;s=socket.socket();s.settimeout(2);s.connect((\"8.8.8.8\",53))')"

echo
echo "[write-git mode]"
check "can write .git"    allow "$(run_ok --mode write-git -- bash -c 'echo x > .git/test')"

echo
echo "[write-net mode]"
# Note: this one depends on the host actually having network. Skip cleanly if not.
if python3 -c 'import socket;s=socket.socket();s.settimeout(2);s.connect(("8.8.8.8",53))' 2>/dev/null; then
    check "network allowed" allow "$(run_ok --mode write-net -- python3 -c 'import socket;s=socket.socket();s.settimeout(2);s.connect((\"8.8.8.8\",53))')"
else
    echo "  - skipping network test (host has no outbound)"
fi

echo
echo "[explain]"
check "explain exits 0"   allow "$(run_ok --mode read --explain -- ls)"

echo
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
