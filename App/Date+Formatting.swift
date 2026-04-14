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
            if Calendar.current.component(.year, from: self)
                == Calendar.current.component(.year, from: Date()) {
                formatter.setLocalizedDateFormatFromTemplate("MMMd")
            } else {
                formatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
            }
            return formatter.string(from: self)
        }
    }
}
