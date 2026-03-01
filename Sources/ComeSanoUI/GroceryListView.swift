import SwiftUI
import ComeSanoCore

@MainActor
public final class GroceryListViewModel: ObservableObject {
    @Published public private(set) var items: [ShoppingListItem] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?

    private let shoppingStore: ShoppingListStore

    public init(shoppingStore: ShoppingListStore) {
        self.shoppingStore = shoppingStore
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let stored = try await shoppingStore.fetchShoppingItems()
            items = stored.sorted {
                if $0.isPurchased != $1.isPurchased {
                    return !$0.isPurchased && $1.isPurchased
                }
                if $0.category != $1.category {
                    return $0.category.localizedCaseInsensitiveCompare($1.category) == .orderedAscending
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            errorMessage = nil
        } catch {
            errorMessage = "No se pudo cargar la lista del súper: \(error.localizedDescription)"
        }
    }

    public func addItem(name: String, category: String = "Otros") async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        var next = items
        next.append(
            ShoppingListItem(
                name: trimmedName,
                category: category,
                quantity: 1,
                unit: "pieza",
                isPurchased: false
            )
        )
        await saveAndApply(next)
    }

    public func togglePurchased(item: ShoppingListItem) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var next = items
        next[index].isPurchased.toggle()
        await saveAndApply(next)
    }

    public func delete(item: ShoppingListItem) async {
        let next = items.filter { $0.id != item.id }
        await saveAndApply(next)
    }

    public func pendingCount() -> Int {
        items.filter { !$0.isPurchased }.count
    }

    public func groupedByCategory() -> [(category: String, items: [ShoppingListItem])] {
        let grouped = Dictionary(grouping: items, by: \.category)
        return grouped.keys.sorted().map { key in
            let categoryItems = grouped[key] ?? []
            return (category: key, items: categoryItems)
        }
    }

    private func saveAndApply(_ nextItems: [ShoppingListItem]) async {
        do {
            try await shoppingStore.save(shoppingItems: nextItems)
            items = nextItems
            errorMessage = nil
            await refresh()
        } catch {
            errorMessage = "No se pudo guardar la lista del súper: \(error.localizedDescription)"
        }
    }
}

public struct GroceryListView: View {
    @StateObject private var viewModel: GroceryListViewModel
    @State private var newItemName = ""
    @State private var selectedCategory = "Otros"
    private let onScanTap: () -> Void

    private let manualCategories = ["Proteínas", "Vegetales", "Frutas", "Lácteos", "Cereales", "Otros"]

    public init(viewModel: GroceryListViewModel, onScanTap: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onScanTap = onScanTap
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: onScanTap) {
                        Label("Escanear refri para autocompletar", systemImage: "sparkles")
                            .font(.headline)
                            .foregroundStyle(.purple)
                    }
                }

                Section("Agregar manualmente") {
                    HStack(spacing: 12) {
                        TextField("Agregar producto...", text: $newItemName)

                        Menu {
                            Picker("Categoría", selection: $selectedCategory) {
                                ForEach(manualCategories, id: \.self) { category in
                                    Text(category).tag(category)
                                }
                            }
                        } label: {
                            Text(selectedCategory)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            Task {
                                await viewModel.addItem(name: newItemName, category: selectedCategory)
                                newItemName = ""
                                selectedCategory = "Otros"
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        .disabled(newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if viewModel.items.isEmpty, !viewModel.isLoading {
                    Section {
                        ContentUnavailableView(
                            "Sin productos",
                            systemImage: "cart",
                            description: Text("Analiza una foto o agrega productos manualmente.")
                        )
                    }
                } else {
                    ForEach(viewModel.groupedByCategory(), id: \.category) { group in
                        Section(group.category) {
                            ForEach(group.items) { item in
                                HStack(spacing: 12) {
                                    Button {
                                        Task { await viewModel.togglePurchased(item: item) }
                                    } label: {
                                        Image(systemName: item.isPurchased ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(item.isPurchased ? .green : .gray)
                                            .font(.title3)
                                    }
                                    .buttonStyle(.plain)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.name)
                                            .strikethrough(item.isPurchased, color: .gray)
                                            .foregroundStyle(item.isPurchased ? .secondary : .primary)
                                        Text("\(item.quantity.formatted()) \(item.unit)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        Task { await viewModel.delete(item: item) }
                                    } label: {
                                        Label("Eliminar", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.automatic)
            #endif
            .navigationTitle("Lista del Súper")
            .toolbar {
                ToolbarItem(placement: pendingToolbarPlacement) {
                    Text("\(viewModel.pendingCount()) pendientes")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .safeAreaInset(edge: .top) {
                Text("Tip: marca con check lo que ya tienes en casa/refri o ya compraste.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
            }
            .task { await viewModel.refresh() }
            .refreshable { await viewModel.refresh() }
            .alert("Error", isPresented: Binding(get: {
                viewModel.errorMessage != nil
            }, set: { _ in
                Task { await viewModel.refresh() }
            })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}

private extension ToolbarItemPlacement {
    static var pendingCountPlacement: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarTrailing
        #else
        return .primaryAction
        #endif
    }
}

private extension GroceryListView {
    var pendingToolbarPlacement: ToolbarItemPlacement {
        .pendingCountPlacement
    }
}

#Preview {
    GroceryListView(
        viewModel: GroceryListViewModel(shoppingStore: PreviewShoppingStore())
    )
}

private actor PreviewShoppingStore: ShoppingListStore {
    private var data: [ShoppingListItem] = [
        ShoppingListItem(name: "Pechuga de pollo", category: "Proteínas", quantity: 1, unit: "kg"),
        ShoppingListItem(name: "Huevos", category: "Proteínas", quantity: 12, unit: "pzas", isPurchased: true),
        ShoppingListItem(name: "Brócoli", category: "Vegetales", quantity: 2, unit: "pzas")
    ]

    func save(shoppingItems: [ShoppingListItem]) async throws {
        data = shoppingItems
    }

    func fetchShoppingItems() async throws -> [ShoppingListItem] {
        data
    }
}
