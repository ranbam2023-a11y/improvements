//
//  AugmentData.swift — where an augment is allowed to keep things.
//
//  Augments never write their own files. Anything they need to remember lives
//  under one directory (or one UserDefaults suite) named after the augment, so
//  the app can delete all of it in one go when the augment is switched off.
//

import Foundation

enum AugmentData {
    private static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Improvements")
    }

    static func directory(for id: String) -> URL {
        support.appendingPathComponent("augments/\(id)")
    }

    static func suiteName(for id: String) -> String {
        "com.ranbam.improvements.\(id)"
    }

    /// Removes every trace of an augment's data: its directory, its defaults
    /// suite, and the preferences file that suite writes.
    static func removeAll(for id: String) {
        try? FileManager.default.removeItem(at: directory(for: id))

        let suite = suiteName(for: id)
        UserDefaults.standard.removePersistentDomain(forName: suite)

        if let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            let plist = library.appendingPathComponent("Preferences/\(suite).plist")
            try? FileManager.default.removeItem(at: plist)
        }

        Log.write("cleared stored data for \(id)")
    }
}
