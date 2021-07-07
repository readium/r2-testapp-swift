//
//  Copyright 2021 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import R2Navigator
import UIKit
import SwiftSoup

extension Decoration.Style.Id {
    static let sidemark: Self = "sidemark"
    static let image: Self = "image"
}

extension Decoration.Style {

    static func sidemark(tint: UIColor? = nil) -> Self {
        .init(id: .sidemark, config: SidemarkConfig(tint: tint))
    }

    struct SidemarkConfig: Hashable {
        let tint: UIColor?
    }

    static func image(url: URL) -> Self {
        .init(id: .image, config: ImageConfig(source: .url(url)))
    }

    static func image(_ image: UIImage?) -> Self {
        .init(id: .image, config: ImageConfig(source: image.map { .bitmap($0) }))
    }

    struct ImageConfig: Hashable {
        enum Source: Hashable {
            case url(URL)
            case bitmap(UIImage)
        }
        let source: Source?
    }
}

extension HTMLDecorationTemplate {

    static func sidemark(defaultTint: UIColor = .yellow, lineWeight: Int = 5, cornerRadius: Int = 2, margin: Int = 20) -> HTMLDecorationTemplate {
        return HTMLDecorationTemplate(
            layout: .bounds,
            width: .page,
            element: { decoration in
                let config = decoration.style.config as! Decoration.Style.SidemarkConfig
                let tint = config.tint ?? defaultTint
                return "<div><div class=\"r2-sidemark\" style=\"background-color: \(tint.cssValue(includingAlpha: false))\"/></div>"
            },
            stylesheet:
            """
            .r2-sidemark {
                float: left;
                width: \(lineWeight)px;
                height: 100%;
                margin-left: \(margin)px;
                border-radius: \(cornerRadius)px;
            }
            [dir=rtl] .r2-sidemark {
                float: right;
                margin-left: 0px;
                margin-right: \(margin)px;
            }
            """
        )
    }

    static func image() -> HTMLDecorationTemplate {
        return HTMLDecorationTemplate(
            layout: .bounds,
            width: .page,
            element: { decoration in
                let config = decoration.style.config as! Decoration.Style.ImageConfig
                var width = "auto"
                let src: String? = {
                    guard let source = config.source else {
                        return nil
                    }
                    switch source {
                    case .url(let url):
                        return Entities.escape(url.absoluteString, .utf8)
                    case .bitmap(let bitmap):
                        guard let data = bitmap.pngData() else {
                            return nil
                        }
                        let b64 = data.base64EncodedString()
                        width = "\(Int(bitmap.size.width))px !important"
                        return "data:image/png;base64,\(b64)"
                    }
                }()
                return "<div><img class=\"r2-image\" src=\"\(src ?? "")\" style=\"width: \(width)\"/></div>"
            },
            stylesheet:
            """
            .r2-image {
                opacity: 0.5;
            }
            """
        )
    }
}


private extension UIColor {
    func cssValue(includingAlpha: Bool) -> String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var alpha: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &alpha) else {
            return "black"
        }
        let red = Int(r * 255)
        let green = Int(g * 255)
        let blue = Int(b * 255)
        if includingAlpha {
            return "rgba(\(red), \(green), \(blue), \(alpha))"
        } else {
            return "rgb(\(red), \(green), \(blue))"
        }
    }
}
