#!/usr/bin/env bash
set -euo pipefail
task_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/jaagte-core-check.XXXXXX")
trap 'rm -rf -- "$task_tmp"' EXIT

# Command Line Tools may lack XCTest. This standalone harness runs the SAME
# synchronous test method bodies against real Core sources using Swift assertions.
# It validates the fatigue core only; it does not compile the iOS app or XCTest.
python3 - "$task_root" "$task_tmp" <<'PY'
import pathlib, re, sys
root, out = map(pathlib.Path, sys.argv[1:])
test = (root / 'Tests/JaagteRahoCoreTests/FatigueEngineTests.swift').read_text()
test = test[test.index('final class FatigueEngineTests:'):]
header = (root / 'scripts/check-core-harness.swift').read_text()
methods = re.findall(r'    func (test\w+)\(\)', test)
calls = '\n'.join(f'        run("{m}") {{ suite.{m}() }}' for m in methods)
runner = '''
@main struct CoreCheckRunner {
    static func main() {
        print("Standalone Swift core assertions (no XCTest or iOS build)")
        let suite = FatigueEngineTests()
%s
        print("\\(testCount) core checks, \\(failureCount) assertion failures")
        if failureCount != 0 { exit(1) }
    }
}
''' % calls
(out / 'CoreCheck.swift').write_text(header + '\n' + test + '\n' + runner)
PY
swiftc -swift-version 5 "$task_root"/iOS/JaagteRaho/Core/*.swift "$task_tmp/CoreCheck.swift" -o "$task_tmp/check-core"
"$task_tmp/check-core"
