BATS_MOCK_TMPDIR="${BATS_TEST_TMPDIR}"
BATS_MOCK_BINDIR="${BATS_MOCK_TMPDIR}/bin"

BATS_MOCK_REAL_mkdir=$(which mkdir)
export BATS_MOCK_REAL_mkdir
BATS_MOCK_REAL_ln=$(which ln)
export BATS_MOCK_REAL_ln
BATS_MOCK_REAL_touch=$(which touch)
export BATS_MOCK_REAL_touch
BATS_MOCK_REAL_rm=$(which rm)
export BATS_MOCK_REAL_rm

PATH="$BATS_MOCK_BINDIR:$PATH"

stub() {
  local program="$1"
  local prefix
  # shellcheck disable=SC2018,SC2019  # anything not A-Z0-9 will be _
  # the "\n" is necessary to avoid adding a trailing _ to the name
  # LC_ALL=C.UTF-8: see the matching comment in binstub.
  prefix="$(echo "$program" | LC_ALL=C.UTF-8 tr a-z A-Z | LC_ALL=C.UTF-8 tr -C "A-Z0-9\n" '_')"
  shift


  if [[ "$prefix" =~ ^[^A-Z_]+(.*)$ ]]; then
    # remove leading non A-Z_ characters to make a valid variable name
    prefix="${BASH_REMATCH[1]}"
  fi

  export "${prefix}_STUB_PLAN"="${BATS_MOCK_TMPDIR}/${program}-stub-plan"
  export "${prefix}_STUB_RUN"="${BATS_MOCK_TMPDIR}/${program}-stub-run"
  export "${prefix}_STUB_END"=
  # Reset on every stub call -- re-stubbing a program plainly after
  # stub_repeated must not leave the flag stuck on from before.
  export "${prefix}_STUB_NOINDEX"=

  "$BATS_MOCK_REAL_mkdir" -p "${BATS_MOCK_BINDIR}"
  "$BATS_MOCK_REAL_ln" -sf "${BASH_SOURCE[0]%stub.bash}binstub" "${BATS_MOCK_BINDIR}/${program}"

  "$BATS_MOCK_REAL_touch" "${BATS_MOCK_TMPDIR}/${program}-stub-plan"
  for arg in "$@"; do printf "%s\n" "$arg" >> "${BATS_MOCK_TMPDIR}/${program}-stub-plan"; done
}

stub_repeated() {
  local program="$1"
  local prefix
  # shellcheck disable=SC2018,SC2019  # anything not A-Z0-9 will be _
  # the "\n" is necessary to avoid adding a trailing _ to the name
  # LC_ALL=C.UTF-8: see the matching comment in binstub.
  prefix="$(echo "$program" | LC_ALL=C.UTF-8 tr a-z A-Z | LC_ALL=C.UTF-8 tr -C "A-Z0-9\n" '_')"

  if [[ "$prefix" =~ ^[^A-Z_]+(.*)$ ]]; then
    # remove leading non A-Z_ characters to make a valid variable name
    prefix="${BASH_REMATCH[1]}"
  fi

  # Only one plan line is supported: binstub always re-checks index 1
  # against it, so a second line would be dead (never reached).
  stub "$@"
  export "${prefix}_STUB_NOINDEX"=1
}

unstub() {
  local allow_missing=0
  local force=0
  while [ "$1" == "--allow-missing" ] || [ "$1" == "--force" ]; do
    case "$1" in
      --allow-missing) allow_missing=1 ;;
      --force) force=1 ;;
    esac
    shift
  done
  local program="$1"
  local path="${BATS_MOCK_BINDIR}/${program}"
  local prefix
  # shellcheck disable=SC2018,SC2019  # anything not A-Z0-9 will be _
  # the "\n" is necessary to avoid adding a trailing _ to the name
  # LC_ALL=C.UTF-8: see the matching comment in binstub.
  prefix="$(echo "${program}" | LC_ALL=C.UTF-8 tr a-z A-Z | LC_ALL=C.UTF-8 tr -C "A-Z0-9\n" '_')"

  if [[ "$prefix" =~ ^[^A-Z_]+(.*)$ ]]; then
    # remove leading non A-Z_ characters to make a valid variable name
    prefix="${BASH_REMATCH[1]}"
  fi

  export "${prefix}_STUB_END"=1

  local STATUS=0
  if [ $force -eq 1 ]; then
    : # --force: skips verification entirely -- also forgives an
      # unfulfilled plan (unlike --allow-missing); binstub never runs,
      # so no debug output either.
  elif [ -f "$path" ]; then
    "$path" || STATUS="$?"
  elif [ $allow_missing -eq 0 ]; then
    echo "$program is not stubbed" >&2
    STATUS=1
  fi

  "$BATS_MOCK_REAL_rm" -f "$path"
  "$BATS_MOCK_REAL_rm" -f "${BATS_MOCK_TMPDIR}/${program}-stub-plan" "${BATS_MOCK_TMPDIR}/${program}-stub-run"
  return "$STATUS"
}
