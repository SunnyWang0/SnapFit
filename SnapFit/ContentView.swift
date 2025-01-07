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
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(items: items)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)
            
            CameraView(modelContext: modelContext)
                .tabItem {
                    Label("Camera", systemImage: "camera.fill")
                }
                .tag(1)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(2)
        }
    }
}

struct HomeView: View {
    let items: [Item]
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationStack {
            List {
                // Progress Section
                Section {
                    VStack(spacing: 20) {
                        // Recent photos grid
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 16) {
                            ForEach(items.prefix(4)) { item in
                                if let imageData = item.imageData,
                                   let uiImage = UIImage(data: imageData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 150)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listSectionSpacing(.compact)
                
                // Journal Entries Section
                Section {
                    ForEach(items) { item in
                        NavigationLink {
                            VStack(spacing: 16) {
                                if let imageData = item.imageData,
                                   let uiImage = UIImage(data: imageData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFit()
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
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Journal")
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

struct CameraView: View {
    let modelContext: ModelContext
    @State private var isShowingCamera = false
    @State private var image: UIImage?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            VStack {
                // Camera preview placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.1))
                        .aspectRatio(4/3, contentMode: .fit)
                        .overlay {
                            VStack {
                                Image(systemName: "camera.fill")
                                    .font(.largeTitle)
                                Text("Take a Photo")
                                    .font(.headline)
                            }
                        }
                }
                .padding()
                .onTapGesture {
                    isShowingCamera = true
                }
                
                // Hints
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tips for best results:")
                        .font(.headline)
                    
                    TipRow(icon: "person.fill", text: "Stand 6-8 feet from camera")
                    TipRow(icon: "light.max", text: "Ensure good lighting")
                    TipRow(icon: "camera.filters", text: "Wear form-fitting clothes")
                }
                .padding()
                
                Spacer()
            }
            .navigationTitle("Take Photo")
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
        }
    }
    
    private func addItemWithImage(_ image: UIImage) async {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            errorMessage = "Failed to process image"
            return
        }
        
        await MainActor.run {
            withAnimation {
                let newItem = Item(timestamp: Date(), imageData: imageData, bodyFatAnalysis: nil)
                modelContext.insert(newItem)
            }
        }
    }
}

struct TipRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
            Text(text)
        }
        .foregroundStyle(.secondary)
    }
}

struct SettingsView: View {
    @AppStorage("userHeight") private var userHeight = ""
    @AppStorage("userWeight") private var userWeight = ""
    @AppStorage("userAge") private var userAge = ""
    @AppStorage("userGender") private var userGender = "male"
    @AppStorage("activityLevel") private var activityLevel = "moderate"
    @AppStorage("showCelebrityComparison") private var showCelebrityComparison = true
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Personal Information") {
                    TextField("Height", text: $userHeight)
                        .keyboardType(.decimalPad)
                    TextField("Weight", text: $userWeight)
                        .keyboardType(.decimalPad)
                    TextField("Age", text: $userAge)
                        .keyboardType(.numberPad)
                    Picker("Gender", selection: $userGender) {
                        Text("Male").tag("male")
                        Text("Female").tag("female")
                    }
                }
                
                Section("Activity Level") {
                    Picker("Activity", selection: $activityLevel) {
                        Text("Sedentary").tag("sedentary")
                        Text("Light").tag("light")
                        Text("Moderate").tag("moderate")
                        Text("Active").tag("active")
                        Text("Very Active").tag("very_active")
                    }
                }
                
                Section("Features") {
                    Toggle("Show Celebrity Comparisons", isOn: $showCelebrityComparison)
                }
            }
            .navigationTitle("Settings")
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
