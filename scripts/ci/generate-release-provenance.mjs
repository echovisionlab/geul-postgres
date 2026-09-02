#!/usr/bin/env node
import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { access, mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

const SOURCE_REPOSITORY = 'echovisionlab/geul-postgres';
const SOURCE_PATH = 'infra/postgres';
const MANIFEST_PATH = 'release/prod/source.json';

function usage() {
  return `Usage: node scripts/ci/generate-release-provenance.mjs [--check]

Generates ${MANIFEST_PATH} from the current tracked Postgres image asset tree.

Options:
  --check   Verify the committed manifest is current without writing files.
  --help    Show this help text.
`;
}

function parseArgs(argv) {
  const options = { check: false };

  for (const arg of argv) {
    if (arg === '--check') {
      options.check = true;
      continue;
    }

    if (arg === '--help' || arg === '-h') {
      console.log(usage());
      process.exit(0);
    }

    throw new Error(`Unsupported argument: ${arg}`);
  }

  return options;
}

function sha256(input) {
  return createHash('sha256').update(input).digest('hex');
}

function git(args) {
  return new Promise((resolve, reject) => {
    execFile('git', args, { cwd: process.cwd() }, (error, stdout, stderr) => {
      if (error) {
        reject(new Error(stderr.trim() || error.message));
        return;
      }

      resolve(stdout.trim());
    });
  });
}

async function collectTrackedFiles(sourcePath) {
  const trackedFiles = await git(['ls-files', '--', sourcePath]);

  return trackedFiles
    .split('\n')
    .filter(Boolean)
    .sort()
    .map((repoRelativePath) => ({
      fullPath: path.join(process.cwd(), repoRelativePath),
      repoRelativePath,
    }));
}

async function computeAggregateChecksum(files) {
  const perFileLines = [];

  for (const { fullPath, repoRelativePath } of files) {
    const fileBytes = await readFile(fullPath);
    const fileChecksum = sha256(fileBytes);
    perFileLines.push(`${fileChecksum}  ${repoRelativePath}\n`);
  }

  return sha256(perFileLines.join(''));
}

async function assertPathExists(directoryPath) {
  try {
    await access(directoryPath);
  } catch {
    throw new Error(`Missing directory: ${directoryPath}`);
  }
}

async function buildManifest() {
  await assertPathExists(SOURCE_PATH);

  const trackedFiles = await collectTrackedFiles(SOURCE_PATH);
  const aggregateChecksum = await computeAggregateChecksum(trackedFiles);

  return {
    source: {
      repository: SOURCE_REPOSITORY,
      source_path: SOURCE_PATH,
      image_asset_path: SOURCE_PATH,
      tracked_file_count: trackedFiles.length,
      aggregate_checksum: aggregateChecksum,
      aggregate_checksum_algorithm:
        'sha256 of sorted per-file sha256 lines in the form "<sha256>  <repo-relative path>\\n"',
    },
  };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const expectedText = `${JSON.stringify(await buildManifest(), null, 2)}\n`;

  if (options.check) {
    const actualText = await readFile(MANIFEST_PATH, 'utf8').catch(() => null);

    if (actualText !== expectedText) {
      console.error(`${MANIFEST_PATH} is missing or stale.`);
      console.error('Run: node scripts/ci/generate-release-provenance.mjs');
      process.exit(1);
    }

    console.log(`${MANIFEST_PATH} is current.`);
    return;
  }

  await mkdir(path.dirname(MANIFEST_PATH), { recursive: true });
  await writeFile(MANIFEST_PATH, expectedText);
  console.log(`Wrote ${MANIFEST_PATH}`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
