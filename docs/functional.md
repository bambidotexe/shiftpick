# ShiftPick — what it does

**The authority on behaviour.** Every rule the app is held to, with its numbers. It is kept in sync with
the code in the same commit as any change, and it never carries an outdated rule: one the owner has
overruled is replaced, not annotated.

Numbers are interpolated from `Sources/ShiftPickCore/Constants.swift` (`K`) wherever one appears; the value
in the code is the one that counts.

---

## 1. Which clicks ShiftPick looks at

ShiftPick holds **two session event taps**, and they are not alike.

- **The sentinel only listens.** It hears the modifier keys change and the left button go down, and nothing
  else: no moves, no drags, no key presses. macOS does not wait for a listening tap, so nothing that happens
  to ShiftPick can make it hold an event up. It is on for as long as the app is watching.
- **The click tap can swallow a click**, which is the whole feature and the one thing in the app that could
  hold up the Mac's input. It is subscribed to **the left button going down and coming up and nothing
  else**; it is **created disabled, and it is enabled only while ⇧ Shift is held**, or while a press it
  swallowed is still waiting for its release. With no finger on ⇧ Shift, no click on the Mac passes through
  ShiftPick at all.

**Both taps are created on a live answer about the grant, never on the cached one alone.** The one
exception is the launch itself: a process that has just started reads the grant as it is. After that, a start
asked for by a grant that seems to have arrived, by the wizard's poll or by another try first asks the live
question of step 3 below, and creates nothing unless the answer is yes. A tap macOS refuses to create is said
once in the log, however often it is asked for again.

**Arming**, when ⇧ Shift goes down:

1. **The kill switch is read first.** With *Enable ShiftPick* off nothing is armed, every click goes straight
   to the system, and no anchor is looked for. It takes effect on the next press of ⇧ Shift, not on the next
   launch.
2. **⌥ Option or ⌃ Control held with it arms nothing, and pressing either while armed disarms**: both mean
   something else in Finder, and neither is ShiftPick's to take. Letting go of it with ⇧ Shift still down arms
   again.
3. **The grant is asked about first, live.** A real Accessibility request is made of the Dock, and an answer
   no older than **`K.trustFreshness` (2 s)** is reused, so a burst of capital letters asks once. **An answer
   only counts if it was asked after the grant was last put in doubt**: a privacy notification, a tap macOS
   took away and a Mac coming back each make every answer still on its way worthless. A refusal takes both
   taps down (§7). No answer within **`K.trustProbeTimeout` (50 ms)** arms nothing and takes the last
   answer's word away too, so the next press asks again. The keys are looked at again when the answer comes:
   a key let go meanwhile arms nothing.
4. The click tap is enabled. Releasing ⇧ Shift disables it again.

While it is armed, a click **with ⇧ Shift and without ⌥ Option or ⌃ Control** is a **⇧ Shift click**, and §2
decides it. Any other click is returned at once.

**What is under the cursor decides, never which app is frontmost.** The hit test asks the window server
what it draws at that point, so a Finder window behind another application's window does not answer for a
point that window covers, and a Desktop icon or a background Finder window answers while another
application is in front.

**A swallowed press swallows its release, and only its own.** Finder applies its ⇧ Shift toggle on the
mouse-up, so letting the release through would undo the range on the file that was clicked. macOS gives a
press and its release the same event number, which is how the release is recognised, and the tap stays armed
until it has come even if ⇧ Shift is let go first. A press that is let through forgets the one before it, so
a release that never arrives cannot swallow somebody else's. **When the tap has to go while a button is
down** (the grant put in doubt, a trip, the Mac going away), the release reaches Finder, which toggles the
clicked file: a selection one file short, in a rare moment, and the price of never leaving the tap enabled.

**A watch is kept while the tap is armed, and only then.** Every **`K.armedWatchInterval` (0.5 s)** the
keyboard itself is asked whether ⇧ Shift is still down and ⌥ Option and ⌃ Control are not, and the grant is
asked about again. **It disarms rather than wait**, on any of three: the keys no longer asking for it and
nothing having said so; **`K.armedIdleLimit` (60 s)** with nothing clicked, so a key held down by a bag, or
latched by Sticky Keys, does not keep the tap enabled for hours; and the last look's question about the grant
still unanswered at the next look. Most ⇧ Shift clicks are over before the first look.

**If macOS takes the click tap away, it is never enabled again by the event that says so.** macOS gives two
reasons, and they are not alike:

- **A timeout** is a callback the window server gave up waiting for, which is what a revoked grant under an
  enabled tap looks like. macOS disabling that tap is the system's own safety net, and it is left whole. The
  tap stays disabled, the log says so, the grant is looked at again, and the next press of ⇧ Shift arms it
  through the same questions as any other. **`K.breakerTrips` (3) timeouts inside `K.breakerWindow` (60 s)**
  and ShiftPick destroys both taps and stops creating them: the menu and Settings › System say so, and turning
  *Enable ShiftPick* off and on again is what asks for another try, which still asks the live question first.
  Nothing else closes it and nothing else starts the count over: not a launch of the wizard, not the grant
  going and coming back.
- **User input** is also what macOS says back to a tap ShiftPick disables itself, which it does right after
  creating the click tap and at every disarm. **It is never counted.** Heard with the tap armed, it disarms;
  heard otherwise, it is the tap's own disable and nothing is done, above all not a second disable, which
  would be heard back in turn.

**Nothing is armed while nobody can be clicking**: the Mac asleep, the screen locked, another user's session
in front. **The reasons are counted**: closing a lid both sleeps and locks, and the way back can wake the Mac
with the lock screen still up, so each reason is ended by its own notification and nothing arms until none is
left. Taps created meanwhile arm nothing either. Coming back asks about the grant again before anything
arms. **And no notification is trusted to arrive**: whenever there is news of any kind, a notification of
coming back or somebody pressing ⇧ Shift while the Mac is said to be away (at most every
**`K.awayCheckInterval` (5 s)**), the reasons are held against what the session says itself. A lost unlock
therefore costs that one press, which goes to Finder, and never leaves ShiftPick asleep with Settings
saying it is listening.

**Both taps are destroyed before anything that takes the grant or the process away**: a quit, which is also
how an update begins (§8, where the helper touches nothing until the process has gone), and an uninstall,
before it resets the grant (§9).

**One ShiftPick at a time.** A second copy started while one is running asks the first for its window and
leaves before it has created anything.

## 2. One ⇧ Shift click

In this order. **Any step that cannot answer returns the event unmodified**, and Finder does what it has
always done.

1. **Find Finder.** Its pid is remembered until the process it names has gone.
2. **Hit-test the point.** The result has to be an icon in a Finder icon view: an item in a window's icon
   view or on the Desktop. A hit on the gap between two icons, on a group's header, on the space under the
   last row, on a list view, on the sidebar, on a toolbar or on another application is not.
3. **Refuse a rename.** While a name is being typed in place, Finder's focused element is a text field and
   the click belongs to it.
4. **Read the view.** Every icon it is showing, each one's frame, which group it is in and the order
   Accessibility listed it in. On the Desktop, also whether it is a file at all.
5. **Find the anchor** (§2.1).
6. **Work out the range** (§3).
7. **Set the selection.** One call, whatever the size of the range. With ⌘ Command held and the switch on,
   the range is added to what was already selected instead of replacing it; with the switch off, a ⌘ Command
   ⇧ Shift click is left to Finder entirely.
8. **Swallow the click**, and its release.
9. **Do what the click would have done besides selecting**: bring Finder forward, and raise the window
   that was clicked. The Desktop has no window, so making Finder frontmost is the whole of it. The press has
   been answered by then, so nobody's click waits for this part.

**The work happens on a worker, and the thread that holds the click waits for it `K.clickBudget` (150 ms)
and no longer.** Past that the event is returned whatever the worker is doing; the worker is told, stops at
the next thing it was about to ask, and sets nothing. If the budget runs out at the very moment the selection
is being set, that one call is waited for, for at most **`K.commitGrace` (100 ms)** more: letting the click
through then would have Finder toggle the clicked file on top of the range. **A click never queues**: one
that arrives while the worker is still busy with the click before is returned at once. Every Accessibility
element is given **`K.axTimeout` (100 ms)**, which sits under the budget so that one call that never answers
cannot spend all of it. Measured: one frame read costs about 0.06 ms warm, so a full screen of icons costs 6
to 20 ms.

### 2.1 Where a range is measured from

- **A plain click or a ⌘ Command click on an icon sets the anchor.** The sentinel hears it, and the click
  itself is never held. The anchor is looked for **`K.anchorDelay` (60 ms) later**, on the worker, and only if
  the application that owns the view is frontmost by then, so an ordinary click gains no latency and a click
  that went to another application sets nothing.
- **A plain click on empty space inside an icon view clears the anchor.** Finder has just deselected
  everything. A click outside Finder leaves it alone.
- **A ⇧ Shift click does not move the anchor.** Widening and narrowing a range are both measured from the
  same file.
- **The anchor is per container**: each window has its own, and the Desktop has its own.
- **If the stored anchor is gone, stale, or in another container**, it is derived from what is selected in
  the container that was clicked: **the selected file farthest from the target**. That is one rule, and it
  gives the selected file nearest the start of the range when the target comes after the selection, the one
  nearest the end when it comes before, and the widest range the selection justifies when the target is
  inside it. Distance is counted in flow order where there is one and across the screen where there is not.
- **If nothing is selected there either, the click goes through.**

## 3. What "between" means

There is no order Finder can be asked for in every context, so the range is worked out from where the icons
are. All of it is pure arithmetic over rectangles (`Core/LayoutModel.swift`), and all of it is unit-tested.

1. **The reference point of an icon is the centre of its frame.** Measured: Finder reports the icon's own
   box and not its cell, so a name that wraps to two lines does not move it.
2. **The lattice.** The reference points are clustered into rows and columns. The tolerance is half the
   median distance between two lines, which is itself measured from a first, coarse pass at a quarter of an
   icon's side.
3. **The layout is one of two things.**
   - **Arranged**: inside every group, the occupied cells are the first *n* cells of some fill order. No
     hole, nothing off the lattice; a partial last line is allowed and every group starts a new line.
     Finder is laying these out, so the order is meaningful.
   - **Hand-placed**: anything else. Holes in the lattice, icons that are not on one, a line that only
     exists because a scatter chained together.
4. **The fill order**, for an arranged layout, is one of four: rows down the screen filled from the left or
   from the right, or columns filled downwards with the next column to the right or to the left. It is
   inferred from the icons; where several fit, which is what one row, one column and a single icon always
   look like, the order Accessibility listed the items in decides, and where that says nothing the
   container's own default does: **rows from the leading edge in a window, columns from the trailing edge
   on the Desktop**, both measured, and both flipped for a right-to-left layout.
5. **The range.**
   - **Arranged**: every icon between the anchor and the target in fill order, inclusive. Groups count from
     the top of the view downwards, with the fill order inside each of them.
   - **Hand-placed**: the anchor, the target, and every icon whose reference point falls inside the
     rectangle their two frames span. A rubber band drawn between the two icons.
6. **A collapsed Desktop stack is not a file.** It is never in a range, and a ⇧ Shift click whose anchor or
   target is one goes through. It does hold its place in the lattice, because that is where it is drawn.
7. **Three properties, pinned by `RangeSelectionTests`.** The range always holds both ends; anchor to
   target is the same set as target to anchor; and it is `O(n log n)`, worked out for five thousand icons
   in a test that runs in milliseconds.

**A range is only ever as complete as what Finder is showing.** Finder builds the icons that are on screen
and a little beyond, and no more, so both ends have to be visible. When one is not, the anchor reads as
gone, nothing usable is selected, and the click goes through: a smaller selection nobody noticed was
smaller would be worse. `docs/pitfalls.md` has the measurement.

## 4. Where it works

Every Finder icon view and the Desktop. Folders, search results, Recents, tags, iCloud Drive. Every Sort By
mode, with or without **Use Groups**, with or without **Stacks**, and a folder nobody has sorted at all.
**No setting restricts where it works**, because there is no place it should not.

**And Open and Save panels shown as icons**, whichever application put them up. Measured: a panel's icon
view has Finder's hierarchy identifier for identifier, and its own ⇧ Shift click has exactly the same gap,
adding the one item under the pointer. A panel is recognised by its window's `AXIdentifier`, `open-panel`
or `save-panel`, because it belongs to the application that opened it and not to Finder; nothing about the
Finder path changes for it. Two things differ:

- The application brought forward when the click is swallowed is the panel's own, not Finder.
- The rename check is not made. A Save panel keeps its name field focused the whole time it is up, so the
  same question asked of a panel would refuse every click in it.

List, column and gallery views are untouched: Finder already selects a range in all three.

## 5. Settings

A window of four pages, opened from the menu-bar item (⌘,) or by opening the app again. Its shape, its
numbers and its copy are the `macos-building-settings-pages` skill's, not this document's.

| Page | Group | Rows |
|---|---|---|
| **General** | the app icon, alone | |
| | Startup | Launch at login · Show in menu bar. A note names the way back to this window when the icon is hidden. |
| | Updates | `ShiftPick <version>` with the last answer as its mark · one button, *Check for Updates* or *Update* |
| | Quit | one destructive button |
| | Uninstall | one destructive button, with a warning that never goes away |
| **Selection** | ⇧ Shift-click | Enable ShiftPick · ⌘ Command with ⇧ Shift adds the range to the selection, under it and disabled with it |
| **System** | Accessibility | the permission, live and **as ShiftPick can use it**: macOS's answer, except once ShiftPick has found the grant gone itself, which that answer can go on hiding for seconds (§7). While it is denied, a button to the pane and a warning naming the switch; once granted both go and the row stays. |
| | Clicks | whether ShiftPick is watching. Its warning tells *off on purpose* from *macOS refused the taps* and from *macOS kept taking the click tap away* (§1), and that last one names the way back: *Enable ShiftPick* off and on again. |
| | Start over | one button, *Show Onboarding Again*, which opens a fresh wizard at its first page |
| **Tip** | the app icon beside one sentence, in a card with no title | every feature is free and stays free, and a coffee is how the project is supported |
| | One-time tip | the Ko-fi cup, *A cup of coffee*, what it is, and a button naming the smallest tip the page takes (`SupportLink.smallestTip`, 5 €). It opens `https://ko-fi.com/bambidotexe` in the browser; nothing is paid inside the app. |

Defaults: **Enable ShiftPick on**, **⌘ Command adds on**, **Show in menu bar on**. Launch at login is the
system's answer and is not stored here. `onboardingCompleted` is stored beside the three switches and is not
a setting: no window shows it, and Start over opens the wizard rather than clearing it.

Settings are one JSON blob in `UserDefaults`. A key missing from a file written by an older build falls back
to its default instead of resetting the others.

## 6. The menu-bar item

Rebuilt from scratch every time it is opened, so it is never a language or a state behind.

```
Enable ShiftPick            ✓
──────────
Launch at Login             ✓
──────────
<what it is doing right now>        (not clickable)
──────────
Settings…                   ⌘,
──────────
Quit ShiftPick              ⌘Q
```

The status line is one of five: *Watching for ⇧ Shift clicks*, *Off: Finder handles every click*, *Waiting
for the Accessibility permission*, *macOS refused the click listener*, *Stopped: macOS kept interrupting the
click listener*.

Hiding the icon leaves the app working. Opening the bundle again from the Applications folder or Spotlight
is then the way back to the Settings window.

## 7. The permission, and the onboarding wizard

Its shape, its numbers and every trap it avoids are the `macos-building-onboarding` skill's, not this document's.

**The wizard** is a titled, closable, fixed 540 wide window, stepping through four pages with one button at
the bottom right. Its height follows the page around its **top-left** corner: 440, 440, 440, 400.

| Page | What is on it | Its button |
|---|---|---|
| 1 | the app icon, the headline with one word in the icon's blue, what the app does, three capsules: *Icon views*, *Desktop*, *Open and Save* | Continue |
| 2 | **Permission**: one row, the Accessibility grant, marked required | *Skip* until it is granted, then *Continue* |
| 3 | **Where it lives**: *Open at Login* and *Show in menu bar*, both optional, each with *Turn On* or *Turn Off* | *Skip* until either is on, then *Continue* |
| 4 | **All set**: the gesture in one sentence, and where the menu-bar item is | Finish |

- **It opens on a first run the person started**, whatever the grants are, and on **any** launch that finds
  Accessibility missing, however the app was launched. A login item whose wizard was simply never finished
  opens no window. **Opening the app again asks the same question**, so while the wizard is unwalked that is
  what comes up rather than the Settings window, and while it is already up it is simply brought forward; a
  reinstall opens no window at all, so that is the first thing a person does afterwards.
  **Settings › System › Start over** opens it whenever it is wanted. It is a **fresh controller every time**:
  every row re-reads the system and the walk starts at page one.
- **Finish records that it was walked**; a window closed before that button keeps the flag false, so the
  wizard returns at the next launch.
- **The row's button is the only thing in the whole app that asks macOS for the permission.** Nothing at
  launch, nothing when a window opens, nothing "once, to get it out of the way": a prompt nobody clicked for
  arrives with no explanation beside it, and macOS remembers a refusal for good. The system's dialog carries
  its own way to the pane, so nothing opens a pane beside it or instead of it after a refusal.
- **The row shows the grant as ShiftPick can use it**, and so do the System page's row, the menu and the
  choice between the wizard and Settings when the app is opened again: macOS's own answer, except once
  ShiftPick has found the grant gone itself. That answer was measured saying yes for seconds after the grant
  had gone, so a row that believed it alone showed *Granted* while nothing was listening.
- **The grant arriving does not close the wizard.** The taps are created as soon as a live answer agrees, with
  no relaunch; the row ticks over to *Granted* and the button turns from *Skip* to *Continue*. Closing it is the
  user's move. It is noticed two ways: the system's `com.apple.accessibility.api` notification, which costs
  nothing while nothing happens and after which the grant is looked at again **`K.trustRecheckDelays` (0.25 s,
  1 s and 3 s)** later, because that notification has been seen to arrive before the answer changes; and the
  wizard's **`K.onboardingPollInterval` (2 s)** tick.
- **A grant taken away destroys both taps at once and brings the wizard back**, unless it is already up. It
  is noticed four ways, and none of them is relied on alone: the notification, which **disarms the click tap
  before anything is asked**; the live question every arming asks (§1); any Accessibility call that comes
  back refused; and the watch kept while armed. **`AXIsProcessTrusted()` alone never keeps a tap enabled**:
  it has been seen to go on saying yes after the grant had gone.
- **Who is in front.** The wizard is an ordinary window at the ordinary level, with the default collection
  behaviour: the Accessibility dialog and System Settings open over it and stay there. The app is activated
  once, when the window opens. Two things bring it back afterwards and nothing else: **System Settings
  quitting** (`K.focusReturnWait`, 300 s, after which the wait is dropped) and the app becoming active while
  the wizard is its only window, which orders it front without activating.
- **Nothing else polls, ever.** The wizard starts its one timer when it opens and stops it when it closes.
  With the permission granted and no window open, ShiftPick arms no timer at all except the update
  schedule's, and **the watch kept while ⇧ Shift is held (§1), which exists only for as long as the key is
  down**. The looks after a notification are three, and then nothing.

## 8. Updates

- **The check** is an anonymous request to GitHub for the repository's latest release. A release has to
  carry a tag that parses as a version and an asset whose name ends in `.dmg`. A 404 means *no release
  published*, which is also what a repository an anonymous caller cannot see looks like; it is not a
  failure.
- **The schedule**: **`K.updateLaunchDelay` (20 s)** after launch, then **`K.updateInterval` (a week)** after
  the last check that got an answer, asked again at every wake, and retried after **`K.updateRetryDelay`
  (an hour)** when one could not reach GitHub. Nothing is kept across launches.
- **A release found without being asked for** is announced by one notification, which replaces the one
  before it. Permission for notifications is asked the first time there is something to say, and for
  nothing else.
- **The update window** fetches the image, holds it against the length and SHA-256 GitHub stated, mounts
  it, copies the app out, and checks that copy before enabling anything: same bundle identifier, strictly
  newer, runs on this macOS, **signed by the same team as the running app**.
- **Install and Relaunch** starts a detached helper and quits through the ordinary quit, which destroys both
  event taps on its way out. **The helper is only started on a plan that names nothing it should not touch**:
  what is replaced is an app bundle, and everything it removes or writes is inside ShiftPick's own updates
  folder. A plan that fails that is refused before anything is written, and the window says the update
  could not be installed. The helper waits
  for the process to go, renames the old bundle aside, renames the new one in, opens it, and **puts the old
  one back if the new version is not seen running**. It leaves one line behind, which the next launch reads
  and shows.
- **An update never installs by itself.** The automatic check only announces; the fetch and the install
  each need a click. If the app has not quit **`K.updateStallNotice` (8 s)** after Install and Relaunch, the
  helper is stopped and the window says so, so that a later quit is only ever a quit.

## 9. Uninstalling

**Settings › General › Uninstall**, after an alert that says what will go. In this order:

0. **Both event taps are destroyed**, before anything else and for good. The next step takes the grant away,
   and an enabled click tap whose owner has just lost it stalls every click on the Mac (§1).
1. The **Accessibility grant** and the **login item**, while the bundle they both name is still where they
   name it. `tccutil reset` against a bundle identifier with no bundle behind it fails, and nothing puts
   that right afterwards.
2. The **bundle to the Trash**, not deleted: the app the user has just removed is still there to put back.
3. The **preferences and the support folder**, handed to a detached helper that waits for this process to
   go. `cfprefsd` writes the domain out again as the process exits whatever happens, so removing them in
   the app leaves an empty plist where a Mac that never had ShiftPick has no file at all. **The helper is
   only started when every path it would remove is provably ShiftPick's own**: a bundle identifier that is
   one, a home folder that is one, and exactly one folder directly inside that home's Application Support.
   Otherwise nothing is removed, and the last alert says so.
4. The app quits. Whatever could not be done is named, with what the system said about it.

**The window stays responsive the whole time.** Steps 1 and 2 wait on other processes, so they run off the
main thread, each within **`K.uninstallStepWait` (10 s)**: one that does not answer in time is named in the
last alert (*macOS did not answer in time*) and the uninstall goes on without it. The window's own refresh of
the grant and the login item is paused meanwhile, the button is disabled, and every step is logged with what
came back and how long it took.

**Only what is ShiftPick's own is touched, and only through the system's own tools.** The answer once given
to "may ShiftPick send notifications" stays where macOS keeps it, and a reinstall inherits it: putting it
back would mean rewriting another program's private database.

**Dragging the bundle to the Trash is not an uninstall**, and the Uninstall group says so permanently: the
Login Items entry and the Accessibility grant would stay, pointing at an app that is gone.

## 10. The words

Every sentence the user reads is in **English and French**, picked from the system language at launch, with
English the fallback for every other language. They live in `Core/Strings*.swift`, one table per surface,
one accessor per sentence switching over the language, so a sentence cannot exist in one language alone.

The copy rules are the `macos-building-settings-pages` skill's. The two `LocalizationTests` enforce here: **no
dash longer than the one on the keyboard**, anywhere; and **a key is its symbol then its name** at every
mention, ⇧ Shift, ⌘ Command, ⌥ Option, ⌃ Control. The app's own name is never translated and never spelt
out in a table: it is read from the bundle, so renaming the app carries through.
