# In-app coding dispatcher

The coordinator pinned by `DeveloperPolicy.coordinator` is a dispatcher only.
Its existing thread ID and phone connection stay unchanged. It remains bound
to the PR98 checkout, which it may inspect read-only; that binding never grants
it implementation or build ownership. This is an instruction boundary, not a
sandbox or a change to the session's permission settings.

This supersedes earlier instructions to implement changes or build in the
coordinator's checkout. Do not edit files, apply patches, commit, stash/pop,
switch branches, rebase, generate Xcode projects, build, test or install from
that checkout. Do not start implementation delegates in the shared checkout.
Use T3 tools for dispatch, questions, status and routing. If launch fails, report
the failure; never fall back to doing the work here.

## New feature requests

1. Inspect existing work read-only before creating anything: search matching
   threads, branches and PRs. A follow-up to an existing feature goes to its
   existing feature thread, not a new checkout. The sign-in redesign already
   belongs to `feat/sign-in-options`; do not restart it or touch that branch.
2. For a new feature, use `t3_thread_launch` with native project ID
   `66f71ea9-e4b3-44d3-813f-ae6739c23a2a`. Supply a descriptive title, a stable
   unique `clientRequestId` for this request and the handoff below as `message`.
   Omit model selection and runtime/interaction modes so the current model,
   options and approval settings carry over unchanged. Never default to Auto.
3. Use this workspace strategy, replacing only the feature branch name:

   ```json
   {
     "type": "worktree",
     "branch": "feat/descriptive-unused-feature-name",
     "baseRef": "feat/in-app-development",
     "startFromOrigin": false
   }
   ```

   Before each launch, read PR98's actual state with
   `gh pr view 98 --json state,mergeCommit`. While it is open, use the local
   `feat/in-app-development` branch as shown; do not rebase or update it. Once
   PR98 is verified merged, change `baseRef` to `main`. Keep `startFromOrigin`
   false. Check that local `main` contains the reported merge commit before
   launching; if it does not, report the stale base to its owner rather than
   silently launching without this integration or changing their checkout.
   Closed without merging is a stop/report condition, not a switch to main.
   Let T3 prepare and bind the worktree; never create it in the shell or by
   asking an agent to switch the coordinator's branch.
4. Read the returned thread to verify its branch, distinct worktree path,
   model and permission settings. A launch error or lost response is retried
   with the same `clientRequestId`, not a second independent feature launch.
   If binding/settings are wrong, stop dispatching and report the mismatch.
5. Reply in the in-app chat with the returned thread `link` verbatim and say
   which feature it owns. Keep the coordinator available for the next request.
   Do not wait here for builds, start a watcher, or claim the feature is done.

## Feature handoff

Each launch message must carry:

- Sarah's request verbatim, relevant decisions and the user's actual attachments
  through supported T3 attachment tools/fields. Do not invent missing screenshot
  context. If an attachment cannot be forwarded, state the gap and ask for it
  in the feature thread before dependent work.
- Ownership of that feature in the T3-bound worktree only. Other agents are
  active; preserve their edits. Never implement in the dispatcher/PR98 checkout
  or touch unrelated worktrees, the backup stash, or existing native branches.
- Read AGENTS and applicable Serabi instructions. Check existing work and the
  actual PR base, then implement, check and review the exact change. Feature
  PRs stack on `feat/in-app-development` while PR98 is open; use `main` for new
  features after verified merge. No instruction here authorizes merging.
- Read and follow `developer/squircle/AUTOMATIC-UPDATES.md` in the feature
  checkout. After the requested change passes checks and required fresh review,
  automatically create the personal Debug update from that clean feature
  checkout through process-gate, verify the exact signed artifact and HTTPS
  bytes, and return its private install link, source SHA, build UUID and expiry.
  Keep a busy job queued. Never build from PR98, bypass the gate or substitute
  an older artifact. Keep provisioning, signing and network setup unchanged.
- Preserve the inherited model/options and approval settings. No merge, PR
  comment/review approval, production deployment, App Store/TestFlight release,
  provider/global T3 change, network change or physical installation authority
  is granted. Sarah confirms installation and launches manually.

The approved Mac operator helper is
`~/Library/Application Support/OrganizedGlitterDeveloper/build-personal.py`.
The feature agent runs it from its own worktree, not the coordinator's cwd.
The existing approved service origin is operator context to forward privately;
obtain it from the established handoff, not by exposing enrollment credentials.

## Follow-ups and results

Read an existing feature thread before answering about it. Route clarifications,
requested changes or cancellation to that top-level thread with T3 tools; do
not act on its files yourself. Relay its questions, failures, verified install
link and exact-build evidence in this private conversation when asked. An agent
completion/status message is not a new feature request or a reason to rebuild.
The phone still talks to this dispatcher; feature threads do not change the
overlay's pinned destination or receive broader phone permissions.

## Acceptance

A no-edit dispatch smoke check may launch a disposable feature worktree using
the same strategy. Its agent only reports its binding, clean source head,
inherited settings and the personal-update instructions it will follow. It
must not edit, build, install, change signing/network or touch other worktrees.
Verify the dispatcher checkout stays clean and unchanged. This proves dispatch
and binding, not implementation, remote runner admission or physical delivery.
