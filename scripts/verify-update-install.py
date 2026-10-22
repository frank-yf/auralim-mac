#!/usr/bin/env python3
"""Run the production Sparkle controller in disposable apps against a local feed.
Never targets the installed Auralim, publishes a release or touches its defaults.
"""
import functools
import http.server
import pathlib
import platform
import plistlib
import subprocess
import sys
import threading
import time
import uuid

root = pathlib.Path(__file__).resolve().parent.parent
run_dir = root / 'artifacts/update-install-0.3' / uuid.uuid4().hex
server_dir = run_dir / 'server'
server_dir.mkdir(parents=True)
events = run_dir / 'events.log'
framework_dir = root / '.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64'
tools = root / '.build/artifacts/sparkle/Sparkle/bin'
fixture_id = 'app.duskshift.update-smoke.' + uuid.uuid4().hex
normal_quit = '--normal-quit' in sys.argv[1:]
invalid_feed = '--invalid-feed' in sys.argv[1:]

def run(*args):
    subprocess.run([str(x) for x in args], check=True, cwd=root)

handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(server_dir))
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
port = server.server_port
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    executable = run_dir / 'Smoke'
    run('swiftc', '-parse-as-library', '-target', platform.machine() + '-apple-macos13.0',
        '-F', framework_dir, '-framework', 'Sparkle',
        '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks',
        root / 'Sources/Auralim/UpdateController.swift', root / 'scripts/fixtures/update-smoke.swift', '-o', executable)
    old_app = run_dir / 'host/Auralim.app'
    new_app = run_dir / 'new/Auralim.app'
    with (root / 'dist/Auralim.app/Contents/Info.plist').open('rb') as f:
        original_info = plistlib.load(f)
    for app, build, version in [(old_app, '25', '0.3'), (new_app, '26', '0.3.1')]:
        run('ditto', root / 'dist/Auralim.app', app)
        run('cp', executable, app / 'Contents/MacOS/Auralim')
        info = dict(original_info)
        info.update(CFBundleIdentifier=fixture_id, CFBundleVersion=build,
                    CFBundleShortVersionString=version, SmokeTestOutput=str(events),
                    SmokeQuitInsteadOfRestart=normal_quit,
                    SUFeedURL=f'http://127.0.0.1:{port}/appcast.xml',
                    NSAppTransportSecurity={'NSAllowsLocalNetworking': True})
        with (app / 'Contents/Info.plist').open('wb') as f:
            plistlib.dump(info, f)
        run('codesign', '--force', '--sign', '-', '--options', 'runtime', '--entitlements',
            root / '.build/signing/AdHoc.entitlements', app)
        run('codesign', '--verify', '--deep', '--strict', app)
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', new_app, server_dir / 'Auralim-smoke.zip')
    run(tools / 'generate_appcast', '--account', 'app.duskshift.mac', '--maximum-deltas', '0',
        '--download-url-prefix', f'http://127.0.0.1:{port}/', server_dir)
    run(tools / 'sign_update', '--account', 'app.duskshift.mac', '--verify', server_dir / 'appcast.xml')
    if invalid_feed:
        feed = server_dir / 'appcast.xml'
        feed.write_text(feed.read_text().replace('<title>', '<title>tampered ', 1))
    print('Launching isolated fixture; mode=' + ('invalid-feed' if invalid_feed else 'normal-quit' if normal_quit else 'explicit-restart'), flush=True)
    with (run_dir / 'process.log').open('w') as log:
        process = subprocess.Popen([str(old_app / 'Contents/MacOS/Auralim')], stdout=log, stderr=log)
        deadline = time.monotonic() + 75
        while time.monotonic() < deadline:
            text = events.read_text() if events.exists() else ''
            if 'verified-installed-and-relaunched' in text:
                assert 'state-ready' in text and 'explicit-restart-action' in text, text
                assert text.index('state-ready') < text.index('explicit-restart-action') < text.index('launched-build-26'), text
                with (old_app / 'Contents/Info.plist').open('rb') as f:
                    assert plistlib.load(f)['CFBundleVersion'] == '26'
                print(text, end='')
                print('PASS: signed feed, real background download, waiting for action, installation and relaunch. Evidence:', run_dir)
                break
            if normal_quit and process.poll() is not None:
                try:
                    with (old_app / 'Contents/Info.plist').open('rb') as f:
                        installed_build = plistlib.load(f)['CFBundleVersion']
                except (FileNotFoundError, plistlib.InvalidFileException):
                    installed_build = None
                if installed_build == '26':
                    time.sleep(2)
                    text = events.read_text()
                    assert 'normal-quit-action' in text and 'launched-build-26' not in text, text
                    print(text, end='')
                    print('PASS: normal quit installed the prepared update without relaunch. Evidence:', run_dir)
                    break
            if 'state-failed' in text:
                if invalid_feed:
                    assert 'validation' in text and 'state-ready' not in text, text
                    with (old_app / 'Contents/Info.plist').open('rb') as f:
                        assert plistlib.load(f)['CFBundleVersion'] == '25'
                    print(text, end='')
                    print('PASS: tampered signed feed was rejected without installation. Evidence:', run_dir)
                    break
                raise RuntimeError('Fixture updater failed:\n' + text + '\n' + (run_dir / 'process.log').read_text())
            time.sleep(0.25)
        else:
            process.terminate()
            raise TimeoutError('Update smoke test timed out. Evidence: ' + str(run_dir))
finally:
    server.shutdown()
    subprocess.run(['defaults', 'delete', fixture_id], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
