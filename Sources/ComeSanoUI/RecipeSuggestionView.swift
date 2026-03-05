import SwiftUI
import ComeSanoCore
import ComeSanoAI

#if os(iOS)
import UIKit
import PhotosUI

public struct RecipeSuggestionView: View {
    @StateObject private var viewModel: RecipeSuggestionViewModel
    @State private var fridgePhotos: [UIImage] = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isShowingCamera = false
    @State private var userInstruction = ""

    public init(viewModel: RecipeSuggestionViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Escanea tus ingredientes")
                        .font(.headline)
                        .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            Button {
                                isShowingCamera = true
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: "camera.badge.ellipsis")
                                        .font(.system(size: 26))
                                    Text("Tomar\nfoto")
                                        .font(.caption)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(width: 96, height: 120)
                                .background(Color.orange.opacity(0.12))
                                .foregroundStyle(.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }

                            PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 10, matching: .images) {
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .font(.system(size: 26))
                                    Text("Galería")
                                        .font(.caption)
                                }
                                .frame(width: 96, height: 120)
                                .background(Color.blue.opacity(0.12))
                                .foregroundStyle(.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }

                            ForEach(Array(fridgePhotos.enumerated()), id: \.offset) { index, image in
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 96, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(alignment: .topTrailing) {
                                        Button {
                                            fridgePhotos.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.white)
                                                .background(Circle().fill(Color.black.opacity(0.55)))
                                        }
                                        .padding(6)
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }

                    TextField("Ej: alto en proteína y bajo en carbohidratos", text: $userInstruction, axis: .vertical)
                        .lineLimit(2...4)
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)

                    Button {
                        analyzePhotos()
                    } label: {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(viewModel.isLoading ? "Analizando ingredientes..." : "Crear recetas con IA")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(fridgePhotos.isEmpty || viewModel.isLoading ? Color.gray : Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(fridgePhotos.isEmpty || viewModel.isLoading)
                    .padding(.horizontal)

                    if let limitStatus = viewModel.limitStatusMessage {
                        Text(limitStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }

                    if !viewModel.recipes.isEmpty {
                        Button {
                            Task { await viewModel.saveMissingIngredientsToShoppingList() }
                        } label: {
                            Label("Agregar faltantes a Lista del Súper", systemImage: "cart.badge.plus")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(viewModel.isSaving)
                        .padding(.horizontal)
                    }

                    if let saveMessage = viewModel.saveMessage {
                        Text(saveMessage)
                            .font(.footnote)
                            .foregroundStyle(.green)
                            .padding(.horizontal)
                    }

                    if let saveError = viewModel.saveErrorMessage {
                        Text(saveError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    if !viewModel.recipes.isEmpty {
                        Text("Recetas sugeridas")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(viewModel.recipes) { recipe in
                            RecipeCardView(recipe: recipe)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Chef IA")
            .background(Color(uiColor: .systemGroupedBackground))
            .sheet(isPresented: $isShowingCamera) {
                MultiImagePicker { image in
                    fridgePhotos.append(image)
                }
            }
            .onChange(of: selectedPhotoItems) { _, items in
                Task {
                    for item in items {
                        guard let data = try? await item.loadTransferable(type: Data.self),
                              let image = UIImage(data: data) else { continue }
                        fridgePhotos.append(image)
                    }
                    selectedPhotoItems = []
                }
            }
            .task {
                viewModel.refreshLimitStatus()
            }
        }
    }

    private func analyzePhotos() {
        let imageData = fridgePhotos.compactMap { $0.jpegData(compressionQuality: 0.85) }
        Task {
            await viewModel.analyze(imagesData: imageData, userInstruction: userInstruction)
        }
    }
}

private struct RecipeCardView: View {
    let recipe: RecipeSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(recipe.nombre)
                .font(.headline)

            HStack(spacing: 14) {
                Label("\(recipe.tiempoMinutos) min", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("\(recipe.calorias) kcal", systemImage: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !recipe.ingredientesUsados.isEmpty {
                Text("Tienes: \(recipe.ingredientesUsados.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            if !recipe.ingredientesFaltantes.isEmpty {
                Text("Te falta: \(recipe.ingredientesFaltantes.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }
}

private struct MultiImagePicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked, onDismiss: dismiss.callAsFunction)
    }

    @MainActor
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onImagePicked: (UIImage) -> Void
        private let onDismiss: () -> Void

        init(onImagePicked: @escaping (UIImage) -> Void, onDismiss: @escaping () -> Void) {
            self.onImagePicked = onImagePicked
            self.onDismiss = onDismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImagePicked(image)
            }
            onDismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onDismiss()
        }
    }
}

#Preview {
    RecipeSuggestionView(viewModel: RecipeSuggestionViewModel(aiClient: PreviewRecipeInference()))
}

#else

public struct RecipeSuggestionView: View {
    public init(viewModel: RecipeSuggestionViewModel) {
        _ = viewModel
    }

    public var body: some View {
        Text("RecipeSuggestionView solo está disponible en iOS")
    }
}

#endif

private struct PreviewRecipeInference: MultimodalRecipeInference {
    func inferRecipes(fromImageData images: [Data], prompt: String) async throws -> [RecipeSuggestion] {
        _ = images
        _ = prompt
        return [
            RecipeSuggestion(
                nombre: "Omelette de espinaca",
                tiempoMinutos: 12,
                calorias: 290,
                ingredientesUsados: ["Huevos", "Espinaca"],
                ingredientesFaltantes: ["Queso panela"],
                pasos: ["Batir huevos", "Cocinar con espinaca"]
            )
        ]
    }
}
