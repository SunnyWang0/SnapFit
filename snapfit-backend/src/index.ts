interface BodyFatAnalysis {
	bodyFatPercentage: number;
}

interface Env {
	GEMINI_API_KEY: string;
	PHOTOS_BUCKET: R2Bucket;
}

interface UserInfo {
	height: string;
	weight: string;
	age: string;
	gender: string;
	activityLevel: string;
}

interface GeminiResponse {
	candidates: Array<{
		content: {
			parts: Array<{
				text: string;
			}>;
		};
	}>;
}

const MODEL_NAME = 'gemini-pro-vision';

async function analyzeBodyImage(
	imageBase64: string,
	userInfo: UserInfo,
	apiKey: string
): Promise<BodyFatAnalysis> {
	const prompt = `Given the following user information:
		- Height: ${userInfo.height}
		- Weight: ${userInfo.weight}
		- Age: ${userInfo.age}
		- Gender: ${userInfo.gender}
		- Activity Level: ${userInfo.activityLevel}

		Analyze the image and provide the body fat percentage as a decimal number to the nearest tenth. 
		Only return a json object with the body fat percentage, no additional text. 
		The json object should be in the following format: 
		{
			"bodyFatPercentage": <body fat percentage>
		}
		
		- Do not include any other text or commentary in your response
		- Make your best guess, even if the image is not clear or the user is wearing/not wearing clothes.`;

	const requestBody = {
		contents: [{
			parts: [
				{ text: prompt },
				{
					inlineData: {
						mimeType: 'image/jpeg',
						data: imageBase64
					}
				}
			]
		}]
	};

	const response = await fetch(
		`https://generativelanguage.googleapis.com/v1/models/${MODEL_NAME}:generateContent`, 
		{
			method: 'POST',
			headers: {
				'Content-Type': 'application/json',
				'Authorization': `Bearer ${apiKey}`
			},
			body: JSON.stringify(requestBody)
		}
	);

	if (!response.ok) {
		throw new Error(`Gemini API error: ${response.statusText}`);
	}

	const data = await response.json() as GeminiResponse;
	
	if (!data.candidates?.[0]?.content?.parts?.[0]?.text) {
		throw new Error('Invalid response format from Gemini API');
	}

	// Extract the JSON string from the response text
	const responseText = data.candidates[0].content.parts[0].text;
	const jsonMatch = responseText.match(/\{[\s\S]*\}/);
	
	if (!jsonMatch) {
		throw new Error('Could not find JSON in response');
	}

	try {
		return JSON.parse(jsonMatch[0]) as BodyFatAnalysis;
	} catch (e) {
		throw new Error('Failed to parse response JSON');
	}
}

async function handleImageUpload(request: Request, env: Env): Promise<Response> {
	try {
		const formData = await request.formData();
		const imageFile = formData.get('image') as File;
		const height = formData.get('height') as string;
		const weight = formData.get('weight') as string;
		const age = formData.get('age') as string;
		const gender = formData.get('gender') as string;
		const activityLevel = formData.get('activityLevel') as string;
		
		if (!imageFile) {
			return new Response('No image provided', { status: 400 });
		}

		if (!height || !weight || !age || !gender || !activityLevel) {
			return new Response('Missing required user information', { status: 400 });
		}

		// Generate a unique filename
		const timestamp = Date.now();
		const filename = `${timestamp}-${Math.random().toString(36).substring(7)}.jpg`;
		
		// Upload to R2
		await env.PHOTOS_BUCKET.put(filename, await imageFile.arrayBuffer(), {
			httpMetadata: {
				contentType: imageFile.type,
			}
		});

		// Get image data for Gemini API
		const imageBuffer = await imageFile.arrayBuffer();
		const base64Image = btoa(String.fromCharCode(...new Uint8Array(imageBuffer)));

		const userInfo: UserInfo = {
			height,
			weight,
			age,
			gender,
			activityLevel
		};

		const analysis = await analyzeBodyImage(base64Image, userInfo, env.GEMINI_API_KEY);
		
		return new Response(JSON.stringify({
			bodyFatPercentage: analysis.bodyFatPercentage,
			success: true
		}), {
			headers: {
				'Content-Type': 'application/json'
			}
		});

	} catch (error) {
		console.error('Error processing image:', error);
		const errorMessage = error instanceof Error ? error.message : 'An unknown error occurred';
		return new Response(JSON.stringify({
			error: errorMessage,
			success: false
		}), {
			status: 500,
			headers: {
				'Content-Type': 'application/json'
			}
		});
	}
}

export default {
	async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
		if (request.method === 'POST') {
			return handleImageUpload(request, env);
		}

		return new Response('Method not allowed', { status: 405 });
	},
} satisfies ExportedHandler<Env>;
