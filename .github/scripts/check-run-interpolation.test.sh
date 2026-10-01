#!/bin/sh
# Tests for check-run-interpolation.sh. Run: sh check-run-interpolation.test.sh
set -u

SCRIPT="$(dirname "$0")/check-run-interpolation.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
n=0

# The expression every failing case plants. Built here so that no line of this file holds
# the sequence literally inside something a shell would expand.
X='${{ inputs.x }}'

# new_root: a fresh repository root holding one clean workflow, so that a case which plants
# nothing else still has a file to scan.
new_root() {
  n=$((n + 1))
  root="$TMP/$n"
  mkdir -p "$root/.github/workflows" "$root/.github/actions/a"
  printf 'jobs:\n  j:\n    steps:\n      - name: clean\n        run: echo ok\n' \
    > "$root/.github/workflows/clean.yml"
}

# expect_exit <description> <expected exit>: runs the script against the current $root.
expect_exit() {
  description="$1"; expected="$2"
  sh "$SCRIPT" "$root" >/dev/null 2>&1
  actual=$?
  if [ "$actual" -eq "$expected" ]; then
    echo "ok   - $description"
  else
    echo "FAIL - $description (expected exit $expected, got $actual)"
    failures=$((failures + 1))
  fi
}

# workflow <file name> <step lines>: writes a workflow whose only step is the given lines.
workflow() {
  printf 'jobs:\n  j:\n    steps:\n%s\n' "$2" > "$root/.github/workflows/$1"
}

new_root
expect_exit "a tree with no expression in any run: body passes" 0

new_root
workflow w.yml "      - name: s
        env:
          V: $X
        if: $X
        with:
          v: $X
        run: |
          echo \"\$V\""
expect_exit "an expression in env:, if: and with: passes" 0

new_root
workflow w.yml "      - name: s
        run: |
          echo $X"
expect_exit "a plain block body fails" 1

new_root
workflow w.yml "      - name: s
        run: echo $X"
expect_exit "a single-line body fails" 1

new_root
workflow w.yml "      - run: |
          echo $X"
expect_exit "a body whose run: is the step's first key fails" 1

# PR #100 review: every legal block-scalar header starts a body, not just a bare | or >.
new_root
workflow w.yml "      - name: s
        run: | # explanation
          echo $X"
expect_exit "a block header followed by a comment fails" 1

new_root
workflow w.yml "      - name: s
        run: |2
          echo $X"
expect_exit "a block header with an indentation indicator fails" 1

new_root
workflow w.yml "      - name: s
        run: >-2
          echo $X"
expect_exit "a folded header with chomping and indentation indicators fails" 1

new_root
workflow w.yml "      - name: s
        run:
          echo $X"
expect_exit "a body that starts on the line after run: fails" 1

new_root
workflow w.yml "      - name: s
        run: echo start
          $X"
expect_exit "a plain scalar continued on a second line fails" 1

new_root
workflow w.yml "      - name: s
        run: |
          echo one

          echo $X"
expect_exit "a body is followed across a blank line" 1

new_root
workflow w.yml "      - name: first
        run: |
          echo ok
      - name: second
        env:
          V: $X
        run: echo \"\$V\""
expect_exit "a body ends where the indentation returns to the step" 0

# PR #100 review: GitHub accepts .yaml as well as .yml, for workflows and for actions.
new_root
workflow other.yaml "      - name: s
        run: |
          echo $X"
expect_exit "a workflow with a .yaml extension is scanned" 1

new_root
printf 'runs:\n  using: composite\n  steps:\n    - shell: bash\n      run: |\n        echo %s\n' "$X" \
  > "$root/.github/actions/a/action.yml"
expect_exit "a composite action's action.yml is scanned" 1

new_root
printf 'runs:\n  using: composite\n  steps:\n    - shell: bash\n      run: |\n        echo %s\n' "$X" \
  > "$root/.github/actions/a/action.yaml"
expect_exit "a composite action's action.yaml is scanned" 1

# defaults.run holds settings, not a script.
new_root
printf 'defaults:\n  run:\n    working-directory: %s\njobs:\n  j:\n    steps:\n      - run: echo ok\n' "$X" \
  > "$root/.github/workflows/w.yml"
expect_exit "an expression under defaults.run passes" 0

new_root
printf 'jobs:\n  j:\n    defaults:\n      run:\n        working-directory: %s\n    steps:\n      - run: echo %s\n' "$X" "$X" \
  > "$root/.github/workflows/w.yml"
expect_exit "a step after a job-level defaults.run is still scanned" 1

n=$((n + 1)); root="$TMP/$n"; mkdir -p "$root"
expect_exit "a root with no workflow or action file is an error, not a pass" 2

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed."
  exit 1
fi
echo "All tests passed."
