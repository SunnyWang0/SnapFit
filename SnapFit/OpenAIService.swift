import Foundation

class OpenAIService {
    private let apiKey: String
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func analyzeBodyFat(imageData: Data) async throws -> String {
        let base64Image = imageData.base64EncodedString()
        
        let systemPrompt = """
        You are an expert fitness analyst specializing in visual body composition assessment. When analyzing images for body fat estimation:

        RULES:
        - Provide ONLY a single numerical value as output (e.g. "12.3")
        - Round to nearest 0.1%
        - Do not include explanations or commentary
        - Do not hedge or qualify your estimate
        - The user is aware that this is an estimate and not an exact measurement so do not include any additional

        ASSESSMENT CRITERIA:
        - Primary indicators:
        * Muscle definition visibility
        * Fat distribution patterns
        * Vascularity
        * Anatomical landmark visibility
        * Overall body shape
        * Any other relevant factors
        
        - Secondary factors:
        * Image lighting conditions
        * Subject posture/positioning
        * Image quality/clarity
        * Gender-specific fat distribution patterns
        * Relative muscle mass

        FORMAT:
        - Output must be a single decimal number between 3.0-60.0
        - Include decimal point even for whole numbers (e.g. "15.0")
        - No % symbol or other characters

        Example valid outputs:
        8.5
        15.0
        22.3

        Example invalid outputs:
        "About 15%"
        "15-20%"
        "15% body fat"
        """
        
        let requestBody: [String: Any] = [
            "model": "chatgpt-4o-latest", // or gpt-4o-mini
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": "Please analyze this image and provide the body fat percentage."
                        ],
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