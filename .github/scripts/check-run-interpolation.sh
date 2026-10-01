#!/bin/sh
# Fail if a run: body in a workflow or composite action interpolates an expression.
#
# MRISS-Projects/parent-poms#81: an expression inside a run: body is substituted into the
# script TEXT before bash parses it, so a caller-supplied input holding shell metacharacters
# becomes code - and a `#` in it can swallow the rest of a command, leaving a green step
# that did nothing. Every value a script needs goes through the step's env: and is read as
# a quoted variable; inside a composite action, $GITHUB_ACTION_PATH replaces the
# action_path expression. The rule is absolute, with no allowlist to keep current.
#
# Usage: check-run-interpolation.sh [<repository root>]   (default: the current directory)
set -eu

ROOT="${1:-.}"

# GitHub accepts both extensions, for workflows and for an action's metadata file.
set --
for f in "$ROOT"/.github/workflows/*.yml "$ROOT"/.github/workflows/*.yaml \
         "$ROOT"/.github/actions/*/action.yml "$ROOT"/.github/actions/*/action.yaml; do
  if [ -f "$f" ]; then
    set -- "$@" "$f"
  fi
done

if [ "$#" -eq 0 ]; then
  echo "::error::check-run-interpolation: no workflow or action file found under $ROOT/.github"
  exit 2
fi

# A body is whatever a run: key holds: the rest of its own line, and every following line
# indented deeper than the key. That one rule covers a block scalar under any header
# (`|`, `>-`, `|2`, `| # comment`), a script that starts on the next line, and a plain
# scalar continued over several lines, with no list of header shapes to fall out of date -
# matching only a bare `|` or `>` is how PR #100's first version of this check let the
# others through.
#
# The one run: key that is not a script is the mapping under `defaults:`, which holds
# settings such as shell and working-directory. It is recognised by the key on the line
# before it, and its lines are skipped rather than scanned.
bad=$(awk '
  function indent(s) { match(s, /^ */); return RLENGTH }
  function report() { if ($0 ~ /\$\{\{/) print FILENAME ":" FNR ": " $0 }
  FNR == 1 { inrun = 0; prev = "" }
  {
    if (inrun) {
      if ($0 ~ /^ *$/ || indent($0) > runind) {
        if (scan) report()
        if ($0 !~ /^ *$/) prev = $0
        next
      }
      inrun = 0
    }
    if ($0 ~ /^ *(- )?run:( |$)/) {
      line = $0; sub(/- /, "  ", line); runind = indent(line); inrun = 1
      scan = !(prev ~ /^ *defaults: *(#.*)?$/ && indent(prev) < runind)
      if (scan) report()
    }
    if ($0 !~ /^ *(#.*)?$/) prev = $0
  }
' "$@")

if [ -n "$bad" ]; then
  echo "::error::a run: body interpolates an expression (see #81):"
  echo "$bad"
  echo "Move each value into the step's env: and read it as a quoted variable."
  exit 1
fi
echo "No run: body interpolates an expression."
