#!/usr/bin/env python3
"""Publish a validated .deb and ZIP of its unpacked contents to the configured repository."""
import argparse
import hashlib
import io
import json
import re
import shutil
import stat
import subprocess
import tarfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

from check_package import check


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def release_repository(repo=None):
    if not shutil.which('gh'):
        raise ValueError('GitHub CLI (gh) is required for automatic releases. Sign in with gh auth login.')
    if not repo:
        remote = command('git', 'remote', 'get-url', 'origin')
        match = re.fullmatch(r'(?:https://github\.com/|git@github\.com:)([^/]+/[^/]+?)(?:\.git)?', remote)
        if not match:
            raise ValueError('origin must point to the intended GitHub repository.')
        repo = match.group(1)
    result = json.loads(command('gh', 'repo', 'view', repo, '--json', 'nameWithOwner,isPrivate'))
    return result['nameWithOwner']


def deb_archives(package):
    data = package.read_bytes()
    if data[:8] != b'!<arch>\n':
        raise ValueError('Invalid Debian archive')
    offset, result = 8, {}
    while offset < len(data):
        header = data[offset:offset + 60]
        if len(header) != 60 or header[58:] != b'`\n':
            raise ValueError('Invalid Debian ar header')
        size = int(header[48:58])
        payload = data[offset + 60:offset + 60 + size]
        if len(payload) != size:
            raise ValueError('Truncated Debian member')
        name = header[:16].decode().strip().rstrip('/')
        if name.startswith(('control.tar', 'data.tar')):
            result[name.split('.')[0]] = payload
        offset += 60 + size + size % 2
    if set(result) != {'control', 'data'}:
        raise ValueError('Missing control or data archive')
    return result


def safe_name(name):
    path = PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts or '\\' in name:
        raise ValueError('Unsafe package member path')
    return '' if str(path) == '.' else str(path)


def prepare_assets(package, destination, metadata):
    """Read package tar members directly; never extract them on the host."""
    archives = deb_archives(package)
    destination.mkdir(parents=True, exist_ok=False)
    version = re.sub(r'[^A-Za-z0-9._-]', '-', metadata['version'])
    scheme = metadata.get('packageScheme', 'rootless')
    deb = destination / f'MyLittleEnergy_{version}_{scheme}.deb'
    unpacked = destination / f'MyLittleEnergy_{version}_{scheme}_unpacked.zip'
    shutil.copyfile(package, deb)
    seen = set()
    with zipfile.ZipFile(unpacked, 'w', compression=zipfile.ZIP_DEFLATED) as output:
        for kind in ('control', 'data'):
            with tarfile.open(fileobj=io.BytesIO(archives[kind])) as archive:
                for member in archive:
                    path = safe_name(member.name)
                    if not path:
                        continue
                    name = ('DEBIAN/' if kind == 'control' else '') + path
                    if member.isdir():
                        name += '/'
                    if name in seen:
                        raise ValueError('Duplicate archive path')
                    seen.add(name)
                    item = zipfile.ZipInfo(name)
                    item.create_system = 3
                    item.compress_type = zipfile.ZIP_DEFLATED
                    if member.issym():
                        item.external_attr = (stat.S_IFLNK | member.mode) << 16
                        content = member.linkname.encode()
                    elif member.isdir():
                        item.external_attr = ((stat.S_IFDIR | member.mode) << 16) | 0x10
                        content = b''
                    elif member.isfile() or member.islnk():
                        if member.islnk():
                            safe_name(member.linkname)
                        item.external_attr = (stat.S_IFREG | member.mode) << 16
                        content = archive.extractfile(member).read()
                    else:
                        raise ValueError('Unsupported special file in package')
                    output.writestr(item, content)
    manifest = destination / 'BUILD_MANIFEST.json'
    manifest.write_text(json.dumps(metadata, indent=2) + '\n')
    assets = [deb, unpacked, manifest]
    checksums = destination / 'SHA256SUMS'
    checksums.write_text(''.join(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n' for path in assets))
    return assets + [checksums]


def push_source(repo):
    if repo != release_repository():
        raise ValueError('Source push destination must match the origin repository.')
    subprocess.run(['git', 'push', 'origin', 'HEAD'], check=True)


def publish(repo, tag, commit, version, assets, notes):
    subprocess.run([
        'gh', 'release', 'create', tag, '--repo', repo, '--target', commit,
        '--prerelease', '--title', f'MyLittleEnergy {version} ({tag})',
        '--notes-file', str(notes), *map(str, assets),
    ], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', nargs='?', type=Path)
    parser.add_argument('--repo')
    parser.add_argument('--tag')
    parser.add_argument('--push-source', action='store_true', help='Push the local source commit to origin after the package passes validation')
    parser.add_argument('--check', action='store_true', help='Check repository access before building')
    args = parser.parse_args()
    repo = release_repository(args.repo)
    if args.check:
        print(f'Automatic releases enabled for repository {repo}')
        return
    if not args.package:
        parser.error('package is required')
    check(args.package)
    if args.push_source:
        push_source(repo)
    with tarfile.open(fileobj=io.BytesIO(deb_archives(args.package)['control'])) as archive:
        control = next(m for m in archive if safe_name(m.name) == 'control')
        fields = dict(line.split(': ', 1) for line in archive.extractfile(control).read().decode().splitlines() if ': ' in line)
    version = fields['Version']
    commit = command('git', 'rev-parse', 'HEAD')
    # The release must point to a source commit already present in the destination.
    command('gh', 'api', f'repos/{repo}/commits/{commit}', '--jq', '.sha')
    now = datetime.now(timezone.utc)
    safe_version = re.sub(r'[^A-Za-z0-9._-]', '-', version)
    tag = args.tag or f'v{safe_version}-local-{now:%Y%m%dT%H%M%S%fZ}-{commit[:8]}'
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', tag):
        raise ValueError('Invalid release tag')
    # Source versions are stamped by CI before packaging; report local modifications honestly.
    dirty = bool(command('git', 'status', '--porcelain', '--untracked-files=no'))
    scheme = 'roothide' if fields['Architecture'] == 'iphoneos-arm64e' else 'rootless'
    metadata = {'version': version, 'commit': commit, 'repository': repo,
                'builtAt': now.isoformat(), 'tag': tag, 'workingTreeModified': dirty, 'packageScheme': scheme, 'freeToUse': True}
    destination = Path('dist') / tag
    assets = prepare_assets(args.package, destination, metadata)
    notes = destination / 'RELEASE_NOTES.md'
    changelog = Path('CHANGELOG.md').read_text()
    section = re.search(r'^## ' + re.escape(version) + r'\s*\n(.*?)(?=^## |\Z)', changelog, re.M | re.S)
    notes.write_text(
        f'## MyLittleEnergy {version}\n\n' +
        '**Free to use. No account, purchase activation or license server required.**\n\n' +
        (section.group(1).strip() + '\n\n' if section else '') +
        f'Source commit: `{commit}`.\n\n' +
        ('Built from a working tree with local modifications.\n\n' if dirty else '') +
        f'- `{assets[0].name}`: installable {scheme} package.\n'
        f'- `{assets[1].name}`: unpacked package files with `DEBIAN/` and the {scheme} filesystem layout. This ZIP is not an installer.\n'
        '- `BUILD_MANIFEST.json` and `SHA256SUMS`: build metadata and asset checksums.\n\n'
        'Automated prerelease. Compilation is not evidence of device compatibility.\n')
    publish(repo, tag, commit, version, assets, notes)
    print(command('gh', 'release', 'view', tag, '--repo', repo, '--json', 'url', '--jq', '.url'))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(f'Build release failed: {error}')
