// Quit only the explicitly supplied development bundles before rebuilding.
ObjC.import('AppKit');
ObjC.import('Foundation');

function run(paths) {
    if (!paths.length) throw new Error('Provide at least one local app bundle path.');
    function running() {
        const apps = $.NSWorkspace.sharedWorkspace.runningApplications;
        const matches = [];
        for (let index = 0; index < apps.count; index++) {
            const app = apps.objectAtIndex(index);
            if (paths.includes(ObjC.unwrap(app.bundleURL.path))) matches.push(app);
        }
        return matches;
    }
    const apps = running();
    for (const app of apps) app.terminate;
    const deadline = Date.now() + 10000;
    while (running().length) {
        if (Date.now() >= deadline) {
            throw new Error('Local app did not quit; build cancelled. Close it and retry.');
        }
        $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.1));
    }
    return 'Stopped ' + apps.length + ' local app(s).';
}
