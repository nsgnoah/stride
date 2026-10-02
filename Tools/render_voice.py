#!/usr/bin/env python3
"""Records the coach's voice clips with ElevenLabs and bundles them into the watch app.

The watch can't synthesize a natural voice on its own, so every cue is assembled from
short clips recorded once, here. Clip names must match Shared/Voice/VoiceScript.swift;
`--manifest` writes the list the unit tests check the app against.

    Tools/render_voice.py --manifest            # rewrite StrideWatch/Voice/manifest.json
    Tools/render_voice.py --audition            # record just enough for a few full cues to listen to
    Tools/render_voice.py --render              # record whatever is missing
    Tools/render_voice.py --render --only speed_up,pm_11,ps_38 --force
    Tools/render_voice.py --samples             # re-stitch the example cues from what's recorded

Recording needs ELEVENLABS_API_KEY and ELEVENLABS_VOICE_ID, either in the environment or
in a `.env` file at the repo root (git-ignored), plus ffmpeg and afconvert on the PATH.
Nothing else: standard library only.
"""

import argparse
import concurrent.futures
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VOICE_DIR = ROOT / "StrideWatch" / "Voice"
MANIFEST = VOICE_DIR / "manifest.json"
SAMPLE_DIR = ROOT / "build" / "voice-samples"

MODEL = "eleven_v4"
# Lower stability and some style: more energy, a coach rather than a narrator.
SETTINGS = {"stability": 0.35, "similarity_boost": 0.85, "style": 0.35, "use_speaker_boost": True}
WORKERS = 3  # concurrent requests the plan allows
RATE = 44100
TARGET_MEAN_DB = -20.0  # every clip lands at the same loudness so joins don't jump
PEAK_CEILING_DB = -1.0

ONES = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
TENS = ["", "", "twenty", "thirty", "forty", "fifty"]


def words(n):
    if n < 20:
        return ONES[n]
    if n < 60:
        return TENS[n // 10] + ("" if n % 10 == 0 else "-" + ONES[n % 10])
    if n % 100 == 0 and n < 2000:
        return f"{words(n // 100)} hundred" if n != 1000 else "one thousand"
    raise ValueError(n)


def cap(s):
    return s[0].upper() + s[1:]


def inventory():
    """name -> {text, prev, next}. prev/next give the model the surrounding sentence so a
    fragment is spoken the way it would be mid-sentence, not as a line on its own."""
    clips = {}

    def add(name, text, prev="", next=""):
        assert name not in clips, name
        clips[name] = {"text": text, "prev": prev, "next": next}

    # Coaching
    add("speed_up", "Speed up!")
    add("slow_down", "Slow down.")
    add("on_pace", "Nice, on pace!")
    add("paused", "Paused.")
    add("resuming", "Resuming. Let's go!")
    add("complete", "Workout complete! Great job.")

    # Workouts and segments
    add("w_easy", "Easy run.")
    add("w_long", "Long run.")
    add("w_run", "Today's run.")
    add("w_tempo", "Tempo run.")
    add("w_intervals", "Intervals.")
    add("w_shakeout", "Shakeout run.")
    add("w_race", "Race day!")
    add("w_free", "Free run.")
    add("seg_walk_drills", "Walk and drills.")
    add("seg_run", "Run.")
    add("seg_walk", "Walk.")
    add("seg_warmup_jog", "Warm-up jog.")
    add("seg_cooldown_jog", "Cool-down jog.")
    add("seg_tempo", "Tempo.")
    add("seg_recover", "Recover.")
    add("seg_easy_jog", "Easy jog.")
    add("g_5k", "Five K.")
    add("g_10k", "Ten K.")
    add("g_half", "Half marathon.")
    add("g_marathon", "Marathon.")
    for n in range(3, 9):
        for i in range(1, n + 1):
            add(f"rep_{i}_{n}", f"Rep {words(i)} of {words(n)}.")

    # Paces, to the nearest five seconds, each a whole phrase so nothing is spliced mid-breath.
    for seconds in range(240, 1200, 5):
        m, sec = divmod(seconds, 60)
        pace = f"{words(m)} " + ("flat" if sec == 0 else f"oh {words(sec)}" if sec < 10 else words(sec))
        add(f"at_{seconds}", f"You're at {pace}.", prev="Slow down.")
        add(f"tg_{seconds}", f"Target, {pace}", prev="Easy run. Two miles.", next=" to twelve thirty-five.")
        add(f"to_{seconds}", f"to {pace}.", prev="Target, eleven forty")

    # Distances: track reps in meters, everything else in miles to the tenth.
    for m in (200, 400, 600, 800, 1000, 1200, 1600):
        add(f"m_{m}", cap(f"{words(m)} meters."))
    for tenths in range(1, 310):
        n, t = divmod(tenths, 10)
        if t == 0:
            said = f"{words(n)} {'mile' if n == 1 else 'miles'}"
        elif t == 5:
            said = "half a mile" if n == 0 else f"{words(n)} and a half miles"
        else:
            said = f"{words(n)} point {words(t)} miles"
        add(f"mi_{tenths}", cap(said + "."))
    for n in range(1, 31):
        add(f"mile_{n}", f"Mile {words(n)}.")

    # Durations. "minc" leads into the seconds: "Eleven minutes," + "forty-two seconds."
    for n in range(1, 60):
        unit = "minute" if n == 1 else "minutes"
        add(f"min_{n}", cap(f"{words(n)} {unit}."))
        add(f"minc_{n}", cap(f"{words(n)} {unit},"), next=" forty-two seconds.")
        add(f"sec_{n}", f"{words(n)} {'second' if n == 1 else 'seconds'}.", prev="Eleven minutes,")
    add("sec_90", "Ninety seconds.")
    for n in range(1, 7):
        add(f"hr_{n}", cap(f"{words(n)} {'hour' if n == 1 else 'hours'},"), next=" twelve minutes.")

    return clips


# A few whole cues, as the watch assembles them: (clip, pause after it in seconds).
SAMPLES = {
    "1-start": [("w_easy", .3), ("mi_20", .3), ("seg_walk_drills", .3), ("min_4", .3)],
    "2-segment": [("w_easy", .3), ("mi_20", .3), ("tg_700", .06), ("to_755", .3)],
    "3-slow-down": [("slow_down", .3), ("at_655", .3), ("tg_700", .06), ("to_755", .3)],
    "4-mile-split": [("mile_2", .3), ("minc_11", .08), ("sec_42", .3)],
    "5-finish": [("complete", .3), ("mi_31", .3), ("minc_36", .08), ("sec_12", .3)],
    "6-speed-up": [("speed_up", .3), ("at_790", .3), ("tg_700", .06), ("to_755", .3)],
}


def run(*args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, **kwargs)


def synthesize(clip, key, voice):
    body = {"text": clip["text"], "model_id": MODEL, "voice_settings": SETTINGS}
    if clip["prev"]:
        body["previous_text"] = clip["prev"]
    if clip["next"]:
        body["next_text"] = clip["next"]
    request = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{voice}?output_format=mp3_44100_128",
        data=json.dumps(body).encode(),
        headers={"xi-api-key": key, "Content-Type": "application/json", "Accept": "audio/mpeg"},
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read(), int(response.headers.get("character-cost") or 0)


def finish(mp3, destination):
    """Trim the silence either side, level the loudness, and encode as AAC."""
    with tempfile.TemporaryDirectory() as tmp:
        raw, trimmed, levelled = Path(tmp, "raw.mp3"), Path(tmp, "trimmed.wav"), Path(tmp, "levelled.wav")
        raw.write_bytes(mp3)
        trim = "silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.02"
        run("ffmpeg", "-y", "-i", str(raw), "-af", f"{trim},areverse,{trim},areverse", "-ac", "1", "-ar", str(RATE), str(trimmed))
        stats = run("ffmpeg", "-i", str(trimmed), "-af", "volumedetect", "-f", "null", "-").stderr.decode()
        mean = float(re.search(r"mean_volume: (-?[\d.]+) dB", stats).group(1))
        peak = float(re.search(r"max_volume: (-?[\d.]+) dB", stats).group(1))
        gain = min(TARGET_MEAN_DB - mean, PEAK_CEILING_DB - peak)
        run("ffmpeg", "-y", "-i", str(trimmed), "-af", f"volume={gain:.2f}dB,afade=t=in:d=0.005", str(levelled))
        run("afconvert", "-f", "m4af", "-d", "aac", "-b", "48000", str(levelled), str(destination))


def credential(name):
    if os.environ.get(name):
        return os.environ[name]
    env = ROOT / ".env"
    if env.exists():
        for line in env.read_text().splitlines():
            key, _, value = line.strip().removeprefix("export ").partition("=")
            if key.strip() == name and value.strip():
                return value.strip().strip("\"'")
    return None


def render(only, force):
    key, voice = credential("ELEVENLABS_API_KEY"), credential("ELEVENLABS_VOICE_ID")
    if not key or not voice:
        sys.exit("Set ELEVENLABS_API_KEY and ELEVENLABS_VOICE_ID (environment or .env) first.")
    clips = inventory()
    names = only or list(clips)
    unknown = [n for n in names if n not in clips]
    if unknown:
        sys.exit(f"Not in the inventory: {', '.join(unknown)}")
    VOICE_DIR.mkdir(parents=True, exist_ok=True)
    todo = [n for n in names if force or not (VOICE_DIR / f"{n}.m4a").exists()]
    print(f"{len(todo)} to record ({sum(len(clips[n]['text']) for n in todo)} characters), {len(names) - len(todo)} already there.")

    def record(name):
        for attempt in range(4):
            try:
                audio, cost = synthesize(clips[name], key, voice)
                finish(audio, VOICE_DIR / f"{name}.m4a")
                return cost
            except urllib.error.HTTPError as error:
                detail = error.read().decode(errors="replace")[:300]
                if error.code not in (429, 500, 502, 503) or attempt == 3:
                    raise RuntimeError(f"ElevenLabs refused '{name}': {error.code} {detail}")
            except (urllib.error.URLError, TimeoutError):
                if attempt == 3:
                    raise
            time.sleep(2 * (attempt + 1))

    spent, failed = 0, []
    with concurrent.futures.ThreadPoolExecutor(WORKERS) as pool:
        jobs = {pool.submit(record, name): name for name in todo}
        for i, job in enumerate(concurrent.futures.as_completed(jobs), 1):
            name = jobs[job]
            try:
                spent += job.result()
            except Exception as error:  # keep going; report what's missing at the end
                failed.append(name)
                print(f"  {name}: {error}")
            if i % 50 == 0 or i == len(todo):
                print(f"  {i}/{len(todo)} recorded, {spent} credits so far", flush=True)
    if failed:
        sys.exit(f"{len(failed)} clips failed: {', '.join(failed[:20])}")


def samples():
    SAMPLE_DIR.mkdir(parents=True, exist_ok=True)
    for title, cue in SAMPLES.items():
        missing = [name for name, _ in cue if not (VOICE_DIR / f"{name}.m4a").exists()]
        if missing:
            print(f"{title}: skipped, not recorded yet: {', '.join(missing)}")
            continue
        frames = b""
        for name, pause in cue:
            frames += run("ffmpeg", "-i", str(VOICE_DIR / f"{name}.m4a"), "-f", "s16le", "-ac", "1", "-ar", str(RATE), "-").stdout
            frames += b"\0\0" * int(RATE * pause)
        with wave.open(str(SAMPLE_DIR / f"{title}.wav"), "wb") as out:
            out.setnchannels(1)
            out.setsampwidth(2)
            out.setframerate(RATE)
            out.writeframes(frames)
        print(f"{title}: {SAMPLE_DIR / (title + '.wav')}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--manifest", action="store_true", help="write the clip list the tests check against")
    parser.add_argument("--render", action="store_true", help="record missing clips")
    parser.add_argument("--only", help="comma-separated clip names to record")
    parser.add_argument("--force", action="store_true", help="re-record clips that already exist")
    parser.add_argument("--samples", action="store_true", help="stitch example cues into build/voice-samples")
    parser.add_argument("--audition", action="store_true", help="record only the clips the example cues need, then stitch them")
    args = parser.parse_args()

    if args.manifest:
        VOICE_DIR.mkdir(parents=True, exist_ok=True)
        for stale in VOICE_DIR.glob("*.m4a"):
            if stale.stem not in inventory():
                stale.unlink()
        MANIFEST.write_text(json.dumps({name: clip["text"] for name, clip in inventory().items()}, indent=1) + "\n")
        print(f"{len(inventory())} clips, {sum(len(c['text']) for c in inventory().values())} characters -> {MANIFEST.relative_to(ROOT)}")
    if args.audition:
        render(sorted({name for cue in SAMPLES.values() for name, _ in cue}), args.force)
        samples()
    if args.render:
        render(args.only.split(",") if args.only else None, args.force)
    if args.samples:
        samples()
    if not (args.manifest or args.render or args.samples or args.audition):
        parser.print_help()


if __name__ == "__main__":
    main()
