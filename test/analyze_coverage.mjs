import fs from 'node:fs';
import path from 'node:path';

const projectRoot = process.cwd();
const metadataPath = path.join(projectRoot, 'test', 'coverage', 'metadata.json');
const traceLogPath = path.join(projectRoot, 'coverage', 'trace.log');

if (!fs.existsSync(metadataPath)) {
  console.error('Error: metadata.json not found in test/coverage');
  process.exit(1);
}

if (!fs.existsSync(traceLogPath)) {
  console.error('Error: trace.log not found in coverage directory');
  process.exit(1);
}

const metadata = JSON.parse(fs.readFileSync(metadataPath, 'utf-8'));
const executedLinesByFile = new Map();
const traceLines = fs.readFileSync(traceLogPath, 'utf-8').split('\n');

for (const line of traceLines) {
  if (!line.trim()) continue;
  const match = line.match(/^(.*):(\d+)$/);
  if (!match) continue;
  const relPath = match[1];
  const lineNo = parseInt(match[2], 10);

  if (!executedLinesByFile.has(relPath)) {
    executedLinesByFile.set(relPath, new Set());
  }
  executedLinesByFile.get(relPath).add(lineNo);
}

let totalExecutable = 0;
let totalCovered = 0;
let allPassed = true;

console.log('\n================================================================');
console.log('              BASH CODE COVERAGE REPORT (100% TARGET)');
console.log('================================================================');
console.log(
  'File'.padEnd(28) +
    ' | ' +
    'Total Lines'.padStart(11) +
    ' | ' +
    'Covered'.padStart(7) +
    ' | ' +
    'Coverage'.padStart(8) +
    ' | Status',
);
console.log('-'.repeat(64));

for (const [relPath, info] of Object.entries(metadata)) {
  const executableLines = info.executableLines;
  const executed = executedLinesByFile.get(relPath) || new Set();

  const coveredLines = executableLines.filter((l) => executed.has(l));
  const missedLines = executableLines.filter((l) => !executed.has(l));

  totalExecutable += executableLines.length;
  totalCovered += coveredLines.length;

  const pct =
    executableLines.length === 0
      ? 100
      : ((coveredLines.length / executableLines.length) * 100).toFixed(1);

  const passed = missedLines.length === 0;
  if (!passed) {
    allPassed = false;
  }

  const status = passed ? 'PASS' : `FAIL (Missed: ${missedLines.join(', ')})`;
  console.log(
    relPath.padEnd(28) +
      ' | ' +
      String(executableLines.length).padStart(11) +
      ' | ' +
      String(coveredLines.length).padStart(7) +
      ' | ' +
      (pct + '%').padStart(8) +
      ' | ' +
      status,
  );
}

const overallPct =
  totalExecutable === 0 ? 100 : ((totalCovered / totalExecutable) * 100).toFixed(1);

console.log('='.repeat(64));
console.log(
  'TOTAL'.padEnd(28) +
    ' | ' +
    String(totalExecutable).padStart(11) +
    ' | ' +
    String(totalCovered).padStart(7) +
    ' | ' +
    (overallPct + '%').padStart(8) +
    ' | ' +
    (allPassed ? 'PASS (100%)' : 'FAIL'),
);
console.log('================================================================\n');

// Write lcov summary
const lcovPath = path.join(projectRoot, 'coverage', 'lcov.info');
let lcov = '';
for (const [relPath, info] of Object.entries(metadata)) {
  const fullPath = path.join(projectRoot, relPath);
  lcov += `TN:\nSF:${fullPath}\n`;
  const executed = executedLinesByFile.get(relPath) || new Set();
  for (const lineNo of info.executableLines) {
    const hits = executed.has(lineNo) ? 1 : 0;
    lcov += `DA:${lineNo},${hits}\n`;
  }
  lcov += 'end_of_record\n';
}
fs.writeFileSync(lcovPath, lcov);

if (!allPassed) {
  console.error(`Coverage check failed: 100% code coverage required (got ${overallPct}%).`);
  process.exit(1);
}

console.log('100% test coverage successfully verified!');
