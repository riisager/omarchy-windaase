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

  // Verify i18n JSON files are valid and carry matching keys
  const en = JSON.parse(fs.readFileSync(path.join(__dirname, "../i18n/en.json"), "utf8"));
  const da = JSON.parse(fs.readFileSync(path.join(__dirname, "../i18n/da.json"), "utf8"));
  assert.deepStrictEqual(Object.keys(en).sort(), Object.keys(da).sort());

  console.log("ALL TASKBAR MODEL & I18N TESTS PASSED");
}

run();
