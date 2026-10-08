# Desktop pet

Date: 2026-10-06
Status: decisions approved in chat; implementing on `feat/desktop-pet`

## Problem

The notch island is glanceable only at the top of one screen. Codex's desktop app showed a friendlier pattern:
a small pixel creature that floats over your windows, acts out what the agent is doing, and opens the chat when
clicked. Ambient already knows what every agent is doing, so it can offer the same companion for Claude Code,
Codex and Gemini CLI at once.

## Goal

An optional desktop pet: a pixel-art critter you drag anywhere. It acts out the most urgent session and carries
a speech bubble with that session's status. Click the pet and it reacts, and its bubble opens into the list of
sessions. Click a session name and a burst of pixels flies out of it as Ambient takes you to that session.

Non-goals: custom pets from images (Codex's `/hatch`), pets per agent, sounds, and any change to the island.

## Decisions

| Topic | Decision |
| --- | --- |
| Relation to the island | Independent. Settings › Desktop Pet has its own switch, off by default. The island, pet, both or neither can run |
| Look | Pixel art drawn in code (no image assets), 16×13 pixels at 4 pt each, plus props. Three species: Blob, Crab, Cat |
| Color | The body takes the color of the agent behind the primary session (Claude coral, Codex green, Gemini blue), and grey while asleep. Mood is never shown by color alone: there is always a pose, a prop and the bubble's text |
| Poses | Asleep (closed eyes, "z"), working (typing on a laptop), needs you (wide eyes, a blinking "!", hopping), done (happy eyes, sparkles), failed (dizzy eyes, a sweat drop) |
| What it shows | Only relevant data. Idle and already-seen sessions are left out, so with nothing to show the pet sleeps. The bubble shows the most urgent session: title, what it's doing or needs, its clock, and "+N" for other sessions that also need you or are working. The list shows up to five such sessions, with the same actions as the island's menu (Quiet 1h, Mark all seen, Settings) plus Hide |
| Hover the pet | Like the island: after a 0.25 s rest the bubble opens into the full list (most urgent first, a summary such as "Needs you 2 · Working 1", and the island's actions); it closes 0.3 s after the pointer leaves the pet and the list. VoiceOver opens it with a named action |
| Click the pet | It plays a reaction for its pose (wake, hop, wave, cheer, shake), pixels burst from it in its mood's color, and it pins a peek: every session, titles only, up to eight. A second click or a click elsewhere unpins it. The hovered list gives way to the peek until the pointer leaves |
| Click a session name | Pixels burst from the click in the session's color, and Ambient jumps to the session exactly as the island does (and marks it seen) |
| Unprompted | When a session starts to need you, finishes or fails (the moments the island blooms for, respecting Quiet), the pet plays that pose's reaction without particles. Reactions are coalesced: within 4 s only a more urgent one (needs you › failed › done) plays, so a run of sessions finishing at once gets one cheer |
| Several sessions | The bubble holds its session while others of the same urgency churn, and switches only for something more urgent or when its session stops mattering. Its badge reads "+1 needs you" (amber) when another session waits, else a quiet "+2". Under the pet, static pips, one per session (up to five, then "+N"), each with a shape as well as a color: "!" needs you, check done, cross failed, plain agent color working. With two or more prompts waiting, the pet holds up their count instead of the "!". Lists and pips use a stable order (urgency, then title), so nothing shuffles under the pointer |
| Drag | Drag it anywhere. It moves only after 3 pt, so a click is never a drag. The position is remembered and kept on screen when displays change. The bubble opens upward in the lower half of the screen and downward in the upper half |
| Window | A non-activating floating panel on every Space, also over full-screen apps. It never takes focus, and it ignores the mouse outside the pet and its bubble, like the island |
| Motion and cost | Poses flip between two frames 2–4 times a second. Reactions are keyframe animations that run only when triggered, and particles render only while a burst lives (0.9 s). The bubble, the peek and the list are separate views: switching fades the old one out (0.1 s) and the new one in just after (0.18 s ease-out, starting 0.07 s later, drifting 4 pt from the pet), with no spring, overshoot or stretching. With Reduce Motion: one still frame, no hops, reactions become a short glow without particles, and the bubble only fades |
| Rendering cost (measured) | The pixel art is a 20×18 bitmap drawn once per look with Core Graphics and cached, scaled up without smoothing. A SwiftUI `Canvas` held a Metal renderer of ~55 MB. Bursts are Core Animation layers played by the render server. The bubble uses the system's behind-window blur: Liquid Glass re-rendered with Metal in the app on every open and close (+60 MB, and far more CPU). Measured on a release build with the wallpaper off: no measurable memory over the pet being off (19–26 MB either way), idle CPU +0.1% of a core, +1.8% with four busy agents, 29 MB after 20 hover cycles, and the same 416 framework leaks (20 KB) with the pet on or off. While hidden, the panel renders nothing |
| Menu bar | "Show Desktop Pet" toggle, so a pet that's in the way is always one click from hidden |

## Structure

- `AmbientCore/Pet/` (pure and tested): `PetPolicy` (relevant sessions, pose, reaction, the bubble's sticky session,
  stable order, badge, summary, peek, pips, and `PetReactionGate`), `PetArt` (sprites, eyes, mouths, props, count
  digits), `PetLayout` (default spot, clamping, where the panel and bubble go), `PetBurst` (deterministic particles).
- `AmbientApp/Pet/`: `PetController` (panel, pointer, hover, drag, wiring), `PetViewModel`, `PetView` (bubble, peek,
  list, pips), `PetFigure` (cached bitmap frames, reactions) and `PetBurstView` (Core Animation particles).
- Settings: a `Desktop Pet` pane with a live preview, the switch, a species picker and a Reset button for the position.
- Menu bar: a "Show Desktop Pet" toggle.
