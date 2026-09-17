import path from 'node:path';

// Dynamically derive the output filename from the repository/directory name: <repo>_sdk.xml
const repoName = path.basename(process.cwd());

export default {
  include: [
    'mix.exs',
    'README.md',
    'AGENTS.md',
    'CLAUDE.md',
    'CHANGELOG.md',
    'guides/**/*.md',
    'examples/**/*.{ex,exs,md}',
    'apps/*/mix.exs',
    'apps/*/README.md',
    'apps/*/CHANGELOG.md',
    'apps/*/guides/**/*.md',
    'apps/*/lib/**/*.{ex,exs}',
    'apps/*/examples/**/*.{ex,exs}'
  ],
  ignore: {
    useGitignore: true,
    useDotIgnore: true,
    useDefaultPatterns: true,
    customPatterns: [
      'test/**',
      'apps/*/test/**',
      '**/*_test.exs',
      '**/test_helper.exs',
      '**/fixtures/**',
      'apps/*/tmp/**',
      'docs/**',
      'assets/**',
      '**/assets/**',
      'build_support/**',
      '.blitz/**',
      '.claude/**',
      'LICENSE*',
      '**/LICENSE*',
      '**/*.beam',
      '**/*.plt*',
      'priv/**',
      'pristine*.xml',
      '*_sdk.xml',
      'repomix-output.*'
    ]
  },
  output: {
    filePath: `${repoName}_sdk.xml`,
    style: 'xml',
    filePathStyle: 'target-relative',
    fileSummary: true,
    directoryStructure: true,
    files: true,
    removeComments: false,
    removeEmptyLines: false,
    compress: false,
    topFilesLength: 5,
    showLineNumbers: false,
    copyToClipboard: false
  },
  security: {
    enableSecurityCheck: true
  },
  tokenCount: {
    encoding: 'o200k_base'
  }
};
