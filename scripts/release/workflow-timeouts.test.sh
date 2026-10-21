#!/usr/bin/env bash
# Every job in the release workflows has a time limit, so a hung simulator or
# emulator fails in minutes, not after GitHub's six-hour default
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fails=0
for wf in .github/workflows/publish.yml .github/workflows/release-please.yml; do
  if ! missing=$(ruby -ryaml -e '
    wf = YAML.load_file(ARGV[0])
    puts wf["jobs"].reject { |_, j| j.key?("timeout-minutes") }.keys
  ' "$wf" 2>&1); then
    echo "FAIL $wf: could not parse: $missing"; fails=$((fails + 1)); continue
  fi
  if [ -z "$missing" ]; then echo "ok   $wf: every job has timeout-minutes"; else echo "FAIL $wf: no timeout-minutes on: $missing"; fails=$((fails + 1)); fi
done
# Every job that checks out code uses the one commit the resolve
# job recorded, so a run never mixes two commits
wf=.github/workflows/publish.yml
if ! unpinned=$(ruby -ryaml -e '
  wf = YAML.load_file(ARGV[0])
  wf["jobs"].each do |name, job|
    next if name == "resolve"
    (job["steps"] || []).each do |step|
      next unless step["uses"].to_s.start_with?("actions/checkout@")
      pinned = step.dig("with", "ref") == "${{ needs.resolve.outputs.sha }}"
      # Without resolve in needs, the output reads as empty and checkout falls
      # back to the default ref without saying so
      puts name unless pinned && Array(job["needs"]).include?("resolve")
    end
  end
' "$wf" 2>&1); then
  echo "FAIL $wf: could not parse: $unpinned"; fails=$((fails + 1))
elif [ -z "$unpinned" ]; then
  echo "ok   $wf: every build checkout uses the resolved commit"
else
  echo "FAIL $wf: checkouts not pinned to the resolved commit in: $unpinned"; fails=$((fails + 1))
fi

# Release mode: only the publish job holds the npm environment and the OIDC
# token, it always publishes with provenance, the jobs that write to GitHub
# wait on the release environment, and every release job runs only when the
# mode job says so. The summary job must never wait on an approval
if ! release=$(ruby -ryaml -e '
  wf = YAML.load_file(ARGV[0])
  jobs = wf["jobs"]
  env = ->(job) { e = job["environment"]; e.is_a?(Hash) ? e["name"] : e }
  problems = []
  %w[publish confirm finish-release release-docs mark-not-published summary].each do |name|
    problems << "#{name} is missing" unless jobs.key?(name)
  end
  if (pub = jobs["publish"])
    problems << "publish has no environment: npm" unless env.(pub) == "npm"
    problems << "publish has no id-token: write" unless (pub["permissions"] || {})["id-token"] == "write"
    lines = (pub["steps"] || []).flat_map { |s| s["run"].to_s.lines }.select { |l| l =~ /\bnpm publish\b/ }
    problems << "publish runs no npm publish" if lines.empty?
    lines.each { |l| problems << "publish runs npm publish without --provenance" unless l.include?("--provenance") }
  end
  %w[finish-release release-docs mark-not-published].each do |name|
    next unless jobs[name]
    problems << "#{name} has no environment: release" unless env.(jobs[name]) == "release"
  end
  %w[publish confirm finish-release release-docs].each do |name|
    next unless jobs[name]
    problems << "#{name} has no if naming needs.mode.outputs.mode" unless jobs[name]["if"].to_s.include?("needs.mode.outputs.mode")
  end
  problems << "summary declares an environment" if jobs["summary"]&.key?("environment")
  jobs.each do |name, job|
    next if name == "publish"
    problems << "#{name} has environment: npm" if env.(job) == "npm"
    problems << "#{name} has id-token: write" if job["permissions"].is_a?(Hash) && job["permissions"]["id-token"] == "write"
    problems << "#{name} runs npm publish" if (job["steps"] || []).any? { |s| s["run"].to_s =~ /\bnpm publish\b/ }
  end
  # The summary decides the result of the run, so a job left out of its needs
  # could fail without failing the run
  if (summary = jobs["summary"])
    covered = Array(summary["needs"])
    (jobs.keys - %w[summary mark-not-published] - covered).each do |name|
      problems << "summary does not need #{name}"
    end
  end
  # The default run shell has no pipefail, so a node script piped into tee
  # would fail without failing its step
  jobs.each do |name, job|
    (job["steps"] || []).each do |s|
      run = s["run"].to_s
      next unless run =~ /\|\s*tee\b/ && run =~ /\bnode\b/
      problems << "#{name} pipes node into tee without shell: bash" unless s["shell"] == "bash"
    end
  end
  puts problems
' "$wf" 2>&1); then
  echo "FAIL $wf: could not parse: $release"; fails=$((fails + 1))
elif [ -z "$release" ]; then
  echo "ok   $wf: release jobs hold the right environments, permissions, and mode gates"
else
  while IFS= read -r line; do echo "FAIL $wf: $line"; done <<< "$release"
  fails=$((fails + 1))
fi

# The mode seam: only the mode job's decision lets publish run, and that
# decision reads the run's own identity, never a value a caller can set
if ! seam=$(ruby -ryaml -e '
  wf = YAML.load_file(ARGV[0])
  jobs = wf["jobs"]
  problems = []
  pub = jobs["publish"] || {}
  cond = pub["if"].to_s.strip
  # A status function such as always() would let publish run past a failed or
  # skipped mode job, so the condition is pinned exactly
  problems << "publish if is not exactly needs.mode.outputs.mode == release: #{cond}" unless cond == "needs.mode.outputs.mode == '\''release'\''"
  problems << "publish if calls a status function: #{cond}" if cond =~ /\b(always|failure|success|cancelled)\s*\(/
  mode = (jobs.dig("mode", "steps") || []).find { |s| s["id"] == "mode" }
  expected = {
    "ACTOR_ID" => "${{ github.actor_id }}",
    "REF_TYPE" => "${{ github.ref_type }}",
    "REF_NAME" => "${{ github.ref_name }}",
    "RESOLVED_SHA" => "${{ needs.resolve.outputs.sha }}",
    "RUN_SHA" => "${{ github.sha }}",
  }
  if mode.nil?
    problems << "the mode job has no step with id: mode"
  else
    problems << "the mode step does not run release-mode.mjs" unless mode["run"].to_s.include?("scripts/release/react-native/release-mode.mjs")
    got = mode["env"] || {}
    problems << "the mode step env is not exactly #{expected.inspect}: #{got.inspect}" unless got == expected
  end
  # The tarball must carry the version the mode job decided, checked after
  # the package is verified and before the registry is read or written
  steps = pub["steps"] || []
  verify = steps.index { |s| s["run"].to_s.include?("sha256sum -c") }
  version = steps.index do |s|
    run = s["run"].to_s
    run.include?("pkg/react-native.tgz") && run.include?("package/package.json") &&
      (s["env"] || {}).values.include?("${{ needs.mode.outputs.version }}")
  end
  state = steps.index { |s| s["run"].to_s.include?("registry.mjs state") }
  publish = steps.index { |s| s["run"].to_s =~ /\bnpm publish\b/ }
  if version.nil?
    problems << "publish has no step that checks the tarball version against needs.mode.outputs.version"
  else
    problems << "the tarball version step does not use shell: bash" unless steps[version]["shell"] == "bash"
    problems << "the tarball version step does not come after the SHA-256 verification" unless verify && verify < version
    problems << "the tarball version step does not come before the registry state step" unless state && version < state
    problems << "the tarball version step does not come before npm publish" unless publish && version < publish
  end
  puts problems
' "$wf" 2>&1); then
  echo "FAIL $wf: could not parse: $seam"; fails=$((fails + 1))
elif [ -z "$seam" ]; then
  echo "ok   $wf: publish runs only on the mode decision, which reads the run identity and the tarball version"
else
  while IFS= read -r line; do echo "FAIL $wf: $line"; done <<< "$seam"
  fails=$((fails + 1))
fi

# Only these secrets exist for the release workflows, so any other name reads
# as empty and fails at run time instead of here
allowed=' RELEASE_APP_CLIENT_ID RELEASE_APP_KEY DISPATCH_APP_CLIENT_ID DISPATCH_APP_KEY GITHUB_TOKEN '
for f in .github/workflows/publish.yml .github/workflows/release-please.yml; do
  unknown=''
  for name in $(grep -o -E 'secrets\.[A-Za-z0-9_]+' "$f" | sed 's/^secrets\.//' | sort -u); do
    case "$allowed" in
      *" $name "*) ;;
      *) unknown="${unknown:+$unknown, }$name" ;;
    esac
  done
  if [ -z "$unknown" ]; then
    echo "ok   $f: every secret it reads exists"
  else
    echo "FAIL $f: reads secrets that do not exist: $unknown"; fails=$((fails + 1))
  fi
done

# release-please opens release PRs and tags on a push to main, then starts
# publish.yml on the new tag. A manual run re-dispatches an existing tag
rp=.github/workflows/release-please.yml
if ! rpout=$(ruby -ryaml -e '
  wf = YAML.load_file(ARGV[0])
  problems = []
  # The job asks for its token permissions through the App, so GITHUB_TOKEN
  # holds none
  problems << "top-level permissions is not {}" unless wf.key?("permissions") && wf["permissions"] == {}
  pin = "googleapis/release-please-action@45996ed1f6d02564a971a2fa1b5860e934307cf7"
  steps = (wf["jobs"] || {}).values.flat_map { |j| j["steps"] || [] }
  rp_steps = steps.select { |s| s["uses"].to_s.start_with?("googleapis/release-please-action@") }
  problems << "runs no release-please-action" if rp_steps.empty?
  rp_steps.each do |s|
    problems << "release-please-action is not pinned to the v5.0.0 SHA: #{s["uses"]}" unless s["uses"] == pin
    problems << "the release-please step has no id: rp" unless s["id"] == "rp"
    # A manual run only re-dispatches, so it must never cut a release
    problems << "the release-please step does not run only on push" unless s["if"].to_s.strip == "github.event_name == '\''push'\''"
  end
  dispatch = steps.select { |s| s["run"].to_s.include?("actions/workflows/publish.yml/dispatches") }
  problems << "no step dispatches publish.yml" if dispatch.empty?
  dispatch.each do |s|
    cond = s["if"].to_s.strip
    # Without always() a release-please step that fails after reporting its
    # release would skip the dispatch and leave a tag that nothing publishes
    problems << "the dispatch if does not start with always()" unless cond.start_with?("always()")
    problems << "the dispatch if does not name sdks/react-native/coproduct--release_created" unless cond.include?("sdks/react-native/coproduct--release_created")
    # On a push the tag comes from the output for this package, never another
    tag_src = (s["env"] || {})["TAG"].to_s
    problems << "the dispatch TAG does not name sdks/react-native/coproduct--tag_name" unless tag_src.include?("sdks/react-native/coproduct--tag_name")
    run = s["run"].to_s
    # publish.yml releases only on a tag ref, so the tag must be the ref and
    # never an input
    problems << "the dispatch does not pass ref=\"$TAG\"" unless run.include?("ref=\"$TAG\"")
    problems << "the dispatch sends an inputs[ field" if run.include?("inputs[")
    problems << "the dispatch does not check the tag format" unless run.include?("^react-native-v[0-9]+\\.[0-9]+\\.[0-9]+$")
  end
  # Expressions reach a shell only through env, never spliced into the script
  steps.each do |s|
    problems << "a run script contains ${{ }}: #{s["name"] || s["id"] || s["run"].to_s.lines.first}" if s["run"].to_s.include?("${{")
  end
  puts problems
' "$rp" 2>&1); then
  echo "FAIL $rp: could not parse: $rpout"; fails=$((fails + 1))
elif [ -z "$rpout" ]; then
  echo "ok   $rp: release-please is pinned and dispatches publish.yml on the tag ref"
else
  while IFS= read -r line; do echo "FAIL $rp: $line"; done <<< "$rpout"
  fails=$((fails + 1))
fi

# github.triggering_actor changes when someone re-runs a job, so the release
# decision reads github.actor_id, which stays the original dispatcher
for f in .github/workflows/*.yml; do
  if grep -n -F 'triggering_actor' "$f"; then
    echo "FAIL $f: uses github.triggering_actor"; fails=$((fails + 1))
  else
    echo "ok   $f: never reads github.triggering_actor"
  fi
done

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
