#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
# Each @test is its own subshell (bats' isolation model); shellcheck
# doesn't know the STUB_DEBUG exports are deliberately test-local.

load '../stub'

function teardown() {
  # Just clean up
  unstub --allow-missing mycommand
}

@test "STUB_DEBUG as a numeric fd logs the invocation lifecycle" {
  # Use fd 9, not fd 3: bats-core reserves fd 3 for its own TAP output --
  # opening/closing it ourselves breaks every later test with "Bad file
  # descriptor". Any other already-open fd works the same for STUB_DEBUG.
  exec 9>"${BATS_TEST_TMPDIR}/debug.log"
  export MYCOMMAND_STUB_DEBUG=9

  stub mycommand "foo : echo OK"
  run mycommand foo
  [ "$status" -eq 0 ]
  [ "$output" == "OK" ]
  unstub mycommand

  exec 9>&-
  run cat "${BATS_TEST_TMPDIR}/debug.log"
  [[ "$output" == *"got mycommand foo"* ]]
  [[ "$output" == *"arguments [1]"* ]]
  [[ "$output" == *"patterns  [1]"* ]]
  [[ "$output" == *"running echo OK"* ]]
  [[ "$output" == *"command result was 0"* ]]
  [[ "$output" == *"unstubbing"* ]]
  [[ "$output" == *"result 0"* ]]
}

@test "STUB_DEBUG as a file path only ever shows the LAST debug line" {
  # `>&word` for a non-numeric word is `> word 2>&1` (truncating, not
  # appending). debug() re-triggers this every call, so file-path mode
  # only ever shows the LAST debug line, unlike fd mode.
  export MYCOMMAND_STUB_DEBUG="${BATS_TEST_TMPDIR}/debug.log"

  stub mycommand "foo : echo OK"
  run mycommand foo
  [ "$status" -eq 0 ]
  run unstub mycommand
  [ "$status" -eq 0 ]

  run cat "${BATS_TEST_TMPDIR}/debug.log"
  [ "$output" == "bats-mock(mycommand): unstubbing" ]
}

@test "STUB_DEBUG logs a mismatch reason when the plan does not match" {
  exec 9>"${BATS_TEST_TMPDIR}/debug.log"
  export MYCOMMAND_STUB_DEBUG=9

  stub mycommand "foo : echo OK"
  run mycommand bar
  [ "$status" -eq 1 ]
  # --allow-missing wouldn't rescue this: it only forgives "never stubbed",
  # not a genuine plan mismatch.
  run unstub mycommand
  [ "$status" -eq 1 ]

  exec 9>&-
  run cat "${BATS_TEST_TMPDIR}/debug.log"
  [[ "$output" == *"match failed at idx 0"* ]]
}

@test "STUB_DEBUG logs when no plan line was found for the call" {
  exec 9>"${BATS_TEST_TMPDIR}/debug.log"
  export MYCOMMAND_STUB_DEBUG=9

  stub mycommand
  mycommand --help || true
  run unstub mycommand
  [ "$status" -eq 1 ]

  exec 9>&-
  run cat "${BATS_TEST_TMPDIR}/debug.log"
  [[ "$output" == *"no plan row found"* ]]
}

@test "without STUB_DEBUG, unstub on a never-invoked stub succeeds" {
  # Baseline for the next test: same scenario, without STUB_DEBUG.
  stub mycommand
  run unstub mycommand
  [ "$status" -eq 0 ]
}

@test "with STUB_DEBUG, unstub on a never-invoked stub FAILS instead" {
  # Surprising, pinned explicitly: binstub's END-mode check
  # `[ ! -f ... ] && [ -n STUB_DEBUG ]` is itself debug-gated, so this
  # exact scenario flips from pass to fail with debug on.
  #
  # fd 9 must stay open even though unused below: debug("unstubbing")
  # writes to it before the "wasn't run" check runs.
  exec 9>"${BATS_TEST_TMPDIR}/debug.log"
  export MYCOMMAND_STUB_DEBUG=9

  stub mycommand
  # This message is a plain echo, not routed through debug() -- it lands
  # on stdout (visible via `run`), not the STUB_DEBUG fd.
  run unstub mycommand
  [ "$status" -eq 1 ]
  [[ "$output" == *"The stub for mycommand wasn't run"* ]]

  exec 9>&-
}
