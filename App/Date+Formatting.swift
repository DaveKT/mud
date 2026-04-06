import Foundation

extension Date {
    /// Formats as a short, human-readable timestamp: "10:19am" for today,
    /// "yesterday" for yesterday, or short date+time otherwise.
    var shortTimestamp: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mma"
            return formatter.string(from: self).lowercased()
        } else if calendar.isDateInYesterday(self) {
            return "yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: self)
        }
    }
}
