# ShiftPick — what it does

**The authority on behaviour.** Every rule the app is held to, with its numbers. It is kept in sync with
the code in the same commit as any change, and it never carries an outdated rule: one the owner has
overruled is replaced, not annotated.

Numbers are interpolated from `Sources/ShiftPickCore/Constants.swift` (`K`) wherever one appears, and the
inferred grids' tolerances from `LayoutConstants.swift`, which extends the same `K`; the value in the code is
the one that counts.

---

## 0. The guarantees

**A bug in this app must never be able to break clicking.** The sections below are the rules the app
follows; these are the rules every other one is held to. **A request that would loosen one is a conflict**
under step 2 of the workflow in `CLAUDE.md`: the rule is quoted to the owner, and nothing changes until the
owner has said so for that rule. `SafetyNetTests` and the `TapLifecycle` tests pin each of them, and the
`shiftpick-safety-nets` skill says where each one lives in the code.

1. **One tap can swallow a click, and it is enabled only while ⇧ Shift is held**, or while a press it
   swallowed waits for its release. The other only listens. §1.
2. **A tap macOS disabled is never enabled by the event that says so**, and after **`K.breakerTrips` (3)**
   timeouts inside **`K.breakerWindow` (60 s)** no tap exists until the user asks for another try. §1.
3. **Nothing arms the click tap or creates the taps on the cached answer about the grant**, the launch alone
   excepted. Arming asks a live question; a grant put in doubt disarms first and asks afterwards. §1, §7.
4. **A held click waits at most `K.clickBudget` (150 ms)**, and **`K.commitGrace` (100 ms)** more only while
   its range is being selected, whatever the worker is doing. A click never queues behind another. §2.
5. **A click is swallowed only once its range has been selected.** Every other path returns it unmodified,
   and its release goes with it. §1, §2.
6. **Nothing a window does can delay a click.** The taps are served on a thread of their own, which never
   calls Accessibility and never waits without a deadline. §2, and `docs/architecture.md` *Threading*.
7. **Nothing is armed while nobody can be clicking**: the Mac asleep, the screen locked, another user's
   session in front. §1.
8. **Both taps are destroyed before anything takes the grant or the process away**: a quit, an update, an
   uninstall. §1, §8, §9.
9. **Nothing waits on another process on the main thread**, and every step of the uninstall has a deadline.
   §9.
10. **One ShiftPick at a time.** §1.
11. **Every permission prompt follows a click of the user's.** §7.
12. **Nothing is deleted that is not provably ShiftPick's own.** §8, §9.

## 1. Which clicks ShiftPick looks at

ShiftPick holds **two session event taps**, and nothing else that touches the event stream: no other tap, no
`NSEvent` global monitor, and it never posts an event. The two are not alike.

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
question of step 2 below, and creates nothing unless the answer is yes. A tap macOS refuses to create is said
once in the log, however often it is asked for again.

**Arming**, when ⇧ Shift goes down:

1. **⌥ Option or ⌃ Control held with it arms nothing, and pressing either while armed disarms**: both mean
   something else in Finder, and neither is ShiftPick's to take. Letting go of it with ⇧ Shift still down arms
   again.
2. **The grant is asked about first, live.** A real Accessibility request is made of the Dock, and an answer
   no older than **`K.trustFreshness` (2 s)** is reused, so a burst of capital letters asks once. **An answer
   only counts if it was asked after the grant was last put in doubt**: a privacy notification, a tap macOS
   took away and a Mac coming back each make every answer still on its way worthless. A refusal takes both
   taps down (§7). No answer within **`K.trustProbeTimeout` (50 ms)** arms nothing and takes the last
   answer's word away too, so the next press asks again. The keys are looked at again when the answer comes:
   a key let go meanwhile arms nothing.
3. The click tap is enabled. Releasing ⇧ Shift disables it again.

**Nothing a user sets stops any of that.** ShiftPick has no setting about what it does (§5): a ⇧ Shift press
arms whenever the keys ask for it and the grant answers.

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
  and ShiftPick destroys both taps and stops creating them: the menu and Settings › Health and System say so,
  and **Start Listening Again**, on the System page, is what asks for another try, which still asks the live
  question first. That button is the only thing that closes it, and nothing else starts the count over: not a
  launch of the wizard, not the grant going and coming back.
- **User input** is also what macOS says back to a tap ShiftPick disables itself, which it does right after
  creating the click tap and at every disarm. **It is never counted.** Heard with the tap armed, it disarms;
  heard otherwise, it is the tap's own disable and nothing is done, above all not a second disable, which
  would be heard back in turn.

**Nothing is armed while nobody can be clicking**: the Mac asleep, the screen locked, another user's session
in front. **The reasons are held apart** (`Core/AwayReasons`): closing a lid both sleeps and locks, and the
way back can wake the Mac with the lock screen still up or unlock it before any wake notice comes, so the
first reason heard suspends the listener, each reason is ended by its own notification, and **the last one to
end resumes it, whichever it is and in whichever order they end**. Taps created meanwhile arm nothing either.
Coming back asks about the grant again before anything arms. **And no notification is trusted to arrive**:
whenever there is news of any kind, a notification of coming back, whether its reason was heard going or
not, or somebody pressing ⇧ Shift while the listener is suspended (at most every **`K.awayCheckInterval`
(5 s)**), the reasons are held against what the session says itself: any news at all is a Mac that is awake,
and the session says whether its screen is locked and whether it is the one on the console. The session ends
reasons and never begins one, a reason's own notification of coming back ends it whatever the session reads
at that instant, and the ⇧ Shift press is answered from the session alone, whatever the reasons say. A lost
unlock therefore costs that one press, which goes to Finder, and never leaves ShiftPick asleep with Settings
saying it is listening.

**Both taps are destroyed before anything that takes the grant or the process away**: a quit, which is also
how an update begins (§8, where the helper touches nothing until the process has gone), and an uninstall,
before it resets the grant (§9).

**One ShiftPick at a time.** A second copy started while one is running asks the first for its window and
leaves before it has created anything.

## 2. One ⇧ Shift click

In this order. **Any step that cannot answer returns the event unmodified**, and Finder does what it has
always done.

1. **⌘ Command held with ⇧ Shift is Finder's own toggle**, measured in its list view: the event is returned
   before anything is asked of anybody, and the sentinel, which heard the same press, notes the anchor
   (§2.1).
2. **Find Finder.** Its pid is remembered until the process it names has gone.
3. **Hit-test the point.** The result has to be an icon in a Finder icon view: an item in a window's icon
   view or on the Desktop. A hit on the gap between two icons, on a group's header, on the space under the
   last row, on a list view, on the sidebar, on a toolbar or on another application is not.
4. **Refuse a rename.** While a name is being typed in place, Finder's focused element is a text field and
   the click belongs to it.
5. **Read the view.** Every icon it is showing, each one's frame, which group it is in and the order
   Accessibility listed it in. On the Desktop, also whether it is a file at all.
6. **Read the selection.** One round trip, and it is the whole of the state besides the anchor: the icons on
   screen Finder names as selected, and every selected element it names that is not one of them.
7. **Find the anchor** (§2.1).
8. **Work out the range and what it leaves selected** (§3, §2.2).
9. **Set the selection.** One call, whatever its size: the selection §2.2 describes, with every selected
   element Finder named that is not on screen handed back as it came.
10. **Swallow the click**, and its release.
11. **Do what the click would have done besides selecting**: bring Finder forward, and raise the window
    that was clicked. The Desktop has no window, so making Finder frontmost is the whole of it. The press has
    been answered by then, so nobody's click waits for this part.
12. **The anchor becomes the icon the range was measured from** (§2.1). Nobody waits for this part either.

**The work happens on a worker, and the thread that holds the click waits for it `K.clickBudget` (150 ms)
and no longer.** Past that the event is returned whatever the worker is doing; the worker is told, stops at
the next thing it was about to ask, and sets nothing. If the budget runs out at the very moment the selection
is being set, that one call is waited for, for at most **`K.commitGrace` (100 ms)** more: letting the click
through then would have Finder toggle the clicked file on top of the range. **A click never queues**: one
that arrives while the worker is still busy with the click before is returned at once. Every Accessibility
element is given **`K.axTimeout` (100 ms)**, which sits under the budget so that one call that never answers
cannot spend all of it. Measured: one frame read costs about 0.06 ms warm, so a full screen of icons costs 6
to 20 ms. The selection is one round trip per click on top of that, and the question about whether the view
is scrolled is one parent, one role and two frames, asked only when nothing is selected.

### 2.1 Where a range is measured from

ShiftPick keeps **one anchor per container** and nothing else: the selection is read from Finder at every
⇧ Shift click, and nothing about an earlier range is remembered. Whatever the user did meanwhile with the
mouse, the keyboard, a drag or ⌘ A is simply what is selected now. This is the list view's own model,
measured on AppKit's `NSTableView` (`docs/macOS.md`, *The selection model*).

- **A press without ⇧ Shift, or a press with ⌘ Command, sets the anchor**: a plain click, a ⌘ Command click
  and a ⌘ Command ⇧ Shift click on an icon all do. **A press with ⇧ Shift and without ⌘ Command does not**,
  whatever else is held, so an ⌥ Option ⇧ Shift or ⌃ Control ⇧ Shift click leaves the anchor where it was.
  The sentinel hears it, and the click itself is never held. The anchor is looked for
  **`K.anchorDelay` (60 ms) later**, on the worker, and only if the application that owns the view is
  frontmost by then, so an ordinary click gains no latency and a click that went to another application sets
  nothing.
- **A click on empty space inside an icon view clears the anchor**, with or without ⌘ Command. A plain click
  there has just deselected everything; what a ⌘ Command click there leaves selected is not measured, and
  the anchor goes either way, because a range measured from a file nothing on screen says anything about
  would be a guess. A click outside Finder leaves it alone.
- **The anchor is per container**: each window has its own, and the Desktop has its own.
- **The click is measured from the anchor while the anchor is selected.** When it is not, a **stand-in**
  takes its place: the first selected file after it in reading order (§3), however far; else the last
  selected file before it. An anchor that is gone, stale, in another container or not a file counts as one
  before everything, so the first selected file in reading order stands in. A stand-in may be in another
  cluster, and the range to it is then the rubber band (§3). **After the click, the anchor is the icon the
  range was measured from**, the stand-in included, so the next click is measured from where this one was.
- **Nothing selected**: the click is measured from the first file in reading order **while the view is known
  not to be scrolled** (its container's top edge at or below its scroll area's top edge, within a point; the
  Desktop never scrolls). A scrolled view may hold its first icon off screen, and so may a view whose
  scrolling cannot be read at all (its container not directly under a scroll area, or a frame that does not
  answer), so in either case the click goes through and the log says `nothing selected, and the first icon
  may be off screen`.

### 2.2 What the click leaves selected

With the range R between the icon the click was measured from and the target (§3):

- **Inside one reading order** (an arranged view, or one grid of a hand-placed one): **the old selection,
  minus every run of consecutive selected files that R touches, plus R.** A run R touches goes whole, the
  part of it outside R included; a run R does not touch stays, whatever ⌘ Command clicks built it with. The
  selection in any other cluster is never touched. **A selected collapsed stack is never touched either**: it
  stays exactly as it was, wherever it is, and its place is not a selected position, so two selected files on
  either side of it are two runs and not one.
- **A rubber band** (§3): the old selection **plus** the files inside the rectangle. Nothing is remembered
  about the band before it.

The whole of it is AppKit's own rule, measured. On a 3 × 4 window filling rows from the left: click 1,
⇧ Shift click 5 leaves {1…5}; ⌘ Command click 8 leaves {1…5, 8} with the anchor at 8; ⇧ Shift click 10 leaves
{1…5, 8, 9, 10}; and ⇧ Shift click 6 has R = [6, 8] touch the run {8, 9, 10}, which goes whole, so {1…8}.

## 3. What "between" means

There is no order Finder can be asked for in every context, so the range is worked out from where the icons
are. All of it is pure arithmetic over rectangles (`Core/LayoutModel.swift`, `Clusters.swift`, `Grid.swift`,
`ShiftClick.swift`), and all of it is unit-tested. The numbers the inferred grids are built on live in
`Core/LayoutConstants.swift`, apart from the safety layer's own: they are **best-effort tolerances for a
view somebody laid out by hand, not guarantees**.

1. **The reference point of an icon is the centre of its frame.** Measured: Finder reports the icon's own
   box and not its cell, so a name that wraps to two lines does not move it.
2. **The lattice.** The reference points are clustered into rows and columns. The tolerance is half the
   median distance between two lines, which is itself measured from a first, coarse pass at a quarter of an
   icon's side.
3. **The layout is one of two things.**
   - **Arranged**: inside every group, the occupied cells are the first *n* cells of some fill order. No
     hole, nothing off the lattice; a partial last line is allowed and every group starts a new line.
     Finder is laying these out, so the order is meaningful. Groups that fill the lattice cell for cell read
     as arranged when they sit one above the other with an empty band between them: what is asked is that
     each group's occupied cells be the first *n* of a fill order, not that the lines be evenly spaced.
   - **Hand-placed**: anything else. Holes in the lattice, icons that are not on one, a line that only
     exists because a scatter chained together. Its icons are cut into clusters, and each cluster is fitted
     with a grid or found to be a scatter (5. and 6.).
4. **The fill order**, for an arranged layout, is one of four: rows down the screen filled from the left or
   from the right, or columns filled downwards with the next column to the right or to the left. It is
   inferred from the icons; where several fit, which is what one row, one column and a single icon always
   look like, the order Accessibility listed the items in decides, and where that says nothing the
   container's own default does: **rows from the leading edge in a window, columns from the trailing edge
   on the Desktop**, both measured, and both flipped for a right-to-left layout.
5. **The pitch, and the clusters**, for a hand-placed layout. For every icon, the nearest other icon in each
   of the four directions (left, right, above and below, each a quarter of the plane around it, a neighbour
   exactly on a diagonal counting for both), within **`K.neighbourReachSides` (3)** icon sides, gives one
   sample, its distance along that direction's axis. One sample per direction rather than the nearest
   neighbour alone is what lets an icon wobbled towards this one and an icon wobbled away from it cancel;
   the nearest of four is always the one that came closer, and it reads a hand-placed grid's pitch low. Two
   icons whose centres are within **`K.overlapSides` (1)** icon side of each other on both axes overlap: one
   was dropped on the other, a pile, and it is passed over for the nearest icon that does not. **The pitch**
   is the median of the samples no farther than **`K.gridLinkPitches` (1.5)** coarse pitches, the coarse
   pitch being the median, over the icons, of the distance to the nearest one of all; with no neighbour
   within reach anywhere it is **`K.lonePitchSides` (1.5)** icon sides, and never under a point. **An icon's
   side, for every one of these distances, is the median frame height and never under `K.cellSideFloor`
   (64) points**: below that Finder's cell is the label's and not the icon's — a 16-point icon sits under
   the same label as a 64-point one, on a pitch that does not shrink with it, and two of them dropped within
   a label's width of each other share a cell — so a small icon looks three sides of a 64-point icon for its
   neighbours, overlaps another within one, and its grid is read exactly as a 64-point window's is. Two
   icons are then **linked** when their centres are within **`K.gridLinkPitches` (1.5)** pitches of each
   other on both axes, and a **cluster** is a connected set of links: a grid's orthogonal and diagonal
   neighbours are one pitch apart and a wobble, while an empty row or column between two groups is two
   pitches less a wobble and breaks the link. **A gap of more than `K.gridLinkPitches` (1.5) pitches on
   either axis through a cluster breaks it the same way**: the gap has to run through every row (or, the
   other way, through every column), because one link anywhere across it, diagonal included, holds the two
   sides together; where it does, the icons beyond it are another cluster and a range across the gap is the
   rubber band. An icon far from everyone is a cluster of one.
6. **A grid, or a scatter.** Inside a cluster the centres' *y* values are cut into rows at every gap wider
   than **`K.gridLineTolerancePitches` (0.5)** of a pitch, the *x* values into columns the same way. The
   cluster is a **grid** when **no row is wider than that tolerance** (an icon a quarter pitch off its row
   is on it, and a row that only exists because a scatter chained together is wider) and, past
   **`K.gridAlwaysCount` (2)** icons, when **some row or some column holds two of them**: icons that share no
   line with anyone, a staircase however even its steps, give nothing to read along and are a **scatter**. A
   cluster of one or two icons is always a grid. A column's width is no verdict, because the reading runs
   along rows: an icon dropped between two columns, or rows packed tighter than the pitch, change nothing
   about which icon follows which. Measured on the Desktop's 122-point pitch: a wobble of twenty points holds
   through both the clusters and the grid over forty layouts, and the cliff is a quarter of the pitch.
7. **The reading order.** Every icon has exactly one place in it. **Arranged**: the fill order, groups from
   the top of the view downwards. **Hand-placed**: cluster by cluster, the clusters ordered by their top edge
   and then by their leading edge; inside a grid, rows top to bottom and along each row from the leading
   edge, a column no wider than the tolerance counting as one cell whose icons read in the order
   Accessibility listed them; inside a scatter, by top edge then leading edge. **A range never crosses a
   cluster**: the order across clusters exists only so that a stand-in can be named (§2.1).
8. **The range.**
   - **Both ends in one reading order** (an arranged view, or one grid of a hand-placed one): every file
     between them in that order, inclusive. Groups count from the top of the view downwards, with the fill
     order inside each of them.
   - **Anything else** (two clusters, or a scatter): **the rubber band**, the anchor, the target, and every
     file whose reference point falls inside the rectangle their two frames span. Best effort, and never a
     guess outside the rectangle.
9. **What the range leaves selected is §2.2.**
10. **A collapsed Desktop stack is not a file.** It is never in a range, and a ⇧ Shift click whose anchor or
    target is one goes through. It does hold its place in the lattice and in the reading order, because that
    is where it is drawn, and a stack somebody selected stays selected wherever it is.
11. **Every selected element Finder names that is not on screen is kept**, handed back unchanged to the one
    call that sets the selection. Whether Finder ever names one is not measured; the rule costs nothing
    either way.
12. **Three properties, pinned by `RangeSelectionTests`.** The range always holds both ends; anchor to
    target is the same set as target to anchor; and it is `O(n log n)`, worked out for five thousand icons
    in a test that runs in milliseconds.

**A range is only ever as complete as what Finder is showing.** Finder builds the icons that are on screen
and a little beyond, and no more, so both ends have to be visible. An anchor that is not reads as gone and a
stand-in is named from what is selected on screen; when nothing is selected there either, the click is
measured from the first icon while the view is not scrolled and otherwise goes through, because a smaller
selection nobody noticed was smaller would be worse. `docs/pitfalls.md` has the measurement.

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
numbers and its copy are the `macos-building-settings-pages` skill's, not this document's. **Nothing in it is
a setting about what ShiftPick does**: the feature is always on, and it does one thing one way.

| Page | Group | Rows |
|---|---|---|
| **General** | the app icon, alone | |
| | Startup | Launch at login · Show in menu bar. A note names the way back to this window when the icon is hidden. |
| | Updates | `ShiftPick <version>` with the last answer as its mark · one button, *Check for Updates* or *Update* |
| | Quit | one destructive button |
| | Uninstall | one destructive button, with a warning that never goes away |
| **System** | Accessibility | the permission, live and **as ShiftPick can use it**: macOS's answer, except once ShiftPick has found the grant gone itself, which that answer can go on hiding for seconds (§7). Red *Denied* while it is missing, with a button to the pane and a warning naming the switch; once granted both go and the row stays. |
| | Click listener | *Watching for ⇧ Shift clicks*, the Health page's row in the same colour and with the same word, whenever the listener is past waiting for the permission. No group at all in the two cases that have nothing to say: while the permission is missing, which the row above already says, and before the first start or after the quit. **The warning follows the status**, so a red row is never silent: a listener macOS refused and one the breaker stopped each get their own sentence, and the hint covers both ways it can be down. **The button belongs to the breaker alone**: while it is open, *Start Listening Again* under the row, which asks for another try (§1) and nothing else. |
| | Start over | one button, *Show Onboarding Again*, which opens a fresh wizard at its first page |
| **Health** | Health | the checks, **green, orange or red and never blue**, at most four lines, then **Check Again** (a spinner beside it for at least `K.healthMinimumBusy`, 0.5 s). **Always**: *Accessibility permission*, the System page's row in the same colour (below). **While the listener is past waiting for the permission**: *Watching for ⇧ Shift clicks*, green *Enabled* while it listens, red *Failed* when macOS refused the taps, red *Stopped* when macOS kept taking the click tap away (§1), whose fix names the System page's *Start Listening Again* button; its tooltip is the engine's own name for the state. No line while the permission is missing (the permission's line says it: one cause, one line) or before the first start. **Only while wrong**: *Finder*, orange *Stopped* (without it only Open and Save panels are left); *Crashes in the last 7 days* (`K.healthCrashWindow`), an orange count with the last one's date in its tooltip, read from `~/Library/Logs/DiagnosticReports`. Every orange or red line's fix is a warning under the table. |
| | Information | the readings, blue: *Running for* · *Memory used* |
| **Tip** | the app icon beside one sentence, in a card with no title | every feature is free and stays free, and a coffee is how the project is supported |
| | One-time tip | the Ko-fi cup, *A cup of coffee*, what it is, and a button naming the smallest tip the page takes (`SupportLink.smallestTip`, 5 €). It opens `https://ko-fi.com/bambidotexe` in the browser; nothing is paid inside the app. |

**One colour rule, on every page.** Green is as it should be. Blue is a reading, or a switch the user turned
off (Launch at login): the state they asked for. Orange is not as it should be while ⇧ Shift clicks still
work. Red, the stop sign, is what stops them. A permission missing is red when the wizard marks
it required and orange otherwise, never blue: Accessibility is required, so it is red on the System page and
on the Health page alike. **The Health page is two tables and nothing else**: *Health*, the checks, and
*Information*, the readings. A preference is on neither, whichever way it is set, and neither are the version
and the updates, which stay on General. Every orange or red line says in a warning under the table how to put
it right; the page itself changes nothing. **It reads the permission from the window's 2 s poll, the listener
from what the engine already publishes, and its own readings when the window opens on it, when it is picked
and on Check Again, never on a timer**: none of them asks anything that can block, calls Accessibility or asks
for a permission.

Defaults: **Show in menu bar on**. Launch at login is the system's answer and is not stored here.
`onboardingCompleted` is stored beside the one switch and is not a setting: no window shows it, and Start
over opens the wizard rather than clearing it.

Settings are one JSON blob in `UserDefaults`. A key missing from a file written by an older build falls back
to its default instead of resetting the others, and a key such a file carries that no longer exists is
ignored.

## 6. The menu-bar item

Rebuilt from scratch every time it is opened, so it is never a language or a state behind. Its mark is the
app icon's drawing, 18 pt, as a template image that takes the menu bar's own colour: four icons in a grid,
three of them selected and the fourth an outline.

```
Launch at Login             ✓
──────────
<what it is doing right now>        (not clickable)
──────────
Settings…                   ⌘,
──────────
Quit ShiftPick              ⌘Q
```

The status line is one of four: *Watching for ⇧ Shift clicks*, *Waiting for the Accessibility permission*,
*macOS refused the click listener*, *Stopped: macOS kept interrupting the click listener*.

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
- **The row shows the grant as ShiftPick can use it**, and so do the System and Health pages' rows, the menu
  and the choice between the wizard and Settings when the app is opened again: macOS's own answer, except once
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
