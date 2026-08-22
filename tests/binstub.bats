#!/usr/bin/env bats

load '../stub'

function teardown() {
    # Just clean up
    unstub --allow-missing mycommand
}

# Uncomment to enable stub debug output:
# export MYCOMMAND_STUB_DEBUG=/dev/tty

@test "Stub a single command with basic arguments" {
  stub mycommand "llamas : echo running llamas"

  run mycommand llamas

  [ "$status" -eq 0 ]
  [[ "$output" == *"running llamas"* ]]

  unstub mycommand
}

@test "Stub a command with multiple invocations" {
  stub mycommand \
    "llamas : echo running llamas" \
    "alpacas : echo running alpacas"

  run bash -c "mycommand llamas && mycommand alpacas"

  [ "$status" -eq 0 ]
  [[ "$output" == *"running llamas"* ]]
  [[ "$output" == *"running alpacas"* ]]

  unstub mycommand
}


@test "Invoke a stub more than expected" {
  stub mycommand "llamas : echo running llamas"

  run bash -c "mycommand llamas"
  [ "$status" -eq 0 ]
  [ "$output" == "running llamas" ]

  # More executions -> return failure
  run bash -c "mycommand llamas"
  [ "$status" -eq 1 ]
  [ "$output" == "" ]

  # and they also make unstubbing fail to fail the whole command
  run unstub mycommand
  [ "$status" -eq 1 ]
  [[ "$output" == "" ]]
}

@test "Stub a single command with quoted strings" {
  stub mycommand "llamas '' 'always llamas' : echo running llamas"

  run mycommand llamas '' always\ llamas

  [ "$status" -eq 0 ]
  [[ "$output" == *"running llamas"* ]]

  unstub mycommand
}

@test "Return status of passed stub" {
  stub myCommand \
    " : exit 1" \
    " : exit 42" \
    " : exit 0"
  run myCommand
  [ "$status" -eq 1 ]
  [ "$output" == "" ]
  run myCommand
  [ "$status" -eq 42 ]
  [ "$output" == "" ]
  run myCommand
  [ "$status" -eq 0 ]
  [ "$output" == "" ]
  unstub myCommand
}

@test "Succeed for empty stubbed command" {
  stub mycommand
  # mycommand not called
  run unstub mycommand
  [ "$status" -eq 0 ]
  [ "$output" == "" ]
}

@test "Fail if empty stubbed command called" {
  stub mycommand
  # force an execution outside of run and never fail
  mycommand --help || true # Don't fail here
  run unstub mycommand
  [ "$status" -eq 1 ]
  [ "$output" == "" ]
}

@test "Fail if called out of sequence" {
  stub mycommand \
    "foo : echo 'OK'" \
    "bar : echo '1K'" \
    "baz : echo '2K'"
  run bash -c "mycommand foo; mycommand baz; mycommand bar"
  [ "$status" -eq 1 ]
  [ "$output" == "OK" ]
  run unstub mycommand
  [ "$status" -eq 1 ]
  [ "$output" == "" ]
}

@test "Check stdin" {
  file="$(mktemp "${BATS_TEST_TMPDIR}/output.XXXXXXXX")"
  stub curl \
    "foo : cat > '${file}'; echo 'mock output'"
  run bash -c "echo 'Some input' | curl foo"
  [ "$status" -eq 0 ]
  [ "$output" == "mock output" ]
  input="$(cat "$file")"
  [ "$input" == "Some input" ]
  rm "$file"
  unstub curl
}

@test "Error with --allow-missing" {
  # Case 1: Double unstub
  stub mycommand "foo : echo 'Bar'"
  run mycommand foo
  [ "$status" -eq 0 ]
  run unstub mycommand
  [ "$status" -eq 0 ]
  [ "$output" == "" ]
  run unstub mycommand
  [ "$status" -eq 1 ]
  [ "$output" == "mycommand is not stubbed" ]
  # With --allow-missing
  stub mycommand "foo : echo 'Bar'"
  run mycommand foo
  [ "$status" -eq 0 ]
  # First removes
  run unstub --allow-missing mycommand
  [ "$status" -eq 0 ]
  [ "$output" == "" ]
  # Then errors with regular
  run unstub mycommand
  [ "$status" -eq 1 ]
  [ "$output" == "mycommand is not stubbed" ]
  # But not with param
  run unstub --allow-missing mycommand
  [ "$status" -eq 0 ]
  [ "$output" == "" ]

  # Case 2: Unstub non-stubbed command
  run unstub non_stubbed_command
  [ "$status" -eq 1 ]
  [ "$output" == "non_stubbed_command is not stubbed" ]
  run unstub --allow-missing non_stubbed_command2
  [ "$status" -eq 0 ]
  [ "$output" == "" ]
}

@test "--force skips plan verification entirely, unlike --allow-missing" {
  # --allow-missing does NOT forgive an unfulfilled plan on a stub that
  # DOES exist (only a never-created one) -- confirmed before showing
  # what --force adds.
  stub mycommand "foo : echo OK"
  run mycommand bar # mismatch: plan expects "foo"
  [ "$status" -eq 1 ]
  run unstub --allow-missing mycommand
  [ "$status" -eq 1 ]

  # --force does forgive it.
  stub mycommand "foo : echo OK"
  run mycommand bar
  [ "$status" -eq 1 ]
  run unstub --force mycommand
  [ "$status" -eq 0 ]
  [ "$output" == "" ]
}

@test "--force also covers a never-invoked stub and a never-stubbed program" {
  stub mycommand "foo : echo OK"
  run unstub --force mycommand
  [ "$status" -eq 0 ]

  run unstub --force totally_unknown_command
  [ "$status" -eq 0 ]
  [ "$output" == "" ]
}

@test "--force and --allow-missing compose in either order" {
  run unstub --force --allow-missing totally_unknown_command
  [ "$status" -eq 0 ]
  run unstub --allow-missing --force totally_unknown_command
  [ "$status" -eq 0 ]
}

@test "--force still cleans up the stub's symlink and state files" {
  stub mycommand "foo : echo OK"
  run mycommand bar
  run unstub --force mycommand
  [ "$status" -eq 0 ]
  [ ! -e "${BATS_MOCK_BINDIR}/mycommand" ]
  [ ! -e "${BATS_MOCK_TMPDIR}/mycommand-stub-plan" ]
  [ ! -e "${BATS_MOCK_TMPDIR}/mycommand-stub-run" ]
}

@test "'is not stubbed' message goes to stderr, not stdout" {
  # `run` merges stdout/stderr, so it can't tell them apart -- bypass it
  # and check the streams directly.
  unstub non_stubbed_command 1>"${BATS_TEST_TMPDIR}/out" 2>"${BATS_TEST_TMPDIR}/err" || true
  [ ! -s "${BATS_TEST_TMPDIR}/out" ]
  grep -q "non_stubbed_command is not stubbed" "${BATS_TEST_TMPDIR}/err"
}

@test "Using * as parameter matches any parameter" {
  # * matches any param
  stub mycommand '* : echo OK'
  run mycommand foo
  [ "$status" -eq 0 ]
  [ "$output" == "OK" ]
  unstub mycommand

  # Also works in any position
  stub mycommand 'first second * : echo OK'
  run mycommand first second foo
  [ "$status" -eq 0 ]
  [ "$output" == "OK" ]
  unstub mycommand

  stub mycommand 'first * last : echo OK'
  run mycommand first foo last
  [ "$status" -eq 0 ]
  [ "$output" == "OK" ]
  unstub mycommand

  stub mycommand '* second last : echo OK'
  run mycommand foo second last
  [ "$status" -eq 0 ]
  [ "$output" == "OK" ]
  unstub mycommand

  # Also matches literal *
  stub mycommand '* : echo OK'
  run mycommand '*'
  [ "$status" -eq 0 ]
  [ "$output" == "OK" ]
  unstub mycommand

  # in double quotes it does not needs to be escaped
  stub mycommand "* : echo NOT ESCAPED"
  run mycommand 'whatever'
  [ "$status" -eq 0 ]
  [ "$output" == "NOT ESCAPED" ]
  unstub mycommand

  # ... but it can and still works
  stub mycommand "\* : echo NOT ESCAPED"
  run mycommand 'whatever'
  [ "$status" -eq 0 ]
  [ "$output" == "NOT ESCAPED" ]
  unstub mycommand

}

@test "Match parameters with whitespace" {
  # Single quotes
  stub mycommand "'first arg' 'second arg' : echo OK"
  run mycommand "first arg" "second arg"
  [ "$status" -eq 0 ]
  [ "$output" == "OK" ]
  unstub mycommand
  # Double quotes
  stub mycommand '"first arg" "second arg" : echo OK'
  run mycommand "first arg" "second arg"
  [ "$status" -eq 0 ]
  [ "$output" == "OK" ]
  unstub mycommand
}

@test "Match parameter with embedded command line" {
  stub mycommand "-c 'echo \"Hello \$USER\"' : echo OK"
  # shellcheck disable=SC2016  # this is on purpose
  run mycommand -c 'echo "Hello $USER"'
  [ "$status" -eq 0 ]
  [ "$output" == "OK" ]
  unstub mycommand
}

@test "Allow partial matches" {
  skip
  stub mycommand '/foo/bar/* : echo OK'
  run mycommand "/foo/bar/myfile"
  [ "$status" -eq 0 ]
  [ "$output" == "OK" ]
  unstub mycommand
  # But reject others
  stub mycommand '/foo/bar/* : echo OK'
  run mycommand "/foo/baz/myfile"
  [ "$status" -eq 1 ]
  [ "$output" == "" ]
  run unstub mycommand
  [ "$status" -eq 1 ]
}

@test "Allow incremental stubbing" {
  stub mycommand "foo : echo OK"
  stub mycommand "bar : echo 1K"
  stub mycommand "baz : echo 2K"
  run bash -c 'mycommand foo && mycommand bar && mycommand baz'
  [ "$status" -eq 0 ]
  expected='OK
1K
2K'
  [ "$output" = "$expected" ]
}

@test "Stubbing still works when some util binaries are stubbed" {
  stub rm
  stub mkdir
  stub ln
  stub touch
  stub mycommand " : echo OK"
  run mycommand
  [ "$status" -eq 0 ]
  [ "$output" == "OK" ]
  unstub rm
  unstub mkdir
  unstub ln
  unstub touch
  unstub mycommand
}

@test "Allow any argument by omitting the args and colon" {
  # 0 args
  stub mycommand "echo OK"
  run mycommand
  [ "$status" -eq 0 ]
  [ "$output" == "OK" ]
  unstub mycommand
  # 1 arg
  stub mycommand "echo OK"
  run mycommand foo
  [ "$status" -eq 0 ]
  [ "$output" == "OK" ]
  unstub mycommand
  # 2 args
  stub mycommand "echo OK"
  run mycommand foo bar
  [ "$status" -eq 0 ]
  [ "$output" == "OK" ]
  unstub mycommand
}

@test "Allow any argument by starting with double colon" {
  # This allows including the colon separator in the command
  stub mycommand "::echo ' includes : colon with spaces'"
  run mycommand foo bar
  [ "$status" -eq 0 ]
  [ "$output" == ' includes : colon with spaces' ]
  unstub mycommand
}

@test "Assume no arguments when starting with a colon and space" {
  stub mycommand ": echo OK"
  run mycommand
  [ "$status" -eq 0 ]
  [ "$output" == 'OK' ]
  unstub mycommand
  stub mycommand ": echo OK"
  run mycommand foo
  [ "$status" -eq 1 ]
  [ "$output" == '' ]
  run unstub mycommand
  [ "$status" -eq 1 ]
}

@test "Call stub with more arguments than expected" {
  stub mycommand "llamas : echo running llamas"

  run mycommand llamas extra

  [ "$status" -eq 1 ]
  [ "$output" == '' ]

  run unstub mycommand
  [ "$status" -eq 1 ]
}

@test "Call stub with fewer arguments than expected fails, unless the missing ones are *" {
  # A missing arg at a literal-pattern position never matches (empty !=
  # pattern).
  stub mycommand "foo bar : echo OK"
  run mycommand foo
  [ "$status" -eq 1 ]
  [ "$output" == '' ]
  run unstub mycommand
  [ "$status" -eq 1 ]

  # But * never inspects the argument at all -- an upper bound on count,
  # not a presence requirement.
  stub mycommand "foo * : echo OK"
  run mycommand foo
  [ "$status" -eq 0 ]
  [ "$output" == 'OK' ]
  unstub mycommand
}