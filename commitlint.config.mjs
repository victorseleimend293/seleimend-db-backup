export default {
  extends: ['@commitlint/config-conventional'],
  plugins: [
    {
      rules: {
        'scope-disallow-matching-type': ({ type, scope }) => {
          if (type && scope && type.trim().toLowerCase() === scope.trim().toLowerCase()) {
            return [
              false,
              `Scope '${scope}' matches type '${type}'. Scope should be omitted when it matches the commit type (e.g., '${type}: message' instead of '${type}(${scope}): message').`,
            ];
          }
          return [true];
        },
        'scope-required-for-changes': ({ type, scope }) => {
          const typesRequiringScope = ['feat', 'fix', 'refactor', 'perf'];
          if (
            type &&
            typesRequiringScope.includes(type.toLowerCase()) &&
            (!scope || !scope.trim())
          ) {
            return [
              false,
              `Scope is required for '${type}' commits (e.g., '${type}(scope): message').`,
            ];
          }
          return [true];
        },
      },
    },
  ],
  rules: {
    'scope-disallow-matching-type': [2, 'always'],
    'scope-required-for-changes': [2, 'always'],
  },
};
