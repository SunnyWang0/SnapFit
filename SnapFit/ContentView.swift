//
//  ContentView.swift
//  SnapFit
//
//  Created by Sunny Wang on 12/25/24.
//

import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    @State private var isShowingCamera = false
    @State private var image: UIImage?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    
    private let openAIService = OpenAIService()
    
    var body: some View {
        NavigationSplitView {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        VStack(spacing: 16) {
                            if let imageData = item.imageData,
                               let uiImage = UIImage(data: imageData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                            }
                            
                            if let analysis = item.bodyFatAnalysis {
                                Text(analysis)
                                    .padding()
                                    .background(Color(.systemBackground))
                                    .cornerRadius(10)
                            }
                            
                            Text("Logged on \(item.timestamp, format: Date.FormatStyle(date: .numeric)) at \(item.timestamp, format: Date.FormatStyle(time: .shortened))")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    } label: {
                        HStack {
                            if let imageData = item.imageData,
                               let uiImage = UIImage(data: imageData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .frame(width: 44, height: 44)
                                    .cornerRadius(8)
                            }
                            
                            VStack(alignment: .leading) {
                                Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .shortened))
                                if let analysis = item.bodyFatAnalysis {
                                    Text(analysis)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
#endif
            .navigationTitle("Journal")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { isShowingCamera = true }) {
                        Label("Add Item", systemImage: "plus")
                    }
                    .disabled(isAnalyzing)
                }
            }
            .sheet(isPresented: $isShowingCamera) {
                ImagePicker(image: $image, sourceType: .camera)
                    .ignoresSafeArea()
                    .onDisappear {
                        if let image = image {
                            Task {
                                await addItemWithImage(image)
                            }
                        }
                    }
            }
            .overlay {
                if isAnalyzing {
                    ProgressView("Analyzing image...")
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                }
            }
        } detail: {
            Text("Select an item")
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
    }
    
    private func addItemWithImage(_ image: UIImage) async {
        isAnalyzing = true
        defer { isAnalyzing = false }
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            errorMessage = "Failed to process image"
            return
        }
        
        do {
            let analysis = try await openAIService.analyzeBodyFat(imageData: imageData)
            
            await MainActor.run {
                withAnimation {
                    let newItem = Item(timestamp: Date(), imageData: imageData, bodyFatAnalysis: analysis)
                    modelContext.insert(newItem)
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to analyze image: \(error.localizedDescription)"
            }
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let sourceType: UIImagePickerController.SourceType

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
