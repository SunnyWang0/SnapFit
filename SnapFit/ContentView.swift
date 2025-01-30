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
    
    @State private var isHeightPickerShown = false
    @State private var isWeightPickerShown = false
    @State private var isAgePickerShown = false
    
    // Temporary values for pickers
    @State private var tempHeight = 170.0
    @State private var tempWeight = 70.0
    @State private var tempAge = 25.0
    
    // Computed properties for unit conversion
    private var displayedHeight: Double {
        if heightUnit == "cm" {
            return userHeight
        } else {
            // Convert cm to feet (including fractional feet)
            return userHeight / 2.54 / 12
        }
    }
    
    private var displayedWeight: Double {
        weightUnit == "kg" ? userWeight : userWeight * 2.20462
    }
    
    private var formattedHeight: String {
        if heightUnit == "cm" {
            return "\(Int(displayedHeight)) cm"
        } else {
            let totalInches = (userHeight / 2.54)
            let feet = Int(totalInches / 12)
            let inches = Int(round(totalInches.truncatingRemainder(dividingBy: 12)))
            // Handle case where inches == 12
            if inches == 12 {
                return "\(feet + 1)'0\""
            }
            return "\(feet)'\(inches)\""
        }
    }
    
    private var formattedWeight: String {
        "\(Int(displayedWeight)) \(weightUnit)"
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Personal Information") {
                    // Height
                    HStack {
                        Button(action: { isHeightPickerShown = true }) {
                            HStack {
                                Text("Height")
                                Spacer()
                                Text(formattedHeight)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .foregroundColor(.primary)
                    }
                    .sheet(isPresented: $isHeightPickerShown) {
                        NavigationStack {
                            HStack {
                                if heightUnit == "cm" {
                                    Picker("Height", selection: $tempHeight) {
                                        ForEach(60...220, id: \.self) { cm in
                                            Text("\(cm)").tag(Double(cm))
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                    Text("cm")
                                        .foregroundColor(.secondary)
                                } else {
                                    Picker("Feet", selection: $tempHeight) {
                                        ForEach(2...7, id: \.self) { feet in
                                            ForEach(0...11, id: \.self) { inches in
                                                Text("\(feet)'\(inches)\"")
                                                    .tag(Double(feet) + Double(inches) / 12.0)
                                            }
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                }
                                
                                Picker("Unit", selection: $heightUnit) {
                                    Text("cm").tag("cm")
                                    Text("ft").tag("ft")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 100)
                            }
                            .padding()
                            .navigationTitle("Height")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Cancel") {
                                        isHeightPickerShown = false
                                    }
                                }
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") {
                                        if heightUnit == "cm" {
                                            userHeight = tempHeight
                                        } else {
                                            // Convert feet to cm more accurately
                                            let feet = Int(tempHeight)
                                            let fractionalFeet = tempHeight - Double(feet)
                                            let inches = fractionalFeet * 12
                                            let totalInches = Double(feet * 12) + inches
                                            userHeight = totalInches * 2.54
                                        }
                                        isHeightPickerShown = false
                                    }
                                }
                            }
                            .onAppear {
                                tempHeight = displayedHeight
                            }
                        }
                        .presentationDetents([.height(300)])
                    }
                    
                    // Weight
                    HStack {
                        Button(action: { isWeightPickerShown = true }) {
                            HStack {
                                Text("Weight")
                                Spacer()
                                Text(formattedWeight)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .foregroundColor(.primary)
                    }
                    .sheet(isPresented: $isWeightPickerShown) {
                        NavigationStack {
                            HStack {
                                if weightUnit == "kg" {
                                    Picker("Weight", selection: $tempWeight) {
                                        ForEach(30...200, id: \.self) { kg in
                                            Text("\(kg)").tag(Double(kg))
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                    Text("kg")
                                        .foregroundColor(.secondary)
                                } else {
                                    Picker("Weight", selection: $tempWeight) {
                                        ForEach(66...440, id: \.self) { lbs in
                                            Text("\(lbs)").tag(Double(lbs))
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                    Text("lbs")
                                        .foregroundColor(.secondary)
                                }
                                
                                Picker("Unit", selection: $weightUnit) {
                                    Text("kg").tag("kg")
                                    Text("lbs").tag("lbs")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 100)
                            }
                            .padding()
                            .navigationTitle("Weight")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Cancel") {
                                        isWeightPickerShown = false
                                    }
                                }
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") {
                                        if weightUnit == "kg" {
                                            userWeight = tempWeight
                                        } else {
                                            userWeight = tempWeight / 2.20462
                                        }
                                        isWeightPickerShown = false
                                    }
                                }
                            }
                            .onAppear {
                                tempWeight = displayedWeight
                            }
                        }
                        .presentationDetents([.height(300)])
                    }
                    
                    // Age
                    HStack {
                        Button(action: { isAgePickerShown = true }) {
                            HStack {
                                Text("Age")
                                Spacer()
                                Text("\(Int(userAge))")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .foregroundColor(.primary)
                    }
                    .sheet(isPresented: $isAgePickerShown) {
                        NavigationStack {
                            Picker("Age", selection: $tempAge) {
                                ForEach(18...100, id: \.self) { age in
                                    Text("\(age)").tag(Double(age))
                                }
                            }
                            .pickerStyle(.wheel)
                            .navigationTitle("Age")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Cancel") {
                                        isAgePickerShown = false
                                    }
                                }
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") {
                                        userAge = tempAge
                                        isAgePickerShown = false
                                    }
                                }
                            }
                            .onAppear {
                                tempAge = userAge
                            }
                        }
                        .presentationDetents([.height(300)])
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
