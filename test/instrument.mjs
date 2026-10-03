import fs from 'node:fs';
import path from 'node:path';

const projectRoot = process.cwd();
const srcDir = path.join(projectRoot, 'scripts');
const destDir = path.join(projectRoot, 'test', 'coverage', 'instrumented', 'scripts');

fs.mkdirSync(destDir, { recursive: true });

const tfSrc = path.join(projectRoot, 'terraform');
const tfDest = path.join(projectRoot, 'test', 'coverage', 'instrumented', 'terraform');
if (fs.existsSync(tfSrc)) {
  fs.cpSync(tfSrc, tfDest, { recursive: true });
}

const scriptFiles = [
  'common.sh',
  'backup.sh',
  'restore.sh',
  'entrypoint.sh',
  'dr_test.sh',
  'provision_b2.sh',
];

const metadata = {};

for (const file of scriptFiles) {
  const srcPath = path.join(srcDir, file);
  const destPath = path.join(destDir, file);
  const relPath = `scripts/${file}`;

  const content = fs.readFileSync(srcPath, 'utf-8');
  const lines = content.split('\n');

  const executableLines = [];
  const instrumentedLines = [];

  let inHeredoc = false;
  let heredocMarker = '';
  let inContinuation = false;

  for (let i = 0; i < lines.length; i++) {
    const lineNo = i + 1;
    const rawLine = lines[i];
    const trimmed = rawLine.trim();

    // Line continuation handling
    if (inContinuation) {
      instrumentedLines.push(rawLine);
      if (!trimmed.endsWith('\\')) {
        inContinuation = false;
      }
      continue;
    }

    // Check heredoc start/end
    if (inHeredoc) {
      instrumentedLines.push(rawLine);
      if (trimmed === heredocMarker) {
        inHeredoc = false;
      }
      continue;
    }

    const heredocMatch = trimmed.match(/<<-?\s*['"]?([A-Za-z0-9_]+)['"]?/);
    if (heredocMatch) {
      inHeredoc = true;
      heredocMarker = heredocMatch[1];
      executableLines.push(lineNo);
      const leadingSpace = rawLine.match(/^\s*/)[0];
      instrumentedLines.push(`${leadingSpace}__cov "${relPath}" ${lineNo}; ${trimmed}`);
      continue;
    }

    // Shebang
    if (i === 0 && rawLine.startsWith('#!')) {
      instrumentedLines.push(rawLine);
      instrumentedLines.push(
        '__cov() { if [[ -n "${COVERAGE_TRACE_FILE:-}" ]]; then echo "$1:$2" >> "${COVERAGE_TRACE_FILE}"; fi; }',
      );
      continue;
    }

    // Comments and empty lines
    if (!trimmed || trimmed.startsWith('#')) {
      instrumentedLines.push(rawLine);
      continue;
    }

    // Function definitions
    if (trimmed.match(/^(function\s+)?[a-zA-Z0-9_-]+\s*\(\)\s*\{?\s*$/)) {
      instrumentedLines.push(rawLine);
      continue;
    }

    // Case patterns e.g. foo), *), --file), --help|-h), etc.
    if (trimmed.match(/^[a-zA-Z0-9_\-*|()\s]+\)\s*(;;)?$/)) {
      instrumentedLines.push(rawLine);
      continue;
    }

    // Pure syntax delimiters and control flow endings
    if (
      trimmed === ';;' ||
      trimmed === 'fi' ||
      trimmed === 'done' ||
      trimmed === 'esac' ||
      trimmed === '}' ||
      trimmed === '{' ||
      trimmed === 'then' ||
      trimmed === 'do' ||
      trimmed === 'else' ||
      trimmed.match(/^case\s+.*\s+in$/) ||
      trimmed.startsWith('set -')
    ) {
      instrumentedLines.push(rawLine);
      continue;
    }

    // Track continuation
    if (trimmed.endsWith('\\')) {
      inContinuation = true;
    }

    // Executable statement line
    executableLines.push(lineNo);
    const leadingSpace = rawLine.match(/^\s*/)[0];
    instrumentedLines.push(`${leadingSpace}__cov "${relPath}" ${lineNo}; ${trimmed}`);
  }

  fs.writeFileSync(destPath, instrumentedLines.join('\n'));
  fs.chmodSync(destPath, 0o755);

  metadata[relPath] = {
    executableLines,
  };
}

fs.writeFileSync(
  path.join(projectRoot, 'test', 'coverage', 'metadata.json'),
  JSON.stringify(metadata, null, 2),
);

console.log('Successfully instrumented scripts for coverage testing.');
