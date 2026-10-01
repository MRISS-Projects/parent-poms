#!/bin/sh
# Tests for verify-staged-site.sh. Run: sh verify-staged-site.test.sh
set -u

SCRIPT="$(dirname "$0")/verify-staged-site.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
n=0

# new_stage: a fresh staged root, laid out the way site:deploy leaves /tmp/sites.
new_stage() {
  n=$((n + 1))
  stage="$TMP/$n"
  mkdir -p "$stage"
}

# module <path relative to the stage> [noindex]: a module site. Every module site has the
# project-info.html that parent-poms' reporting gives it; "noindex" leaves index.html out.
module() {
  mkdir -p "$stage/$1"
  : > "$stage/$1/project-info.html"
  if [ "${2:-}" != "noindex" ]; then
    : > "$stage/$1/index.html"
  fi
}

# report <path relative to the stage>: a report directory inside a module site. It has
# pages of its own and no project-info.html, so it is not a module.
report() {
  mkdir -p "$stage/$1"
  : > "$stage/$1/$2"
}

# expect <description> <expected exit> [<text the output must contain>]...
expect() {
  description="$1"; expected="$2"; shift 2
  output="$(sh "$SCRIPT" "$stage" 2>&1)"
  actual=$?
  if [ "$actual" -ne "$expected" ]; then
    echo "FAIL - $description (expected exit $expected, got $actual)"
    failures=$((failures + 1))
    return
  fi
  for wanted in "$@"; do
    case "$output" in
      *"$wanted"*) ;;
      *)
        echo "FAIL - $description (output lacks '$wanted')"
        failures=$((failures + 1))
        return
        ;;
    esac
  done
  echo "ok   - $description"
}

# refuse <description> <text the output must NOT contain>: for a run expected to fail.
refuse() {
  description="$1"; unwanted="$2"
  output="$(sh "$SCRIPT" "$stage" 2>&1)"
  case "$output" in
    *"$unwanted"*)
      echo "FAIL - $description (output contains '$unwanted')"
      failures=$((failures + 1))
      ;;
    *) echo "ok   - $description" ;;
  esac
}

new_stage
module rcs/products/dsh
module rcs/products/dsh/dsh-data
module rcs/products/dsh/dsh-doc-analyser
module rcs/products/dsh/dsh-doc-analyser/dsh-keyword-extractor
expect "a stage where every module site has an index.html passes" 0 "4 module site(s)"

new_stage
module rcs/products/dsh noindex
module rcs/products/dsh/dsh-data
expect "a root module with no index.html fails and is named" 1 "rcs/products/dsh"
refuse "a module that has its index.html is not named" "rcs/products/dsh/dsh-data"

new_stage
module rcs/products/dsh
module rcs/products/dsh/dsh-doc-analyser
module rcs/products/dsh/dsh-doc-analyser/dsh-keyword-extractor noindex
expect "a nested module with no index.html fails and is named" 1 \
  "rcs/products/dsh/dsh-doc-analyser/dsh-keyword-extractor"

# MRISS-Projects/dsh#90: every module at once.
new_stage
module rcs/products/dsh noindex
module rcs/products/dsh/dsh-data noindex
module rcs/products/dsh/dsh-rest-api noindex
expect "every module with no index.html is named, not just the first" 1 \
  "rcs/products/dsh/dsh-data" "rcs/products/dsh/dsh-rest-api" "3 of 3"

# Report directories carry an index.html of their own, or none; neither makes them modules.
new_stage
module rcs/products/dsh
report rcs/products/dsh/jacoco index.html
report rcs/products/dsh/css site.css
report rcs/products/dsh/xref overview-summary.html
expect "a report directory without project-info.html is not a module" 0 "1 module site(s)"

new_stage
module rcs/products/dsh noindex
report rcs/products/dsh/apidocs index.html
expect "a report directory's index.html does not stand in for the module's" 1 "rcs/products/dsh"

new_stage
module "rcs/products/my product"
module "rcs/products/my product/a module" noindex
expect "a path with a space is handled and named whole" 1 "rcs/products/my product/a module"

# An empty stage must not pass: a run that staged nothing would otherwise be verified.
new_stage
expect "a stage with no module site at all fails" 1 "no module site"

new_stage
report rcs/products/dsh index.html
expect "a stage with pages but no project-info.html fails" 1 "no module site"

n=$((n + 1)); stage="$TMP/$n-missing"
expect "a stage directory that does not exist fails" 1 "does not exist"

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed."
  exit 1
fi
echo "All tests passed."
