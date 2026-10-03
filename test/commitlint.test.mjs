import { execSync } from 'node:child_process';
import assert from 'node:assert/strict';

function testCommit(message, shouldPass) {
  try {
    execSync('pnpm exec commitlint', {
      input: message,
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    if (!shouldPass) {
      assert.fail(`Expected commit message to fail, but it passed: "${message}"`);
    }
  } catch (error) {
    if (shouldPass) {
      assert.fail(
        `Expected commit message to pass, but it failed: "${message}"\n${error.stderr || error.stdout}`,
      );
    }
  }
}

console.log('Running commitlint rule verification tests...');

// 1. Types where scope is omitted (since type == scope)
testCommit('test: add unit test suite', true);
testCommit('test(test): add unit test suite', false);

testCommit('docs: update readme documentation', true);
testCommit('docs(docs): update readme documentation', false);

testCommit('ci: configure github actions pipeline', true);
testCommit('ci(ci): configure github actions pipeline', false);

testCommit('chore: update dependencies', true);
testCommit('chore(chore): update dependencies', false);

// 2. Types requiring scopes
testCommit('feat(core): implement direct memory streaming', true);
testCommit('feat: implement direct memory streaming', false);

testCommit('fix(b2): handle endpoint protocol parsing', true);
testCommit('fix: handle endpoint protocol parsing', false);

testCommit('refactor(scripts): extract shared logic into common.sh', true);
testCommit('refactor: extract shared logic into common.sh', false);

// 3. Breaking changes with '!'
testCommit('feat(core)!: drop legacy connection parameter support', true);
testCommit('fix(api)!: modify restore argument semantics', true);

// 4. Invalid types
testCommit('random: arbitrary message', false);
testCommit('feature(core): typo in type', false);

console.log('All commitlint tests passed successfully!');
