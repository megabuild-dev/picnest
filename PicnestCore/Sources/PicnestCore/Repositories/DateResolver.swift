import Foundation
import ImageIO

/// Finds the date of a photo or video. Order: EXIF date, file-name timestamp, modification time.
public struct DateResolver: Sendable {
    public init() {}

    public func date(for url: URL, modified: Date) -> PhotoDate {
        if let exif = exifDate(url) { return PhotoDate(date: exif, source: .exif) }
        if let stamp = fileNameDate(url.lastPathComponent) { return PhotoDate(date: stamp, source: .fileNameTimestamp) }
        return PhotoDate(date: modified, source: .modificationTime)
    }

    /// EXIF dates have no time zone. This reads them as local time.
    private func exifDate(_ url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }

    /// A 13-digit millisecond timestamp at the start of the name, with a year from 2000 to 2100. Read as UTC.
    private func fileNameDate(_ name: String) -> Date? {
        let digits = name.prefix(while: { $0.isASCII && $0.isNumber })
        guard digits.count == 13, let millis = Double(digits) else { return nil }
        let date = Date(timeIntervalSince1970: millis / 1000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let year = calendar.component(.year, from: date)
        return (2000...2100).contains(year) ? date : nil
    }
}
