#!/usr/bin/env bash
# Every job in the release workflows has a time limit, so a hung simulator or
# emulator fails in minutes, not after GitHub's six-hour default
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fails=0
for wf in .github/workflows/publish.yml .github/workflows/publish-flutter.yml .github/workflows/release-please.yml .github/workflows/core-trigger.yml; do
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
for wf in .github/workflows/publish.yml .github/workflows/publish-flutter.yml; do
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
done
wf=.github/workflows/publish.yml

# Release mode: only the publish job holds the npm environment and the OIDC
# token, it always publishes with provenance, the jobs that write to GitHub
# wait on the release environment, and every release job runs only when the
# mode job says so. The summary job must never wait on an environment's protection rules
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

# Only the release automation's tag runs share a group, so a person's checks
# run on a release tag can never displace a pending release run
if ! group=$(ruby -ryaml -e '
  puts YAML.load_file(ARGV[0]).dig("concurrency", "group").to_s
' "$wf" 2>&1); then
  echo "FAIL $wf: could not parse: $group"; fails=$((fails + 1))
elif [ "$group" = "\${{ github.ref_type == 'tag' && github.actor_id == '345134390' && format('publish-react-native-{0}', github.ref_name) || format('publish-checks-{0}', github.run_id) }}" ]; then
  echo "ok   $wf: only the release automation's tag runs share a concurrency group"
else
  echo "FAIL $wf: the concurrency group does not key release runs by the release App and the rest by run: $group"; fails=$((fails + 1))
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

# The Flutter publish workflow holds the same release guarantees as React
# Native's, with pub.dev in place of npm and one sealed tar carried from the
# job that built and tested it to the jobs that verify and publish it
fwf=.github/workflows/publish-flutter.yml
if ! flutter=$(ruby -ryaml -e '
  wf = YAML.load_file(ARGV[0])
  q = "\x27"
  jobs = wf["jobs"] || {}
  env = ->(job) { e = job["environment"]; e.is_a?(Hash) ? e["name"] : e }
  steps_of = ->(name) { (jobs[name] || {})["steps"] || [] }
  needs_of = ->(name) { Array((jobs[name] || {})["needs"]) }
  all_steps = jobs.flat_map { |name, job| (job["steps"] || []).map { |s| [name, s] } }
  problems = []
  %w[resolve mode pipeline verify-package publish confirm finish-release release-docs summary mark-not-published].each do |name|
    problems << "#{name} is missing" unless jobs.key?(name)
  end
  problems << "top-level permissions is not exactly contents: read" unless wf["permissions"] == { "contents" => "read" }

  # Only runs the release automation starts on a tag share a group, so checks
  # a person runs on a release tag can never displace a pending release run
  want_group = "${{ github.ref_type == #{q}tag#{q} && github.actor_id == #{q}345134390#{q} && " \
    "format(#{q}publish-flutter-{0}#{q}, github.ref_name) || format(#{q}publish-flutter-checks-{0}#{q}, github.run_id) }}"
  group = wf.dig("concurrency", "group").to_s
  problems << "the concurrency group is not exactly #{want_group}: #{group}" unless group == want_group
  problems << "concurrency cancels in progress" unless wf.dig("concurrency", "cancel-in-progress") == false

  # The mode seam: only the decision of the mode job lets publish run, and
  # that decision reads the identity of the run, never a value a caller can set
  mode = steps_of.("mode").find { |s| s["id"] == "mode" }
  want_env = {
    "ACTOR_ID" => "${{ github.actor_id }}",
    "REF_TYPE" => "${{ github.ref_type }}",
    "REF_NAME" => "${{ github.ref_name }}",
    "RESOLVED_SHA" => "${{ needs.resolve.outputs.sha }}",
    "RUN_SHA" => "${{ github.sha }}",
  }
  if mode.nil?
    problems << "the mode job has no step with id: mode"
  else
    problems << "the mode step does not run the Flutter release-mode.mjs" unless mode["run"].to_s.include?("scripts/release/flutter/release-mode.mjs")
    problems << "the mode step env is not exactly #{want_env.inspect}: #{(mode["env"] || {}).inspect}" unless mode["env"] == want_env
  end

  # Only publish holds the pub.dev environment and the OIDC token, and it runs
  # only when the mode job says so, with no status function to run it past a
  # failed or skipped job
  pub = jobs["publish"] || {}
  problems << "publish has no environment: pub.dev" unless env.(pub) == "pub.dev"
  problems << "publish permissions are not exactly contents: read and id-token: write" unless pub["permissions"] == { "contents" => "read", "id-token" => "write" }
  cond = pub["if"].to_s.strip
  problems << "publish if is not exactly needs.mode.outputs.mode == release: #{cond}" unless cond == "needs.mode.outputs.mode == #{q}release#{q}"
  problems << "publish does not need verify-package" unless needs_of.("publish").include?("verify-package")
  problems << "publish does not need mode" unless needs_of.("publish").include?("mode")
  jobs.each do |name, job|
    next if name == "publish"
    problems << "#{name} has environment: pub.dev" if env.(job) == "pub.dev"
    problems << "#{name} has id-token: write" if job["permissions"].is_a?(Hash) && job["permissions"]["id-token"] == "write"
  end
  %w[finish-release release-docs mark-not-published].each do |name|
    problems << "#{name} has no environment: release" unless jobs[name] && env.(jobs[name]) == "release"
  end
  %w[publish confirm finish-release release-docs].each do |name|
    problems << "#{name} has no if naming needs.mode.outputs.mode" unless jobs[name] && jobs[name]["if"].to_s.include?("needs.mode.outputs.mode")
  end
  problems << "summary declares an environment" if jobs["summary"]&.key?("environment")
  # verify-package proves the handoff on every run, so a rehearsal exercises it
  problems << "verify-package has an if, so it does not run in every mode" if jobs["verify-package"]&.key?("if")
  problems << "verify-package does not need pipeline" unless needs_of.("verify-package").include?("pipeline")
  problems << "confirm does not need publish" unless needs_of.("confirm").include?("publish")

  # The pipeline uploads the one tar it packed, unarchived and named only by
  # its file, so a download by that name gets exactly that file
  sha_out = "${{ needs.pipeline.outputs.sha256 }}"
  pack = steps_of.("pipeline").find { |s| s["run"].to_s.include?("handoff.sh pack") }
  if pack.nil?
    problems << "pipeline runs no handoff.sh pack"
  else
    out = (jobs["pipeline"]["outputs"] || {})["sha256"].to_s
    problems << "pipeline output sha256 does not come from the handoff.sh pack step" unless pack["id"] && out == "${{ steps.#{pack["id"]}.outputs.sha256 }}"
  end
  uploads = all_steps.select { |_, s| s["uses"].to_s.start_with?("actions/upload-artifact@") }
  tar_uploads = uploads.select { |_, s| s.to_s.include?("flutter-package.tar") }
  if tar_uploads.length != 1
    problems << "#{tar_uploads.length} steps upload flutter-package.tar, not exactly one"
  else
    name, s = tar_uploads.first
    w = s["with"] || {}
    problems << "the tar is uploaded from #{name}, not pipeline" unless name == "pipeline"
    problems << "the tar upload path is not exactly ${{ runner.temp }}/flutter-package.tar: #{w["path"]}" unless w["path"] == "${{ runner.temp }}/flutter-package.tar"
    problems << "the tar upload does not set archive: false" unless w["archive"] == false
    problems << "the tar upload sets name:, which archive: false ignores" if w.key?("name")
    problems << "the tar upload does not fail when the file is missing" unless w["if-no-files-found"] == "error"
  end
  downloads = all_steps.select { |_, s| s["uses"].to_s.start_with?("actions/download-artifact@") }
  problems << "no job downloads the tar" if downloads.empty?
  downloads.each do |name, s|
    w = s["with"] || {}
    problems << "a download in #{name} does not request exactly name: flutter-package.tar" unless w["name"] == "flutter-package.tar" && !w.key?("pattern")
    problems << "a download in #{name} does not go to ${{ runner.temp }}/handoff" unless w["path"] == "${{ runner.temp }}/handoff"
    # Every job that downloads the tar unpacks it through the checked handoff
    unpacks = steps_of.(name).select { |u| u["run"].to_s.include?("handoff.sh unpack") }
    problems << "#{name} downloads the tar but never runs handoff.sh unpack" if unpacks.empty?
  end
  # Each unpack checks the SHA-256 the pipeline recorded and extracts into a
  # new directory, never the one the download wrote the tar into
  want_unpack = "scripts/release/flutter/ci/handoff.sh unpack \"$RUNNER_TEMP/handoff/flutter-package.tar\" \"$PACKAGE_SHA256\" \"$RUNNER_TEMP/package\""
  all_steps.each do |name, s|
    run = s["run"].to_s
    next unless run.include?("handoff.sh unpack")
    problems << "the unpack in #{name} is not exactly #{want_unpack}" unless run.lines.map(&:strip).include?(want_unpack)
    problems << "the unpack in #{name} does not read PACKAGE_SHA256 from the pipeline output" unless (s["env"] || {})["PACKAGE_SHA256"] == sha_out
    problems << "#{name} unpacks without needing pipeline" unless needs_of.(name).include?("pipeline")
  end
  all_steps.each do |name, s|
    problems << "#{name} extracts a tar outside handoff.sh" if s["run"].to_s =~ /\btar\s+-?x/
  end

  # Gate logs live under the runner temp directory, outside the checkout, and
  # a failed pipeline uploads them
  measure = steps_of.("pipeline").find { |s| s["run"].to_s.include?("scripts/release/flutter/measure.sh") }
  if measure.nil?
    problems << "pipeline does not run measure.sh"
  else
    e = measure["env"] || {}
    problems << "measure.sh does not run with COPRODUCT_RELEASE_GATES=ci" unless e["COPRODUCT_RELEASE_GATES"] == "ci"
    %w[COPRODUCT_RELEASE_STAGE COPRODUCT_RELEASE_OUT COPRODUCT_FLUTTER_ARCHIVE_DIR COPRODUCT_CONSUMER_DIR COPRODUCT_GATE_LOG_DIR].each do |k|
      problems << "measure.sh #{k} is not under ${{ runner.temp }}: #{e[k].inspect}" unless e[k].to_s.start_with?("${{ runner.temp }}/")
    end
    problems << "measure.sh has no COPRODUCT_ACCEPTANCE_TIMEOUT_MINUTES" unless e["COPRODUCT_ACCEPTANCE_TIMEOUT_MINUTES"].to_s =~ /\A\d+\z/
    logs = steps_of.("pipeline").find do |s|
      s["uses"].to_s.start_with?("actions/upload-artifact@") && s["if"].to_s.strip == "failure()" &&
        (s["with"] || {})["path"] == e["COPRODUCT_GATE_LOG_DIR"]
    end
    problems << "pipeline does not upload COPRODUCT_GATE_LOG_DIR when it fails" if logs.nil?
  end

  # The OIDC token, its registration with pub, and the publish share one step,
  # so the token exists only where it is used
  pub_steps = steps_of.("publish")
  oidc = pub_steps.select { |s| s["run"].to_s.include?("ACTIONS_ID_TOKEN_REQUEST_URL") }
  if oidc.length != 1
    problems << "#{oidc.length} publish steps request an OIDC token, not exactly one"
  else
    run = oidc.first["run"].to_s
    problems << "the OIDC request does not name audience https://pub.dev" unless run.include?("audience=https://pub.dev")
    problems << "the OIDC token is not masked" unless run.include?("::add-mask::")
    problems << "the OIDC step does not export PUB_TOKEN" unless run =~ /^\s*export PUB_TOKEN\b/
    problems << "the OIDC step does not run flutter pub token add https://pub.dev --env-var PUB_TOKEN" unless run.include?("flutter pub token add https://pub.dev --env-var PUB_TOKEN")
    problems << "the OIDC step does not run scripts/release/flutter/publish.sh --force" unless run.include?("scripts/release/flutter/publish.sh --force")
    %w[already-published mismatch stale retracted].each do |st|
      problems << "the publish step does not handle #{st}" unless run =~ /^\s*#{Regexp.escape(st)}\)/
    end
    problems << "the publish step does not name the runbook" unless run.include?("bad-version runbook in DEVELOPMENT.md")
  end
  # With the OIDC permission, setup-dart mints a pub.dev token and exports it
  # to every later step, so the step right after it drops that token
  drop_run = "dart pub token remove --all\necho \"PUB_TOKEN=\" >> \"$GITHUB_ENV\"\n"
  dart_at = pub_steps.each_index.select { |i| pub_steps[i]["uses"].to_s.start_with?("dart-lang/setup-dart@") }
  drop = nil
  if dart_at.length != 1
    problems << "publish runs setup-dart #{dart_at.length} times, not once"
  else
    drop = pub_steps[dart_at.first + 1]
    problems << "the step after setup-dart in publish does not drop its pub.dev token" unless drop && drop["run"] == drop_run && drop["env"].nil?
  end
  all_steps.each do |name, s|
    next if oidc.include?(s) || s.equal?(drop)
    text = s.to_s
    problems << "a step in #{name} other than the publish step touches the OIDC token" if text.include?("ACTIONS_ID_TOKEN_REQUEST")
    problems << "a step in #{name} other than the publish step uses PUB_TOKEN" if text.include?("PUB_TOKEN")
    problems << "a step in #{name} other than the publish step runs publish.sh" if text.include?("publish.sh")
    problems << "a step in #{name} adds a pub token" if text.include?("pub token add")
    s["run"].to_s.lines.each do |l|
      problems << "a step in #{name} runs pub publish without --dry-run: #{l.strip}" if l =~ /\bpub publish\b/ && !l.include?("--dry-run")
    end
  end
  # Before the registry is read or written, the stage must carry the version
  # the mode job decided
  version = pub_steps.index do |s|
    s["run"].to_s.include?("$RUNNER_TEMP/package/stage/pubspec.yaml") &&
      (s["env"] || {}).values.include?("${{ needs.mode.outputs.version }}")
  end
  state = pub_steps.index { |s| s["run"].to_s.include?("registry.mjs state coproduct") }
  unpack = pub_steps.index { |s| s["run"].to_s.include?("handoff.sh unpack") }
  publish = pub_steps.index { |s| s["run"].to_s.include?("publish.sh --force") }
  if version.nil?
    problems << "publish has no step that checks the stage version against needs.mode.outputs.version"
  else
    problems << "the stage version step does not come after the unpack" unless unpack && unpack < version
    problems << "the stage version step does not come before the registry state step" unless state && version < state
  end
  problems << "the registry state step does not come before the publish" unless state && publish && state < publish
  if state
    problems << "the registry state step does not use shell: bash" unless pub_steps[state]["shell"] == "bash"
    problems << "the registry state step has no id: state" unless pub_steps[state]["id"] == "state"
  end
  problems << "the publish step does not read STATE from steps.state" unless publish && (pub_steps[publish]["env"] || {})["STATE"] == "${{ steps.state.outputs.state }}"

  # verify-package checks the seal and runs the pub dry run on the unpacked stage
  vp = steps_of.("verify-package").map { |s| s["run"].to_s }.join("\n")
  problems << "verify-package does not run verify-seal.sh" unless vp.include?("scripts/release/flutter/verify-seal.sh")
  problems << "verify-package does not run dry-run-check.sh on the stage" unless vp.include?("scripts/release/flutter/ci/dry-run-check.sh \"$RUNNER_TEMP/package/stage\"")
  problems << "confirm does not run registry.mjs confirm coproduct" unless steps_of.("confirm").any? { |s| s["run"].to_s.include?("registry.mjs confirm coproduct \"$VERSION\" \"$RUNNER_TEMP/package/out/seal.txt\"") }

  mv = "${{ needs.mode.outputs.version }}"
  fr = steps_of.("finish-release").find { |s| s["run"].to_s.include?("gh release edit") }
  if fr.nil?
    problems << "finish-release runs no gh release edit"
  else
    problems << "finish-release does not set --draft=false --title \"flutter: v$VERSION\"" unless fr["run"].to_s.include?("--draft=false --title \"flutter: v$VERSION\"")
    problems << "finish-release VERSION is not the mode version" unless (fr["env"] || {})["VERSION"] == mv
  end
  mnp = steps_of.("mark-not-published").find { |s| s["run"].to_s.include?("gh release edit") }
  problems << "mark-not-published does not set the not-published title" unless mnp && mnp["run"].to_s.include?("--title \"flutter: v$VERSION (not published)\"")
  problems << "mark-not-published does not run only on the summary action" unless jobs.dig("mark-not-published", "if").to_s.strip == "always() && needs.summary.outputs.action == #{q}mark-not-published#{q}"
  docs = steps_of.("release-docs").find { |s| s["run"].to_s.include?("sdk-docs-release.yml/dispatches") }
  if docs.nil?
    problems << "release-docs dispatches no sdk-docs-release.yml"
  else
    run = docs["run"].to_s
    problems << "release-docs does not pass sdk=flutter" unless run.include?("-f \x27inputs[sdk]=flutter\x27")
    problems << "release-docs does not pass the version" unless run.include?("-f \"inputs[version]=$VERSION\"")
    problems << "release-docs VERSION is not the mode version" unless (docs["env"] || {})["VERSION"] == mv
    problems << "release-docs does not watch the run" unless run.include?("gh run watch")
  end
  wait = steps_of.("release-docs").find { |s| s["run"].to_s.include?("registry.mjs latest coproduct") }
  problems << "release-docs does not wait for pub.dev to serve the version as latest" unless wait && steps_of.("release-docs").index(wait) < steps_of.("release-docs").index(docs).to_i

  # The summary decides the result of the run, so a job left out of its needs
  # could fail without failing the run
  summary = jobs["summary"] || {}
  problems << "summary does not run checks-result.sh" unless steps_of.("summary").any? { |s| s["run"].to_s.include?("scripts/release/checks-result.sh") }
  problems << "summary does not run the Flutter finalize.mjs" unless steps_of.("summary").any? { |s| s["run"].to_s.include?("scripts/release/flutter/finalize.mjs") }
  problems << "summary if is not always()" unless summary["if"].to_s.strip == "always()"
  (jobs.keys - %w[summary mark-not-published] - needs_of.("summary")).each { |name| problems << "summary does not need #{name}" }
  (needs_of.("summary") - jobs.keys).each { |name| problems << "summary needs #{name}, which does not exist" }

  # Every step that pipes runs under bash, whose pipefail lets a failure
  # anywhere in the pipe fail the step
  all_steps.each do |name, s|
    run = s["run"].to_s
    next unless run.gsub("||", "") =~ /\|/
    problems << "a step in #{name} pipes without shell: bash: #{s["name"] || s["id"] || run.lines.first.strip}" unless s["shell"] == "bash"
  end
  # Expressions reach a shell only through env, never spliced into the script
  all_steps.each do |name, s|
    problems << "a run script in #{name} contains ${{ }}: #{s["name"] || s["id"] || s["run"].to_s.lines.first}" if s["run"].to_s.include?("${{")
  end
  puts problems
' "$fwf" 2>&1); then
  echo "FAIL $fwf: could not parse: $flutter"; fails=$((fails + 1))
elif [ -z "$flutter" ]; then
  echo "ok   $fwf: publishes only on the mode decision, from the one sealed tar, through pub.dev OIDC"
else
  while IFS= read -r line; do echo "FAIL $fwf: $line"; done <<< "$flutter"
  fails=$((fails + 1))
fi

# Only these secrets exist for the release workflows, so any other name reads
# as empty and fails at run time instead of here
allowed=' RELEASE_APP_CLIENT_ID RELEASE_APP_KEY DISPATCH_APP_CLIENT_ID DISPATCH_APP_KEY SDK_CORE_TRIGGER_APP_CLIENT_ID SDK_CORE_TRIGGER_APP_KEY GITHUB_TOKEN '
for f in .github/workflows/publish.yml .github/workflows/publish-flutter.yml .github/workflows/release-please.yml .github/workflows/core-trigger.yml; do
  if [ ! -f "$f" ]; then
    echo "FAIL $f: does not exist"; fails=$((fails + 1)); continue
  fi
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
# each package's publish workflow on its new tag. A manual run re-dispatches an
# existing tag, and only to the workflow its tag prefix names
rp=.github/workflows/release-please.yml
if ! rpout=$(ruby -ryaml -e '
  wf = YAML.load_file(ARGV[0])
  q = "\x27"
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
    problems << "the release-please step does not run only on push" unless s["if"].to_s.strip == "github.event_name == #{q}push#{q}"
  end
  token_steps = steps.select { |s| s["uses"].to_s.start_with?("actions/create-github-app-token@") }
  by_id = token_steps.to_h { |s| [s["id"], s] }
  perms = ->(s) { (s["with"] || {}).select { |k, _| k.start_with?("permission-") } }
  ref = ->(text) { text.to_s[/\A\$\{\{\s*steps\.([A-Za-z0-9_-]+)\.outputs\.token\s*\}\}\z/, 1] }
  rp_ids = rp_steps.map { |r| ref.((r["with"] || {})["token"]) }
  # release-please-action is third-party code, so its token cannot start
  # workflows
  rp_steps.each do |s|
    tok = by_id[ref.((s["with"] || {})["token"])]
    if tok.nil?
      problems << "the release-please token does not come from an App token step"
      next
    end
    want = { "permission-contents" => "write", "permission-pull-requests" => "write", "permission-issues" => "write" }
    problems << "the release-please token permissions are not exactly #{want.inspect}: #{perms.(tok).inspect}" unless perms.(tok) == want
  end
  packages = [
    { "path" => "sdks/react-native/coproduct", "workflow" => "publish.yml", "prefix" => "react-native-v" },
    { "path" => "sdks/flutter/coproduct", "workflow" => "publish-flutter.yml", "prefix" => "flutter-v" },
  ]
  packages.each do |pkg|
    path, workflow, prefix = pkg.values_at("path", "workflow", "prefix")
    dispatch = steps.select { |s| s["run"].to_s.include?("actions/workflows/#{workflow}/dispatches") }
    problems << "no step dispatches #{workflow}" if dispatch.empty?
    problems << "more than one step dispatches #{workflow}" if dispatch.length > 1
    dispatch.each do |s|
      cond = s["if"].to_s.strip
      # always() lets a release-please step that fails after reporting its
      # release still dispatch. A manual run dispatches only the workflow its
      # tag prefix names, so it never starts the publish of the other package
      want_cond = "always() && (steps.rp.outputs[#{q}#{path}--release_created#{q}] == #{q}true#{q} || " \
        "(github.event_name == #{q}workflow_dispatch#{q} && startsWith(inputs.tag, #{q}#{prefix}#{q})))"
      problems << "the #{workflow} dispatch if is not exactly #{want_cond}: #{cond}" unless cond == want_cond
      # On a push the tag comes from the output for this package, never another
      want_tag = "${{ github.event_name == #{q}workflow_dispatch#{q} && inputs.tag || steps.rp.outputs[#{q}#{path}--tag_name#{q}] }}"
      tag_src = (s["env"] || {})["TAG"].to_s
      problems << "the #{workflow} dispatch TAG is not exactly #{want_tag}: #{tag_src}" unless tag_src == want_tag
      run = s["run"].to_s
      # The publish workflow releases only on a tag ref, so the tag must be the
      # ref and never an input
      problems << "the #{workflow} dispatch does not pass ref=\"$TAG\"" unless run.include?("ref=\"$TAG\"")
      problems << "the #{workflow} dispatch sends an inputs[ field" if run.include?("inputs[")
      problems << "the #{workflow} dispatch does not check the tag format" unless run.include?("^#{prefix}[0-9]+\\.[0-9]+\\.[0-9]+$")
      # An unchecked tag could carry a newline into a workflow command, so the
      # format check comes first and nothing prints the raw value before it
      lines = run.lines
      check = lines.index { |l| l.include?("^#{prefix}[0-9]+") }
      if check
        lines[0...check].each { |l| problems << "the #{workflow} dispatch uses TAG before checking its format: #{l.strip}" if l.include?("TAG") }
        lines[(check + 1)..].take_while { |l| l.strip != "fi" }.each do |l|
          problems << "the #{workflow} dispatch prints an unchecked TAG without printf %q: #{l.strip}" if l.include?("TAG") && !l.include?("%q")
        end
      end
      # A second token that can only start workflows goes to the dispatch step
      # alone, minted just before it under the same condition
      id = ref.((s["env"] || {})["GH_TOKEN"])
      tok = by_id[id]
      if tok.nil?
        problems << "the #{workflow} dispatch token does not come from an App token step"
        next
      end
      want = { "permission-actions" => "write", "permission-contents" => "read" }
      problems << "the #{workflow} dispatch token permissions are not exactly #{want.inspect}: #{perms.(tok).inspect}" unless perms.(tok) == want
      problems << "the #{workflow} dispatch shares the release-please token" if rp_ids.include?(id)
      problems << "the #{workflow} dispatch token step does not run under the dispatch condition" unless tok["if"].to_s.strip == cond
      problems << "the #{workflow} dispatch token step is not the step just before the dispatch" unless steps.index(tok) == steps.index(s) - 1
      # The publish workflows release only for this App, so the dispatch token
      # is minted from it
      problems << "the #{workflow} dispatch token is not minted from the release App" unless (tok["with"] || {})["client-id"] == "${{ secrets.RELEASE_APP_CLIENT_ID }}"
      others = steps.reject { |o| o.equal?(s) }.select { |o| o.to_s.include?("steps.#{id}.outputs.token") }
      problems << "a step other than the #{workflow} dispatch uses its token" unless others.empty?
    end
  end
  # The Flutter pair follows the React Native pair, so the React Native steps
  # keep the order they had before Flutter joined
  rn = steps.index { |s| s["run"].to_s.include?("actions/workflows/publish.yml/dispatches") }
  fl_token = steps.index { |s| s["id"] == "flutter-dispatch-token" }
  problems << "the Flutter dispatch token step does not come right after the React Native dispatch" unless rn && fl_token == rn + 1
  # A manual run whose tag has neither prefix starts nothing, so it must fail
  # rather than end green
  want_refuse = "github.event_name == #{q}workflow_dispatch#{q} && !startsWith(inputs.tag, #{q}react-native-v#{q}) && !startsWith(inputs.tag, #{q}flutter-v#{q})"
  refuse = steps.find { |s| s["if"].to_s.strip == want_refuse }
  problems << "no step fails a manual run whose tag has neither prefix" unless refuse && refuse["run"].to_s =~ /^\s*exit 1\s*$/
  # Expressions reach a shell only through env, never spliced into the script
  steps.each do |s|
    problems << "a run script contains ${{ }}: #{s["name"] || s["id"] || s["run"].to_s.lines.first}" if s["run"].to_s.include?("${{")
  end
  puts problems
' "$rp" 2>&1); then
  echo "FAIL $rp: could not parse: $rpout"; fails=$((fails + 1))
elif [ -z "$rpout" ]; then
  echo "ok   $rp: release-please is pinned and dispatches each publish workflow on its tag ref"
else
  while IFS= read -r line; do echo "FAIL $rp: $line"; done <<< "$rpout"
  fails=$((fails + 1))
fi

# The core trigger bot runs on pull_request_target with secrets in reach, so
# PR code never runs, the App token reaches only the push, and every
# expression reaches a shell only through env
cf=.github/workflows/core-trigger.yml
if [ ! -f "$cf" ]; then
  echo "FAIL $cf: does not exist"; fails=$((fails + 1))
elif ! ctout=$(ruby -ryaml -e '
  wf = YAML.load_file(ARGV[0])
  raw = File.read(ARGV[0])
  q = "\x27"
  problems = []
  # Psych reads a bare on: key as true
  on = wf["on"] || wf[true] || {}
  if on.is_a?(Hash) && on.keys == ["pull_request_target"]
    prt = on["pull_request_target"] || {}
    problems << "pull_request_target types are not opened, synchronize, reopened, and edited: #{prt["types"].inspect}" unless prt["types"] == %w[opened synchronize reopened edited]
    problems << "pull_request_target branches are not main only: #{prt["branches"].inspect}" unless prt["branches"] == ["main"]
  else
    problems << "on is not exactly pull_request_target: #{on.inspect}"
  end
  want_perms = { "contents" => "read", "pull-requests" => "write" }
  problems << "top-level permissions are not exactly #{want_perms.inspect}: #{wf["permissions"].inspect}" unless wf["permissions"] == want_perms
  # The bot push fires synchronize while its own run is going, and canceling
  # that run would lose the comment
  want_conc = { "group" => "core-trigger-${{ github.event.pull_request.number }}", "cancel-in-progress" => false }
  problems << "concurrency is not exactly #{want_conc.inspect}: #{wf["concurrency"].inspect}" unless wf["concurrency"] == want_conc
  # Workflow or job env would put a value in every step, and job permissions
  # would replace the read-only default token, so neither level has them
  problems << "the workflow sets env" if wf.key?("env")
  want_top = ["name", true, "permissions", "concurrency", "jobs"]
  problems << "the workflow keys are not exactly name, on, permissions, concurrency, and jobs: #{wf.keys.inspect}" unless wf.keys.sort_by(&:to_s) == want_top.sort_by(&:to_s)
  jobs = wf["jobs"] || {}
  problems << "the jobs are not exactly trigger: #{jobs.keys.inspect}" unless jobs.keys == ["trigger"]
  job = jobs["trigger"] || {}
  problems << "the trigger job sets env" if job.key?("env")
  problems << "the trigger job sets permissions: #{job["permissions"].inspect}" if job.key?("permissions")
  want_job = %w[name if runs-on environment timeout-minutes steps]
  problems << "the trigger job keys are not exactly #{want_job.join(", ")}: #{job.keys.inspect}" unless job.keys.sort == want_job.sort
  # The bot push fires synchronize again, so the run it starts is skipped
  want_if = "github.event.pull_request.head.repo.full_name == github.repository && github.event.pull_request.state == #{q}open#{q} && github.event.pull_request.user.login != #{q}dependabot[bot]#{q} && github.actor != #{q}coproduct-sdk-core-trigger[bot]#{q}"
  problems << "the trigger job if is not exactly #{want_if}: #{job["if"]}" unless job["if"].to_s.strip == want_if
  want_env = { "name" => "sdk-core-trigger", "deployment" => false }
  problems << "the trigger job environment is not exactly #{want_env.inspect}: #{job["environment"].inspect}" unless job["environment"] == want_env
  steps = job["steps"] || []
  label = ->(s) { s["name"] || s["id"] || s["uses"] || s["run"].to_s.lines.first.to_s.strip }

  # Checkouts never leave a credential in either tree
  checkouts = steps.select { |s| s["uses"].to_s.start_with?("actions/checkout@") }
  problems << "there are not exactly two checkouts: #{checkouts.length}" unless checkouts.length == 2
  checkouts.each do |s|
    problems << "a checkout does not set persist-credentials: false: #{(s["with"] || {})["path"]}" unless (s["with"] || {})["persist-credentials"] == false
  end
  trusted = checkouts.find { |s| (s["with"] || {})["path"] == "trusted" }
  # Exact inputs, so neither checkout can switch repository, ref, or submodules
  if trusted.nil?
    problems << "no checkout has path: trusted"
  else
    want = { "path" => "trusted", "persist-credentials" => false }
    problems << "the trusted checkout inputs are not exactly #{want.inspect}: #{trusted["with"].inspect}" unless trusted["with"] == want
  end
  pr = checkouts.find { |s| (s["with"] || {})["path"] == "pr" }
  if pr.nil?
    problems << "no checkout has path: pr"
  else
    want = { "path" => "pr", "ref" => "${{ github.event.pull_request.head.sha }}", "fetch-depth" => 0, "persist-credentials" => false }
    problems << "the pr checkout inputs are not exactly #{want.inspect}: #{pr["with"].inspect}" unless pr["with"] == want
  end

  tokens = steps.select { |s| s["uses"].to_s.start_with?("actions/create-github-app-token@") }
  problems << "there is not exactly one App token step: #{tokens.length}" unless tokens.length == 1
  commit_if = "steps.prepare.outputs.commit == #{q}true#{q}"
  tokens.each do |s|
    w = s["with"] || {}
    problems << "the App token step id is not token: #{s["id"]}" unless s["id"] == "token"
    problems << "the App token step if is not exactly #{commit_if}: #{s["if"]}" unless s["if"].to_s.strip == commit_if
    want = {
      "client-id" => "${{ secrets.SDK_CORE_TRIGGER_APP_CLIENT_ID }}",
      "private-key" => "${{ secrets.SDK_CORE_TRIGGER_APP_KEY }}",
      "repositories" => "${{ github.event.repository.name }}",
      "permission-contents" => "write",
    }
    problems << "the App token inputs are not exactly #{want.inspect}: #{w.inspect}" unless w == want
    perms = w.select { |k, _| k.start_with?("permission-") }
    problems << "the App token permissions are not exactly {\"permission-contents\"=>\"write\"}: #{perms.inspect}" unless perms == { "permission-contents" => "write" }
    problems << "the App token repositories is not this repository: #{w["repositories"]}" unless w["repositories"] == "${{ github.event.repository.name }}"
    problems << "the App token client-id is not SDK_CORE_TRIGGER_APP_CLIENT_ID: #{w["client-id"]}" unless w["client-id"] == "${{ secrets.SDK_CORE_TRIGGER_APP_CLIENT_ID }}"
    problems << "the App token private-key is not SDK_CORE_TRIGGER_APP_KEY: #{w["private-key"]}" unless w["private-key"] == "${{ secrets.SDK_CORE_TRIGGER_APP_KEY }}"
  end

  kind = lambda do |s|
    if s["uses"].to_s.start_with?("actions/checkout@") then "checkout"
    elsif s["id"] == "prepare" then "prepare"
    elsif s["id"] == "token" then "token"
    elsif s["id"] == "push" then "push"
    elsif s["run"].to_s.include?("core-trigger-comment.sh") then "comment"
    else "other: #{label.(s)}"
    end
  end
  order = steps.map(&kind)
  want_order = %w[checkout checkout prepare token push comment]
  problems << "the steps are not in the order #{want_order.join(", ")}: #{order.join(", ")}" unless order == want_order

  # Nothing that reads PR data holds the App token
  steps.each do |s|
    next if s["id"] == "push"
    problems << "a step other than push uses the App token: #{label.(s)}" if s.to_s.include?("steps.token.outputs.token")
  end
  token_at = steps.index { |s| s["id"] == "token" } || steps.length
  steps[0...token_at].each do |s|
    ((s["env"] || {}).merge(s["with"] || {})).each do |k, v|
      problems << "#{label.(s)} before the App token step reads a token or secret in #{k}" if v.to_s =~ /token/i || v.to_s.include?("secrets.")
    end
  end
  push = steps.find { |s| s["id"] == "push" }
  if push.nil?
    problems << "no step has id: push"
  else
    problems << "the push step if is not exactly #{commit_if}: #{push["if"]}" unless push["if"].to_s.strip == commit_if
    want = {
      "APP_TOKEN" => "${{ steps.token.outputs.token }}",
      "HEAD_SHA" => "${{ github.event.pull_request.head.sha }}",
      "BRANCH" => "${{ github.event.pull_request.head.ref }}",
    }
    problems << "the push env is not exactly #{want.inspect}: #{push["env"].inspect}" unless push["env"] == want
  end

  prepare = steps.find { |s| s["id"] == "prepare" }
  if prepare.nil?
    problems << "no step has id: prepare"
  else
    penv = prepare["env"] || {}
    want_keys = %w[BASE_SHA HEAD_SHA TITLE GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL]
    problems << "the prepare env keys are not exactly #{want_keys.join(", ")}: #{penv.keys.inspect}" unless penv.keys.sort == want_keys.sort
    {
      "BASE_SHA" => "${{ github.sha }}",
      "HEAD_SHA" => "${{ github.event.pull_request.head.sha }}",
      "TITLE" => "${{ github.event.pull_request.title }}",
    }.each { |k, v| problems << "prepare #{k} is not #{v}: #{penv[k]}" unless penv[k] == v }
    %w[GIT_AUTHOR_NAME GIT_COMMITTER_NAME].each do |k|
      problems << "prepare #{k} is not coproduct-sdk-core-trigger[bot]: #{penv[k]}" unless penv[k] == "coproduct-sdk-core-trigger[bot]"
    end
    %w[GIT_AUTHOR_EMAIL GIT_COMMITTER_EMAIL].each do |k|
      problems << "prepare #{k} is not the bot noreply address: #{penv[k]}" unless penv[k].to_s =~ /\A\d+\+coproduct-sdk-core-trigger\[bot\]@users\.noreply\.github\.com\z/
    end
  end

  pins = [
    "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1",
    "actions/create-github-app-token@64ab729a6294000f5aa4a4bc0b73d1f32bc45510 # v3.3.0",
  ]
  uses_lines = raw.lines.map(&:strip).select { |l| l =~ /\A(- )?uses:/ }.map { |l| l.sub(/\A(- )?uses:\s*/, "") }
  uses_lines.each { |u| problems << "uses is not one of the pinned actions: #{u}" unless pins.include?(u) }
  problems << "the uses lines do not match the parsed steps" unless uses_lines.length == steps.count { |s| s.key?("uses") }

  # Every script is the trusted checkout, run under bash from the job root.
  # Each run line is exact, so nothing can run from the PR checkout beside it
  want_runs = {
    "prepare" => "trusted/scripts/release/core-trigger.sh prepare pr \"$BASE_SHA\" \"$HEAD_SHA\" \"$TITLE\"",
    "push" => "trusted/scripts/release/core-trigger.sh push pr \"$HEAD_SHA\" \"$BRANCH\"",
    "comment" => "trusted/scripts/release/core-trigger-comment.sh \"$GITHUB_REPOSITORY\" \"$PR_NUMBER\"",
  }
  run_steps = steps.select { |s| s.key?("run") }
  problems << "the run steps are not exactly prepare, push, and comment: #{run_steps.map(&kind).inspect}" unless run_steps.map(&kind) == %w[prepare push comment]
  run_steps.each do |s|
    want = want_runs[kind.(s)]
    problems << "the #{kind.(s)} run is not exactly #{want}: #{s["run"].to_s.strip}" unless want && s["run"].to_s.strip == want
  end
  problems << "the job sets defaults" if job.key?("defaults") || wf.key?("defaults")
  steps.each do |s|
    problems << "#{label.(s)} sets working-directory" if s.key?("working-directory")
    next unless s.key?("run")
    run = s["run"].to_s
    problems << "a run script contains ${{ }}: #{label.(s)}" if run.include?("${{")
    problems << "#{label.(s)} has no shell: bash" unless s["shell"] == "bash"
    problems << "#{label.(s)} does not run a script from trusted/scripts/release/" unless run.include?("trusted/scripts/release/")
  end

  comment = steps.find { |s| s["run"].to_s.include?("core-trigger-comment.sh") }
  if comment.nil?
    problems << "no step runs core-trigger-comment.sh"
  else
    want = "steps.push.outputs.pushed == #{q}true#{q}"
    problems << "the comment step if is not exactly #{want}: #{comment["if"]}" unless comment["if"].to_s.strip == want
    want = { "GH_TOKEN" => "${{ github.token }}", "PR_NUMBER" => "${{ github.event.pull_request.number }}" }
    problems << "the comment env is not exactly #{want.inspect}: #{comment["env"].inspect}" unless comment["env"] == want
  end
  puts problems
' "$cf" 2>&1); then
  echo "FAIL $cf: could not parse: $ctout"; fails=$((fails + 1))
elif [ -z "$ctout" ]; then
  echo "ok   $cf: runs no PR code, scopes the App token to the push, and comments only after a push"
else
  while IFS= read -r line; do echo "FAIL $cf: $line"; done <<< "$ctout"
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
