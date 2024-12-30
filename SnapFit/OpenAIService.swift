import Foundation
import CryptoKit

class OpenAIService {
    // This is a simple obfuscation key, not meant for serious security
    private static let salt = "SnapFit2024"
    private static let encryptedKey = "YOUR_ENCRYPTED_API_KEY" // You'll replace this with your encrypted key
    
    private let apiKey: String
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    
    init() {
        // Basic deobfuscation - this is not meant for high security
        // but provides basic protection against casual inspection
        let combined = OpenAIService.salt + OpenAIService.encryptedKey
        let hash = SHA256.hash(data: combined.data(using: .utf8)!)
        self.apiKey = hash.map { String(format: "%02x", $0) }.joined()
    }
    
    func analyzeBodyFat(imageData: Data) async throws -> String {
        let base64Image = imageData.base64EncodedString()
        
        let systemPrompt = """
        You are a fitness expert specialized in body composition analysis. Analyze the provided image and estimate the body fat percentage. \
        Consider visible muscle definition, body shape, and other relevant factors. \
        Provide a concise response with: 
        1. Estimated body fat percentage (range)
        2. Brief explanation of key visual indicators
        Keep the response under 100 words.
        """
        
        let requestBody: [String: Any] = [
            "model": "gpt-4-vision-preview",
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
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