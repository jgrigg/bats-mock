#!/usr/bin/env bats

load '../stub'

function teardown() {
  unstub --allow-missing mycommand
}

@test "stub_repeated matches zero invocations" {
  stub_repeated mycommand "llamas : echo running llamas"

  unstub mycommand
}

@test "stub_repeated matches a single invocation" {
  stub_repeated mycommand "llamas : echo running llamas"

  run mycommand llamas
  [ "$status" -eq 0 ]
  [[ "$output" == *"running llamas"* ]]

  unstub mycommand
}

@test "stub_repeated matches any number of invocations" {
  stub_repeated mycommand "llamas : echo running llamas"

  run bash -c "mycommand llamas && mycommand llamas && mycommand llamas"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l)" -eq 3 ]

  unstub mycommand
}

@test "stub_repeated still fails a call whose arguments don't match" {
  stub_repeated mycommand "llamas : echo running llamas"

  run mycommand alpacas
  [ "$status" -eq 1 ]

  run unstub mycommand
  [ "$status" -eq 1 ]
}

@test "stub_repeated works with unstub --force" {
  stub_repeated mycommand "llamas : echo running llamas"

  run mycommand llamas

  unstub --force mycommand
}

@test "a program re-stubbed plainly after stub_repeated does not stay repeated" {
  stub_repeated mycommand "llamas : echo running llamas"
  run mycommand llamas
  unstub mycommand

  stub mycommand "llamas : echo running llamas"
  run mycommand llamas
  run mycommand llamas
  [ "$status" -eq 1 ]
  run unstub mycommand
  [ "$status" -eq 1 ]
}
