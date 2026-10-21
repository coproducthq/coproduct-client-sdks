#!/usr/bin/env bash
# Every job in the release workflows has a time limit, so a hung simulator or
# emulator fails in minutes, not after GitHub's six-hour default
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fails=0
for wf in .github/workflows/publish.yml; do
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

# Only these secrets exist for the publish workflow, so any other name reads
# as empty and fails at run time instead of here
allowed=' RELEASE_APP_CLIENT_ID RELEASE_APP_KEY DISPATCH_APP_CLIENT_ID DISPATCH_APP_KEY GITHUB_TOKEN '
unknown=''
for name in $(grep -o -E 'secrets\.[A-Za-z0-9_]+' "$wf" | sed 's/^secrets\.//' | sort -u); do
  case "$allowed" in
    *" $name "*) ;;
    *) unknown="${unknown:+$unknown, }$name" ;;
  esac
done
if [ -z "$unknown" ]; then
  echo "ok   $wf: every secret it reads exists"
else
  echo "FAIL $wf: reads secrets that do not exist: $unknown"; fails=$((fails + 1))
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
