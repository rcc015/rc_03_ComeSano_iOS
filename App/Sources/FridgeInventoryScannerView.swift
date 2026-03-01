import SwiftUI
import PhotosUI

#if os(iOS)
import UIKit

struct FridgeInventoryScannerView: View {
    let onAnalyze: (_ imagesData: [Data]) async throws -> [String]
    let onApplyIngredients: (_ ingredients: [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var images: [UIImage] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isShowingCamera = false
    @State private var isAnalyzing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        Button {
                            isShowingCamera = true
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "camera.fill")
                                    .font(.title2)
                                Text("Cámara")
                                    .font(.caption)
                            }
                            .frame(width: 92, height: 120)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        PhotosPicker(selection: $photoItems, maxSelectionCount: 8, matching: .images) {
                            VStack(spacing: 8) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.title2)
                                Text("Galería")
                                    .font(.caption)
                            }
                            .frame(width: 92, height: 120)
                            .background(Color.blue.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 92, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        images.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white)
                                            .background(Color.black.opacity(0.5).clipShape(Circle()))
                                    }
                                    .padding(4)
                                }
                        }
                    }
                    .padding(.horizontal)
                }

                Text("Toma fotos del interior, puerta y congelador para un inventario más preciso.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Button {
                    Task { await analyzeAndApply() }
                } label: {
                    if isAnalyzing {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Analizar Refri para Plan")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(images.isEmpty || isAnalyzing)
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Inventario de Refri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .sheet(isPresented: $isShowingCamera) {
                FridgeCameraImagePicker { image in
                    if let image {
                        images.append(image)
                    }
                }
            }
            .onChange(of: photoItems) { _, newItems in
                Task {
                    var appended: [UIImage] = []
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            appended.append(image)
                        }
                    }
                    if !appended.isEmpty {
                        images.append(contentsOf: appended)
                    }
                    photoItems = []
                }
            }
        }
    }

    @MainActor
    private func analyzeAndApply() async {
        errorMessage = nil
        isAnalyzing = true
        defer { isAnalyzing = false }

        let data = images.compactMap { $0.jpegData(compressionQuality: 0.8) }
        do {
            let ingredients = try await onAnalyze(data)
            guard !ingredients.isEmpty else {
                errorMessage = "No pude detectar ingredientes. Intenta con fotos más claras."
                return
            }
            onApplyIngredients(ingredients)
            dismiss()
        } catch {
            errorMessage = "No se pudo analizar el refri: \(error.localizedDescription)"
        }
    }
}

private struct FridgeCameraImagePicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImagePicked: (UIImage?) -> Void
        let dismiss: DismissAction

        init(onImagePicked: @escaping (UIImage?) -> Void, dismiss: DismissAction) {
            self.onImagePicked = onImagePicked
            self.dismiss = dismiss
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onImagePicked(nil)
            dismiss()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onImagePicked(info[.originalImage] as? UIImage)
            dismiss()
        }
    }
}

#endif
