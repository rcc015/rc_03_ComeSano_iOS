import SwiftUI
import ComeSanoCore
import ComeSanoAI

#if os(iOS)
import UIKit

public struct FoodPhotoAnalyzerView: View {
    @StateObject private var viewModel: FoodPhotoAnalyzerViewModel
    @State private var imageData: Data?
    @State private var previewImage: UIImage?
    @State private var pickerSource: ImagePickerSource?
    @State private var userInstruction = ""

    public init(viewModel: FoodPhotoAnalyzerViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Foto") {
                    if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    HStack {
                        Button("Tomar foto") {
                            pickerSource = .camera
                        }

                        Button("Elegir de galería") {
                            pickerSource = .library
                        }
                    }
                }

                Section("Instrucción") {
                    TextField("Ej: prioriza comidas altas en proteína", text: $userInstruction, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    Button {
                        Task {
                            guard let imageData else { return }
                            await viewModel.analyze(imageData: imageData, userInstruction: userInstruction)
                        }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Analizar con Gemini")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(imageData == nil || viewModel.isLoading)
                }

                if let result = viewModel.result {
                    Section("Alimentos detectados") {
                        ForEach(result.foodItems) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.name).font(.headline)
                                Text(item.servingDescription).font(.subheadline).foregroundStyle(.secondary)
                                Text("\(Int(item.nutrition.calories.rounded())) kcal | P \(Int(item.nutrition.proteinGrams.rounded()))g | C \(Int(item.nutrition.carbsGrams.rounded()))g | G \(Int(item.nutrition.fatGrams.rounded()))g")
                                    .font(.footnote)
                            }
                        }
                    }

                    if !result.shoppingList.isEmpty {
                        Section("Lista de súper sugerida") {
                            ForEach(result.shoppingList) { item in
                                Text("\(item.name) - \(item.quantity.formatted()) \(item.unit)")
                            }
                        }
                    }

                    if !result.notes.isEmpty {
                        Section("Notas") {
                            Text(result.notes)
                        }
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section("Error") {
                        Text(errorMessage)
                            .foregroundStyle(.red)

                        if let retryAfter = viewModel.retryAfterSeconds {
                            Button {
                                Task { await viewModel.retryLastAnalysis() }
                            } label: {
                                if retryAfter > 0 {
                                    Text("Reintentar en \(retryAfter)s")
                                } else {
                                    Text("Reintentar ahora")
                                }
                            }
                            .disabled(retryAfter > 0 || viewModel.isLoading)
                        }
                    }
                }
            }
            .navigationTitle("Analizar Foto")
            .sheet(item: $pickerSource) { source in
                SourceImagePicker(source: source.uiKitSourceType) { image in
                    if let image {
                        previewImage = image
                        imageData = image.jpegData(compressionQuality: 0.85)
                    }
                }
            }
        }
    }
}

private enum ImagePickerSource: String, Identifiable {
    case camera
    case library

    var id: String { rawValue }

    var uiKitSourceType: UIImagePickerController.SourceType {
        switch self {
        case .camera:
            return UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        case .library:
            return .photoLibrary
        }
    }
}

private struct SourceImagePicker: UIViewControllerRepresentable {
    let source: UIImagePickerController.SourceType
    let onImagePicked: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = source
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onImagePicked: (UIImage?) -> Void

        init(onImagePicked: @escaping (UIImage?) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onImagePicked(nil)
            picker.dismiss(animated: true)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            onImagePicked(image)
            picker.dismiss(animated: true)
        }
    }
}

#Preview {
    let aiClient = NutritionAIClientFactory.makeOpenAI(apiKey: "TEST_KEY", model: .gpt4point1mini)
    return FoodPhotoAnalyzerView(viewModel: FoodPhotoAnalyzerViewModel(aiClient: aiClient))
}

#else

public struct FoodPhotoAnalyzerView: View {
    public init(viewModel: FoodPhotoAnalyzerViewModel) {
        _ = viewModel
    }

    public var body: some View {
        Text("FoodPhotoAnalyzerView solo está disponible en iOS")
    }
}

#endif
