interface Env {
	GEMINI_API_KEY: string;
	PHOTOS_BUCKET: R2Bucket;
}

async function handleImageUpload(request: Request, env: Env): Promise<Response> {
	try {
		const formData = await request.formData();
		const imageFile = formData.get('image') as File;
		const height = formData.get('height');
		const weight = formData.get('weight');
		const age = formData.get('age');
		const gender = formData.get('gender');
		const activityLevel = formData.get('activityLevel');
		
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

		// Call Gemini API
		const response = await fetch('https://generativelanguage.googleapis.com/v1/models/gemini-pro-vision:generateContent', {
			method: 'POST',
			headers: {
				'Content-Type': 'application/json',
				'Authorization': `Bearer ${env.GEMINI_API_KEY}`,
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

						Analyze the image and provide the body fat percentage as a decimal number to the nearest tenth. Only return a 
						json object with the body fat percentage, no additional text. The json object should be in 
						the following format: 
						{
							"bodyFat": <body fat percentage>
						}
						
						- Do not include any other text or commentary in your response
						- Make your best guess, even if the image is not clear or the user is wearing/not wearing clothes.`,
					}, {
						inline_data: {
							mime_type: imageFile.type,
							data: base64Image
						}
					}]
				}]
			})
		});

		const analysisResult = await response.json() as {
			candidates: Array<{
				content: {
					parts: Array<{
						text: string
					}>
				}
			}>
		};
		
		// Extract the body fat percentage from Gemini's response
		const bodyFatPercentage = parseFloat(analysisResult.candidates[0].content.parts[0].text);

		return new Response(JSON.stringify({
			bodyFatPercentage,
			success: true
		}), {
			headers: {
				'Content-Type': 'application/json'
			}
		});

	} catch (error) {
		console.error('Error processing image:', error);
		return new Response(JSON.stringify({
			error: 'Failed to process image',
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
