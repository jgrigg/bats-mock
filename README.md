# bats-mock

Mocking/stubbing library for BATS (Bash Automated Testing System)

A maintained fork of https://github.com/jasonkarns/bats-mock. Upstream hasn't merged community-contributed features in some time; this fork carries those changes, plus a test suite and CI.

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

This verifies that `format_date` indeed called `date` using the args defined in each specified stub, and made proper use of the output of it. Note that `\*` matches (and ignores) whatever is at that argument position — including a missing argument. It does not require one to be present; see "Accepting any (or no) arguments" below for the full semantics.

The plan is verified, one by one, as the calls come in, but the final check that there are no remaining un-met plans at the end is left until the stub is removed with `unstub`.

### Unstubbing

Once the test case is done, you should call `unstub <program>` in order to clean up the temporary files, and make a final check that all the plans have been met for the stub.

By default, `unstub`-ing a program that was never actually `stub`-bed (or was already `unstub`-bed) is itself a failure — it prints `<program> is not stubbed` to stderr and returns 1. If that's expected (e.g. a `teardown` that unconditionally cleans up a stub some earlier test path might not have touched), pass `--allow-missing`: `unstub --allow-missing <program>`. Note this only suppresses that specific "never stubbed" case — if the program *was* stubbed and its plan wasn't fulfilled, `unstub --allow-missing` still fails; `--allow-missing` is not a way to skip plan verification.

For that, there's `--force`: `unstub --force <program>` skips plan verification entirely and always returns 0, regardless of whether the program was ever stubbed, ever invoked, or invoked in a way that didn't match its plan. Cleanup (removing the stub's symlink and state files) still happens as normal. Useful for a `teardown` that just wants stubs gone without asserting anything about how the test used them. `--force` and `--allow-missing` compose in either order if you want both, though `--force` alone already covers everything `--allow-missing` does.

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

For a quick sanity check across all of them at once rather than picking out individual positions, `inspect_args "$@"` formats the full argument list as a single string (space-separated, double-quoting any argument that itself contains a space). Note the escaped `\$(...)`, same as with `\$1`/`\$2` above — it needs to be deferred to when the stub is actually invoked, not expanded immediately by the shell that's setting up the stub:

```bash
@test "send_message" {
  stub curl \
    "-X * * : echo \$(inspect_args \"\$@\") > ${BATS_TEST_TMPDIR}/actual-curl-args"

  run send_message

  assert_success
  [ "$(cat "${BATS_TEST_TMPDIR}/actual-curl-args")" == '-X POST https://example.com' ]
  unstub curl
}
```

`inspect_args` is a plain shell function, made available inside the `eval`'d plan command the same way `$1`/`$2`/`$@` are — it's not exported, so it won't be visible to a further-nested `bash -c` the plan command spawns.

### Using a function as the plan command

The command portion of a plan line doesn't have to be a literal shell command — it can call a function you've defined, which is handy when the logic needed to produce a realistic response is more than fits comfortably in a one-line plan:

```bash
respond_based_on_method() {
  case "$2" in
    GET) echo '{"result": "cached"}' ;;
    *) echo '{"result": "ok"}' ;;
  esac
}
export -f respond_based_on_method

@test "GET requests return the cached response" {
  stub curl "-X * * : respond_based_on_method \"\$@\""
  run send_request GET https://example.com
  # ...
  unstub curl
}
```

The `export -f` is required, and easy to miss: the stubbed program runs as a genuinely separate process (`binstub`, reached via the `PATH` symlink `stub` set up), not sourced into your test's shell — so, exactly like any other external command, it only sees functions you've explicitly exported, not ones merely defined earlier in the same test file. A function that isn't exported fails the same way `inspect_args` does when a plan command shells out to a nested `bash -c`: `<function>: command not found`.

If the function needs the actual arguments the stub was called with, forward them explicitly with `"$@"` (escaped the same way as everywhere else in this section, to defer expansion until the stub is actually invoked) — a function doesn't automatically inherit them otherwise, since it's an ordinary function call, not special-cased by `bats-mock`.

**Watch out for self-reference.** If your function calls the *same* command you're stubbing (e.g. stubbing `date` with a function that itself shells out to `date` to build a realistic-looking response), it'll resolve right back through the stub's own `PATH` entry and recurse — the process only stops when it exhausts something (you'll typically see `fork: Resource temporarily unavailable`, not a clean failure). If you need the real thing from inside a replacement, resolve it before `load`ing this library (`REAL_DATE=$(command -v date)`) the same way `stub.bash` itself does for `rm`/`mkdir`/`ln`/`touch`, and call that instead.

### Accepting any (or no) arguments

Sometimes the argument is too complicated to determine in advance, or it would make the stubbing really long and convoluted. In those cases you can use `\*` as a placeholder for one argument position — it matches whatever is there, including nothing at all. The only thing that can still make a call fail to match a plan line with `\*`s in it is passing *more* arguments than the line declares.

```bash
@test "send_message" {
  stub grep \
    '\* \* : echo OK' \
    '\* \* : echo OK'

  # matches: 0, 1, or 2 arguments are all within this line's budget of 2
  grep "$complicated_pattern" /home/user/file
  # this does not match: 3 arguments exceeds the budget of 2 :(
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

  # But don't forget the space between the program name and the plan!
  # Without it, "cat" and the plan line are parsed as ONE argument, so
  # `stub` sees a single program literally named `cat:echo "OK"` -- it
  # never stubs `cat` at all. The line below runs the real, unstubbed
  # `cat` binary, which fails because ./foo doesn't exist.
  stub cat':echo "OK"'
  cat foo

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

## Troubleshooting

It can be difficult to figure out why your mock has failed. You can enable debugging by setting an environment variable named after the command being stubbed (all in underscore-separated, uppercase) with the `STUB_DEBUG` suffix. The value of the variable needs to be a device or already-open file descriptor where to redirect the debugging output.

A numeric value (e.g. `3`) duplicates that file descriptor — bats itself keeps fd 3 open as its own diagnostic channel, so routing debug output there tends to show up alongside bats' own output. Don't `exec 3>`/`exec 3>&-` a numeric fd yourself, though: bats relies on fd 3 staying open for its own TAP output, and closing it out from under bats will break later tests in the same run with "Bad file descriptor". Use any other already-open fd, or point `STUB_DEBUG` at a real file path (e.g. `/dev/tty`) instead — but note that a file path is opened fresh (truncated) on *every* debug line, so only the most recent line survives; it's meant for interactively watching a single point of failure, not for accumulating a log.

If you have stubbed the `date` command, you can do something like:

```
export DATE_STUB_DEBUG=3
```

## How it works

(You may want to know this, if you get weird results there may be stray files lingering about messing with your state.)

Under the covers, `bats-mock` is two scripts (`stub.bash`, which you `load`, and `binstub`, which does the actual matching) plus, per stub, two state files that `binstub` manages.

First, it is the command (or program) itself, which when the stub is created is placed in (or rather, the `binstub` script is sym-linked to) `${BATS_MOCK_BINDIR}/${program}` (which is added to your `PATH` when loading the stub library). Secondly, it creates a stub plan, based on the arguments passed when creating the stub, and finally, during execution, the command invocations are tracked in a stub run file which is checked once the command is `unstub`'ed. The `${program}-stub-[plan|run]` files are both in `${BATS_MOCK_TMPDIR}`.

`BATS_MOCK_TMPDIR` is `$BATS_TEST_TMPDIR`, so stub state is isolated per test case (each test gets a fresh directory bats cleans up itself), which is what makes it safe to run under `bats --jobs`. This requires **bats-core >= 1.4.0** (`BATS_TEST_TMPDIR` was added there); older bats versions aren't supported.

An empty plan (`stub foo` with no plan lines at all) means "must not be called" — `unstub` fails if the stubbed program was invoked even once. Pattern text is not treated literally: each plan line's argument-pattern portion is parsed via `eval` (under `set -f`, so globs in patterns are not expanded against the filesystem), which is what lets quoted patterns containing spaces work, but also means `$variables` and `$(command substitutions)` in a pattern are expanded/executed. Keep that in mind if a pattern's contents come from anything other than a literal string you wrote.

### Caveat

If you stub functions, make sure to unset them, or the stub script won't be called, as the function will shadow the binstub script on the `PATH`.

Shell builtins (`read`, `cd`, `test`, `[`, etc.) can't be stubbed at all — builtins are resolved before `PATH` is ever consulted, so the `binstub` symlink is never reached. Wrap the builtin in your own function and stub that instead, or test its effects through an external command.

## Credits

Forked from https://github.com/jasonkarns/bats-mock originally with thanks to [@jasonkarns](https://github.com/jasonkarns).

Originally extracted from the [ruby-build][] test suite. Many thanks to its author and contributors: [Sam Stephenson][sstephenson] and [Mislav Marohnić][mislav].

[ruby-build]: https://github.com/sstephenson/ruby-build
[sstephenson]: https://github.com/sstephenson
[mislav]: https://github.com/mislav
