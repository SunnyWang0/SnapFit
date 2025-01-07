import Foundation

class OpenAIService {
    private let apiKey: String
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    enum ImageInput {
        case url(String)
        case base64(Data)
    }
    
    func analyzeBodyFat(image: ImageInput) async throws -> String {
        let systemPrompt = """
        You are a body composition analysis expert. Analyze the image and output ONLY a single decimal number representing body fat percentage.

        OUTPUT RULES:
        - Single decimal number between 3.0-60.0
        - Round to nearest 0.1%
        - Include decimal point (e.g. "15.0")
        - No text, symbols, or explanations

        ANALYSIS CRITERIA:
        - Muscle definition
        - Fat distribution
        - Vascularity
        - Anatomical landmarks
        - Gender-specific patterns
        - Overall physique
        - Image quality factors
        """
        
        let imageContent: [String: Any]
        
        switch image {
        case .url(let urlString):
            imageContent = ["url": urlString]
        case .base64(let imageData):
            imageContent = ["url": "data:image/jpeg;base64,\(imageData.base64EncodedString())"]
        }
        
        let requestBody: [String: Any] = [
            "model": "gpt-4-vision-preview",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": [
                    ["type": "text", "text": "Analyze this image and provide the exact body fat percentage as a decimal number."],
                    ["type": "image_url", "image_url": imageContent]
                ]]
            ],
            "max_tokens": 150
        ]
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "OpenAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "API request failed"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "OpenAI", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        
        return content
    }
} 