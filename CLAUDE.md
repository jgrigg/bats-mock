# bats-mock

Fork of jasonkarns/bats-mock (mocking/stubbing library for BATS).

## Comments

Same comment-quality floor as the global config (delete narration,
change-narration, block-end markers, ephemeral references; keep only what
carries a *why* the code can't). In this codebase, that's mostly meant:

- macOS/BSD vs. Linux/GNU shell-utility differences (e.g. `tr` under the C
  locale) — invisible from the command itself, easy to "simplify" away.
- `shellcheck disable` directives — always pair with a one-line reason, or
  a future edit deletes the "dead code" it's actually protecting.
- bash subshell/export semantics (`( eval ... )`, `export -f`) — a plain
  reading suggests the opposite of the correct behavior.

Keep these to one line where possible. Longer rationale belongs in the
commit message, not inline.
