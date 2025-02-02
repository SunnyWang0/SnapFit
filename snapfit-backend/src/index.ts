interface BodyFatAnalysis {
	bodyFatPercentage: number;
}

interface Env {
	GEMINI_API_KEY: string;
	PHOTOS_BUCKET: R2Bucket;
	PHOTO_CACHE: KVNamespace;
	THUMBNAIL_WIDTH: string;
	THUMBNAIL_HEIGHT: string;
	THUMBNAIL_QUALITY: string;
	ORIGINAL_QUALITY: string;
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

interface PhotoMetadata {
	userId: string;
	takenAt: string;
	bodyFat?: number;
	weight?: number;
	thumbnailKey: string;
	originalKey: string;
}

const MODEL_NAME = 'gemini-pro-vision';

// Convert image to WebP with specified dimensions
async function processImage(file: Uint8Array, width?: number, height?: number, quality: number = 80): Promise<ArrayBuffer> {
	return fetch('http://api.cloudflare.com/transform', {
		method: 'POST',
		body: file,
		headers: {
			'Content-Type': 'image/webp',
			'Width': width?.toString() || '',
			'Height': height?.toString() || '',
			'Quality': quality.toString(),
		},
	}).then(res => res.arrayBuffer());
}

// Helper to generate storage keys
function generateStorageKey(userId: string, timestamp: string, type: 'original' | 'thumbnail'): string {
	return `users/${userId}/photos/${timestamp}-${type}.webp`;
}

async function handleImageUpload(request: Request, env: Env): Promise<Response> {
	try {
		const formData = await request.formData();
		const imageFile = formData.get('image') as File;
		const userId = formData.get('userId') as string;
		const timestamp = Date.now().toString();
		const height = formData.get('height') as string;
		const weight = formData.get('weight') as string;
		const age = formData.get('age') as string;
		const gender = formData.get('gender') as string;
		const activityLevel = formData.get('activityLevel') as string;
		
		if (!imageFile || !userId) {
			return new Response('Missing required fields', { status: 400 });
		}

		if (!height || !weight || !age || !gender || !activityLevel) {
			return new Response('Missing required user information', { status: 400 });
		}

		// Generate storage keys
		const thumbnailKey = generateStorageKey(userId, timestamp, 'thumbnail');
		const originalKey = generateStorageKey(userId, timestamp, 'original');

		// Convert image to buffer
		const imageBuffer = new Uint8Array(await imageFile.arrayBuffer());

		// Process images for storage
		const [thumbnailBuffer, originalBuffer] = await Promise.all([
			processImage(
				imageBuffer, 
				parseInt(env.THUMBNAIL_WIDTH), 
				parseInt(env.THUMBNAIL_HEIGHT), 
				parseInt(env.THUMBNAIL_QUALITY)
			),
			processImage(
				imageBuffer, 
				undefined, 
				undefined, 
				parseInt(env.ORIGINAL_QUALITY)
			)
		]);

		// Upload both versions to R2
		await Promise.all([
			env.PHOTOS_BUCKET.put(thumbnailKey, thumbnailBuffer, {
				httpMetadata: { contentType: 'image/webp' },
				customMetadata: { cacheControl: 'public, max-age=31536000' }
			}),
			env.PHOTOS_BUCKET.put(originalKey, originalBuffer, {
				httpMetadata: { contentType: 'image/webp' },
				customMetadata: { cacheControl: 'public, max-age=31536000' }
			})
		]);

		// Get image data for Gemini API
		const base64Image = btoa(String.fromCharCode(...new Uint8Array(imageBuffer)));

		// Call Gemini API for body fat analysis
		const response = await fetch(
			`https://generativelanguage.googleapis.com/v1/models/${MODEL_NAME}:generateContent`, 
			{
				method: 'POST',
				headers: {
					'Content-Type': 'application/json',
					'Authorization': `Bearer ${env.GEMINI_API_KEY}`
				},
				body: JSON.stringify({
					contents: [{
						parts: [{
							text: `Given the following user information:
							- Height: ${height}
							- Weight: ${weight}
							- Age: ${age}
							- Gender: ${gender}
							- Activity Level: ${activityLevel}

							Analyze the image and provide the body fat percentage as a decimal number to the nearest tenth. 
							Only return a json object with the body fat percentage, no additional text. 
							The json object should be in the following format: 
							{
								"bodyFatPercentage": <body fat percentage>
							}
							
							- Do not include any other text or commentary in your response
							- Make your best guess, even if the image is not clear or the user is wearing/not wearing clothes.`
						}, {
							inlineData: {
								mimeType: 'image/jpeg',
								data: base64Image
							}
						}]
					}]
				})
			}
		);

		const data = await response.json() as GeminiResponse;
		
		if (!data.candidates?.[0]?.content?.parts?.[0]?.text) {
			throw new Error('Invalid response format from Gemini API');
		}

		const responseText = data.candidates[0].content.parts[0].text;
		const jsonMatch = responseText.match(/\{[\s\S]*\}/);
		
		if (!jsonMatch) {
			throw new Error('Could not find JSON in response');
		}

		const analysis = JSON.parse(jsonMatch[0]) as BodyFatAnalysis;

		// Store metadata in KV
		const metadata: PhotoMetadata = {
			userId,
			takenAt: timestamp,
			bodyFat: analysis.bodyFatPercentage,
			weight: parseFloat(weight),
			thumbnailKey,
			originalKey
		};

		await env.PHOTO_CACHE.put(
			`photo:${userId}:${timestamp}`,
			JSON.stringify(metadata),
			{ expirationTtl: 86400 * 30 }
		);

		return new Response(JSON.stringify({
			success: true,
			bodyFatPercentage: analysis.bodyFatPercentage,
			timestamp,
			thumbnailUrl: `/photos/${userId}/${timestamp}/thumbnail`,
			originalUrl: `/photos/${userId}/${timestamp}/original`
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
