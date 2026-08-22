#!/usr/bin/env bats

load '../stub'

my_function() {
  echo "called with: $*"
  return 3
}
export -f my_function

function teardown() {
  unstub --allow-missing mycommand
}

@test "an exported function works as a stub's command" {
  stub mycommand "foo : my_function"
  run mycommand foo
  [ "$status" -eq 3 ]
  [ "$output" == "called with: " ]
}

@test "the function receives the actual invocation args, if forwarded with \$@" {
  # "$@" must stay unexpanded until binstub evals the plan command (same
  # pattern as $1/$2/inspect_args elsewhere).
  stub mycommand "my_function \"\$@\"" # no colon: accept any number of args
  run mycommand foo bar
  [ "$status" -eq 3 ]
  [ "$output" == "called with: foo bar" ]
}

@test "a NON-exported function does NOT work as a stub's command" {
  # Real requirement upstream's README doesn't mention: the stubbed
  # program runs as a separate process (via the PATH symlink), not
  # sourced into the caller's shell -- only exported functions are
  # visible, same as inspect_args vs. a nested bash -c.
  not_exported_function() { echo "should not run"; }

  stub mycommand "foo : not_exported_function"
  run mycommand foo
  [ "$status" -eq 127 ] # "command not found"
  [[ "$output" == *"not_exported_function: command not found"* ]]
}
