import SwiftUI
import PhotosUI
import ComeSanoCore
import ComeSanoAI

#if os(iOS)
import UIKit

public struct FoodPhotoAnalyzerView: View {
    @StateObject private var viewModel: FoodPhotoAnalyzerViewModel
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var previewImage: UIImage?
    @State private var showCamera = false
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
                            showCamera = true
                        }

                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Text("Elegir de galería")
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
                            Text("Analizar con OpenAI")
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
                    }
                }
            }
            .navigationTitle("Analizar Foto")
            .sheet(isPresented: $showCamera) {
                CameraImagePicker { image in
                    guard let image else { return }
                    previewImage = image
                    imageData = image.jpegData(compressionQuality: 0.85)
                }
            }
            .onChange(of: selectedPhotoItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self), let uiImage = UIImage(data: data) {
                        previewImage = uiImage
                        imageData = data
                    }
                }
            }
        }
    }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
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
