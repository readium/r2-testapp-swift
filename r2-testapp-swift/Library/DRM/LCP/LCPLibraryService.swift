//
//  LCPLibraryService.swift
//  r2-testapp-swift
//
//  Created by Mickaël Menu on 01.02.19.
//
//  Copyright 2019 Readium Foundation. All rights reserved.
//  Use of this source code is governed by a BSD-style license which is detailed
//  in the LICENSE file present in the project repository where this source code is maintained.
//

#if LCP

import Foundation
import UIKit
import R2Shared
import ReadiumLCP


class LCPLibraryService: DRMLibraryService {

    private var lcpService = LCPService()
    
    lazy var contentProtection: ContentProtection = lcpService.contentProtection()
    
    func canFulfill(_ file: URL) -> Bool {
        return file.pathExtension.lowercased() == "lcpl"
    }
    
    func fulfill(_ file: URL, completion: @escaping (CancellableResult<DRMFulfilledPublication>) -> Void) {
        lcpService.acquirePublication(from: file) { result in
                switch result {
                case .success(let publication):
                    let publication = DRMFulfilledPublication(localURL: publication.localURL, downloadTask: publication.downloadTask, suggestedFilename: publication.suggestedFilename)
                    completion(.success(publication))
                case .failure(let error):
                    completion(.failure(error))
                case .cancelled:
                    completion(.cancelled)
                }
            }
    }
    
}

#endif
