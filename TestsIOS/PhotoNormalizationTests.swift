import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import QiuQiu

final class PhotoNormalizationTests: XCTestCase {
    func testCameraSizedHEICAndOrientationBecomeBoundedJPEG() async throws {
        let width=4032, height=3024
        var pixels=Data(count:width*height*4)
        pixels.withUnsafeMutableBytes { raw in
            let p=raw.bindMemory(to:UInt8.self)
            for i in stride(from:0,to:p.count,by:4) { p[i]=UInt8((i/4)%251); p[i+1]=UInt8((i/width)%241); p[i+2]=177; p[i+3]=255 }
        }
        let provider=try XCTUnwrap(CGDataProvider(data:pixels as CFData))
        let image=try XCTUnwrap(CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.noneSkipLast.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent))
        let data=NSMutableData()
        let destination=try XCTUnwrap(CGImageDestinationCreateWithData(data,UTType.heic.identifier as CFString,1,nil))
        CGImageDestinationAddImage(destination,image,[kCGImagePropertyOrientation:6,kCGImageDestinationLossyCompressionQuality:0.95] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let attachment=try await PhotoNormalizer.normalize(data as Data)
        XCTAssertTrue(attachment.name.hasPrefix("photo-")); XCTAssertTrue(attachment.name.hasSuffix(".jpg"))
        XCTAssertEqual(attachment.mime,"image/jpeg"); XCTAssertLessThanOrEqual(attachment.data.count,4194304)
        let result=try XCTUnwrap(CGImageSourceCreateWithData(attachment.data as CFData,nil))
        let props=try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(result,0,nil) as? [CFString:Any])
        XCTAssertLessThanOrEqual(try XCTUnwrap(props[kCGImagePropertyPixelWidth] as? Int),2048)
        XCTAssertLessThanOrEqual(try XCTUnwrap(props[kCGImagePropertyPixelHeight] as? Int),2048)
        XCTAssertGreaterThan(try XCTUnwrap(props[kCGImagePropertyPixelHeight] as? Int),try XCTUnwrap(props[kCGImagePropertyPixelWidth] as? Int))
    }
    func testEmptyAndInvalidProviderBytesHaveDifferentReason() async {
        do { _ = try await PhotoNormalizer.normalize(Data()); XCTFail("accepted empty") }
        catch { XCTAssertEqual((error as? AttachmentFailure)?.reason,.emptyData) }
        do { _ = try await PhotoNormalizer.normalize(Data("not an image".utf8)); XCTFail("accepted invalid") }
        catch { XCTAssertEqual((error as? AttachmentFailure)?.reason,.photoDecode) }
    }
}
