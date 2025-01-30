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
    @AppStorage("userBirthday") private var userBirthday = Date() // Default to current date
    @AppStorage("userGender") private var userGender = "male"
    @AppStorage("activityLevel") private var activityLevel = "moderate"
    @AppStorage("showCelebrityComparison") private var showCelebrityComparison = true
    @AppStorage("heightUnit") private var heightUnit = "cm" // cm or ft
    @AppStorage("weightUnit") private var weightUnit = "kg" // kg or lbs
    
    @State private var isHeightPickerShown = false
    @State private var isWeightPickerShown = false
    @State private var isBirthdayPickerShown = false
    
    // Temporary values for pickers
    @State private var tempHeight = 170.0
    @State private var tempWeight = 70.0
    @State private var tempMonth = Calendar.current.component(.month, from: Date())
    @State private var tempDay = Calendar.current.component(.day, from: Date())
    @State private var tempYear = Calendar.current.component(.year, from: Date())
    @State private var previousHeightUnit = "cm"
    
    private let months = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]
    
    private let calendar = Calendar.current
    
    private var age: Int {
        calendar.dateComponents([.year], from: userBirthday, to: Date()).year ?? 0
    }
    
    // Computed properties for unit conversion
    private var displayedHeight: Double {
        heightUnit == "cm" ? userHeight : (userHeight / 2.54) / 12
    }
    
    private var displayedWeight: Double {
        weightUnit == "kg" ? userWeight : userWeight * 2.20462
    }
    
    private var formattedHeight: String {
        if heightUnit == "cm" {
            return "\(Int(displayedHeight)) cm"
        } else {
            let feet = Int(displayedHeight)
            let inches = Int((displayedHeight - Double(feet)) * 12)
            return "\(feet)'\(inches)\""
        }
    }
    
    private var formattedWeight: String {
        "\(Int(displayedWeight)) \(weightUnit)"
    }
    
    private func convertHeight() {
        if previousHeightUnit != heightUnit {
            if heightUnit == "cm" {
                // Convert from feet to cm
                tempHeight = tempHeight * 12 * 2.54
            } else {
                // Convert from cm to feet
                tempHeight = tempHeight / 2.54 / 12
            }
            previousHeightUnit = heightUnit
        }
    }
    
    private func daysInMonth(month: Int, year: Int) -> Int {
        let dateComponents = DateComponents(year: year, month: month)
        guard let date = calendar.date(from: dateComponents),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return 31
        }
        return range.count
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Personal Information") {
                    // Height
                    HStack {
                        Button(action: { 
                            tempHeight = displayedHeight
                            previousHeightUnit = heightUnit
                            isHeightPickerShown = true 
                        }) {
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
                                .onChange(of: heightUnit) { _, _ in
                                    convertHeight()
                                }
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
                                            userHeight = tempHeight * 12 * 2.54
                                        }
                                        isHeightPickerShown = false
                                    }
                                }
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
                    
                    // Birthday
                    HStack {
                        Button(action: {
                            let components = calendar.dateComponents([.month, .day, .year], from: userBirthday)
                            tempMonth = components.month ?? 1
                            tempDay = components.day ?? 1
                            tempYear = components.year ?? calendar.component(.year, from: Date())
                            isBirthdayPickerShown = true
                        }) {
                            HStack {
                                Text("Date of Birth")
                                Spacer()
                                Text("\(age) years")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .foregroundColor(.primary)
                    }
                    .sheet(isPresented: $isBirthdayPickerShown) {
                        NavigationStack {
                            HStack(spacing: 0) {
                                // Month Picker
                                Picker("Month", selection: $tempMonth) {
                                    ForEach(1...12, id: \.self) { month in
                                        Text(months[month - 1]).tag(month)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(maxWidth: .infinity)
                                
                                // Day Picker
                                Picker("Day", selection: $tempDay) {
                                    ForEach(1...daysInMonth(month: tempMonth, year: tempYear), id: \.self) { day in
                                        Text("\(day)").tag(day)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(maxWidth: .infinity)
                                
                                // Year Picker
                                Picker("Year", selection: $tempYear) {
                                    ForEach((1900...calendar.component(.year, from: Date())).reversed(), id: \.self) { year in
                                        Text("\(year)").tag(year)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(maxWidth: .infinity)
                            }
                            .padding()
                            .navigationTitle("Date of Birth")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Cancel") {
                                        isBirthdayPickerShown = false
                                    }
                                }
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") {
                                        var dateComponents = DateComponents()
                                        dateComponents.year = tempYear
                                        dateComponents.month = tempMonth
                                        dateComponents.day = min(tempDay, daysInMonth(month: tempMonth, year: tempYear))
                                        
                                        if let date = calendar.date(from: dateComponents) {
                                            userBirthday = date
                                        }
                                        isBirthdayPickerShown = false
                                    }
                                }
                            }
                            .onChange(of: tempMonth) { _, _ in
                                let maxDays = daysInMonth(month: tempMonth, year: tempYear)
                                if tempDay > maxDays {
                                    tempDay = maxDays
                                }
                            }
                            .onChange(of: tempYear) { _, _ in
                                let maxDays = daysInMonth(month: tempMonth, year: tempYear)
                                if tempDay > maxDays {
                                    tempDay = maxDays
                                }
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
