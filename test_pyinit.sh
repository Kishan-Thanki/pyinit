#!/usr/bin/env bash
set -euo pipefail

PYINIT_SCRIPT="$(pwd)/pyinit"
TEST_DIR=""

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' 

PASSED_COUNT=0
FAILED_COUNT=0

setup() {
    TEST_DIR="$(mktemp -d /tmp/pyinit_test_XXXXXX)"
}

cleanup() {
    local exit_code=$?
    
    trap - EXIT INT TSTP TERM

    if [ -n "${TEST_DIR:-}" ] && [ -d "$TEST_DIR" ]; then
        chmod -R u+w "$TEST_DIR" 2>/dev/null || true
        rm -rf "$TEST_DIR"
    fi

    jobs -p | xargs -r kill -9 2>/dev/null || true

    if [ "$exit_code" -ne 0 ]; then
        echo -e "\n${RED}Test execution interrupted or aborted.${NC}"
    fi

    exit "$exit_code"
}

trap cleanup EXIT INT TSTP TERM

run_test() {
    local test_name="$1"
    shift
    
    echo -n "Running: $test_name ... "
    
    local sub_test_dir="$TEST_DIR/run_$(date +%s%N)_$RANDOM"
    mkdir -p "$sub_test_dir"
    
    if ( cd "$sub_test_dir" && "$@" >/dev/null 2>&1 ); then
        echo -e "${GREEN}PASS${NC}"
        PASSED_COUNT=$((PASSED_COUNT + 1))
    else
        echo -e "${RED}FAIL${NC}"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi

    rm -rf "$sub_test_dir"
}

run_failing_test() {
    local test_name="$1"
    shift
    
    echo -n "Running (expecting error): $test_name ... "
    
    local sub_test_dir="$TEST_DIR/run_$(date +%s%N)_$RANDOM"
    mkdir -p "$sub_test_dir"
    
    if ( cd "$sub_test_dir" && "$@" >/dev/null 2>&1 ); then
        echo -e "${RED}FAIL (expected exit status > 0, got 0)${NC}"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    else
        echo -e "${GREEN}PASS${NC}"
        PASSED_COUNT=$((PASSED_COUNT + 1))
    fi

    rm -rf "$sub_test_dir"
}

assert_importable() {
    local test_name="$1"
    local raw_name="$2"
    shift 2

    echo -n "Running (importability): $test_name ... "

    local sub_test_dir="$TEST_DIR/run_$(date +%s%N)_$RANDOM"
    mkdir -p "$sub_test_dir"

    if (
        cd "$sub_test_dir"
        
        if [ "$#" -gt 0 ]; then
            "$PYINIT_SCRIPT" --name "$raw_name" "$@" >/dev/null 2>&1 || exit 1
        else
            "$PYINIT_SCRIPT" --name "$raw_name" >/dev/null 2>&1 || exit 1
        fi

        cd "$raw_name" || exit 1

        local search_root="src"
        [ -d "src" ] || search_root="."

        local pkg_dir
        pkg_dir="$(find "$search_root" -mindepth 1 -maxdepth 1 -type d ! -name venv | head -1)"
        [ -n "$pkg_dir" ] || exit 1
        local pkg_name
        pkg_name="$(basename "$pkg_dir")"

        venv/bin/python -c "import sys; sys.path.insert(0, '$search_root'); import ${pkg_name}" >/dev/null 2>&1
    ); then
        echo -e "${GREEN}PASS${NC}"
        PASSED_COUNT=$((PASSED_COUNT + 1))
    else
        echo -e "${RED}FAIL${NC}"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi

    rm -rf "$sub_test_dir"
}

setup

echo "=========================================="
echo "    Running Test Suite for pyinit.        "
echo "=========================================="
echo ""

if [ ! -f "$PYINIT_SCRIPT" ]; then
    echo -e "${RED}Error: Cannot find '$PYINIT_SCRIPT'. Make sure pyinit is in the current directory.${NC}"
    exit 1
fi
chmod +x "$PYINIT_SCRIPT"

run_test "Help flag (-h)" "$PYINIT_SCRIPT" -h
run_test "Help flag (--help)" "$PYINIT_SCRIPT" --help

run_test "Default execution (current directory, src layout)" "$PYINIT_SCRIPT"

run_test "Named project (--name myproj)" "$PYINIT_SCRIPT" --name myproj

run_test "Flat layout option (--flat)" "$PYINIT_SCRIPT" --flat

run_test "Explicit path (--path)" bash -c "mkdir target_dir && $PYINIT_SCRIPT --path target_dir"

run_test "With valid dependencies (--deps)" "$PYINIT_SCRIPT" --deps "urllib3"

run_test "Full combination: --name + --path + --flat + --deps" bash -c \
    "mkdir target_dir && $PYINIT_SCRIPT --name myapp --path target_dir --flat --deps 'urllib3'"

assert_importable "Project name with hyphens (--name my-cool-app)" "my-cool-app"

assert_importable "Project name with uppercase (--name MyCoolApp)" "MyCoolApp"

assert_importable "Project name with underscores (--name my_cool_app)" "my_cool_app"

assert_importable "Project name with a space produces an importable package (regression test)" "my project"

assert_importable "Project name with a dot produces an importable package" "my.app"

assert_importable "Project name with a space, flat layout, produces an importable package" "my flat project" --flat

run_test "Path with spaces (--path 'dir with spaces')" bash -c \
    "mkdir 'dir with spaces' && $PYINIT_SCRIPT --path 'dir with spaces'"

run_failing_test "Invalid argument (--invalid-flag)" "$PYINIT_SCRIPT" --invalid-flag

run_failing_test "Empty --name value" "$PYINIT_SCRIPT" --name ""

run_failing_test "Flag-like --name value" "$PYINIT_SCRIPT" --name --path

run_failing_test "Flag-like --path value" "$PYINIT_SCRIPT" --path --deps

run_failing_test "Flag-like --deps value" "$PYINIT_SCRIPT" --deps --flat

run_failing_test "Duplicate --name flag" "$PYINIT_SCRIPT" --name proj1 --name proj2

run_failing_test "Duplicate --path flag" "$PYINIT_SCRIPT" --path . --path .

run_failing_test "Forbidden --name with path slash ('foo/bar')" "$PYINIT_SCRIPT" --name foo/bar

run_failing_test "Forbidden --name dot ('.')" "$PYINIT_SCRIPT" --name .

run_failing_test "Forbidden --name double dot ('..')" "$PYINIT_SCRIPT" --name ..

run_failing_test "Non-existent path directory" "$PYINIT_SCRIPT" --path /path/does/not/exist/12345

run_failing_test "Target project directory already exists" bash -c \
    "mkdir existing_proj && $PYINIT_SCRIPT --name existing_proj"

echo -n "Running: Soft failure on invalid dependency (--deps) ... "
SOFT_TEST_DIR="$TEST_DIR/soft_fail_test"
mkdir -p "$SOFT_TEST_DIR"
if (
    cd "$SOFT_TEST_DIR"
    "$PYINIT_SCRIPT" --name softapp --deps "nonexistent_package_xyz_999" >/dev/null 2>&1
    test -d softapp
    test -d softapp/venv
    test -f softapp/README.md
); then
    echo -e "${GREEN}PASS${NC}"
    PASSED_COUNT=$((PASSED_COUNT + 1))
else
    echo -e "${RED}FAIL${NC}"
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi
rm -rf "$SOFT_TEST_DIR"

echo -n "Running: Strict atomic rollback on critical failure ... "
ROLLBACK_TEST_DIR="$TEST_DIR/rollback_test"
mkdir -p "$ROLLBACK_TEST_DIR"
if (
    cd "$ROLLBACK_TEST_DIR"
    REAL_PYTHON="$(command -v python3)"

    mkdir -p fake_bin
    cat <<EOF > fake_bin/python3
#!/usr/bin/env bash
if [ "\${1:-}" = "-m" ] && [ "\${2:-}" = "venv" ]; then
    echo "Simulated venv creation crash" >&2
    exit 1
fi
exec "$REAL_PYTHON" "\$@"
EOF
    chmod +x fake_bin/python3

    PATH="$(pwd)/fake_bin:$PATH" "$PYINIT_SCRIPT" --name failed_proj >/dev/null 2>&1 || true

    test ! -e failed_proj
); then
    echo -e "${GREEN}PASS${NC}"
    PASSED_COUNT=$((PASSED_COUNT + 1))
else
    echo -e "${RED}FAIL${NC}"
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi
rm -rf "$ROLLBACK_TEST_DIR"

echo -n "Running: Bare invocation (no --name) never touches pre-existing files on failure ... "
BARE_SAFETY_DIR="$TEST_DIR/bare_safety_test"
mkdir -p "$BARE_SAFETY_DIR"
if (
    cd "$BARE_SAFETY_DIR"
    touch pre_existing_file.txt
    REAL_PYTHON="$(command -v python3)"

    mkdir -p fake_bin
    cat <<EOF > fake_bin/python3
#!/usr/bin/env bash
if [ "\${1:-}" = "-m" ] && [ "\${2:-}" = "venv" ]; then
    echo "Simulated venv creation crash" >&2
    exit 1
fi
exec "$REAL_PYTHON" "\$@"
EOF
    chmod +x fake_bin/python3

    PATH="$(pwd)/fake_bin:$PATH" "$PYINIT_SCRIPT" >/dev/null 2>&1 || true

    test -f pre_existing_file.txt
); then
    echo -e "${GREEN}PASS${NC}"
    PASSED_COUNT=$((PASSED_COUNT + 1))
else
    echo -e "${RED}FAIL${NC}"
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi
rm -rf "$BARE_SAFETY_DIR"

echo -n "Running: Structure check (src layout) ... "
STRUCT_DIR="$TEST_DIR/struct_src"
mkdir -p "$STRUCT_DIR"
if (
    cd "$STRUCT_DIR"
    "$PYINIT_SCRIPT" --name testproj >/dev/null 2>&1
    test -d testproj/src/testproj
    test -f testproj/src/testproj/__init__.py
    test -f testproj/src/testproj/main.py
    test -d testproj/venv
    test -f testproj/README.md
    test -f testproj/.gitignore
); then
    echo -e "${GREEN}PASS${NC}"
    PASSED_COUNT=$((PASSED_COUNT + 1))
else
    echo -e "${RED}FAIL${NC}"
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi
rm -rf "$STRUCT_DIR"

echo -n "Running: Structure check (flat layout) ... "
FLAT_STRUCT_DIR="$TEST_DIR/struct_flat"
mkdir -p "$FLAT_STRUCT_DIR"
if (
    cd "$FLAT_STRUCT_DIR"
    "$PYINIT_SCRIPT" --name testproj --flat >/dev/null 2>&1
    test -d testproj/testproj
    test -f testproj/testproj/__init__.py
    test -f testproj/testproj/main.py
    test -d testproj/venv
    test -f testproj/README.md
    test -f testproj/.gitignore
); then
    echo -e "${GREEN}PASS${NC}"
    PASSED_COUNT=$((PASSED_COUNT + 1))
else
    echo -e "${RED}FAIL${NC}"
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi
rm -rf "$FLAT_STRUCT_DIR"

echo ""
echo "=========================================="
echo "              TEST RESULTS                "
echo "=========================================="
echo -e "Passed: ${GREEN}${PASSED_COUNT}${NC}"
echo -e "Failed: ${RED}${FAILED_COUNT}${NC}"
echo "Total:  $((PASSED_COUNT + FAILED_COUNT))"

if [ "$FAILED_COUNT" -gt 0 ]; then
    exit 1
fi

exit 0
