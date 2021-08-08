//
//  Copyright 2021 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import GRDB
import R2Shared

struct Bookmark: Codable {
    struct Id: EntityId { let rawValue: Int64 }
    
    let id: Id?
    /// Foreign key to the publication.
    var bookId: Book.Id
    /// Location in the publication.
    var locator: Locator
    /// Progression in the publication, extracted from the locator.
    var progression: Double? = nil
    /// Date of creation.
    var created: Date = Date()
    
    init(id: Id? = nil, bookId: Book.Id, locator: Locator, created: Date = Date()) {
        self.id = id
        self.bookId = bookId
        self.locator = locator
        self.progression = locator.locations.totalProgression
        self.created = created
    }
}

extension Bookmark: TableRecord, FetchableRecord, PersistableRecord {
    enum Columns: String, ColumnExpression {
        case id, bookId, locator, progression, created
    }
}
