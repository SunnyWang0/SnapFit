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
    @State private var isShowingCamera = false
    @State private var image: UIImage?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
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
                            
                            Text("Logged on \(item.timestamp, format: Date.FormatStyle(date: .numeric)) at \(item.timestamp, format: Date.FormatStyle(time: .shortened))")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    } label: {
                        Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .shortened))
                    }
                }
                .onDelete(perform: deleteItems)
            }
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
    }
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
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
    @AppStorage("userHeight") private var userHeight = 170.0 // Default in cm
    @AppStorage("userWeight") private var userWeight = 70.0 // Default in kg
    @AppStorage("userAge") private var userAge = 25.0
    @AppStorage("userGender") private var userGender = "male"
    @AppStorage("activityLevel") private var activityLevel = "moderate"
    @AppStorage("showCelebrityComparison") private var showCelebrityComparison = true
    @AppStorage("heightUnit") private var heightUnit = "cm" // cm or ft
    @AppStorage("weightUnit") private var weightUnit = "kg" // kg or lbs
    
    // Computed properties for unit conversion
    private var displayedHeight: Double {
        heightUnit == "cm" ? userHeight : (userHeight / 2.54) / 12
    }
    
    private var displayedWeight: Double {
        weightUnit == "kg" ? userWeight : userWeight * 2.20462
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Personal Information") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Height")
                            Spacer()
                            Picker("Unit", selection: $heightUnit) {
                                Text("cm").tag("cm")
                                Text("ft").tag("ft")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 100)
                        }
                        
                        HStack {
                            if heightUnit == "cm" {
                                Text("\(Int(displayedHeight)) cm")
                            } else {
                                let feet = Int(displayedHeight)
                                let inches = Int((displayedHeight - Double(feet)) * 12)
                                Text("\(feet)'\(inches)\"")
                            }
                            Spacer()
                        }
                        
                        Slider(
                            value: Binding(
                                get: { displayedHeight },
                                set: { newValue in
                                    if heightUnit == "cm" {
                                        userHeight = newValue
                                    } else {
                                        userHeight = newValue * 12 * 2.54
                                    }
                                }
                            ),
                            in: heightUnit == "cm" ? 120...220 : 4...7.5,
                            step: heightUnit == "cm" ? 1 : 0.1
                        )
                    }
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Weight")
                            Spacer()
                            Picker("Unit", selection: $weightUnit) {
                                Text("kg").tag("kg")
                                Text("lbs").tag("lbs")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 100)
                        }
                        
                        HStack {
                            Text("\(Int(displayedWeight)) \(weightUnit)")
                            Spacer()
                        }
                        
                        Slider(
                            value: Binding(
                                get: { displayedWeight },
                                set: { newValue in
                                    if weightUnit == "kg" {
                                        userWeight = newValue
                                    } else {
                                        userWeight = newValue / 2.20462
                                    }
                                }
                            ),
                            in: weightUnit == "kg" ? 30...200 : 66...440,
                            step: weightUnit == "kg" ? 1 : 1
                        )
                    }
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Age: \(Int(userAge))")
                            Spacer()
                        }
                        Slider(value: $userAge, in: 18...100, step: 1)
                    }
                    
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
