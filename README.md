# bats-mock

Mocking/stubbing library for BATS (Bash Automated Testing System)

A maintained fork of https://github.com/jasonkarns/bats-mock, which is dormant.

There are great things happening in the `bats` ecosystem! Anyone actively using it should be installing from [bats-core]: https://github.com/bats-core.

## Installation

Recommended installation is via git submodule. Assuming your project's bats
tests are in `test`:

``` sh
git submodule add https://github.com/buildkite-plugins/bats-mock test/helpers/mocks
git commit -am 'added bats-mock module'
```

then in `test/test_helper.bash`:

``` bash
load helpers/mocks/stub
```

## Usage

After loading `bats-mock/stub` you have two new functions defined:

- `stub`: for creating new stubs, along with a plan with expected args and the results to return when called.
- `unstub`: for cleaning up, and also verifying that the plan was fulfilled.

### Stubbing

The `stub` function takes a program name as its first argument, and any remaining arguments goes into the stub plan, one line per arg.

Each plan line represents an expected invocation, with a list of expected arguments followed by a command to execute in case the arguments matched, separated with a colon:

    arg1 arg2 ... : only_run if args matched

The expected args (and the colon) is optional.

So, in order to stub `date`, we could use something like this in a test case (where `format_date` is the function under test, relying on data from the `date` command):

```bash
load helper

# this is the "code under test"
# it would normally be in another file
format_date() {
  date -r 222
}

setup() {
  stub date \
      "-r 222 : echo 'I am stubbed!'" \
      "-r \* : echo 'Wed Dec 31 18:03:42 CST 1969'"
}

teardown() {
  unstub date
}

@test "date format util formats date with expected arguments" {
  result="$(format_date)"
  [ "$result" == 'I am stubbed!' ]

  result="$(format_date)"
  [ "$result" == 'Wed Dec 31 18:03:42 CST 1969' ]
}
```

This verifies that `format_date` indeed called `date` using the args defined in each specified stub, and made proper use of the output of it. Note that `\*` matches whatever is at that argument position, including a missing one — it does not require an argument to be present.

The plan is verified, one by one, as the calls come in, but the final check that there are no remaining un-met plans at the end is left until the stub is removed with `unstub`.

### Unstubbing

Once the test case is done, you should call `unstub <program>` in order to clean up the temporary files, and make a final check that all the plans have been met for the stub.

`unstub --allow-missing <program>` tolerates a program that was never stubbed, or was already unstubbed, which otherwise fails with `<program> is not stubbed`. It does not skip plan verification: a program that *was* stubbed and whose plan went unfulfilled still fails.

`unstub --force <program>` does skip verification entirely and always succeeds, while still cleaning up as normal. The two flags compose in either order.

### Verifying stub input

If you want to verify that your stub was passed the correct data in STDIN, you can redirect its content to a temporary file and check it.

```bash
@test "send_message" {
  stub curl \
    "${_CURL_ARGS} : cat > ${_TMP_DIR}/actual-input ; cat ${_RESOURCES_DIR}/mock-output"

  run send_message
  assert_success
  diff "${_TMP_DIR}/actual-input" "${_RESOURCES_DIR}/expected-input"
  unstub curl
}
```

### Verifying stub arguments

If you want to verify that your stub was called with the correct arguments, you can use (escaped) positional variables in the command. They will be interpreted correctly (`$1`, `$2`, ...).

```bash
@test "send_message" {
  stub curl \
    "-X \* \* : echo \$3 > ${_TMP_DIR}/curl-url; echo \$2 > ${_TMP_DIR}/curl-method"

  run send_message
  
  assert_success
  diff "${_TMP_DIR}/curl-url" "${_RESOURCES_DIR}/expected-url"
  called_method="$(cat ${_TMP_DIR}/curl-method)"
  [ "$called_method" == "POST" ]

  unstub curl
}
```

To check them all at once instead of by position, `inspect_args "$@"` formats the whole argument list as one string, space-separated, double-quoting any argument containing a space:

```bash
stub curl "-X \* \* : echo \$(inspect_args \"\$@\") > ${_TMP_DIR}/curl-args"
```

It is a plain shell function, not exported, so it is not visible to a nested `bash -c` that the plan command spawns.

### Using a function as the plan command

A plan's command can call a function instead of a literal command. The function must be exported: the stub runs as a separate process, so it only sees functions you've explicitly exported.

```bash
respond() { echo '{"result": "ok"}'; }
export -f respond

stub curl "-X \* \* : respond \"\$@\""
```

Forward arguments with `"$@"` if the function needs them. Avoid calling the command you're stubbing from inside the function — it resolves back through the stub's own `PATH` entry and recurses.

### Accepting any (or no) arguments

Sometimes the argument is too complicated to determine in advance, or it would make the stubbing really long and convoluted. In those cases you can use `\*` as a placeholder for one argument position — it matches whatever is there, including nothing at all. Only passing *more* arguments than the line declares makes the call fail to match.

```bash
@test "send_message" {
  stub grep \
    '\* \* : echo OK' \
    '\* \* : echo OK'

  # matches: up to 2 arguments are accepted
  grep "$complicated_pattern" /home/user/file
  # does not match: 3 arguments, more than the 2 declared :(
  grep -ri "$complicated_pattern" /home/user/file
}
```

If you do not care about the amount of arguments, not having any colons whatsoever means accepting any amount of arguments:

```bash
@test "send_message" {
  stub grep \
    'exit 0' \
    'exit 1' \
    'exit 2'

  # Will match the first stub line and exit with code 0
  grep "$complicated_pattern" /home/user/file

  # Matches the second one and exits with code 1
  grep -E -i "$some_pattern" "$some_file"

  # No arguments also match, the third one exits with code 2 :)
  grep
}
```

If you want to ensure no arguments whatsoever, you add a single colon at the very beginning:

```bash
@test "send_message" {
  # Note that a single colon at the start is interpreted as "no arguments"
  stub cat ': echo "OK"'
  ! cat foo # `cat` stub fails as an argument was passed

  # But don't forget the space! Without it `stub` receives one argument --
  # a program named `cat:echo "OK"` -- and never stubs `cat` at all.
  stub cat':echo "OK"'
  cat foo # runs the real cat, which fails: no such file

  # If your command contains ' : ' just start with double-colon
  stub cat '::echo "Hello : World"'
  # Prints "Hello : World"
  cat foo bar
}
```

### Incremental Stubbing

In some case it might be preferable to define the invocation plan incrementally to mirror the actual behavior of the program under test.
This can be done by invoking `stub` multiple times with the same command.
In case you want to start with a new plan call `unstub` first.

```bash
# Function to test
function install() {
  apt-get update
  apt-add-repository -y myrepo
  apt-get update
}

@test "test installation" {
  stub apt-get "update : "
  stub apt-add-repository "-y myrepo : "
  stub apt-get "update : " # Appends to existing plan
  run install
  unstub apt-get # Verifies plan and removes all remaining files
  stub apt-get "upgrade" # Start with a new plan
}
```

### Repeated Stubbing

`stub_repeated` takes a single plan line that matches any number of invocations — zero, one, or many — instead of one line per expected call:

```bash
stub_repeated curl "example.com : echo body"
```

The line is re-checked on every call rather than advancing, so `unstub` never fails it as unconsumed. Only one plan line is used; a second is never reached.

## Troubleshooting

When `unstub` fails it reports why on stderr: plan lines that were never reached, and calls that didn't match one, with the arguments actually received. `unstub --force` skips this along with everything else.

For more detail, enable debugging by setting an environment variable named after the command being stubbed (all in underscore-separated, uppercase) with the `STUB_DEBUG` suffix. The value of the variable needs to be a device or already-open file descriptor where to redirect the debugging output.

Note that bats keeps fd 3 open for its own output, so don't close it yourself; and a file path is truncated on every write, leaving only the most recent line.

If you have stubbed the `date` command, you can do something like:

```
export DATE_STUB_DEBUG=3
```

## How it works

(You may want to know this, if you get weird results there may be stray files lingering about messing with your state.)

Under the covers, `bats-mock` is two scripts (`stub.bash`, which you `load`, and `binstub`, which does the actual matching) plus, per stub, a few state files that `binstub` manages.

First, it is the command (or program) itself, which when the stub is created is placed in (or rather, the `binstub` script is sym-linked to) `${BATS_MOCK_BINDIR}/${program}` (which is added to your `PATH` when loading the stub library). Secondly, it creates a stub plan, based on the arguments passed when creating the stub, and finally, during execution, the command invocations are tracked in a stub run file which is checked once the command is `unstub`'ed, alongside a stub errors file recording any call that didn't match. The `${program}-stub-[plan|run|errors]` files are all in `${BATS_MOCK_TMPDIR}`.

`BATS_MOCK_TMPDIR` is `$BATS_TEST_TMPDIR`, so stub state is isolated per test, which is what makes it safe under `bats --jobs`. This requires bats-core >= 1.4.0.

An empty plan (`stub foo` with no plan lines) means "must not be called". Argument patterns are parsed with `eval` under `set -f`, which is what lets quoted patterns containing spaces work — but it also means `$variables` and `$(command substitutions)` in a pattern are expanded. Keep that in mind for patterns that aren't literals you wrote.

### Caveat

If you stub functions, make sure to unset them, or the stub script won't be called, as the function will shadow the binstub script on the `PATH`.

Shell builtins (`read`, `cd`, `test`, etc.) can't be stubbed: builtins are resolved before `PATH` is consulted, so the `binstub` symlink is never reached. Wrap the builtin in your own function and stub that instead.

## Credits

Forked from https://github.com/jasonkarns/bats-mock originally with thanks to [@jasonkarns](https://github.com/jasonkarns).

Originally extracted from the [ruby-build][] test suite. Many thanks to its author and contributors: [Sam Stephenson][sstephenson] and [Mislav Marohnić][mislav].

[ruby-build]: https://github.com/sstephenson/ruby-build
[sstephenson]: https://github.com/sstephenson
[mislav]: https://github.com/mislav
