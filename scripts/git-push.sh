#!/usr/bin/env bash
# git-push-via-broker.sh — Push to GitHub via the Hub's GitHub App token broker.
#
# Hub-wide template. First written organically by daniel-treblemakers on
# 2026-05-23 after their SSH push hit SIGPIPE-before-pack-transfer-completed;
# promoted to a shared template the same evening. Copy this verbatim into your
# project as scripts/git-push.sh (or any name you like) — the only thing that
# might need per-project adaptation is the default REFSPEC ("HEAD:main" below).
#
# Why this exists:
#   The agent container cannot AUTHENTICATE to github.com over SSH:
#     - Agents hold no SSH private key. ~/.ssh/ contains at most known_hosts,
#       BY DESIGN — "agents have no long-lived git credentials" is the whole
#       reason this broker exists. `ssh -T git@github.com` completes its TCP
#       handshake and then fails "Permission denied (publickey)".
#     - CORRECTED 2026-07-31: this used to read "Port 22 is blocked on the
#       agent network for security". That is FALSE and was verified false from
#       inside a live agent container — github.com:22 is REACHABLE. The myth
#       was self-refuting all along: the evidence cited for it was
#       `Host key verification failed`, which can ONLY be produced by a
#       SUCCESSFUL connection to port 22 (you cannot fail to verify a host key
#       you never received). It matters because "port blocked" reads as
#       network policy somebody else must change, which sends agents to Super
#       for a firewall fix that was never needed; "no key, by design" points at
#       the real answer, which is this script.
#     - Beware the probe, too: `exec 3<>/dev/tcp/github.com/22; head -c 60 <&3`
#       HANGS — not because the port is closed, but because SSH's banner is
#       ~30 bytes and it blocks waiting for 60 that never come. A hung probe is
#       not a closed port. Use a real client (`ssh -T`) to settle it.
#     - Independently, the pre-push hook in many projects runs ~100+s, which
#       causes SSH to SIGPIPE before the pack transfer completes
#   The portal broker provides a short-lived (≤60min) GitHub App installation
#   token over HTTPS, scoped to your repo only. HTTPS has no equivalent
#   timeout issue and the token is fresh every push (no long-lived key to
#   protect).
#
# Usage:
#   ./scripts/git-push.sh                   # push HEAD → the repo's REAL default
#                                           # branch (resolved from origin/HEAD,
#                                           # not assumed to be "main")
#   ./scripts/git-push.sh HEAD:my-branch    # push to a different ref
#   ./scripts/git-push.sh feature-x         # equivalent to HEAD:feature-x
#                                           # (push current commit to branch)
#
# Requires (always present in agent containers):
#   $INTERNAL_API_KEY  — portal auth
#   $AGENT_TOPIC       — broker uses this to resolve the agent's repo
#
# Full broker docs: /root/agentic-hub/CLAUDE.md → "GitHub App Push-Token Broker"
#
# WHERE TO GET A FRESH COPY (2026-08-20):
#   FROM AN AGENT CONTAINER:  /consults/templates/git-push-via-broker.sh   ← use this
#   Host source-of-truth:     /root/scripts/templates/git-push-via-broker.sh
#     (symlink into /root/agentic-hub/host-scripts/templates/, so it is version-controlled)
#
# The host path is mode 700 root-only and is mounted into NO agent container, so for three
# months the documented instruction "copy the template into your project" was one no agent
# could physically follow. Every install was therefore a hand-port, and hand-ports drift:
# that is why StripeBot's copy had a local fix for the HEAD:main bug that never made it
# upstream, and why the bug was still live in Secretary and claude-memory-server.
# The /consults copy is root-owned in a root-owned directory (agents can read, and cannot
# overwrite, delete, or add alongside it) — this file runs with a live GitHub push token,
# so an agent-writable copy would be a supply-chain hole, not a convenience.
#
# MAINTAINER NOTE: the /consults copy is a COPY, not a symlink (a symlink to /root/... does
# not resolve inside the container). After editing the host source, re-publish:
#   install -o root -g root -m 444 /root/scripts/templates/git-push-via-broker.sh \
#           /root/data/tenants/consults/templates/git-push-via-broker.sh

set -euo pipefail

# Default branch is RESOLVED, never assumed. It used to be hardcoded "HEAD:main",
# which fails in the worst possible way on a `master` repo: `git push HEAD:main`
# CREATES a new branch and exits 0. The push "succeeds", the deploy webhook (keyed
# to the real default branch) never fires, and the agent reports shipped work that
# is not deployed. claude-memory-server hit exactly this on 2026-08-20 — it also
# fired a phantom CI alert from a workflow that only triggers on `main` and had
# never run before. 5 fleet repos are on `master` (YouGuard, StripeBot, Secretary,
# claude-memory-server, DFYHub-Website), so this was never a one-repo quirk.
#
# Resolution order, each falling through only if it yields nothing:
#   1. origin/HEAD — what the remote itself calls default (authoritative)
#   2. the branch currently checked out (right for a normal working tree)
#   3. main (last resort, and now only reached when 1 and 2 both fail)
_resolve_default_branch() {
  local b
  b=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) && b="${b#origin/}"
  if [[ -z "$b" ]]; then
    b=$(git ls-remote --symref origin HEAD 2>/dev/null \
        | awk '/^ref:/ {sub("refs/heads/","",$2); print $2; exit}')
  fi
  [[ -z "$b" ]] && b=$(git symbolic-ref --short HEAD 2>/dev/null)
  echo "${b:-main}"
}

if [[ -n "${1:-}" ]]; then
  REFSPEC="$1"
  # If the arg looks like a bare branch name (no colon), assume HEAD:<branch>
  if [[ "$REFSPEC" != *":"* ]]; then
    REFSPEC="HEAD:$1"
  fi
else
  REFSPEC="HEAD:$(_resolve_default_branch)"
  echo "No refspec given; resolved default branch → ${REFSPEC#HEAD:}"
fi

if [[ -z "${INTERNAL_API_KEY:-}" ]]; then
  echo "ERROR: INTERNAL_API_KEY not set — this script must run inside the agent container." >&2
  exit 1
fi

if [[ -z "${AGENT_TOPIC:-}" ]]; then
  echo "ERROR: AGENT_TOPIC not set — this script must run inside the agent container." >&2
  exit 1
fi

echo "Fetching GitHub App token from portal broker..."
# Validate the token by OUTCOME, not by appearance (from daniel-health's copy,
# folded upstream 2026-07-31). Never gate on token length or prefix: GitHub
# documents that these change, so a shape check is a latent fleet-wide outage —
# when the new format becomes the only format, every agent hard-fails here while
# printing a confident, wrong "broker fault". One cheap probe against
# receive-pack answers the only question that matters: can this token push?
#
# The evidence, kept because the rule alone does not stop the re-investigation
# (daniel-health, 2026-07-28; folded upstream 2026-07-31): the broker returns TWO
# shapes — the classic 40-char `ghs_<36>` and a ~390-char `ghs_<id>_<JWT>_<suffix>`.
# The long one LOOKS malformed and arrives mixed in at a varying rate, which makes
# it a very attractive suspect for intermittent "remote: Repository not found"
# failures. It is not the cause. It decodes to an ES256 JWT with `iss:"github"`
# and a 1-hour life matching the broker's expires_at — GitHub minted and signed
# it, so our code could not have forged it (which is also why grepping the portal
# for a construction site finds nothing). Measured 24/24 successful receive-pack
# auths across BOTH shapes, zero failures. The original push failures were a
# time-correlated transient that both shapes hit; length was a coincidence we
# pattern-matched onto. A `len == 40` gate was written here once and was wrong.
#
# Retry because a freshly-minted installation token is not always immediately
# usable; a single-shot fetch turns a transient into a hard failure.
# ── ASK FOR THE REPO YOU ARE ACTUALLY IN (2026-09-18) ──────────────────────
# This used to send only agent_topic, so the broker returned the agent's DEFAULT
# repo. For a single-repo agent that is always right. For a MULTI-REPO agent it
# is right only for the first repo in its allowlist, and silently wrong for the
# others: you get a valid token for the wrong repository and the push fails in a
# way that looks like a permissions problem.
#
# Hit by micaiahswick-4d27-stinkystars pushing Micaiah's ark-game side project
# while its default stayed stinky-stars. Only 2 agents are multi-repo today
# (stinkystars, dfyhub) — but the failure is silent and the diagnosis is
# non-obvious, which is worth more than the headcount suggests.
#
# Derived from `origin`, not passed as a flag: the repo you are pushing to IS
# the repo you are standing in, so there is nothing for anyone to remember or
# get wrong. Handles both HTTPS and SSH remote forms.
#
# Safe fleet-wide only because every agent now carries an explicit github_repos
# array (backfilled 2026-09-17); an explicit request is matched against that
# list, so a repo you do not own is REFUSED with a clear message rather than
# quietly falling back to a different one.
WANT_REPO=$(git remote get-url origin 2>/dev/null \
  | sed -E 's#^git@github\.com:#https://github.com/#' \
  | sed -E 's#^https://github\.com/##; s#\.git$##' \
  | grep -E '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' || true)
if [[ -n "$WANT_REPO" ]]; then
  REQ_BODY="{\"agent_topic\":\"$AGENT_TOPIC\",\"repo\":\"$WANT_REPO\"}"
  echo "Requesting a token scoped to $WANT_REPO (from origin)"
else
  # No parseable GitHub origin — fall back to the agent's default repo, which is
  # the historical behaviour and correct for a single-repo agent.
  REQ_BODY="{\"agent_topic\":\"$AGENT_TOPIC\"}"
fi

TOKEN=""; REPO=""
for _attempt in $(seq 1 5); do
  RESP=$(curl -sf -X POST http://portal:5000/api/internal/gh-token \
    -H "X-Internal-Key: $INTERNAL_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$REQ_BODY") || { sleep 2; continue; }

  TOKEN=$(echo "$RESP" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("token",""))')
  REPO=$(echo "$RESP"  | python3 -c 'import sys,json;print(json.load(sys.stdin).get("repo",""))')

  if [[ -n "$TOKEN" ]] && [[ -n "$REPO" ]]; then
    PROBE=$(curl -s -o /dev/null -w '%{http_code}' -u "x-access-token:${TOKEN}" \
      "https://github.com/${REPO}.git/info/refs?service=git-receive-pack" || echo "000")
    if [[ "$PROBE" == "200" ]]; then
      [[ $_attempt -gt 1 ]] && echo "  (authenticated on attempt $_attempt)"
      break
    fi
    echo "  attempt $_attempt: token did not authenticate for push (HTTP $PROBE), retrying" >&2
  else
    echo "  attempt $_attempt: broker response missing token or repo, retrying" >&2
  fi

  TOKEN=""
  sleep 2
done

if [[ -z "${TOKEN}" ]] || [[ -z "${REPO}" ]]; then
  echo "ERROR: could not obtain a push-capable token in 5 attempts." >&2
  echo "The token was rejected by GitHub for push (git-receive-pack)." >&2
  echo "Before assuming this agent lost repo access: GitHub answers a bad or" >&2
  echo "under-scoped token with 404, not 403, so 'Repository not found' here" >&2
  echo "means AUTH, not a missing repo. Check the App installation's repo scope" >&2
  echo "and Contents:write permission first; report to Super with the response" >&2
  echo "below (token redacted)." >&2
  echo "$RESP" | sed 's/"token":"[^"]*"/"token":"<redacted>"/' >&2
  exit 2
fi

echo "Pushing $REFSPEC → github.com/$REPO ..."
git push "https://x-access-token:${TOKEN}@github.com/${REPO}.git" "$REFSPEC"
PUSH_RC=${PIPESTATUS[0]}   # The PUSH's own exit status — capture on the VERY next
             # line (the unset below resets $?/PIPESTATUS). PIPESTATUS[0] not $?
             # on purpose: it stays correct even if someone later PIPES the push
             # (e.g. `git push ... | tail`), where $? is the pipe's LAST command
             # and would falsely read 0 on a failed push (PennyBot, 2026-07-27).
             # BOTH `set -euo pipefail` (line ~33) and this guard are load-bearing;
             # keep this push UNPIPED and UNWRAPPED so the guard can't be disarmed.
             # CAVEAT (PennyBot, verified 2026-07-27): PIPESTATUS describes the
             # pipeline of the statement JUST run, in THIS shell — read it on the
             # VERY next statement, NOTHING between (any intervening command clobbers
             # it to 0 = fires the guard = false "synced", the dangerous direction).
             # A bare `PUSH_RC=$(git push …)` is actually fine (the assignment's exit
             # status IS the push's), but `$(git push | tail)` or a HELPER that runs
             # the pipeline internally while the CALLER reads PIPESTATUS both collapse
             # to the outer status (0) and re-arm the bug. If you wrap the push in a
             # helper, capture ${PIPESTATUS[0]} INSIDE the helper and `return` it.

# Scrub token from environment + this shell's variables so it can't leak via
# subsequent commands, $HISTFILE, or process listings.
unset TOKEN RESP

# Keep the local tracking ref honest. Ad-hoc HTTPS pushes never advance
# refs/remotes/origin/<branch>, and `git fetch origin` fails on SSH-configured
# remotes (no SSH key in the container — see the header; NOT a blocked port,
# corrected 2026-07-31) — so the tracking ref goes chronically
# stale, and the pre-push divergence gate ends up comparing against history:
# false "diverged" blocks, and a behind-check that protects nothing
# (Max, 2026-07-05).
# NEVER `git push --force`/`--force-with-lease` to "resolve" an apparent
# "ahead N"/divergence read off a stale ref — it overwrites good history. Check
# the TRUE remote with `git ls-remote origin <branch>`, not the local tracking
# ref. (PennyBot read a false "ahead 41"; Growth hit the same, 2026-07-27.)
#
# ...BUT THE REMOTE CAN ALSO LIE, BRIEFLY (daniel-health, 2026-07-31). For a few
# seconds after a successful push, GitHub's read path can still serve the PREVIOUS
# sha: push output said 9d304f9, `GET /commits/main` said b11f84ba, and the local
# tracking ref said 8bc6292 — three sources, three answers, at once. A re-query
# cleared it. This window opens at exactly the moment an agent will ask, which is
# right after pushing, and a stale read there is INDISTINGUISHABLE from a push
# that silently failed. The instinctive "fixes" are re-push and --force, and both
# are wrong. So: RE-QUERY before concluding anything, prefer
# `/git/refs/heads/<branch>` and `/commits/<branch>` agreeing with each other, and
# never let a disagreement in this window justify a force push.
#
# CRITICAL — only advance the ref after a CONFIRMED successful push (PUSH_RC=0).
# Running update-ref after a FAILED push would falsely report "synced" and HIDE
# real unpushed work — the opposite, MORE dangerous failure (PennyBot, 2026-07-27).
# The ${PUSH_RC:-1} default means "skip if we somehow didn't capture a success".
# >>> tracking-ref-block >>>  (verify-tracking-ref.sh extracts + runs THIS block in a throwaway repo — an anchor marks LOCATION, not correctness; keep both)
SRC="${REFSPEC%%:*}"; DST="${REFSPEC#*:}"
SRC="${SRC#+}"   # strip a leading '+' from a force refspec (+HEAD:main) or rev-parse fails and the whole block skips silently
if [[ "${PUSH_RC:-1}" -eq 0 ]] && PUSHED_SHA=$(git rev-parse --verify "${SRC}^{commit}" 2>/dev/null); then
  # Bind the "synced" report to the ACTUAL outcome of update-ref. A bare
  # `|| true` + unconditional echo re-creates the exact false-"synced" this
  # block exists to kill: update-ref can still fail (e.g. a ref/dir conflict)
  # and the echo would report a sync that never happened (allfiber, 2026-07-28).
  if git update-ref "refs/remotes/origin/${DST}" "$PUSHED_SHA" 2>/dev/null; then
    echo "Tracking ref refs/remotes/origin/${DST} → ${PUSHED_SHA:0:10}"
  else
    # Push LANDED (PUSH_RC=0); only local tracking-ref bookkeeping failed. Warn,
    # but keep exit 0 — a non-zero here would falsely report the good push as
    # failed (phantom-unshipped from the other side).
    echo "WARN: push landed but tracking ref refs/remotes/origin/${DST} NOT updated (update-ref failed) — trust 'git ls-remote origin ${DST}'" >&2
  fi
fi
# <<< tracking-ref-block <<<

# Optional: trigger a Vercel deploy hook after a successful push.
#
# Why this exists: Vercel projects with gitForkProtection=true silently
# refuse to deploy commits authored by external GitHub Apps (including
# agent-hub[bot] — the identity this broker pushes under). The push lands
# on GitHub but no deployment runs. A scoped Vercel Deploy Hook is the
# clean workaround that keeps fork protection ON for security while
# letting the agent's own pushes deploy. Diagnosed on InVelocity 2026-05-28.
#
# To enable per-project:
#   1. Vercel Dashboard → Project → Settings → Git → Deploy Hooks → Create.
#      Pick the production branch. Copy the URL.
#   2. Add to the agent's env vars (DB):
#        VERCEL_DEPLOY_HOOK_URL=https://api.vercel.com/v1/integrations/deploy/prj_.../...
#      The URL is a scoped secret — it only triggers a deploy of THIS
#      project's THIS branch. Store via tenant_agents.resource_limits.env_vars.
#   3. The next push that uses this script will POST to the hook.
#
# Skipped silently if the env var is unset, so unaffected projects don't
# need to change anything.
if [[ -n "${VERCEL_DEPLOY_HOOK_URL:-}" ]]; then
  echo "Triggering Vercel deploy hook..."
  if HOOK_RESP=$(curl -sfS -X POST "$VERCEL_DEPLOY_HOOK_URL" 2>&1); then
    JOB_ID=$(echo "$HOOK_RESP" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("job",{}).get("id","?"))' 2>/dev/null || echo "?")
    echo "Vercel deploy queued (job $JOB_ID)."
  else
    echo "WARNING: Vercel deploy hook failed: $HOOK_RESP" >&2
    echo "Push succeeded — check Vercel dashboard or re-trigger manually." >&2
  fi
fi

echo "Done."
