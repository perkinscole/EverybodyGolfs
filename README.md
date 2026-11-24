# Everybody Golfs (working title)

A walk-it-yourself multiplayer golf game. Minimal HUD: walk to your ball,
address it, pick a club, swing, then go and find it before the clock runs out.

Built with [Godot 4.3](https://godotengine.org/download/archive/4.3-stable/)
(standard build, GDScript). All geometry is generated from code — there are no
imported art assets.

## Running

Open the folder in Godot 4.3 and press F5, or from a terminal:

```bash
godot --path .
```

## Controls

| Input | Action |
| --- | --- |
| WASD / Shift / Space | Walk / run / jump |
| E | Address the ball, or step away |
| Mouse (at the ball) | Aim |
| Wheel or 1-8 | Pick a club |
| Hold left mouse, release | Backswing, swing. Longer hold = more power |
| Right mouse | Cancel the backswing / step away |
| V | Third-person camera |
| Tab | Scorecard |
| H | Controls |
| B | Dev aid: beacon on the ball |

Moving the mouse sideways during the backswing hooks or slices the shot, and
holding past the top of the swing sprays it.

## Rules so far

- Two minutes to get within a few metres of your ball once it stops.
  Run out and it is a lost ball: one stroke penalty, drop on the fairway.
- Water or out of bounds: one stroke penalty, replay from the same spot.

## Layout

- `scripts/course.gd` — procedural hole: terrain, surfaces, trees, clubhouse
- `scripts/ball.gd` — ball flight, bounce and roll
- `scripts/clubs.gd` — club table and launch maths
- `scripts/player.gd` — golfer, cameras, swing input
- `scripts/main.gd` — game flow and HUD

## Tests

```bash
godot --headless -s tests/sim.gd
```

```bash
xvfb-run -a godot --path . -s tests/playthrough.gd -- /tmp/shots
```

The first checks club distances and has a bot play the hole. The second drives
the real scene through a full hole and saves screenshots.
