import SwiftUI
import PhotosUI
import ComeSanoCore
import ComeSanoAI

#if os(iOS)
import UIKit

public struct CameraAnalysisView: View {
    @StateObject private var viewModel: FoodPhotoAnalyzerViewModel
    @State private var selectedImage: UIImage?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isShowingCamera = false
    @State private var userInstruction = ""
    @State private var showSaveConfirmation = false
    @FocusState private var isInstructionFocused: Bool

    public init(viewModel: FoodPhotoAnalyzerViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 25) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)

                        if let image = selectedImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 350)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                        } else {
                            VStack(spacing: 15) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 60))
                                    .foregroundStyle(.gray)
                                Text("Toma una foto de tu comida\no de tu alacena")
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.gray)
                            }
                        }
                    }
                    .frame(height: 350)
                    .padding(.horizontal)

                    TextField("Ej: prioriza comidas altas en proteína", text: $userInstruction, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($isInstructionFocused)
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") {
                                    isInstructionFocused = false
                                }
                            }
                        }

                    HStack(spacing: 20) {
                        Button {
                            isInstructionFocused = false
                            isShowingCamera = true
                        } label: {
                            Label("Cámara", systemImage: "camera.fill")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label("Galería", systemImage: "photo.on.rectangle")
                                .font(.headline)
                                .foregroundStyle(.blue)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            isInstructionFocused = false
                        })
                    }
                    .padding(.horizontal)

                    if let result = viewModel.result {
                        List {
                            Section("Alimentos detectados") {
                                ForEach(result.foodItems) { item in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(item.name).font(.headline)
                                        Text(item.servingDescription)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Text("\(Int(item.nutrition.calories.rounded())) kcal | P \(Int(item.nutrition.proteinGrams.rounded()))g | C \(Int(item.nutrition.carbsGrams.rounded()))g | G \(Int(item.nutrition.fatGrams.rounded()))g")
                                            .font(.footnote)
                                    }
                                }
                            }

                            if !result.shoppingList.isEmpty {
                                Section("Lista de súper sugerida") {
                                    ForEach(result.shoppingList) { item in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.name)
                                            Text("\(item.category) | \(item.quantity.formatted()) \(item.unit)")
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(height: 230)
                        .listStyle(.insetGrouped)
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

                    if let shoppingSaveMessage = viewModel.shoppingSaveMessage {
                        Text(shoppingSaveMessage)
                            .font(.footnote)
                            .foregroundStyle(.green)
                            .padding(.horizontal)
                    }

                    if let shoppingSaveError = viewModel.shoppingSaveErrorMessage {
                        Text(shoppingSaveError)
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

                    if let result = viewModel.result {
                        HStack(spacing: 12) {
                            iconActionButton(
                                icon: "fork.knife",
                                title: "Comida",
                                tint: .green,
                                isDisabled: viewModel.isSaving || result.foodItems.isEmpty
                            ) {
                                isInstructionFocused = false
                                showSaveConfirmation = true
                            }

                            iconActionButton(
                                icon: "cart.badge.plus",
                                title: "Súper",
                                tint: .blue,
                                isDisabled: viewModel.isSaving || result.shoppingList.isEmpty
                            ) {
                                isInstructionFocused = false
                                Task {
                                    await viewModel.saveCurrentShoppingList()
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    Button {
                        analyzeCurrentImage()
                    } label: {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                                Text("Analizando con IA...")
                            } else {
                                Image(systemName: "sparkles")
                                Text("Analizar con Gemini")
                            }
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedImage == nil || viewModel.isLoading ? Color.gray : Color.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(selectedImage == nil || viewModel.isLoading)
                    .padding(.horizontal)

                    if let limitStatus = viewModel.limitStatusMessage {
                        Text(limitStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }

                    Color.clear.frame(height: 8)
                }
            }
            .navigationTitle("Escáner Inteligente")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(uiColor: .systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 120)
            }
            .simultaneousGesture(TapGesture().onEnded {
                isInstructionFocused = false
            })
            .sheet(isPresented: $isShowingCamera) {
                CameraImagePicker(image: $selectedImage)
            }
            .onChange(of: selectedImage) { _, newImage in
                guard newImage != nil else { return }
                viewModel.clearCurrentAnalysis()
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        isInstructionFocused = false
                        selectedImage = image
                    }
                }
            }
            .confirmationDialog("¿Guardar esta comida?", isPresented: $showSaveConfirmation, titleVisibility: .visible) {
                Button("Guardar") {
                    Task {
                        await viewModel.saveCurrentFoodItems()
                    }
                }
                Button("Cancelar", role: .cancel) {}
            }
            .task {
                viewModel.refreshLimitStatus()
            }
        }
    }

    private func analyzeCurrentImage() {
        isInstructionFocused = false
        guard let image = selectedImage, let imageData = image.jpegData(compressionQuality: 0.85) else { return }
        Task {
            await viewModel.analyze(imageData: imageData, userInstruction: userInstruction)
        }
    }

    @ViewBuilder
    private func iconActionButton(
        icon: String,
        title: String,
        tint: Color,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.20))
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1.0)
    }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraImagePicker

        init(_ parent: CameraImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.image = uiImage
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    let aiClient = NutritionAIClientFactory.makeOpenAI(apiKey: "TEST_KEY", model: .gpt4point1mini)
    CameraAnalysisView(viewModel: FoodPhotoAnalyzerViewModel(aiClient: aiClient))
}

#else

public struct CameraAnalysisView: View {
    public init(viewModel: FoodPhotoAnalyzerViewModel) {
        _ = viewModel
    }

    public var body: some View {
        Text("CameraAnalysisView solo está disponible en iOS")
    }
}

#endif
