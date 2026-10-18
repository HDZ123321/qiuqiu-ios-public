#if os(iOS)
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct ChatAttachmentPicker: View {
    @EnvironmentObject private var store: ChatStore
    @State private var photos: [PhotosPickerItem] = []
    @State private var files = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !store.attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(Array(store.attachments.enumerated()), id: \.offset) { index, attachment in
                            HStack {
                                if attachment.mime.hasPrefix("image/"), let image = UIImage(data: attachment.data) {
                                    Image(uiImage: image).resizable().scaledToFit().frame(width: 48,height: 48)
                                } else { Image(systemName: "doc.text").frame(width: 32,height: 48) }
                                VStack(alignment: .leading) { Text(attachment.name).lineLimit(1); Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
                                Button { store.attachments.remove(at: index) } label: { Image(systemName: "xmark.circle.fill").frame(width: 44,height: 44) }.accessibilityLabel("移除附件 \(attachment.name)").disabled(store.busy)
                            }.padding(6).background(.thinMaterial,in:RoundedRectangle(cornerRadius:12))
                        }
                    }
                }
            }
            HStack {
                PhotosPicker(selection: $photos, maxSelectionCount: 4, matching: .images) { Label("照片",systemImage:"photo") }.accessibilityIdentifier("chat-photos").simultaneousGesture(TapGesture().onEnded { DiagnosticLog.shared.record(.pickerPhotoOpen) })
                Button { DiagnosticLog.shared.record(.pickerDocumentOpen); files = true } label: { Label("附件",systemImage:"paperclip") }.accessibilityIdentifier("chat-files")
                if store.attachmentLoading { ProgressView(); Text("读取附件…").font(.caption) }
                Spacer()
                Text("≤4个 · 总计≤4 MiB").font(.caption2).foregroundStyle(.secondary)
            }.buttonStyle(.bordered).disabled(store.busy || store.attachmentLoading || store.current?.archived == true)
        }.padding(.horizontal)
        .fileImporter(isPresented: $files, allowedContentTypes: [.image,.pdf,.plainText,.json,.commaSeparatedText], allowsMultipleSelection: true) { result in
            switch result {
            case .failure(let error):
                DiagnosticLog.shared.recordProviderError(error)
                if (error as NSError).code != NSUserCancelledError { store.error = AttachmentFailure(.providerRead).localizedDescription }
            case .success(let urls):
                store.attachmentLoading = true
                Task { @MainActor in
                    defer { store.attachmentLoading = false }
                    do {
                        for url in urls {
                            let bytes = try await LocalDocumentReader.read(url)
                            if UTType(filenameExtension:url.pathExtension)?.conforms(to:.image) == true {
                                try store.addAttachment(try await PhotoNormalizer.normalize(bytes))
                            } else {
                                let mime = UTType(filenameExtension:url.pathExtension)?.preferredMIMEType ?? "text/plain"
                                let name = try ChatAttachment.localName(url.lastPathComponent,mime:mime)
                                try store.addAttachment(ChatAttachment(name:name,mime:mime,data:bytes))
                            }
                        }
                    } catch {
                        DiagnosticLog.shared.recordProviderError(error)
                        store.error = (error as? AttachmentFailure ?? AttachmentFailure(.providerRead)).localizedDescription
                    }
                }
            }
        }
        .onChange(of: photos) { items in
            guard !items.isEmpty else { return }
            store.attachmentLoading = true
            Task { @MainActor in
                defer { photos = []; store.attachmentLoading = false }
                do {
                    for item in items {
                        DiagnosticLog.shared.record(.photoSelected)
                        guard let bytes = try await item.loadTransferable(type:Data.self) else { throw AttachmentFailure(.providerRead) }
                        DiagnosticLog.shared.record(.photoRead,texts:bytes.count)
                        try store.addAttachment(try await PhotoNormalizer.normalize(bytes))
                    }
                } catch {
                        DiagnosticLog.shared.recordProviderError(error)
                        store.error = (error as? AttachmentFailure ?? AttachmentFailure(.providerRead)).localizedDescription
                    }
            }
        }
    }
}
#endif
