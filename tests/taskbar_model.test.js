const assert = require("assert");
const fs = require("fs");
const path = require("path");
const TaskbarModel = require("../TaskbarModel.js");

function run() {
  // 1. normalizeId & normalizeAddress
  assert.strictEqual(TaskbarModel.normalizeId(" google-chrome.desktop "), "google-chrome");
  assert.strictEqual(TaskbarModel.normalizeId("antigravity"), "antigravity");

  assert.strictEqual(TaskbarModel.normalizeAddress("0x561976dfba10"), "0x561976dfba10");
  assert.strictEqual(TaskbarModel.normalizeAddress("561976dfba10"), "0x561976dfba10");
  assert.strictEqual(TaskbarModel.normalizeAddress("  0xABC123 "), "0xABC123");
  assert.strictEqual(TaskbarModel.normalizeAddress(""), "");
  assert.strictEqual(TaskbarModel.normalizeAddress(null), "");
  assert.strictEqual(TaskbarModel.normalizeAddress("0x123; rm -rf /"), "");
  assert.strictEqual(TaskbarModel.normalizeAddress("0x" + "a".repeat(25)), "");

  // 2. isDockWindow & claimingEntryId
  assert.strictEqual(TaskbarModel.isDockWindow({ key: "foot", hasEntry: true, workspaceId: 1 }), true);
  assert.strictEqual(TaskbarModel.isDockWindow({ key: "foot", hasEntry: false, workspaceId: 1 }), false);
  assert.strictEqual(TaskbarModel.isDockWindow({ key: "foot", hasEntry: false, minimized: true, workspaceId: -1 }), true);
  assert.strictEqual(TaskbarModel.isDockWindow(null), false);

  const entries = [
    { id: "org.omarchy.agent", execString: "foot --app-id=org.omarchy.agent", command: ["agent"], runInTerminal: true },
    { id: "nvim", execString: "", command: ["/usr/bin/nvim"], runInTerminal: true }
  ];
  assert.strictEqual(TaskbarModel.claimingEntryId("org.omarchy.agent", entries), "org.omarchy.agent");
  assert.strictEqual(TaskbarModel.claimingEntryId("org.omarchy.nvim", entries), "nvim");
  assert.strictEqual(TaskbarModel.claimingEntryId("google-chrome", entries), "");

  // 3. buildItems with combined & uncombined apps
  const pinned = ["org.gnome.Nautilus", "google-chrome", "foot"];
  const zeroWins = TaskbarModel.buildItems(pinned, [], ["google-chrome"]);
  assert.strictEqual(zeroWins.length, 3);
  assert.deepStrictEqual(zeroWins[1], {
    key: "google-chrome",
    appKey: "google-chrome",
    pinned: true,
    split: false,
    windows: []
  });

  const wins = [
    { key: "foot", hasEntry: true, workspaceId: 1, address: "0x1", title: "term1" },
    { key: "google-chrome", hasEntry: true, workspaceId: 2, address: "0x2", title: "Tab A" },
    { key: "google-chrome", hasEntry: true, workspaceId: 3, address: "0x3", title: "Tab B" },
    { key: "foot", hasEntry: true, workspaceId: 1, address: "0x4", title: "term2" },
    { key: "chromium", hasEntry: true, workspaceId: 1, address: "0x5", title: "Cr1" },
    { key: "chromium", hasEntry: true, workspaceId: 1, address: "0x6", title: "Cr2" }
  ];
  const splitPinned = TaskbarModel.buildItems(pinned, wins, ["google-chrome"]);
  assert.deepStrictEqual(splitPinned.map(x => [x.key, x.appKey, x.pinned, x.split, x.windows.length]), [
    ["org.gnome.Nautilus", "org.gnome.Nautilus", true, false, 0],
    ["google-chrome::0x2", "google-chrome", true, true, 1],
    ["google-chrome::0x3", "google-chrome", true, true, 1],
    ["foot", "foot", true, false, 2],
    ["chromium", "chromium", false, false, 2]
  ]);

  const unpinnedSplit = TaskbarModel.buildItems(["foot"], wins, ["google-chrome"]);
  assert.deepStrictEqual(unpinnedSplit.map(x => [x.key, x.appKey, x.pinned, x.split, x.windows.length]), [
    ["foot", "foot", true, false, 2],
    ["google-chrome::0x2", "google-chrome", false, true, 1],
    ["google-chrome::0x3", "google-chrome", false, true, 1],
    ["chromium", "chromium", false, false, 2]
  ]);

  // 4. stabilizeWindows order preservation + pruning
  const state = { seq: 0, byAddr: {} };
  const s1 = TaskbarModel.stabilizeWindows([{ address: "0x10" }, { address: "0x20" }], state);
  assert.deepStrictEqual(s1.map(w => w.address), ["0x10", "0x20"]);
  const s2 = TaskbarModel.stabilizeWindows([{ address: "0x20" }, { address: "0x10" }], state);
  assert.deepStrictEqual(s2.map(w => w.address), ["0x10", "0x20"]);
  const s3 = TaskbarModel.stabilizeWindows([{ address: "0x30" }, { address: "0x20" }], state);
  assert.deepStrictEqual(s3.map(w => w.address), ["0x20", "0x30"]);
  assert.strictEqual(state.byAddr["0x10"], undefined);

  // 5. sanitizeTooltipText (control chars, truncation, markup-shaped text pass-through)
  assert.strictEqual(TaskbarModel.sanitizeTooltipText("  Hello\n\tworld   test  ", 96), "Hello world test");
  assert.strictEqual(TaskbarModel.sanitizeTooltipText("abcdefghij", 6), "abcde…");
  assert.strictEqual(
    TaskbarModel.sanitizeTooltipText('<img src="https://example.invalid/x"> Page', 96),
    '<img src="https://example.invalid/x"> Page'
  );

  // 6. browserProfileConfigDir & isValidProfileDir
  assert.strictEqual(TaskbarModel.browserProfileConfigDir("google-chrome", "/home/alice/"), "/home/alice/.config/google-chrome");
  assert.strictEqual(TaskbarModel.browserProfileConfigDir("chromium.desktop", "/home/alice"), "/home/alice/.config/chromium");
  assert.strictEqual(TaskbarModel.browserProfileConfigDir("brave-browser", "/home/alice"), "/home/alice/.config/BraveSoftware/Brave-Browser");
  assert.strictEqual(TaskbarModel.browserProfileConfigDir("firefox", "/home/alice"), "");

  assert.strictEqual(TaskbarModel.isValidProfileDir("Profile 1"), true);
  assert.strictEqual(TaskbarModel.isValidProfileDir(".."), false);
  assert.strictEqual(TaskbarModel.isValidProfileDir("."), false);
  assert.strictEqual(TaskbarModel.isValidProfileDir("foo/bar"), false);
  assert.strictEqual(TaskbarModel.isValidProfileDir("bad\nname"), false);

  // 7. parseChromeProfiles
  assert.deepStrictEqual(TaskbarModel.parseChromeProfiles("{not json", "/tmp"), []);
  const synth = {
    profile: {
      info_cache: {
        "Profile 10": { name: "Ten", user_name: "ten@example.com", gaia_picture_file_name: "pic.png" },
        "Profile 2": { name: "Two\nLine", user_name: "two@example.com", gaia_picture_file_name: "../evil.png" },
        "Profile 1": { name: "One", user_name: "one@example.com" },
        "Default": { name: "Main", user_name: "main@example.com", gaia_picture_file_name: "Google Profile Picture.png" },
        "Profile 3": { name: "Three", user_name: "three@example.com" },
        "Profile 4": { name: "Four", user_name: "four@example.com" },
        "Profile 5": { name: "Five", user_name: "five@example.com" },
        "Profile 6": { name: "Six", user_name: "six@example.com" },
        "CustomDir": { name: "Work", user_name: "work@example.com" },
        "Guest Profile": { name: "Guest" },
        "System Profile": { name: "System" },
        "Profile 99": { name: "Eph", is_ephemeral: true },
        "Profile 98": { name: "Omit", is_omitted_from_profile_list: true },
        "../evil": { name: "EvilDir" }
      }
    }
  };
  const parsed = TaskbarModel.parseChromeProfiles(JSON.stringify(synth), "/home/test/.config/google-chrome/");
  assert.deepStrictEqual(parsed.map(p => p.dir), [
    "Default", "Profile 1", "Profile 2", "Profile 3", "Profile 4", "Profile 5", "Profile 6", "Profile 10", "CustomDir"
  ]);
  assert.strictEqual(parsed[0].picturePath, "/home/test/.config/google-chrome/Default/Google Profile Picture.png");
  assert.strictEqual(parsed[0].initial, "M");
  assert.strictEqual(parsed[2].name, "Two Line");
  assert.strictEqual(parsed[2].picturePath, "");

  // 8. parseHiddenEntryIds, entryName & filterAndSortApps
  const hiddenMap = TaskbarModel.parseHiddenEntryIds("\n btop.desktop \navahi-discover\n\n");
  assert.deepStrictEqual(hiddenMap, { btop: true, "avahi-discover": true });
  assert.strictEqual(TaskbarModel.entryName({ name: "Files", id: "org.gnome.Nautilus" }), "Files");
  assert.strictEqual(TaskbarModel.entryName({ id: "foot" }), "foot");
  assert.strictEqual(TaskbarModel.entryName(null), "");

  const appEntries = [
    { id: "btop", name: "Btop++", genericName: "System Monitor", keywords: ["top"] },
    { id: "avahi-discover.desktop", name: "Avahi SSH", genericName: "Discovery" },
    { id: "hidden-flag", name: "Hidden Flag", noDisplay: true },
    { id: "org.gnome.Nautilus", name: "Files", genericName: "File Manager", keywords: ["folder", "explorer"] },
    { id: "google-chrome", name: "Google Chrome", genericName: "Web Browser", keywords: ["internet"] },
    { id: "foot", name: "Foot", genericName: "Terminal", keywords: ["shell"] },
    { id: "my-file-tool", name: "Quick File Viewer", genericName: "Viewer", comment: "Preview files" },
    { id: "code-visual", name: "Visual Studio Code", genericName: "Text Editor", keywords: ["ide"] }
  ];

  const allVisible = TaskbarModel.filterAndSortApps(appEntries, "", hiddenMap);
  assert.deepStrictEqual(allVisible.map(e => e.id), [
    "org.gnome.Nautilus",
    "foot",
    "google-chrome",
    "my-file-tool",
    "code-visual"
  ]);

  const fileRanked = TaskbarModel.filterAndSortApps(appEntries, "fil", hiddenMap);
  assert.deepStrictEqual(fileRanked.map(e => e.id), [
    "org.gnome.Nautilus",
    "my-file-tool"
  ]);

  const acronymRanked = TaskbarModel.filterAndSortApps(appEntries, "vsc", hiddenMap);
  assert.deepStrictEqual(acronymRanked.map(e => e.id), ["code-visual"]);

  const multiWord = TaskbarModel.filterAndSortApps(appEntries, "web google", hiddenMap);
  assert.deepStrictEqual(multiWord.map(e => e.id), ["google-chrome"]);

  // 9. resolveIconSize
  assert.strictEqual(TaskbarModel.resolveIconSize(26, 0, 14), 16);
  assert.strictEqual(TaskbarModel.resolveIconSize(40, 0, 14), 26);
  assert.strictEqual(TaskbarModel.resolveIconSize(44, 0, 14), 29);
  assert.strictEqual(TaskbarModel.resolveIconSize(40, 28, 14), 28);
  assert.strictEqual(TaskbarModel.resolveIconSize(26, 99, 14), 20);
  assert.strictEqual(TaskbarModel.resolveIconSize(26, 4, 14), 14);

  // 10. Settings & uncombine helpers
  const defaults = TaskbarModel.defaultHyprSettings();
  assert.deepStrictEqual(defaults, {
    snap_layouts: true,
    snap_assist: true,
    aero_snap: true,
    hover_scroll: true,
    soft_maximize: true,
    auto_raise: true,
    shortcuts: true,
    ultrawide_layout: false
  });

  assert.deepStrictEqual(
    TaskbarModel.parseHyprSettings(JSON.stringify({ hover_scroll: false, ultrawide_layout: true, auto_raise: "nope", extra: false })),
    {
      snap_layouts: true,
      snap_assist: true,
      aero_snap: true,
      hover_scroll: false,
      soft_maximize: true,
      auto_raise: true,
      shortcuts: true,
      ultrawide_layout: true
    }
  );
  assert.deepStrictEqual(TaskbarModel.parseHyprSettings("{bad"), defaults);

  assert.deepStrictEqual(
    TaskbarModel.buildUpdatedWidgetEntry({ id: "riisager.windaase", uncombine: ["google-chrome"], iconSize: 28, windowFilter: "workspace" }, "riisager.windaase", { iconSize: 0, uncombine: [], windowFilter: "all" }),
    { id: "riisager.windaase" }
  );
  assert.deepStrictEqual(
    TaskbarModel.buildUpdatedWidgetEntry({ showAppsButton: true }, "riisager.windaase", { iconSize: 24.4, uncombine: ["chromium"], windowFilter: "monitor" }),
    { id: "riisager.windaase", showAppsButton: true, iconSize: 24, uncombine: ["chromium"], windowFilter: "monitor" }
  );

  assert.strictEqual(TaskbarModel.isAppUncombined(["google-chrome.desktop"], "Google-Chrome"), true);
  assert.strictEqual(TaskbarModel.isAppUncombined(["google-chrome"], "foot"), false);
  assert.deepStrictEqual(TaskbarModel.toggleUncombineApp(["google-chrome"], "chromium.desktop"), ["google-chrome", "chromium"]);
  assert.deepStrictEqual(TaskbarModel.toggleUncombineApp(["google-chrome", "chromium"], "Google-Chrome"), ["chromium"]);

  assert.strictEqual(
    TaskbarModel.isTwoLineClockFormat(JSON.stringify({ bar: { layout: { right: [{ id: "omarchy.clock", format: "HH:mm\ndd-MM-yyyy" }] } } })),
    true
  );
  assert.strictEqual(
    TaskbarModel.isTwoLineClockFormat(JSON.stringify({ bar: { layout: { right: [{ id: "omarchy.clock", format: "dddd HH:mm" }] } } })),
    false
  );
  assert.strictEqual(TaskbarModel.isTwoLineClockFormat("{bad"), false);

  // 11. Shared pinned extraction, launch argv & template formatting
  assert.deepStrictEqual(
    TaskbarModel.extractPinnedList(JSON.stringify({ dock: { pinned: ["foot", "google-chrome"] } })),
    ["foot", "google-chrome"]
  );
  assert.strictEqual(TaskbarModel.extractPinnedList("{bad"), null);
  assert.strictEqual(TaskbarModel.extractPinnedList(JSON.stringify({ dock: {} })), null);

  assert.deepStrictEqual(
    TaskbarModel.launchArgvForEntry({ id: "google-chrome" }),
    ["uwsm-app", "--", "gtk-launch", "google-chrome.desktop"]
  );
  assert.deepStrictEqual(
    TaskbarModel.launchArgvForEntry({ id: "org.gnome.Nautilus.desktop" }),
    ["uwsm-app", "--", "gtk-launch", "org.gnome.Nautilus.desktop"]
  );
  assert.deepStrictEqual(
    TaskbarModel.launchArgvForEntry({ id: "nvim", runInTerminal: true, command: ["nvim", "%F", "%u"] }),
    ["omarchy-launch-tui", "nvim"]
  );
  assert.deepStrictEqual(TaskbarModel.launchArgvForEntry(null), []);

  assert.strictEqual(TaskbarModel.formatTemplate("[Minimeret] %1", "Docs $HOME"), "[Minimeret] Docs $HOME");
  assert.strictEqual(TaskbarModel.formatTemplate("%1 (%2)", "Chrome", "3"), "Chrome (3)");
  assert.strictEqual(TaskbarModel.formatTemplate("appGrid.noAppsMatch", ""), "appGrid.noAppsMatch");

  // 12. v1.1 scope filter, Snap Layouts keyboard navigation & Snap Assist helpers
  assert.strictEqual(TaskbarModel.normalizeWindowFilter("workspace"), "workspace");
  assert.strictEqual(TaskbarModel.normalizeWindowFilter("MONITOR"), "monitor");
  assert.strictEqual(TaskbarModel.normalizeWindowFilter("unknown"), "all");

  assert.strictEqual(TaskbarModel.minimizedOriginWorkspaceId(["omarchy-floating-workspace", "omarchy-minimized-from-3"]), 3);
  assert.strictEqual(TaskbarModel.minimizedOriginWorkspaceId(["omarchy-showdesktop-2"]), 2);
  assert.strictEqual(TaskbarModel.minimizedOriginWorkspaceId([]), -1);

  const scopeWins = [
    { key: "foot", address: "0x1", workspaceId: 1, monitorName: "DP-1", minimized: false, tags: [] },
    { key: "google-chrome", address: "0x2", workspaceId: 2, monitorName: "DP-2", minimized: false, tags: [] },
    { key: "obsidian", address: "0x3", workspaceId: -1, monitorName: "DP-1", minimized: true, tags: ["omarchy-minimized-from-1"] },
    { key: "spotify", address: "0x4", workspaceId: -1, monitorName: "DP-2", minimized: true, tags: ["omarchy-minimized-from-2"] }
  ];
  assert.deepStrictEqual(TaskbarModel.filterWindowsByScope(scopeWins, "all", 1, "DP-1").map(w => w.key), ["foot", "google-chrome", "obsidian", "spotify"]);
  assert.deepStrictEqual(TaskbarModel.filterWindowsByScope(scopeWins, "workspace", 1, "DP-1").map(w => w.key), ["foot", "obsidian"]);
  assert.deepStrictEqual(TaskbarModel.filterWindowsByScope(scopeWins, "monitor", 1, "DP-1").map(w => w.key), ["foot", "obsidian"]);

  assert.deepStrictEqual(
    TaskbarModel.complementaryZone({ rx: 0, ry: 0, rw: 0.5, rh: 1.0, max: false }),
    { rx: 0.5, ry: 0, rw: 0.5, rh: 1.0, max: false }
  );
  assert.deepStrictEqual(
    TaskbarModel.complementaryZone({ rx: 0.65, ry: 0, rw: 0.35, rh: 1.0, max: false }),
    { rx: 0, ry: 0, rw: 0.65, rh: 1.0, max: false }
  );
  assert.strictEqual(TaskbarModel.complementaryZone({ rx: 0, ry: 0, rw: 0.5, rh: 0.5, max: false }), null);
  assert.strictEqual(TaskbarModel.complementaryZone({ rx: 0.3333333, ry: 0, rw: 0.3333333, rh: 1.0, max: false }), null);
  assert.strictEqual(TaskbarModel.complementaryZone({ rx: 0, ry: 0, rw: 1.0, rh: 1.0, max: true }), null);

  const layoutsJson = JSON.parse(fs.readFileSync(path.join(__dirname, "../layouts.json"), "utf8"));
  const snapCards = layoutsJson.layouts.concat([layoutsJson.ultrawideLayout]);
  assert.strictEqual(snapCards.length, 7);
  assert.deepStrictEqual(TaskbarModel.nextSnapZone(snapCards, 0, 0, "right"), { card: 0, zone: 1 });
  assert.deepStrictEqual(TaskbarModel.nextSnapZone(snapCards, 0, 1, "right"), { card: 1, zone: 0 });
  assert.deepStrictEqual(TaskbarModel.nextSnapZone(snapCards, 2, 1, "down"), { card: 2, zone: 2 });
  assert.deepStrictEqual(TaskbarModel.nextSnapZone(snapCards, 2, 1, "left"), { card: 2, zone: 0 });
  assert.deepStrictEqual(TaskbarModel.nextSnapZone(snapCards, 4, 0, "down"), { card: 4, zone: 2 });
  assert.deepStrictEqual(TaskbarModel.nextSnapZone(snapCards, 0, 0, "left"), { card: 6, zone: 2 });
  assert.deepStrictEqual(TaskbarModel.jumpToSnapCard(snapCards, 3, 0, 0), { card: 2, zone: 0 });
  assert.deepStrictEqual(TaskbarModel.jumpToSnapCard(snapCards, 3, 2, 0), { card: 2, zone: 1 });
  assert.deepStrictEqual(TaskbarModel.jumpToSnapCard(snapCards, 7, 0, 0), { card: 6, zone: 0 });
  assert.strictEqual(TaskbarModel.jumpToSnapCard(snapCards, 8, 0, 0), null);

  const assistPool = [
    { address: "0x1", workspaceId: 1, minimized: false, floating: true, fullscreen: false, title: "Snapped" },
    { address: "0x2", workspaceId: 1, minimized: false, floating: true, fullscreen: false, title: "Target" },
    { address: "0x3", workspaceId: 1, minimized: false, floating: false, fullscreen: false, title: "Tiled" },
    { address: "0x4", workspaceId: 1, minimized: true, floating: true, fullscreen: false, title: "Min" },
    { address: "0x5", workspaceId: 2, minimized: false, floating: true, fullscreen: false, title: "OtherWS" }
  ];
  assert.deepStrictEqual(
    TaskbarModel.filterSnapAssistCandidates(assistPool, "0x1", 1).map(w => w.address),
    ["0x2"]
  );
  assert.deepStrictEqual(
    TaskbarModel.filterSnapAssistCandidates(
      [
        { address: "0xabc123", workspaceId: 1, minimized: false, floating: true, fullscreen: false, title: "Snapped" },
        { address: "0xDEF456", workspaceId: 1, minimized: false, floating: true, fullscreen: false, title: "Target" }
      ],
      "0xABC123",
      1
    ).map(w => w.address),
    ["0xDEF456"]
  );

  // Verify i18n JSON files cover all 50 Omarchy locales cleanly with exact key & placeholder parity
  const i18nDir = path.join(__dirname, "../i18n");
  const omarchyLocalesPath = "/usr/share/omarchy/default/i18n/locales.json";
  const fallbackLocales = [
    "ar", "bg", "bn", "ca", "cs", "da", "de", "el", "en", "es-MX",
    "et", "fa", "fi", "fil", "fr", "ga", "he", "hi", "hr", "hu",
    "id", "is", "it", "ja", "ko", "lt", "lv", "ms", "nl", "no",
    "pl", "pt", "pt-BR", "ro", "ru", "si", "sk", "sl", "sr", "sv",
    "sw", "ta", "th", "tr", "uk", "ur", "uz", "vi", "zh-CN", "zh-TW"
  ];
  let expectedLocales = fallbackLocales;
  if (fs.existsSync(omarchyLocalesPath)) {
    const rawLocales = JSON.parse(fs.readFileSync(omarchyLocalesPath, "utf8"));
    const list = Array.isArray(rawLocales)
      ? rawLocales
      : (rawLocales.locales || Object.keys(rawLocales));
    expectedLocales = list.map((entry) =>
      typeof entry === "string" ? entry : (entry.code || entry.id || entry.locale)
    );
  }
  assert.strictEqual(expectedLocales.length, 50, "Expected 50 Omarchy locales");

  const actualFiles = fs.readdirSync(i18nDir).filter((f) => f.endsWith(".json")).sort();
  const expectedFiles = expectedLocales.map((loc) => `${loc}.json`).sort();
  assert.deepStrictEqual(actualFiles, expectedFiles, "i18n directory must match the 50 Omarchy locales exactly");

  const en = JSON.parse(fs.readFileSync(path.join(i18nDir, "en.json"), "utf8"));
  const enKeys = Object.keys(en).sort();
  assert.strictEqual(enKeys.length, 49, "Expected 49 keys in en.json");

  const placeholders = (str) => [...(str.match(/%[12]/g) || [])].sort();

  for (const loc of expectedLocales) {
    const file = path.join(i18nDir, `${loc}.json`);
    const catalog = JSON.parse(fs.readFileSync(file, "utf8"));
    assert.deepStrictEqual(Object.keys(catalog).sort(), enKeys, `Key parity mismatch in ${loc}.json`);
    for (const key of enKeys) {
      const val = catalog[key];
      assert.strictEqual(typeof val, "string", `${loc}.${key} must be a string`);
      assert.ok(val.trim().length > 0, `${loc}.${key} must be non-empty`);
      assert.deepStrictEqual(
        placeholders(val),
        placeholders(en[key]),
        `Placeholder mismatch in ${loc}.json key ${key}`
      );
    }
  }

  console.log("ALL TASKBAR MODEL & I18N TESTS PASSED");
}

run();
