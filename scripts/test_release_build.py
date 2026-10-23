#!/usr/bin/env python3
"""Release packaging tests. No real GitHub release is created."""
import io
import json
import stat
import subprocess
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

import release_build as release


def tar_bytes(members):
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode='w:xz') as archive:
        for name, payload, mode, target in members:
            item = tarfile.TarInfo(name)
            item.mode = mode
            if target is not None:
                item.type, item.linkname = tarfile.SYMTYPE, target
                archive.addfile(item)
            else:
                item.size = len(payload)
                archive.addfile(item, io.BytesIO(payload))
    return buffer.getvalue()


def package_bytes(members):
    result = bytearray(b'!<arch>\n')
    for name, body in [('control.tar.xz', tar_bytes([('control', b'Version: 1.0.8\n', 0o644, None), ('postinst', b'#!/bin/sh\n', 0o755, None)])), ('data.tar.xz', tar_bytes(members))]:
        header = f'{name + "/":<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{len(body):<10}`\n'.encode()
        result.extend(header + body + (b'\n' if len(body) % 2 else b''))
    return bytes(result)


class ReleaseTests(unittest.TestCase):
    def test_zip_contains_unpacked_files_and_preserves_modes_and_symlinks(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            package = root / 'input.deb'
            package.write_bytes(package_bytes([
                ('./var/jb/usr/libexec/mylittleenergyd', b'actual binary bytes', 0o755, None),
                ('./var/jb/alias', b'', 0o777, 'usr/libexec/mylittleenergyd'),
            ]))
            assets = release.prepare_assets(package, root / 'output', {'version': '1.0.8'})
            with zipfile.ZipFile(assets[1]) as archive:
                self.assertEqual(archive.read('var/jb/usr/libexec/mylittleenergyd'), b'actual binary bytes')
                self.assertEqual(archive.read('DEBIAN/postinst'), b'#!/bin/sh\n')
                self.assertEqual(archive.read('var/jb/alias'), b'usr/libexec/mylittleenergyd')
                self.assertEqual(archive.getinfo('DEBIAN/postinst').external_attr >> 16 & 0o777, 0o755)
                self.assertTrue(stat.S_ISLNK(archive.getinfo('var/jb/alias').external_attr >> 16))
                self.assertFalse(any(name.endswith('.deb') for name in archive.namelist()))
            for line in assets[-1].read_text().splitlines():
                digest, name = line.split('  ', 1)
                self.assertEqual(digest, release.hashlib.sha256((root / 'output' / name).read_bytes()).hexdigest())
            self.assertEqual(assets[0].read_bytes(), package.read_bytes())

    def test_refuses_path_traversal_and_duplicate_zip_entries(self):
        for members in [
            [('../escape', b'bad', 0o644, None)],
            [('/absolute', b'bad', 0o644, None)],
            [('var/file', b'a', 0o644, None), ('./var/file', b'b', 0o644, None)],
        ]:
            with self.subTest(members=members), tempfile.TemporaryDirectory() as temporary:
                package = Path(temporary) / 'input.deb'
                package.write_bytes(package_bytes(members))
                with self.assertRaises(ValueError):
                    release.prepare_assets(package, Path(temporary) / 'output', {'version': '1'})

    def test_accepts_intended_public_destination(self):
        with patch.object(release.shutil, 'which', return_value='/usr/bin/gh'), patch.object(release, 'command', return_value=json.dumps({'nameWithOwner': 'owner/repo', 'isPrivate': False})):
            self.assertEqual(release.release_repository('owner/repo'), 'owner/repo')

    def test_uses_origin_and_checks_privacy(self):
        with patch.object(release.shutil, 'which', return_value='/usr/bin/gh'), patch.object(release, 'command', side_effect=['https://github.com/owner/private.git', json.dumps({'nameWithOwner': 'owner/private', 'isPrivate': True})]) as command:
            self.assertEqual(release.release_repository(), 'owner/private')
            self.assertEqual(command.call_args_list[1].args[3], 'owner/private')

    def test_release_uploads_all_assets_to_exact_commit_with_notes_file(self):
        with patch.object(release.subprocess, 'run') as run:
            release.publish('owner/private', 'v1-build99', 'abcdef', '1', [Path('file.deb'), Path('unpacked.zip')], Path('notes.md'))
            args = run.call_args.args[0]
            self.assertIn('--prerelease', args)
            self.assertEqual(args[args.index('--target') + 1], 'abcdef')
            self.assertEqual(args[args.index('--repo') + 1], 'owner/private')
            self.assertEqual(args[-2:], ['file.deb', 'unpacked.zip'])
            self.assertTrue(run.call_args.kwargs['check'])

    def test_source_push_uses_private_origin_without_force(self):
        with patch.object(release, 'release_repository', return_value='owner/private'), patch.object(release.subprocess, 'run') as run:
            release.push_source('owner/private')
            self.assertEqual(run.call_args.args[0], ['git', 'push', 'origin', 'HEAD'])
            self.assertTrue(run.call_args.kwargs['check'])

    def test_source_push_refuses_a_different_destination(self):
        with patch.object(release, 'release_repository', return_value='owner/private'), patch.object(release.subprocess, 'run') as run:
            with self.assertRaises(ValueError):
                release.push_source('owner/other')
            run.assert_not_called()

    def test_roothide_assets_have_distinct_names(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            package = root / 'input.deb'
            package.write_bytes(package_bytes([]))
            assets = release.prepare_assets(package, root / 'output', {'version': '1', 'packageScheme': 'roothide'})
            self.assertIn('_roothide.', assets[0].name)
            self.assertIn('_roothide_', assets[1].name)

    def test_publish_failure_is_not_silently_ignored(self):
        with patch.object(release.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'gh')):
            with self.assertRaises(subprocess.CalledProcessError):
                release.publish('owner/private', 'v1', 'sha', '1', [], Path('notes.md'))


if __name__ == '__main__':
    unittest.main()
