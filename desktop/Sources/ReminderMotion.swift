import Foundation

/// Animation uses elapsed time, so reopening a hidden window never changes its deadline.
struct ReminderMotion: Equatable {
    var lift: Double
    var rotation: Double
    var scale: Double
    var haloOpacity: Double

    static func sample(elapsed: Double, reducedMotion: Bool) -> ReminderMotion {
        guard !reducedMotion else {return ReminderMotion(lift:0,rotation:0,scale:1,haloOpacity:0.24)}
        let phase=max(0,elapsed).truncatingRemainder(dividingBy:6)
        // Three small hops, then a quiet pause; repeats until the user responds.
        let hop=phase<2.4 ? abs(sin(phase * .pi / 0.8)) : 0
        let sway=phase<2.4 ? sin(phase * 2 * .pi / 1.6) : 0
        let pulse=(sin(elapsed * .pi)+1)/2
        return ReminderMotion(lift:14*hop,rotation:4*sway,scale:1+0.035*hop,haloOpacity:0.13+0.18*pulse)
    }
}
