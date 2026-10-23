#!/usr/bin/env python3
"""Exercise the installer migration with temporary data and stubbed system tools."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class MigrationTests(unittest.TestCase):
    def test_preserves_destination_and_skips_receipts_transient_files_and_symlinks(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            old, new, tools = root / 'old', root / 'new', root / 'tools'
            for directory in (old, new, tools):
                directory.mkdir()
            for name in ('launchctl', 'chown'):
                tool = tools / name
                tool.write_text('#!/bin/sh\nexit 0\n')
                tool.chmod(0o755)
            (old / 'settings.plist').write_bytes(b'old settings')
            (new / 'settings.plist').write_bytes(b'new settings')
            (old / 'history.bin').write_bytes(b'actual history')
            (old / 'sessions.json').write_bytes(b'[]')
            for name in ('license.json', 'status.plist', 'springboard-launch'):
                (old / name).write_bytes(b'must not migrate')
            (old / 'health.json').symlink_to(old / 'license.json')
            source = (Path(__file__).resolve().parent.parent / 'layout/DEBIAN/preinst').read_text()
            source = source.replace('/var/mobile/Library/Voltix', str(old))
            source = source.replace('/var/mobile/Library/MyLittleEnergy', str(new))
            script = root / 'preinst'
            script.write_text(source)
            environment = dict(os.environ, PATH=str(tools) + ':' + os.environ['PATH'])
            subprocess.run(['sh', str(script), 'install'], env=environment, check=True)
            self.assertEqual((new / 'settings.plist').read_bytes(), b'new settings')
            self.assertEqual((new / 'history.bin').read_bytes(), b'actual history')
            self.assertEqual((new / 'sessions.json').read_bytes(), b'[]')
            self.assertEqual({p.name for p in new.iterdir()}, {'settings.plist', 'history.bin', 'sessions.json'})
            self.assertEqual((old / 'license.json').read_bytes(), b'must not migrate')
            # Re-running installation must leave newer data alone.
            (new / 'history.bin').write_bytes(b'newer history')
            subprocess.run(['sh', str(script), 'upgrade'], env=environment, check=True)
            self.assertEqual((new / 'history.bin').read_bytes(), b'newer history')
            # Do not write through a destination symlink.
            linked = root / 'linked'
            linked.symlink_to(new, target_is_directory=True)
            script.write_text(source.replace(str(new), str(linked)))
            result = subprocess.run(['sh', str(script), 'install'], env=environment, capture_output=True)
            self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
