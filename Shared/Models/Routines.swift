import Foundation

/// A single warm-up drill, stretch, or strength move.
struct Exercise: Codable, Hashable, Identifiable, Sendable {
    var id: String { name }
    var name: String
    var detail: String
    /// "30 sec", "10 each side", etc.
    var dose: String
}

struct Routine: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var purpose: String
    var minutes: Int
    var exercises: [Exercise]
}

/// The library of warm-ups, cool-downs, and mobility work. Static content;
/// the planner references routines by id so both phone and watch resolve the same thing.
enum RoutineLibrary {
    static func routine(_ id: String?) -> Routine? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    static let all: [Routine] = [dynamicWarmup, speedWarmup, cooldown, hipMobility, calfAnkle, runnerStrength, raceDayWarmup]

    static let dynamicWarmup = Routine(
        id: "warmup.dynamic",
        title: "Dynamic Warm-up",
        purpose: "Wake up hips, ankles, and glutes before the first stride so easy miles stay easy on your body.",
        minutes: 6,
        exercises: [
            Exercise(name: "Brisk walk", detail: "Start the watch on this. Arms swinging, tall posture.", dose: "2 min"),
            Exercise(name: "Leg swings", detail: "Hold a wall or tree. Front-to-back, then side-to-side.", dose: "10 each direction, each leg"),
            Exercise(name: "Walking lunges", detail: "Step long, knee tracks over toes, back knee toward the ground.", dose: "8 each leg"),
            Exercise(name: "Hip circles", detail: "Knee up, out to the side, and back down. Slow and controlled.", dose: "8 each leg"),
            Exercise(name: "Ankle bounces", detail: "Small hops on the balls of your feet. Quick and light.", dose: "20"),
            Exercise(name: "High knees", detail: "Quick cadence, land under your hips.", dose: "20 m"),
            Exercise(name: "Butt kicks", detail: "Heels to glutes, stay tall.", dose: "20 m"),
        ]
    )

    static let speedWarmup = Routine(
        id: "warmup.speed",
        title: "Speed Day Warm-up",
        purpose: "Faster running needs more prep. Drills plus a few strides so the first rep doesn't feel like a shock.",
        minutes: 10,
        exercises: dynamicWarmup.exercises + [
            Exercise(name: "A-skips", detail: "Skip with a high knee, foot snaps down under you.", dose: "20 m"),
            Exercise(name: "Strides", detail: "Build to ~90% effort over 20 seconds, then float to a stop. Walk back.", dose: "4 × 20 sec"),
        ]
    )

    static let raceDayWarmup = Routine(
        id: "warmup.race",
        title: "Race Warm-up",
        purpose: "Get loose without spending energy. Finish 10 minutes before the gun.",
        minutes: 12,
        exercises: [
            Exercise(name: "Easy jog", detail: "Conversational. Nothing more.", dose: "8 min"),
            Exercise(name: "Leg swings", detail: "Front-to-back and side-to-side.", dose: "10 each"),
            Exercise(name: "Walking lunges", detail: "Long steps, tall torso.", dose: "6 each leg"),
            Exercise(name: "Strides", detail: "Smooth accelerations to race pace, walk back between.", dose: "3 × 15 sec"),
        ]
    )

    static let cooldown = Routine(
        id: "cooldown.standard",
        title: "Cool-down & Stretch",
        purpose: "Bring heart rate down gradually, then give the muscles that just worked a chance to lengthen.",
        minutes: 8,
        exercises: [
            Exercise(name: "Walk it out", detail: "Keep moving until breathing is normal.", dose: "3 min"),
            Exercise(name: "Standing calf stretch", detail: "Hands on a wall, back leg straight, heel down.", dose: "30 sec each"),
            Exercise(name: "Standing quad stretch", detail: "Hold your foot behind you, knees together, hips forward.", dose: "30 sec each"),
            Exercise(name: "Figure-4 glute stretch", detail: "Cross ankle over knee, sit back. Use a bench if standing is wobbly.", dose: "30 sec each"),
            Exercise(name: "Hip flexor stretch", detail: "Half-kneeling, tuck your tailbone, shift forward gently.", dose: "30 sec each"),
            Exercise(name: "Hamstring stretch", detail: "Heel on a low step, hinge from the hips with a flat back.", dose: "30 sec each"),
        ]
    )

    static let hipMobility = Routine(
        id: "mobility.hips",
        title: "Hip & Glute Mobility",
        purpose: "Tight hips are behind most runner knee and IT band pain. Fifteen minutes on a rest day pays off for weeks.",
        minutes: 15,
        exercises: [
            Exercise(name: "90/90 hip switches", detail: "Sit with both knees at 90°, rotate side to side keeping your chest tall.", dose: "10 each side"),
            Exercise(name: "Pigeon pose", detail: "Front shin across the mat, back leg long. Breathe into the outer hip.", dose: "60 sec each"),
            Exercise(name: "Couch stretch", detail: "Back knee down, foot on a couch or wall. Squeeze the glute of the back leg.", dose: "60 sec each"),
            Exercise(name: "Glute bridges", detail: "Drive through heels, ribs down, pause at the top.", dose: "2 × 15"),
            Exercise(name: "Side-lying leg raises", detail: "Toes pointed slightly down so the outer hip does the work, not the quad.", dose: "2 × 12 each"),
            Exercise(name: "World's greatest stretch", detail: "Lunge, elbow to instep, rotate and reach to the sky.", dose: "5 each side"),
            Exercise(name: "Deep squat hold", detail: "Heels down, hold something if needed. Rock gently.", dose: "60 sec"),
        ]
    )

    static let calfAnkle = Routine(
        id: "mobility.calves",
        title: "Calf, Ankle & Foot Care",
        purpose: "Calves and Achilles absorb the most load per stride. Strong, mobile ankles prevent shin splints and plantar pain.",
        minutes: 12,
        exercises: [
            Exercise(name: "Ankle circles", detail: "Big slow circles both directions.", dose: "10 each way, each foot"),
            Exercise(name: "Knee-to-wall", detail: "Foot flat, drive the knee toward the wall without lifting the heel.", dose: "10 each"),
            Exercise(name: "Straight-leg calf raises", detail: "Off a step. 3 seconds up, 3 seconds down.", dose: "2 × 15"),
            Exercise(name: "Bent-knee calf raises", detail: "Same as above with a soft knee to target the soleus.", dose: "2 × 15"),
            Exercise(name: "Toe yoga", detail: "Lift the big toe with the others down, then swap. Harder than it sounds.", dose: "10 each"),
            Exercise(name: "Foot roll", detail: "Lacrosse ball or bottle under the arch, slow passes.", dose: "60 sec each"),
            Exercise(name: "Single-leg balance", detail: "Barefoot, eyes forward. Close your eyes if it's easy.", dose: "30 sec each"),
        ]
    )

    static let runnerStrength = Routine(
        id: "strength.runner",
        title: "Runner Strength",
        purpose: "Short, bodyweight, no gym needed. Single-leg strength is what keeps form together late in a run.",
        minutes: 15,
        exercises: [
            Exercise(name: "Single-leg glute bridge", detail: "Hips level, no arching.", dose: "2 × 10 each"),
            Exercise(name: "Reverse lunges", detail: "Step back, tap the knee, drive through the front heel.", dose: "2 × 10 each"),
            Exercise(name: "Single-leg deadlift", detail: "Hinge at the hip, back flat, reach toward the floor.", dose: "2 × 8 each"),
            Exercise(name: "Side plank", detail: "Straight line from head to heels. Top leg can lift for a challenge.", dose: "30 sec each"),
            Exercise(name: "Clamshells", detail: "Side-lying, knees bent, open the top knee without rolling the hips.", dose: "2 × 15 each"),
            Exercise(name: "Dead bug", detail: "Opposite arm and leg lower slowly, lower back stays glued down.", dose: "2 × 10 each"),
        ]
    )
}
