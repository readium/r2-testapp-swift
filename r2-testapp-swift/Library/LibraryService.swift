//
//  LibraryService.swift
//  r2-testapp-swift
//
//  Created by Mickaël Menu on 20.02.19.
//
//  Copyright 2019 European Digital Reading Lab. All rights reserved.
//  Licensed to the Readium Foundation under one or more contributor license agreements.
//  Use of this source code is governed by a BSD-style license which is detailed in the
//  LICENSE file present in the project repository where this source code is maintained.
//

import Foundation
import UIKit
import R2Shared
import R2Streamer
import Kingfisher


protocol LibraryServiceDelegate: AnyObject {
    
    func reloadLibrary(with downloadTask: URLSessionDownloadTask?, canceled:Bool)
    func libraryService(_ libraryService: LibraryService, presentError error: Error)
    
}

final class LibraryService: Loggable {
    
    weak var delegate: LibraryServiceDelegate?
    
    let publicationServer: PublicationServer
    
    let streamer: Streamer
    
    var drmLibraryServices = [DRMLibraryService]()
    
    init(publicationServer: PublicationServer) {
        self.publicationServer = publicationServer
        
        #if LCP
        drmLibraryServices.append(LCPLibraryService())
        #endif
        
        self.streamer = Streamer(
            contentProtections: drmLibraryServices.map(\.contentProtection)
        )
        
        preloadSamples()
        
    }
    
    func preloadSamples() {
        let version = 1
        let VERSION_KEY = "LIBRARY_VERSION"
        let oldversion = UserDefaults.standard.integer(forKey: VERSION_KEY)
        if oldversion < version {
            UserDefaults.standard.set(version, forKey: VERSION_KEY)
            clearDocumentsDir()
            // Parse publications (just the OPF and Encryption for now)
            loadSamplePublications()
        }
    }
    
    func present(_ alert: UIAlertController) {
        guard let rootViewController = UIApplication.shared.delegate?.window??.rootViewController else {
            return
        }
        if let _  = rootViewController.presentedViewController {
            rootViewController.dismiss(animated: true) {
                rootViewController.present(alert, animated: true)
            }
        } else {
            rootViewController.present(alert, animated: true)
        }
    }
    
    func movePublicationToLibrary(from sourceURL: URL, downloadTask: URLSessionDownloadTask? = nil, completion: @escaping (Bool) -> Void = { _ in }) {
        let repository = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let url = repository.appendingPathComponent("\(UUID().uuidString).\(sourceURL.pathExtension)")

        /// Copy the Publication to documents.
        do {
            // Necessary to read URL exported from the Files app, for example.
            let shouldRelinquishAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if shouldRelinquishAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            try FileManager.default.copyItem(at: sourceURL, to: url)
            let dateAttribute = [FileAttributeKey.modificationDate: Date()]
            try FileManager.default.setAttributes(dateAttribute, ofItemAtPath: url.path)

        } catch {
            delegate?.libraryService(self, presentError: LibraryError.importFailed(error))
            completion(false)
            return
        }

        if let drmService = drmLibraryServices.first(where: { $0.canFulfill(url) }) {
            drmService.fulfill(url) { [weak self] result in
                guard let self = self else {
                    return
                }
                let fileManager = FileManager.default
                try? fileManager.removeItem(at: url)
                
                switch result {
                case .success(let publication):
                    do {
                        // Moves the fulfilled publication to Documents/
                        let repository = try! fileManager
                            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                        var destinationFile = repository
                            .appendingPathComponent(publication.suggestedFilename)
                        if fileManager.fileExists(atPath: destinationFile.path) {
                            destinationFile = repository.appendingPathComponent("\(UUID().uuidString).\(destinationFile.pathExtension)")
                        }
                        try fileManager.moveItem(at: publication.localURL, to: destinationFile)
                        
                        self.addPublication(at: destinationFile, downloadTask: publication.downloadTask, completion: completion)
                    } catch {
                        self.delegate?.libraryService(self, presentError: error)
                        completion(false)
                    }
                    
                case .failure(let error):
                    self.delegate?.libraryService(self, presentError: error)
                    completion(false)
                case .cancelled:
                    completion(true)
                    break
                }
            }
            
        } else {
            addPublication(at: url, downloadTask: downloadTask, completion: completion)
        }
    }
    
    func addPublication(at url: URL, downloadTask: URLSessionDownloadTask? = nil, completion: @escaping (Bool) -> Void = { _ in }) {
        streamer.open(file: File(url: url), allowUserInteraction: true) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let publication):
                let book = Book(
                    href: url.isFileURL ? url.lastPathComponent : url.absoluteString,
                    title: publication.metadata.title,
                    author: publication.metadata.authors
                        .map { $0.name }
                        .joined(separator: ", "),
                    identifier: publication.metadata.identifier ?? url.lastPathComponent,
                    cover: publication.cover?.pngData()
                )
                
                if (try! BooksDatabase.shared.books.insert(book: book)) != nil {
                    self.delegate?.reloadLibrary(with: downloadTask, canceled: false)
                    completion(true)
                } else {
                    let duplicatePublicationAlert = UIAlertController(
                        title: NSLocalizedString("library_duplicate_alert_title", comment: "Title of the import confirmation alert when the publication already exists in the library"),
                        message: NSLocalizedString("library_duplicate_alert_message", comment: "Message of the import confirmation alert when the publication already exists in the library"),
                        preferredStyle: UIAlertController.Style.alert
                    )
                    let addAction = UIAlertAction(title: NSLocalizedString("add_button", comment: "Confirmation button to import a duplicated publication"), style: .default, handler: { alert in
                        if (try! BooksDatabase.shared.books.insert(book: book, allowDuplicate: true)) != nil {
                            self.delegate?.reloadLibrary(with: downloadTask, canceled: false)
                            completion(true)
                            return
                        }
                        else {
                            try? FileManager.default.removeItem(at: url)
                            self.delegate?.reloadLibrary(with: downloadTask, canceled: true)
                            completion(true)
                            return
                        }
                    })
                    let cancelAction = UIAlertAction(title: NSLocalizedString("cancel_button", comment: "Cancel the confirmation alert"), style: .cancel, handler: { alert in
                        try? FileManager.default.removeItem(at: url)
                        self.delegate?.reloadLibrary(with: downloadTask, canceled: true)
                        completion(true)
                        return
                    })
        
                    duplicatePublicationAlert.addAction(addAction)
                    duplicatePublicationAlert.addAction(cancelAction)
                    self.present(duplicatePublicationAlert)
                }
            
            case .failure(let error):
                try? FileManager.default.removeItem(at: url)
                self.delegate?.libraryService(self, presentError: error)
                completion(false)
                
            case .cancelled:
                completion(true)
                break
            }
        }
    }
    
    fileprivate func loadSamplePublications() {
        let urls = urlsFromSamples()
        
        func importAt(_ index: Int) {
            guard index < urls.count else { return }
            
            addPublication(at: urls[index]) { _ in
                importAt(index + 1)
            }
        }
        
        importAt(0)
    }
    
    func preparePresentation(of publication: Publication, book: Book) {
        // If the book is a webpub, it means it is loaded remotely from a URL, and it doesn't need to be added to the publication server.
        if publication.format != .webpub {
            publicationServer.removeAll()
            do {
                try publicationServer.add(publication, at: book.href)
            } catch {
                log(.error, error)
            }
        }
    }
    
    func parsePublication(for book: Book, allowUserInteraction: Bool, from sender: UIViewController, completion: @escaping (Publication?) -> Void) {
        streamer.open(file: File(url: book.url), allowUserInteraction: allowUserInteraction, sender: sender) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let publication):
                completion(publication)
            case .failure(let error):
                self.delegate?.libraryService(self, presentError: error)
                completion(nil)
            case .cancelled:
                completion(nil)
            }
        }
    }
    
    func downloadPublication(_ publication: Publication? = nil, at link: Link, completion: @escaping (Bool) -> Void = { _ in }) {
        guard let url = link.url(relativeTo: publication?.baseURL) else {
            completion(false)
            return
        }
        
        DownloadSession.shared.launch(
            request: URLRequest(url: url),
            description: publication?.metadata.title
        ) { localURL, response, error, downloadTask in
            if let localURL = localURL, error == nil {
                // Download succeeded. DownloadTask renames the file download, thus to be parsed correctly according to the filetype, we have to fix the extension.
                let ext = response?.sniffFormat(mediaTypes: Array(ofNotNil: link.type))?.fileExtension ?? url.pathExtension
                let fixedURL = localURL.deletingLastPathComponent()
                    .appendingPathComponent("\(url.deletingPathExtension().lastPathComponent).\(ext)")
                do {
                    try? FileManager.default.removeItem(at: fixedURL)
                    try FileManager.default.moveItem(at: localURL, to: fixedURL)
                } catch {
                    self.log(.warning, error)
                }
                self.movePublicationToLibrary(from: fixedURL, downloadTask: downloadTask, completion: completion)
                return true
            } else {
                // Download failed
                self.log(.warning, "Error while downloading a publication.")
                DispatchQueue.main.async {
                    completion(false)
                }
                return false
            }
        }
    }
    
    /// Get the paths out of the bundled Samples directory.
    fileprivate func urlsFromSamples() -> [URL] {
        let samplesPath = Bundle.main.resourceURL!.appendingPathComponent("Samples")
        return try! FileManager.default.contentsOfDirectory(at: samplesPath, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
    }
    
    func remove(_ book: Book) {
        // Remove item from Database.
        _ = try! BooksDatabase.shared.books.delete(book)
        
        if let filename = book.fileName {
            // Removes file from documents directory.
            removeFromDocumentsDirectory(fileName: filename)
            // Removes publication from publicationServer.
            publicationServer.remove(at: filename)
        }
    }
    
    fileprivate func removeFromDocumentsDirectory(fileName: String) {
        let fileManager = FileManager.default
        // Document Directory always exists (hence `try!`).
        let documents = try! fileManager.url(for: .documentDirectory,
                                             in: .userDomainMask,
                                             appropriateFor: nil,
                                             create: true)
        // Assemble destination path.
        let absoluteUrl = documents.appendingPathComponent(fileName)
        // Check that file don't exist.
        guard !fileManager.fileExists(atPath: absoluteUrl.path) else {
            do {
                try fileManager.removeItem(at: absoluteUrl)
            } catch {
                log(.error, "Error while deleting file in Documents.")
            }
            return
        }
    }
    
    func clearDocumentsDir() {
        let fileManager = FileManager.default
        let documents = try! fileManager.url(for: .documentDirectory,
                                             in: .userDomainMask,
                                             appropriateFor: nil,
                                             create: true)
        guard let filePaths = try? fileManager.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil, options: []) else { return }
        for filePath in filePaths {
            try? fileManager.removeItem(at: filePath)
        }
    }
    
}

