#!/usr/bin/env bash
# Shared by the dispatcher (bash-gate.sh), the gates under gates/ and the stop
# hook. Sourcing only defines functions.
#
#   hook_read_payload                  stdin once → HOOK_CMD HOOK_CWD HOOK_FILE HOOK_RAW; with
#                                      HOOK_PAYLOAD_SET=1 exported it returns at once and trusts
#                                      HOOK_CMD HOOK_CWD HOOK_FILE HOOK_RAW HOOK_GIT_DIR HOOK_CLASSES TOP
#   normalize_shell_command CMD        → JOINED (heredoc bodies dropped unless a shell runs them),
#                                        NORM (quoted arguments blanked)
#   is_git_commit_command [CMD]        NORM runs `git [opts] commit`; sets HOOK_GIT_DIR from cd / -C
#   is_git_push_command [CMD]          the same shape with `push`
#   opens_pr_command [CMD]             gh pr create|new|ready, a POST to …/pulls, a createPullRequest mutation
#   classify_command [CMD]             → HOOK_CLASSES, the subset of "commit push pr-open" the command is in
#   in_class NAME                      0 when NAME is in HOOK_CLASSES
#   refuse_combined_commit_shape [CMD] B15: prints the reason and returns 1 when the commit also stages
#   repo_top [DIR]                     toplevel of DIR, else HOOK_GIT_DIR, HOOK_CWD, CLAUDE_PROJECT_DIR
#   hook_config                        load the project: block of the review map into HOOK_CFG_* (once, exported)
#   cfg_lines NAME                     a list or map HOOK_CFG_<NAME> as one entry per line
#   is_project_repo [TOP]              TOP is this project: origin is project.repo, or TOP shares the hooks' git dir
#   commit_message_from_command [CMD]  → MESSAGE: the command text, -F/--file files, a reused message (B5)
#   staged_paths [TOP] [FILTER]        → STAGED array, NUL-safe; FILTER defaults to ACMR, '' means all
#   state_dir [TOP]                    <git common dir>/<project.state_dir>, absolute (B17)
#   hook_slug NAME                     a branch name as a marker file name (gstack-slug's sanitisation)
#   changed_paths BASE [HEAD] [TOP]    → CHANGED array: git diff --no-renames --name-only -z
#   changed_status BASE [HEAD] [TOP]   the --no-renames --name-status -z rows on stdout
#   map_query SUB ARGS…                node scripts/review-map.mjs SUB ARGS… (HOOK_REVIEW_MAP_SCRIPT overrides)
#   docs_only_verdict PATH…            prints docs | never | code for the set; returns 0 only for docs
#   lifecycle_key [TOP] [REV]          sha256 of the REV:<path> ids of project.lifecycle_inputs (B7)
#   deps_key [TOP] [REV]               sha256 of the manifest rows of git ls-tree -r REV (B9)
#   first_parent_walk START MAX [TOP]  START then up to MAX first-parent ancestors, none on origin/main
#   secret_exempt_path PATH            0 when the path matches project.secret_exempt (B19)
#   hook_remedy COMMAND                tells the dispatcher what to run by hand (fd 3, when it is open)
#
# Payload contract: PreToolUse gets {tool_input:{command,file_path},cwd}; Stop gets {cwd}.

HOOK_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

hook_read_payload() {
  if [ "${HOOK_PAYLOAD_SET:-}" = 1 ]; then
    # The dispatcher read and classified the payload once and spawned this stage
    # with </dev/null: trust its export, read nothing.
    : "${HOOK_CMD=}" "${HOOK_CWD=}" "${HOOK_FILE=}" "${HOOK_GIT_DIR=}" "${HOOK_CLASSES=}" "${TOP=}"
    HOOK_RAW=${HOOK_RAW:-no}
    HOOK_INPUT=''
    return 0
  fi
  HOOK_INPUT=$(cat)
  HOOK_CMD='' HOOK_CWD='' HOOK_FILE='' HOOK_GIT_DIR='' HOOK_CLASSES='' HOOK_RAW=no
  if command -v jq >/dev/null 2>&1 &&
    printf '%s' "$HOOK_INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
    HOOK_CMD=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.command? | strings' 2>/dev/null)
    HOOK_CWD=$(printf '%s' "$HOOK_INPUT" | jq -r '.cwd? | strings' 2>/dev/null)
    # shellcheck disable=SC2034  # read by the edit-time hooks
    HOOK_FILE=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.file_path? | strings' 2>/dev/null)
  else
    # Fail closed: no jq or a malformed payload → match the raw text (JSON-escaped
    # newlines turned back into line breaks) rather than let the command through.
    HOOK_RAW=yes
    HOOK_CMD=$(printf '%s' "$HOOK_INPUT" | sed -e 's/\\n/\n/g' -e 's/\\t/ /g')
  fi
}

# In order:
#  1. drop heredoc bodies — commit messages and docs that MENTION a command —
#     unless the command word before `<<` is a shell (bash, sh, zsh, dash, eval,
#     source, `.`): that body will execute, so it stays and its terminator
#     becomes a `;` (B3)
#  2. join lines, drop backslashes (continuations, `g\h`)
#  3. unquote the argument of `-c` / `eval`, which bash will execute
#  3b. unquote whitespace-free strings (`-C "/wt"`): without it step 4 pairs a
#     closing quote with the next opening one and
#     blanks ` commit -m ` out of `git -C "/wt" commit -m "fix: x"`
#  4. blank any other quoted string containing whitespace — it is an argument
#     (`grep 'git commit'`, `-m "..."`), not a command
#  5. strip the remaining quotes (`"git" commit`) and squeeze spaces
normalize_shell_command() {
  JOINED=$(printf '%s\n' "$1" | awk '
    delim != "" {
      t = $0; sub(/^[ \t]+/, "", t)
      if (t == delim) { delim = ""; if (keep) print ";"; keep = 0; next }
      if (keep) print
      next
    }
    {
      if (match($0, /<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*["\047]?/) &&
          (RSTART == 1 || substr($0, RSTART - 1, 1) != "<")) {
        delim = substr($0, RSTART, RLENGTH); gsub(/<<-?[ \t]*|["\047]/, "", delim)
        pre = substr($0, 1, RSTART - 1)
        n = split(pre, segs, /[;|&(]/); seg = segs[n]; sub(/^[ \t]+/, "", seg)
        split(seg, w, /[ \t]+/); word = w[1]; sub(/.*\//, "", word)
        keep = (word ~ /^(bash|sh|zsh|dash|eval|source|\.)$/)
      }
      print
    }' | tr '\n' ' ' | sed -e 's/\\//g')
  NORM=$(printf '%s' "$JOINED" | sed -E \
    -e "s/(-c|eval)[[:space:]]+'([^']*)'/\\1 \\2/g" \
    -e 's/(-c|eval)[[:space:]]+"([^"]*)"/\1 \2/g' \
    -e "s/'([^'[:space:]]*)'/\\1/g" \
    -e 's/"([^"[:space:]]*)"/\1/g' \
    -e "s/'[^']*[[:space:]][^']*'/Q/g" \
    -e 's/"[^"]*[[:space:]][^"]*"/Q/g' \
    -e "s/['\"]//g" | tr -s ' ')
  # In the raw fallback the whole command sits inside one JSON string, which step 4
  # would blank. Skip it there: over-matching is the right failure for a gate.
  if [ "${HOOK_RAW:-no}" = yes ]; then
    NORM=$(printf '%s' "$JOINED" | sed "s/['\"]//g" | tr -s ' ')
  fi
}

# `git [-flag [value]]... <verb>` anywhere in NORM (`git -c x=y commit`, `git -C dir
# push`, `sudo git commit`, `$(git commit)`). Only the first match is read: its
# text goes to HOOK_VERB_MATCH and the tree it acts on to HOOK_GIT_DIR, absolute:
# the last `cd`/`pushd` before it, then each -C in order; empty when none.
_GIT_RE='(^|[^[:alnum:]_./-])([^[:space:]]*/)?git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]]+)?)*[[:space:]]+'
_git_verb_match() {
  local re m d rest base
  HOOK_GIT_DIR='' HOOK_VERB_MATCH=''
  re="${_GIT_RE}$1([^[:alnum:]_.-]|\$)"
  [[ $NORM =~ $re ]] || return 1
  m=${BASH_REMATCH[0]}
  HOOK_VERB_MATCH=$m
  base=${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}
  d=$(printf '%s' "${NORM%%"$m"*}" |
    grep -oE '(^|[;&|(])[[:space:]]*(cd|pushd)[[:space:]]+[^[:space:];&|)]+' |
    tail -1 | sed -E 's/^.*(cd|pushd)[[:space:]]+//')
  if [ -n "$d" ]; then
    HOOK_GIT_DIR=$(_hook_abs_dir "$d" "$base"); base=$HOOK_GIT_DIR
  fi
  rest=$m
  while [[ $rest =~ [[:space:]]-C[[:space:]]+([^[:space:]]+)(.*)$ ]]; do
    HOOK_GIT_DIR=$(_hook_abs_dir "${BASH_REMATCH[1]}" "$base"); base=$HOOK_GIT_DIR
    rest=${BASH_REMATCH[2]}
  done
  return 0
}
is_git_commit_command() { normalize_shell_command "${1-${HOOK_CMD-}}"; _git_verb_match commit; }
is_git_push_command() { normalize_shell_command "${1-${HOOK_CMD-}}"; _git_verb_match push; }

# The shapes that open a PR.
_norm_has() { printf '%s' "$NORM" | grep -qEi -- "$1"; }
_PR_OPEN_RE='(^|[^[:alnum:]_./-])([^[:space:]]*/)?gh[[:space:]]+pr[[:space:]]+(create|new|ready)([^[:alnum:]_-]|$)'
_opens_pr_match() {
  _norm_has "$_PR_OPEN_RE" && return 0
  if _norm_has '(^|[^[:alnum:]_./-])gh[[:space:]]+api([[:space:]]|$)'; then
    # REST: the pulls collection, sent as a POST — explicitly, or implicitly
    # because gh switches to POST as soon as a field or body is given.
    _norm_has '/pulls([^/[:alnum:]]|$)' &&
      _norm_has '(-X[[:space:]]*POST|--method([[:space:]]+|=)POST|[[:space:]](-f|-F|--field|--raw-field|--input)([[:space:]=]|$))' &&
      return 0
    # GraphQL: the mutation lives inside a quoted query, which NORM blanks.
    printf '%s' "$JOINED" | grep -q 'createPullRequest' && return 0
  fi
  return 1
}
opens_pr_command() { normalize_shell_command "${1-${HOOK_CMD-}}"; _opens_pr_match; }

# One normalization, three matchers. HOOK_GIT_DIR is the commit's tree when the
# command commits, else the push's. Returns 1 for a command in no class.
classify_command() {
  local dir='' c=''
  normalize_shell_command "${1-${HOOK_CMD-}}"
  if _git_verb_match commit; then c='commit'; dir=$HOOK_GIT_DIR; fi
  if _git_verb_match push; then c="${c:+$c }push"; [ -n "$c" ] && [ "${c%% *}" = commit ] || dir=$HOOK_GIT_DIR; fi
  if _opens_pr_match; then c="${c:+$c }pr-open"; fi
  HOOK_CLASSES=$c
  HOOK_GIT_DIR=$dir
  [ -n "$HOOK_CLASSES" ]
}
in_class() { case " ${HOOK_CLASSES-} " in *" $1 "*) return 0 ;; esac; return 1; }

# The commit's own argument tokens (after `git … commit`, up to ; & | or a
# closing paren) into ARGS. Quoted strings with whitespace are already `Q`.
_commit_args() {
  local rest last
  last=${HOOK_VERB_MATCH: -1}
  rest=${NORM#*"$HOOK_VERB_MATCH"}
  case $last in [[:space:]]) ;; *) rest="$last$rest" ;; esac
  rest=${rest%%[;\&|)]*}
  read -r -a ARGS <<<"$rest"
}

# B15. Every gate reads the index before the command runs, so a commit that also
# stages would be judged on the wrong content. Refused: (a) git add/rm/mv/restore/
# checkout/stash pop|apply before the commit, (b) -a -i -p -o and their long forms,
# also inside a short-flag cluster (-am), (c) a pathspec or a bare `--` after the
# values of the message and author options. Prints the reason; returns 1 to refuse.
# `git commit --amend --no-edit` with nothing staged stays allowed.
refuse_combined_commit_shape() {
  local why='' pre verb i n tok cluster c
  normalize_shell_command "${1-${HOOK_CMD-}}"
  _git_verb_match commit || return 0
  pre=${NORM%%"$HOOK_VERB_MATCH"*}
  if [[ $pre =~ ${_GIT_RE}(add|rm|mv|restore|checkout|stash[[:space:]]+(pop|apply))([^[:alnum:]_.-]|$) ]]; then
    verb=$(printf '%s' "${BASH_REMATCH[0]}" | sed -E 's/^.*git.*[[:space:]](add|rm|mv|restore|checkout|stash[[:space:]]+(pop|apply)).*$/\1/' | tr -s ' ')
    why="git $verb runs in the same call, before the commit"
  fi
  if [ -z "$why" ]; then
    _commit_args
    i=0; n=${#ARGS[@]}
    while [ "$i" -lt "$n" ] && [ -z "$why" ]; do
      tok=${ARGS[$i]}; i=$((i + 1))
      case $tok in
        --) why="a pathspec follows '--'" ;;
        -a|--all|-i|--include|-p|--patch|--interactive|-o|--only|--pathspec-from-file|--pathspec-from-file=*)
          why="'$tok' stages as part of the commit" ;;
        --message|--file|--author|--date|--trailer|--fixup|--squash|--reuse-message|--reedit-message|--template|--cleanup)
          i=$((i + 1)) ;;
        --*) ;;
        -[!-]*)
          cluster=${tok#-}
          while [ -n "$cluster" ]; do
            c=${cluster:0:1}; cluster=${cluster:1}
            case $c in
              a|i|p|o) why="'-$c' stages as part of the commit"; break ;;
              m|F|C|c|t) [ -n "$cluster" ] || i=$((i + 1)); break ;;
              S|u) break ;;
            esac
          done ;;
        [0-9]*[\<\>]*|[\<\>]*) # a redirection; a bare operator (`2>`, `<`) takes the next token
          case $tok in *[!0-9\<\>]*) ;; *) i=$((i + 1)) ;; esac ;;
        *) # in the raw fallback quotes are gone, so a message reads as words: no pathspec rule there
          [ "${HOOK_RAW:-no}" = yes ] || why="'$tok' is a pathspec" ;;
      esac
    done
  fi
  [ -n "$why" ] || return 0
  printf 'stage in its own call, then commit alone: the gates read the index before the command runs (%s).\n' "$why"
  return 1
}

# A path from the command text: `~` and $HOME expanded, relative made absolute
# against $2. Anything else the shell would expand stays literal and fails
# repo_top, which the gates treat as "cannot tell which tree" and block.
_hook_abs_dir() {
  local d=$1
  d=${d/#\~/$HOME}; d=${d//\$\{HOME\}/$HOME}; d=${d//\$HOME/$HOME}
  case $d in /*) printf '%s' "$d" ;; *) printf '%s/%s' "$2" "$d" ;; esac
}

repo_top() {
  local dir=${1:-${HOOK_GIT_DIR:-${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}}}
  git -C "$dir" rev-parse --show-toplevel 2>/dev/null
}

# The project: block of .claude/review-map.yml, read once per hook run and
# exported, so the dispatcher's stages never start node again. Returns 1 when
# the map cannot be read; every caller treats that as a block.
hook_config() {
  local out
  [ "${HOOK_CFG_LOADED:-}" = 1 ] && return 0
  out=$(map_query config 2>/dev/null) || return 1
  eval "$out" || return 1
  # shellcheck disable=SC2046  # one word per variable name
  export HOOK_CFG_LOADED=1 $(printf '%s\n' "$out" | grep -oE '^HOOK_CFG_[A-Z_]+=' | tr -d =)
}
cfg_lines() { local v="HOOK_CFG_$1"; [ -n "${!v:-}" ] && printf '%s\n' "${!v}"; }

# The gates belong to this project: a checkout (or worktree) of the repo that
# holds these hooks, or any clone whose origin is project.repo. Another repo a
# session happens to operate on is left alone.
is_project_repo() {
  local top=${1:-${TOP:-.}} mine theirs re
  hook_config || return 1
  mine=$(git -C "$HOOK_LIB_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || mine=''
  theirs=$(git -C "$top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  [ -n "$mine" ] && [ "$mine" = "$theirs" ] && return 0
  re=$(printf '%s' "$HOOK_CFG_REPO" | sed 's/[.]/\\./g')
  git -C "$top" remote get-url origin 2>/dev/null | grep -qiE "[/:]$re(\.git)?/?\$"
}

# The message is in the command text (-m, heredoc) plus any -F/--file file,
# read relative to where the commit runs. `-F -` is the heredoc, already there.
# B5: when the message is reused (--amend without -m/-F, -C/--reuse-message,
# -c/--reedit-message, --fixup, --squash) that commit's message is appended,
# read from the same tree: HEAD for --amend, the named commit otherwise.
commit_message_from_command() {
  local cmd=${1-${HOOK_CMD-}} f dir sq="'" saved_dir i tok cluster c reuse='' amend=no explicit=no
  MESSAGE=$cmd
  normalize_shell_command "$cmd"
  dir=${HOOK_GIT_DIR:-${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}}
  while IFS= read -r f; do
    [ -n "$f" ] && [ "$f" != - ] || continue
    case $f in /*) ;; *) f="$dir/$f" ;; esac
    [ -f "$f" ] && MESSAGE="$MESSAGE"$'\n'"$(cat "$f")"
  done < <(printf '%s' "$JOINED" |
    grep -oE "(^|[[:space:]])(-F|--file)([[:space:]]+|=)(\"[^\"]*\"|${sq}[^${sq}]*${sq}|[^[:space:];&|]+)" |
    sed -E "s/^[[:space:]]*(-F|--file)([[:space:]]+|=)//; s/^[\"$sq]//; s/[\"$sq]\$//")
  saved_dir=${HOOK_GIT_DIR-}
  if _git_verb_match commit; then
    _commit_args
    i=0
    while [ "$i" -lt "${#ARGS[@]}" ]; do
      tok=${ARGS[$i]}; i=$((i + 1))
      case $tok in
        --amend) amend=yes ;;
        --message|--file) explicit=yes; i=$((i + 1)) ;;
        --message=*|--file=*) explicit=yes ;;
        --reuse-message=*|--reedit-message=*|--fixup=*|--squash=*) reuse=${tok#*=}; reuse=${reuse#amend:}; reuse=${reuse#reword:} ;;
        --reuse-message|--reedit-message|--fixup|--squash) reuse=${ARGS[$i]:-HEAD}; i=$((i + 1)) ;;
        --author|--date|--trailer|--template|--cleanup) i=$((i + 1)) ;;
        -[!-]*)
          cluster=${tok#-}
          while [ -n "$cluster" ]; do
            c=${cluster:0:1}; cluster=${cluster:1}
            case $c in
              m|F) explicit=yes; [ -n "$cluster" ] || i=$((i + 1)); break ;;
              C|c) reuse=${cluster:-${ARGS[$i]:-HEAD}}; [ -n "$cluster" ] || i=$((i + 1)); break ;;
              t) [ -n "$cluster" ] || i=$((i + 1)); break ;;
              S|u) break ;;
            esac
          done ;;
      esac
    done
    [ -n "$reuse" ] || { [ "$amend" = yes ] && [ "$explicit" = no ] && reuse=HEAD; }
    if [ -n "$reuse" ]; then
      f=$(git -C "$dir" log -1 --format=%B "$reuse" -- 2>/dev/null) || f=$(git -C "$dir" log -1 --format=%B 2>/dev/null) || f=''
      [ -n "$f" ] && MESSAGE="$MESSAGE"$'\n'"$f"
    fi
  fi
  HOOK_GIT_DIR=$saved_dir
  return 0
}

# NUL-delimited into an array, so a path with a space or a quote survives.
staged_paths() {
  local top=${1:-${TOP:-.}} filter=${2-ACMR} f
  STAGED=()
  while IFS= read -r -d '' f; do STAGED+=("$f"); done < <(
    git -C "$top" diff --cached --name-only -z ${filter:+--diff-filter="$filter"} 2>/dev/null
  )
}

# B17: markers live under the common git dir, so every worktree of a checkout
# shares them and they survive `git worktree remove`. Absolute: the main
# checkout prints a relative `.git` without --path-format (git < 2.31 has no
# such flag, hence the fallback).
state_dir() {
  local top=${1:-${TOP:-.}} d
  d=$(git -C "$top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) ||
    d=$(git -C "$top" rev-parse --git-common-dir 2>/dev/null) || return 1
  case $d in /*) ;; *) d="$top/$d" ;; esac
  hook_config || return 1
  printf '%s/%s' "$d" "$HOOK_CFG_STATE_DIR"
}
hook_slug() { printf '%s' "$1" | tr '/' '-' | tr -cd 'a-zA-Z0-9._-'; }

# "Changed paths" is always --no-renames: a rename-detecting diff hides a code
# deletion inside a docs-only delta (`git mv code.ts notes.md`).
changed_paths() {
  local top=${3:-${TOP:-.}} f
  CHANGED=()
  while IFS= read -r -d '' f; do CHANGED+=("$f"); done < <(
    git -C "$top" diff --no-renames --name-only -z "$1" ${2:+"$2"} -- 2>/dev/null
  )
}
changed_status() {
  git -C "${3:-${TOP:-.}}" diff --no-renames --name-status -z "$1" ${2:+"$2"} -- 2>/dev/null
}

# The map is read only through scripts/review-map.mjs, next to the hooks that
# are running (a branch editing the hooks or the map judges itself). A `match`
# answer that is not whole JSON fails like an unreadable map, so no caller
# reads a cut-off answer as "no paths matched".
map_query() {
  local out
  if [ "${1:-}" != match ]; then node "${HOOK_REVIEW_MAP_SCRIPT:-$HOOK_LIB_DIR/../../scripts/review-map.mjs}" "$@"; return; fi
  out=$(node "${HOOK_REVIEW_MAP_SCRIPT:-$HOOK_LIB_DIR/../../scripts/review-map.mjs}" "$@") || return
  printf '%s' "$out" | jq -e '.paths | type == "object"' >/dev/null 2>&1 ||
    { echo "review map: the match answer is not whole JSON" >&2; return 3; }
  printf '%s\n' "$out"
}

# docs: every path is docs-only and none is never-docs-only; never: one is
# never-docs-only; code: anything else. Prints the verdict, returns 0 only for
# docs, 2 when the map cannot be read (callers treat that as not docs).
docs_only_verdict() {
  local out v
  if [ $# -eq 0 ]; then echo docs; return 0; fi
  out=$(map_query match "$@" 2>/dev/null) || return 2
  v=$(printf '%s' "$out" | jq -r --argjson n "$#" '
    [.paths[]?.docs_only] as $v
    | if ($v | any(. == "never")) then "never"
      elif ($v | length) == $n and ($v | all(. == "docs")) then "docs"
      else "code" end' 2>/dev/null) || return 2
  echo "$v"
  [ "$v" = docs ]
}

# B7: what the lifecycle suite can see. A missing path hashes as empty.
lifecycle_key() {
  local top=${1:-${TOP:-.}} rev=${2:-HEAD} p id ids=''
  hook_config || return 1
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    id=$(git -C "$top" rev-parse -q --verify "$rev:$p" 2>/dev/null) || id=''
    ids="$ids $id"
  done < <(cfg_lines LIFECYCLE_INPUTS)
  printf '%s' "${ids# }" | sha256sum | cut -d' ' -f1
}

# B9: the lockfile, the workspace file and every package.json.
deps_key() {
  local top=${1:-${TOP:-.}} rev=${2:-HEAD}
  git -C "$top" ls-tree -r "$rev" 2>/dev/null | awk -F'\t' '
    { p = $2 }
    p == "pnpm-lock.yaml" || p == "pnpm-workspace.yaml" || p ~ /(^|\/)package\.json$/ { print }' |
    sha256sum | cut -d' ' -f1
}

# B11's walk: START, then its first-parent ancestors, at most MAX of them,
# stopping before the first commit already on the local origin/main (a record
# on a main commit never counts). No origin/main → the walk runs to MAX.
first_parent_walk() {
  local top=${3:-${TOP:-.}} sha main
  main=$(git -C "$top" rev-parse -q --verify origin/main 2>/dev/null) || main=''
  while IFS= read -r sha; do
    [ -n "$sha" ] || continue
    if [ -n "$main" ] && git -C "$top" merge-base --is-ancestor "$sha" "$main" 2>/dev/null; then break; fi
    printf '%s\n' "$sha"
  done < <(git -C "$top" rev-list --first-parent --max-count=$(($2 + 1)) "$1" 2>/dev/null)
}

# B19: the one exemption list (project.secret_exempt), shared by secret-scan.sh
# (on edit, absolute paths) and gates/secret-block.sh (at commit, repo-relative).
secret_exempt_path() {
  local pat
  hook_config || return 1
  while IFS= read -r pat; do
    # shellcheck disable=SC2053  # the pattern is meant to glob
    [ -n "$pat" ] && [[ $1 == $pat ]] && return 0
  done < <(cfg_lines SECRET_EXEMPT)
  return 1
}

# A stage names the command to run by hand when the dispatcher has to kill it
# (B16). Silent when fd 3 is not open, so a gate run on its own prints nothing.
hook_remedy() { { printf 'REMEDY: %s\n' "$1" >&3; } 2>/dev/null || true; }
