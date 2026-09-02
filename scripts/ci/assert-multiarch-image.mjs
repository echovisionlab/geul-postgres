#!/usr/bin/env node
import process from 'node:process';

const REQUIRED_PLATFORMS = new Set(['linux/amd64', 'linux/arm64']);
const IMAGE_MANIFEST_MEDIA_TYPES = new Set([
  'application/vnd.docker.distribution.manifest.v2+json',
  'application/vnd.oci.image.manifest.v1+json',
]);

let rawManifest = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  rawManifest += chunk;
});

process.stdin.on('end', () => {
  let manifest;
  try {
    manifest = JSON.parse(rawManifest);
  } catch {
    console.error('Published image did not return a valid OCI image index.');
    process.exit(1);
  }

  if (!Array.isArray(manifest.manifests)) {
    console.error('Published image is not a multi-platform OCI image index.');
    process.exit(1);
  }

  const platformManifests = new Map(
    manifest.manifests.flatMap(({ digest, mediaType, platform }) => {
      if (!platform?.os || !platform.architecture) return [];
      return [[`${platform.os}/${platform.architecture}`, { digest, mediaType }]];
    }),
  );
  const missingPlatforms = [...REQUIRED_PLATFORMS].filter(
    (platform) => !platformManifests.has(platform),
  );
  if (missingPlatforms.length > 0) {
    console.error(
      `Published image is missing required platform manifests: ${missingPlatforms.join(', ')}.`,
    );
    process.exit(1);
  }

  for (const platform of REQUIRED_PLATFORMS) {
    const { digest, mediaType } = platformManifests.get(platform);
    if (
      typeof digest !== 'string' ||
      !/^sha256:[a-f0-9]{64}$/.test(digest) ||
      !IMAGE_MANIFEST_MEDIA_TYPES.has(mediaType)
    ) {
      console.error(`Published ${platform} child is not an OCI/Docker image manifest.`);
      process.exit(1);
    }
  }

  for (const platform of REQUIRED_PLATFORMS) {
    const { digest } = platformManifests.get(platform);
    const architecture = platform.split('/')[1];
    console.log(`${architecture}_digest=${digest}`);
  }
});
