# Could the Live Activity be part of the lock screen player?

Asked for in issue #2 and again since: put Controls, Queue, Lyrics and the sleep timer inside the lock
screen's Now Playing card, under its own transport buttons, so there is one card and not two. This is
what the platform gives, what the mod already uses of it, and what is left.

## Who draws what

The Now Playing card on the lock screen is drawn by SpringBoard, in its own process. An app never draws in
it. It hands the system two things and the system does the rest:

- `MPNowPlayingInfoCenter`: the title, artist, album, artwork, elapsed time and rate, and from iOS 26 an
  animated artwork (a clip the system plays full screen behind the card).
- `MPRemoteCommandCenter`: which of a fixed list of commands the app answers. The system decides which of
  them get a button and where.

A Live Activity is the other thing an app may put on the lock screen, and it is a separate card, laid out
by the system under the player. There is no call that places one inside the other, no shared container, and
no parameter on either side that names the other.

The mod runs inside Spotify, not inside SpringBoard. Hooking Spotify cannot reach SpringBoard's views. That
would take a jailbreak tweak injected into SpringBoard, which is another kind of project and not something
a sideloaded IPA can carry.

## Buttons an app can add to the player

Of the remote commands, the lock screen's card shows:

| Command | Shown on the lock screen card |
|---|---|
| play, pause, toggle | yes, the middle button |
| next / previous track | yes, unless the skip pair replaces them |
| skip forward / backward by an interval | yes, in place of next / previous |
| change playback position | yes, the scrubber |
| like / dislike / bookmark (feedback commands) | one of them, as a single extra button |
| rating, shuffle mode, repeat mode, playback rate, language options | no (CarPlay, Control Center on some systems, accessories) |

So the count of buttons an app controls is the transport row plus one. The mod already takes that one: the
star, which cycles the lock screen's views (Canvas, Lyrics, Fill, Colourful, Default). Its title and whether
it shows as active are the app's; its symbol, place and size are the system's. A second row of buttons under
the transport row does not exist to be asked for.

## What that means for each part of the Live Activity

| Live Activity part | Inside the player card? |
|---|---|
| Lyrics line | Not as a row. Already possible two ways the mod has: in the artist line (Lock screen lyrics), and drawn into the animated artwork behind the card (the Lyrics view). |
| Previous, play, next | Already the card's own. |
| Shuffle, repeat | No button for them on the lock screen card. The single extra button could be given to one of them instead of the star, losing the star. |
| Queue with tappable rows | No. The card has no list. |
| Sleep timer | No. |
| Tabs | No. |

## The closest that can be had

1. **One look, two cards.** The Translucent card color (now the default) leaves the system's material
   under the Live Activity with next to nothing over it, the same material the player sits on, so the two
   read as one surface with a seam. This is a matter of looks, not a merge, and the settings row says so.
2. **Lyrics in the player itself.** Lock screen lyrics in the artist line, or the Lyrics view in the
   artwork. With the Live Activity showing lyrics, the artwork leaves them to it so they are not there twice.
3. **The one extra button, reassigned.** The star could become a choice: cycle views (today), toggle
   shuffle, or toggle repeat. One of them, not several.
4. **A smaller Live Activity.** A card with only what the player lacks (shuffle, repeat, timer, queue) and
   no transport row, so nothing is doubled between the two.

Options 3 and 4 are not built. Either is a contained change if wanted.

## What was not verified

This is from the public API and from what the mod already does with it. Which feedback command wins the
extra button when several are enabled, and whether iOS 26 or 27 shows more than one, was not tried on a
device; the star working today shows that one does.
