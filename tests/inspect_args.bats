#!/usr/bin/env bats
# shellcheck disable=SC2016
# Single-quoted plan lines below intentionally don't expand $(...) at
# definition time -- eval'd later inside binstub (same as tests/binstub.bats's
# "embedded command line" test).

load '../stub'

function teardown() {
  unstub --allow-missing mycommand
}

@test "inspect_args prints plain args separated by spaces" {
  stub mycommand 'echo $(inspect_args "$@")'
  run mycommand foo bar baz
  [ "$status" -eq 0 ]
  [ "$output" == "foo bar baz" ]
}

@test "inspect_args double-quotes an arg containing a space, escaping inner quotes" {
  stub mycommand 'echo $(inspect_args "$@")'
  run mycommand 'hello world' 'say "hi"'
  [ "$status" -eq 0 ]
  [ "$output" == '"hello world" "say \"hi\""' ]
}

@test "inspect_args single-quotes an arg containing a quote but no space" {
  # Only reachable when the arg has a quote but no space -- an arg with
  # both takes the double-quote branch above (matches upstream exactly).
  stub mycommand 'echo $(inspect_args "$@")'
  run mycommand 'say"hi"'
  [ "$status" -eq 0 ]
  [ "$output" == "'say\"hi\"'" ]
}

@test "inspect_args passes through an arg with neither a space nor a quote" {
  stub mycommand 'echo $(inspect_args "$@")'
  run mycommand "it's-fine"
  [ "$status" -eq 0 ]
  [ "$output" == "it's-fine" ]
}

@test "inspect_args on zero args prints nothing" {
  stub mycommand 'echo -n "[$(inspect_args "$@")]"'
  run mycommand
  [ "$status" -eq 0 ]
  [ "$output" == "[]" ]
}

@test "inspect_args can be called with a subset of the arguments" {
  # Ordinary function call, not tied to the plan's own "$@" -- whatever
  # you pass is what gets formatted.
  stub mycommand 'echo $(inspect_args "$1")'
  run mycommand foo bar
  [ "$status" -eq 0 ]
  [ "$output" == "foo" ]
}

@test "inspect_args is a shell function, not exported -- invisible to a nested bash -c" {
  # Inherited by binstub's own eval subshell (function inheritance, no
  # export needed), but invisible to a genuinely separate nested bash -c.
  stub mycommand 'bash -c "inspect_args"'
  run mycommand foo
  [ "$status" -eq 127 ] # "command not found"
  [[ "$output" == *"inspect_args: command not found"* ]]
}
