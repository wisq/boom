# Boom

Target computer for [Iron Nest](https://store.steampowered.com/app/2950790/IRON_NEST_Heavy_Turret_Simulator/).

Allows triangulation and trilateration of game objects, either based on grid coordinates, or based on their relationship to other objects.

## Installation & Usage

- Install [Elixir](https://elixir-lang.org/install.html) and [Python 3](https://www.python.org/downloads/).
- Run `mix deps.get` to fetch dependencies.
- Run `mix scenic.run` to start the server.  This will launch a map window that updates in realtime as you add observations.
- In a different terminal window, run `./client.sh` to launch the command-line client and connect to the server to issue commands.

Here's a series of example commands to get you started:

- Set your location:
  - `iron nest is at c4 3:5`
- Set up `target1` and aim at it:
  - `target1 is at g9 4:3`
  - `aim at target1`
- Triangulate `target2` and aim at it:
  - `spotter1 is at j9 8:3`
  - `spotter2 is at e5 3:3`
  - `target2 is bearing 45 from spotter2`
  - `target2 is range 3.22km from spotter1`
  - `aim ap at target2 with 4 charges`

## Observations

The primary way to update the map is to input _observations_.  These generally take the form of `<object name> is <observation>`.

Observations are added to the _observation log_.  This log is used to compute the position of each object in the world.  It can also be edited, e.g. if an observation was incorrect, or no longer applies.

**It is not an error to enter an observation based on a nonexistent object.**  The target object will be marked as having an unknown position.  Once the origin object's location becomes known (or changes), the target object's location will be updated accordingly, based on the observation(s) that link the two.

This also means that **object updates can cascade**.  If object A depends on B, which depends on C, which depends on D, then updating object D will cause C to update, which will cause B to update, which will cause A to update.  As such, you can enter all the data you have about all objects, then decide which ones need their position to be refined more (with recon, forward observers, etc).

Some commands allow multiple observations to be entered at once.  These will appear as multiple separate entries in the log, allowing them to be edited individually.

### Object names

Object names can be almost anything, as long as it starts with a letter.  However, to avoid confusion with other commands, certain keywords should be avoided, like `is`, `with`, and `at`.  Also certain punctuation symbols are not allowed, e.g. colon (`:`) is disallowed in order to avoid confusion with grid squares.

A few object names are special:

 - `iron nest`, `nest`, `ownship` — These all place the Iron Nest, i.e. you, in the world.  You'll need to place this before you can use the `aim` command.
 - `last` — Refers to the target of the last observation.  Obviously cannot be used if there are no observations.  Particularly useful for `aim` commands, especially when combined with the command history.

### Uncertainty

Note that Boom always operates in **uncertainty**.  Whenever you enter a command, it's assumed the target could be anywhere that matches that command.

Accordingly, if you say that `x is at b2 2:2`, that entire grid square (sector B2, grid 2:2) will be filled in as possible locations:

<img width="569" height="598" alt="Screenshot 2026-08-19 at 23 09 00" src="https://github.com/user-attachments/assets/e771daf9-01d1-4d95-bb4f-819c07bb3f00" />

If you then say that `y is bearing 45° from x`, you'll get an expanding wedge that starts at B2 2:2 and extends northeast, getting wider as it goes:

<img width="550" height="575" alt="Screenshot 2026-08-19 at 23 09 22" src="https://github.com/user-attachments/assets/1d8e4d88-2974-4357-9dd9-d01320f60663" />

That's because — as the game tells you early on — `y` might be anywhere between 44.5° and 45.5° from `x`.  And since `x` is an entire grid square, our bearing line **begins** as wide as a single grid square, and only gets worse with distance.

If you happen to know that `y` is _exactly_ 45° from `x`, you can reduce this widening by adding more decimals to your observation, e.g. `y is bearing 45.00000° from x`.  This will then limit the error to 0.000005 in either direction, i.e. essentially none at these scales.

## Observation commands

### `is at` / `is in`

This is used to put an object at a specific grid coordinate (or entire sector).  It's fairly self-explanatory.

Examples:

 - `spotter 1 is at g5 4:7`
 - `iron nest is in b9`
 - Can be combined with `is moving` (below), but not with other observations —
   - `ship8 is at j10 1:9 moving 180° at 19.7 knots @ 7:13:00`

### `is bearing` 

This is used to put an object at a particular bearing relative to another object (or a grid location).  The number of decimal places included (if any) will be used to determine the uncertainty.

You may omit the word "bearing", but **only if** you explicitly identify the number as being degrees.  The actual degrees symbol (`°`) is available using ⌥⇧8 on Mac, or using ⎇ 0176 (on the numpad) on Windows — but since that's not super accessible for most people, you can also use `d`, `deg`, or ` degrees`.  

If used as `is bearing`, then you **may** enter a units suffix, but it's unnecessary and ignored.

Examples:

  - `mole is bearing 245 from spotter 1`
    - Equivalent:
    - `mole is 245° from spotter 1`
    - `mole is 245d from spotter 1`
    - `mole is 245 degrees from spotter 1`
  - `ship is bearing 23° from d5 4:4`
  - Can be combined with `is range`:
    - `target point is bearing 55d, range 2.33km from infantry1`
    - `aa1 is 3.40km 180° from alpha`

### `is range`

This is used to put an object at a specific range from another object (or a grid location).

You may omit the word "range", but **only if** you explicitly identify the number as being kilometres (or metres).  If used as `is range`, then you **may** enter a units suffix; otherwise, it's assumed to be kilometres.

Examples:

  - `house is range 4.22 from mole`
    - Equivalent:
    - `house is range 4.22km from mole`
    - `house is 4.22km from mole`
  - `ship is range 2.00km from o1 0:4`
  - Can be combined with `is bearing`:
    - `target point is bearing 55d, range 2.33km from infantry1`
    - `aa1 is 3.40km 180° from alpha`

**Beware:** You might be tempted to round your ranges, e.g. inputting `2km` when the game gives you `2.00km`.  **These are very different:** The latter asks for a maximum error of five metres (i.e. between 1.995 and 2.005 km), but the former gives you a massive *half a kilometre* of error (between 1.5km and 2.5km).  It's an easy trap to fall into, so if you see your measurements highlighting way too much territory, check your decimals.

Similarly, entering metres (using the `m` suffix) means your maximum error will be no greater than 0.5m, i.e. 50cm.  That means that `4.22km` and `4220m` are **not** equivalent — the former has a max error of 5 metres (0.005km), while the latter has a max error of 50 centimetres (0.5m).

### `is moving`

Used to target objects that are moving at a given (known, fixed) speed, in a given (known, fixed) direction, starting at a given time.

The syntax is `is moving <bearing> at <speed> since <time>`.  All units are fixed — degrees and knots, respectively, with no support for other speed units at this time — and so while unit suffixes can be used, they're all ignored.  ("Since" may be replaced by "@", mirroring the corresponding `aim` syntax.)

Entering this command does not directly affect the target's shape on the map.  Instead, it's logged as the current known speed and direction of the target's movement.  (Any previous `is moving` command on that target will be superseded and ignored.)

When using the `aim` command (see below) with the `@ <time>` option, all of these parameters — the aim time, the movement start time, and the speed and bearing of the movement — will all be used to determine where the object is expected to be at that point in time, and the `aim` command will adjust accordingly.

This means that

 - `ship is moving 34° at 16.2 knots since 12:00:00`
 - `aim at ship at 12:02:00`

… is (nearly) functionally equivalent to …

 - `aimpoint is bearing 34°, range 1.00km from ship`
 - `aim at aimpoint`

In fact, using the `aim` command on moving targets actually directly uses the `is bearing` and `is range` code under the hood.  The only differences are that

- you don't have to do the speed math yourself (or rely on a table);
- it's a lot easier to target several points in an object's movement;
- you don't get a ton of extra aimpoints cluttering up the map; and,
- the error margins are slightly different.

Standard error rules apply, so the speed of `16.2` above is assumed to be somewhere between 16.15 and 16.25 knots, and the range error is calculated accordingly.

### `has moved`

Used to invalidate **all** previous observations about a target.  (The exception is movement observations, which are only invalidated by entering a new movement observation.)

You can enter this on its own, or you can enter a grid coordinate or sector (essentially combining it with an `is at` command).

For moving the Iron Nest itself, an `emergency move` command (or its short form, `move`) is available.

Examples:

 - `target has moved`
 - `target has moved to a3 4:4`
 - `iron nest has moved`
   - Equivalent:
   - `emergency move`
   - `move`
 - `iron nest has moved to a5`
   - Equivalent:
   - `emergency move to a5`
   - `move to a5`

## `aim` / `fire`

Next to the observation commands, this is the second most important and essential command.  It's used to determine the bearing, elevation, and number of charges needed to fire at the given target, and the chance to hit with those parameters.

To calculate shot parameters, an "ideal" shot is calculated, i.e. from the "centre of mass" (geometric median) of the Iron Nest's possible location area (which must be known) to the "centre of mass" of the target's possible location area (which must also be known).

Then, tiny variations are made to the bearing and elevation of the gun.  For each setting, the app draws a series of blast circles, based on simulated shots from possible Iron Nest locations.  The resulting hit percentage is the percent of the target area contained within each of these blast circles, on average.

**For precise targeting, the Iron Nest's known location must also be precise.**  This normally isn't a huge problem, since nearly all maps start out with you knowing your exact grid location.  However, after e.g. an Emergency Move, you'll want to make sure you have a pretty good idea where you ended up — ideally narrowed down to a single grid square.

### Ammo

When used in the form `aim at <target>`, it goes through a standard set of ammo types — `DRIL`, `AP`, `HE`, `HCHE` — in order of increasing blast radius.  For each ammo type, it calculates the estimated chance to hit.  It stops early if it achieves 99.9% hit chance, since once a near-certain hit is achieved, there's no point in solving for ammo types with a larger blast radius.

You can customise the ammo (or list of ammo) used via `aim <ammo> at <target>`.  Various separators are allowed.  These are all equivalent:

 - `aim ap,he,hche at ship`
 - `aim ap/he/hche at ship`
 - `aim ap+he+hche at ship`
 - `aim ap + he / hche at ship`

### Charges

By default, `aim` uses the minimum number of charges required to reach the target.  However, there will be times when you want to use a larger number of charges.  Maybe it's because you want shorter flight times, or maybe you want to pre-load the cannons for fast response but don't know how many charges you'll need.

Adding `with <n> charges` to your `aim` command will force it to use *no less than* that number of charges.  But **beware:** This is only a *minimum* number of charges.  If the shot needs more charges than the number you specify, it'll just use the larger number, since otherwise there's no way to shoot the target at all.

Examples:

 - `aim at ship3 with 5 charges`
 - `aim HCHE at signal station with 3 charges`

### Moving targets

To aim at moving targets, first input a `<target> is moving ...` observation with the time of the target's known location.  Then, add `at <time>` or `@ <time>` to your `aim` command.  For example:

 - `aim at garrison with 4 charges at 12:34:56`
 - `aim HE at landing ship @ 07:03:00`

Internally, the `aim` command will essentially create a fake object that is the given bearing and distance (based on speed and time) from the origin object, then aim at that.

## Other commands

### `list`

Lists all observations, in order (oldest to newest), along with their associated number (used for editing).

Darkened entries are observations that have been invalidated.  Most observations are invalidated by a `has moved` observation, while `is moving` observations are invalidated by other `is moving` observations.

Red entries are observations that have been *specifically* disabled (by the `disable` or `rollback` commands).  Dark red entries are observations that have both invalidated **and** explicitly disabled.

### `disable` / `delete`

Disables a specific observation.  Used as `disable <id>`, where `<id>` is the ID number of a rule from the `list` command.

Note that if you disable an observation that invalidates other observations (i.e. `has moved` / `is moving`), it may cause prior observation(s) to become valid again.  There is no indication of this in the output of the `disable` command, so be aware of this if you're disabling those sorts of commands.

### `enable` / `undelete`

Enables a specific observation (that was previously disabled).  Same usage as `disable`.

As per `disable`, re-enabling an `is moving` or `has moved` command may (silently) invalidate prior commands.

### `rollback` / `undo`

Disables the last (non-disabled) observation entered.  Exactly the same as `disable`, except that it automatically picks the ID to disable.

Entering this command repeatedly will disable one observation each time (going backwards through the observation log).

### `describe` / `show` / `where is`

Describes (in text) the current known location of an object.  Usage is `describe <object>`, where `<object>` is an object name.

This is the same text that is automatically output when an object's location is updated.

### `RESET` / `CLEAR`

Deletes all objects and observations, clearing the entire map.  Must be entered in all caps, for safety.  Functionally, it's as though you just closed and restarted the entire app (without needing to actually do that).

## Legal stuff

Copyright © 2026, Adrian Irving-Beer.

Boom is released under the [MIT license](LICENSE) and is provided with **no warranty**.  I'm not responsible for your friendly fire because you put in the wrong grid coordinate.

Iron Nest is a video game developed by Nick Nieuwoudt and Dominik Latos.  Neither myself nor this app are affiliated with Iron Nest or its developers in any way, apart from me being a player that enjoys playing it.
